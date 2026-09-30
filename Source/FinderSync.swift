import Cocoa
import FinderSync

@objc(FinderSync)
final class FinderSync: FIFinderSync {
    // Finder sends tags back across the extension boundary. Keep action data here,
    // rather than relying on arbitrary representedObject values surviving IPC.
    var requests: [Int: (String, String, String)] = [:]
    var nextTag = 100
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        EventLog.write("extension_started", fields: ["version": "2.1", "path": Bundle.main.bundlePath])
    }
    override func menu(for kind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        guard let target = controller.targetedURL(), target.isFileURL else { return nil }
        var chosen = target
        if kind == .contextualMenuForItems, let selected = controller.selectedItemURLs(), selected.count == 1 { chosen = selected[0] }
        let menu = NSMenu()
        let other = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (title, type) in [("文本文件 (.txt)", "txt"), ("Word 文档 (.docx)", "docx"), ("PowerPoint 演示文稿 (.pptx)", "pptx"), ("Excel 工作簿 (.xlsx)", "xlsx"), ("Markdown (.md)", "md"), ("Python (.py)", "py"), ("JSON (.json)", "json"), ("自定义文件名…", "custom")] {
            submenu.addItem(item(title, action: "create", path: chosen.path, type: type))
        }
        other.submenu = submenu; menu.addItem(other)
        menu.addItem(item("在此处打开终端", action: "terminal", path: chosen.path, type: "txt"))
        menu.addItem(item("打开活动监视器", action: "activity-monitor", path: chosen.path, type: "txt"))
        return menu
    }
    func item(_ title: String, action: String, path: String, type: String) -> NSMenuItem {
        nextTag += 1
        requests[nextTag] = (action, path, type)
        if requests.count > 2048 { requests.removeValue(forKey: nextTag - 2048) }
        let item = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self; item.tag = nextTag
        return item
    }
    @objc func runAction(_ item: NSMenuItem) {
        guard let (action, path, type) = requests[item.tag] else {
            EventLog.write("missing_action", fields: ["tag": item.tag]); return
        }
        let request = ActionRequest(action: action, path: path, type: type)
        var host = Bundle.main.bundleURL
        for _ in 0..<5 {
            if host.pathExtension == "app" { break }
            host.deleteLastPathComponent()
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.allowsRunningApplicationSubstitution = false
        EventLog.write("menu_clicked", fields: ["id": request.id, "action": action, "path": path, "host": host.path])
        NSWorkspace.shared.open([request.url], withApplicationAt: host, configuration: config) { _, error in
            if let error { EventLog.write("dispatch_failed", fields: ["id": request.id, "error": error.localizedDescription]) }
            else { EventLog.write("dispatch_ok", fields: ["id": request.id]) }
        }
    }
}
