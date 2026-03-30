# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**autopyq** is a Windows-only WeChat Moments (朋友圈) automation toolkit. It uses AutoHotkey v2.0 compiled executables for UI automation and a Python image-processing utility for template refinement. The automation works by matching template images (pyq1–pyq4) against the WeChat UI to locate and click buttons.

## Architecture

- **AutoHotkey runners** (`assets/*.exe`, compiled from `assets/*.ahk`): Three runners handle text posts, image/mixed posts, and template capture. They use ImageSearch with template PNGs to find UI elements in WeChat windows.
- **Image tool** (`scripts/imgtool.py`, compiled to `assets/imgtool.exe`): Python CLI with subcommands (`info`, `crop`, `find-component`, `find-text-bbox`) for connected-component analysis and text bounding-box detection. Used during template capture to refine template bounds.
- **Configuration** (`assets/config.ini`): Central INI file with window selectors, timing parameters, template filenames, and click-mode settings per UI element.
- **Templates** (`assets/pyq1_bg.png` – `pyq4_bg.png`): Four template images matched against WeChat UI. Each has a `_template.png` reference copy. These need refreshing when WeChat's UI changes — see `references/template-capture-guide.md`.

## Running the Executables

All runners require absolute Windows paths. In bash, use `cygpath -w` to convert paths.

```bash
# Text post
"$text_runner_win" --config "$config_win" --text-file "$(cygpath -w "$text_file")" --log-file "$(cygpath -w "$log_file")"

# Image/mixed post (omit --text-file for image-only)
"$image_runner_win" --config "$config_win" --image-list-file "$(cygpath -w "$image_list")" --text-file "$(cygpath -w "$text_file")" --log-file "$(cygpath -w "$log_file")"

# Template capture
"$capture_runner_win" --config "$config_win" --target moments_button --log-file "$(cygpath -w "$log_file")"
```

## Running the Image Tool

```bash
# From source (requires Pillow)
python scripts/imgtool.py info image.png
python scripts/imgtool.py crop image.png --region x,y,w,h -o out.png
python scripts/imgtool.py find-component image.png --polarity dark --selector largest --region x,y,w,h
python scripts/imgtool.py find-text-bbox image.png --region x,y,w,h

# Or use the compiled exe
assets/imgtool.exe info image.png
```

## Key Exit Codes

0=success, 10=bad config, 11=missing text, 12=WeChat not found, 13–17=UI element not found (moments button/camera/editor/publish), 18=image load fail, 19=runtime error, 20–24=image-specific errors (bad list, count >9, file dialog issues).

## Important Conventions

- Staging directory for each publish run: `C:\Users\<username>\Pictures\Moments\<YYYY-MM-dd_HHmmss>\`
- `text.txt` and `image_list.txt` must be UTF-8 encoded
- `image_list.txt` has one absolute Windows path per line, max 9 images
- After publish, `after_publish.png` screenshot may appear in the staging directory
- Template capture targets: `moments_button`, `camera_button`, `editor_anchor`, `publish_button`, `restore_windows`
- The `search_variation` config parameter (default 20) controls ImageSearch tolerance
