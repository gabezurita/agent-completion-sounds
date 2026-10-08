import Cocoa

// MARK: - Helper Models & File Management

class SoundManager {
    static let shared = SoundManager()

    var soundsRoot: URL {
        if let envRoot = ProcessInfo.processInfo.environment["AGENT_SOUNDS_ROOT"], !envRoot.isEmpty {
            return URL(fileURLWithPath: envRoot)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("sounds")
    }

    var disabledFileURL: URL {
        return soundsRoot.appendingPathComponent(".disabled")
    }

    var modeFileURL: URL {
        return soundsRoot.appendingPathComponent(".mode")
    }

    var favoritesFileURL: URL {
        return soundsRoot.appendingPathComponent("favorites.txt")
    }

    var isMuted: Bool {
        return FileManager.default.fileExists(atPath: disabledFileURL.path)
    }

    func setMuted(_ muted: Bool) {
        if muted {
            FileManager.default.createFile(atPath: disabledFileURL.path, contents: nil, attributes: nil)
        } else {
            try? FileManager.default.removeItem(at: disabledFileURL)
        }
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    var currentMode: String {
        if let content = try? String(contentsOf: modeFileURL, encoding: .utf8) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "session"
    }

    func setMode(_ mode: String) {
        try? FileManager.default.createDirectory(at: soundsRoot, withIntermediateDirectories: true)
        try? (mode + "\n").write(to: modeFileURL, atomically: true, encoding: .utf8)
    }

    func availableUnits() -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: soundsRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var units: [String] = []
        for item in items {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                let name = item.lastPathComponent
                if name != "scratch" && !name.hasPrefix(".") {
                    units.append(name)
                }
            }
        }
        return units.sorted()
    }

