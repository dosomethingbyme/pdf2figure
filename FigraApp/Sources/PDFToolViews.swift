import AppKit
import SwiftUI

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
