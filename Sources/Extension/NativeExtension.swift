import AppKit
import ExtensionFoundation
import os

private let logger = Logger(subsystem: ShaderLibrary.provider, category: "wallpaper")
func extensionLog(_ message: String) { logger.notice("\(message, privacy: .public)") }
func traceLog(_ message: String) { logger.debug("\(message, privacy: .public)") }

@main final class MeditationExtension: NSObject, AppExtension {
    override required init() {
        super.init()
        guard dlopen("/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit", RTLD_LAZY) != nil else {
            extensionLog("WallpaperExtensionKit is unavailable"); return
        }
        extensionLog("Started native shader extension; \(ShaderLibrary.entries.count) shaders")
        DispatchQueue.main.async { Engine.shared.observeEnvironment() }
    }
    var configuration: some AppExtensionConfiguration { MeditationExtensionConfig() }
}

/// Called only on the main queue, including XPC operations and render timers.
final class Engine {
    static let shared = Engine()
    struct Surface {
        var context: CAContext
        var root: CALayer
        var renderer: ShaderRenderer
        var preview: Bool
        var generation: UUID
        var valid: Bool
    }
    var surfaces: [UUID: Surface] = [:]
    private var clocks: [String: MotionClock] = [:]
    private var mode = "default"
    private var activity = "active"
    private var sleeping = false
    private var lastCheckpoint = CACurrentMediaTime()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func clock(for shader: String) -> MotionClock {
        if let clock = clocks[shader] { return clock }
        let clock = MotionClock(saved: UserDefaults.standard.double(forKey: "time.\(shader)"))
        clocks[shader] = clock
        return clock
    }
    func checkpoint() {
        for (id, clock) in clocks { UserDefaults.standard.set(clock.value, forKey: "time.\(id)") }
        lastCheckpoint = CACurrentMediaTime()
    }
    func observeEnvironment() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sleeping = asleep; self?.applyPolicy()
            }
            observers.append((workspace, token))
        }
        let token = workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.applyPolicy() }
        observers.append((workspace, token))
        let system = NotificationCenter.default
        for name in [Notification.Name.NSSystemTimeZoneDidChange, Notification.Name.NSSystemClockDidChange] {
            let token = system.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                for surface in self.surfaces.values {
                    surface.renderer.refreshDaylight()
                }
            }
            observers.append((system, token))
        }
    }
    func update(mode: String, activity: String) {
        self.mode = mode; self.activity = activity
        extensionLog("Lifecycle mode=\(mode), activity=\(activity)")
        applyPolicy()
    }
    func applyPolicy() {
        let hardPause = sleeping || activity != "active" || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let moving = !hardPause && (mode == "locked" || mode == "idle" || mode == "screenSaver")
        let visible = Set(surfaces.values.filter { !$0.preview && $0.valid }.map { $0.renderer.entry.id })
        for (id, clock) in clocks { clock.setMoving(moving && visible.contains(id), immediately: hardPause || !visible.contains(id)) }
        for surface in surfaces.values {
            let daylightVisible = !surface.preview && surface.valid && !sleeping && activity == "active"
            surface.renderer.setDaylightUpdatesEnabled(daylightVisible)
            guard !surface.preview && surface.valid else { continue }
            if hardPause {
                surface.renderer.stop()
                // Reduce Motion needs a sharp held frame. Sleep and inactive
                // surfaces defer that work until they become visible again.
                if daylightVisible { surface.renderer.restoreNativeFrame() }
            }
            else if !surface.renderer.clock.settled { surface.renderer.start() }
            else { surface.renderer.restoreNativeFrame() }
        }
        if !moving { checkpoint() }
    }
    func acquire(id: UUID, name: String, size: CGSize, scale: CGFloat, display: UInt32?, preview: Bool) throws -> AnyObject {
        let entry = ShaderLibrary.entry(name) ?? ShaderLibrary.entry(ShaderLibrary.defaultShader)
        guard let entry else { throw failure("No bundled shaders") }
        if var existing = surfaces[id], existing.renderer.entry.id == entry.id,
           existing.root.bounds.size == size, existing.root.contentsScale == scale {
            existing.generation = UUID(); existing.valid = true; surfaces[id] = existing
            if !preview { applyPolicy() }
            guard let result = createRemoteContextXPC(contextId: existing.context.contextId) else { throw failure("Could not return wallpaper surface") }
            return result
        }
        let existing = surfaces[id]
        existing?.renderer.stop()
        existing?.renderer.setDaylightUpdatesEnabled(false)
        let context: CAContext
        if let old = existing { context = old.context }
        else {
            let options: [String: Any] = display.map { ["displayId": $0] } ?? [:]
            guard let remote = CAContext.remoteContext(withOptions: options) as? CAContext, remote.contextId != 0 else { throw failure("Could not create wallpaper surface") }
            context = remote
        }
        let root = existing?.root ?? CALayer()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit(); CATransaction.flush() }
        root.frame = CGRect(origin: .zero, size: size); root.contentsScale = scale
        root.isOpaque = true
        if existing == nil { context.layer = root }
        let clock = preview ? MotionClock(saved: self.clock(for: entry.id).value) : self.clock(for: entry.id)
        let renderer = try ShaderRenderer(entry: entry, clock: clock, root: root, scale: scale)
        existing?.renderer.layer.removeFromSuperlayer()
        renderer.onSettled = { [weak self, weak renderer] in
            self?.checkpoint()
            if let renderer { extensionLog("Settled \(entry.id) at \(renderer.clock.value); timer stopped after \(renderer.frameCount) frames") }
        }
        renderer.onFrame = { [weak self] in
            guard let self, CACurrentMediaTime() - self.lastCheckpoint > 30 else { return }
            self.checkpoint()
        }
        renderer.onError = { error in extensionLog("Rendering \(entry.id) failed: \(error.localizedDescription)") }
        surfaces[id] = Surface(context: context, root: root, renderer: renderer, preview: preview, generation: UUID(), valid: true)
        if preview { clock.setMoving(false, immediately: true) }
        else { applyPolicy() }
        guard let result = createRemoteContextXPC(contextId: context.contextId) else { throw failure("Could not return wallpaper surface") }
        extensionLog("Acquired \(entry.id), surface=\(id), preview=\(preview), context=\(context.contextId)")
        return result
    }
    func invalidate(_ id: UUID) {
        guard let surface = surfaces[id] else { return }
        surfaces[id]?.valid = false
        surface.renderer.stop()
        surface.renderer.setDaylightUpdatesEnabled(false)
        if !surfaces.values.contains(where: { !$0.preview && $0.renderer.isRendering && $0.renderer.entry.id == surface.renderer.entry.id }) {
            surface.renderer.clock.setMoving(false, immediately: true)
        }
        checkpoint()
        let generation = surface.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, let stale = self.surfaces[id], stale.generation == generation else { return }
            stale.context.perform(NSSelectorFromString("invalidate"))
            self.surfaces.removeValue(forKey: id)
            if !self.surfaces.values.contains(where: { !$0.preview && $0.renderer.isRendering }) {
                self.clocks.values.forEach { $0.setMoving(false, immediately: true) }
                self.checkpoint()
            }
            extensionLog("Released surface \(id)")
        }
    }
    func snapshot(_ id: UUID?) -> AnyObject? {
        guard let renderer = id.flatMap({ surfaces[$0]?.renderer }) ?? surfaces.values.first?.renderer,
              let pixel = renderer.lastFrame, let surface = CVPixelBufferGetIOSurface(pixel)?.takeUnretainedValue() else { return nil }
        return createSnapshotXPC(surface: surface)
    }
}
