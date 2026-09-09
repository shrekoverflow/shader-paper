# Native wallpaper architecture

The gallery embeds a WallpaperExtensionKit provider. The extension owns a separate display surface and Metal kernel per wallpaper surface. It presents IOSurface-backed pixel buffers through an AVSampleBufferDisplayLayer and retains the last frame after its rendering timer stops.

The shared clock integrates a smooth velocity change when macOS switches between animated and still states. Clock time remains exactly constant while stopped. Progress is checkpointed during animation and on settling. Static picker previews use isolated clocks.

The renderer first evaluates the shader into an `rgba16Float` texture, then converts the result to an SDR display surface. Artwork needs a fullscreen triangle, `vertex_main`, `fragment_main`, and a Float animation time at fragment buffer 0. Time-aware artwork may read a Float local hour in [0, 24) at fragment buffer 1. Pipeline reflection detects use of that optional input; existing artwork ignores it. No external shader files or renderer services are loaded at runtime.

Flight and Portal lighting use local civil time from the Mac's current calendar and time zone, independently of saved motion time. While motion is paused, one environmental redraw about every minute updates the lighting without advancing geometry, camera motion, or animated accent sweeps. Animated frames already update the lighting, so the minute callback skips them. Only valid, active, non-preview surfaces schedule these updates; sleep, inactivity, invalidation, replacement, and render errors cancel them. Clock and time-zone notifications refresh eligible held surfaces, and waking re-enables updates with an immediate redraw. Reduce Motion keeps geometry paused while allowing environmental lighting to follow the clock. Other shaders retain their exact settled display buffer and have no daylight timer.

Build thumbnails and exports use a fixed noon hour by default. The exporter accepts `--hour` to reproduce dawn, dusk, or night independently of animation time, including repeated frames and movie comparisons. The daily palette is artist-directed rather than tied to geographic sunrise or seasonal day length. Portal blends its neutral room lighting from night to day over 06:30–09:00 and from day to night over 17:00–20:30. Its original colored grazing lights keep their source colors and intensities across the day; their movement uses saved animation time. Additional silver and blue edge lights accompany the daytime window, with less ambient fill and a stronger cast shadow.

Selection registers the embedded extension and updates the user's private wallpaper store atomically. It preserves a previous-selection snapshot and timestamped backups. Restore keeps subsequent independent user choices. Build and test scripts do not activate the wallpaper.

The private XPC bridge is derived from Phosphene; see the root license notice. The extension uses Xcode's `_NSExtensionMain` entry point so its XPC run loop remains alive after registration. Its app and provider identifiers intentionally retain their Visual Meditation values to preserve existing selections and saved clocks.

The implementation targets Apple Silicon and macOS 26+. Validation uses the installed runtime Metal compiler.
