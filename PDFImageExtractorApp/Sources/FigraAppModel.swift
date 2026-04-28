import AppKit
import PDFKit
import SwiftUI

final class AppModel: ObservableObject {
    @Published var selectedTool: Tool = .figureExtract
    @Published var dpi: DPI = .dpi600
    @Published var defaultOutputDirectory: URL?
    @Published var autoRevealOutputs = false
    @Published var recentTasks: [RecentTask] = []

    @Published var pagePDFURL: URL?
    @Published var pageDocument: PDFDocument?
    @Published var pages: [PageItem] = []
    @Published var selectedPages: Set<Int> = []
    @Published var focusedPageIndex: Int?
    @Published var pageRangeText = ""
    @Published var pageStatus = "选择或拖入一个 PDF 开始。"
    private var lastPageSelection: Int?

    @Published var figurePDFURL: URL?
    @Published var figureResults: [FigureResult] = []
    @Published var figureOutputURL: URL?
    @Published var figureStatus = "选择一个论文 PDF 后自动提取图表。"
    @Published var figureLog = ""
    @Published var isExtractingFigures = false
    @Published var showingGallery = false

    @Published var mergeItems: [MergeItem] = []
    @Published var mergeStatus = "添加至少两个 PDF。"

    @Published var organizePDFURL: URL?
    @Published var organizeDocument: PDFDocument?
    @Published var organizePages: [PageItem] = []
    @Published var organizeOrder: [Int] = []
    @Published var organizeStatus = "选择一个 PDF 后重排或删除页面。"

    @Published var splitPDFURL: URL?
    @Published var splitDocument: PDFDocument?
    @Published var splitPages: [PageItem] = []
    @Published var splitSelectedPages: Set<Int> = []
    @Published var splitFocusedPageIndex: Int?
    @Published var splitRangeText = ""
    @Published var splitEveryN = "5"
    @Published var splitStatus = "选择一个 PDF 后设置拆分规则。"
    private var lastSplitPageSelection: Int?

    @Published var compressPDFURL: URL?
    @Published var compressDocument: PDFDocument?
    @Published var compressStatus = "选择一个 PDF 后导出体积优化副本。"
    @Published var compressOutputURL: URL?

    @Published var privacyPDFURL: URL?
    @Published var privacyDocument: PDFDocument?
    @Published var privacyStatus = "选择一个 PDF 查看可清理元数据。"
    @Published var privacyOutputURL: URL?

    @Published var securityPDFURL: URL?
    @Published var securityDocument: PDFDocument?
    @Published var securityPassword = ""
    @Published var securityOwnerPassword = ""
    @Published var securityStatus = "选择一个 PDF 后可加密或导出解锁副本。"
    @Published var securityOutputURL: URL?

    func openPDFForPages(_ url: URL) {
        guard let document = PDFDocument(url: url) else {
            pageStatus = "无法读取 PDF：\(url.lastPathComponent)"
            return
        }
        pagePDFURL = url
        pageDocument = document
        selectedPages = []
        focusedPageIndex = document.pageCount > 0 ? 0 : nil
        pageRangeText = ""
        lastPageSelection = nil
        pages = makePageItems(document: document)
        pageStatus = "\(url.lastPathComponent) · \(document.pageCount) 页"
    }

    func openPDFForFigures(_ url: URL) {
        figurePDFURL = url
        figureResults = []
        figureOutputURL = nil
        figureLog = ""
        figureStatus = "\(url.lastPathComponent) 已选择。"
    }

    func openPDFForSplit(_ url: URL) {
        guard let document = PDFDocument(url: url) else {
            splitStatus = "无法读取 PDF：\(url.lastPathComponent)"
            return
        }
        splitPDFURL = url
        splitDocument = document
        splitSelectedPages = []
        splitFocusedPageIndex = document.pageCount > 0 ? 0 : nil
        splitRangeText = ""
        lastSplitPageSelection = nil
        splitPages = makePageItems(document: document)
        splitStatus = "\(url.lastPathComponent) · \(document.pageCount) 页"
    }

    func openPDFForOrganize(_ url: URL) {
        guard let document = PDFDocument(url: url) else {
            organizeStatus = "无法读取 PDF：\(url.lastPathComponent)"
            return
        }
        organizePDFURL = url
        organizeDocument = document
        organizePages = makePageItems(document: document)
        organizeOrder = Array(0..<document.pageCount)
        organizeStatus = "\(url.lastPathComponent) · \(document.pageCount) 页。拖动缩略图重排，或移除页面后导出副本。"
    }

