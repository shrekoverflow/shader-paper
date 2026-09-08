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

`--hour` sets a fixed local hour independently of animation time, defaulting to 12 (noon). Use a finite value from 0 inclusive to 24 exclusive; fractional values are supported, such as `--hour 6.5` for 06:30. Flight uses this input for its daylight mood; shaders without local-hour lighting ignore it. The chosen hour stays fixed throughout an export rather than following the computer's clock.

```sh
build/export/render-shader movie --shader Resources/shaders/Flight.shader \
  --out build/Flight-evening.mp4 --time 600 --hour 18 --duration 30 --fps 30
build/export/render-shader moviecheck --shader Resources/shaders/Flight.shader \
  --input build/Flight-evening.mp4 --out build/Flight-evening-check.json \
  --time 600 --hour 18 --duration 30 --fps 30
```

Use the same shader revision, start time, local hour, duration, and frame rate for export and verification. `moviecheck` decodes every sample and compares the first, middle, and last frames with native renders after color conversion; it writes those sample images alongside the report. Codec losses are measured rather than treated as exact pixel matches.

`validate` samples six animation times through one day in four aspect ratios at the selected local hour, reads half-float output, checks finite color and opaque alpha, compares repeated/consecutive frames, measures native rendering cost, and exercises the clock through a long pause and resume. Four additional color/alpha probes hold animation time at 18 seconds while sampling midnight, 06:00, noon, and 18:00, covering lighting moods independently of motion. Validation and movie-check reports identify the source hash and selected local hour. These are sampled checks, not exhaustive visual or OS lifecycle tests.

This exporter was generalized from the Light study's validated rendering tool. It operates independently of the installed wallpaper and does not change the desktop.
