import Foundation

@main struct MotionTests {
    static func main() {
        var now = 0.0
        let clock = MotionClock(saved: 18, now: { now })
        func equal(_ actual: Double, _ expected: Double, _ label: String) {
            precondition(abs(actual - expected) < 0.000001, "\(label): \(actual) != \(expected)")
        }
        now = 100; equal(clock.value, 18, "Initial wallpaper stays still")
        clock.setMoving(true); now = 101
        equal(clock.speed, 0.5, "Smooth start midpoint")
        equal(clock.value, 18.1875, "Integrated start")
        now = 102; equal(clock.value, 19, "Integrated full ramp")
        now = 112; equal(clock.value, 29, "Natural shader time")
        clock.setMoving(false); now = 113
        equal(clock.value, 29.8125, "Integrated slowdown")
        clock.setMoving(true)
        equal(clock.value, 29.8125, "Interrupted ramp has no position jump")
        equal(clock.speed, 0.5, "Interrupted ramp has no speed jump")
        now = 115; equal(clock.value, 31.3125, "Interrupted ramp integral")
        clock.setMoving(false); now = 117
        precondition(clock.settled)
        equal(clock.value, 32.3125, "Exact settled position")
        now = 10_000; equal(clock.value, 32.3125, "No time drift while paused")
        clock.setMoving(true); now += 0.5
        let beforeSleep = clock.value
        clock.setMoving(false, immediately: true); now += 100_000
        equal(clock.value, beforeSleep, "Sleep does not advance shader time")
        let restarted = MotionClock(saved: clock.value, now: { now })
        equal(restarted.value, beforeSleep, "Saved progress survives restart")
        precondition(restarted.settled)
        print("PASS: motion integration, interrupted ramps, settled hold, sleep, and saved progress")
    }
}
