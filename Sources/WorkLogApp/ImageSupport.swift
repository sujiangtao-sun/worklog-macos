import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageSupport {
    static let maxPixelSize: CGFloat = 1600
    static let maxDisplayWidth: CGFloat = 340
    static let maxDisplayHeight: CGFloat = 220

    static func image(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return data
        }

        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        for url in urls where url.isFileURL {
            if let data = try? Data(contentsOf: url), NSImage(data: data) != nil {
                return data
            }
        }
        return nil
    }

    static func makeAttachment(from image: NSImage) -> NSTextAttachment? {
        guard let data = pngData(from: image) else { return nil }

        let attachment = NSTextAttachment()
        let fileWrapper = FileWrapper(regularFileWithContents: data)
        fileWrapper.preferredFilename = "image.png"
        attachment.fileWrapper = fileWrapper
        attachment.image = image
        attachment.bounds = NSRect(origin: .zero, size: displaySize(for: image))
        return attachment
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func displaySize(for image: NSImage) -> NSSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return NSSize(width: 320, height: 200)
        }

        let scale = min(1, maxDisplayWidth / size.width, maxDisplayHeight / size.height)
        return NSSize(
            width: max(1, floor(size.width * scale)),
            height: max(1, floor(size.height * scale))
        )
    }

    static func image(for attachment: NSTextAttachment) -> NSImage? {
        if let image = attachment.image {
            return image
        }
        if let data = attachment.fileWrapper?.regularFileContents {
            return NSImage(data: data)
        }
        return nil
    }

    /// Scales inline attachments down to a thumbnail that fits the content column.
    /// The attachment image itself stays intact so the preview can show the stored original.
    static func prepareForDisplay(
        _ attributedString: NSAttributedString
    ) -> (attributedString: NSAttributedString, hasImages: Bool) {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        var hasImages = false
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttribute(.attachment, in: fullRange, options: []) { value, _, _ in
            guard let attachment = value as? NSTextAttachment,
                  let image = image(for: attachment) else {
                return
            }
            if attachment.image == nil {
                attachment.image = image
            }
            attachment.bounds = NSRect(origin: .zero, size: displaySize(for: image))
            hasImages = true
        }

        return (mutable, hasImages)
    }
}
