import Foundation
import AVFoundation
import CoreMedia

/// Normal playback can succeed without temporal metadata. The native aerial
/// ramp-down path requires it on each compressed sample, so validate the same
/// CoreMedia attachment the wallpaper player reads (including after a seek).
@main struct ValidateAerial {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Usage: validate-aerial movie.mov") }
        let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { fatalError("No video") }
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        guard reader.startReading() else { fatalError("Cannot read movie") }
        var samples = 0, missing = 0
        var levels = Set<Int>()
        while let buffer = output.copyNextSampleBuffer() {
            samples += CMSampleBufferGetNumSamples(buffer)
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [NSDictionary] else {
                missing += CMSampleBufferGetNumSamples(buffer)
                continue
            }
            for item in attachments {
                if let info = item[kCMSampleAttachmentKey_HEVCTemporalLevelInfo] as? NSDictionary,
                   let level = info[kCMHEVCTemporalLevelInfoKey_TemporalLevel] as? NSNumber {
                    levels.insert(level.intValue)
                } else { missing += 1 }
            }
        }
        guard reader.status == .completed else { fatalError("Read failed: \(String(describing: reader.error))") }
        print("\(samples) frames, \(seconds)s; temporal levels: \(levels.sorted()); missing temporal metadata: \(missing)")
        guard samples > 0, missing == 0, levels.count >= 2 else { exit(1) }
        // A new reader near the end mirrors resuming from a frozen aerial frame.
        let seekReader = try AVAssetReader(asset: asset)
        seekReader.timeRange = CMTimeRange(start: CMTime(seconds: max(0, seconds - 1), preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
        let seekOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        seekReader.add(seekOutput)
        guard seekReader.startReading() else { fatalError("Could not start seek reader") }
        var resumedFrames = 0
        while let resumed = seekOutput.copyNextSampleBuffer() {
            // CoreMedia emits a zero-sample marker at a seek boundary. It is
            // a timing event, not a video frame, and has no sample attachments.
            guard CMSampleBufferGetNumSamples(resumed) > 0 else { continue }
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(resumed, createIfNecessary: false) as? [NSDictionary],
                  attachments.allSatisfy({ $0[kCMSampleAttachmentKey_HEVCTemporalLevelInfo] != nil }) else {
                fatalError("Missing temporal info after seeking")
            }
            resumedFrames += CMSampleBufferGetNumSamples(resumed)
        }
        guard seekReader.status == .completed, resumedFrames > 0 else { fatalError("Could not read resumed frames") }
        print("Temporal metadata remains available after seeking.")
    }
}
