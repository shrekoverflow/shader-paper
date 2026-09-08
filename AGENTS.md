# Package Manager Safety

- Run every package-manager command through Socket Firewall: `sfw <command>`.
- This includes installs, updates, removals, scripts, and package executors.
- The current build uses the system Swift compiler directly and needs no packages.

# Project boundaries

- Shader Paper is the standalone native wallpaper app. It must build without a checkout of a-visual-meditation or any local study worktree.
- Resources/Shaders.txt declares the curated collection. Keep shader resources self-contained.
- Preserve existing bundle/provider identifiers and wallpaper backup locations unless implementing an explicit migration.
- Do not inspect other models' shader source as part of authoring artwork. Copying and compiling the approved collection is allowed.
- Keep generated binaries, full-resolution stills, movies, and local validation reports under build/.
- Validate with bash scripts/build.sh and bash scripts/test.sh on a Mac with Metal access. Building and testing must not change the installed wallpaper.