    func openPDFForCompress(_ url: URL) {
        guard let document = PDFDocument(url: url) else {
            compressStatus = "无法读取 PDF：\(url.lastPathComponent)"
            return
        }
        compressPDFURL = url
        compressDocument = document
        compressOutputURL = nil
        compressStatus = "\(url.lastPathComponent) · \(document.pageCount) 页 · \(formatFileSize(fileSize(url)))。"
    }

    func openPDFForPrivacy(_ url: URL) {
        guard let document = PDFDocument(url: url) else {
            privacyStatus = "无法读取 PDF：\(url.lastPathComponent)"
            return
        }
        privacyPDFURL = url
        privacyDocument = document
        privacyOutputURL = nil
        let count = document.documentAttributes?.count ?? 0
        privacyStatus = count == 0 ? "未检测到常见文档元数据，可导出清理副本。" : "检测到 \(count) 个元数据字段。"
    }

    func openPDFForSecurity(_ url: URL) {
        guard let document = PDFDocument(url: url) else {
            securityStatus = "无法读取 PDF：\(url.lastPathComponent)"
            return
        }
        securityPDFURL = url
        securityDocument = document
        securityOutputURL = nil
        securityStatus = document.isEncrypted ? "已选择加密 PDF。如需导出解锁副本，请输入密码。" : "已选择未加密 PDF，可设置密码导出加密副本。"
    }

    func selectPage(_ index: Int, inSplit: Bool = false) {
        let modifiers = NSApplication.shared.currentEvent?.modifierFlags ?? []
        let isCommand = modifiers.contains(.command)
        let isShift = modifiers.contains(.shift)

        if inSplit {
            splitFocusedPageIndex = index
            applySelection(index, selectedPages: &splitSelectedPages, lastSelection: &lastSplitPageSelection, command: isCommand, shift: isShift)
            splitRangeText = formatPageSet(splitSelectedPages)
        } else {
            focusedPageIndex = index
            applySelection(index, selectedPages: &selectedPages, lastSelection: &lastPageSelection, command: isCommand, shift: isShift)
            pageRangeText = formatPageSet(selectedPages)
        }
    }

    func copyPageImage(_ index: Int, inSplit: Bool = false) {
        let document = inSplit ? splitDocument : pageDocument
        guard let document else {
            if inSplit {
                splitStatus = "请先选择 PDF。"
            } else {
                pageStatus = "请先选择 PDF。"
            }
            return
        }
        guard copyPageToPasteboard(document: document, pageIndex: index, dpi: dpi.rawValue) else {
            if inSplit {
                splitStatus = "页面 \(index + 1) 复制失败。"
            } else {
                pageStatus = "页面 \(index + 1) 复制失败。"
            }
            return
        }
        if inSplit {
            splitFocusedPageIndex = index
            splitStatus = "已复制第 \(index + 1) 页为 \(dpi.rawValue) DPI 图片。"
        } else {
            focusedPageIndex = index
            pageStatus = "已复制第 \(index + 1) 页为 \(dpi.rawValue) DPI 图片。"
        }
    }

    func applyRange(_ text: String, pageCount: Int, inSplit: Bool = false) {
        do {
            let parsed = try parsePageRanges(text, pageCount: pageCount)
            if inSplit {
                splitSelectedPages = Set(parsed)
                splitFocusedPageIndex = parsed.first
                splitStatus = parsed.isEmpty ? "未选择页面。" : "已选择 \(parsed.count) 页。"
            } else {
                selectedPages = Set(parsed)
                focusedPageIndex = parsed.first
                pageStatus = parsed.isEmpty ? "未选择页面。" : "已选择 \(parsed.count) 页。"
            }
        } catch {
            if inSplit {
                splitStatus = error.localizedDescription
            } else {
                pageStatus = error.localizedDescription
            }
        }
    }

    func selectAllPages(pageCount: Int, inSplit: Bool = false) {
        guard pageCount > 0 else { return }
        let allPages = Set(0..<pageCount)
        if inSplit {
            splitSelectedPages = allPages
            splitFocusedPageIndex = 0
            splitRangeText = "1-\(pageCount)"
            splitStatus = "已选择全部 \(pageCount) 页。"
        } else {
            selectedPages = allPages
            focusedPageIndex = 0
            pageRangeText = "1-\(pageCount)"
            pageStatus = "已选择全部 \(pageCount) 页。"
        }
    }

