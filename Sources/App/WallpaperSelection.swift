import AppKit

enum WallpaperSelection {
    static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Visual Meditation")
    static let index = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    @discardableResult static func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.standardOutput = output; process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { throw failure(text.isEmpty ? "Wallpaper registration failed" : text) }
        return text
    }
    static func register() throws {
        let bundle = Bundle.main.bundleURL.appendingPathComponent("Contents/Extensions/MeditationExtension.appex")
        try run("/usr/bin/pluginkit", ["-a", bundle.path])
    }
    static func containsOurs(_ value: Any) -> Bool {
        if let dict = value as? [String: Any] {
            return dict["Provider"] as? String == ShaderLibrary.provider || dict.values.contains(where: containsOurs)
        }
        return (value as? [Any])?.contains(where: containsOurs) ?? false
    }
    static func selected(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if dict["Provider"] as? String == ShaderLibrary.provider, let data = dict["Configuration"] as? Data {
                return String(data: data, encoding: .utf8)
            }
            return dict.values.compactMap { selected(in: $0) }.first
        }
        return (value as? [Any])?.compactMap { selected(in: $0) }.first
    }
    static func current() -> String? {
        guard let data = try? Data(contentsOf: index), let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        return selected(in: plist)
    }
    static func linked(_ current: [String: Any], shader: String, date: Date = Date()) throws -> [String: Any] {
        var result = current
        let options = try PropertyListSerialization.data(fromPropertyList: ["values": ["placement": ["picker": ["_0": ["id": "FillScreen"]]]]], format: .binary, options: 0)
        let container: [String: Any] = ["Type": "linked", "Linked": ["LastSet": date, "LastUse": date, "Content": [
            "Choices": [["Provider": ShaderLibrary.provider, "Files": [], "Configuration": Data(shader.utf8)]],
            "Shuffle": "$null", "EncodedOptionValues": options]]]
        result["AllSpacesAndDisplays"] = container; result["SystemDefault"] = container
        result["Displays"] = [String: Any](); result["Spaces"] = [String: Any]()
        return result
    }
    static func restoring(_ current: Any, previous: Any) -> Any {
        guard let current = current as? [String: Any] else { return current }
        if let type = current["Type"] as? String, ["linked", "individual"].contains(type), containsOurs(current) { return previous }
        let previous = previous as? [String: Any] ?? [:]
        var result = current.reduce(into: [String: Any]()) { result, pair in
            result[pair.key] = restoring(pair.value, previous: previous[pair.key] ?? [String: Any]())
        }
        // Activation linked every display and cleared its old overrides. Bring
        // those back too, while giving subsequent user selections precedence.
        if let linked = current["AllSpacesAndDisplays"], containsOurs(linked) {
            for key in ["Displays", "Spaces"] {
                let old = previous[key] as? [String: Any] ?? [:]
                let newer = result[key] as? [String: Any] ?? [:]
                result[key] = old.merging(newer) { _, new in new }
            }
        }
        return result
    }
    static func update(_ transform: ([String: Any], Data) throws -> Any) throws {
        // Prevent the agent's old in-memory selection from overwriting an atomic
        // edit. Always resume it on failure. This touches only our user's agent.
        let found = (try? run("/usr/bin/pgrep", ["-u", String(getuid()), "-x", "WallpaperAgent"])) ?? ""
        let pids = found.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
        var suspended = [pid_t](), committed = false
        defer { for pid in suspended { kill(pid, committed ? SIGKILL : SIGCONT) } }
        for pid in pids { if kill(pid, SIGSTOP) == 0 { suspended.append(pid) } }
        let data = try Data(contentsOf: index)
        guard let current = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw failure("Unrecognized wallpaper settings") }
        let updated = try transform(current, data)
        let serialized = try PropertyListSerialization.data(fromPropertyList: updated, format: .binary, options: 0)
        try serialized.write(to: index, options: .atomic)
        committed = true
    }
    static func activate(_ shader: String) throws {
        guard ShaderLibrary.entry(shader) != nil else { throw failure("Unknown shader: \(shader)") }
        try register()
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try update { current, data in
            let backup = support.appendingPathComponent("backups/\(UUID().uuidString).plist")
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: backup, options: .atomic)
            if !containsOurs(current) || !FileManager.default.fileExists(atPath: support.appendingPathComponent("Previous.plist").path) {
                try data.write(to: support.appendingPathComponent("Previous.plist"), options: .atomic)
            }
            return try linked(current, shader: shader)
        }
    }
    static func restore() throws {
        let previous = try PropertyListSerialization.propertyList(from: Data(contentsOf: support.appendingPathComponent("Previous.plist")), format: nil)
        try update { current, data in
            try data.write(to: support.appendingPathComponent("Before Restore.plist"), options: .atomic)
            return restoring(current, previous: previous)
        }
    }
}