    func loadFavorites() -> Set<String> {
        guard let content = try? String(contentsOf: favoritesFileURL, encoding: .utf8) else {
            return []
        }
        var set = Set<String>()
        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            // Ignore trailing inline comment
            let parts = line.components(separatedBy: "#")
            let unit = parts[0].trimmingCharacters(in: .whitespaces)
            if !unit.isEmpty {
                set.insert(unit)
            }
        }
        return set
    }

    func saveFavorites(_ favorites: Set<String>) {
        try? FileManager.default.createDirectory(at: soundsRoot, withIntermediateDirectories: true)
        let sorted = favorites.sorted()
        let content = "# Favorite clip folders (one per line)\n" + sorted.joined(separator: "\n") + "\n"
        try? content.write(to: favoritesFileURL, atomically: true, encoding: .utf8)
    }

    func toggleFavorite(_ unit: String) {
        var favs = loadFavorites()
        if favs.contains(unit) {
            favs.remove(unit)
        } else {
            favs.insert(unit)
        }
        saveFavorites(favs)
    }

    func selectAllFavorites() {
        let all = Set(availableUnits())
        saveFavorites(all)
    }

    func clearAllFavorites() {
        saveFavorites([])
    }

    func findScript(named name: String) -> String? {
        let fileManager = FileManager.default

        // 1. Check relative to application bundle
        let bundleURL = Bundle.main.bundleURL
        let candidates = [
            bundleURL.deletingLastPathComponent().appendingPathComponent("scripts/\(name)"),
            bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/\(name)"),
            bundleURL.appendingPathComponent("Contents/Resources/\(name)"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/\(name)"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("code/agent-completion-sounds/scripts/\(name)")
        ]

        for cand in candidates {
            if fileManager.isExecutableFile(atPath: cand.path) {
                return cand.path
            }
        }

        // 2. PATH lookup
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
            return output
        }

        return nil
    }

    func playTestSound() {
        if let script = findScript(named: "play-random-completion-sound.sh") ?? findScript(named: "play-random-completion-sound") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: script)
            task.arguments = ["stop"]
            // Allow test sound even if muted globally
            var env = ProcessInfo.processInfo.environment
            env["AGENT_COMPLETION_SOUND_DISABLE"] = "0"
            task.environment = env
            let inPipe = Pipe()
            task.standardInput = inPipe
            try? task.run()
            inPipe.fileHandleForWriting.write("{\"conversationId\":\"test-ui-ping\",\"executionNum\":1}\n".data(using: .utf8)!)
            inPipe.fileHandleForWriting.closeFile()
        } else {
            // Fallback: pick a random file from soundsRoot
            let units = availableUnits()
            var audioFiles: [URL] = []
            let extensions = ["wav", "mp3", "aif", "aiff", "m4a", "ogg"]
            for u in units {
                let dir = soundsRoot.appendingPathComponent(u)
                if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                    for f in files where extensions.contains(f.pathExtension.lowercased()) {
                        audioFiles.append(f)
                    }
                }
            }
            if let clip = audioFiles.randomElement() {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                task.arguments = [clip.path]
                try? task.run()
            }
        }
    }

    func clearSessions() {
        let cacheDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agent-sound-sessions")
        try? FileManager.default.removeItem(at: cacheDir)
    }

    func availableCuratedSets() -> [String] {
        var sets: [String] = []
        let manifestURLs = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("scripts/completion-sound-sets.default.txt"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("code/agent-completion-sounds/scripts/completion-sound-sets.default.txt"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/completion-sound-sets.default.txt")
        ]
        for url in manifestURLs {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                    let parts = trimmed.components(separatedBy: "|")
                    if let first = parts.first, !first.isEmpty, !sets.contains(first) {
                        sets.append(first)
                    }
                }
                break
            }
        }
        return sets.isEmpty ? ["kenney-ui"] : sets
    }

    func fetchCuratedSet(_ setName: String, completion: @escaping (Bool, String) -> Void) {
        guard let script = findScript(named: "fetch-completion-sounds.sh") ?? findScript(named: "soundfetch") else {
            completion(false, "Could not find fetch-completion-sounds.sh script.")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: script)
            task.arguments = [setName]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    completion(task.terminationStatus == 0, output)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Application Delegate & Status Item

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        updateStatusIcon()
        rebuildMenu()
    }

    func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let isMuted = SoundManager.shared.isMuted
        let symbolName = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isMuted ? "Sounds Muted" : "Sounds Active") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = isMuted ? "🔇" : "🔊"
        }
    }

    // MARK: - Menu Construction

    func menuWillOpen(_ menu: NSMenu) {
        updateStatusIcon()
        rebuildMenu()
    }

    func rebuildMenu() {
        menu.removeAllItems()

        let sm = SoundManager.shared
        let isMuted = sm.isMuted
        let currentMode = sm.currentMode
        let units = sm.availableUnits()
        let favorites = sm.loadFavorites()

        // 1. Mute / Toggle Sounds
        let toggleItem = NSMenuItem(title: "Sounds Enabled", action: #selector(toggleSoundsAction), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = isMuted ? .off : .on
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Playback Mode Submenu
        let modeMenuItem = NSMenuItem(title: "Playback Mode: \(modeDisplayName(currentMode))", action: nil, keyEquivalent: "")
        let modeSubmenu = NSMenu()

        let modes: [(id: String, name: String, desc: String)] = [
            ("session", "Session (Sticky Favorite)", "Sticky favorite unit per conversation"),
            ("session-all", "Session All (Sticky Full Pool)", "Sticky unit from full pool per conversation"),
            ("favorites", "Favorites (Random Turn)", "Random favorite unit every turn"),
            ("all", "All (Random Full Pool)", "Random unit from full pool every turn")
        ]

        for m in modes {
            let item = NSMenuItem(title: m.name, action: #selector(setModeAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.id
            item.toolTip = m.desc
            item.state = (currentMode == m.id) ? .on : .off
            modeSubmenu.addItem(item)
        }

        // Check if locked to a unit
        if !modes.contains(where: { $0.id == currentMode }) && units.contains(currentMode) {
            modeSubmenu.addItem(NSMenuItem.separator())
            let lockedItem = NSMenuItem(title: "Locked to '\(currentMode)'", action: nil, keyEquivalent: "")
            lockedItem.state = .on
            modeSubmenu.addItem(lockedItem)
        }

        modeMenuItem.submenu = modeSubmenu
        menu.addItem(modeMenuItem)

        // 3. Favorites Submenu
        let favCount = favorites.count
        let totalCount = units.count
        let favMenuItem = NSMenuItem(title: "Favorites (\(favCount)/\(totalCount))", action: nil, keyEquivalent: "")
        let favSubmenu = NSMenu()

        let selectAllItem = NSMenuItem(title: "Select All as Favorites", action: #selector(selectAllFavoritesAction), keyEquivalent: "")
        selectAllItem.target = self
        favSubmenu.addItem(selectAllItem)

        let clearAllItem = NSMenuItem(title: "Clear All Favorites", action: #selector(clearAllFavoritesAction), keyEquivalent: "")
        clearAllItem.target = self
        favSubmenu.addItem(clearAllItem)

        favSubmenu.addItem(NSMenuItem.separator())

        if units.isEmpty {
            let emptyItem = NSMenuItem(title: "(No sound packs in ~/sounds)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            favSubmenu.addItem(emptyItem)
        } else {
            for unit in units {
                let isFav = favorites.contains(unit)
                let unitItem = NSMenuItem(title: unit, action: #selector(toggleFavoriteAction(_:)), keyEquivalent: "")
                unitItem.target = self
                unitItem.representedObject = unit
                unitItem.state = isFav ? .on : .off
                favSubmenu.addItem(unitItem)
            }
        }

        favMenuItem.submenu = favSubmenu
        menu.addItem(favMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Add Sound Files Submenu (Options A, B, C)
        let addMenuItem = NSMenuItem(title: "Add Sound Files", action: nil, keyEquivalent: "")
        let addSubmenu = NSMenu()

        // Option A: Open ~/sounds in Finder
        let finderItem = NSMenuItem(title: "Open ~/sounds in Finder", action: #selector(openFinderAction), keyEquivalent: "o")
        finderItem.target = self
        addSubmenu.addItem(finderItem)

        // Option B: Import Audio Files or Folder
        let importItem = NSMenuItem(title: "Import Audio Files or Folder...", action: #selector(importSoundsAction), keyEquivalent: "i")
        importItem.target = self
        addSubmenu.addItem(importItem)

        // Option C: Download Curated Packs
        let curatedSets = sm.availableCuratedSets()
        let fetchMenuItem = NSMenuItem(title: "Download Curated Packs", action: nil, keyEquivalent: "")
        let fetchSubmenu = NSMenu()

        for s in curatedSets {
            let setItem = NSMenuItem(title: "Download '\(s)'", action: #selector(downloadSetAction(_:)), keyEquivalent: "")
            setItem.target = self
            setItem.representedObject = s
            fetchSubmenu.addItem(setItem)
        }
        let fetchAllItem = NSMenuItem(title: "Download All Curated Sets", action: #selector(downloadAllSetsAction), keyEquivalent: "")
        fetchAllItem.target = self
        fetchSubmenu.addItem(fetchAllItem)

        fetchMenuItem.submenu = fetchSubmenu
        addSubmenu.addItem(fetchMenuItem)

        addMenuItem.submenu = addSubmenu
        menu.addItem(addMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Actions
        let testSoundItem = NSMenuItem(title: "Play Test Sound", action: #selector(playTestSoundAction), keyEquivalent: "t")
        testSoundItem.target = self
        menu.addItem(testSoundItem)

        let clearSessionsItem = NSMenuItem(title: "Reset Active Sessions", action: #selector(clearSessionsAction), keyEquivalent: "")
        clearSessionsItem.target = self
        clearSessionsItem.toolTip = "Clear concurrent session voice bindings"
        menu.addItem(clearSessionsItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Quit
        let quitItem = NSMenuItem(title: "Quit Agent Sounds", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func modeDisplayName(_ id: String) -> String {
        switch id {
        case "session": return "Session (Sticky)"
        case "session-all": return "Session All (Pool)"
        case "favorites": return "Favorites (Turn)"
        case "all": return "All (Turn)"
        default: return id
        }
    }

    // MARK: - Actions

    @objc func toggleSoundsAction() {
        SoundManager.shared.toggleMute()
        updateStatusIcon()
        rebuildMenu()
    }

    @objc func setModeAction(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        SoundManager.shared.setMode(mode)
        rebuildMenu()
    }

    @objc func toggleFavoriteAction(_ sender: NSMenuItem) {
        guard let unit = sender.representedObject as? String else { return }
        SoundManager.shared.toggleFavorite(unit)
        rebuildMenu()
    }

    @objc func selectAllFavoritesAction() {
        SoundManager.shared.selectAllFavorites()
        rebuildMenu()
    }

    @objc func clearAllFavoritesAction() {
        SoundManager.shared.clearAllFavorites()
        rebuildMenu()
    }

    @objc func openFinderAction() {
        let root = SoundManager.shared.soundsRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    @objc func importSoundsAction() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [] // allow all audio types or directories
        panel.prompt = "Import"
        panel.message = "Select audio files (.wav, .mp3, etc.) or a directory of sounds to import"

        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }

            let sm = SoundManager.shared
            let fileManager = FileManager.default

            // Case 1: A single directory was chosen
            if urls.count == 1, (try? urls[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let folderURL = urls[0]
                let dest = sm.soundsRoot.appendingPathComponent(folderURL.lastPathComponent)
                do {
                    if fileManager.fileExists(atPath: dest.path) {
                        // Merge contents
                        let files = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                        for f in files {
                            let target = dest.appendingPathComponent(f.lastPathComponent)
                            if !fileManager.fileExists(atPath: target.path) {
                                try fileManager.copyItem(at: f, to: target)
                            }
                        }
                    } else {
                        try fileManager.copyItem(at: folderURL, to: dest)
                    }
                    showNotification(title: "Sound Pack Imported", message: "Imported folder '\(folderURL.lastPathComponent)' into ~/sounds.")
                } catch {
                    showAlert(title: "Import Failed", message: error.localizedDescription)
                }
                rebuildMenu()
                return
            }

            // Case 2: One or more files selected -> prompt for pack name
            let alert = NSAlert()
            alert.messageText = "Import Sound Pack"
            alert.informativeText = "Enter a folder name for these sound files in ~/sounds:"
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            input.stringValue = "custom-clips"
            alert.accessoryView = input
            alert.addButton(withTitle: "Import")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                let packName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !packName.isEmpty else { return }
                let destDir = sm.soundsRoot.appendingPathComponent(packName)
                try? fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)

                var copied = 0
                for fileURL in urls {
                    let target = destDir.appendingPathComponent(fileURL.lastPathComponent)
                    if !fileManager.fileExists(atPath: target.path) {
                        do {
                            try fileManager.copyItem(at: fileURL, to: target)
                            copied += 1
                        } catch {}
                    }
                }
                showNotification(title: "Sounds Imported", message: "Added \(copied) clip(s) to ~/sounds/\(packName).")
                rebuildMenu()
            }
        }
    }

    @objc func downloadSetAction(_ sender: NSMenuItem) {
        guard let setName = sender.representedObject as? String else { return }
        showNotification(title: "Downloading Sounds", message: "Fetching sound set '\(setName)'...")
        SoundManager.shared.fetchCuratedSet(setName) { [weak self] success, output in
            if success {
                self?.showNotification(title: "Download Complete", message: "Sound set '\(setName)' downloaded to ~/sounds.")
                self?.rebuildMenu()
            } else {
                self?.showAlert(title: "Download Failed", message: output)
            }
        }
    }

    @objc func downloadAllSetsAction() {
        showNotification(title: "Downloading Sounds", message: "Fetching all curated sound sets...")
        SoundManager.shared.fetchCuratedSet("") { [weak self] success, output in
            if success {
                self?.showNotification(title: "Download Complete", message: "All curated sounds downloaded to ~/sounds.")
                self?.rebuildMenu()
            } else {
                self?.showAlert(title: "Download Failed", message: output)
            }
        }
    }

    @objc func playTestSoundAction() {
        SoundManager.shared.playTestSound()
    }

    @objc func clearSessionsAction() {
        SoundManager.shared.clearSessions()
        showNotification(title: "Sessions Cleared", message: "Active session sound bindings have been reset.")
    }

    @objc func quitAction() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showNotification(title: String, message: String) {
        let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMsg = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedMsg)\" with title \"\(escapedTitle)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
