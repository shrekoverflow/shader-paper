# Shader export

Build with `bash tools/export/build.sh` from the repository root. This tool compiles directly with the app's shared renderer and clock; it needs no external checkout or packages. Running it requires Metal access.

`build/export/render-shader` accepts four commands:

| Command | Output |
| --- | --- |
| `still` | An sRGB PNG at the requested shader time |
| `movie` | A silent H.264 MP4 at fixed time increments |
| `validate` | Shader output, repeated-frame, timing, and clock checks |
| `moviecheck` | Full movie decode, timestamp/track checks, and sampled color comparisons |

All commands require `--shader FILE --out FILE`. The default dimensions are 1920 × 1080, time is 0 seconds, and movies default to 30 seconds at 30 fps. Use `--width`, `--height`, `--time`, `--duration`, and `--fps` to change them. Movie dimensions must be even. Output paths should be new files under `build/`.

```sh
build/export/render-shader movie --shader Resources/shaders/Weather.shader \
  --out build/Weather.mp4 --time 600 --duration 30 --fps 30
build/export/render-shader moviecheck --shader Resources/shaders/Weather.shader \
  --input build/Weather.mp4 --out build/Weather-check.json \
  --time 600 --duration 30 --fps 30
```

Use the same shader revision, start time, duration, and frame rate for export and verification. `moviecheck` decodes every sample and compares the first, middle, and last frames with native renders after color conversion; it writes those sample images alongside the report. Codec losses are measured rather than treated as exact pixel matches.

`validate` samples six times through one day in four aspect ratios, reads half-float output, checks finite color and opaque alpha, compares repeated/consecutive frames, measures native rendering cost, and exercises the clock through a long pause and resume. Reports identify the source hash. These are sampled checks, not exhaustive visual or OS lifecycle tests.

This exporter was generalized from the Light study's validated rendering tool. It operates independently of the installed wallpaper and does not change the desktop.
