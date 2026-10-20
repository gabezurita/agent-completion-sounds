import Cocoa

// MARK: - Helper Models & File Management

class SoundManager {
    static let shared = SoundManager()

    var soundsRoot: URL {
        if let envRoot = ProcessInfo.processInfo.environment["AGENT_SOUNDS_ROOT"], !envRoot.isEmpty {
            return URL(fileURLWithPath: envRoot).resolvingSymlinksInPath()
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("sounds").resolvingSymlinksInPath()
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
        let units = availableUnits()
        guard !units.isEmpty else { return }
        saveFavorites(Set(units))
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
            // Allow test sound even if muted globally or within turn cooldown
            var env = ProcessInfo.processInfo.environment
            env["AGENT_COMPLETION_SOUND_DISABLE"] = "0"
            env["AGENT_SOUND_COOLDOWN_SECS"] = "0"
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

// MARK: - Quota Management & Metrics

class QuotaManager {
    static let shared = QuotaManager()

    let cachePath = "/tmp/ai_quota_collector_cache.json"
    private var isFetching = false
    private var lastFetchTime: Date?

    var collectorScriptPath: String {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/scripts/ai_quota_collector.py").path
    }

    func loadCachedData() -> [String: Any]? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: cachePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return json
    }

    func getQuotaData(completion: (([String: Any]?) -> Void)? = nil) -> [String: Any]? {
        let cached = loadCachedData()
        let shouldRefresh: Bool
        if let last = lastFetchTime {
            shouldRefresh = Date().timeIntervalSince(last) > 60
        } else if let attrs = try? FileManager.default.attributesOfItem(atPath: cachePath),
                  let modDate = attrs[.modificationDate] as? Date {
            shouldRefresh = Date().timeIntervalSince(modDate) > 60
        } else {
            shouldRefresh = true
        }

        if shouldRefresh && !isFetching {
            refreshInBackground(completion: completion)
        }
        return cached
    }

    func refreshInBackground(completion: (([String: Any]?) -> Void)? = nil) {
        guard !isFetching else { return }
        isFetching = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let script = self.collectorScriptPath
            if FileManager.default.fileExists(atPath: script) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["python3", script, "--json"]
                try? process.run()
                process.waitUntilExit()
            }
            let fresh = self.loadCachedData()
            DispatchQueue.main.async {
                self.isFetching = false
                self.lastFetchTime = Date()
                completion?(fresh)
            }
        }
    }

    func menuBarSummary(style: String) -> String? {
        guard let data = loadCachedData(),
              let providers = data["providers"] as? [String: Any] else {
            return nil
        }
        var curRem: Int?
        var agyRem: Int?
        var cdxRem: Int?

        if let cur = providers["cursor"] as? [String: Any],
           cur["status"] as? String == "ok",
           let models = cur["models"] as? [String: Any],
           let curModels = models["cursor_models"] as? [String: Any],
           let rem = curModels["remaining_percent"] as? Int {
            curRem = rem
        }

        if let agy = providers["antigravity"] as? [String: Any],
           agy["status"] as? String == "ok",
           let buckets = agy["buckets"] as? [String: Any],
           let g5h = buckets["gemini_5h"] as? [String: Any],
           let rem = g5h["remaining_percent"] as? Int {
            agyRem = rem
        }

        if let cdx = providers["codex"] as? [String: Any],
           cdx["status"] as? String == "ok",
           let rl = cdx["rate_limits"] as? [String: Any],
           let f5h = rl["five_hour"] as? [String: Any],
           let rem = f5h["remaining_percent"] as? Int {
            cdxRem = rem
        }

        switch style {
        case "primary":
            if let cur = curRem { return "Cur: \(cur)%" }
            if let agy = agyRem { return "AGY: \(agy)%" }
            if let cdx = cdxRem { return "Cdx: \(cdx)%" }
            return nil
        case "compact":
            var parts: [String] = []
            if let cur = curRem { parts.append("Cur: \(cur)%") }
            if let agy = agyRem { parts.append("AGY: \(agy)%") }
            if let cdx = cdxRem { parts.append("Cdx: \(cdx)%") }
            return parts.isEmpty ? nil : parts.joined(separator: " | ")
        default:
            return nil
        }
    }

    static func renderBlocks(percent: Int, length: Int = 10) -> String {
        let clamped = max(0, min(100, percent))
        let filled = Int(round(Double(clamped) / 100.0 * Double(length)))
        let empty = length - filled
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }

