import AppKit
import AVFoundation
import CoreVideo
import Metal
import CryptoKit
import CoreImage

// Compile alongside the app's ShaderRenderer.swift and MotionClock.swift.
// This minimal entry is the only part of the gallery model the renderer requires.
struct ShaderEntry { let sourceURL: URL }

func sourceHash(_ source: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
}

struct Options {
    let command: String
    let values: [String: String]
    init() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, ["still", "movie", "validate", "moviecheck"].contains(command) else {
            throw failure("Usage: render-shader still|movie|validate|moviecheck --shader FILE --out FILE [--input MOVIE --width N --height N --time SECONDS --duration SECONDS --fps N]")
        }
        self.command = command
        var values: [String: String] = [:]
        var i = 1
        while i < args.count {
            guard args[i].hasPrefix("--"), i + 1 < args.count else { throw failure("Expected --option value") }
            values[String(args[i].dropFirst(2))] = args[i + 1]
            i += 2
        }
        self.values = values
    }
    func required(_ key: String) throws -> String {
        guard let value = values[key] else { throw failure("Missing --\(key)") }
        return value
    }
    func number(_ key: String, _ fallback: Double) throws -> Double {
        guard let raw = values[key] else { return fallback }
        guard let value = Double(raw), value.isFinite else { throw failure("Invalid number for --\(key)") }
        return value
    }
}

func bytes(_ pixel: CVPixelBuffer) -> [UInt8] {
    CVPixelBufferLockBaseAddress(pixel, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
    let width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel)
    let stride = CVPixelBufferGetBytesPerRow(pixel)
    let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
    var result = [UInt8](); result.reserveCapacity(width * height * 4)
    for y in 0..<height { result.append(contentsOf: UnsafeBufferPointer(start: base + y * stride, count: width * 4)) }
    return result
}

func srgbBytes(_ pixel: CVPixelBuffer, context: CIContext) -> [UInt8] {
    let width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel)
    var result = [UInt8](repeating: 0, count: width * height * 4)
    let image = CIImage(cvPixelBuffer: pixel)
    result.withUnsafeMutableBytes {
        context.render(image, toBitmap: $0.baseAddress!, rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .BGRA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
    return result
}

func writePNG(_ pixel: CVPixelBuffer, to output: URL) throws {
    CVPixelBufferLockBaseAddress(pixel, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
    let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: CVPixelBufferGetWidth(pixel),
        height: CVPixelBufferGetHeight(pixel), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel),
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
    guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw failure("Could not make PNG")
    }
    try png.write(to: output)
}

func delta(_ a: [UInt8], _ b: [UInt8]) -> [String: Any] {
    precondition(a.count == b.count)
    var total: Double = 0, maximum = 0, changed = 0
    for i in a.indices where i % 4 != 3 {
        let d = abs(Int(a[i]) - Int(b[i]))
        total += Double(d); maximum = max(maximum, d)
        if d != 0 { changed += 1 }
    }
    let channels = a.count / 4 * 3
    return ["meanAbsolute8bitChannelDelta": total / Double(channels),
            "maximum8bitChannelDelta": maximum, "changedChannelFraction": Double(changed) / Double(channels)]
}

