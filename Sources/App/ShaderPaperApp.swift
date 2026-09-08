import SwiftUI

@main struct ShaderPaperApp: App {
    init() {
        let args = CommandLine.arguments
        if args.contains("--activate") || args.contains("--restore") || args.contains("--register") {
            do {
                if let index = args.firstIndex(of: "--activate"), args.count > index + 1 {
                    try WallpaperSelection.activate(args[index + 1]); print("Selected \(args[index + 1]) for wallpaper and screen saver.")
                } else if args.contains("--restore") { try WallpaperSelection.restore(); print("Previous wallpaper restored.") }
                else { try WallpaperSelection.register(); print("Native shader extension registered.") }
                exit(0)
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        WindowGroup("Shader Paper") { GalleryView() }
            .defaultSize(width: 920, height: 740)
            .windowResizability(.contentMinSize)
    }
}

struct GalleryView: View {
    @State private var chosen = ShaderLibrary.defaultShader
    @State private var active = WallpaperSelection.current()
    @State private var message: String?
    @State private var error: String?
    private let entries = ShaderLibrary.entries

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A little space to think.").font(.system(size: 30, weight: .medium, design: .serif))
                    Text("Moves while you’re away. Holds its place while you work.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entries.count) WALLPAPERS").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary).padding(.top, 10)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], spacing: 18) {
                    ForEach(entries) { entry in
                        Button { chosen = entry.id; message = nil } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                if let thumbnail = NSImage(contentsOf: entry.thumbnailURL) {
                                    Image(nsImage: thumbnail).resizable().aspectRatio(1.6, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                }
                                HStack {
                                    Text(entry.name).font(.system(size: 12, weight: chosen == entry.id ? .semibold : .regular))
                                    Spacer()
                                    if active == entry.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                                }.padding(.horizontal, 2)
                            }
                            .padding(7)
                            .background(chosen == entry.id ? Color.accentColor.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(chosen == entry.id ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: chosen == entry.id ? 2 : 1))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Choose \(entry.name)")
                    }
                }.padding(2)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chosen).font(.headline)
                    Text(message ?? "Wallpaper and screen saver · all displays and Spaces")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use as Wallpaper") {
                    do { try WallpaperSelection.activate(chosen); active = chosen; message = "Ready. You can close this window." }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            HStack {
                Button("Wallpaper Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!) }
                Spacer()
                Button("Restore Previous Wallpaper") {
                    do { try WallpaperSelection.restore(); active = WallpaperSelection.current(); message = "Previous wallpaper restored." }
                    catch { self.error = error.localizedDescription }
                }.disabled(!FileManager.default.fileExists(atPath: WallpaperSelection.support.appendingPathComponent("Previous.plist").path))
            }.font(.caption).buttonStyle(.link)
        }
        .padding(26).frame(minWidth: 720, minHeight: 540)
        .onAppear { if let active { chosen = active } }
        .alert("Couldn’t change the wallpaper", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

func failure(_ description: String) -> NSError {
    NSError(domain: "VisualMeditation", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
}
