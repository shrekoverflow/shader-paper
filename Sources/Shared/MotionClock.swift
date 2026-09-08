import Foundation
import QuartzCore

/// Integrates a smooth change in speed, then becomes mathematically constant.
/// No timer is needed after settling. The clock is driven by monotonic time;
/// the saved value is shader time, so neither sleep nor app restarts skip ahead.
final class MotionClock {
    private var base: Double
    private var began: Double
    private var fromSpeed = 0.0
    private var toSpeed = 0.0
    private var ramp = 0.0
    private let now: () -> Double

    init(saved: Double = 0, now: @escaping () -> Double = { CACurrentMediaTime() }) {
        self.base = saved.isFinite ? max(0, saved) : 0
        self.now = now
        self.began = now()
    }

    var value: Double {
        let dt = max(0, now() - began)
        guard ramp > 0 else { return base + toSpeed * dt }
        let t = min(dt, ramp), u = t / ramp
        let integral = ramp * (u * u * u - 0.5 * u * u * u * u)
        return base + fromSpeed * t + (toSpeed - fromSpeed) * integral + toSpeed * max(0, dt - ramp)
    }
    var speed: Double {
        guard ramp > 0 else { return toSpeed }
        let u = min(1, max(0, (now() - began) / ramp))
        return fromSpeed + (toSpeed - fromSpeed) * u * u * (3 - 2 * u)
    }
    var settled: Bool { toSpeed == 0 && (ramp == 0 || now() - began >= ramp) }

    func setMoving(_ moving: Bool, immediately: Bool = false) {
        let target = moving ? 1.0 : 0.0
        if toSpeed == target && !immediately { return }
        let currentValue = value, currentSpeed = speed
        base = currentValue
        began = now()
        fromSpeed = immediately ? target : currentSpeed
        toSpeed = target
        ramp = immediately ? 0 : 2.0
    }
}
