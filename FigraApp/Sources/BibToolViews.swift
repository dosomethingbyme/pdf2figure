import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum BibWorkspaceTab: String, CaseIterable, Identifiable {
    case duplicates = "重复项"
    case entries = "条目"
    case output = "输出"

    var id: String { rawValue }
}

private enum BibEntryFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case removed = "将移除"
    case conflict = "冲突"
    case suspicious = "疑似"
    case warning = "异常"
    case missingDOI = "缺 DOI"

    var id: String { rawValue }
}

struct BibToolView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab: BibWorkspaceTab = .duplicates
    @State private var entryFilter: BibEntryFilter = .all
    @State private var searchText = ""
    @State private var selectedEntryID: String?
    @State private var selectedGroupID: String?

    private var filteredEntries: [BibEntryPreview] {
        model.bibPreviewResult.entries.filter { entry in
            let matchesFilter: Bool
            switch entryFilter {
            case .all:
                matchesFilter = true
            case .removed:
                matchesFilter = entry.decision == .removeDuplicate
            case .conflict:
                matchesFilter = entry.decision == .keyConflict
            case .suspicious:
                matchesFilter = entry.decision == .suspiciousDuplicate
            case .warning:
                matchesFilter = entry.decision == .parseWarning
            case .missingDOI:
                matchesFilter = entry.isReference && (entry.doi?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            return matchesFilter && matchesSearch(entry)
        }
    }

    private var filteredGroups: [BibDuplicateGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.bibPreviewResult.duplicateGroups }
        return model.bibPreviewResult.duplicateGroups.filter { group in
            group.title.localizedCaseInsensitiveContains(query)
            || group.reason.rawValue.localizedCaseInsensitiveContains(query)
            || group.candidateEntries.contains { matchesSearch($0) }
        }
    }

    private var selectedGroup: BibDuplicateGroup? {
        guard let selectedGroupID else { return nil }
        return model.bibPreviewResult.duplicateGroups.first { $0.id == selectedGroupID }
    }

    private var selectedEntry: BibEntryPreview? {
        if let selectedEntryID, let entry = model.bibPreviewResult.entries.first(where: { $0.id == selectedEntryID }) {
            return entry
        }
        if let selectedGroup {
            return selectedGroup.keptEntry
        }
        return filteredEntries.first ?? model.bibPreviewResult.entries.first
    }

    var body: some View {
        Group {
            if model.bibItems.isEmpty {
                BibEmptyStartView(model: model)
            } else {
                VStack(spacing: 0) {
                    BibTopBar(model: model)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)

                    Divider()

                    GeometryReader { geometry in
                        let widths = bibColumnWidths(total: geometry.size.width)
                        HStack(spacing: 0) {
                            BibSourcePriorityPane(model: model)
                                .frame(width: widths.files)

                            Divider()

                            BibWorkspace(
                                model: model,
                                selectedTab: $selectedTab,
                                entryFilter: $entryFilter,
                                searchText: $searchText,
                                selectedEntryID: $selectedEntryID,
                                selectedGroupID: $selectedGroupID,
                                entries: filteredEntries,
                                groups: filteredGroups
                            )
                            .frame(width: widths.workspace)

                            Divider()

                            BibDetailPane(entry: selectedEntry, group: selectedGroup)
                                .frame(width: widths.detail)
                        }
                    }
                }
            }
        }
        .onChange(of: model.bibPreviewResult.duplicateGroups) { groups in
            if !groups.isEmpty, selectedGroupID == nil {
                selectedTab = .duplicates
                selectedGroupID = groups.first?.id
                selectedEntryID = groups.first?.keptEntry.id
            }
        }
        .onChange(of: model.bibPreviewResult.entries) { entries in
            guard selectedEntryID == nil || !entries.contains(where: { $0.id == selectedEntryID }) else { return }
            selectedEntryID = entries.first?.id
        }
    }

    private func matchesSearch(_ entry: BibEntryPreview) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [
            entry.citationKey,
            entry.title,
            entry.author,
            entry.year,
            entry.doi,
            entry.arxivID,
            entry.journal,
            entry.sourceFileName
        ].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private func bibColumnWidths(total: CGFloat) -> (files: CGFloat, workspace: CGFloat, detail: CGFloat) {
    let clampedTotal = max(total, 920)
    let files = min(max(clampedTotal * 0.22, 220), 292)
    let detail = min(max(clampedTotal * 0.31, 320), 430)
    let workspace = max(clampedTotal - files - detail - 2, 360)
    return (files, workspace, detail)
}

