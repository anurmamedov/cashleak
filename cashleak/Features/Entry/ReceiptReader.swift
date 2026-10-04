import UIKit
import Vision

/// Reads the text on receipt photos with Vision. Entirely on-device — no
/// network call is made, and nothing leaves the phone.
///
/// Returns positioned lines for `ReceiptParser`; deciding what they mean is
/// the parser's job, so it can be tested without images.
nonisolated enum ReceiptReader {

    /// Reads one or more pages. A long receipt scanned as several pages is
    /// stacked into one tall page, first page at the top, so "near the top"
    /// and "near the bottom" still mean what the parser expects.
    static func lines(in pages: [UIImage]) async -> [ReceiptLine] {
        let count = pages.count
        guard count > 0 else { return [] }

        var all: [ReceiptLine] = []
        for (index, page) in pages.enumerated() {
            let pageLines = await lines(in: page)
            let offset = Double(count - 1 - index)
            for line in pageLines {
                let box = CGRect(
                    x: line.box.minX,
                    y: (line.box.minY + offset) / Double(count),
                    width: line.box.width,
                    height: line.box.height / Double(count)
                )
                all.append(ReceiptLine(line.text, box: box))
            }
        }
        return all
    }

    static func lines(in image: UIImage) async -> [ReceiptLine] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Language correction "fixes" store numbers and prices into words.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "fr-CA"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                return []
            }
            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return ReceiptLine(candidate.string, box: observation.boundingBox)
            }
        }.value
    }

    /// The photo kept with the purchase: long side 1600 px, JPEG. Enough to
    /// read the receipt again later, small enough not to crowd iCloud.
    static func storedImage(from image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 1600 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.6)
    }
}

private extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
