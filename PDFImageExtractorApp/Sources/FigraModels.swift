import AppKit
import Foundation

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case figureExtract = "图表提取"
    case pageExport = "页面提取"
    case pageOrganize = "页面整理"
    case merge = "合并 PDF"
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
    let id = UUID()
    let index: Int
    let thumbnail: NSImage
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
