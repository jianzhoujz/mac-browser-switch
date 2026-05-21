import AppKit
import Foundation

// MARK: - App configuration

private struct AppConfig {
    let appName: String
    let displayName: String
    let bundleID: String
    let launchAgentID: String
    let logFileName: String
}

private let appConfig = AppConfig(
    appName: "BrowserSwitch",
    displayName: "BrowserSwitch",
    bundleID: "local.mac-browser-switch",
    launchAgentID: "local.mac-browser-switch",
    logFileName: "BrowserSwitch.log"
)

private let gitHubRepository = "jianzhoujz/mac-browser-switch"
private let gitHubURL = URL(string: "https://github.com/\(gitHubRepository)")!
private let latestReleaseURL = URL(string: "https://github.com/\(gitHubRepository)/releases/latest")!

private struct GitHubRelease {
    let tagName: String
    let htmlURL: URL
}

private func isNewerVersion(_ latest: String, than current: String) -> Bool {
    func normalize(_ value: String) -> String {
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.first, first == "v" || first == "V" {
            s.removeFirst()
        }
        // Drop a "-beta1"-style suffix so "1.2.3" and "1.2.3-rc1" compare equal.
        return s.split(separator: "-", maxSplits: 1).first.map(String.init) ?? s
    }
    return normalize(current).compare(normalize(latest), options: .numeric) == .orderedAscending
}

// MARK: - Browser catalog (LaunchServices wrapper)

private struct Browser {
    let bundleID: String
    let displayName: String
    let appURL: URL
    let version: String
    let icon: NSImage
}

private enum BrowserCatalog {
    /// Probe URL used to enumerate apps that handle the https scheme. The host
    /// is irrelevant — LaunchServices only inspects the scheme.
    private static let httpsProbeURL = URL(string: "https://example.com")!

    /// Bundle IDs we never want to show as "browsers" even if they happen to
    /// register an https handler — usually transient helpers or services.
    /// Keep this tight; the system list is the source of truth.
    private static let blockedBundleIDs: Set<String> = [
        "com.apple.systempreferences"
    ]

    /// URL schemes that betray a non-browser app (terminals, IDEs). A real web
    /// browser never registers itself as an SSH/SFTP/Telnet handler, so any
    /// app declaring one of these is excluded even if it also claims `https`.
    /// Example: Kitty declares http/https alongside ssh/sftp/telnet so it
    /// appears in `urlsForApplications(toOpen:)` for https.
    private static let nonBrowserSchemes: Set<String> = [
        "ssh", "sftp", "telnet"
    ]

    static func allBrowsers() -> [Browser] {
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: httpsProbeURL)

        var seen = Set<String>()
        var browsers: [Browser] = []
        for appURL in appURLs {
            guard let browser = describe(appURL: appURL) else {
                continue
            }
            let key = browser.bundleID.lowercased()
            if blockedBundleIDs.contains(key) {
                continue
            }
            if !seen.insert(key).inserted {
                continue
            }
            browsers.append(browser)
        }

        browsers.sort { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return browsers
    }

