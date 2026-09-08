import AppKit
import CoreVideo

@main struct RenderLibrary {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: render-library resources-directory previews-directory") }
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var failed = [String]()
        for entry in ShaderLibrary.entries(in: resources) {
            do {
                let kernel = try ShaderKernel(source: entry.sourceURL)
                // Sample multiple times and aspect ratios without showing any
                // other model's shader source to the reviewing agent.
                for (time, size) in [(18.0, CGSize(width: 640, height: 400)),
                                     (47.0, CGSize(width: 400, height: 640))] {
                    let frame = try kernel.frame(time: time, size: size)
                    CVPixelBufferLockBaseAddress(frame, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
                    let bytes = CVPixelBufferGetBaseAddress(frame)!
                    let context = CGContext(data: bytes, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(frame), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
                    guard let image = context.makeImage() else { throw failure("No thumbnail") }
                    if time == 18 {
                        let bitmap = NSBitmapImageRep(cgImage: image)
                        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(entry.id + ".png"))
                    }
                }
                print("PASS \(entry.id)")
            } catch {
                failed.append(entry.id)
                // Compiler errors can contain source excerpts, so keep this
                // compatibility report to the shader name and error category.
                print("FAIL \(entry.id) (\((error as NSError).domain), \((error as NSError).code))")
            }
        }
        guard failed.isEmpty else { exit(1) }
        print("All \(ShaderLibrary.entries(in: resources).count) shaders rendered at two times and aspect ratios.")
    }
}
