import AppKit
import Foundation

extension AppModel {
    struct FigureExtractionOutput {
        let status: String
        let log: String
        let outputURL: URL?
        let images: [URL]
    }

    static func extractFigures(pdfURL: URL, dpi: Int) -> FigureExtractionOutput {
        guard let resources = Bundle.main.resourceURL else {
            return FigureExtractionOutput(status: "应用资源目录不可用。", log: "", outputURL: nil, images: [])
        }
        let javaURL = resources.appendingPathComponent("jre/bin/java")
        let jarURL = resources.appendingPathComponent("pdffigures2.jar")
        guard FileManager.default.isExecutableFile(atPath: javaURL.path) else {
            return FigureExtractionOutput(status: "找不到内置 Java runtime。", log: javaURL.path, outputURL: nil, images: [])
        }
        guard FileManager.default.fileExists(atPath: jarURL.path) else {
            return FigureExtractionOutput(status: "找不到 pdffigures2.jar。", log: jarURL.path, outputURL: nil, images: [])
        }

        let baseName = safeName(pdfURL.deletingPathExtension().lastPathComponent)
        let outputURL = figureOutputDirectory(for: pdfURL, folderPrefix: "images_")
        let workURL = outputURL.appendingPathComponent(".figra-pdffigures-\(UUID().uuidString)", isDirectory: true)
        let figuresURL = workURL.appendingPathComponent("figures", isDirectory: true)
        let dataURL = workURL.appendingPathComponent("data", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: figuresURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        } catch {
            return FigureExtractionOutput(status: "创建输出目录失败。", log: error.localizedDescription, outputURL: nil, images: [])
        }
        defer {
            try? FileManager.default.removeItem(at: workURL)
        }

        let process = Process()
        process.executableURL = javaURL
        process.arguments = [
            "-jar", jarURL.path,
            "-q",
            "-e",
            "-i", "\(dpi)",
            "-f", "png",
            "-m", figuresURL.path + "/",
            "-d", dataURL.path + "/",
            pdfURL.path
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var outputData = Data()
        let outputLock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputLock.lock()
            outputData.append(data)
            outputLock.unlock()
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return FigureExtractionOutput(status: "启动 pdffigures2 失败。", log: error.localizedDescription, outputURL: outputURL, images: [])
        }

        pipe.fileHandleForReading.readabilityHandler = nil
        let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
        outputLock.lock()
        outputData.append(remainingData)
        let capturedData = outputData
        outputLock.unlock()
        let log = String(data: capturedData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            return FigureExtractionOutput(status: "提取失败，请查看日志。", log: log, outputURL: outputURL, images: [])
        }

        let images = moveExtractedPNGs(
            from: figuresURL,
            to: outputURL,
            prefixesToStrip: [baseName, pdfURL.deletingPathExtension().lastPathComponent],
            outputPrefix: ""
        )
        let status = images.isEmpty ? "未识别到 Figure/Table。" : "识别到 \(images.count) 个 Figure/Table。"
        return FigureExtractionOutput(status: status, log: log.isEmpty ? "pdffigures2 未返回详细日志。" : log, outputURL: outputURL, images: images)
    }

    static func thumbnail(forImageAt url: URL, size: NSSize) -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.size = size
        return image
    }
}

private func figureOutputDirectory(for pdfURL: URL, folderPrefix: String) -> URL {
    let baseName = safeName(pdfURL.deletingPathExtension().lastPathComponent)
    return pdfURL.deletingLastPathComponent().appendingPathComponent("\(folderPrefix)\(baseName)", isDirectory: true)
}

private func pngFiles(in directory: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
    return enumerator.compactMap { $0 as? URL }
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

private func moveExtractedPNGs(from sourceDirectory: URL, to destinationDirectory: URL, prefixesToStrip: [String], outputPrefix: String) -> [URL] {
    let normalized = Set(prefixesToStrip.flatMap { prefix in
        let safe = safeName(prefix)
        return ["\(prefix)-", "\(prefix)_", "\(safe)-", "\(safe)_"]
    })
    var moved: [URL] = []
    for url in pngFiles(in: sourceDirectory) {
        var name = url.lastPathComponent
        if let prefix = normalized.first(where: { name.hasPrefix($0) }) {
            let stripped = String(name.dropFirst(prefix.count))
            if !stripped.isEmpty {
                name = stripped
            }
        }
        if !outputPrefix.isEmpty && !name.hasPrefix(outputPrefix) {
            name = "\(outputPrefix)\(name)"
        }
        let destinationURL = uniqueFileURL(in: destinationDirectory, fileName: name)
        do {
            try FileManager.default.moveItem(at: url, to: destinationURL)
            moved.append(destinationURL)
        } catch {
            continue
        }
    }
    return moved.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}
