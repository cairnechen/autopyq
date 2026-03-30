# Template Capture Guide

Use this guide when the user wants to refresh the template images used by the WeChat Moments runners, or when `moments_button`, `camera_button`, `editor_anchor`, or `publish_button` matching becomes unreliable.

For detailed `imgtool` usage, also read `./references/imgtool-guide.md`.

## Assets

- Capture runner: `./assets/wechat_moments_capture_reference.exe`
- Programmatic crop tool: `./assets/imgtool.exe` (fallback: `python ./scripts/imgtool.py`)
- Config: `./assets/config.ini`
- Default template references: `./assets/pyq1_bg_template.png`, `./assets/pyq2_bg_template.png`, `./assets/pyq3_bg_template.png`, `./assets/pyq4_bg_template.png`
- Runtime templates to refresh: `./assets/pyq1_bg.png`, `./assets/pyq2_bg.png`, `./assets/pyq3_bg.png`, `./assets/pyq4_bg.png`
- Preserve `./assets/pyq1_full.png` as the clean full-button source for `pyq1` after a successful capture.

## Capture Order

Always bootstrap in this order:

1. `pyq1`
2. `pyq2`
3. `pyq3`
4. `pyq4`

Later captures depend on earlier runtime templates already being valid.

## Capture Runner

Run the capture runner with one of these targets:

- `moments_button`
- `camera_button`
- `editor_anchor`
- `publish_button`
- `restore_windows`

Required arguments:

- `--config <path>`
- `--target <target>`
- `--log-file <path>`

Optional argument:

- `--seed-text <text>` for `publish_button`; default is `test`
- `--window-state-file <path>` for persisting and restoring the original window sizes across calls

Argument rules:

- `--output-dir <path>` is required for `moments_button`, `camera_button`, `editor_anchor`, and `publish_button`.
- `--output-dir` is not used for `restore_windows`.
- `restore_windows` requires `--window-state-file <path>`.
- For the standard template-refresh flow, pass the same `--window-state-file` to `moments_button` and `camera_button`.

The runner saves full-window screenshots with fixed names under `--output-dir`:

- `capture_moments_button.png`
- `capture_camera_button.png`
- `capture_editor_anchor.png`
- `capture_publish_button.png`

## Temporary Working Directory

- Use one temporary directory for the entire template-refresh run: `./.tmp_template_capture/<run-id>/`.
- Create a shared window-state file for the run, for example `./.tmp_template_capture/<run-id>/window_state.ini`.
- Save all intermediate files from the run into that directory, including full-window screenshots, narrowed crops, candidate crops, previews, and per-step logs.
- Only keep the final template outputs in `./assets/`.
- If the entire template-refresh flow succeeds, delete `./.tmp_template_capture/<run-id>/` at the end.
- If any step fails, keep `./.tmp_template_capture/<run-id>/` for debugging and review.

## Workflow

- At the start of the run, choose one `window_state.ini` path under the run directory.
- Use that same `window_state.ini` for the `moments_button` and `camera_button` runner calls.
- The first call records and shrinks the WeChat main window. The second call records and shrinks the Moments window.

### 1. Capture `pyq1`

- Run the capture runner with `--target moments_button` and `--window-state-file <run-window-state.ini>`.
- Inspect `capture_moments_button.png`.
- Extract the left navigation rail from the WeChat window screenshot. Its width must be at least 15% of the image width.
- Use `./assets/pyq1_bg_template.png` only as a reference for what the correct sidebar icon should look like.
- Locate the 朋友圈 icon candidate inside that navigation-rail crop, confirm it, and temporarily save that candidate crop (cropped from the navigation-rail image) for the remaining `pyq1` steps.
- Check visually whether that candidate has a red badge on the icon itself, especially near the actual icon's top-right area.
- If a badge is present, stop and ask the user to clear the badge, then repeat this step.
- If no badge is present, run `imgtool find-component --polarity dark` on the candidate crop to get the icon bounding box.
- Compute the bounding box center from the returned `x, y, w, h`.
- Crop from the candidate crop using the bounding box center as the crop center. Keep no padding, but expand the crop as needed to avoid clipping any visible icon edge or curve.
- Save the result as a temporary file, not directly as `pyq1_full.png`.
- Run `imgtool find-component --polarity dark` on the temporary file as a heuristic check. If the result suggests that the icon is materially off-center, adjust and re-crop, but treat visual centering as the authoritative check.
- Only after verification passes, save as `./assets/pyq1_full.png`.
- Before cropping the final runtime template, use visual inspection to verify that `./assets/pyq1_full.png` is correct by reading it together with `./assets/pyq1_bg_template.png` as a visual reference.
- Crop the final runtime template `./assets/pyq1_bg.png` from `./assets/pyq1_full.png` by taking the bottom-left quarter of `./assets/pyq1_full.png`. Do not use the full icon as the runtime template.

### 2. Capture `pyq2`

