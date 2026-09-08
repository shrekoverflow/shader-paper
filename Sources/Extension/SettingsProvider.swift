// Codable/XPC remapping adapted from Phosphene (MIT, ../../LICENSE.phosphene).
import Foundation

func buildSettingsViewModelsXPC() -> AnyObject? {
    let provider = ChoiceProviderID(rawValue: ShaderLibrary.provider)
    let items = ShaderLibrary.entries.map { entry -> SettingsItem in
        let id = ChoiceID(id: entry.id, descriptor: ChoiceIDDescriptor(provider: provider,
            identifier: entry.id, files: [], configuration: Data(entry.id.utf8)))
        return SettingsItem(id: id, localizedName: entry.name, thumbnail: .image(url: entry.thumbnailURL),
            choice: ChoiceDescriptor(id: id, provider: provider, identifier: entry.id, name: entry.name,
                localizedDescription: "Live shader · rests while you work", thumbnail: .image(url: entry.thumbnailURL),
                isDownloaded: true, options: []), contentBadge: .dynamic, showInTopLevel: true,
            sortOrder: entry.id == ShaderLibrary.defaultShader ? -1 : 0, disposability: .none, contextMenu: nil)
    }
    let group = SettingsGroup(id: GroupID(id: "meditations"), items: items,
        localizedName: "Shader Paper", disposability: .none, sortOrder: -100,
        sortID: GroupSortID(id: "com.apple.wallpaper.aerials"), allChoiceID: nil,
        shouldHideItemLabels: false, contextMenu: nil, thumbnail: nil)
    let view = SettingsViewModel(groups: [group], refreshPolicy: .default, isModificationDisabled: false)
    let shim = ShimViewModelsXPC(value: SettingsViewModels(desktop: view, screenSaver: view))
    do {
        let data = try NSKeyedArchiver.archivedData(withRootObject: shim, requiringSecureCoding: false)
        guard let real = objc_getClass("WallpaperSettingsViewModelsXPC") as? AnyClass else { return nil }
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        decoder.requiresSecureCoding = false
        decoder.decodingFailurePolicy = .setErrorAndReturn
        decoder.setClass(real, forClassName: "ShimViewModelsXPC")
        let object = decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        decoder.finishDecoding()
        if let error = decoder.error { extensionLog("Settings decode: \(error)") }
        return object as AnyObject?
    } catch { extensionLog("Settings: \(error)"); return nil }
}