    func clearPageSelection(inSplit: Bool = false) {
        if inSplit {
            splitSelectedPages = []
            splitRangeText = ""
            lastSplitPageSelection = nil
            splitStatus = "已清空页面选择。"
        } else {
            selectedPages = []
            pageRangeText = ""
            lastPageSelection = nil
            pageStatus = "已清空页面选择。"
        }
    }

    func exportSelectedPagesAsImages() {
        guard let document = pageDocument, let sourceURL = pagePDFURL else {
            pageStatus = "请先选择 PDF。"
            return
        }
        let pages = sortedSelectedPages()
        guard !pages.isEmpty else {
            pageStatus = "请先选择要导出的页面。"
            return
        }
        guard let directory = chooseDirectory(defaultURL: defaultOutputDirectory) else { return }
        do {
            try exportPagesAsImages(document: document, pageIndexes: pages, sourceURL: sourceURL, dpi: dpi.rawValue, directory: directory)
            pageStatus = "已导出 \(pages.count) 张图片到：\(directory.path)"
            addRecentTask(tool: "页面提取", title: "\(sourceURL.lastPathComponent) 导出图片", detail: "\(pages.count) 张图片 · \(dpi.rawValue) DPI", outputURL: directory)
            revealIfNeeded(directory)
        } catch {
            pageStatus = "导出图片失败：\(error.localizedDescription)"
        }
    }

    func exportSelectedPagesAsSinglePDF() {
        guard let document = pageDocument else {
            pageStatus = "请先选择 PDF。"
            return
        }
        let pages = sortedSelectedPages()
        guard !pages.isEmpty else {
            pageStatus = "请先选择要导出的页面。"
            return
        }
        guard let url = chooseSavePDF(defaultName: "selected-pages.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        do {
            try writePDF(document: document, pageIndexes: pages, to: url)
            pageStatus = "已导出 PDF：\(url.path)"
            addRecentTask(tool: "页面提取", title: "导出选中页面 PDF", detail: "\(pages.count) 页", outputURL: url)
            revealIfNeeded(url)
        } catch {
            pageStatus = "导出 PDF 失败：\(error.localizedDescription)"
        }
    }

    func exportSelectedPagesAsIndividualPDFs() {
        guard let document = pageDocument, let sourceURL = pagePDFURL else {
            pageStatus = "请先选择 PDF。"
            return
        }
        let pages = sortedSelectedPages()
        guard !pages.isEmpty else {
            pageStatus = "请先选择要导出的页面。"
            return
        }
        guard let directory = chooseDirectory(defaultURL: defaultOutputDirectory) else { return }
        do {
            try writeIndividualPDFs(document: document, pageIndexes: pages, sourceURL: sourceURL, directory: directory)
            pageStatus = "已导出 \(pages.count) 个单页 PDF。"
            addRecentTask(tool: "页面提取", title: "\(sourceURL.lastPathComponent) 单页导出", detail: "\(pages.count) 个 PDF", outputURL: directory)
            revealIfNeeded(directory)
        } catch {
            pageStatus = "导出单页 PDF 失败：\(error.localizedDescription)"
        }
    }

    func exportSelectedPagesAsGroupedPDFs() {
        guard let document = pageDocument, let sourceURL = pagePDFURL else {
            pageStatus = "请先选择 PDF。"
            return
        }
        let groups = contiguousGroups(sortedSelectedPages())
        guard !groups.isEmpty else {
            pageStatus = "请先选择要导出的页面。"
            return
        }
        guard let directory = chooseDirectory(defaultURL: defaultOutputDirectory) else { return }
        do {
            try writeGroupedPDFs(document: document, groups: groups, sourceURL: sourceURL, directory: directory)
            pageStatus = "已按连续页段导出 \(groups.count) 个 PDF。"
            addRecentTask(tool: "页面提取", title: "\(sourceURL.lastPathComponent) 分组导出", detail: "\(groups.count) 个 PDF", outputURL: directory)
            revealIfNeeded(directory)
        } catch {
            pageStatus = "分组导出失败：\(error.localizedDescription)"
        }
    }

