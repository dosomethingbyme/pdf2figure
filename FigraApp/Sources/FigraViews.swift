import AppKit
import SwiftUI

struct FigraAppView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            FigraSidebar(selectedTool: $model.selectedTool)
        } detail: {
            ToolDetailView(model: model, selectedTool: model.selectedTool)
                .frame(minWidth: 900, minHeight: 680)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .topTrailing) {
                    if model.isWorking || model.isExtractingFigures {
                        WorkStatusBadge()
                            .padding(18)
                    }
                }
        }
    }
}

private struct FigraSidebar: View {
    @Binding var selectedTool: Tool

    var body: some View {
        List(Tool.allCases, selection: $selectedTool) { tool in
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
    }
}

private struct ToolDetailView: View {
    @ObservedObject var model: AppModel
    let selectedTool: Tool

    var body: some View {
        switch selectedTool {
        case .figureExtract:
            FigureExtractView(model: model)
        case .pageExport:
            PageExportView(model: model, mode: .pageExport)
        case .pageOrganize:
            PageOrganizeView(model: model)
        case .merge:
            MergePDFView(model: model)
        case .bibMerge:
            BibToolView(model: model)
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
}

private struct WorkStatusBadge: View {
    var body: some View {
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
    }
}
