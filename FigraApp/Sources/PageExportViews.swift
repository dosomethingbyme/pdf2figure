import AppKit
import PDFKit
import SwiftUI

enum PageToolMode {
    case pageExport
    case split
}

struct PageExportView: View {
    @ObservedObject var model: AppModel
    let mode: PageToolMode

    private var isSplit: Bool { mode == .split }
    private var title: String { isSplit ? "拆分 PDF" : "页面提取" }
    private var status: String { isSplit ? model.splitStatus : model.pageStatus }
    private var document: PDFDocument? { isSplit ? model.splitDocument : model.pageDocument }
    private var pageItems: [PageItem] { isSplit ? model.splitPages : model.pages }
    private var selectedPages: Set<Int> { isSplit ? model.splitSelectedPages : model.selectedPages }
    private var focusedPageIndex: Int? { isSplit ? model.splitFocusedPageIndex : model.focusedPageIndex }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: title, subtitle: isSplit ? "复用页面选择器导出拆分后的 PDF。" : "预览全部页面，选择页面后导出图片或 PDF。") {
                Button("选择 PDF") {
                    if let url = choosePDF() {
                        isSplit ? model.openPDFForSplit(url) : model.openPDFForPages(url)
                    }
                }
            }

            DropTarget(title: "拖入一个 PDF", subtitle: "页面缩略图会在下方显示。") { urls in
                guard let url = urls.first else { return }
                isSplit ? model.openPDFForSplit(url) : model.openPDFForPages(url)
            }

            HStack(spacing: 12) {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Picker("DPI", selection: $model.dpi) {
                    ForEach(DPI.allCases) { dpi in
                        Text(dpi.label).tag(dpi)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }

            HStack(alignment: .top, spacing: 18) {
                PageThumbnailPanel(
                    pages: pageItems,
                    selectedPages: selectedPages,
                    onSelect: { model.selectPage($0, inSplit: isSplit) },
                    onCopy: { model.copyPageImage($0, inSplit: isSplit) }
                )

                VStack(alignment: .leading, spacing: 14) {
                    PageSelectionControls(model: model, mode: mode, pageCount: document?.pageCount ?? 0)

                    if let document {
                        PDFPreview(document: document, focusedPageIndex: focusedPageIndex)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2)))
                    } else {
                        EmptyState(symbol: "doc", title: "未选择 PDF", message: "选择或拖入 PDF 后，这里会显示页面预览。")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(28)
    }
}

private struct PageSelectionControls: View {
    @ObservedObject var model: AppModel
    let mode: PageToolMode
    let pageCount: Int

    private var isSplit: Bool { mode == .split }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("页面选择")
                    .font(.headline)
                Spacer()
                Text("共 \(pageCount) 页")
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("页码范围，例如 1-3, 8, 10-12", text: isSplit ? $model.splitRangeText : $model.pageRangeText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.applyRange(isSplit ? model.splitRangeText : model.pageRangeText, pageCount: pageCount, inSplit: isSplit)
                    }
                Button("应用范围") {
                    model.applyRange(isSplit ? model.splitRangeText : model.pageRangeText, pageCount: pageCount, inSplit: isSplit)
                }
                Button("全选") {
                    model.selectAllPages(pageCount: pageCount, inSplit: isSplit)
                }
                .disabled(pageCount == 0)
                Button("清空") {
                    model.clearPageSelection(inSplit: isSplit)
                }
            }

            if isSplit {
                HStack {
                    Button("选中页保存为一个 PDF") { model.splitExportSelectedAsOnePDF() }
                    Button("每页保存为 PDF") { model.splitExportEachPage() }
                    TextField("N", text: $model.splitEveryN)
                        .frame(width: 52)
                        .textFieldStyle(.roundedBorder)
                    Button("每 N 页保存为 PDF") { model.splitExportEveryNPages() }
                }
                .disabled(model.isWorking)
            } else {
                HStack {
                    Button("保存为图片") { model.exportSelectedPagesAsImages() }
                    Button("保存为一个 PDF") { model.exportSelectedPagesAsSinglePDF() }
                    Button("每页保存为 PDF") { model.exportSelectedPagesAsIndividualPDFs() }
                    Button("按连续分组保存 PDF") { model.exportSelectedPagesAsGroupedPDFs() }
                }
                .disabled(model.isWorking)
            }
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct PageThumbnailPanel: View {
    let pages: [PageItem]
    let selectedPages: Set<Int>
    let onSelect: (Int) -> Void
    let onCopy: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 116), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("页面")
                .font(.headline)
            if pages.isEmpty {
                EmptyState(symbol: "doc.text.magnifyingglass", title: "等待 PDF", message: "页面缩略图会显示在这里。")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pages) { page in
                            Button {
                                onSelect(page.index)
                            } label: {
                                VStack(spacing: 8) {
                                    PageThumbnailImage(image: page.thumbnail, height: 128)
                                    Text("第 \(page.index + 1) 页")
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(selectedPages.contains(page.index) ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selectedPages.contains(page.index) ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: selectedPages.contains(page.index) ? 2 : 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("复制页面图片") {
                                    onCopy(page.index)
                                }
                            }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .padding(16)
        .frame(width: 390)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
