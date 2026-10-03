import UIKit

/// Turns whatever someone picks from Photos into a small square profile photo.
///
/// A phone photo is several megabytes and the wrong shape. Stored as-is it would
/// sync through the person's iCloud every time and be cropped differently on
/// every screen. So it's cropped to the centre square and shrunk once, here,
/// before it's ever saved.
/// `nonisolated`: the project defaults to the main actor, and resizing a large
/// photo belongs off it.
nonisolated enum ProfilePhoto {

    static let side: CGFloat = 512

    /// Square, `side` × `side`, JPEG. `nil` if the data isn't an image.
    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let size = image.size
        let shortest = min(size.width, size.height)
        guard shortest > 0 else { return nil }

        // Scale so the shorter edge fills the square, then centre it — the same
        // crop the round avatar shows.
        let scale = side / shortest
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: drawn))
        }
        return square.jpegData(compressionQuality: 0.8)
    }
}
