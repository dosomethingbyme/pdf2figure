import AppKit
import PDFKit
import SwiftUI

final class AppModel: ObservableObject {
    private let pdfQueue = DispatchQueue(label: "figra.pdf-work", qos: .userInitiated)
    private let thumbnailQueue = DispatchQueue(label: "figra.thumbnail-work", qos: .utility)
    private var activeBackgroundJobs = 0
    private var pageThumbnailToken = UUID()
    private var splitThumbnailToken = UUID()
    private var organizeThumbnailToken = UUID()
    private var figureExtractionToken = UUID()

    @Published var selectedTool: Tool = .figureExtract
    @Published var dpi: DPI = .dpi600
    @Published var defaultOutputDirectory: URL?
    @Published var autoRevealOutputs = false
    @Published var recentTasks: [RecentTask] = []
    @Published var isWorking = false

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
        let token = UUID()
        pageThumbnailToken = token
        pagePDFURL = url
        pageDocument = document
        selectedPages = []
        focusedPageIndex = document.pageCount > 0 ? 0 : nil
        pageRangeText = ""
        lastPageSelection = nil
        pages = makePageItems(document: document)
        pageStatus = "\(url.lastPathComponent) · \(document.pageCount) 页 · 正在生成缩略图..."
        buildPageThumbnails(for: url, pageCount: document.pageCount, token: token, target: .pageExport)
    }

    func openPDFForFigures(_ url: URL) {
        figureExtractionToken = UUID()
        figurePDFURL = url
        figureResults = []
        figureOutputURL = nil
        figureLog = ""
        isExtractingFigures = false
        figureStatus = "\(url.lastPathComponent) 已选择。"
    }

    func openPDFForSplit(_ url: URL) {
        guard let document = PDFDocument(url: url) else {
            splitStatus = "无法读取 PDF：\(url.lastPathComponent)"
            return
        }
        let token = UUID()
        splitThumbnailToken = token
        splitPDFURL = url
        splitDocument = document
        splitSelectedPages = []
        splitFocusedPageIndex = document.pageCount > 0 ? 0 : nil
        splitRangeText = ""
        lastSplitPageSelection = nil
        splitPages = makePageItems(document: document)
        splitStatus = "\(url.lastPathComponent) · \(document.pageCount) 页 · 正在生成缩略图..."
        buildPageThumbnails(for: url, pageCount: document.pageCount, token: token, target: .split)
    }

    func openPDFForOrganize(_ url: URL) {
        guard let document = PDFDocument(url: url) else {
            organizeStatus = "无法读取 PDF：\(url.lastPathComponent)"
            return
        }
        let token = UUID()
        organizeThumbnailToken = token
        organizePDFURL = url
        organizeDocument = document
        organizePages = makePageItems(document: document)
        organizeOrder = Array(0..<document.pageCount)
        organizeStatus = "\(url.lastPathComponent) · \(document.pageCount) 页 · 正在生成缩略图..."
        buildPageThumbnails(for: url, pageCount: document.pageCount, token: token, target: .organize)
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
        guard let sourceURL = pagePDFURL else {
            pageStatus = "请先选择 PDF。"
            return
        }
        let pages = sortedSelectedPages()
        guard !pages.isEmpty else {
            pageStatus = "请先选择要导出的页面。"
            return
        }
        guard let directory = chooseDirectory(defaultURL: defaultOutputDirectory) else { return }
        let dpiValue = dpi.rawValue
        pageStatus = "正在导出 \(pages.count) 张图片..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            try exportPagesAsImages(document: document, pageIndexes: pages, sourceURL: sourceURL, dpi: dpiValue, directory: directory)
        } completion: { result in
            switch result {
            case .success:
                self.pageStatus = "已导出 \(pages.count) 张图片到：\(directory.path)"
                self.addRecentTask(tool: "页面提取", title: "\(sourceURL.lastPathComponent) 导出图片", detail: "\(pages.count) 张图片 · \(dpiValue) DPI", outputURL: directory)
                self.revealIfNeeded(directory)
            case .failure(let error):
                self.pageStatus = "导出图片失败：\(error.localizedDescription)"
            }
        }
    }

    func exportSelectedPagesAsSinglePDF() {
        guard let sourceURL = pagePDFURL else {
            pageStatus = "请先选择 PDF。"
            return
        }
        let pages = sortedSelectedPages()
        guard !pages.isEmpty else {
            pageStatus = "请先选择要导出的页面。"
            return
        }
        guard let url = chooseSavePDF(defaultName: "selected-pages.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        pageStatus = "正在导出 PDF..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            try writePDF(document: document, pageIndexes: pages, to: url)
        } completion: { result in
            switch result {
            case .success:
                self.pageStatus = "已导出 PDF：\(url.path)"
                self.addRecentTask(tool: "页面提取", title: "导出选中页面 PDF", detail: "\(pages.count) 页", outputURL: url)
                self.revealIfNeeded(url)
            case .failure(let error):
                self.pageStatus = "导出 PDF 失败：\(error.localizedDescription)"
            }
        }
    }

    func exportSelectedPagesAsIndividualPDFs() {
        guard let sourceURL = pagePDFURL else {
            pageStatus = "请先选择 PDF。"
            return
        }
        let pages = sortedSelectedPages()
        guard !pages.isEmpty else {
            pageStatus = "请先选择要导出的页面。"
            return
        }
        guard let directory = chooseDirectory(defaultURL: defaultOutputDirectory) else { return }
        pageStatus = "正在导出 \(pages.count) 个单页 PDF..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            try writeIndividualPDFs(document: document, pageIndexes: pages, sourceURL: sourceURL, directory: directory)
        } completion: { result in
            switch result {
            case .success:
                self.pageStatus = "已导出 \(pages.count) 个单页 PDF。"
                self.addRecentTask(tool: "页面提取", title: "\(sourceURL.lastPathComponent) 单页导出", detail: "\(pages.count) 个 PDF", outputURL: directory)
                self.revealIfNeeded(directory)
            case .failure(let error):
                self.pageStatus = "导出单页 PDF 失败：\(error.localizedDescription)"
            }
        }
    }

    func exportSelectedPagesAsGroupedPDFs() {
        guard let sourceURL = pagePDFURL else {
            pageStatus = "请先选择 PDF。"
            return
        }
        let groups = contiguousGroups(sortedSelectedPages())
        guard !groups.isEmpty else {
            pageStatus = "请先选择要导出的页面。"
            return
        }
        guard let directory = chooseDirectory(defaultURL: defaultOutputDirectory) else { return }
        pageStatus = "正在按连续页段导出..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            try writeGroupedPDFs(document: document, groups: groups, sourceURL: sourceURL, directory: directory)
        } completion: { result in
            switch result {
            case .success:
                self.pageStatus = "已按连续页段导出 \(groups.count) 个 PDF。"
                self.addRecentTask(tool: "页面提取", title: "\(sourceURL.lastPathComponent) 分组导出", detail: "\(groups.count) 个 PDF", outputURL: directory)
                self.revealIfNeeded(directory)
            case .failure(let error):
                self.pageStatus = "分组导出失败：\(error.localizedDescription)"
            }
        }
    }

    func runFigureExtraction() {
        guard let pdfURL = figurePDFURL else {
            figureStatus = "请先选择 PDF。"
            return
        }
        guard !isExtractingFigures else { return }
        let token = UUID()
        figureExtractionToken = token
        isExtractingFigures = true
        figureStatus = "正在提取 Figure/Table..."
        figureLog = "开始处理：\(pdfURL.path)"
        let dpiValue = dpi.rawValue

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.extractFigures(pdfURL: pdfURL, dpi: dpiValue)
            let figures = result.images.map {
                FigureResult(url: $0, thumbnail: Self.thumbnail(forImageAt: $0, size: NSSize(width: 140, height: 100)))
            }
            DispatchQueue.main.async {
                guard self.figureExtractionToken == token else { return }
                self.isExtractingFigures = false
                self.figureStatus = result.status
                self.figureLog = result.log
                self.figureOutputURL = result.outputURL
                self.figureResults = figures
                if let outputURL = result.outputURL {
                    self.addRecentTask(tool: "图表提取", title: pdfURL.lastPathComponent, detail: "\(result.images.count) 个 Figure/Table · \(dpiValue) DPI", outputURL: outputURL)
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
        let items = mergeItems
        mergeStatus = "正在合并 \(items.count) 个 PDF..."
        runPDFJob {
            let output = PDFDocument()
            for item in items {
                guard let document = PDFDocument(url: item.url) else { throw AppError("无法读取：\(item.url.lastPathComponent)") }
                for pageIndex in 0..<document.pageCount {
                    if let page = document.page(at: pageIndex) {
                        output.insert(page, at: output.pageCount)
                    }
                }
            }
            guard output.write(to: outputURL) else { throw AppError("写入合并 PDF 失败。") }
        } completion: { result in
            switch result {
            case .success:
                self.mergeStatus = "已导出：\(outputURL.path)"
                self.addRecentTask(tool: "合并 PDF", title: outputURL.lastPathComponent, detail: "\(items.count) 个文件", outputURL: outputURL)
                self.revealIfNeeded(outputURL)
            case .failure(let error):
                self.mergeStatus = "合并失败：\(error.localizedDescription)"
            }
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
        guard let sourceURL = organizePDFURL else {
            organizeStatus = "请先选择 PDF。"
            return
        }
        guard !organizeOrder.isEmpty else {
            organizeStatus = "至少保留一页。"
            return
        }
        guard let url = chooseSavePDF(defaultName: "\(safeName(sourceURL.deletingPathExtension().lastPathComponent))_organized.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        let order = organizeOrder
        organizeStatus = "正在导出整理后的 PDF..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            try writePDF(document: document, pageIndexes: order, to: url)
        } completion: { result in
            switch result {
            case .success:
                self.organizeStatus = "已导出整理副本：\(url.path)"
                self.addRecentTask(tool: "页面整理", title: sourceURL.lastPathComponent, detail: "\(order.count) 页", outputURL: url)
                self.revealIfNeeded(url)
            case .failure(let error):
                self.organizeStatus = "整理导出失败：\(error.localizedDescription)"
            }
        }
    }

    func splitExportSelectedAsOnePDF() {
        guard let sourceURL = splitPDFURL else {
            splitStatus = "请先选择 PDF。"
            return
        }
        let pages = sortedSplitSelectedPages()
        guard !pages.isEmpty else {
            splitStatus = "请先选择页面。"
            return
        }
        guard let url = chooseSavePDF(defaultName: "split-selection.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        splitStatus = "正在导出选中页面..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            try writePDF(document: document, pageIndexes: pages, to: url)
        } completion: { result in
            switch result {
            case .success:
                self.splitStatus = "已导出：\(url.path)"
                self.addRecentTask(tool: "拆分 PDF", title: url.lastPathComponent, detail: "\(pages.count) 页", outputURL: url)
                self.revealIfNeeded(url)
            case .failure(let error):
                self.splitStatus = "拆分失败：\(error.localizedDescription)"
            }
        }
    }

    func splitExportEachPage() {
        guard let document = splitDocument, let sourceURL = splitPDFURL else {
            splitStatus = "请先选择 PDF。"
            return
        }
        let pages = sortedSplitSelectedPages().isEmpty ? Array(0..<document.pageCount) : sortedSplitSelectedPages()
        guard let directory = chooseDirectory(defaultURL: defaultOutputDirectory) else { return }
        splitStatus = "正在导出 \(pages.count) 个单页 PDF..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            try writeIndividualPDFs(document: document, pageIndexes: pages, sourceURL: sourceURL, directory: directory)
        } completion: { result in
            switch result {
            case .success:
                self.splitStatus = "已导出 \(pages.count) 个单页 PDF。"
                self.addRecentTask(tool: "拆分 PDF", title: sourceURL.lastPathComponent, detail: "\(pages.count) 个单页 PDF", outputURL: directory)
                self.revealIfNeeded(directory)
            case .failure(let error):
                self.splitStatus = "拆分失败：\(error.localizedDescription)"
            }
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
        splitStatus = "正在按每 \(n) 页拆分..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            try writeGroupedPDFs(document: document, groups: groups, sourceURL: sourceURL, directory: directory)
        } completion: { result in
            switch result {
            case .success:
                self.splitStatus = "已按每 \(n) 页导出 \(groups.count) 个 PDF。"
                self.addRecentTask(tool: "拆分 PDF", title: sourceURL.lastPathComponent, detail: "每 \(n) 页 · \(groups.count) 个 PDF", outputURL: directory)
                self.revealIfNeeded(directory)
            case .failure(let error):
                self.splitStatus = "拆分失败：\(error.localizedDescription)"
            }
        }
    }

    func exportCompressedPDF() {
        guard let sourceURL = compressPDFURL else {
            compressStatus = "请先选择 PDF。"
            return
        }
        guard let outputURL = chooseSavePDF(defaultName: "\(safeName(sourceURL.deletingPathExtension().lastPathComponent))_optimized.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        compressStatus = "正在导出优化副本..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            guard document.write(to: outputURL) else { throw AppError("优化导出失败。") }
            return (before: fileSize(sourceURL), after: fileSize(outputURL))
        } completion: { result in
            switch result {
            case .success(let sizes):
                self.compressOutputURL = outputURL
                self.compressStatus = "已导出优化副本：\(formatFileSize(sizes.before)) → \(formatFileSize(sizes.after))。PDFKit 不重采样页面内图片。"
                self.addRecentTask(tool: "压缩 PDF", title: sourceURL.lastPathComponent, detail: "\(formatFileSize(sizes.before)) → \(formatFileSize(sizes.after))", outputURL: outputURL)
                self.revealIfNeeded(outputURL)
            case .failure(let error):
                self.compressStatus = "优化导出失败：\(error.localizedDescription)"
            }
        }
    }

    func exportPrivacyCleanPDF() {
        guard let pdfURL = privacyPDFURL else {
            privacyStatus = "请先选择 PDF。"
            return
        }
        guard let outputURL = chooseSavePDF(defaultName: "\(safeName(pdfURL.deletingPathExtension().lastPathComponent))_private.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        privacyStatus = "正在导出清理副本..."
        runPDFJob {
            guard let document = PDFDocument(url: pdfURL) else { throw AppError("无法读取 PDF。") }
            try writeSanitizedPDFCopy(document: document, to: outputURL)
        } completion: { result in
            switch result {
            case .success:
                self.privacyOutputURL = outputURL
                self.privacyStatus = "已导出清理副本：\(outputURL.path)"
                self.addRecentTask(tool: "清除隐私", title: pdfURL.lastPathComponent, detail: "清理 document info metadata", outputURL: outputURL)
                self.revealIfNeeded(outputURL)
            case .failure(let error):
                self.privacyStatus = "写入 PDF 失败：\(error.localizedDescription)"
            }
        }
    }

    func exportEncryptedPDF() {
        guard let sourceURL = securityPDFURL else {
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
        securityStatus = "正在导出加密副本..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            guard document.write(to: outputURL, withOptions: options) else { throw AppError("加密导出失败。") }
        } completion: { result in
            switch result {
            case .success:
                self.securityOutputURL = outputURL
                self.securityStatus = "已导出加密副本：\(outputURL.path)"
                self.addRecentTask(tool: "PDF 加密", title: sourceURL.lastPathComponent, detail: "已生成加密副本", outputURL: outputURL)
                self.revealIfNeeded(outputURL)
            case .failure(let error):
                self.securityStatus = "加密导出失败：\(error.localizedDescription)"
            }
        }
    }

    func exportUnlockedPDF() {
        guard let sourceURL = securityPDFURL else {
            securityStatus = "请先选择 PDF。"
            return
        }
        let password = securityPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let outputURL = chooseSavePDF(defaultName: "\(safeName(sourceURL.deletingPathExtension().lastPathComponent))_unlocked.pdf", defaultDirectory: defaultOutputDirectory) else { return }
        securityStatus = "正在导出无密码副本..."
        runPDFJob {
            guard let document = PDFDocument(url: sourceURL) else { throw AppError("无法读取 PDF。") }
            if document.isEncrypted {
                guard !password.isEmpty, document.unlock(withPassword: password) else {
                    throw AppError("密码错误或无法解锁 PDF。")
                }
            }
            try writeSanitizedPDFCopy(document: document, to: outputURL)
        } completion: { result in
            switch result {
            case .success:
                self.securityOutputURL = outputURL
                self.securityStatus = "已导出无密码副本：\(outputURL.path)"
                self.addRecentTask(tool: "PDF 加密", title: sourceURL.lastPathComponent, detail: "已导出无密码副本", outputURL: outputURL)
                self.revealIfNeeded(outputURL)
            case .failure(let error):
                self.securityStatus = "导出无密码副本失败：\(error.localizedDescription)"
            }
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

    private enum ThumbnailTarget {
        case pageExport
        case split
        case organize
    }

    private func runPDFJob<ResultValue>(_ work: @escaping () throws -> ResultValue, completion: @escaping (Result<ResultValue, Error>) -> Void) {
        activeBackgroundJobs += 1
        isWorking = true
        pdfQueue.async { [weak self] in
            let result = Result { try work() }
            DispatchQueue.main.async {
                completion(result)
                guard let self else { return }
                self.activeBackgroundJobs = max(0, self.activeBackgroundJobs - 1)
                self.isWorking = self.activeBackgroundJobs > 0
            }
        }
    }

    private func buildPageThumbnails(for url: URL, pageCount: Int, token: UUID, target: ThumbnailTarget) {
        thumbnailQueue.async { [weak self] in
            guard let self, let document = PDFDocument(url: url) else { return }
            let batchSize = 12
            var batch: [PageItem] = []
            for pageIndex in 0..<pageCount {
                guard let item = makePageThumbnail(document: document, pageIndex: pageIndex) else { continue }
                batch.append(item)
                if batch.count >= batchSize {
                    self.publishThumbnailBatch(batch, token: token, target: target, isComplete: false, pageCount: pageCount)
                    batch.removeAll(keepingCapacity: true)
                }
            }
            self.publishThumbnailBatch(batch, token: token, target: target, isComplete: true, pageCount: pageCount)
        }
    }

    private func publishThumbnailBatch(_ batch: [PageItem], token: UUID, target: ThumbnailTarget, isComplete: Bool, pageCount: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.thumbnailToken(for: target) == token else { return }
            if !batch.isEmpty {
                self.mergeThumbnailBatch(batch, into: target)
            }
            if isComplete {
                switch target {
                case .pageExport:
                    if self.pageStatus.contains("正在生成缩略图") {
                        self.pageStatus = "\(self.pagePDFURL?.lastPathComponent ?? "PDF") · \(pageCount) 页"
                    }
                case .split:
                    if self.splitStatus.contains("正在生成缩略图") {
                        self.splitStatus = "\(self.splitPDFURL?.lastPathComponent ?? "PDF") · \(pageCount) 页"
                    }
                case .organize:
                    if self.organizeStatus.contains("正在生成缩略图") {
                        self.organizeStatus = "\(self.organizePDFURL?.lastPathComponent ?? "PDF") · \(pageCount) 页。拖动缩略图重排，或移除页面后导出副本。"
                    }
                }
            }
        }
    }

    private func thumbnailToken(for target: ThumbnailTarget) -> UUID {
        switch target {
        case .pageExport: return pageThumbnailToken
        case .split: return splitThumbnailToken
        case .organize: return organizeThumbnailToken
        }
    }

    private func mergeThumbnailBatch(_ batch: [PageItem], into target: ThumbnailTarget) {
        switch target {
        case .pageExport:
            pages.applyThumbnails(batch)
        case .split:
            splitPages.applyThumbnails(batch)
        case .organize:
            organizePages.applyThumbnails(batch)
        }
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