private struct BibTopBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BibTeX 工作台")
                    .font(.title2.bold())
                Text(model.bibStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                BibMetric(value: model.bibPreviewSummary.inputReferenceCount, title: "输入")
                BibMetric(value: model.bibPreviewResult.duplicateGroups.count, title: "重复")
                BibMetric(value: model.bibPreviewSummary.duplicateReferenceCount, title: "移除")
                BibMetric(value: model.bibPreviewSummary.outputReferenceCount, title: "输出")
            }

            Divider()
                .frame(height: 28)

            HStack(spacing: 8) {
                BibSwitchButton(title: "去重", symbol: "rectangle.stack.badge.minus", isOn: $model.bibRemoveDuplicates)
                BibSwitchButton(title: "格式化", symbol: "text.alignleft", isOn: $model.bibFormatOutput)
            }

            Button {
                model.addBibFiles(chooseBibFiles())
            } label: {
                Label("添加", systemImage: "plus")
            }

            Button {
                model.clearBibItems()
            } label: {
                Image(systemName: "trash")
            }
            .help("清空")
            .disabled(model.bibItems.isEmpty || model.isWorking)

            Button {
                model.exportBibTask()
            } label: {
                Label("导出 BibTeX", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.bibItems.isEmpty || model.isWorking)
        }
    }
}

private struct BibSwitchButton: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isOn ? Color.accentColor.opacity(0.16) : Color(nsColor: .separatorColor).opacity(0.18))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct BibMetric: View {
    let value: Int
    let title: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 42, alignment: .trailing)
    }
}

private struct BibEmptyStartView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BibTeX 工作台")
                        .font(.largeTitle.bold())
                    Text("拖入 .bib 后先看重复项，再导出清理后的引用库。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.addBibFiles(chooseBibFiles())
                } label: {
                    Label("添加 BibTeX", systemImage: "plus")
                }
                .controlSize(.large)
            }
            .padding(.horizontal, 36)
            .padding(.top, 34)
            .padding(.bottom, 26)

            BibDropTarget(compact: false) { urls in
                model.addBibFiles(urls)
            }
            .padding(.horizontal, 36)

            HStack(spacing: 14) {
                BibEmptyPoint(symbol: "1.circle", title: "顺序决定默认保留")
                BibEmptyPoint(symbol: "rectangle.stack.badge.minus", title: "强重复自动移除")
                BibEmptyPoint(symbol: "exclamationmark.triangle", title: "冲突保留待审")
            }
            .padding(.horizontal, 36)
            .padding(.top, 18)

            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct BibEmptyPoint: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct BibDropTarget: View {
    let compact: Bool
    let onDrop: ([URL]) -> Void

    var body: some View {
        FileDropTarget(
            title: compact ? "拖入更多 .bib" : "拖入一个或多个 .bib 文件",
            subtitle: compact ? "追加到优先级末尾。" : "优先级越靠前，重复组里越倾向默认保留。",
            symbol: "text.badge.plus",
            minHeight: compact ? 66 : 148,
            acceptedTypes: [.fileURL, .url, bibContentType()],
            allowedExtensions: ["bib"],
            fileRepresentationType: bibContentType(),
            temporaryDirectoryName: "FigraDroppedBibFiles",
            temporaryExtension: "bib"
        ) { urls in
            onDrop(urls)
        }
    }
}

