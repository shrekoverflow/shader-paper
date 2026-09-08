import AppKit
import Metal
import CoreVideo
import AVFoundation
import IOSurface

enum LocalDaylight {
    /// Civil time follows the Mac's time zone and daylight-saving changes.
    /// This is an artistic day cycle, not a calculation of local sunrise.
    static func hour(at date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Float {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return normalized(Float(Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
            + (Double(parts.second ?? 0) + Double(parts.nanosecond ?? 0) / 1_000_000_000) / 3600))
    }

    static func normalized(_ hour: Float) -> Float {
        guard hour.isFinite else { return 12 }
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        return wrapped < 0 ? wrapped + 24 : wrapped
    }
}

/// Adapts every DriftView shader without inspecting or rewriting its source:
/// vertex_main / fragment_main, fullscreen triangle, Float time at buffer(0).
/// Time-aware artwork can also read a Float local hour at fragment buffer(1).
/// The half-float artwork is converted into an IOSurface-backed display frame
/// that remains valid in WallpaperAgent after the renderer's timer stops.
final class ShaderKernel {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let usesLocalTime: Bool
    private let artPipeline: MTLRenderPipelineState
    private let displayPipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache!
    private var pool: CVPixelBufferPool!
    private var art: MTLTexture!
    private var dimensions = CGSize.zero

