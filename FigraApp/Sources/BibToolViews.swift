import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BibToolView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "BibTeX 工具", subtitle: "选择或拖入 .bib 文件，按列表顺序合并、去重或格式化导出。") {
                HStack {
                    Button("添加 BibTeX") {
                        model.addBibFiles(chooseBibFiles())
                    }
                    Button("清空") {
                        model.clearBibItems()
                    }
                    .disabled(model.bibItems.isEmpty || model.isWorking)
                }
            }

            FileDropTarget(
                title: "拖入 .bib 文件",
                subtitle: "可拖入一个或多个文件；列表顺序就是合并和去重时的保留顺序。",
                symbol: "text.badge.plus",
                acceptedTypes: [.fileURL, .url, bibContentType()],
                allowedExtensions: ["bib"],
                fileRepresentationType: bibContentType(),
                temporaryDirectoryName: "FigraDroppedBibFiles",
                temporaryExtension: "bib"
            ) { urls in
                model.addBibFiles(urls)
            }

            Text(model.bibStatus).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                BibStatCard(title: "Bib 文件", value: "\(model.bibItems.count)")
                BibStatCard(title: "输入参考文献", value: "\(model.bibPreviewSummary.inputReferenceCount)")
                BibStatCard(title: "重复项", value: "\(model.bibPreviewSummary.duplicateReferenceCount)")
                BibStatCard(title: "生成参考文献", value: "\(model.bibPreviewSummary.outputReferenceCount)")
            }

            BibWorkflowPanel(model: model)

            if model.bibItems.isEmpty {
                EmptyState(symbol: "text.book.closed", title: "未添加 BibTeX", message: "选择或拖入 .bib 文件后，这里会显示处理顺序。")
            } else {
                List {
                    ForEach(model.bibItems) { item in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading) {
                                Text(item.url.lastPathComponent).font(.headline)
                                Text("\(item.referenceCount) 篇参考文献 · \(formatFileSize(item.fileSize))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("上移") { model.moveBibItemUp(item) }
                            Button("下移") { model.moveBibItemDown(item) }
                            Button("移除") { model.removeBibItem(item) }
                        }
                        .padding(.vertical, 6)
                    }
                    .onMove(perform: model.moveBibItem)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            HStack {
                Button(model.bibTask.exportButtonTitle) { model.exportBibTask() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.bibItems.isEmpty || model.isWorking)
                if let outputURL = model.bibOutputURL {
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

private struct BibStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct BibWorkflowPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("任务")
                    .font(.headline)
                Spacer()
                Text(model.bibTask.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Picker("任务", selection: $model.bibTask) {
                ForEach(BibTask.allCases) { task in
                    Text(task.rawValue).tag(task)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                BibRuleBadge(
                    title: "重复判断",
                    value: model.bibTask.duplicatePolicy == .keyAndTitle ? "引用键 + 标题" : "不清理"
                )
                BibRuleBadge(
                    title: "输出格式",
                    value: model.bibTask.outputStyle == .formatted ? "统一格式" : "保留原条目"
                )
                Spacer()
                BibMetricBadge(title: "重复引用键", value: model.bibPreviewSummary.duplicateKeyMatchCount)
                BibMetricBadge(title: "重复标题", value: model.bibPreviewSummary.duplicateTitleMatchCount)
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct BibRuleBadge: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
    }
}

private struct BibMetricBadge: View {
    let title: String
    let value: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
    }
}
