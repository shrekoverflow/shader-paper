# Recorded aerial experiment

This optional toolchain renders Astra II as a six-minute 3840 × 2160 HEVC Main10 aerial movie at 30 fps. It repeats a two-minute reversible traversal of shader time three times, and adds temporal HEVC metadata used by Apple's transition to a still desktop. It is separate from Shader Paper's live native renderer.

```sh
bash tools/aerial/build.sh
python3 tools/aerial/catalog.py install \
  "build/aerial/Almost a Shape — Native.mov" "build/aerial/Poster.png"
python3 tools/aerial/catalog.py activate
```

Install and activation write the private per-user aerial catalog and wallpaper selection. Backups are retained under `~/Library/Application Support/Almost a Shape/Aerial/`. Existing assets are preserved. Use `install --replace` to replace an earlier export; `python3 tools/aerial/catalog.py restore` removes this entry and restores the previous selection when this aerial is still selected.

The intermediate `Almost a Shape.mov` is not suitable for installation: plain HEVC can turn black when macOS slows playback on unlock. The final native movie is checked for temporal metadata and seeking behavior by `ValidateAerial.swift`. The encoder's original MIT license is included here.

This experimental path requires a Metal-capable Mac, the system Swift compiler, and Python 3.11+. Private catalog behavior can change with macOS. The live wallpaper app is the primary product; recorded aerials remain available for reproducing the earlier work.

Run catalog fixture tests with `python3 -m unittest discover -s tools/aerial -p 'test_*.py'`.
