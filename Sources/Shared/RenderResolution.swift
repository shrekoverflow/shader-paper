import Foundation

/// Start at the destination's backing resolution. Only sustained slow animation
/// reduces it; still frames never use this adaptive size.
struct RenderResolution {
    let nativeSize: CGSize
    private(set) var scale: CGFloat = 1
    private var budget = 1.0 / 30
    private var warmupFrames = 4
    private var samples = [Double]()
    private var fastWindows = 0

    init(bounds: CGSize, backingScale: CGFloat) {
        nativeSize = CGSize(width: max(2, (bounds.width * backingScale).rounded()),
                            height: max(2, (bounds.height * backingScale).rounded()))
    }

    var animationSize: CGSize {
        CGSize(width: max(2, (nativeSize.width * scale).rounded()),
               height: max(2, (nativeSize.height * scale).rounded()))
    }

    mutating func beginAnimation(framesPerSecond: Double) {
        budget = 1 / framesPerSecond
        scale = 1
        fastWindows = 0
        resetSamples()
    }

    mutating func recordFrame(seconds: Double) {
        guard seconds.isFinite && seconds > 0 else { return }
        // Exclude allocation and startup effects after changing resolution.
        if warmupFrames > 0 { warmupFrames -= 1; return }
        samples.append(seconds)
        guard samples.count == 12 else { return }
        samples.sort()
        let median = (samples[5] + samples[6]) / 2
        samples.removeAll(keepingCapacity: true)

        if median > budget {
            // Aim for some presentation headroom. Limit each adjustment to
            // half the previous dimensions and preserve at least quarter scale.
            let ratio = max(0.5, sqrt(budget * 0.8 / median))
            let next = max(0.25, scale * ratio)
            fastWindows = 0
            if next < scale { scale = next; resetSamples() }
        } else if median < budget * 0.5 && scale < 1 {
            // Recover detail after load clears without oscillating every window.
            fastWindows += 1
            if fastWindows >= 3 {
                scale = min(1, scale * 1.2)
                fastWindows = 0
                resetSamples()
            }
        } else {
            fastWindows = 0
        }
    }

    private mutating func resetSamples() {
        warmupFrames = 4
        samples.removeAll(keepingCapacity: true)
    }
}
