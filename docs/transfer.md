# Transfer Shader Paper to another Mac

This package requires **Apple Silicon and macOS 26 or later**, with a Metal device. It contains the complete app and its wallpaper collection; no other repository or downloaded assets are needed.

This is a personal build with local ad-hoc signing. It is **not Developer ID signed or notarized**, and uses private macOS wallpaper interfaces. Gatekeeper or your employer's management policy may prevent it from opening or registering its wallpaper extension. Check with your Mac administrator if that happens; this package does not bypass those protections. Compatibility may change with macOS updates.

If macOS offers **Open Anyway** in **System Settings → Privacy & Security**, use that per-app option only if you trust this build and your administrator permits it. See [Apple's guidance](https://support.apple.com/en-us/102445). Do not disable system security protections.

## On your work Mac

1. Transfer the `.zip` and adjacent `.zip.sha256` file together. In Terminal, from their folder, check the download with `shasum -a 256 -c ./*.zip.sha256`. It should report `OK`.
2. Unzip the archive with Finder. Quit any existing Shader Paper gallery. Copy **Shader Paper.app** into your **Applications** folder inside your home folder (`~/Applications`), creating the folder if needed.
3. Keep a single installed copy. If Shader Paper or Visual Meditation was previously installed, follow the [migration notes](migration.md) before replacing or registering the app. Both names share the same wallpaper provider identity; duplicate registered copies can conflict.
4. Open the installed app, choose **Portal** for the magnesium WorkOS wallpaper, then click **Use as Wallpaper**. You can close the gallery afterward. The collection also appears in **System Settings → Wallpaper**.

Selecting a wallpaper applies it across Spaces and displays and links it with the screen saver. **Restore Previous Wallpaper** in the app restores the selection saved before activation. Merely unpacking the archive does not change your wallpaper.

## Build from source if needed

A local build requires Xcode or Command Line Tools with the macOS 26 SDK. Your Mac's management policies still apply. If you received `Shader-Paper-source.bundle` alongside the app, create a source checkout from its folder:

```sh
git clone --branch codex/workos-magnesium-motion Shader-Paper-source.bundle shader-paper
cd shader-paper
```

From this or another complete Shader Paper source checkout, run:

```sh
bash scripts/build.sh
bash scripts/test.sh
```

Then copy `build/native/Shader Paper.app` to `~/Applications` and follow the installation steps above. Building and testing do not install or select a wallpaper, and need no package dependencies.

To prepare another transfer archive from source:

```sh
bash scripts/package.sh
```

The versioned archive and SHA-256 checksum are written to `build/distribution/`. After a successful build, `bash scripts/package.sh --skip-build` packages the existing app after checking its bundle contents, architecture and signatures. The filename records the source checkout's current revision and marks uncommitted changes with `dirty`; when skipping the build, make sure that app was built from the intended source revision.
