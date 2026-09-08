import AppKit
import CoreVideo

@main struct DaylightTests {
    static func pixels(_ pixel: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        let width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
        var result = [UInt8](); result.reserveCapacity(width * height * 4)
        for row in 0..<height {
            result.append(contentsOf: UnsafeBufferPointer(start: base + row * stride, count: width * 4))
        }
        return result
    }

    static func main() throws {
        func equal(_ actual: Float, _ expected: Float, _ label: String) {
            precondition(abs(actual - expected) < 0.00001, "\(label): \(actual) != \(expected)")
        }
        let iso = ISO8601DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func localHour(_ timestamp: String) -> Float {
            LocalDaylight.hour(at: iso.date(from: timestamp)!, calendar: calendar)
        }
        equal(localHour("2026-03-08T09:59:59Z"), 2 - 1.0 / 3600, "Before spring clock change")
        equal(localHour("2026-03-08T10:00:00Z"), 3, "Spring clock skips to 03:00")
        equal(localHour("2026-11-01T08:59:59Z"), 2 - 1.0 / 3600, "Before autumn clock change")
        equal(localHour("2026-11-01T09:00:00Z"), 1, "Autumn clock repeats 01:00")
        equal(localHour("2026-09-09T06:59:59Z"), 24 - 1.0 / 3600, "Before local midnight")
        equal(localHour("2026-09-09T07:00:00Z"), 0, "Local midnight wraps to zero")
        equal(localHour("2026-09-08T19:30:00Z"), 12.5, "Civil hour includes minutes")
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        equal(localHour("2026-09-08T19:30:00Z"), 4.5, "Same instant follows a changed time zone")
        equal(LocalDaylight.normalized(-0.5), 23.5, "Negative hour wraps")
        equal(LocalDaylight.normalized(24), 0, "24:00 wraps")
        equal(LocalDaylight.normalized(48.5), 0.5, "Multiple days wrap")
        equal(LocalDaylight.normalized(.nan), 12, "Invalid hour falls back to noon")
        equal(LocalDaylight.normalized(.infinity), 12, "Infinite hour falls back to noon")

        _ = NSApplication.shared
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let entries = ShaderLibrary.entries(in: resources)
        let flight = entries.first { $0.id == "Flight" }!
        let kernel = try ShaderKernel(source: flight.sourceURL)
        precondition(kernel.usesLocalTime, "Flight does not expose its local-hour input")
        let size = CGSize(width: 320, height: 200)
        func render(_ hour: Float) throws -> [UInt8] {
            pixels(try kernel.frame(time: 18, size: size, localHour: hour))
        }
        let noon = try render(12), evening = try render(18.5), midnight = try render(0)
        let repeatedNoon = try render(12), wrappedMidnight = try render(24)
        precondition(noon == repeatedNoon, "Identical motion and local hour must render identically")
        precondition(noon != evening && evening != midnight && noon != midnight,
                     "Day, evening, and night must produce distinct lighting")
        precondition(midnight == wrappedMidnight, "Midnight must match normalized 24:00")
        let beforeMidnight = try render(24 - 1.0 / 3600), afterMidnight = try render(1.0 / 3600)
        let midnightDelta = zip(beforeMidnight, afterMidnight).enumerated()
            .filter { $0.offset % 4 != 3 }
            .reduce(0.0) { $0 + Double(abs(Int($1.element.0) - Int($1.element.1))) }
            / Double(Int(size.width * size.height) * 3)
        precondition(midnightDelta < 0.25, "Lighting jumps across midnight: mean channel delta \(midnightDelta)")

        let root = CALayer(); root.frame = CGRect(origin: .zero, size: size)
        var hour: Float = 12
        let clock = MotionClock(saved: 18)
        let renderer = try ShaderRenderer(entry: flight, clock: clock, root: root, scale: 1, daylightHour: { hour })
        var renderError: Error?
        renderer.onError = { renderError = $0 }
        renderer.setDaylightUpdatesEnabled(true)
        if let renderError { throw renderError }
        precondition(renderer.isUpdatingDaylight && !renderer.isRendering, "Paused Flight needs only its daylight timer")
        precondition(pixels(renderer.lastFrame!) == noon, "Injected noon differs from fixed-hour export")
        for (newHour, expected) in [(Float(18.5), evening), (Float(0), midnight)] {
            hour = newHour
            let count = renderer.frameCount
            renderer.refreshDaylight()
            if let renderError { throw renderError }
            precondition(renderer.frameCount == count + 1 && pixels(renderer.lastFrame!) == expected,
                         "Paused lighting did not follow the wall clock")
            precondition(clock.value == 18 && clock.settled && !renderer.isRendering,
                         "Updating daylight advanced saved motion")
        }
        renderer.setDaylightUpdatesEnabled(false)
        let held = renderer.lastFrame!, heldCount = renderer.frameCount
        hour = 12
        renderer.refreshDaylight()
        precondition(!renderer.isUpdatingDaylight && renderer.frameCount == heldCount && renderer.lastFrame === held,
                     "A queued daylight callback must not draw after disabling updates")
        renderer.setDaylightUpdatesEnabled(true)
        if let renderError { throw renderError }
        precondition(renderer.frameCount == heldCount + 1 && pixels(renderer.lastFrame!) == noon,
                     "Re-enabling daylight must immediately catch up")
        precondition(clock.value == 18, "Catching up after suspension advanced motion")

        renderer.start()
        let animatingCount = renderer.frameCount
        renderer.refreshDaylight()
        precondition(renderer.frameCount == animatingCount, "Daylight refresh duplicated an active animation timer")
        renderer.stop()
        precondition(renderer.isUpdatingDaylight && !renderer.isRendering, "Stopping motion also stopped daylight")
        renderer.setDaylightUpdatesEnabled(false)

        let ordinary = entries.first { $0.id == ShaderLibrary.defaultShader }!
        let ordinaryRoot = CALayer(); ordinaryRoot.frame = CGRect(origin: .zero, size: size)
        let ordinaryRenderer = try ShaderRenderer(entry: ordinary, clock: MotionClock(saved: 18),
            root: ordinaryRoot, scale: 1, daylightHour: { hour })
        let ordinaryFrame = ordinaryRenderer.lastFrame!, ordinaryCount = ordinaryRenderer.frameCount
        ordinaryRenderer.setDaylightUpdatesEnabled(true)
        hour = 0; ordinaryRenderer.refreshDaylight()
        precondition(!ordinaryRenderer.isUpdatingDaylight && !ordinaryRenderer.isRendering,
                     "Artwork without a local-hour input must not acquire a daylight timer")
        precondition(ordinaryRenderer.frameCount == ordinaryCount && ordinaryRenderer.lastFrame === ordinaryFrame,
                     "Other wallpapers must retain their exact held surface")
        print("PASS: civil time, DST, time zones, deterministic daylight, midnight continuity, frozen motion, suspension, and unchanged ordinary wallpapers")
    }
}