// Read the actual artwork output before the host's SDR conversion. This is a
// separate test pipeline; delivered media always goes through exact ShaderKernel.
final class FloatProbe {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    init(source: URL) throws {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        let library = try device.makeLibrary(source: String(contentsOf: source, encoding: .utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    func inspect(time: Double, width: Int, height: Int) throws -> [String: Any] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .renderTarget
        let texture = device.makeTexture(descriptor: descriptor)!
        let command = queue.makeCommandBuffer()!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        var t = Float(time)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&t, length: 4, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        var data = [UInt16](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: width * 8, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        var minimum: Float = .infinity, maximum: Float = -.infinity, nonfinite = 0, badAlpha = 0, overbright = 0
        for i in data.indices {
            let value = Float(Float16(bitPattern: data[i]))
            if !value.isFinite { nonfinite += 1 }
            if i % 4 == 3 { if value != 1 { badAlpha += 1 } }
            else { minimum = min(minimum, value); maximum = max(maximum, value); if value > 1 { overbright += 1 } }
        }
        guard nonfinite == 0 && badAlpha == 0 else { throw failure("Nonfinite half-float output or nonopaque alpha at \(time)") }
        return ["time": time, "width": width, "height": height, "nonfiniteChannels": nonfinite,
            "nonopaquePixels": badAlpha, "minimumRGB": minimum, "maximumRGB": maximum,
            "overbrightChannelFraction": Double(overbright) / Double(width * height * 3),
            "gpuMilliseconds": max(0, command.gpuEndTime - command.gpuStartTime) * 1000]
    }
}

func testClock() throws -> [String: Any] {
    var instant = 100.0
    let clock = MotionClock(saved: 19.5, now: { instant })
    guard clock.value == 19.5 && clock.settled else { throw failure("Clock initial saved state") }
    clock.setMoving(true)
    guard clock.value == 19.5 && clock.speed == 0 else { throw failure("Clock start continuity") }
    instant += 2
    guard abs(clock.value - 20.5) < 1e-10 && clock.speed == 1 else { throw failure("Clock smooth start integral") }
    instant += 5
    let beforeStop = clock.value
    clock.setMoving(false)
    guard clock.value == beforeStop && clock.speed == 1 else { throw failure("Clock stop continuity") }
    instant += 2
    let frozen = clock.value
    guard clock.settled && clock.speed == 0 && abs(frozen - beforeStop - 1) < 1e-10 else { throw failure("Clock settling") }
    instant += 43_200
    guard clock.value == frozen else { throw failure("Clock held value changed") }
    clock.setMoving(true)
    guard clock.value == frozen && clock.speed == 0 else { throw failure("Clock resume continuity") }
    instant += 2
    guard abs(clock.value - frozen - 1) < 1e-10 else { throw failure("Clock resume integral") }
    let restored = MotionClock(saved: frozen, now: { instant })
    guard restored.value == frozen && restored.settled else { throw failure("Clock persistence") }
    let invalid = MotionClock(saved: .nan, now: { instant })
    guard invalid.value == 0 else { throw failure("Clock invalid saved value") }
    return ["passed": true, "checks": ["saved time", "start continuity", "smooth acceleration integral", "stop continuity", "settling", "12-hour exact hold", "resume continuity", "resume integral", "saved-time restoration", "invalid-time normalization"], "heldShaderTime": frozen]
}

func validate(_ kernel: ShaderKernel, source: URL, output: URL) throws {
    let probe = try FloatProbe(source: source)
    let sampledTimes = [0.0, 18.0, 600.0, 7_200.0, 43_200.0, 86_400.0]
    let sizes = [(640, 400), (400, 640), (1024, 256), (512, 512)]
    var probes: [[String: Any]] = []
    for time in sampledTimes { for (w, h) in sizes { probes.append(try probe.inspect(time: time, width: w, height: h)) } }
    var continuity: [[String: Any]] = []
    for time in sampledTimes {
        let size = CGSize(width: 640, height: 400)
        let a = bytes(try kernel.frame(time: time, size: size))
        let repeatA = bytes(try kernel.frame(time: time, size: size))
        guard a == repeatA else { throw failure("Equal-time renders differ") }
        let b = bytes(try kernel.frame(time: time + 1.0 / 30.0, size: size))
        let c = bytes(try kernel.frame(time: time + 30, size: size))
        continuity.append(["time": time, "equalTimeByteIdentical": true,
            "nextFrame": delta(a, b), "after30Seconds": delta(a, c)])
    }
    var performance: [[String: Any]] = []
    for (w, h) in [(2560, 1440), (1600, 2560)] {
        let size = CGSize(width: w, height: h)
        for i in 0..<4 { _ = try kernel.frame(time: Double(i) / 30, size: size) }
        var milliseconds: [Double] = []
        for i in 0..<24 {
            let began = CACurrentMediaTime()
            _ = try kernel.frame(time: 18 + Double(i) / 30, size: size)
            milliseconds.append((CACurrentMediaTime() - began) * 1000)
        }
        let sorted = milliseconds.sorted()
        performance.append(["width": w, "height": h, "warmupFrames": 4, "measuredFrames": milliseconds.count,
            "meanWallMilliseconds": milliseconds.reduce(0, +) / Double(milliseconds.count),
            "medianWallMilliseconds": sorted[sorted.count / 2], "p95WallMilliseconds": sorted[Int(Double(sorted.count - 1) * 0.95)],
            "maximumWallMilliseconds": sorted.last!, "includes": "shader, host SDR conversion, pixel allocation, CPU encode, synchronous GPU wait"])
    }
    let report: [String: Any] = ["shader": source.path, "shaderSHA256": try sourceHash(source), "generatedUTC": ISO8601DateFormatter().string(from: Date()),
        "device": kernel.device.name, "runtimeCompilation": "passed, default options; vertex_main + fragment_main; rgba16Float",
        "hostHelpers": "compiled directly from Sources/Shared", "floatOutput": probes,
        "continuity": continuity, "performance": performance, "motionClock": try testClock(),
        "limitations": ["Pixel deltas measure change; aesthetic motion quality requires visual review.", "Wall render times are local measurements, not energy measurements.", "Shader time is Float as required by the host; very large accumulated times have lower temporal precision."]]
    let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: output)
    print(String(data: json, encoding: .utf8)!)
}

func movie(_ kernel: ShaderKernel, output: URL, width: Int, height: Int, start: Double, duration: Double, fps: Int) throws {
    guard width % 2 == 0 && height % 2 == 0 && duration > 0 && fps > 0 else { throw failure("Movie requires even dimensions and positive duration/fps") }
    if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 18_000_000, AVVideoMaxKeyFrameIntervalKey: fps * 2,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoAllowFrameReorderingKey: false]]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
    guard writer.canAdd(input) else { throw failure("Cannot add movie video track") }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? failure("Movie start failed") }
    writer.startSession(atSourceTime: .zero)
    let count = Int((duration * Double(fps)).rounded())
    let size = CGSize(width: width, height: height)
    for index in 0..<count {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw writer.error ?? failure("Movie writing failed") }
            Thread.sleep(forTimeInterval: 0.003)
        }
        try autoreleasepool {
            let frame = try kernel.frame(time: start + Double(index) / Double(fps), size: size)
            guard adaptor.append(frame, withPresentationTime: CMTime(value: Int64(index), timescale: Int32(fps))) else {
                throw writer.error ?? failure("Movie append failed at frame \(index)")
            }
        }
        if index % (fps * 5) == 0 { print("Rendered \(index)/\(count) frames"); fflush(stdout) }
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: Int64(count), timescale: Int32(fps)))
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }; done.wait()
    guard writer.status == .completed else { throw writer.error ?? failure("Movie finish failed") }
    print("Wrote silent \(width)x\(height) movie: \(count) frames, \(fps) fps, \(duration)s, shader time \(start)...\(start + duration): \(output.path)")
}

