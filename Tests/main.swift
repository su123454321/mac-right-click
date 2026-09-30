import Foundation
import Darwin
let base = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
let folder = base.appendingPathComponent("中文 空格 ' $ ; & # 测试")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let start = Date()
let first = try FileTools.create(in: folder, type: "txt")
try Data("不能覆盖".utf8).write(to: first)
let second = try FileTools.create(in: folder, type: "txt")
assert(second.lastPathComponent == "未命名 2.txt")
let saved = try String(contentsOf: first, encoding: .utf8); assert(saved == "不能覆盖")
for type in ["md", "py", "json"] {
    let url = try FileTools.create(in: folder, type: type)
    if type == "json" { _ = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) }
}
for name in ["", "..", ".", "../escape", "a/b", "a:b", "\0", "a\nb"] {
    do { _ = try FileTools.create(in: folder, type: "custom", name: name); fatalError("Invalid name accepted") } catch {}
}
let custom = try FileTools.create(in: folder, type: "custom", name: "配置.json")
_ = try JSONSerialization.jsonObject(with: Data(contentsOf: custom))
let fileFolder = try FileTools.directory(for: first); assert(fileFolder.path == folder.path)
let request = ActionRequest(action: "create", path: folder.path, type: "json")
let decoded = ActionRequest(url: request.url)!
assert(decoded.path == request.path && decoded.id == request.id && decoded.type == "json")
assert(ActionRequest(url: URL(string: "local-rightclick-tools://create?path=relative")!) == nil)
let link = folder.appendingPathComponent("link.txt")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
let safe = try FileTools.create(in: folder, type: "txt", name: "link.txt")
assert(safe.lastPathComponent == "link 2.txt")
let concurrent = base.appendingPathComponent("parallel")
try FileManager.default.createDirectory(at: concurrent, withIntermediateDirectories: true)
DispatchQueue.concurrentPerform(iterations: 40) { _ in
    do { _ = try FileTools.create(in: concurrent, type: "txt") } catch { fatalError("Concurrent failure: \(error)") }
}
let files = try FileManager.default.contentsOfDirectory(atPath: concurrent.path)
assert(files.count == 40)
print("PASS: direct creation, numbered collisions, content preservation, symlinks, 40 concurrent creations, URL round trip, Chinese/special paths, JSON, name validation")
print("TOTAL test duration: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
print("Test directory: \(base.path)")
let templates = URL(fileURLWithPath: CommandLine.arguments[2])
for type in ["docx", "pptx", "xlsx"] {
    let created = try FileTools.create(in: folder, type: type, templates: templates)
    let bytes = try Data(contentsOf: created)
    assert(bytes.prefix(2) == Data([0x50, 0x4b]))
    let source = try Data(contentsOf: templates.appendingPathComponent("Blank.\(type)"))
    assert(bytes == source)
    let again = try FileTools.create(in: folder, type: type, templates: templates)
    assert(again.lastPathComponent == "未命名 2.\(type)")
}
let customOffice = try FileTools.create(in: folder, type: "custom", name: "自定义.docx", templates: templates)
assert(try! Data(contentsOf: customOffice) == Data(contentsOf: templates.appendingPathComponent("Blank.docx")))
let beforeFailure = try FileManager.default.contentsOfDirectory(atPath: folder.path).count
do {
    _ = try FileTools.create(in: folder, type: "docx", name: "不能留下损坏文件.docx", templates: base.appendingPathComponent("missing"))
    fatalError("Missing template accepted")
} catch {}
let afterFailure = try FileManager.default.contentsOfDirectory(atPath: folder.path).count
assert(beforeFailure == afterFailure)
let activity = ActionRequest(action: "activity-monitor", path: "/")
assert(ActionRequest(url: activity.url)?.action == "activity-monitor")
print("PASS: Office templates, automatic numbering, custom Office suffix, missing-template protection, Activity Monitor request")
