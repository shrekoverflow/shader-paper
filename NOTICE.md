# Origins and third-party notices

Shader Paper was extracted from the native wallpaper work developed in [a-visual-meditation](https://github.com/kanalo-shrek/a-visual-meditation) on September 8, 2026.

The original Fable 5 shader was introduced in source commit `11db539`. Its path-filtered history is retained in this repository as commit `60979e3e2e1269eaa406955f3982bc13cf84c33d`, preserving its author, date, and message. Filtering changes the commit hash and retains only that shader; the inherited message also names another artwork that was not imported. The following migration commit relocates Fable 5 without changing its contents.

The native app, both Astra shaders, and the three new studies were uncommitted work at extraction time, so their history starts with this repository's migration commit. The original checkout and model collection remain available separately. This repository has no build dependency on that checkout.

Parts of the wallpaper extension's XPC bridge are adapted from [kageroumado/phosphene](https://github.com/kageroumado/phosphene). The original MIT notice is retained in [LICENSE.phosphene](LICENSE.phosphene) and bundled with the app and extension.

The recorded-aerial temporal encoder is adapted from [AlexisBCD/macos-custom-video-wallpaper-fix](https://github.com/AlexisBCD/macos-custom-video-wallpaper-fix). Its original MIT notice is retained in [tools/aerial/LICENSE.temporal-encoder](tools/aerial/LICENSE.temporal-encoder).

These third-party licenses apply to their respective components. No project-wide license has been added during extraction.

Portal and Flight were added in September 2026. Portal renders the WorkOS symbol as a magnesium sculpture, with an outline adapted from the official mark on the [WorkOS website](https://workos.com/), viewed September 8, 2026. Its material, lighting, and rendering are original procedural artwork, developed from a generated material concept. It is not an official WorkOS wallpaper. Flight is original procedural artwork. Both shaders are self-contained and require no external image assets or textures.
