import AppKit

@main struct RendererLifecycleTests {
    static func main() throws {
        _ = NSApplication.shared
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let entry = ShaderLibrary.entries(in: resources).first { $0.id == ShaderLibrary.defaultShader }!
        let root = CALayer(); root.frame = CGRect(x: 0, y: 0, width: 640, height: 400)
        let clock = MotionClock(saved: 18)
        let renderer = try ShaderRenderer(entry: entry, clock: clock, root: root, scale: 1)
        var renderError: Error?
        renderer.onError = { renderError = $0 }
        func run(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        clock.setMoving(true, immediately: true); renderer.start(); run(0.7)
        precondition(renderer.frameCount > 4 && renderer.isRendering, "Live animation did not advance")
        clock.setMoving(false); run(2.4)
        precondition(!renderer.isRendering && clock.settled, "Settled renderer still schedules frames")
        let held = renderer.lastFrame!, count = renderer.frameCount, time = clock.value
        run(1)
        precondition(renderer.frameCount == count && clock.value == time, "Paused renderer advanced")
        precondition(renderer.lastFrame === held, "Paused renderer discarded its display surface")
        clock.setMoving(true); renderer.start(); run(0.7)
        precondition(renderer.frameCount > count && clock.value > time, "Resume did not continue")
        renderer.stop(); clock.setMoving(false, immediately: true)
        if let renderError { throw renderError }
        print("PASS: live frames → smooth stop → retained frame with no timer → resume")
    }
}