- Run the capture runner with `--target camera_button` and the same `--window-state-file <run-window-state.ini>`.
- Inspect `capture_camera_button.png`.
- Focus on the top-left toolbar area of the Moments window.
- Extract the camera button and save as a temporary candidate crop.
- Use `./assets/pyq2_bg_template.png` only as a visual reference while refining the crop.
- Run `imgtool find-component --polarity light` on the candidate crop to get the icon bounding box. Compute the bounding box center from the returned `x, y, w, h`.
- Crop from the candidate crop using the bounding box center as the crop center. Keep no padding, but expand the crop as needed to avoid clipping any visible icon edge or curve.
- Save the result as a temporary file, not directly as `pyq2_bg.png`.
- Run `imgtool find-component --polarity light` on the temporary file as a heuristic check. If the result suggests that the icon is materially off-center, adjust and re-crop, but treat visual centering as the authoritative check.
- Only after verification passes, save as `./assets/pyq2_bg.png`.
- Use visual inspection to verify that `pyq2_bg.png` is correct. The icon content in `pyq2_bg.png` should be visually centered without padding, and the icon must remain fully intact with no part cropped off.


### 3. Capture `pyq3`

- Run the capture runner with `--target editor_anchor`.
- Inspect `capture_editor_anchor.png`.
- First use `imgtool find-component --polarity light --select largest` on `capture_editor_anchor.png` to locate the white editor dialog, then use that dialog image as the working image for the remaining `pyq3` steps.
- For `pyq3`, a full-image largest light-component pass on `capture_editor_anchor.png` is acceptable because the white editor dialog is expected to be the dominant light component in that screenshot.
- Use visual inspection to verify that the extracted working image is the white editor dialog before continuing.
- The upper half of that white editor dialog contains the placeholder text. Confirm that visually before narrowing the placeholder text region.
- Use `./assets/pyq3_bg_template.png` only as a visual reference to narrow the placeholder text region. Do not overwrite the template file.
- Use `imgtool find-text-bbox` on the narrowed region inside the white editor dialog to programmatically tighten the crop to the glyph bounds.
- For `pyq3`, first narrow the placeholder region visually, then crop to the text glyph bounding box with zero or near-zero padding; only keep extra pixels when they are required to avoid clipping a glyph edge.
- Save the final runtime template as `./assets/pyq3_bg.png`.
- Use visual inspection to verify that `./assets/pyq3_bg.png` is correct by reading it together with `./assets/pyq3_bg_template.png` as a visual reference, ensure that no glyph is clipped, and there is no padding around the text.

### 4. Capture `pyq4`

- Run the capture runner with `--target publish_button`.
- The runner will focus the editor, paste the seed text, and bring the publish button into the enabled state.
- Inspect `capture_publish_button.png`.
- Focus on the editor dialog's lower action-button area.
- Extract the enabled publish button and save the final runtime template as `./assets/pyq4_bg.png`.
- Use `./assets/pyq4_bg_template.png` only as a visual reference while refining the crop. Do not overwrite the template file.
- Use `imgtool find-component` on the narrowed button area when a programmatic edge-tightening pass is helpful.
- Use visual inspection to verify that `pyq4_bg.png` is correct by reading it together with `./assets/pyq4_bg_template.png` as a visual reference. The button content should be visually centered without padding, and ensure the full button content, including the rounded corners, is not clipped.

### 5. Restore Window Sizes

- After `pyq4` is complete, run the capture runner with `--target restore_windows --window-state-file <run-window-state.ini> --log-file <path>`.
- If any step in the template-refresh flow fails after the window-state file has been created, run the same `restore_windows` command before ending the session.
- `restore_windows` restores only the original window width and height for the WeChat main window and the Moments window. It does not restore position, maximize state, or open/closed state.

## Cropping Rules

- Preferred path: use visual inspection to identify the correct UI region and confirm the target state. Use the corresponding `*_bg_template.png` as a reference for the target's visual structure and color patterns. Within the narrowed region, use `imgtool` to find the target bounds and produce the final runtime crop.
- Prefer `./assets/imgtool.exe`. If it is unavailable, fall back to `python ./scripts/imgtool.py`, or any other image tool available in the current environment.
- Use `imgtool info --in <path>` to get the dimensions of any image.
- Always narrow the area you inspect before refining the crop. Do not judge the target from the full-window screenshot when the expected UI area is already known.

- For `pyq1`, the expected UI area is the left navigation rail of the main WeChat window.
- Iterate as needed: extract, inspect the result, adjust the selection, and extract again.
- The final runtime template should preserve the correct content and state; it does not need to have the same dimensions as the reference template.
- A satisfactory crop must:
  - keep the target fully visible
  - fill the crop as much as practical
  - keep the icon or text content visually centered within the crop as much as practical
  - for icon or button targets (`pyq1`, `pyq2`, `pyq4`), crop as tightly as practical around the visible content; use no padding or only minimal padding, but keep the full icon or button intact
  - do not save a crop if any icon edge, button edge, or text glyph appears clipped
  - avoid badges, hover states, highlights, or unrelated overlays

## Output Rules

- Never overwrite `*_bg_template.png`.
- Overwrite `*_bg.png` only after the new crop is satisfactory.
- Preserve `pyq1_full.png` after a successful `pyq1` refresh.
- `pyq2`, `pyq3`, and `pyq4` do not need `*_full.png` artifacts.
