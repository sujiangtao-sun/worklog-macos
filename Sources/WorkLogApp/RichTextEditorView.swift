import AppKit
import SwiftUI

struct RichTextEditorView: View {
    let controller: RichTextController
    var editorHeight: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            RichTextToolbar(controller: controller)
            Divider()
            RichTextEditorRepresentable(controller: controller, height: editorHeight)
                .frame(height: editorHeight)
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.borderColor, lineWidth: 1)
        )
    }
}

private struct RichTextToolbar: View {
    let controller: RichTextController

    var body: some View {
        HStack(spacing: 2) {
            toolbarButton("bold", "粗体") { controller.toggleBold() }
            toolbarButton("italic", "斜体") { controller.toggleItalic() }
            toolbarButton("underline", "下划线") { controller.toggleUnderline() }
            toolbarButton("strikethrough", "删除线") { controller.toggleStrikethrough() }

            divider

            toolbarTextButton("A−", "减小字号") { controller.changeFontSize(by: -1) }
            toolbarTextButton("A+", "增大字号") { controller.changeFontSize(by: 1) }

            divider

            toolbarButton("text.alignleft", "左对齐") { controller.setAlignment(.left) }
            toolbarButton("text.aligncenter", "居中") { controller.setAlignment(.center) }
            toolbarButton("text.alignright", "右对齐") { controller.setAlignment(.right) }

            Spacer(minLength: 4)

            toolbarButton("photo.badge.plus", "插入图片") { controller.chooseImage() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.025))
    }

    private var divider: some View {
        Divider()
            .frame(height: 14)
            .padding(.horizontal, 3)
    }

    private func toolbarButton(_ systemImage: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func toolbarTextButton(_ label: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

private struct RichTextEditorRepresentable: NSViewRepresentable {
    let controller: RichTextController
    let height: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        container.lineFragmentPadding = 4
        layoutManager.addTextContainer(container)

        let initialSize = NSSize(width: 640, height: max(height, 80))
        let textView = RichEditorTextView(
            frame: NSRect(origin: .zero, size: initialSize),
            textContainer: container
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor.labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFontPanel = false
        textView.usesRuler = false

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]

        if controller.initialContent.length > 0 {
            textView.textStorage?.setAttributedString(controller.initialContent)
        } else {
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: "", attributes: baseAttributes)
            )
        }
        textView.typingAttributes = baseAttributes
        textView.imagePasteHandler = { [weak controller] image in
            controller?.insertImage(image)
        }

        if controller.initialContent.length == 0 {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }

        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 640, height: max(height, 80))
        )
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        controller.attach(textView)
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? RichEditorTextView {
            controller.attach(textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var textView: RichEditorTextView?
    }
}

final class RichEditorTextView: NSTextView {
    var imagePasteHandler: ((NSImage) -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func paste(_ sender: Any?) {
        if let data = ImageSupport.imageData(from: NSPasteboard.general),
           let image = ImageSupport.image(from: data) {
            imagePasteHandler?(image)
            return
        }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let data = ImageSupport.imageData(from: sender.draggingPasteboard),
           let image = ImageSupport.image(from: data) {
            imagePasteHandler?(image)
            return true
        }
        return super.performDragOperation(sender)
    }
}
