import AppKit
import UniformTypeIdentifiers

@MainActor
final class RichTextController {
    let initialContent: NSAttributedString
    weak var textView: RichEditorTextView?

    private let baseFont = NSFont.systemFont(ofSize: 13)

    init(initialContent: NSAttributedString) {
        self.initialContent = initialContent
    }

    var currentContent: NSAttributedString {
        textView?.attributedString() ?? initialContent
    }

    func attach(_ textView: RichEditorTextView) {
        self.textView = textView
    }

    func focus() {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
    }

    func toggleBold() {
        toggleFontTrait(.boldFontMask)
    }

    func toggleItalic() {
        toggleFontTrait(.italicFontMask)
    }

    func toggleUnderline() {
        toggleStyleAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue)
    }

    func toggleStrikethrough() {
        toggleStyleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue)
    }

    func changeFontSize(by delta: CGFloat) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let font = currentFont(in: textView, range: range)
        let newSize = min(max(font.pointSize + delta, 9), 36)
        let newFont = NSFontManager.shared.convert(font, toSize: newSize)
        applyFont(newFont, in: textView, range: range)
        focus()
    }

    func setAlignment(_ alignment: NSTextAlignment) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let style = mutableParagraphStyle(in: textView, range: range)
        style.alignment = alignment

        if range.length > 0 {
            let paragraphRange = (textView.string as NSString).paragraphRange(for: range)
            textView.textStorage?.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            textView.didChangeText()
        } else {
            textView.typingAttributes[.paragraphStyle] = style
            let paragraphRange = (textView.string as NSString).paragraphRange(for: range)
            if paragraphRange.length > 0 {
                textView.textStorage?.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
                textView.didChangeText()
            }
        }
        focus()
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "插入图片"
        panel.prompt = "插入"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }
        guard let url = panel.url,
              let data = try? Data(contentsOf: url),
              let image = ImageSupport.image(from: data) else {
            showImageError()
            return
        }
        insertImage(image)
    }

    func insertImage(_ image: NSImage) {
        guard let textView else { return }
        guard let attachment = ImageSupport.makeAttachment(from: image) else {
            showImageError()
            return
        }

        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()
        let imageString = NSMutableAttributedString(attachment: attachment)
        let inheritedAttributes = textView.typingAttributes.filter { $0.key != .attachment }
        imageString.addAttributes(
            inheritedAttributes,
            range: NSRange(location: 0, length: imageString.length)
        )

        textView.textStorage?.beginEditing()
        textView.textStorage?.replaceCharacters(in: range, with: imageString)
        textView.textStorage?.endEditing()
        let cursor = range.location + imageString.length
        textView.setSelectedRange(NSRange(location: cursor, length: 0))
        textView.didChangeText()
        textView.scrollRangeToVisible(NSRange(location: cursor, length: 0))
        focus()
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let font = currentFont(in: textView, range: range)
        let manager = NSFontManager.shared
        let newFont: NSFont

        if manager.traits(of: font).contains(trait) {
            newFont = manager.convert(font, toNotHaveTrait: trait)
        } else {
            newFont = manager.convert(font, toHaveTrait: trait)
        }

        applyFont(newFont, in: textView, range: range)
        focus()
    }

    private func toggleStyleAttribute(_ key: NSAttributedString.Key, value: Any) {
        guard let textView else { return }
        let range = textView.selectedRange()

        if range.length > 0 {
            let existing = textView.textStorage?.attribute(key, at: range.location, effectiveRange: nil)
            if existing == nil {
                textView.textStorage?.addAttribute(key, value: value, range: range)
            } else {
                textView.textStorage?.removeAttribute(key, range: range)
            }
            textView.didChangeText()
        } else if textView.typingAttributes[key] == nil {
            textView.typingAttributes[key] = value
        } else {
            textView.typingAttributes.removeValue(forKey: key)
        }
        focus()
    }

    private func applyFont(_ font: NSFont, in textView: RichEditorTextView, range: NSRange) {
        if range.length > 0 {
            textView.textStorage?.addAttribute(.font, value: font, range: range)
            textView.didChangeText()
        } else {
            textView.typingAttributes[.font] = font
        }
    }

    private func currentFont(in textView: RichEditorTextView, range: NSRange) -> NSFont {
        if range.length > 0,
           let font = textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
            return font
        }
        if let font = textView.typingAttributes[.font] as? NSFont {
            return font
        }
        return baseFont
    }

    private func mutableParagraphStyle(in textView: RichEditorTextView, range: NSRange) -> NSMutableParagraphStyle {
        if range.length > 0,
           let style = textView.textStorage?.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
           let mutable = style.mutableCopy() as? NSMutableParagraphStyle {
            return mutable
        }
        if let style = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle,
           let mutable = style.mutableCopy() as? NSMutableParagraphStyle {
            return mutable
        }
        return NSMutableParagraphStyle()
    }

    private func showImageError() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法插入图片"
        alert.informativeText = "请选择本机上的有效图片文件。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