// Decode every encoded sample, verify timing and track topology, and compare
// several decoded frames with the exact host renderer. The comparison naturally
// includes expected H.264 losses and RGB/YUV conversion differences.
func checkMovie(_ kernel: ShaderKernel, source: URL, input: URL, output: URL, start: Double, duration: Double, fps: Int) async throws {
    let asset = AVURLAsset(url: input)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw failure("Movie has no video track") }
    guard try await asset.loadTracks(withMediaType: .audio).isEmpty else { throw failure("Movie is not silent") }
    let assetDuration = try await asset.load(.duration).seconds
    let naturalSize = try await track.load(.naturalSize)
    let frameRate = try await track.load(.nominalFrameRate)
    let reader = try AVAssetReader(asset: asset)
    let video = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(video)
    guard reader.startReading() else { throw reader.error ?? failure("Cannot decode movie") }
    let expectedCount = Int((duration * Double(fps)).rounded())
    let colorContext = CIContext(options: [.cacheIntermediates: false])
    let sampleIndices: Set<Int> = [0, expectedCount / 2, expectedCount - 1]
    var count = 0, priorTime = -1.0, firstTime = 0.0
    var comparisons: [[String: Any]] = []
    while let sample = video.copyNextSampleBuffer() {
        let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard time > priorTime && abs(time - Double(count) / Double(fps)) < 0.0001 else { throw failure("Movie frame timestamps are irregular") }
        if count == 0 { firstTime = time }
        priorTime = time
        if sampleIndices.contains(count), let pixel = CMSampleBufferGetImageBuffer(sample) {
            let size = CGSize(width: CVPixelBufferGetWidth(pixel), height: CVPixelBufferGetHeight(pixel))
            let reference = try kernel.frame(time: start + time, size: size)
            let image = CIImage(cvPixelBuffer: pixel)
            let decodedImage = colorContext.createCGImage(image, from: image.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
            let preview = output.deletingPathExtension().appendingPathExtension("frame-\(count).png")
            try NSBitmapImageRep(cgImage: decodedImage).representation(using: .png, properties: [:])!.write(to: preview)
            comparisons.append(["frame": count, "presentationTime": time,
                "decodedFramePNG": preview.path,
                "decodedVersusHostInSRGB": delta(srgbBytes(pixel, context: colorContext), bytes(reference))])
        }
        count += 1
    }
    guard reader.status == .completed else { throw reader.error ?? failure("Movie did not decode to completion") }
    guard count == expectedCount && abs(assetDuration - duration) < 0.001 else { throw failure("Movie duration or decoded frame count mismatch") }
    let report: [String: Any] = ["movie": input.path, "comparisonShaderSHA256": try sourceHash(source), "passed": true, "decodedFrames": count, "expectedFrames": expectedCount,
        "width": naturalSize.width, "height": naturalSize.height, "nominalFPS": frameRate,
        "durationSeconds": assetDuration, "audioTracks": 0, "firstPresentationSeconds": firstTime,
        "colorComparison": "Decoded Rec.709 frames converted to sRGB through Core Image before comparison; expected H.264/chroma losses remain.",
        "lastPresentationSeconds": priorTime, "uniformPresentationIntervals": true, "decodedFrameComparisons": comparisons]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: output)
    print(String(data: data, encoding: .utf8)!)
}

