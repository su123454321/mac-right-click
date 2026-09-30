import Cocoa
import FinderSync

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var statusItem: NSStatusItem?
    var statusLabel: NSTextField?
    var lastMessage = "已就绪，等待右键操作。"
    var receivedAction = false
    var seen: Set<String> = []
    let worker = DispatchQueue(label: "local.suxin.rightclicktools.actions", qos: .userInitiated)

    func applicationWillFinishLaunching(_ notification: Notification) {
        EventLog.write("host_starting", fields: ["version": "2.1", "path": Bundle.main.bundlePath])
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "右键小工具")
        let menu = NSMenu()
        let settings = NSMenuItem(title: "右键小工具 2.1…", action: #selector(showWindow), keyEquivalent: "")
        settings.target = self; menu.addItem(settings)
        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); item.menu = menu; statusItem = item
        let main = NSMenu(); let root = NSMenuItem(); let appMenu = NSMenu()
        let q = NSMenuItem(title: "退出右键小工具", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(q); root.submenu = appMenu; main.addItem(root); NSApp.mainMenu = main
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { if !self.receivedAction { self.showWindow() } }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedAction = true
        for url in urls {
            guard let request = ActionRequest(url: url), seen.insert(request.id).inserted else { continue }
            if seen.count > 4096 { seen = [request.id] }
            EventLog.write("request_received", fields: ["id": request.id, "action": request.action, "path": request.path, "dispatch_ms": elapsed(request)])
            if request.action == "create", request.type == "custom" {
                customFile(request); continue
            }
            execute(request, name: nil)
        }
    }
    func elapsed(_ request: ActionRequest) -> Double { max(0, (Date().timeIntervalSince1970 - request.createdAt) * 1000) }
    func execute(_ request: ActionRequest, name: String?) {
        if request.action == "activity-monitor" {
            openActivityMonitor(request)
            return
        }
        worker.async {
            do {
                let folder = try FileTools.directory(for: URL(fileURLWithPath: request.path))
                if request.action == "create" {
                    let created = try FileTools.create(in: folder, type: request.type, name: name)
                    let ms = self.elapsed(request)
                    EventLog.write("file_created", fields: ["id": request.id, "path": created.path, "elapsed_ms": ms])
                    DispatchQueue.main.async {
                        self.update("已创建 \(created.lastPathComponent)（\(Int(ms)) 毫秒）")
                        // Filesystem events refresh the existing Finder window. Do not open
                        // another window or block file creation on Finder activation.
                    }
                } else {
                    DispatchQueue.main.async { self.openTerminal(folder, request: request) }
                }
            } catch {
                EventLog.write("action_failed", fields: ["id": request.id, "path": request.path, "error": error.localizedDescription])
                DispatchQueue.main.async { self.report(error, path: request.path) }
            }
        }
    }
    func openTerminal(_ folder: URL, request: ActionRequest) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: configuration) { app, error in
            if let error {
                EventLog.write("terminal_failed", fields: ["id": request.id, "error": error.localizedDescription])
                DispatchQueue.main.async { self.report(error, path: folder.path) }
            } else {
                let ms = self.elapsed(request)
                EventLog.write("terminal_opened", fields: ["id": request.id, "path": folder.path, "elapsed_ms": ms, "pid": app?.processIdentifier ?? 0])
                DispatchQueue.main.async { self.update("已向终端打开：\(folder.path)（\(Int(ms)) 毫秒）") }
            }
        }
    }
    func openActivityMonitor(_ request: ActionRequest) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                EventLog.write("activity_monitor_failed", fields: ["id": request.id, "error": error.localizedDescription])
                DispatchQueue.main.async { self.report(error, path: url.path) }
            } else {
                let ms = self.elapsed(request)
                EventLog.write("activity_monitor_opened", fields: ["id": request.id, "elapsed_ms": ms])
                DispatchQueue.main.async { self.update("已打开活动监视器（\(Int(ms)) 毫秒）") }
            }
        }
    }
    func customFile(_ request: ActionRequest) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "自定义文件名"
        alert.informativeText = "输入完整文件名；同名文件会自动编号，不覆盖原文件。"
        alert.addButton(withTitle: "创建"); alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 350, height: 26)); input.stringValue = "未命名.txt"
        alert.accessoryView = input; alert.window.initialFirstResponder = input
        if alert.runModal() == .alertFirstButtonReturn { execute(request, name: input.stringValue) }
    }
    func update(_ message: String) { lastMessage = message; statusLabel?.stringValue = message }
    func report(_ error: Error, path: String) {
        update("操作未完成：\(error.localizedDescription)")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "操作未完成"
        alert.informativeText = "\(error.localizedDescription)\n\n位置：\(path)\n如系统询问文件夹访问权限，请允许本工具访问该位置。"
        alert.addButton(withTitle: "知道了"); alert.runModal()
    }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func settings() { FIFinderSyncController.showExtensionManagementInterface() }
    @objc func logs() { NSWorkspace.shared.open(EventLog.directory) }
    @objc func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 390), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "右键小工具 2.1"; w.isReleasedWhenClosed = false
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
            let title = NSTextField(labelWithString: "右键新建与快捷打开")
            title.font = .systemFont(ofSize: 26, weight: .semibold)
            let detail = NSTextField(wrappingLabelWithString: "• 新建文件：在子菜单中选择 TXT、Word、PPT、Excel、Markdown、Python 或 JSON。\n• 选好类型立即创建，同名自动编号。\n• 在此处打开终端，或直接打开活动监视器。\n\n在文件夹空白处操作会使用当前文件夹；右键文件会使用文件所在文件夹。关闭此窗口后工具仍在后台待命。")
            detail.font = .systemFont(ofSize: 14)
            let state = NSTextField(wrappingLabelWithString: lastMessage); state.font = .systemFont(ofSize: 12); state.textColor = .secondaryLabelColor; statusLabel = state
            for view in [title, detail, state] { stack.addArrangedSubview(view) }
            for (title, selector) in [("打开 Finder 扩展设置", #selector(settings)), ("打开操作记录", #selector(logs))] {
                let button = NSButton(title: title, target: self, action: selector); button.bezelStyle = .rounded; stack.addArrangedSubview(button)
            }
            w.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: w.contentView!.topAnchor, constant: 28)])
            w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
