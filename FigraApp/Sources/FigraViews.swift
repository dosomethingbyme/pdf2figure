import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct FigraAppView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            List(Tool.allCases, selection: $model.selectedTool) { tool in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.rawValue)
                            .font(.headline)
                        Text(tool.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: tool.symbol)
                }
                .tag(tool)
                .padding(.vertical, 6)
            }
            .navigationTitle("Figra")
            .frame(minWidth: 260)
        } detail: {
            Group {
                switch model.selectedTool {
                case .figureExtract:
                    FigureExtractView(model: model)
                case .pageExport:
                    PageExportView(model: model, mode: .pageExport)
                case .pageOrganize:
                    PageOrganizeView(model: model)
                case .merge:
                    MergePDFView(model: model)
                case .split:
                    PageExportView(model: model, mode: .split)
                case .compress:
                    CompressPDFView(model: model)
                case .privacy:
                    PrivacyView(model: model)
                case .security:
                    SecurityPDFView(model: model)
                case .history:
                    HistoryView(model: model)
                case .settings:
                    SettingsView(model: model)
                }
            }
            .frame(minWidth: 900, minHeight: 680)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .topTrailing) {
                if model.isWorking || model.isExtractingFigures {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("处理中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .padding(18)
                }
            }
        }
    }
}

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
                Button(isSplit ? "选择 PDF" : "选择 PDF") {
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

struct PageSelectionControls: View {
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

struct PageThumbnailPanel: View {
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

struct FigureExtractView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "图表提取", subtitle: "自动识别论文图片和表格，输出 PNG。") {
                Button("选择 PDF") {
                    if let url = choosePDF() {
                        model.openPDFForFigures(url)
                    }
                }
            }

            DropTarget(title: "拖入一个论文 PDF", subtitle: "提取结果不会挤在主页面，完成后进入图库查看。") { urls in
                if let url = urls.first {
                    model.openPDFForFigures(url)
                }
            }

            HStack(spacing: 14) {
                Picker("DPI", selection: $model.dpi) {
                    ForEach(DPI.allCases) { dpi in Text(dpi.label).tag(dpi) }
                }
                .frame(width: 160)

                Button(model.isExtractingFigures ? "正在提取..." : "开始提取") {
                    model.runFigureExtraction()
                }
                .disabled(model.isExtractingFigures)

                Button("查看全部图表") {
                    model.showingGallery = true
                }
                .disabled(model.figureResults.isEmpty)

                if let outputURL = model.figureOutputURL {
                    Button("打开输出文件夹") {
                        NSWorkspace.shared.open(outputURL)
                    }
                }
            }

            StatusCard(title: model.figurePDFURL?.lastPathComponent ?? "未选择 PDF", message: model.figureStatus)

            DisclosureGroup("日志") {
                ScrollView {
                    Text(model.figureLog.isEmpty ? "暂无日志。" : model.figureLog)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(minHeight: 160)
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.18)))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding(28)
        .sheet(isPresented: $model.showingGallery) {
            FigureGalleryView(model: model)
                .frame(minWidth: 980, minHeight: 680)
        }
    }
}

struct FigureGalleryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: FigureResult?
    @State private var filter: FigureKind = .all

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private var filteredResults: [FigureResult] {
        filter == .all ? model.figureResults : model.figureResults.filter { $0.kind == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("全部图表")
                    .font(.title2.bold())
                Picker("筛选", selection: $filter) {
                    ForEach(FigureKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredResults) { figure in
                            Button {
                                selected = figure
                                copyImage(figure.url)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let thumbnail = figure.thumbnail {
                                        Image(nsImage: thumbnail).resizable().scaledToFit().frame(height: 110)
                                    } else {
                                        Image(systemName: "photo").font(.largeTitle).frame(height: 110)
                                    }
                                    HStack {
                                        Text(figure.kind.rawValue)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.12))
                                            .clipShape(Capsule())
                                        Text(figure.name).font(.caption).lineLimit(1)
                                    }
                                }
                                .padding(10)
                                .background(selected?.id == figure.id ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .frame(width: 380)

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(selected?.name ?? "选择图表")
                            .font(.title2.bold())
                        Spacer()
                        if let selected {
                            Text(selected.kind.rawValue)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    if let url = selected?.url, let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        EmptyState(symbol: "photo.on.rectangle", title: "点击缩略图复制图表", message: "点击左侧缩略图会立即复制到剪贴板，并在这里显示大图。")
                    }
                    HStack {
                        Button("复制图片") { if let url = selected?.url { copyImage(url) } }
                        Button("打开图片") { if let url = selected?.url { NSWorkspace.shared.open(url) } }
                        Button("在 Finder 中显示") { if let url = selected?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                        Button("从结果移除") {
                            if let selected {
                                model.removeFigureResult(selected)
                                self.selected = filteredResults.first
                            }
                        }
                        Button("导出清单 CSV") { exportFigureCSV(model.figureResults) }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            selected = model.figureResults.first
        }
        .onChange(of: filter) { _ in
            selected = filteredResults.first
        }
    }
}

struct MergePDFView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "合并 PDF", subtitle: "左侧拖动把手排序，每项右侧也提供上移、下移和移除。") {
                Button("添加 PDF") {
                    model.addMergePDFs(choosePDFs())
                }
            }

            DropTarget(title: "拖入多个 PDF", subtitle: "原 PDF 不会被修改。") { urls in
                model.addMergePDFs(urls)
            }

            Text(model.mergeStatus).foregroundStyle(.secondary)

            List {
                ForEach(model.mergeItems) { item in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading) {
                            Text(item.url.lastPathComponent).font(.headline)
                            Text("\(item.pageCount) 页 · \(formatFileSize(item.fileSize))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("上移") { model.moveMergeItemUp(item) }
                        Button("下移") { model.moveMergeItemDown(item) }
                        Button("移除") { model.removeMergeItem(item) }
                    }
                    .padding(.vertical, 6)
                }
                .onMove(perform: model.moveMergeItem)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack {
                Spacer()
                Button("导出合并 PDF") { model.exportMergedPDF() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking)
            }
        }
        .padding(28)
    }
}

