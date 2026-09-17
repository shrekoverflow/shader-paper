import AppKit
import CoreVideo

@main struct ResolutionTests {
    static func main() throws {
        func feed(_ policy: inout RenderResolution, _ seconds: Double, count: Int = 16) {
            for _ in 0..<count { policy.recordFrame(seconds: seconds) }
        }
        var policy = RenderResolution(bounds: CGSize(width: 2560, height: 1440), backingScale: 2)
        precondition(policy.nativeSize == CGSize(width: 5120, height: 2880), "Retina backing resolution was capped")
        let portrait = RenderResolution(bounds: CGSize(width: 1800, height: 3200), backingScale: 2)
        precondition(portrait.animationSize == CGSize(width: 3600, height: 6400), "Portrait aspect ratio or scale changed")
        let small = RenderResolution(bounds: CGSize(width: 640, height: 400), backingScale: 1)
        precondition(small.animationSize == CGSize(width: 640, height: 400), "Small surfaces were upscaled")

        policy.beginAnimation(framesPerSecond: 30)
        feed(&policy, 0.5, count: 4) // Startup is not sustained load.
        feed(&policy, 0.005, count: 5)
        feed(&policy, 0.5, count: 1) // An isolated hitch must not lower quality.
        feed(&policy, 0.005, count: 6)
        precondition(policy.animationSize == policy.nativeSize, "Startup or one hitch lowered native quality")
        feed(&policy, .nan); feed(&policy, 0); feed(&policy, .infinity)
        precondition(policy.scale == 1, "Invalid measurements changed quality")
        feed(&policy, 0.12)
        precondition(policy.scale < 1, "Sustained missed frame budgets did not adapt")
        precondition(policy.nativeSize == CGSize(width: 5120, height: 2880), "Adaptation changed the native size")
        let aspect = policy.animationSize.width / policy.animationSize.height
        precondition(abs(aspect - 16.0 / 9) < 0.002, "Adaptation distorted the image")
        feed(&policy, 0.020, count: 48)
        let heldScale = policy.scale
        feed(&policy, 0.020, count: 48)
        precondition(policy.scale == heldScale, "Healthy frame times caused resolution oscillation")
        feed(&policy, 0.004, count: 240)
        precondition(policy.scale == 1, "Quality never recovered after load cleared")
        policy.beginAnimation(framesPerSecond: 15)
        feed(&policy, 0.050)
        precondition(policy.scale == 1, "Low Power Mode ignored its 15 fps budget")
        policy.beginAnimation(framesPerSecond: 30)
        feed(&policy, 0.050)
        precondition(policy.scale < 1, "30 fps budget was not restored")
        policy.beginAnimation(framesPerSecond: 30)
        precondition(policy.scale == 1, "Resuming did not retry native resolution")

        _ = NSApplication.shared
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let entry = ShaderLibrary.entries(in: resources).first { $0.id == "Light" }!
        let root = CALayer(); root.frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        var now = 100.0
        let clock = MotionClock(saved: 18, now: { now })
        let renderer = try ShaderRenderer(entry: entry, clock: clock, root: root, scale: 2)
        func checkSize(_ width: Int, _ height: Int) {
            precondition(CVPixelBufferGetWidth(renderer.lastFrame!) == width)
            precondition(CVPixelBufferGetHeight(renderer.lastFrame!) == height)
        }
        checkSize(5120, 2880)
        clock.setMoving(true, immediately: true); renderer.start()
        // Inject a sustained load into the policy, independent of test hardware.
        feed(&renderer.resolution, 0.15)
        try renderer.drawAnimationFrame()
        precondition(renderer.pixelSize.width < 5120, "Animation ignored measured load")
        now += 1
        clock.setMoving(false)
        now += 2.1
        var settledCallbacks = 0
        renderer.onSettled = { settledCallbacks += 1 }
        try renderer.drawAnimationFrame()
        checkSize(5120, 2880)
        precondition(!renderer.isRendering && settledCallbacks == 1, "Native settled frame did not stop the timer")
        let heldFrame = renderer.lastFrame!, heldTime = clock.value, heldCount = renderer.frameCount
        now += 3600
        renderer.restoreNativeFrame()
        precondition(renderer.lastFrame === heldFrame && renderer.frameCount == heldCount && clock.value == heldTime,
                     "A native held frame was redrawn or its motion advanced")

        clock.setMoving(true, immediately: true); renderer.start()
        precondition(renderer.resolution.animationSize == renderer.nativePixelSize, "Resume did not start at native size")
        feed(&renderer.resolution, 0.15)
        try renderer.drawAnimationFrame()
        let sleepingFrame = renderer.lastFrame!, sleepingCount = renderer.frameCount
        clock.setMoving(false, immediately: true); renderer.stop()
        precondition(renderer.pixelSize.width < 5120 && renderer.lastFrame === sleepingFrame && renderer.frameCount == sleepingCount,
                     "Stopping an inactive surface unexpectedly rendered")
        renderer.restoreNativeFrame()
        checkSize(5120, 2880)
        precondition(!renderer.isRendering, "Restoring native quality restarted animation")
        print("PASS: native backing dimensions, measured animation fallback, hitch tolerance, recovery, low power, native settling and resume")
    }
}
