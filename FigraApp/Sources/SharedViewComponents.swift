import AppKit
import PDFKit
import SwiftUI

struct Header<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

struct DropTarget: View {
    let title: String
    let subtitle: String
    let onDropPDFs: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 108)
        .background(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])).foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onDrop(of: [.fileURL, .url, .pdf], isTargeted: $isTargeted) { providers in
            loadPDFURLs(from: providers, completion: onDropPDFs)
            return true
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct StatusCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(message).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct PageThumbnailImage: View {
    let image: NSImage?
    let height: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct PDFPreview: NSViewRepresentable {
    let document: PDFDocument
    let focusedPageIndex: Int?

    final class Coordinator {
        var document: PDFDocument?
        var focusedPageIndex: Int?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .textBackgroundColor
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if context.coordinator.document !== document {
            nsView.document = document
            context.coordinator.document = document
            context.coordinator.focusedPageIndex = nil
        }
        guard context.coordinator.focusedPageIndex != focusedPageIndex else { return }
        context.coordinator.focusedPageIndex = focusedPageIndex
        if let focusedPageIndex, let page = document.page(at: focusedPageIndex) {
            nsView.go(to: page)
        }
    }
}