struct PageOrganizeView: View {
    @ObservedObject var model: AppModel
    @State private var draggingPage: Int?

    private let columns = [GridItem(.adaptive(minimum: 164), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "页面整理", subtitle: "重排或移除页面后导出新 PDF，原文件不会被修改。") {
                HStack {
                    Button("恢复原始顺序") {
                        model.resetOrganizeOrder()
                    }
                    .disabled(model.organizePages.isEmpty)
                    Button("选择 PDF") {
                        if let url = choosePDF() {
                            model.openPDFForOrganize(url)
                        }
                    }
                }
            }

            DropTarget(title: "拖入一个 PDF", subtitle: "载入后以相册缩略图显示，可直接拖动页面重排。") { urls in
                if let url = urls.first {
                    model.openPDFForOrganize(url)
                }
            }

            Text(model.organizeStatus).foregroundStyle(.secondary)

            if model.organizeOrder.isEmpty {
                EmptyState(symbol: "square.grid.3x3", title: "等待 PDF", message: "选择或拖入 PDF 后，页面会以相册网格展示。")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.organizeOrder, id: \.self) { pageIndex in
                            if let item = model.organizePages.first(where: { $0.index == pageIndex }) {
                                OrganizePageCard(
                                    item: item,
                                    position: (model.organizeOrder.firstIndex(of: pageIndex) ?? 0) + 1,
                                    isDragging: draggingPage == pageIndex,
                                    onRemove: { model.removeOrganizePage(pageIndex) }
                                )
                                .onDrag {
                                    draggingPage = pageIndex
                                    return NSItemProvider(object: "\(pageIndex)" as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: OrganizePageDropDelegate(
                                        pageIndex: pageIndex,
                                        order: $model.organizeOrder,
                                        draggingPage: $draggingPage
                                    )
                                )
                            }
                        }
                    }
                    .padding(4)
                }
                .padding(14)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.18)))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack {
                Text("拖动任意缩略图即可改变导出页序；删除只影响新导出的副本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("导出整理后的 PDF") { model.exportOrganizedPDF() }
                    .disabled(model.organizeOrder.isEmpty || model.isWorking)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
    }
}

struct OrganizePageCard: View {
    let item: PageItem
    let position: Int
    let isDragging: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                PageThumbnailImage(image: item.thumbnail, height: 190)
                    .padding(10)

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("第 \(item.index + 1) 页")
                        .font(.headline)
                    Text("导出顺序 \(position)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isDragging ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isDragging ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(isDragging ? 0.12 : 0.04), radius: isDragging ? 12 : 4, x: 0, y: isDragging ? 8 : 2)
        .opacity(isDragging ? 0.72 : 1)
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

struct OrganizePageDropDelegate: DropDelegate {
    let pageIndex: Int
    @Binding var order: [Int]
    @Binding var draggingPage: Int?

    func dropEntered(info: DropInfo) {
        guard
            let draggingPage,
            draggingPage != pageIndex,
            let fromIndex = order.firstIndex(of: draggingPage),
            let toIndex = order.firstIndex(of: pageIndex)
        else {
            return
        }

        withAnimation(.snappy(duration: 0.18)) {
            order.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingPage = nil
        return true
    }
}

struct CompressPDFView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "压缩 PDF", subtitle: "使用 PDFKit 重写 PDF 结构并生成优化副本，完成后显示体积变化。") {
                Button("选择 PDF") {
                    if let url = choosePDF() {
                        model.openPDFForCompress(url)
                    }
                }
            }

            DropTarget(title: "拖入一个 PDF", subtitle: "适合清理结构冗余；扫描图片不会被有损重采样。") { urls in
                if let url = urls.first {
                    model.openPDFForCompress(url)
                }
            }

            StatusCard(title: model.compressPDFURL?.lastPathComponent ?? "未选择 PDF", message: model.compressStatus)

            HStack {
                Button("导出优化副本") { model.exportCompressedPDF() }
                    .disabled(model.compressPDFURL == nil || model.isWorking)
                if let outputURL = model.compressOutputURL {
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    }
                }
                Spacer()
            }
            Spacer()
        }
        .padding(28)
    }
}