private struct BibSourcePriorityPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            BibDropTarget(compact: true) { urls in
                model.addBibFiles(urls)
            }

            List {
                ForEach(Array(model.bibItems.enumerated()), id: \.element.id) { index, item in
                    BibSourceRow(index: index + 1, item: item, model: model)
                        .padding(.vertical, 4)
                }
                .onMove(perform: model.moveBibItem)
            }
            .listStyle(.sidebar)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct BibSourceRow: View {
    let index: Int
    let item: BibItem
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            Text("\(index)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(item.referenceCount) 篇 · \(formatFileSize(item.fileSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Menu {
                Button("上移") { model.moveBibItemUp(item) }
                Button("下移") { model.moveBibItemDown(item) }
                Divider()
                Button("移除", role: .destructive) { model.removeBibItem(item) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
    }
}

private struct BibWorkspace: View {
    @ObservedObject var model: AppModel
    @Binding var selectedTab: BibWorkspaceTab
    @Binding var entryFilter: BibEntryFilter
    @Binding var searchText: String
    @Binding var selectedEntryID: String?
    @Binding var selectedGroupID: String?
    let entries: [BibEntryPreview]
    let groups: [BibDuplicateGroup]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Picker("", selection: $selectedTab) {
                        ForEach(BibWorkspaceTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 248)

                    Spacer()

                    TextField("搜索 key、标题、作者、DOI", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 150, idealWidth: 210, maxWidth: 240)
                }

                HStack(spacing: 8) {
                    if selectedTab == .entries {
                        Picker("", selection: $entryFilter) {
                            ForEach(BibEntryFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 420)
                    } else if model.bibPreviewSummary.manualOverrideCount > 0 {
                        Button {
                            model.resetBibOverrides()
                        } label: {
                            Label("恢复全部默认", systemImage: "arrow.counterclockwise")
                        }
                        .font(.caption)
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            switch selectedTab {
            case .duplicates:
                BibDuplicateReviewList(model: model, groups: groups, selectedEntryID: $selectedEntryID, selectedGroupID: $selectedGroupID)
            case .entries:
                BibEntryList(entries: entries, selectedEntryID: $selectedEntryID, selectedGroupID: $selectedGroupID)
            case .output:
                BibOutputPreview(text: model.bibPreviewResult.outputText, summary: model.bibPreviewSummary)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct BibEntryList: View {
    let entries: [BibEntryPreview]
    @Binding var selectedEntryID: String?
    @Binding var selectedGroupID: String?

    var body: some View {
        if entries.isEmpty {
            EmptyState(symbol: "text.magnifyingglass", title: "没有匹配条目", message: "调整搜索或筛选条件后再查看。")
                .padding(18)
        } else {
            List(entries, selection: $selectedEntryID) { entry in
                BibEntryRow(entry: entry)
                    .tag(entry.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEntryID = entry.id
                        selectedGroupID = entry.duplicateGroupID
                    }
            }
            .listStyle(.inset)
        }
    }
}

private struct BibEntryRow: View {
    let entry: BibEntryPreview

    var body: some View {
        HStack(spacing: 10) {
            BibDecisionMarker(decision: entry.decision)
                .frame(width: 76, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.displayKey)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.displayYear)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let doi = entry.doi, !doi.isEmpty {
                        Text("DOI")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(entry.sourceFileIndex + 1).\(entry.entryIndex)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }
}

private struct BibDecisionMarker: View {
    let decision: BibEntryDecision

    var body: some View {
        Group {
            switch decision {
            case .keep:
                EmptyView()
            case .keepNonReference:
                Label("文本", systemImage: decision.symbol).foregroundStyle(.secondary)
            case .removeDuplicate:
                Label("移除", systemImage: decision.symbol).foregroundStyle(.orange)
            case .keyConflict:
                Label("冲突", systemImage: decision.symbol).foregroundStyle(.red)
            case .suspiciousDuplicate:
                Label("疑似", systemImage: decision.symbol).foregroundStyle(.yellow)
            case .parseWarning:
                Label("异常", systemImage: decision.symbol).foregroundStyle(.red)
            }
        }
        .font(.caption2.weight(.semibold))
    }
}

private struct BibDuplicateReviewList: View {
    @ObservedObject var model: AppModel
    let groups: [BibDuplicateGroup]
    @Binding var selectedEntryID: String?
    @Binding var selectedGroupID: String?

    var body: some View {
        if groups.isEmpty {
            EmptyState(symbol: "checkmark.seal", title: "未发现重复项", message: "当前文件可以直接导出。")
                .padding(18)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(groups) { group in
                        BibDuplicateCard(model: model, group: group, selectedEntryID: $selectedEntryID, selectedGroupID: $selectedGroupID)
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct BibDuplicateCard: View {
    @ObservedObject var model: AppModel
    let group: BibDuplicateGroup
    @Binding var selectedEntryID: String?
    @Binding var selectedGroupID: String?

    private var stateText: String {
        if group.reason == .keyConflict { return "全部保留" }
        if group.reason == .suspiciousTitle { return "待确认" }
        if group.removedEntries.isEmpty { return "全部保留" }
        return "移除 \(group.removedEntries.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Text(group.reason.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(group.isAutoRemoval ? .orange : .red)
                Text(stateText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(group.candidateEntries) { entry in
                    BibCandidateLine(entry: entry, keptID: group.keptEntry.id) {
                        selectedGroupID = group.id
                        selectedEntryID = entry.id
                    }
                }
            }

            HStack(spacing: 8) {
                Button("保留默认") {
                    model.setBibGroupOverride(groupID: group.id, resolution: .automatic)
                }
                .disabled(!group.isOverridden)

                ForEach(group.candidateEntries) { entry in
                    if entry.id != group.keptEntry.id {
                        Button("保留 \(entry.displayKey)") {
                            model.setBibGroupOverride(groupID: group.id, resolution: .keepEntry(entry.id))
                        }
                    }
                }

                Button("全部保留") {
                    model.setBibGroupOverride(groupID: group.id, resolution: .keepAll)
                }
                .disabled(group.removedEntries.isEmpty && group.isOverridden)

                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .background(group.id == selectedGroupID ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(group.id == selectedGroupID ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor).opacity(0.35))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedGroupID = group.id
            selectedEntryID = group.keptEntry.id
        }
    }
}

private struct BibCandidateLine: View {
    let entry: BibEntryPreview
    let keptID: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: entry.id == keptID ? "checkmark.circle.fill" : entry.decision == .removeDuplicate ? "minus.circle.fill" : "circle")
                    .foregroundStyle(entry.id == keptID ? .green : entry.decision == .removeDuplicate ? .orange : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.displayKey)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(entry.sourceFileIndex + 1).\(entry.entryIndex)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(entry.displayYear)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.displayTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        BibTinyField(name: "doi", value: entry.doi)
                        BibTinyField(name: "venue", value: entry.journal)
                    }
                }

                Spacer(minLength: 4)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .background(entry.id == keptID ? Color.green.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct BibTinyField: View {
    let name: String
    let value: String?

    var body: some View {
        Text("\(name): \(value?.isEmpty == false ? value! : "-")")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

private struct BibOutputPreview: View {
    let text: String
    let summary: BibProcessingSummary

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(summary.outputReferenceCount) 篇 · 移除 \(summary.duplicateReferenceCount) 条 · \(text.split(separator: "\n", omittingEmptySubsequences: false).count) 行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyString(text)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .disabled(text.isEmpty)
            }
            .padding(12)

            Divider()

            ScrollView {
                Text(text.isEmpty ? "暂无预览。" : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
    }
}

private struct BibDetailPane: View {
    let entry: BibEntryPreview?
    let group: BibDuplicateGroup?
    @State private var showRawText = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let entry {
                HStack {
                    BibDecisionMarker(decision: entry.decision)
                    Spacer()
                    Text("\(entry.sourceFileIndex + 1).\(entry.entryIndex)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(entry.displayKey)
                    .font(.title3.bold())
                    .lineLimit(2)

                Text("\(entry.displayType) · \(entry.sourceFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let reason = entry.duplicateReason {
                    BibReasonPanel(entry: entry, group: group, reason: reason)
                }

                BibFieldSummary(entry: entry)

                HStack {
                    Button {
                        copyString(entry.outputText)
                    } label: {
                        Label("复制条目", systemImage: "doc.on.doc")
                    }

                    Button {
                        copyString(entry.citationKey ?? "")
                    } label: {
                        Label("复制 Key", systemImage: "key")
                    }
                    .disabled(entry.citationKey == nil)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([entry.sourceURL])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("显示来源")
                }
                .font(.caption)

                DisclosureGroup("BibTeX", isExpanded: $showRawText) {
                    ScrollView {
                        Text(entry.outputText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .frame(minHeight: 160)
                }
            } else {
                EmptyState(symbol: "sidebar.right", title: "未选择条目", message: "选择一条引用后查看字段和原文。")
            }

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct BibReasonPanel: View {
    let entry: BibEntryPreview
    let group: BibDuplicateGroup?
    let reason: BibDuplicateReason

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(reason.rawValue)
                    .font(.caption.weight(.semibold))
                Spacer()
                if entry.decision == .removeDuplicate {
                    Text("将移除")
                        .foregroundStyle(.orange)
                } else if entry.decision == .keyConflict || entry.decision == .suspiciousDuplicate {
                    Text("保留待审")
                        .foregroundStyle(.red)
                } else {
                    Text("保留")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if let group {
                Text("当前保留 \(group.keptEntry.displayKey)。候选 \(group.candidateEntries.count) 条，已移除 \(group.removedEntries.count) 条。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(9)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct BibFieldSummary: View {
    let entry: BibEntryPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            BibFieldLine(name: "title", value: entry.title)
            BibFieldLine(name: "author", value: entry.author)
            BibFieldLine(name: "year", value: entry.year)
            BibFieldLine(name: "doi", value: entry.doi)
            BibFieldLine(name: "arxiv", value: entry.arxivID)
            BibFieldLine(name: "venue", value: entry.journal)
        }
        .padding(.vertical, 2)
    }
}

private struct BibFieldLine: View {
    let name: String
    let value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "未提供")
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}

private func copyString(_ value: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(value, forType: .string)
}