    static func statusDot(remainingPct: Int) -> String {
        if remainingPct <= 15 { return "🔴" }
        if remainingPct <= 40 { return "🟠" }
        return "🟢"
    }

    static func statusColor(remainingPct: Int) -> NSColor {
        if remainingPct <= 15 { return NSColor.systemRed }
        if remainingPct <= 40 { return NSColor.systemOrange }
        return NSColor.systemGreen
    }

    static func cleanBucketLabel(_ label: String) -> String {
        switch label {
        case "Gemini Models (Five Hour Limit Remaining)": return "Gemini 5-Hour"
        case "Gemini Models (Weekly Limit Remaining)": return "Gemini Weekly"
        case "Claude and GPT models (Five Hour Limit Remaining)": return "Claude & GPT 5-Hour"
        case "Claude and GPT models (Weekly Limit Remaining)": return "Claude & GPT Weekly"
        case "Gemini 4 Argon (Gemini 4 Argon Weekly Limit)": return "Gemini 4 Argon"
        case "Cursor Models (Grok / Composer)": return "Cursor Fast Models"
        case "Other Models (API / Claude)": return "API / Other Models"
        case "Five-Hour Limit": return "Codex 5-Hour"
        case "Weekly Limit": return "Codex Weekly"
        default: return label
        }
    }

    static func formatTableRow(
        dot: String,
        name: String,
        remainingPct: Int,
        resetCountdown: String?,
        nameWidth: Int = 20
    ) -> NSAttributedString {
        let paddedName = name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
        let pctStr = String(format: "%3d%%", remainingPct)
        let clamped = max(0, min(100, remainingPct))
        let filledCount = Int(round(Double(clamped) / 100.0 * 10.0))
        let emptyCount = 10 - filledCount
        let cdStr = (resetCountdown != nil && !resetCountdown!.isEmpty) ? "resets in \(resetCountdown!)" : "ready"

        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let result = NSMutableAttributedString()

        // 1. Status Bar (▌ U+258C — 4/8 width) tinted with statusColor
        let barColor = statusColor(remainingPct: remainingPct)
        result.append(NSAttributedString(
            string: "  ▌ ",
            attributes: [.font: font, .foregroundColor: barColor]
        ))

        // 2. Name and Percentage (Crisp high-contrast labelColor)
        result.append(NSAttributedString(
            string: "\(paddedName) \(pctStr)  ",
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        ))

        // 3. Opening bracket
        result.append(NSAttributedString(
            string: "[",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        ))

        // 3. Filled meter blocks (Green / Orange / Red)
        if filledCount > 0 {
            let barColor = statusColor(remainingPct: remainingPct)
            result.append(NSAttributedString(
                string: String(repeating: "█", count: filledCount),
                attributes: [.font: font, .foregroundColor: barColor]
            ))
        }

        // 4. Empty meter track (Subtle dim)
        if emptyCount > 0 {
            result.append(NSAttributedString(
                string: String(repeating: "░", count: emptyCount),
                attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
            ))
        }

        // 5. Closing bracket and Countdown
        result.append(NSAttributedString(
            string: "]  \(cdStr)",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        ))

        return result
    }
}

