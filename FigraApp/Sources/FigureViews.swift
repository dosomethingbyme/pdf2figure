import AppKit
import SwiftUI

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

private struct FigureGalleryView: View {
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
