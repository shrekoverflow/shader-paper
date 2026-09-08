# Transfer Shader Paper to another Mac

This package requires **Apple Silicon and macOS 26 or later**, with a Metal device. It contains the complete app and its wallpaper collection; no other repository or downloaded assets are needed.

Check the archive's **SIGNING.txt** for its actual signing identity, Apple Developer team, and stapled notarization ticket result. Builds default to local ad-hoc signing; a Developer ID build identifies its developer, but **Developer ID signing alone is not notarization**. A verified stapled ticket confirms that the enclosed app has Apple's notarization ticket. A failed ticket check does not establish whether the app was ever notarized.

The app uses private macOS wallpaper interfaces. Gatekeeper or your employer's management policy may prevent it from opening or registering its wallpaper extension, including when the app is signed or notarized. Check with your Mac administrator if that happens; this package does not bypass those protections. Compatibility may change with macOS updates.

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

## Developer ID signing and notarization

With a **Developer ID Application** certificate and its private key available in your Mac's keychain, build and package with your certificate's exact identity:

```sh
CODE_SIGN_IDENTITY='Developer ID Application: YOUR NAME (YOUR TEAM ID)' bash scripts/package.sh
```

This signs the extension and app with hardened runtime and secure timestamps. It does not submit anything to Apple or install the app. Without `CODE_SIGN_IDENTITY`, builds continue to use local ad-hoc signing. With `--skip-build`, packaging preserves the existing app's signature regardless of that variable.

Notarization is a separate step requiring an authenticated `notarytool` keychain profile. Use your own existing profile name; keep credentials in your keychain, never in this repository or command examples. Submit the exact ZIP printed by the packaging command, replacing the placeholders below:

```sh
xcrun notarytool submit 'build/distribution/YOUR-PACKAGE.zip' \
  --keychain-profile 'YOUR_NOTARY_PROFILE' --wait
```

After Apple reports **Accepted**, staple the ticket to the same app and repackage it:

```sh
xcrun stapler staple 'build/native/Shader Paper.app'
xcrun stapler validate 'build/native/Shader Paper.app'
bash scripts/package.sh --skip-build
```

Transfer the regenerated ZIP and checksum. Do not rebuild or re-sign between acceptance and stapling, because that changes the app Apple reviewed. Packaging checks the copied app's ticket and records the result in `SIGNING.txt`; it never assumes notarization from the certificate. See Apple's [Developer ID overview](https://developer.apple.com/developer-id/) and [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
