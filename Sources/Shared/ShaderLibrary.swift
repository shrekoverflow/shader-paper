import Foundation

struct ShaderEntry: Identifiable {
    let id: String
    let sourceURL: URL
    let thumbnailURL: URL
    var name: String { id }
}

enum ShaderLibrary {
    static let provider = "com.avisualmeditation.wallpaper.shader-extension"
    static let defaultShader = "GPT6-Astra-II"
    static var entries: [ShaderEntry] {
        guard let resources = Bundle.main.resourceURL else { return [] }
        return entries(in: resources)
    }
    static func entries(in resources: URL) -> [ShaderEntry] {
        let root = resources.appendingPathComponent("shaders")
        return ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "shader" }
            .map { ShaderEntry(id: $0.deletingPathExtension().lastPathComponent, sourceURL: $0,
                thumbnailURL: resources.appendingPathComponent("Previews/\($0.deletingPathExtension().lastPathComponent).png")) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
    static func entry(_ name: String) -> ShaderEntry? { entries.first { $0.id == name } }
}
