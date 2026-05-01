import AppKit
import Foundation

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case figureExtract = "图表提取"
    case pageExport = "页面提取"
    case pageOrganize = "页面整理"
    case merge = "合并 PDF"
    case bibMerge = "BibTeX 工具"
    case split = "拆分 PDF"
    case compress = "压缩 PDF"
    case privacy = "清除隐私"
    case security = "PDF 加密"
    case history = "最近任务"
    case settings = "输出设置"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .figureExtract: return "photo.on.rectangle.angled"
        case .pageExport: return "doc.viewfinder"
        case .pageOrganize: return "square.grid.3x3"
        case .merge: return "rectangle.stack.badge.plus"
        case .bibMerge: return "text.badge.plus"
        case .split: return "square.split.2x1"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .privacy: return "hand.raised"
        case .security: return "lock.doc"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }

    var subtitle: String {
        switch self {
        case .figureExtract: return "自动识别论文 Figure/Table"
        case .pageExport: return "选择 PDF 页面，导出图片或 PDF"
        case .pageOrganize: return "重排、删除页面后导出副本"
        case .merge: return "排序并合并多个 PDF"
        case .bibMerge: return "合并、去重、格式化 .bib"
        case .split: return "按页面规则拆分 PDF"
        case .compress: return "生成体积优化副本"
        case .privacy: return "清理文档元数据"
        case .security: return "加密或解锁 PDF 副本"
        case .history: return "回到最近输出结果"
        case .settings: return "默认输出目录和 DPI"
        }
    }
}

enum DPI: Int, CaseIterable, Identifiable {
    case dpi150 = 150
    case dpi300 = 300
    case dpi600 = 600
    case dpi900 = 900

    var id: Int { rawValue }
    var label: String { "\(rawValue) DPI" }
}

struct PageItem: Identifiable {
    var id: Int { index }
    let index: Int
    var thumbnail: NSImage?
}

struct FigureResult: Identifiable {
    let id = UUID()
    let url: URL
    let thumbnail: NSImage?

    var name: String { url.lastPathComponent }
    var kind: FigureKind { inferFigureKind(from: name) }
}

struct MergeItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let pageCount: Int
    let fileSize: Int
}

struct BibItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let fileSize: Int
    let referenceCount: Int
}

enum BibDuplicatePolicy: String, CaseIterable, Identifiable {
    case keepAll = "保留全部"
    case keyAndTitle = "清理重复项"

    var id: String { rawValue }
}

enum BibOutputStyle: String, CaseIterable, Identifiable {
    case original = "保持原样"
    case formatted = "格式化"

    var id: String { rawValue }
}

enum BibTask: String, CaseIterable, Identifiable {
    case merge = "合并"
    case deduplicate = "合并去重"
    case format = "格式化"
    case deduplicateAndFormat = "去重格式化"

    var id: String { rawValue }

    var duplicatePolicy: BibDuplicatePolicy {
        switch self {
        case .merge, .format:
            return .keepAll
        case .deduplicate, .deduplicateAndFormat:
            return .keyAndTitle
        }
    }

    var outputStyle: BibOutputStyle {
        switch self {
        case .merge, .deduplicate:
            return .original
        case .format, .deduplicateAndFormat:
            return .formatted
        }
    }

    var processingOptions: BibProcessingOptions {
        BibProcessingOptions(duplicatePolicy: duplicatePolicy, outputStyle: outputStyle)
    }

    var description: String {
        switch self {
        case .merge:
            return "保留所有条目，按列表顺序输出。"
        case .deduplicate:
            return "按引用键或标题识别重复，保留最先出现的条目。"
        case .format:
            return "不删除条目，只统一条目缩进、字段换行和空行。"
        case .deduplicateAndFormat:
            return "先清理重复项，再输出统一格式。"
        }
    }

    var exportButtonTitle: String {
        switch self {
        case .merge:
            return "导出合并 BibTeX"
        case .deduplicate:
            return "导出去重 BibTeX"
        case .format:
            return "导出格式化 BibTeX"
        case .deduplicateAndFormat:
            return "导出去重并格式化 BibTeX"
        }
    }

    var recentTaskDetailPrefix: String {
        switch self {
        case .merge:
            return "合并"
        case .deduplicate:
            return "去重"
        case .format:
            return "格式化"
        case .deduplicateAndFormat:
            return "去重并格式化"
        }
    }
}

struct BibProcessingOptions {
    let duplicatePolicy: BibDuplicatePolicy
    let outputStyle: BibOutputStyle
}

struct BibProcessingSummary {
    let inputReferenceCount: Int
    let outputReferenceCount: Int
    let duplicateReferenceCount: Int
    let duplicateKeyMatchCount: Int
    let duplicateTitleMatchCount: Int

    static let empty = BibProcessingSummary(
        inputReferenceCount: 0,
        outputReferenceCount: 0,
        duplicateReferenceCount: 0,
        duplicateKeyMatchCount: 0,
        duplicateTitleMatchCount: 0
    )
}

enum FigureKind: String, CaseIterable, Identifiable {
    case all = "全部"
    case figure = "图片"
    case table = "表格"

    var id: String { rawValue }
}

struct RecentTask: Identifiable {
    let id = UUID()
    let tool: String
    let title: String
    let detail: String
    let outputURL: URL?
    let date: Date
}

extension Array where Element == PageItem {
    mutating func applyThumbnails(_ thumbnails: [PageItem]) {
        guard !thumbnails.isEmpty else { return }
        let indexesByPage = Dictionary(uniqueKeysWithValues: enumerated().map { ($0.element.index, $0.offset) })
        for thumbnail in thumbnails {
            guard let index = indexesByPage[thumbnail.index] else { continue }
            self[index].thumbnail = thumbnail.thumbnail
        }
    }
}
