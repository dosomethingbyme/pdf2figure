import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

private struct OrganizePageCard: View {
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

private struct OrganizePageDropDelegate: DropDelegate {
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