    func runFigureExtraction() {
        guard let pdfURL = figurePDFURL else {
            figureStatus = "请先选择 PDF。"
            return
        }
        guard !isExtractingFigures else { return }
        isExtractingFigures = true
        figureStatus = "正在提取 Figure/Table..."
        figureLog = "开始处理：\(pdfURL.path)"

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.extractFigures(pdfURL: pdfURL, dpi: self.dpi.rawValue)
            DispatchQueue.main.async {
                self.isExtractingFigures = false
                self.figureStatus = result.status
                self.figureLog = result.log
                self.figureOutputURL = result.outputURL
                self.figureResults = result.images.map { FigureResult(url: $0, thumbnail: Self.thumbnail(forImageAt: $0, size: NSSize(width: 140, height: 100))) }
                if let outputURL = result.outputURL {
                    self.addRecentTask(tool: "图表提取", title: pdfURL.lastPathComponent, detail: "\(result.images.count) 个 Figure/Table · \(self.dpi.rawValue) DPI", outputURL: outputURL)
                    self.revealIfNeeded(outputURL)
                }
            }
        }
    }

    func addMergePDFs(_ urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else { continue }
            mergeItems.append(MergeItem(url: url, pageCount: document.pageCount, fileSize: fileSize(url)))
        }
        refreshMergeStatus()
    }

    func moveMergeItem(from source: IndexSet, to destination: Int) {
        mergeItems.move(fromOffsets: source, toOffset: destination)
    }

    func moveMergeItemUp(_ item: MergeItem) {
        guard let index = mergeItems.firstIndex(of: item), index > 0 else { return }
        mergeItems.swapAt(index, index - 1)
    }

    func moveMergeItemDown(_ item: MergeItem) {
        guard let index = mergeItems.firstIndex(of: item), index < mergeItems.count - 1 else { return }
        mergeItems.swapAt(index, index + 1)
    }

    func removeMergeItem(_ item: MergeItem) {
        mergeItems.removeAll { $0.id == item.id }
        refreshMergeStatus()
    }

    func exportMergedPDF() {
        guard mergeItems.count >= 2 else {
            mergeStatus = "至少需要两个 PDF。"
            return
        }
        guard let outputURL = chooseSavePDF(defaultName: "merged.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        do {
            let output = PDFDocument()
            for item in mergeItems {
                guard let document = PDFDocument(url: item.url) else { throw AppError("无法读取：\(item.url.lastPathComponent)") }
                for pageIndex in 0..<document.pageCount {
                    if let page = document.page(at: pageIndex) {
                        output.insert(page, at: output.pageCount)
                    }
                }
            }
            guard output.write(to: outputURL) else { throw AppError("写入合并 PDF 失败。") }
            mergeStatus = "已导出：\(outputURL.path)"
            addRecentTask(tool: "合并 PDF", title: outputURL.lastPathComponent, detail: "\(mergeItems.count) 个文件", outputURL: outputURL)
            revealIfNeeded(outputURL)
        } catch {
            mergeStatus = "合并失败：\(error.localizedDescription)"
        }
    }

    func moveOrganizePages(from source: IndexSet, to destination: Int) {
        organizeOrder.move(fromOffsets: source, toOffset: destination)
    }

    func resetOrganizeOrder() {
        guard let document = organizeDocument else {
            organizeStatus = "请先选择 PDF。"
            return
        }
        organizeOrder = Array(0..<document.pageCount)
        organizeStatus = "已恢复原始页序，共 \(document.pageCount) 页。"
    }

    func removeOrganizePage(_ pageIndex: Int) {
        organizeOrder.removeAll { $0 == pageIndex }
        organizeStatus = "当前保留 \(organizeOrder.count) 页。导出会生成新 PDF，原文件不变。"
    }

    func exportOrganizedPDF() {
        guard let document = organizeDocument, let sourceURL = organizePDFURL else {
            organizeStatus = "请先选择 PDF。"
            return
        }
        guard !organizeOrder.isEmpty else {
            organizeStatus = "至少保留一页。"
            return
        }
        guard let url = chooseSavePDF(defaultName: "\(safeName(sourceURL.deletingPathExtension().lastPathComponent))_organized.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        do {
            try writePDF(document: document, pageIndexes: organizeOrder, to: url)
            organizeStatus = "已导出整理副本：\(url.path)"
            addRecentTask(tool: "页面整理", title: sourceURL.lastPathComponent, detail: "\(organizeOrder.count) 页", outputURL: url)
            revealIfNeeded(url)
        } catch {
            organizeStatus = "整理导出失败：\(error.localizedDescription)"
        }
    }

    func splitExportSelectedAsOnePDF() {
        guard let document = splitDocument else {
            splitStatus = "请先选择 PDF。"
            return
        }
        let pages = sortedSplitSelectedPages()
        guard !pages.isEmpty else {
            splitStatus = "请先选择页面。"
            return
        }
        guard let url = chooseSavePDF(defaultName: "split-selection.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        do {
            try writePDF(document: document, pageIndexes: pages, to: url)
            splitStatus = "已导出：\(url.path)"
            addRecentTask(tool: "拆分 PDF", title: url.lastPathComponent, detail: "\(pages.count) 页", outputURL: url)
            revealIfNeeded(url)
        } catch {
            splitStatus = "拆分失败：\(error.localizedDescription)"
        }
    }

    func splitExportEachPage() {
        guard let document = splitDocument, let sourceURL = splitPDFURL else {
            splitStatus = "请先选择 PDF。"
            return
        }
        let pages = sortedSplitSelectedPages().isEmpty ? Array(0..<document.pageCount) : sortedSplitSelectedPages()
        guard let directory = chooseDirectory(defaultURL: defaultOutputDirectory) else { return }
        do {
            try writeIndividualPDFs(document: document, pageIndexes: pages, sourceURL: sourceURL, directory: directory)
            splitStatus = "已导出 \(pages.count) 个单页 PDF。"
            addRecentTask(tool: "拆分 PDF", title: sourceURL.lastPathComponent, detail: "\(pages.count) 个单页 PDF", outputURL: directory)
            revealIfNeeded(directory)
        } catch {
            splitStatus = "拆分失败：\(error.localizedDescription)"
        }
    }

    func splitExportEveryNPages() {
        guard let document = splitDocument, let sourceURL = splitPDFURL else {
            splitStatus = "请先选择 PDF。"
            return
        }
        guard let n = Int(splitEveryN.trimmingCharacters(in: .whitespacesAndNewlines)), n > 0 else {
            splitStatus = "请输入有效的 N。"
            return
        }
        guard let directory = chooseDirectory(defaultURL: defaultOutputDirectory) else { return }
        let groups = stride(from: 0, to: document.pageCount, by: n).map { start in
            Array(start..<min(start + n, document.pageCount))
        }
        do {
            try writeGroupedPDFs(document: document, groups: groups, sourceURL: sourceURL, directory: directory)
            splitStatus = "已按每 \(n) 页导出 \(groups.count) 个 PDF。"
            addRecentTask(tool: "拆分 PDF", title: sourceURL.lastPathComponent, detail: "每 \(n) 页 · \(groups.count) 个 PDF", outputURL: directory)
            revealIfNeeded(directory)
        } catch {
            splitStatus = "拆分失败：\(error.localizedDescription)"
        }
    }

    func exportCompressedPDF() {
        guard let document = compressDocument, let sourceURL = compressPDFURL else {
            compressStatus = "请先选择 PDF。"
            return
        }
        guard let outputURL = chooseSavePDF(defaultName: "\(safeName(sourceURL.deletingPathExtension().lastPathComponent))_optimized.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        if document.write(to: outputURL) {
            compressOutputURL = outputURL
            let before = fileSize(sourceURL)
            let after = fileSize(outputURL)
            compressStatus = "已导出优化副本：\(formatFileSize(before)) → \(formatFileSize(after))。PDFKit 不重采样页面内图片。"
            addRecentTask(tool: "压缩 PDF", title: sourceURL.lastPathComponent, detail: "\(formatFileSize(before)) → \(formatFileSize(after))", outputURL: outputURL)
            revealIfNeeded(outputURL)
        } else {
            compressStatus = "优化导出失败。"
        }
    }

    func exportPrivacyCleanPDF() {
        guard let pdfURL = privacyPDFURL, let document = PDFDocument(url: pdfURL) else {
            privacyStatus = "请先选择 PDF。"
            return
        }
        guard let outputURL = chooseSavePDF(defaultName: "\(safeName(pdfURL.deletingPathExtension().lastPathComponent))_private.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        document.documentAttributes = [:]
        if document.write(to: outputURL) {
            privacyOutputURL = outputURL
            privacyStatus = "已导出清理副本：\(outputURL.path)"
            addRecentTask(tool: "清除隐私", title: pdfURL.lastPathComponent, detail: "清理 document info metadata", outputURL: outputURL)
            revealIfNeeded(outputURL)
        } else {
            privacyStatus = "写入 PDF 失败。"
        }
    }

    func exportEncryptedPDF() {
        guard let document = securityDocument, let sourceURL = securityPDFURL else {
            securityStatus = "请先选择 PDF。"
            return
        }
        let userPassword = securityPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerPassword = securityOwnerPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userPassword.isEmpty else {
            securityStatus = "请设置打开 PDF 的密码。"
            return
        }
        guard let outputURL = chooseSavePDF(defaultName: "\(safeName(sourceURL.deletingPathExtension().lastPathComponent))_encrypted.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: userPassword,
            .ownerPasswordOption: ownerPassword.isEmpty ? userPassword : ownerPassword
        ]
        if document.write(to: outputURL, withOptions: options) {
            securityOutputURL = outputURL
            securityStatus = "已导出加密副本：\(outputURL.path)"
            addRecentTask(tool: "PDF 加密", title: sourceURL.lastPathComponent, detail: "已生成加密副本", outputURL: outputURL)
            revealIfNeeded(outputURL)
        } else {
            securityStatus = "加密导出失败。"
        }
    }

    func exportUnlockedPDF() {
        guard let sourceURL = securityPDFURL, let document = PDFDocument(url: sourceURL) else {
            securityStatus = "请先选择 PDF。"
            return
        }
        if document.isEncrypted {
            let password = securityPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !password.isEmpty, document.unlock(withPassword: password) else {
                securityStatus = "密码错误或无法解锁 PDF。"
                return
            }
        }
        guard let outputURL = chooseSavePDF(defaultName: "\(safeName(sourceURL.deletingPathExtension().lastPathComponent))_unlocked.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        if document.write(to: outputURL) {
            securityOutputURL = outputURL
            securityStatus = "已导出无密码副本：\(outputURL.path)"
            addRecentTask(tool: "PDF 加密", title: sourceURL.lastPathComponent, detail: "已导出无密码副本", outputURL: outputURL)
            revealIfNeeded(outputURL)
        } else {
            securityStatus = "导出无密码副本失败。"
        }
    }

    func removeFigureResult(_ result: FigureResult) {
        figureResults.removeAll { $0.id == result.id }
        figureStatus = "当前保留 \(figureResults.count) 个 Figure/Table。文件不会从磁盘删除。"
    }

    func setDefaultOutputDirectory() {
        if let directory = chooseDirectory(defaultURL: defaultOutputDirectory) {
            defaultOutputDirectory = directory
        }
    }

    func clearRecentTasks() {
        recentTasks.removeAll()
    }

    func selectedPrivacyMetadataText() -> String {
        guard let document = privacyDocument else { return "选择 PDF 后显示 document info metadata。页面正文、批注和图片内容不会被扫描。" }
        guard let attrs = document.documentAttributes, !attrs.isEmpty else { return "未检测到常见 document info metadata。" }
        return attrs.keys.sorted { "\($0)" < "\($1)" }.map { "\($0): \(attrs[$0] ?? "")" }.joined(separator: "\n")
    }

    private func sortedSelectedPages() -> [Int] {
        selectedPages.sorted()
    }

    private func sortedSplitSelectedPages() -> [Int] {
        splitSelectedPages.sorted()
    }

    private func refreshMergeStatus() {
        mergeStatus = mergeItems.isEmpty ? "添加至少两个 PDF。" : "\(mergeItems.count) 个文件，合计 \(mergeItems.reduce(0) { $0 + $1.pageCount }) 页。"
    }

    private func addRecentTask(tool: String, title: String, detail: String, outputURL: URL?) {
        recentTasks.insert(RecentTask(tool: tool, title: title, detail: detail, outputURL: outputURL, date: Date()), at: 0)
        if recentTasks.count > 30 {
            recentTasks = Array(recentTasks.prefix(30))
        }
    }

    private func revealIfNeeded(_ url: URL) {
        guard autoRevealOutputs else { return }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
