# Ink, Light, and Weather

Three original studies completed and visually reviewed on September 8, 2026. Each is an analytic artwork reconstructed from position and saved shader time, with no simulation buffers or external assets.

| Study | Direction | Review and validation |
| --- | --- | --- |
| Ink | Asymmetric graphite capillaries on warm paper. The initial wet front extends, then pigment shifts within a bounded area. | Four aspect ratios, seven sampled times through 30 days, finite opaque output, identical repeated frames, and a simulated 24-hour pause/resume. Full-resolution review corrected a regular edge texture. |
| Light | An open caustic on matte plaster, with a fine spectral seam and a broad soft fold. | Four aspect ratios and six sampled times through 24 hours, finite opaque output, identical repeated frames, and a simulated 12-hour pause/resume. Portrait placement and the contour's focus were refined from actual renders. |
| Weather | Layered hills, a warm horizon, and slow valley mist. | Four aspect ratios, early/late samples through one million seconds, repeated-frame consistency, and clock pause/resume. Ridge spacing and valley framing were refined from actual renders. |

The delivered stills are 4K for Ink and Light and 5K for Weather. Each study includes a silent 30-second 1080p preview. Generated media and original measured reports are kept locally under `build/overnight-2026-09-08`; compact app-generated previews are committed under `docs/previews`.

Complete native frame rendering on the development M4 Max averaged approximately 4.9 ms for Ink, 1.1 ms for Light, and 3.8 ms for Weather at 2560 × 1440. These measurements include synchronous rendering work and exclude the display compositor. They are observations on one Mac, not performance guarantees.

The studies use the app's unchanged entry points and time parameter. Individual study validation did not exercise actual OS lock/unlock events. The integration test separately checks the live renderer's stop, retained frame, and resume behavior. Long-running time inherits the host Float's precision limits; late-time sampling is not an exhaustive continuity proof.

Source fingerprints of the reviewed artwork:

```text
Ink      58ad05d4471cc47534a64aee72f35ac3efed865e84b8dca59f8db09ca45d01be
Light    06ae7bd257dd9a0ef9c2a01ed7ee95001acfb28a75718265c34712128cb5959a
Weather  eb349882713dc1d71a707b78a74393bd36f2638e2415dc4e7cac92054f667e68
```