@main struct RenderShader {
    static func main() async {
        do {
            let options = try Options()
            let source = URL(fileURLWithPath: try options.required("shader"))
            let output = URL(fileURLWithPath: try options.required("out"))
            guard !FileManager.default.fileExists(atPath: output.path) else { throw failure("Output already exists; choose a new --out path") }
            let widthValue = try options.number("width", 1920), heightValue = try options.number("height", 1080)
            let fpsValue = try options.number("fps", 30), duration = try options.number("duration", 30)
            let time = try options.number("time", 0)
            guard [widthValue, heightValue].allSatisfy({ $0 >= 1 && $0 <= 16384 && $0.rounded() == $0 }),
                  fpsValue >= 1 && fpsValue <= 240 && fpsValue.rounded() == fpsValue,
                  duration * fpsValue >= 1 && duration * fpsValue <= 1_000_000_000,
                  time >= 0 && time + duration <= Double(Float.greatestFiniteMagnitude) else {
                throw failure("Use whole dimensions from 1 to 16384, whole fps from 1 to 240, a positive movie duration, and nonnegative finite shader time")
            }
            let width = Int(widthValue), height = Int(heightValue), fps = Int(fpsValue)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let kernel = try ShaderKernel(source: source)
            switch options.command {
            case "still":
                try writePNG(kernel.frame(time: time, size: CGSize(width: width, height: height)), to: output)
                print("Wrote \(width)x\(height) PNG at shader time \(time): \(output.path)")
            case "movie":
                try movie(kernel, output: output, width: width, height: height, start: time,
                    duration: duration, fps: fps)
            case "moviecheck":
                try await checkMovie(kernel, source: source, input: URL(fileURLWithPath: try options.required("input")), output: output, start: time,
                    duration: duration, fps: fps)
            default: try validate(kernel, source: source, output: output)
            }
        } catch { fputs("ERROR: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
