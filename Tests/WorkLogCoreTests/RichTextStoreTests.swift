import AppKit
import Foundation
import Testing
@testable import WorkLogCore

@Suite("Rich text storage")
@MainActor
struct RichTextStoreTests {
    @Test("Rich text with an inline image survives RTFD round-trip")
    func richTextRoundTrip() throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        let richTextStore = RichTextStore(paths: env.paths)
        let id = UUID()
        let document = makeDocument(image: makeImage())

        let saved = try richTextStore.save(attributedString: document, for: id)
        let expectedPath = DataPaths.attachmentRelativePath(for: id)

        #expect(saved.relativePath == expectedPath)
        #expect(saved.plainText.contains("阶段进展"))

        let fileURL = try env.paths.fileURL(forAttachmentRelativePath: expectedPath)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let loaded = richTextStore.load(relativePath: saved.relativePath)
        #expect(!loaded.fileMissing)
        #expect(loaded.plainText.contains("阶段进展"))

        var attachmentCount = 0
        loaded.attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: loaded.attributedString.length),
            options: []
        ) { value, _, _ in
            if value != nil {
                attachmentCount += 1
            }
        }
        #expect(attachmentCount == 1)
    }

    @Test("Blank rich text clears the stored package")
    func blankDocument() throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        let richTextStore = RichTextStore(paths: env.paths)
        let id = UUID()
        let result = try richTextStore.save(
            attributedString: NSAttributedString(string: "   \n"),
            for: id
        )

        #expect(result.relativePath == nil)
        #expect(result.plainText.isEmpty)

        let fileURL = try env.paths.fileURL(
            forAttachmentRelativePath: DataPaths.attachmentRelativePath(for: id)
        )
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("Missing RTFD package falls back to database plain text")
    func missingFileFallback() throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        let richTextStore = RichTextStore(paths: env.paths)
        let id = UUID()
        let saved = try richTextStore.save(
            attributedString: NSAttributedString(string: "数据库纯文本镜像"),
            for: id
        )

        let fileURL = try env.paths.fileURL(
            forAttachmentRelativePath: DataPaths.attachmentRelativePath(for: id)
        )
        try FileManager.default.removeItem(at: fileURL)

        let loaded = richTextStore.load(
            relativePath: saved.relativePath,
            fallbackPlainText: "数据库纯文本镜像"
        )
        #expect(loaded.fileMissing)
        #expect(loaded.plainText == "数据库纯文本镜像")
        #expect(loaded.attributedString.string.contains("数据库纯文本镜像"))
    }

    @Test("Orphan sweep removes unreferenced packages")
    func orphanSweep() throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        let richTextStore = RichTextStore(paths: env.paths)
        let keptID = UUID()
        _ = try richTextStore.save(
            attributedString: NSAttributedString(string: "保留内容"),
            for: keptID
        )

        let strayURL = env.paths.attachmentsURL
            .appendingPathComponent("stray.rtfd", isDirectory: true)
        try FileManager.default.createDirectory(at: strayURL, withIntermediateDirectories: true)
        try Data("stray".utf8).write(to: strayURL.appendingPathComponent("TXT.rtf"))

        let removed = try richTextStore.sweepOrphans(
            referencedPaths: [DataPaths.attachmentRelativePath(for: keptID)]
        )

        #expect(removed.contains("attachments/stray.rtfd"))
        #expect(!FileManager.default.fileExists(atPath: strayURL.path))

        let keptURL = try env.paths.fileURL(
            forAttachmentRelativePath: DataPaths.attachmentRelativePath(for: keptID)
        )
        #expect(FileManager.default.fileExists(atPath: keptURL.path))
    }

    private func makeDocument(image: NSImage) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: "阶段进展\n第一行\n第二行"
        )
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ],
            range: fullRange
        )
        attributed.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 13),
            range: NSRange(location: 0, length: 4)
        )

        let attachment = NSTextAttachment()
        let data = pngData(for: image)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "evidence.png"
        attachment.fileWrapper = wrapper
        attachment.image = image

        attributed.append(NSAttributedString(string: "\n"))
        attributed.append(NSAttributedString(attachment: attachment))
        return attributed
    }

    private func makeImage() -> NSImage {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    private func pngData(for image: NSImage) -> Data {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            Issue.record("Unable to encode test image")
            return Data()
        }
        return data
    }
}
