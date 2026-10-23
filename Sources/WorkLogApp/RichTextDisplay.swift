import AppKit
import Combine
import SwiftUI
import WorkLogCore

private struct PreviewImage: Identifiable {
    let id = UUID()
    let image: NSImage
}

private final class RichTextDisplayState: ObservableObject {
    @Published var loaded: RichTextLoadResult?
    @Published var displayContent: NSAttributedString?
    @Published var hasImages = false
    @Published var previewImage: PreviewImage?
}

struct RichTextDisplay: View {
    let store: RichTextStore
    let relativePath: String?
    let fallbackPlainText: String
    let revision: Date

    @StateObject private var state = RichTextDisplayState()

    var body: some View {
        Group {
            if let loaded = state.loaded, let content = state.displayContent {
                VStack(alignment: .leading, spacing: 6) {
                    if loaded.fileMissing {
                        Label("富文本附件文件缺失，当前显示纯文本内容", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if content.length > 0 {
                        AutoSizingRichText(
                            attributedString: content,
                            onImageClick: { image in
                                state.previewImage = PreviewImage(image: image)
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if state.hasImages {
                        Label("点击图片查看大图", systemImage: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear(perform: load)
        .onChange(of: revision) { _, _ in
            load()
        }
        .onChange(of: relativePath) { _, _ in
            load()
        }
        .sheet(item: $state.previewImage) { preview in
            ImagePreviewSheet(image: preview.image)
        }
    }

    private func load() {
        let loaded = store.load(
            relativePath: relativePath,
            fallbackPlainText: fallbackPlainText
        )
        let prepared = ImageSupport.prepareForDisplay(loaded.attributedString)

        state.loaded = loaded
        state.displayContent = prepared.attributedString
        state.hasImages = prepared.hasImages
    }
}

private struct AutoSizingRichText: NSViewRepresentable {
    let attributedString: NSAttributedString
    let onImageClick: (NSImage) -> Void

    func makeNSView(context: Context) -> RichDisplayTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = RichDisplayTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor.labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.onImageClick = onImageClick
        textView.textStorage?.setAttributedString(attributedString)
        return textView
    }

    func updateNSView(_ nsView: RichDisplayTextView, context: Context) {
        nsView.onImageClick = onImageClick
        if nsView.textStorage?.isEqual(to: attributedString) == false {
            nsView.textStorage?.setAttributedString(attributedString)
            nsView.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: RichDisplayTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let height = nsView.measureHeight(forWidth: width)
        return CGSize(width: width, height: height)
    }
}

private final class RichDisplayTextView: NSTextView {
    var onImageClick: ((NSImage) -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContainerWidth(newSize.width)
    }

    override func scrollWheel(with event: NSEvent) {
        if let enclosingScrollView {
            enclosingScrollView.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let attachment = clickedAttachment(at: event),
           let image = ImageSupport.image(for: attachment) {
            onImageClick?(image)
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let origin = textContainerOrigin
        textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                self.addCursorRect(
                    rect.offsetBy(dx: origin.x, dy: origin.y),
                    cursor: .pointingHand
                )
            }
        }
    }

    func measureHeight(forWidth width: CGFloat) -> CGFloat {
        updateContainerWidth(width)
        guard let textContainer, let layoutManager else { return 0 }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let height = used.height + textContainerInset.height * 2
        return ceil(max(height, 0))
    }

    private func updateContainerWidth(_ width: CGFloat) {
        guard let textContainer else { return }
        let available = max(width - textContainerInset.width * 2, 1)
        textContainer.containerSize = NSSize(width: available, height: .greatestFiniteMagnitude)
        textContainer.widthTracksTextView = false
    }

    private func clickedAttachment(at event: NSEvent) -> NSTextAttachment? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else {
            return nil
        }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let point = NSPoint(
            x: viewPoint.x - origin.x,
            y: viewPoint.y - origin.y
        )

        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -2, dy: -2).contains(point) else { return nil }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length,
              let attachment = textStorage.attribute(
                  .attachment,
                  at: characterIndex,
                  effectiveRange: nil
              ) as? NSTextAttachment else {
            return nil
        }
        return attachment
    }
}

private final class ImagePreviewState: ObservableObject {
    @Published var actualSize = false
}

private struct ImagePreviewSheet: View {
    let image: NSImage

    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = ImagePreviewState()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("图片预览", systemImage: "photo")
                    .font(.system(size: 15, weight: .semibold))

                Text(pixelSizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(state.actualSize ? "适应窗口" : "原始大小") {
                    state.actualSize.toggle()
                }
                .controlSize(.small)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("关闭预览")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            ZStack {
                Color.black

                if state.actualSize {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: image.size.width, height: image.size.height)
                    }
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Text(state.actualSize ? "使用滚动条查看完整原图" : "点击“原始大小”按 1:1 查看")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(width: 940, height: 640)
        .background(AppTheme.pageBackground)
    }

    private var pixelSizeLabel: String {
        if let representation = image.representations.first,
           representation.pixelsWide > 0,
           representation.pixelsHigh > 0 {
            return "\(representation.pixelsWide) × \(representation.pixelsHigh) px"
        }
        return "\(Int(image.size.width)) × \(Int(image.size.height))"
    }
}
