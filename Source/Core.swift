import Foundation
import Darwin

struct ActionRequest {
    let id: String
    let action: String
    let path: String
    let type: String
    let createdAt: Double
    static let scheme = "local-rightclick-tools"
    static let types = ["txt", "docx", "pptx", "xlsx", "md", "py", "json", "custom"]
    init(action: String, path: String, type: String = "txt") {
        self.id = UUID().uuidString; self.action = action; self.path = path
        self.type = type; self.createdAt = Date().timeIntervalSince1970
    }
    init?(url: URL) {
        guard url.scheme == Self.scheme, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let action = c.host, ["create", "terminal", "activity-monitor"].contains(action) else { return nil }
        func value(_ key: String) -> String? { c.queryItems?.first(where: { $0.name == key })?.value }
        guard let path = value("path"), path.hasPrefix("/"), !path.contains("\0"),
              let id = value("id"), UUID(uuidString: id) != nil,
              let timestamp = value("at").flatMap(Double.init), timestamp.isFinite else { return nil }
        let type = value("type") ?? "txt"
        guard Self.types.contains(type) else { return nil }
        self.id = id; self.path = path; self.action = action; self.type = type; self.createdAt = timestamp
    }
    var url: URL {
        var c = URLComponents(); c.scheme = Self.scheme; c.host = action
        c.queryItems = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "type", value: type), URLQueryItem(name: "id", value: id), URLQueryItem(name: "at", value: String(createdAt))]
        return c.url!
    }
}

enum FileTools {
    static func failure(_ message: String) -> NSError {
        NSError(domain: "RightClickTools", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func directory(for url: URL) throws -> URL {
        guard url.isFileURL else { throw failure("需要一个实际文件夹。") }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true ? url : url.deletingLastPathComponent()
    }
    static func validate(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"),
              !name.contains("\0"), !name.contains("\n"), !name.contains("\r") else {
            throw failure("文件名不能为空，不能包含斜杠、冒号或换行。")
        }
    }
    static func create(in folder: URL, type: String, name: String? = nil, templates: URL? = nil) throws -> URL {
        guard ActionRequest.types.contains(type) else { throw failure("不支持该文件类型。") }
        let directory = try directory(for: folder)
        let original = name ?? "未命名.\(type == "custom" ? "txt" : type)"
        try validate(original)
        let ns = original as NSString
        let ext = ns.pathExtension
        let data: Data
        if ["docx", "pptx", "xlsx"].contains(ext.lowercased()) {
            let directory = templates ?? Bundle.main.resourceURL?.appendingPathComponent("Templates", isDirectory: true)
            guard let template = directory?.appendingPathComponent("Blank." + ext.lowercased()) else {
                throw failure("缺少 Office 空白模板，请重新安装工具。")
            }
            // Read the bundled template before creating the destination, so a missing
            // template never leaves an invalid zero-byte Office document behind.
            data = try Data(contentsOf: template, options: .mappedIfSafe)
        } else {
            data = Data((ext.lowercased() == "json" ? "{}\n" : "").utf8)
        }
        let stem = ext.isEmpty ? original : ns.deletingPathExtension
        for index in 0..<10000 {
            let candidate = index == 0 ? original : stem + " \(index + 1)" + (ext.isEmpty ? "" : "." + ext)
            let url = directory.appendingPathComponent(candidate)
            let fd = url.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o644)) }
            if fd < 0 {
                if errno == EEXIST { continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
            }
            // O_EXCL protects both existing files and symbolic links, even on concurrent clicks.
            defer { Darwin.close(fd) }
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                    if count == 0 { throw failure("写入文件失败。") }
                    offset += count
                }
            }
            return url
        }
        throw failure("同名文件过多，请使用自定义文件名。")
    }
}

enum EventLog {
    static let queue = DispatchQueue(label: "local.suxin.rightclicktools.log")
    static var directory: URL { FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/RightClickTools", isDirectory: true) }
    static var file: URL { directory.appendingPathComponent("events.jsonl") }
    static func write(_ event: String, fields: [String: Any] = [:]) {
        var payload = fields
        payload["event"] = event; payload["time"] = Date().timeIntervalSince1970
        payload["bundle"] = Bundle.main.bundleIdentifier ?? "test"
        guard let bytes = try? JSONSerialization.data(withJSONObject: payload), let line = String(data: bytes, encoding: .utf8) else { return }
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 { try? Data().write(to: file) }
            let fd = file.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, mode_t(0o600)) }
            guard fd >= 0 else { return }
            defer { Darwin.close(fd) }
            let data = Data((line + "\n").utf8)
            data.withUnsafeBytes { b in _ = Darwin.write(fd, b.baseAddress, b.count) }
        }
    }
}
