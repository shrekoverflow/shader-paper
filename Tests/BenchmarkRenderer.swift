import AppKit
import Metal

/// Measures the shipping render path without installing or selecting a wallpaper.
@main struct BenchmarkRenderer {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("Usage: benchmark-renderer resources-directory report.json")
        }
        _ = NSApplication.shared
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        var sizes = [CGSize(width: 2560, height: 1440), CGSize(width: 3840, height: 2160),
                     CGSize(width: 5120, height: 2880)]
        let displays = NSScreen.screens.map { screen -> [String: Any] in
            let size = CGSize(width: (screen.frame.width * screen.backingScaleFactor).rounded(),
                              height: (screen.frame.height * screen.backingScaleFactor).rounded())
            if !sizes.contains(size) { sizes.append(size) }
            return ["name": screen.localizedName, "width": Int(size.width), "height": Int(size.height)]
        }
        var rows = [[String: Any]]()
        let warmups = 4, samples = 12
        for entry in ShaderLibrary.entries(in: resources) {
            for size in sizes {
                try autoreleasepool {
                    let kernel = try ShaderKernel(source: entry.sourceURL)
                    for i in 0..<warmups {
                        _ = try kernel.frame(time: 18 + Double(i) / 30, size: size)
                    }
                    var wall = [Double](), gpu = [Double]()
                    for i in 0..<samples {
                        try autoreleasepool {
                            let start = CACurrentMediaTime()
                            _ = try kernel.frame(time: [0.0, 18.0, 47.0][i % 3] + Double(i) / 30, size: size)
                            wall.append((CACurrentMediaTime() - start) * 1000)
                            gpu.append(kernel.lastGPUSeconds * 1000)
                        }
                    }
                    wall.sort(); gpu.sort()
                    func median(_ values: [Double]) -> Double { (values[5] + values[6]) / 2 }
                    let row: [String: Any] = ["shader": entry.id, "width": Int(size.width), "height": Int(size.height),
                        "medianWallMilliseconds": median(wall), "p95WallMilliseconds": wall[11],
                        "medianGPUMilliseconds": median(gpu), "p95GPUMilliseconds": gpu[11]]
                    rows.append(row)
                    print(String(format: "%@ %dx%d: wall %.2f ms, GPU %.2f ms", entry.id,
                                 Int(size.width), Int(size.height), median(wall), median(gpu)))
                    fflush(stdout)
                }
            }
        }
        let report: [String: Any] = ["device": MTLCreateSystemDefaultDevice()!.name,
            "date": ISO8601DateFormatter().string(from: Date()), "displays": displays,
            "warmupFrames": warmups, "measuredFrames": samples,
            "localHour": 12, "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "wallIncludes": "shader, SDR conversion, pixel allocation, CPU encoding, synchronous GPU wait; excludes compositor",
            "performance": rows]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
