# Imgtool Guide

Use this guide when the template-capture workflow needs programmatic cropping help.

`imgtool` is a small CLI helper for:

- image dimensions
- rectangular image crops
- dark or light connected-component bounding boxes in a narrowed region
- text glyph bounding boxes in a narrowed region

Prefer:

- `./assets/imgtool.exe`

Fallback:

- `python ./scripts/imgtool.py`

## General Rules

- First narrow the working region visually. Do not use `imgtool` as a full-window search tool.
- Treat `imgtool` as a boundary-finding helper, not as a replacement for visual confirmation.
- All bounding boxes returned by `imgtool` are in the coordinate system of the original input image, even when `--region` is used.
- All commands print JSON to stdout.

## Commands

### `info`

Use `info` when only the input image dimensions are needed.

Example:

```powershell
./assets/imgtool.exe info `
  --in ./.tmp_template_capture/<run-id>/capture_moments_button.png
```

JSON output shape:

```json
{"ok": true, "w": 1280, "h": 960}
```

### `crop`

Use `crop` when the bounding box is already known and only image extraction is needed.

Example:

```powershell
./assets/imgtool.exe crop `
  --in ./.tmp_template_capture/<run-id>/capture_camera_button.png `
  --out ./.tmp_template_capture/<run-id>/toolbar_crop.png `
  --x 20 --y 20 --w 260 --h 180
```

JSON output shape:

```json
{"ok": true, "out": "path", "x": 20, "y": 20, "w": 260, "h": 180}
```

### `find-component`

Use `find-component` when the target is mainly a dark or light connected shape inside an already narrowed region.

Supported polarities:

- `dark`
- `light`

Supported selectors:

- `largest`
- `topmost`
- `bottommost`
- `leftmost`
- `rightmost`

Example for `pyq1`:

```powershell
./assets/imgtool.exe find-component `
  --in ./.tmp_template_capture/<run-id>/pyq1_candidate.png `
  --region 0,0,100,160 `
  --polarity dark `
  --min-area 20 `
  --select largest
```

Example for `pyq2`:

```powershell
./assets/imgtool.exe find-component `
  --in ./.tmp_template_capture/<run-id>/toolbar_crop.png `
  --region 90,20,70,60 `
  --polarity light `
  --min-area 20 `
  --select largest
```

Example for `pyq4`:

```powershell
./assets/imgtool.exe find-component `
  --in ./.tmp_template_capture/<run-id>/button_area.png `
  --region 300,80,280,80 `
  --polarity dark `
  --min-area 50 `
  --select largest
```

JSON output shape:

```json
{"ok": true, "x": 32, "y": 76, "w": 40, "h": 40, "area": 824, "region": {"x": 0, "y": 0, "w": 100, "h": 160}, "components": 2}
```

Guidance:

- Use `dark` for targets like `pyq1`.
- Use `light` for targets like `pyq2`.
- Increase `--min-area` if tiny noise blobs are being selected.
- Narrow `--region` first if multiple unrelated components are still present.

### `find-text-bbox`

Use `find-text-bbox` when the target is text and the working region has already been visually narrowed around that text.

Required inputs:

- the input image
- a narrowed `--region`
- the corresponding `*_bg_reference.png` as the color-pattern reference

Example for `pyq3`:

```powershell
./assets/imgtool.exe find-text-bbox `
  --in ./.tmp_template_capture/<run-id>/pyq3_region.png `
  --region 0,0,300,90 `
  --template ./assets/pyq3_bg_reference.png `
  --padding 0
```

JSON output shape:

```json
{"ok": true, "x": 48, "y": 53, "w": 187, "h": 28, "region": {"x": 0, "y": 0, "w": 300, "h": 90}, "components": 14}
```

Guidance:

- Keep `--padding 0` unless a tiny safety pixel is needed.
- Visually confirm that no glyph is clipped.
- Preserve antialiased fringe pixels.
- Do not keep padding around the text unless it is necessary to avoid clipping.

## Python Fallback

If `./assets/imgtool.exe` is unavailable, use the same commands through Python:

```powershell
python ./scripts/imgtool.py info --in ...
python ./scripts/imgtool.py find-component --in ... --region ... --polarity dark --min-area 20 --select largest
python ./scripts/imgtool.py find-text-bbox --in ... --region ... --template ./assets/pyq3_bg_reference.png --padding 0
```
