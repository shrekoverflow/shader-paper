// XPC protocol and reflection approach adapted from Phosphene (MIT).
import AppKit

func findProperty(_ label: String, in value: Any, depth: Int = 0) -> Any? {
    guard depth < 9 else { return nil }
    for child in Mirror(reflecting: value).children {
        if child.label == label { return child.value }
        if let found = findProperty(label, in: child.value, depth: depth + 1) { return found }
    }
    return nil
}
func wallpaperUUID(_ value: Any?, depth: Int = 0) -> UUID? {
    guard let value, depth < 8 else { return nil }
    if let uuid = value as? UUID { return uuid }
    for child in Mirror(reflecting: value).children {
        if let id = wallpaperUUID(child.value, depth: depth + 1) { return id }
    }
    return nil
}
func caseName(_ value: Any?) -> String? {
    guard let value else { return nil }
    return Mirror(reflecting: value).children.first?.label ?? String(describing: value)
}

final class WallpaperXPCHandler: NSObject, WallpaperExtensionXPCProtocol {
    var agentProxy: WallpaperExtensionProxyXPCProtocol?
    private var preview = false
    private var lastID: UUID?

    func acquire(withId id: Any?, request: Any?, reply: @escaping (Any?, Error?) -> Void) {
        DispatchQueue.main.async {
            do {
                guard let id = wallpaperUUID(id), let request else { throw failure("Missing wallpaper request") }
                let destination = findProperty("destination", in: request)
                let size = destination.flatMap { findProperty("size", in: $0) as? CGSize } ?? CGSize(width: 1920, height: 1080)
                let scale = destination.flatMap { findProperty("scaleFactor", in: $0) as? CGFloat } ?? 1
                let display = destination.flatMap { findProperty("directDisplayID", in: $0) as? UInt32 }
                self.preview = (findProperty("isPreview", in: request) as? Bool) ?? false
                self.lastID = id
                let data = findProperty("configuration", in: request) as? Data
                let name = data.flatMap { String(data: $0, encoding: .utf8) } ?? ShaderLibrary.defaultShader
                reply(try Engine.shared.acquire(id: id, name: name, size: size, scale: scale, display: display, preview: self.preview), nil)
            } catch { extensionLog("Acquire failed: \(error.localizedDescription)"); reply(nil, error) }
        }
    }
    func update(withId id: Any?, request: Any?, reply: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            let isPreview = wallpaperUUID(id).flatMap { Engine.shared.surfaces[$0]?.preview } ?? self.preview
            if !isPreview, let request {
                Engine.shared.update(mode: caseName(findProperty("presentationMode", in: request)) ?? "default",
                                     activity: caseName(findProperty("activityState", in: request)) ?? "active")
            }
            reply(nil)
        }
    }
    func invalidate(withId id: Any?, reply: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { if let uuid = wallpaperUUID(id) { Engine.shared.invalidate(uuid) }; reply(nil) }
    }
    func snapshot(withId id: Any?, reply: @escaping (Any?, Error?) -> Void) {
        DispatchQueue.main.async { reply(Engine.shared.snapshot(wallpaperUUID(id) ?? self.lastID), nil) }
    }
    func provideSettingsViewModels(withContentTypes _: Any?, reply: @escaping (Any?, Error?) -> Void) {
        DispatchQueue.main.async {
            let models = buildSettingsViewModelsXPC()
            extensionLog("Providing \(ShaderLibrary.entries.count) shader choices; models=\(models != nil)")
            reply(models, nil)
        }
    }
    func addChoiceRequest(withChoiceRequest _: Any?, onBehalfOfProcess _: Any?, reply: @escaping (Any?, Error?) -> Void) { reply(nil, nil) }
    func removeChoiceRequest(withChoiceRequest _: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func selectedChoicesDidChange(for _: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func invokeContextMenuAction(withMenuItemID _: Any?, groupItemID _: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func isChoiceDownloaded(with _: Any?, reply: @escaping (Bool, Error?) -> Void) { reply(true, nil) }
    func download(withChoiceID _: Any?, reply: (Error?) -> Void) -> Any? { reply(nil); return nil }
    func pauseDownload(for _: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func cancelDownload(for _: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func resumeDownload(for _: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func removeDownload(for _: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func migrateSelectedChoice(for _: Any?, reply: @escaping (Any?, Error?) -> Void) { reply(nil, nil) }
    func migrate(from _: Any?, to _: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func skipShuffledContent(withId _: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
    func canSkipShuffledContent(withId _: Any?, reply: @escaping (Bool, Error?) -> Void) { reply(false, nil) }
    func handleDebugRequest(for _: Any?, reply: @escaping (Any?, Error?) -> Void) { reply(nil, nil) }
    func handleNotification(withNamed _: Any?, reply: @escaping (Error?) -> Void) { reply(nil) }
}