// MARK: - Application Delegate & Status Item

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var modeSubmenu: NSMenu?
    private var modeExplanationField: NSTextField?

    static func makeInformationalMenuItem(attributed: NSAttributedString, height: CGFloat = 20, leftPadding: CGFloat = 14) -> NSMenuItem {
        let item = NSMenuItem()
        let field = NSTextField(labelWithAttributedString: attributed)
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.isBordered = false

        let fit = field.fittingSize
        let container = NSView(frame: NSRect(x: 0, y: 0, width: fit.width + leftPadding + 14, height: height))
        container.autoresizingMask = [.width]
        field.frame = NSRect(x: leftPadding, y: (height - fit.height) / 2, width: fit.width, height: fit.height)
        container.addSubview(field)

        item.view = container
        return item
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        updateStatusIcon()
        rebuildMenu()

        // Background timer to refresh quota data and menu bar title every 60s
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            QuotaManager.shared.refreshInBackground { _ in
                self?.updateStatusIcon()
            }
        }
    }

    var menuBarQuotaStyle: String {
        get {
            return UserDefaults.standard.string(forKey: "menuBarQuotaStyle") ?? "primary"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "menuBarQuotaStyle")
        }
    }

    var currentIconStyle: String {
        get {
            return UserDefaults.standard.string(forKey: "agentSoundsIconStyle") ?? "bot"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "agentSoundsIconStyle")
        }
    }

    func createCustomBotIcon(isMuted: Bool) -> NSImage {
        let size = NSSize(width: 19, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            
            let headX: CGFloat = 7.5
            let headY: CGFloat = 3.0
            let headW: CGFloat = 10.5
            let headH: CGFloat = 10.5
            let centerX = headX + headW / 2.0 // 12.75
            let centerY = headY + headH / 2.0 // 8.25
            
            // 1. Robot Head (stationary in both active & muted states)
            let head = NSBezierPath(roundedRect: NSRect(x: headX, y: headY, width: headW, height: headH), xRadius: 2.4, yRadius: 2.4)
            head.lineWidth = 1.3
            head.stroke()
            
            // Antenna
            let ant = NSBezierPath()
            ant.move(to: NSPoint(x: centerX, y: headY + headH))
            ant.line(to: NSPoint(x: centerX, y: headY + headH + 2.0))
            ant.lineWidth = 1.2
            ant.stroke()
            let antDot = NSBezierPath(ovalIn: NSRect(x: centerX - 1.0, y: headY + headH + 1.5, width: 2.0, height: 2.0))
            antDot.fill()
            
            if !isMuted {
                // ACTIVE: Cheerful Eyes [ ^ ‿ ^ ]
                let leftEye = NSBezierPath()
                leftEye.move(to: NSPoint(x: headX + 2.0, y: 8.8))
                leftEye.line(to: NSPoint(x: headX + 3.3, y: 10.5))
                leftEye.line(to: NSPoint(x: headX + 4.6, y: 8.8))
                leftEye.lineWidth = 1.3
                leftEye.lineCapStyle = .round
                leftEye.lineJoinStyle = .round
                leftEye.stroke()
                
                let rightEye = NSBezierPath()
                rightEye.move(to: NSPoint(x: headX + 5.9, y: 8.8))
                rightEye.line(to: NSPoint(x: headX + 7.2, y: 10.5))
                rightEye.line(to: NSPoint(x: headX + 8.5, y: 8.8))
                rightEye.lineWidth = 1.3
                rightEye.lineCapStyle = .round
                rightEye.lineJoinStyle = .round
                rightEye.stroke()
                
                // Cheerful Smile Arc (clear breathing room above bottom border)
                let smile = NSBezierPath()
                smile.appendArc(withCenter: NSPoint(x: centerX, y: 6.9), radius: 1.5, startAngle: 200, endAngle: 340, clockwise: false)
                smile.lineWidth = 1.2
                smile.lineCapStyle = .round
                smile.stroke()
                
                // 3 Curved Sound Wave Arcs on LEFT: ((( (radiating from bot outward to left)
                let arcCenter = NSPoint(x: headX + 0.5, y: centerY)
                
                // Small arc (closest to bot):
                let w1 = NSBezierPath()
                w1.appendArc(withCenter: arcCenter, radius: 2.3, startAngle: 130, endAngle: 230, clockwise: false)
                w1.lineWidth = 1.3
                w1.lineCapStyle = .round
                w1.stroke()
                
                // Medium arc (mid):
                let w2 = NSBezierPath()
                w2.appendArc(withCenter: arcCenter, radius: 4.3, startAngle: 135, endAngle: 225, clockwise: false)
                w2.lineWidth = 1.3
                w2.lineCapStyle = .round
                w2.stroke()
                
                // Big arc (outer left):
                let w3 = NSBezierPath()
                w3.appendArc(withCenter: arcCenter, radius: 6.3, startAngle: 140, endAngle: 220, clockwise: false)
                w3.lineWidth = 1.3
                w3.lineCapStyle = .round
                w3.stroke()
            } else {
                // MUTED: Sleepy / Resting Face [ - _ - ]
                let leftEye = NSBezierPath()
                leftEye.move(to: NSPoint(x: headX + 2.0, y: 8.8))
                leftEye.line(to: NSPoint(x: headX + 3.8, y: 8.8))
                leftEye.lineWidth = 1.3
                leftEye.lineCapStyle = .round
                leftEye.stroke()
                
                let rightEye = NSBezierPath()
                rightEye.move(to: NSPoint(x: headX + 6.7, y: 8.8))
                rightEye.line(to: NSPoint(x: headX + 8.5, y: 8.8))
                rightEye.lineWidth = 1.3
                rightEye.lineCapStyle = .round
                rightEye.stroke()
                
                // Quiet straight mouth
                let mouth = NSBezierPath()
                mouth.move(to: NSPoint(x: headX + 3.6, y: 6.2))
                mouth.line(to: NSPoint(x: headX + 6.9, y: 6.2))
                mouth.lineWidth = 1.2
                mouth.lineCapStyle = .round
                mouth.stroke()
            }
            
            return true
        }
        image.isTemplate = true
        return image
    }

    func createCustomBotWaveIcon(isMuted: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            
            let head = NSBezierPath(roundedRect: NSRect(x: 1.0, y: 3.0, width: 10.5, height: 10.5), xRadius: 2.4, yRadius: 2.4)
            head.lineWidth = 1.3
            head.stroke()
            
            let ant = NSBezierPath()
            ant.move(to: NSPoint(x: 6.25, y: 13.5))
            ant.line(to: NSPoint(x: 6.25, y: 15.5))
            ant.lineWidth = 1.2
            ant.stroke()
            let antDot = NSBezierPath(ovalIn: NSRect(x: 5.25, y: 15.0, width: 2.0, height: 2.0))
            antDot.fill()
            
            if !isMuted {
                // Happy Cheerful Eyes: ^  ^
                let leftEye = NSBezierPath()
                leftEye.move(to: NSPoint(x: 2.8, y: 8.8))
                leftEye.line(to: NSPoint(x: 4.1, y: 10.5))
                leftEye.line(to: NSPoint(x: 5.4, y: 8.8))
                leftEye.lineWidth = 1.3
                leftEye.lineCapStyle = .round
                leftEye.lineJoinStyle = .round
                leftEye.stroke()
                
                let rightEye = NSBezierPath()
                rightEye.move(to: NSPoint(x: 7.1, y: 8.8))
                rightEye.line(to: NSPoint(x: 8.4, y: 10.5))
                rightEye.line(to: NSPoint(x: 9.7, y: 8.8))
                rightEye.lineWidth = 1.3
                rightEye.lineCapStyle = .round
                rightEye.lineJoinStyle = .round
                rightEye.stroke()
                
                // Cheerful Smile Arc
                let smile = NSBezierPath()
                smile.appendArc(withCenter: NSPoint(x: 6.25, y: 6.9), radius: 1.5, startAngle: 200, endAngle: 340, clockwise: false)
                smile.lineWidth = 1.2
                smile.lineCapStyle = .round
                smile.stroke()
                
                let b1 = NSBezierPath(roundedRect: NSRect(x: 13.0, y: 5.5, width: 1.8, height: 5.5), xRadius: 0.9, yRadius: 0.9)
                b1.fill()
                let b2 = NSBezierPath(roundedRect: NSRect(x: 16.0, y: 3.0, width: 1.8, height: 10.5), xRadius: 0.9, yRadius: 0.9)
                b2.fill()
                let b3 = NSBezierPath(roundedRect: NSRect(x: 19.0, y: 4.8, width: 1.8, height: 7.0), xRadius: 0.9, yRadius: 0.9)
                b3.fill()
            } else {
                // Sleepy Face [ - _ - ]
                let leftEye = NSBezierPath()
                leftEye.move(to: NSPoint(x: 2.8, y: 8.8))
                leftEye.line(to: NSPoint(x: 4.6, y: 8.8))
                leftEye.lineWidth = 1.3
                leftEye.lineCapStyle = .round
                leftEye.stroke()
                
                let rightEye = NSBezierPath()
                rightEye.move(to: NSPoint(x: 7.9, y: 8.8))
                rightEye.line(to: NSPoint(x: 9.7, y: 8.8))
                rightEye.lineWidth = 1.3
                rightEye.lineCapStyle = .round
                rightEye.stroke()
                
                let mouth = NSBezierPath()
                mouth.move(to: NSPoint(x: 4.6, y: 6.2))
                mouth.line(to: NSPoint(x: 7.9, y: 6.2))
                mouth.lineWidth = 1.2
                mouth.lineCapStyle = .round
                mouth.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let isMuted = SoundManager.shared.isMuted

        switch currentIconStyle {
        case "bot-wave":
            let image = createCustomBotWaveIcon(isMuted: isMuted)
            button.image = image
        default:
            // Default: Custom Talking Bot + Sound Wave Arcs
            let image = createCustomBotIcon(isMuted: isMuted)
            button.image = image
        }
        button.title = ""
    }

    // MARK: - Menu Construction

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == self.menu else { return }
        updateStatusIcon()
        rebuildMenu()
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if menu == self.modeSubmenu {
            if let modeId = item?.representedObject as? String {
                modeExplanationField?.stringValue = modeExplanation(for: modeId)
            } else if item == nil {
                modeExplanationField?.stringValue = modeExplanation(for: SoundManager.shared.currentMode)
            }
        }
    }

    func rebuildMenu() {
        menu.removeAllItems()

        // MARK: ── 1. Agent Dashboard ──
        let dashboardHeaderAttr = NSAttributedString(
            string: "Agent Dashboard",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        )
        menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: dashboardHeaderAttr, height: 24, leftPadding: 14))
        menu.addItem(NSMenuItem.separator())

        let sm = SoundManager.shared
        let isMuted = sm.isMuted
        let currentMode = sm.currentMode
        let units = sm.availableUnits()
        let favorites = sm.loadFavorites()

        let soundsHeaderAttr = NSAttributedString(
            string: "Agent Sounds",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: soundsHeaderAttr, height: 20, leftPadding: 14))

        let toggleItem = NSMenuItem(title: "Sounds Enabled", action: #selector(toggleSoundsAction), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = isMuted ? .off : .on
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Playback Mode Submenu
        let modeMenuItem = NSMenuItem(title: "Playback Mode: \(modeDisplayName(currentMode))", action: nil, keyEquivalent: "")
        let modeSubmenu = NSMenu()
        modeSubmenu.delegate = self
        self.modeSubmenu = modeSubmenu

        let modes: [(id: String, name: String, desc: String)] = [
            ("session", "Session (Sticky Favorite)", "Sticky favorite voice per conversation"),
            ("session-all", "Session All (Sticky Full Pool)", "Sticky voice from full pool per conversation"),
            ("favorites", "Favorites (Random Turn)", "Random favorite clip every turn"),
            ("all", "All (Random Full Pool)", "Random clip from full pool every turn")
        ]

        for m in modes {
            let item = NSMenuItem(title: m.name, action: #selector(setModeAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.id
            item.toolTip = m.desc
            item.state = (currentMode == m.id) ? .on : .off
            modeSubmenu.addItem(item)
        }

        if !modes.contains(where: { $0.id == currentMode }) && units.contains(currentMode) {
            modeSubmenu.addItem(NSMenuItem.separator())
            let lockedItem = NSMenuItem(title: "Locked to '\(currentMode)'", action: nil, keyEquivalent: "")
            lockedItem.state = .on
            modeSubmenu.addItem(lockedItem)
        }

        modeSubmenu.addItem(NSMenuItem.separator())

        // Footer container for dynamic hover explanation
        let footerItem = NSMenuItem()
        let explainField = NSTextField(labelWithString: modeExplanation(for: currentMode))
        explainField.font = NSFont.systemFont(ofSize: 11)
        explainField.textColor = NSColor.secondaryLabelColor
        explainField.isEditable = false
        explainField.isSelectable = false
        explainField.drawsBackground = false
        explainField.isBordered = false
        explainField.lineBreakMode = .byWordWrapping
        explainField.maximumNumberOfLines = 2
        explainField.preferredMaxLayoutWidth = 260

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 288, height: 38))
        container.autoresizingMask = [.width]
        explainField.frame = NSRect(x: 14, y: 4, width: 260, height: 30)
        container.addSubview(explainField)
        footerItem.view = container

        self.modeExplanationField = explainField
        modeSubmenu.addItem(footerItem)

        modeMenuItem.submenu = modeSubmenu
        menu.addItem(modeMenuItem)

        // Icon Style Submenu
        let iconMenuItem = NSMenuItem(title: "Icon Style", action: nil, keyEquivalent: "")
        let iconSubmenu = NSMenu()
        let iconStyles: [(id: String, name: String)] = [
            ("bot", "Talking Bot + Sound Wave Arcs"),
            ("bot-wave", "Talking Bot + Sound Wave Bars")
        ]
        for style in iconStyles {
            let item = NSMenuItem(title: style.name, action: #selector(setIconStyleAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.id
            item.state = (currentIconStyle == style.id) ? .on : .off
            iconSubmenu.addItem(item)
        }
        iconMenuItem.submenu = iconSubmenu
        menu.addItem(iconMenuItem)

        // Favorites Submenu
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

        // Add Sound Files Submenu
        let addMenuItem = NSMenuItem(title: "Add Sound Files", action: nil, keyEquivalent: "")
        let addSubmenu = NSMenu()

        let finderItem = NSMenuItem(title: "Open ~/sounds in Finder", action: #selector(openFinderAction), keyEquivalent: "o")
        finderItem.target = self
        addSubmenu.addItem(finderItem)

        let importItem = NSMenuItem(title: "Import Audio Files or Folder...", action: #selector(importSoundsAction), keyEquivalent: "i")
        importItem.target = self
        addSubmenu.addItem(importItem)

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

        // Actions
        let testSoundItem = NSMenuItem(title: "Play Test Sound", action: #selector(playTestSoundAction), keyEquivalent: "t")
        testSoundItem.target = self
        menu.addItem(testSoundItem)

        let clearSessionsItem = NSMenuItem(title: "Reset Active Sessions", action: #selector(clearSessionsAction), keyEquivalent: "")
        clearSessionsItem.target = self
        clearSessionsItem.toolTip = "Clear concurrent session voice bindings"
        menu.addItem(clearSessionsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Agent Dashboard", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.addItem(NSMenuItem.separator())

        // MARK: ── 2. AI Quotas Section ──
        let payload = QuotaManager.shared.getQuotaData()
        let providers = payload?["providers"] as? [String: Any] ?? [:]
        
        var timeStr = ""
        if let collected = payload?["collected_at"] as? String, collected.count >= 16 {
            let prefix16 = String(collected.prefix(16))
            let timePart = String(prefix16.suffix(5))
            timeStr = " (Synced \(timePart) UTC)"
        }

        let quotaHeaderAttr = NSAttributedString(
            string: "AI Quotas\(timeStr)",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
        )
        menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: quotaHeaderAttr, height: 22, leftPadding: 14))

        let colHeaderStr = "      " + "QUOTA BUCKET".padding(toLength: 20, withPad: " ", startingAt: 0) + " " + "LEFT".padding(toLength: 4, withPad: " ", startingAt: 0) + "   " + "PROGRESS".padding(toLength: 12, withPad: " ", startingAt: 0) + "  " + "RESETS IN"
        let colHeaderAttr = NSAttributedString(
            string: colHeaderStr,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: colHeaderAttr, height: 18, leftPadding: 14))

        menu.addItem(NSMenuItem.separator())

        // Cursor Section
        if let cursor = providers["cursor"] as? [String: Any], cursor["status"] as? String == "ok" {
            let countdown = cursor["reset_countdown"] as? String
            let cdStr = (countdown != nil && !countdown!.isEmpty) ? " · Resets in \(countdown!)" : ""
            let cursorHeaderAttr = NSAttributedString(
                string: "Cursor Pro\(cdStr)",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
            )
            menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: cursorHeaderAttr, height: 20, leftPadding: 14))

            if let models = cursor["models"] as? [String: Any] {
                for mkey in ["cursor_models", "other_models"] {
                    guard let m = models[mkey] as? [String: Any] else { continue }
                    let rem = m["remaining_percent"] as? Int ?? 0
                    let dot = QuotaManager.statusDot(remainingPct: rem)
                    let rawLabel = m["label"] as? String ?? mkey
                    let cleanLabel = QuotaManager.cleanBucketLabel(rawLabel)
                    let rowAttr = QuotaManager.formatTableRow(dot: dot, name: cleanLabel, remainingPct: rem, resetCountdown: countdown)
                    menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: rowAttr, height: 20, leftPadding: 14))
                }
            }

            if let spend = cursor["spend_limit"] as? [String: Any] {
                let remUsd = spend["remaining_usd"] as? Double ?? 0.0
                let limUsd = spend["limit_usd"] as? Double ?? 0.0
                let spendStr = String(format: "    Spend Limit Runway: $%.2f / $%.2f", remUsd, limUsd)
                let spendAttr = NSAttributedString(
                    string: spendStr,
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
                )
                menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: spendAttr, height: 18, leftPadding: 14))
            }

            let settingsItem = NSMenuItem(title: "    Open Cursor Settings…", action: #selector(openURLAction(_:)), keyEquivalent: "")
            settingsItem.attributedTitle = NSAttributedString(
                string: "    Open Cursor Settings…",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
            )
            settingsItem.representedObject = "cursor://settings"
            settingsItem.target = self
            menu.addItem(settingsItem)

            menu.addItem(NSMenuItem.separator())
        }

        // Antigravity Section
        if let agy = providers["antigravity"] as? [String: Any], agy["status"] as? String == "ok" {
            let agyHeaderAttr = NSAttributedString(
                string: "Google Antigravity (agy CLI)",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
            )
            menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: agyHeaderAttr, height: 20, leftPadding: 14))

            let bucketOrder = ["gemini_weekly", "gemini_5h", "3p_weekly", "3p_5h", "gemini_argon_wtu_weekly"]
            if let buckets = agy["buckets"] as? [String: Any] {
                for bkey in bucketOrder {
                    guard let b = buckets[bkey] as? [String: Any] else { continue }
                    let rem = b["remaining_percent"] as? Int ?? 0
                    let dot = QuotaManager.statusDot(remainingPct: rem)
                    let rawLabel = b["label"] as? String ?? bkey
                    let cleanLabel = QuotaManager.cleanBucketLabel(rawLabel)
                    let cd = b["reset_countdown"] as? String
                    let rowAttr = QuotaManager.formatTableRow(dot: dot, name: cleanLabel, remainingPct: rem, resetCountdown: cd)
                    menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: rowAttr, height: 20, leftPadding: 14))
                }
            }
            menu.addItem(NSMenuItem.separator())
        }

        // OpenAI Codex Section
        if let cdx = providers["codex"] as? [String: Any], cdx["status"] as? String == "ok" {
            let planStr = cdx["plan_type"] as? String ?? (cdx["auth_mode"] as? String ?? "ChatGPT")
            let cdxHeaderAttr = NSAttributedString(
                string: "OpenAI Codex (\(planStr))",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
            )
            menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: cdxHeaderAttr, height: 20, leftPadding: 14))

            if let rl = cdx["rate_limits"] as? [String: Any] {
                for rkey in ["weekly", "five_hour"] {
                    guard let r = rl[rkey] as? [String: Any] else { continue }
                    let rem = r["remaining_percent"] as? Int ?? 0
                    let dot = QuotaManager.statusDot(remainingPct: rem)
                    let rawLabel = r["label"] as? String ?? rkey
                    let cleanLabel = QuotaManager.cleanBucketLabel(rawLabel)
                    let cd = r["reset_countdown"] as? String
                    let rowAttr = QuotaManager.formatTableRow(dot: dot, name: cleanLabel, remainingPct: rem, resetCountdown: cd)
                    menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: rowAttr, height: 20, leftPadding: 14))
                }
            }

            if let credits = cdx["reset_credits_available"] as? Int, credits > 0 {
                let credStr = "    Reset Credits Available: \(credits) credits"
                let credAttr = NSAttributedString(
                    string: credStr,
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
                )
                menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: credAttr, height: 18, leftPadding: 14))
            }

            let threads = cdx["total_threads"] as? Int ?? 0
            let tokens = cdx["lifetime_tokens_recorded"] as? Int ?? 0
            if threads > 0 || tokens > 0 {
                let numFormatter = NumberFormatter()
                numFormatter.numberStyle = .decimal
                let tokenStr = numFormatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"

                let threadAttr = NSAttributedString(
                    string: "    Active Session Threads: \(threads)",
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
                )
                menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: threadAttr, height: 18, leftPadding: 14))

                let tokenAttr = NSAttributedString(
                    string: "    Tracked Lifetime Tokens: \(tokenStr)",
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
                )
                menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: tokenAttr, height: 18, leftPadding: 14))
            }
            menu.addItem(NSMenuItem.separator())
        }

        // Claude Code Section
        if let claude = providers["claude"] as? [String: Any], claude["status"] as? String == "ok" {
            let claudeHeaderAttr = NSAttributedString(
                string: "Claude Code (Local Telemetry)",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
            )
            menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: claudeHeaderAttr, height: 20, leftPadding: 14))

            let sessions = claude["total_sessions"] as? Int ?? 0
            let messages = claude["total_messages"] as? Int ?? 0
            let numFormatter = NumberFormatter()
            numFormatter.numberStyle = .decimal
            let msgStr = numFormatter.string(from: NSNumber(value: messages)) ?? "\(messages)"

            let sessAttr = NSAttributedString(
                string: "    Lifetime Sessions: \(sessions) sessions",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
            )
            menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: sessAttr, height: 18, leftPadding: 14))

            let msgAttr = NSAttributedString(
                string: "    Total Messages Recorded: \(msgStr)",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
            )
            menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: msgAttr, height: 18, leftPadding: 14))

            if let today = claude["today"] as? [String: Any], let todayCount = today["message_count"] as? Int, todayCount > 0 {
                let todayAttr = NSAttributedString(
                    string: "    Today's Messages: \(todayCount)",
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
                )
                menu.addItem(AppDelegate.makeInformationalMenuItem(attributed: todayAttr, height: 18, leftPadding: 14))
            }

            menu.addItem(NSMenuItem.separator())
        }

        // Quota Actions
        let webItem = NSMenuItem(title: "Open Web Dashboard (localhost:3333)", action: #selector(openURLAction(_:)), keyEquivalent: "")
        webItem.representedObject = "http://localhost:3333"
        webItem.target = self
        menu.addItem(webItem)

        let refreshItem = NSMenuItem(title: "Force Refresh All Quotas", action: #selector(refreshQuotasAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())


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

    private func modeExplanation(for id: String) -> String {
        switch id {
        case "session":
            return "Locks each conversation to a unique favorite voice so you can tell active agents apart by ear."
        case "session-all":
            return "Locks each conversation to a unique voice drawn from all installed sound packs."
        case "favorites":
            return "Plays a random sound clip from your favorites every turn (no conversation stickiness)."
        case "all":
            return "Plays a random sound clip from all installed sound packs every turn (maximum variety)."
        default:
            return "Completions play sounds exclusively from the '\(id)' sound pack."
        }
    }

    // MARK: - Actions

    @objc func openURLAction(_ sender: NSMenuItem) {
        if let urlStr = sender.representedObject as? String, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func refreshQuotasAction() {
        QuotaManager.shared.refreshInBackground { [weak self] _ in
            self?.updateStatusIcon()
            self?.rebuildMenu()
        }
    }

    @objc func setMenuBarQuotaStyleAction(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? String else { return }
        menuBarQuotaStyle = style
        updateStatusIcon()
        rebuildMenu()
    }

    @objc func noopAction() {}

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

    @objc func setIconStyleAction(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? String else { return }
        currentIconStyle = style
        updateStatusIcon()
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
        let userSounds = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("sounds")
        if FileManager.default.fileExists(atPath: userSounds.path) {
            NSWorkspace.shared.open(userSounds)
        } else {
            NSWorkspace.shared.open(root)
        }
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
            let resolvedRoot = sm.soundsRoot

            // Case 1: A single directory was chosen
            if urls.count == 1, (try? urls[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let folderURL = urls[0].resolvingSymlinksInPath()

                if folderURL.path == resolvedRoot.path {
                    showAlert(title: "Already in ~/sounds", message: "The selected folder is already your active sounds directory.")
                    return
                }

                let audioExtensions = Set(["wav", "mp3", "aif", "aiff", "m4a", "ogg", "aac", "flac"])
                let contents = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                let directAudioFiles = contents.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
                let subDirectories = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true && $0.lastPathComponent != "sounds" && $0.lastPathComponent != "scratch" }

                if !subDirectories.isEmpty && directAudioFiles.isEmpty {
                    // Folder is a collection of sound packs (e.g. backup of ~/sounds)
                    var importedPacks = 0
                    for packDir in subDirectories {
                        let targetDir = resolvedRoot.appendingPathComponent(packDir.lastPathComponent)
                        if copyOrMergePackDirectory(from: packDir, to: targetDir) {
                            importedPacks += 1
                        }
                    }
                    showNotification(title: "Sound Packs Imported", message: "Imported \(importedPacks) sound pack(s) into ~/sounds.")
                } else {
                    let packName = (folderURL.lastPathComponent == "sounds") ? "custom-sounds" : folderURL.lastPathComponent
                    let targetDir = resolvedRoot.appendingPathComponent(packName)
                    if copyOrMergePackDirectory(from: folderURL, to: targetDir) {
                        showNotification(title: "Sound Pack Imported", message: "Imported folder '\(packName)' into ~/sounds.")
                    } else {
                        showAlert(title: "Import Failed", message: "Could not import sound pack.")
                    }
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
                let destDir = resolvedRoot.appendingPathComponent(packName)
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

    @discardableResult
    private func copyOrMergePackDirectory(from src: URL, to dst: URL) -> Bool {
        let fileManager = FileManager.default
        let audioExtensions = Set(["wav", "mp3", "aif", "aiff", "m4a", "ogg", "aac", "flac"])
        do {
            try fileManager.createDirectory(at: dst, withIntermediateDirectories: true)
            let files = try fileManager.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
            for f in files {
                if audioExtensions.contains(f.pathExtension.lowercased()) {
                    let target = dst.appendingPathComponent(f.lastPathComponent)
                    if !fileManager.fileExists(atPath: target.path) {
                        try? fileManager.copyItem(at: f, to: target)
                    }
                }
            }
            return true
        } catch {
            return false
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