    init(source: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw failure("Metal is unavailable")
        }
        self.device = device; self.queue = queue
        let library = try device.makeLibrary(source: String(contentsOf: source, encoding: .utf8), options: nil)
        func pipeline(_ lib: MTLLibrary, _ vertex: String, _ fragment: String, _ pixel: MTLPixelFormat,
                      reflection: inout MTLRenderPipelineReflection?) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: vertex)
            d.fragmentFunction = lib.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = pixel
            return try device.makeRenderPipelineState(descriptor: d, options: .bindingInfo, reflection: &reflection)
        }
        var artReflection: MTLRenderPipelineReflection?
        artPipeline = try pipeline(library, "vertex_main", "fragment_main", .rgba16Float, reflection: &artReflection)
        usesLocalTime = artReflection?.fragmentBindings.contains { $0.type == .buffer && $0.index == 1 && $0.isUsed } ?? false
        let conversion = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 position [[position]]; };
        vertex V display_vertex(uint id [[vertex_id]]) {
            float2 uv = float2(float((id << 1u) & 2u), float(id & 2u));
            return {float4(uv * 2.0 - 1.0, 0, 1)};
        }
        fragment float4 display_fragment(V in [[stage_in]], texture2d<float> art [[texture(0)]]) {
            float3 c = max(art.read(uint2(in.position.xy)).rgb, 0.0);
            // Preserve SDR values; compress only overbright highlights. The
            // desktop surface is SDR, whereas DriftView also offers EDR output.
            c /= max(1.0, max(c.r, max(c.g, c.b)));
            return float4(c, 1);
        }
        """, options: nil)
        var displayReflection: MTLRenderPipelineReflection?
        displayPipeline = try pipeline(conversion, "display_vertex", "display_fragment", .bgra8Unorm_srgb, reflection: &displayReflection)
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess else {
            throw failure("Could not create a shared display surface")
        }
    }

    func frame(time: Double, size: CGSize, localHour: Float = 12) throws -> CVPixelBuffer {
        let w = max(2, Int(size.width)), h = max(2, Int(size.height))
        if dimensions != CGSize(width: w, height: h) {
            dimensions = CGSize(width: w, height: h)
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
            art = device.makeTexture(descriptor: d)
            guard art != nil else { throw failure("Could not allocate shader surface") }
            let attributes: [String: Any] = [kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
            guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess else {
                throw failure("Could not allocate display frames")
            }
        }
        var pixel: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else {
            throw failure("Could not obtain a display frame")
        }
        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixel, nil, .bgra8Unorm_srgb, w, h, 0, &cvTexture) == kCVReturnSuccess,
              let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture), let command = queue.makeCommandBuffer() else {
            throw failure("Could not bind the display frame")
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = art
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw failure("Could not encode shader") }
        var t = Float(time)
        var hour = LocalDaylight.normalized(localHour)
        encoder.setRenderPipelineState(artPipeline)
        encoder.setFragmentBytes(&t, length: 4, index: 0)
        encoder.setFragmentBytes(&hour, length: 4, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        pass.colorAttachments[0].texture = texture
        guard let finish = command.makeRenderCommandEncoder(descriptor: pass) else { throw failure("Could not finish frame") }
        finish.setRenderPipelineState(displayPipeline)
        finish.setFragmentTexture(art, index: 0)
        finish.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        finish.endEncoding()
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        CVBufferSetAttachment(pixel, kCVImageBufferCGColorSpaceKey, CGColorSpace(name: CGColorSpace.sRGB)!, .shouldPropagate)
        return pixel
    }
}

final class ShaderRenderer {
    let entry: ShaderEntry
    let clock: MotionClock
    let layer = AVSampleBufferDisplayLayer()
    private let kernel: ShaderKernel
    private var timer: DispatchSourceTimer?
    private var daylightTimer: DispatchSourceTimer?
    private let daylightHour: () -> Float
    private(set) var lastFrame: CVPixelBuffer?
    private(set) var frameCount = 0
    var onSettled: (() -> Void)?
    var onFrame: (() -> Void)?
    var onError: ((Error) -> Void)?
    var pixelSize: CGSize

    init(entry: ShaderEntry, clock: MotionClock, root: CALayer, scale: CGFloat,
         daylightHour: @escaping () -> Float = { LocalDaylight.hour() }) throws {
        self.entry = entry; self.clock = clock
        self.daylightHour = daylightHour
        // Each destination owns its pool; differently sized Spaces and picker
        // previews must not continually replace one another's render textures.
        kernel = try ShaderKernel(source: entry.sourceURL)
        let factor = min(scale, 2560 / max(1, max(root.bounds.width, root.bounds.height)))
        pixelSize = CGSize(width: max(2, (root.bounds.width * factor).rounded()), height: max(2, (root.bounds.height * factor).rounded()))
        layer.frame = root.bounds
        layer.contentsScale = scale
        layer.videoGravity = .resizeAspectFill
        layer.isOpaque = true
        root.addSublayer(layer)
        try draw()
    }
    func draw() throws {
        let pixel = try kernel.frame(time: clock.value, size: pixelSize, localHour: daylightHour())
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel, formatDescriptionOut: &format) == noErr,
              let format else { throw failure("Could not describe display frame") }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel, formatDescription: format,
                  sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { throw failure("Could not present frame") }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)! as NSArray
        (attachments[0] as! NSMutableDictionary)[kCMSampleAttachmentKey_DisplayImmediately] = true
        if layer.sampleBufferRenderer.status == .failed { layer.flush() }
        layer.enqueue(sample)
        lastFrame = pixel
        frameCount += 1
        CATransaction.flush()
    }
    func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        let fps = ProcessInfo.processInfo.isLowPowerModeEnabled ? 15 : 30
        source.schedule(deadline: .now(), repeating: 1.0 / Double(fps), leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in
            guard let self, self.isRendering else { return }
            do { try self.draw(); self.onFrame?() }
            catch { self.stop(); self.setDaylightUpdatesEnabled(false); self.onError?(error); return }
            if self.clock.settled { self.stop(); self.onSettled?() }
        }
        timer = source; source.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
    var isRendering: Bool { timer != nil }
    var isUpdatingDaylight: Bool { daylightTimer != nil }

    /// A single environmental refresh per minute keeps the sky current while
    /// motion remains exactly paused. No animation timer runs on the desktop.
    func setDaylightUpdatesEnabled(_ enabled: Bool) {
        guard enabled && kernel.usesLocalTime else {
            daylightTimer?.cancel(); daylightTimer = nil
            return
        }
        guard daylightTimer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(2))
        source.setEventHandler { [weak self] in self?.refreshDaylight() }
        daylightTimer = source; source.resume()
        refreshDaylight()
    }

    func refreshDaylight() {
        guard isUpdatingDaylight && !isRendering else { return }
        do { try draw() }
        catch { setDaylightUpdatesEnabled(false); onError?(error) }
    }

    deinit { timer?.cancel(); daylightTimer?.cancel() }
}

func failure(_ description: String) -> NSError {
    NSError(domain: "VisualMeditation", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
}