struct SecurityPDFView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "PDF 加密", subtitle: "为 PDF 导出加密副本，或在提供密码后导出无密码副本。") {
                Button("选择 PDF") {
                    if let url = choosePDF() {
                        model.openPDFForSecurity(url)
                    }
                }
            }

            DropTarget(title: "拖入一个 PDF", subtitle: "密码只用于本次导出，不会保存。") { urls in
                if let url = urls.first {
                    model.openPDFForSecurity(url)
                }
            }

            StatusCard(title: model.securityPDFURL?.lastPathComponent ?? "未选择 PDF", message: model.securityStatus)

            VStack(alignment: .leading, spacing: 12) {
                SecureField("打开密码", text: $model.securityPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("所有者密码（可选）", text: $model.securityOwnerPassword)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("导出加密副本") { model.exportEncryptedPDF() }
                        .disabled(model.securityPDFURL == nil || model.isWorking)
                    Button("导出无密码副本") { model.exportUnlockedPDF() }
                        .disabled(model.securityPDFURL == nil || model.isWorking)
                    if let outputURL = model.securityOutputURL {
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                        }
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.18)))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding(28)
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "最近任务", subtitle: "记录本次运行中的输出结果，方便回到文件或文件夹。") {
                Button("清空") { model.clearRecentTasks() }
                    .disabled(model.recentTasks.isEmpty)
            }

            if model.recentTasks.isEmpty {
                EmptyState(symbol: "clock", title: "暂无历史", message: "完成导出、提取、合并或清理后会出现在这里。")
            } else {
                List(model.recentTasks) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).font(.headline)
                            Text("\(task.tool) · \(task.detail) · \(task.date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let outputURL = task.outputURL {
                            Button("打开") {
                                NSWorkspace.shared.open(outputURL)
                            }
                            Button("定位") {
                                if (try? outputURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                                    NSWorkspace.shared.open(outputURL)
                                } else {
                                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(28)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "输出设置", subtitle: "设置默认输出目录、DPI 和导出后的行为。") {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("默认 DPI")
                    Spacer()
                    Picker("默认 DPI", selection: $model.dpi) {
                        ForEach(DPI.allCases) { dpi in
                            Text(dpi.label).tag(dpi)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("默认输出目录")
                        Text(model.defaultOutputDirectory?.path ?? "未设置，导出时手动选择")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("选择目录") { model.setDefaultOutputDirectory() }
                    Button("清除") { model.defaultOutputDirectory = nil }
                        .disabled(model.defaultOutputDirectory == nil)
                }
                Toggle("导出完成后自动打开或定位输出", isOn: $model.autoRevealOutputs)
            }
            .padding(16)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.18)))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .padding(28)
    }
}

struct PrivacyView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "清除隐私", subtitle: "仅清理 PDF document info metadata，不扫描页面内容。") {
                Button("选择 PDF") {
                    if let url = choosePDF() {
                        model.openPDFForPrivacy(url)
                    }
                }
            }

            DropTarget(title: "拖入一个 PDF", subtitle: "扫描 document info metadata，并导出清理副本。") { urls in
                if let url = urls.first {
                    model.openPDFForPrivacy(url)
                }
            }

            StatusCard(title: model.privacyPDFURL?.lastPathComponent ?? "未选择 PDF", message: model.privacyStatus)

            TextEditor(text: .constant(model.selectedPrivacyMetadataText()))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack {
                Button("导出清理副本") { model.exportPrivacyCleanPDF() }
                    .disabled(model.privacyPDFURL == nil || model.isWorking)
                if let outputURL = model.privacyOutputURL {
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    }
                }
                Spacer()
            }
        }
        .padding(28)
    }
}

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
