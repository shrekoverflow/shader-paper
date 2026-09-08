import Foundation

@main struct SelectionTests {
    static func main() throws {
        let photo: [String: Any] = ["Type": "individual", "Desktop": ["Content": ["Choices": [["Provider": "example.photo"]]]]]
        let original: [String: Any] = ["SystemDefault": photo, "AllSpacesAndDisplays": photo, "Displays": ["one": photo], "Spaces": ["work": photo], "Version": 1]
        let active = try WallpaperSelection.linked(original, shader: "GPT6-Astra-II")
        precondition(WallpaperSelection.selected(in: active) == "GPT6-Astra-II")
        precondition(active["Version"] as? Int == 1)
        let serialized = try PropertyListSerialization.data(fromPropertyList: active, format: .binary, options: 0)
        let decoded = try PropertyListSerialization.propertyList(from: serialized, format: nil)
        precondition(WallpaperSelection.selected(in: decoded) == "GPT6-Astra-II")
        var edited = active
        let independent: [String: Any] = ["Type": "individual", "Desktop": ["Content": ["Choices": [["Provider": "another.photo"]]]]]
        edited["Displays"] = ["new-display": independent]
        let restored = WallpaperSelection.restoring(edited, previous: original) as! [String: Any]
        precondition(!WallpaperSelection.containsOurs(restored))
        precondition(NSDictionary(dictionary: restored["AllSpacesAndDisplays"] as! [String: Any]).isEqual(to: photo))
        let displays = restored["Displays"] as! [String: Any]
        precondition(NSDictionary(dictionary: displays["one"] as! [String: Any]).isEqual(to: photo))
        precondition(NSDictionary(dictionary: displays["new-display"] as! [String: Any]).isEqual(to: independent))
        print("PASS: shader selection roundtrip and restore preserve independent later display choices")
    }
}
func failure(_ description: String) -> NSError { NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: description]) }