    static func currentDefault() -> Browser? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: httpsProbeURL) else {
            return nil
        }
        return describe(appURL: appURL)
    }

    /// One-shot enumeration that also resolves the current default by URL
    /// against the same list — saves a redundant Bundle load + icon fetch the
    /// menu would otherwise pay every time it opens.
    static func snapshot() -> (browsers: [Browser], current: Browser?) {
        let browsers = allBrowsers()
        let currentURL = NSWorkspace.shared.urlForApplication(toOpen: httpsProbeURL)
        let current = currentURL.flatMap { url in
            browsers.first { $0.appURL == url }
        }
        return (browsers, current)
    }

    /// Asks LaunchServices to set the given app as the default handler for
    /// both `http` and `https`. macOS shows its own confirmation dialog — that
    /// is expected. `mailto` is intentionally NOT touched (email-client
    /// setting).
    ///
    /// `completion` is invoked on the main queue once the https call returns.
    /// The http call runs in parallel; its result is only logged.
    static func setDefault(appURL: URL, completion: @escaping (Error?) -> Void) {
        let workspace = NSWorkspace.shared
        // https is the primary signal — wait on its completion to decide UX.
        workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https") { error in
            DispatchQueue.main.async { completion(error) }
        }
        workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http") { _ in }
    }

    static func describe(appURL: URL) -> Browser? {
        let bundle = Bundle(url: appURL)
        guard let bundleID = bundle?.bundleIdentifier else {
            return nil
        }
        if let bundle, declaresNonBrowserScheme(bundle: bundle) {
            return nil
        }
        let displayName =
            (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
            (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
            appURL.deletingPathExtension().lastPathComponent
        let version =
            (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ??
            (bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ??
            ""

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        return Browser(
            bundleID: bundleID,
            displayName: displayName,
            appURL: appURL,
            version: version,
            icon: icon
        )
    }

    private static func declaresNonBrowserScheme(bundle: Bundle) -> Bool {
        guard let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return false
        }
        for entry in urlTypes {
            guard let schemes = entry["CFBundleURLSchemes"] as? [String] else {
                continue
            }
            for scheme in schemes where nonBrowserSchemes.contains(scheme.lowercased()) {
                return true
            }
        }
        return false
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let logDateFormatter = ISO8601DateFormatter()
    private let maximumLogFileSize: UInt64 = 1_048_576

    private var updateCheckInProgress = false
    private var logDirectoryCreated = false
    private var lastRenderedDefaultBundleID: String?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        log("launch app=\(Bundle.main.bundlePath) version=\(appVersion)")

        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = appConfig.displayName

        menu.delegate = self
        statusItem.menu = menu

        // Paint the status item immediately. The menu itself rebuilds lazily
        // on first open, saving N Bundle loads + N icon fetches at startup.
        refreshStatusItemIcon(default: BrowserCatalog.currentDefault())
    }

    // MARK: Status item icon

    private func refreshStatusItemIcon(default browser: Browser?) {
        let bundleID = browser?.bundleID
        if bundleID == lastRenderedDefaultBundleID, statusItem.button?.image != nil {
            return
        }
        lastRenderedDefaultBundleID = bundleID

        let image: NSImage
        if let browser {
            image = scaledIcon(from: browser.icon, size: 18)
            statusItem.button?.toolTip = "\(appConfig.displayName) — \(browser.displayName)"
        } else {
            image = fallbackMenuBarIcon()
            statusItem.button?.toolTip = appConfig.displayName
        }

        statusItem.button?.image = image
    }

    private func scaledIcon(from icon: NSImage, size sideLength: CGFloat) -> NSImage {
        let target = NSSize(width: sideLength, height: sideLength)
        let resized = NSImage(size: target)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: icon.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        resized.unlockFocus()
        return resized
    }

    private func fallbackMenuBarIcon() -> NSImage {
        if let symbol = NSImage(systemSymbolName: "globe", accessibilityDescription: appConfig.displayName) {
            let configured = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)) ?? symbol
            configured.isTemplate = true
            return configured
        }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 14, height: 14)).stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        let snapshot = BrowserCatalog.snapshot()
        // Picks up out-of-band default-browser changes (e.g. user toggled it
        // in System Settings while our app was running).
        refreshStatusItemIcon(default: snapshot.current)

        menu.removeAllItems()

        let header = NSMenuItem(title: appConfig.displayName, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        if snapshot.browsers.isEmpty {
            let empty = NSMenuItem(title: "No browsers detected", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let currentBundleID = snapshot.current?.bundleID.lowercased()
            for browser in snapshot.browsers {
                let item = NSMenuItem(
                    title: browser.displayName,
                    action: #selector(selectBrowser(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = browser
                item.image = scaledIcon(from: browser.icon, size: 16)
                if browser.bundleID.lowercased() == currentBundleID {
                    item.state = .on
                }
                item.toolTip = browser.version.isEmpty
                    ? browser.bundleID
                    : "\(browser.displayName) \(browser.version)\n\(browser.bundleID)"
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch at login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLogin)

        let updateTitle = updateCheckInProgress ? "Checking for updates…" : "Check for updates…"
        let update = NSMenuItem(title: updateTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        update.isEnabled = !updateCheckInProgress
        menu.addItem(update)

        let gitHub = NSMenuItem(title: "GitHub Homepage", action: #selector(openGitHub), keyEquivalent: "")
        gitHub.target = self
        menu.addItem(gitHub)

        menu.addItem(.separator())

        let versionItem = NSMenuItem(title: "Version \(appVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc private func selectBrowser(_ sender: NSMenuItem) {
        guard let browser = sender.representedObject as? Browser else {
            return
        }
        log("set default bundleID=\(browser.bundleID) app=\(browser.appURL.path)")
        BrowserCatalog.setDefault(appURL: browser.appURL) { [weak self] error in
            if let error {
                self?.log("set default failed bundleID=\(browser.bundleID) error=\(error.localizedDescription)")
            } else {
                self?.log("set default succeeded bundleID=\(browser.bundleID)")
            }
        }
        // No menu refresh here — `menuWillOpen` re-reads the default the next
        // time the user opens the menu, which is after the system confirmation
        // dialog is dismissed.
    }

    @objc private func toggleLaunchAtLogin() {
        if launchAtLoginEnabled {
            disableLaunchAtLogin()
        } else {
            enableLaunchAtLogin()
        }
        rebuildMenu()
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(gitHubURL)
    }

    @objc private func checkForUpdates() {
        guard !updateCheckInProgress else {
            return
        }
        updateCheckInProgress = true
        rebuildMenu()
        log("checking updates url=\(latestReleaseURL.absoluteString)")

        var request = URLRequest(url: latestReleaseURL)
        request.httpMethod = "HEAD"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("\(appConfig.appName)/\(appVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                self?.finishUpdateCheck(response: response, error: error)
            }
        }.resume()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Update check (mirrors input-indicator)

    private func finishUpdateCheck(response: URLResponse?, error: Error?) {
        updateCheckInProgress = false
        rebuildMenu()

        if let error {
            log("update check failed error=\(error.localizedDescription)")
            showAlert(title: "Update check failed", message: error.localizedDescription)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            log("update check failed reason=missing-http-response")
            showAlert(title: "Update check failed", message: "No valid response from GitHub.")
            return
        }

        if httpResponse.statusCode == 404 {
            log("update check no latest release")
            showAlert(
                title: "No release available yet",
                message: "GitHub has no published release for this project."
            )
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            log("update check failed status=\(httpResponse.statusCode)")
            showAlert(title: "Update check failed", message: "GitHub returned HTTP \(httpResponse.statusCode).")
            return
        }

        guard let release = latestRelease(from: httpResponse) else {
            log("update check failed reason=missing-release-tag finalURL=\(httpResponse.url?.absoluteString ?? "")")
            showAlert(title: "Update check failed", message: "Could not parse the latest release tag from GitHub.")
            return
        }

        log("latest release tag=\(release.tagName) current=\(appVersion)")

        if isNewerVersion(release.tagName, than: appVersion) {
            showUpdateAvailable(release)
        } else {
            showAlert(
                title: "You're up to date",
                message: "\(appConfig.displayName) \(appVersion) is the latest version."
            )
        }
    }

    private func latestRelease(from response: HTTPURLResponse) -> GitHubRelease? {
        guard let finalURL = response.url else {
            return nil
        }
        let pathComponents = finalURL.pathComponents
        guard let tagIndex = pathComponents.firstIndex(of: "tag"),
              tagIndex + 1 < pathComponents.count else {
            return nil
        }
        let tagName = pathComponents[tagIndex + 1].removingPercentEncoding ?? pathComponents[tagIndex + 1]
        guard !tagName.isEmpty else {
            return nil
        }
        return GitHubRelease(tagName: tagName, htmlURL: finalURL)
    }

    private func showUpdateAvailable(_ release: GitHubRelease) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "New version \(release.tagName) available"
        alert.informativeText =
            "\(appConfig.displayName) is currently \(appVersion). " +
            "Open GitHub Releases to download the update?"
        alert.addButton(withTitle: "Open download page")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.htmlURL)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Launch at login (mirrors input-indicator)

    private var launchAgentURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/\(appConfig.launchAgentID).plist")
    }

    private var launchAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private func enableLaunchAtLogin() {
        do {
            try FileManager.default.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let appPath = preferredInstalledAppPath()
            try writeLaunchAgentPlist(to: launchAgentURL, appPath: appPath)

            let domain = "gui/\(getuid())"
            _ = runLaunchctl(["bootout", domain, launchAgentURL.path])
            _ = runLaunchctl(["bootstrap", domain, launchAgentURL.path])
            _ = runLaunchctl(["enable", "\(domain)/\(appConfig.launchAgentID)"])
            log("launch at login enabled app=\(appPath)")
        } catch {
            log("launch at login enable failed error=\(error.localizedDescription)")
        }
    }

    private func disableLaunchAtLogin() {
        let domain = "gui/\(getuid())"
        _ = runLaunchctl(["bootout", domain, launchAgentURL.path])
        try? FileManager.default.removeItem(at: launchAgentURL)
        log("launch at login disabled")
    }

    private func preferredInstalledAppPath() -> String {
        let systemInstalled = "/Applications/\(appConfig.appName).app"
        if FileManager.default.fileExists(atPath: systemInstalled) {
            return systemInstalled
        }
        let userInstalled = "\(NSHomeDirectory())/Applications/\(appConfig.appName).app"
        if FileManager.default.fileExists(atPath: userInstalled) {
            return userInstalled
        }
        return Bundle.main.bundlePath
    }

    private func writeLaunchAgentPlist(to url: URL, appPath: String) throws {
        let plist: [String: Any] = [
            "Label": appConfig.launchAgentID,
            "ProgramArguments": ["/usr/bin/open", "-g", appPath],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            log("launchctl failed args=\(arguments.joined(separator: " ")) error=\(error.localizedDescription)")
            return -1
        }
    }

    // MARK: Logging

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var logDirectoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs", isDirectory: true)
    }

    private var logFileURL: URL {
        logDirectoryURL.appendingPathComponent(appConfig.logFileName)
    }

    private var rotatedLogFileURL: URL {
        logFileURL.appendingPathExtension("old")
    }

    private func log(_ message: String) {
        let timestamp = logDateFormatter.string(from: Date())
        let line = "\(timestamp) \(message)\n"
        let url = logFileURL

        if let data = line.data(using: .utf8) {
            ensureLogDirectory()
            rotateLogIfNeeded(additionalBytes: data.count)
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func ensureLogDirectory() {
        guard !logDirectoryCreated else {
            return
        }
        try? FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        logDirectoryCreated = true
    }

    private func rotateLogIfNeeded(additionalBytes: Int) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value + UInt64(additionalBytes) > maximumLogFileSize else {
            return
        }
        try? FileManager.default.removeItem(at: rotatedLogFileURL)
        try? FileManager.default.moveItem(at: logFileURL, to: rotatedLogFileURL)
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
