# From Visual Meditation to Shader Paper

The product name and repository changed; its installed identity remains compatible:

| Item | Retained value |
| --- | --- |
| App bundle identifier | `com.avisualmeditation.wallpaper` |
| Provider identifier | `com.avisualmeditation.wallpaper.shader-extension` |
| Extension bundle | `MeditationExtension.appex` |
| Wallpaper backups | `~/Library/Application Support/Visual Meditation/` |
| Saved clocks | Existing extension container preferences |

Existing wallpaper selections and progress refer to these identifiers, rather than the repository path. Keep them stable when rebuilding.

For an existing installation, close the gallery, build Shader Paper, preserve a copy of the old app, and unregister the old embedded extension before replacing it with the new app. Register the new embedded extension with `Shader Paper.app/Contents/MacOS/VisualMeditation --register`. Avoid leaving both apps registered under the same provider identifier. Registration alone does not select a wallpaper.

The original a-visual-meditation checkout is retained as the model experiment. This repository includes its own curated shaders, renderer, notices, and tests. It does not require the original checkout or any temporary study directory to build.
