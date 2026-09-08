import Foundation
import Metal
import AVFoundation
import AppKit
import VideoToolbox

// Render the original shader once into a native aerial movie. The shader stays
// unchanged; a cosine time path makes this finite excerpt loop continuously,
// with matching position and velocity at the join. macOS controls when to play
// or settle the resulting video, so no shader renderer needs to stay running.
let arguments = CommandLine.arguments
if arguments.count < 3 {
    print("Usage: RenderAerial shader-path output-directory [--smoke]")
    exit(64)
}
let smoke = arguments.contains("--smoke")
let width = smoke ? 960 : 3840
let height = smoke ? 540 : 2160
let fps: Int32 = 30
let duration = smoke ? 2 : 120
let root = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let movie = root.appendingPathComponent("Almost a Shape.mov")
guard !FileManager.default.fileExists(atPath: movie.path) else {
    fatalError("Output already exists: \(movie.path)")
}
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    fatalError("Metal GPU unavailable")
}
let source = try String(contentsOfFile: arguments[1], encoding: .utf8)
let library = try device.makeLibrary(source: source, options: nil)
let descriptor = MTLRenderPipelineDescriptor()
descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
// The artwork emits linear RGB. Metal's sRGB attachment encodes that to display
// RGB before VideoToolbox converts it to the movie's YCbCr representation.
descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
    width: width, height: height, mipmapped: false)
textureDescriptor.storageMode = .shared
textureDescriptor.usage = [.renderTarget]
let texture = device.makeTexture(descriptor: textureDescriptor)!

func draw(at seconds: Double) throws {
    let command = queue.makeCommandBuffer()!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .dontCare
    pass.colorAttachments[0].storeAction = .store
    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
    var time = Float(30 * (1 - cos(2 * .pi * seconds / 120)))
    var localHour: Float = 12 // Fixed daylight for optional time-aware artwork.
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
    encoder.setFragmentBytes(&localHour, length: MemoryLayout<Float>.size, index: 1)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    if let error = command.error { throw error }
}

func snapshot(at seconds: Double, name: String) throws {
    try draw(at: seconds)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { pointer in
        texture.getBytes(pointer.baseAddress!, bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    }
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
    for index in stride(from: 0, to: pixels.count, by: 4) {
        bitmap.bitmapData![index] = pixels[index + 2]
        bitmap.bitmapData![index + 1] = pixels[index + 1]
        bitmap.bitmapData![index + 2] = pixels[index]
        bitmap.bitmapData![index + 3] = 255
    }
    let tagged = bitmap.retagging(with: .sRGB)!
    try tagged.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
}
try snapshot(at: 0, name: "Poster.png")
try snapshot(at: 40, name: "Preview-40.png")

// Intermediate artwork master. TemporalEncode adds the HEVC temporal sample
// groups needed by the native aerial ramp-down path; do not install this
// intermediate movie directly, even though ordinary video playback succeeds.
let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.hevc,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
    ],
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: smoke ? 2_000_000 : 24_000_000,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoMaxKeyFrameIntervalKey: fps,
        AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
        AVVideoAllowFrameReorderingKey: false,
        AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String
    ]
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
])
guard writer.canAdd(input) else { fatalError("Cannot add HEVC video input") }
writer.add(input)
guard writer.startWriting() else { fatalError("Encoder: \(String(describing: writer.error))") }
writer.startSession(atSourceTime: .zero)
let began = Date()
for frame in 0..<(duration * Int(fps)) {
    try autoreleasepool {
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else { fatalError("Encoder: \(String(describing: writer.error))") }
            Thread.sleep(forTimeInterval: 0.002)
        }
        try draw(at: Double(frame) / Double(fps))
        var optionalBuffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
              let buffer = optionalBuffer else { fatalError("Cannot allocate video frame") }
        CVPixelBufferLockBaseAddress(buffer, [])
        texture.getBytes(CVPixelBufferGetBaseAddress(buffer)!, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
            fatalError("Frame \(frame): \(String(describing: writer.error))")
        }
    }
    if frame % 300 == 0 {
        print("Rendered \(frame / Int(fps))/\(duration) seconds (\(Int(Date().timeIntervalSince(began))) seconds elapsed)")
        fflush(stdout)
    }
}
writer.endSession(atSourceTime: CMTime(value: Int64(duration), timescale: 1))
input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
guard writer.status == .completed else { fatalError("Export: \(String(describing: writer.error))") }
print("Completed \(width)×\(height), \(duration)s, \(fps) fps HEVC aerial: \(movie.path)")
