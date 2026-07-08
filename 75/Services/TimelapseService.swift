import Foundation
import AVFoundation
import UIKit

/// Builds a timelapse video from the private progress photos (oldest → newest,
/// ~3 frames/sec). Output goes to a temp file for the share sheet; nothing
/// leaves the device unless the user shares it.
enum TimelapseService {

    enum TimelapseError: LocalizedError {
        case tooFewPhotos, writerFailed
        var errorDescription: String? {
            switch self {
            case .tooFewPhotos: return "Need at least 2 photos for a timelapse."
            case .writerFailed: return "Couldn't create the video file."
            }
        }
    }

    static func build(plan: Plan) async throws -> URL {
        let items: [(Date, String)] = plan.days
            .sorted { $0.date < $1.date }
            .flatMap { d in d.photos.sorted { $0.createdAt < $1.createdAt }.map { (d.date, $0.filename) } }
        guard items.count >= 2 else { throw TimelapseError.tooFewPhotos }

        let size = CGSize(width: 720, height: 1280)
        let fps: Int32 = 30
        let framesPerPhoto: Int64 = 10   // ~1/3 s per photo

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("75-timelapse-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outURL)

        guard let writer = try? AVAssetWriter(outputURL: outURL, fileType: .mp4) else {
            throw TimelapseError.writerFailed
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height
            ])
        writer.add(input)
        guard writer.startWriting() else { throw TimelapseError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        var frame: Int64 = 0
        for (_, filename) in items {
            let url = photosDir().appendingPathComponent(filename)
            guard let image = UIImage(contentsOfFile: url.path),
                  let buffer = pixelBuffer(from: image, size: size, pool: adaptor.pixelBufferPool) else { continue }
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: frame * framesPerPhoto, timescale: fps))
            frame += 1
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw TimelapseError.writerFailed }
        return outURL
    }

    private static func pixelBuffer(from image: UIImage, size: CGSize,
                                    pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var maybeBuffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
        }
        if maybeBuffer == nil {
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32ARGB, nil, &maybeBuffer)
        }
        guard let buffer = maybeBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                      width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue),
              let cg = image.cgImage else { return nil }

        // Aspect-fill into the frame
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let imageAspect = CGFloat(cg.width) / CGFloat(cg.height)
        let frameAspect = size.width / size.height
        var drawRect = CGRect(origin: .zero, size: size)
        if imageAspect > frameAspect {
            let w = size.height * imageAspect
            drawRect = CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        } else {
            let h = size.width / imageAspect
            drawRect = CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        }
        context.draw(cg, in: drawRect)
        return buffer
    }
}
