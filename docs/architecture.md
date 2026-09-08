# Native wallpaper architecture

The gallery embeds a WallpaperExtensionKit provider. The extension owns a separate display surface and Metal kernel per wallpaper surface. It presents IOSurface-backed pixel buffers through an AVSampleBufferDisplayLayer and retains the last frame after its rendering timer stops.

The shared clock integrates a smooth velocity change when macOS switches between animated and still states. Clock time remains exactly constant while stopped. Progress is checkpointed during animation and on settling. Static picker previews use isolated clocks.

The renderer first evaluates the shader into an `rgba16Float` texture, then converts the result to an SDR display surface. Artwork only needs a fullscreen triangle, `vertex_main`, `fragment_main`, and a Float time at fragment buffer 0. No external shader files or renderer services are loaded at runtime.

Selection registers the embedded extension and updates the user's private wallpaper store atomically. It preserves a previous-selection snapshot and timestamped backups. Restore keeps subsequent independent user choices. Build and test scripts do not activate the wallpaper.

The private XPC bridge is derived from Phosphene; see the root license notice. The extension uses Xcode's `_NSExtensionMain` entry point so its XPC run loop remains alive after registration. Its app and provider identifiers intentionally retain their Visual Meditation values to preserve existing selections and saved clocks.

The implementation targets Apple Silicon and macOS 26+. Validation uses the installed runtime Metal compiler.
