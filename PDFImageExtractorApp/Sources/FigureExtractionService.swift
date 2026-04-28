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
        let outputURL = uniqueOutputDirectory(for: pdfURL, suffix: "_pdffigures2")
        let figuresURL = outputURL.appendingPathComponent("figures")
        let dataURL = outputURL.appendingPathComponent("figure_data")
        do {
            try FileManager.default.createDirectory(at: figuresURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        } catch {
            return FigureExtractionOutput(status: "创建输出目录失败。", log: error.localizedDescription, outputURL: nil, images: [])
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

        _ = removePDFPrefixFromPNGs(in: figuresURL, prefixes: [baseName, pdfURL.deletingPathExtension().lastPathComponent])
        let images = pngFiles(in: figuresURL)
        let status = images.isEmpty ? "未识别到 Figure/Table。" : "识别到 \(images.count) 个 Figure/Table。"
        return FigureExtractionOutput(status: status, log: log.isEmpty ? "pdffigures2 未返回详细日志。" : log, outputURL: outputURL, images: images)
    }

    static func thumbnail(forImageAt url: URL, size: NSSize) -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.size = size
        return image
    }
}

private func uniqueOutputDirectory(for pdfURL: URL, suffix: String) -> URL {
    let baseName = safeName(pdfURL.deletingPathExtension().lastPathComponent)
    let base = pdfURL.deletingLastPathComponent().appendingPathComponent("\(baseName)\(suffix)")
    guard FileManager.default.fileExists(atPath: base.path) else { return base }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    return pdfURL.deletingLastPathComponent().appendingPathComponent("\(baseName)\(suffix)_\(formatter.string(from: Date()))")
}

private func pngFiles(in directory: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
    return enumerator.compactMap { $0 as? URL }
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

private func removePDFPrefixFromPNGs(in directory: URL, prefixes: [String]) -> Int {
    var count = 0
    let normalized = Set(prefixes.flatMap { prefix in
        let safe = safeName(prefix)
        return ["\(prefix)-", "\(prefix)_", "\(safe)-", "\(safe)_"]
    })
    for url in pngFiles(in: directory) {
        guard let prefix = normalized.first(where: { url.lastPathComponent.hasPrefix($0) }) else { continue }
        let stripped = String(url.lastPathComponent.dropFirst(prefix.count))
        guard !stripped.isEmpty else { continue }
        do {
            try FileManager.default.moveItem(at: url, to: uniqueFileURL(in: directory, fileName: stripped))
            count += 1
        } catch {
            continue
        }
    }
    return count
}
