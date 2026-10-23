import AppKit
import Foundation

public enum RichTextStoreError: Error, LocalizedError, Sendable {
    case serializationFailed
    case fileWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .serializationFailed:
            "无法序列化富文本内容"
        case .fileWriteFailed(let message):
            "无法写入富文本文件：\(message)"
        }
    }
}

public struct RichTextLoadResult {
    public let attributedString: NSAttributedString
    public let plainText: String
    public let fileMissing: Bool
}

public struct RichTextSaveResult: Sendable {
    public let relativePath: String?
    public let plainText: String
}

@MainActor
public final class RichTextStore {
    private let paths: DataPaths
    private let fileManager: FileManager

    public init(paths: DataPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func load(
        relativePath: String?,
        fallbackPlainText: String = ""
    ) -> RichTextLoadResult {
        guard let relativePath, !relativePath.isEmpty else {
            return RichTextLoadResult(
                attributedString: NSAttributedString(string: ""),
                plainText: "",
                fileMissing: false
            )
        }

        do {
            let fileURL = try paths.fileURL(forAttachmentRelativePath: relativePath)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return fallback(plainText: fallbackPlainText)
            }

            let wrapper = try FileWrapper(url: fileURL, options: .immediate)
            guard let attributed = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) else {
                return fallback(plainText: fallbackPlainText)
            }

            return RichTextLoadResult(
                attributedString: attributed,
                plainText: attributed.string,
                fileMissing: false
            )
        } catch {
            return fallback(plainText: fallbackPlainText)
        }
    }

    public func isBlank(_ attributedString: NSAttributedString) -> Bool {
        let plainText = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return plainText.isEmpty && !containsAttachment(attributedString)
    }

    @discardableResult
    public func save(
        attributedString: NSAttributedString,
        for id: UUID
    ) throws -> RichTextSaveResult {
        let relativePath = DataPaths.attachmentRelativePath(for: id)
        let destinationURL = try paths.fileURL(forAttachmentRelativePath: relativePath)

        let plainText = attributedString.string

        if isBlank(attributedString) {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            return RichTextSaveResult(relativePath: nil, plainText: "")
        }

        let range = NSRange(location: 0, length: attributedString.length)
        let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtfd,
        ]

        let wrapper = try attributedString.fileWrapper(
            from: range,
            documentAttributes: attributes
        )

        let tempURL = paths.attachmentsURL
            .appendingPathComponent(".tmp-\(UUID().uuidString).rtfd", isDirectory: true)
        if fileManager.fileExists(atPath: tempURL.path) {
            try? fileManager.removeItem(at: tempURL)
        }

        do {
            try wrapper.write(to: tempURL, options: [.atomic], originalContentsURL: nil)

            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: destinationURL)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw RichTextStoreError.fileWriteFailed(error.localizedDescription)
        }

        return RichTextSaveResult(relativePath: relativePath, plainText: plainText)
    }

    @discardableResult
    public func delete(relativePath: String?) -> Bool {
        guard let relativePath, !relativePath.isEmpty,
              let fileURL = try? paths.fileURL(forAttachmentRelativePath: relativePath) else {
            return true
        }
        guard fileManager.fileExists(atPath: fileURL.path) else { return true }
        do {
            try fileManager.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func sweepOrphans(referencedPaths: Set<String>) throws -> [String] {
        let entries = try fileManager.contentsOfDirectory(
            at: paths.attachmentsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        var removed: [String] = []
        for entry in entries {
            let name = entry.lastPathComponent
            if name.hasPrefix(".tmp-") {
                try? fileManager.removeItem(at: entry)
                continue
            }
            guard name.hasSuffix(".rtfd") else { continue }

            let relativePath = "attachments/\(name)"
            guard !referencedPaths.contains(relativePath) else { continue }

            try fileManager.removeItem(at: entry)
            removed.append(relativePath)
        }
        return removed
    }

    private func fallback(plainText: String) -> RichTextLoadResult {
        let text = plainText.isEmpty ? "（富文本附件文件缺失）" : plainText
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return RichTextLoadResult(
            attributedString: attributed,
            plainText: plainText,
            fileMissing: true
        )
    }

    private func containsAttachment(_ attributedString: NSAttributedString) -> Bool {
        var found = false
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
