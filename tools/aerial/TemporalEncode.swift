// Adapted from AlexisBCD/macos-custom-video-wallpaper-fix (MIT).
// Copyright (c) 2026 AlexisBCD. See LICENSE.temporal-encoder.
// The base-layer setting preserves the per-frame temporal attachments Apple
// requires when it ramps an aerial down to its still desktop frame.

import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia

// usage: encode_temporal <input.mov> <output.mov> [loopCount] [bitrateMbps]
let args = CommandLine.arguments
guard args.count >= 3 else { FileHandle.standardError.write("usage: encode_temporal in out [loops] [mbps]\n".data(using:.utf8)!); exit(2) }
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let loopCount = args.count >= 4 ? max(1, Int(args[3]) ?? 1) : 1
let bitrate = args.count >= 5 ? (Int(args[4]) ?? 10) * 1_000_000 : 10_000_000
guard !FileManager.default.fileExists(atPath: outURL.path) else { fatalError("Output exists; choose a new destination") }

let asset = AVURLAsset(url: inURL)
var vtrack: AVAssetTrack!
var natSize = CGSize.zero; var nomFps: Float = 24; var clipDur = CMTime.zero
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { fatalError("No video track") }
        vtrack = track
        natSize = try await track.load(.naturalSize)
        nomFps = try await track.load(.nominalFrameRate)
        clipDur = try await asset.load(.duration)
        sem.signal()
    } catch { fatalError("Could not read source: \(error)") }
}
sem.wait()
guard let vtrack = vtrack else { fatalError("no video track") }
let W = Int(natSize.width), H = Int(natSize.height)
if nomFps < 1 { nomFps = 24 }
FileHandle.standardError.write("source \(W)x\(H) @\(nomFps)fps clip=\(CMTimeGetSeconds(clipDur))s loops=\(loopCount) br=\(bitrate)\n".data(using:.utf8)!)

// Streaming writer: sets up on first sample, appends in decode order
final class StreamWriter {
    let outURL: URL; var writer: AVAssetWriter?; var input: AVAssetWriterInput?
    var started = false; let lock = NSLock(); var appended = 0; var failed = false
    init(_ u: URL) { outURL = u }
    func handle(_ sb: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        if failed || !CMSampleBufferDataIsReady(sb) { return }
        if !started {
            guard let fmt = CMSampleBufferGetFormatDescription(sb) else { return }
            let w = try! AVAssetWriter(outputURL: outURL, fileType: .mov)
            let inp = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: fmt)
            inp.expectsMediaDataInRealTime = false
            guard w.canAdd(inp) else { fatalError("Cannot add compressed video track") }; w.add(inp); guard w.startWriting() else { fatalError("Writer failed: \(String(describing: w.error))") }
            w.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
            writer = w; input = inp; started = true
        }
        while !(input!.isReadyForMoreMediaData) { guard writer!.status == .writing else { fatalError("Writer failed: \(String(describing: writer!.error))") }; usleep(500) }
        if !input!.append(sb) { failed = true; FileHandle.standardError.write("append failed: \(String(describing: writer!.error))\n".data(using:.utf8)!) }
        else { appended += 1 }
    }
    func finish() {
        lock.lock(); let w = writer; let inp = input; lock.unlock()
        guard let w = w, let inp = inp else { fatalError("nothing written") }
        inp.markAsFinished()
        let s = DispatchSemaphore(value: 0); w.finishWriting { s.signal() }; s.wait()
        if w.status == .completed { print("OK wrote \(outURL.path), \(appended) frames") }
        else { FileHandle.standardError.write("writer status \(w.status.rawValue) err \(String(describing: w.error))\n".data(using:.utf8)!); exit(1) }
    }
}
let sw = StreamWriter(outURL)

let cb: VTCompressionOutputCallback = { (refCon, _, status, _, sbuf) in
    guard status == noErr, let sbuf = sbuf else { fatalError("HEVC encoder callback failed: \(status)") }
    Unmanaged<StreamWriter>.fromOpaque(refCon!).takeUnretainedValue().handle(sbuf)
}

var session: VTCompressionSession?
let spec: [CFString: Any] = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true]
let cs = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(W), height: Int32(H),
    codecType: kCMVideoCodecType_HEVC, encoderSpecification: spec as CFDictionary, imageBufferAttributes: nil,
    compressedDataAllocator: nil, outputCallback: cb, refcon: Unmanaged.passUnretained(sw).toOpaque(),
    compressionSessionOut: &session)
guard cs == noErr, let session = session else { fatalError("VTCompressionSessionCreate failed \(cs)") }

func setP(_ key: CFString, _ val: CFTypeRef) {
    let s = VTSessionSetProperty(session, key: key, value: val)
    guard s == noErr else { fatalError("Required encoder property \(key) failed: \(s)") }
}
setP(kVTCompressionPropertyKey_RealTime, kCFBooleanFalse)
setP(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main10_AutoLevel)
setP(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanTrue)
setP(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: nomFps))
setP(kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: Int(nomFps * 5)))
setP(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: bitrate))
setP(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
setP(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
setP(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
// *** temporal scalability (2 sub-layers) -> tscl/tsas sample groups ***
setP(kVTCompressionPropertyKey_AllowTemporalCompression, kCFBooleanTrue)
setP(kVTCompressionPropertyKey_BaseLayerFrameRate, NSNumber(value: Double(nomFps) / 2.0))
guard VTCompressionSessionPrepareToEncodeFrames(session) == noErr else { fatalError("Could not prepare encoder") }

func makeReader() -> (AVAssetReader, AVAssetReaderTrackOutput) {
    let reader = try! AVAssetReader(asset: asset)
    let rout = AVAssetReaderTrackOutput(track: vtrack, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
    rout.alwaysCopiesSampleData = false
    reader.add(rout); guard reader.startReading() else { fatalError("Reader failed: \(String(describing: reader.error))") }; return (reader, rout)
}

var n = 0
for loop in 0..<loopCount {
    let offset = CMTimeMultiply(clipDur, multiplier: Int32(loop))
    let (reader, rout) = makeReader()
    while let sbuf = rout.copyNextSampleBuffer() {
        guard let pb = CMSampleBufferGetImageBuffer(sbuf) else { continue }
        let pts = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(sbuf), offset)
        var dur = CMSampleBufferGetDuration(sbuf)
        if !dur.isValid || dur.value == 0 { dur = CMTimeMake(value: 1, timescale: Int32(nomFps.rounded())) }
        let encodeStatus = VTCompressionSessionEncodeFrame(session, imageBuffer: pb, presentationTimeStamp: pts, duration: dur,
            frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
        guard encodeStatus == noErr else { fatalError("Frame \(n) failed: \(encodeStatus)") }
        n += 1
    }
    guard reader.status == .completed else { fatalError("Source decode failed: \(String(describing: reader.error))") }
    if (loop % 1) == 0 { FileHandle.standardError.write("  loop \(loop)/\(loopCount) fed \(n) frames\n".data(using:.utf8)!) }
}
guard VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) == noErr else { fatalError("Could not flush encoder") }
FileHandle.standardError.write("fed \(n) frames total\n".data(using:.utf8)!)
sw.finish()
guard sw.appended == n else { fatalError("Dropped frames: \(sw.appended)/\(n)") }
VTCompressionSessionInvalidate(session)
