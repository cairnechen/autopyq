---
name: autopyq
description: Use when the user wants to 发朋友圈、发布微信朋友圈、发一个带图的朋友圈、发图文朋友圈，或让 Agent 用本地图片路径和聊天内容准备并发布 WeChat Moments/朋友圈 through the local Windows runner. Also use when the user needs to refresh or recapture the pyq1-pyq4 template images used by the local Moments runners.
---

# WeChat Moments Publisher

Use this skill when the user wants to publish text, images, or a mixed post to WeChat Moments/朋友圈 with the local packaged runner, or when the user needs to refresh the pyq1-pyq4 template images used by the ImageSearch workflow.

## Safety

- Never publish without an explicit confirmation in the current conversation.
- Tell the user to keep WeChat visible and avoid moving the mouse or keyboard during execution.
- Verify that the default templates all exist. If any template is missing, stop and switch to template capture.
- For text posts, stage the final text into `Pictures\Moments\<run-id>\text.txt` and publish through `--text-file`.
- When the user wants to publish images, only accept explicit file paths. Do not accept directories, wildcards, or raw chat attachments.
- Reject image batches larger than 9 files before launching the runner.

## Assets

- Text runner: `./assets/wechat_moments_publish.exe`
- Image runner: `./assets/wechat_moments_publish_images.exe`
- Reference capture runner: `./assets/wechat_moments_capture_reference.exe`
- Config: `./assets/config.ini`
- Default templates: `./assets/pyq1_bg.png`, `./assets/pyq2_bg.png`, `./assets/pyq3_bg.png`, `./assets/pyq4_bg.png`
- Default template references: `./assets/pyq1_bg_reference.png`, `./assets/pyq2_bg_reference.png`, `./assets/pyq3_bg_reference.png`, `./assets/pyq4_bg_reference.png`

## References

- Read [`./references/template-capture-guide.md`](./references/template-capture-guide.md) when the user wants to refresh or recapture `pyq1` to `pyq4`, or when any `moments_button` / `camera_button` / `editor_anchor` / `publish_button` match becomes unreliable.

## Workflow

1. Resolve the installed skill root and build absolute asset paths.
2. Resolve the post content from the conversation or another user-specified source.

### PowerShell Template

Use this when the host shell is PowerShell.

```powershell
$skillRoot = 'C:\Users\<username>\.agents\skills\autopyq'
$assetsDir = Join-Path $skillRoot 'assets'
$textRunner = Join-Path $assetsDir 'wechat_moments_publish.exe'
$imageRunner = Join-Path $assetsDir 'wechat_moments_publish_images.exe'
$config = Join-Path $assetsDir 'config.ini'
```

- If the host app installs skills elsewhere, substitute the actual installed root, for example `C:\Users\<username>\.claude\skills\autopyq`.
- Text post:

```powershell
$runId = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$stagingDir = Join-Path 'C:\Users\<username>\Pictures\Moments' $runId
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
$textFile = Join-Path $stagingDir 'text.txt'
$logFile = Join-Path $stagingDir 'log.txt'
```

- Prepare `text.txt` as UTF-8 in `C:\Users\<username>\Pictures\Moments\<run-id>`.
- Launch the runner:

```powershell
& $textRunner --config $config --text-file $textFile --log-file $logFile
```

- Image or mixed post:

```powershell
$runId = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$stagingDir = Join-Path 'C:\Users\<username>\Pictures\Moments' $runId
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
$imageList = Join-Path $stagingDir 'image_list.txt'
$textFile = Join-Path $stagingDir 'text.txt'
$logFile = Join-Path $stagingDir 'log.txt'
```

- Copy input images into `C:\Users\<username>\Pictures\Moments\<run-id>` before launch.
- Prepare `image_list.txt` as UTF-8 with one staged absolute image path per line.
- If there is text, also prepare `text.txt` as UTF-8.
- Launch the runner:

```powershell
& $imageRunner --config $config --image-list-file $imageList --text-file $textFile --log-file $logFile
```

- For pure image posts, omit `--text-file`.

### Bash Template

Use this when the host shell is bash.

```bash
skill_root='/c/Users/<username>/.agents/skills/autopyq'
assets_dir="$skill_root/assets"
text_runner_win="$(cygpath -w "$assets_dir/wechat_moments_publish.exe")"
image_runner_win="$(cygpath -w "$assets_dir/wechat_moments_publish_images.exe")"
config_win="$(cygpath -w "$assets_dir/config.ini")"
```

- If the host app installs skills elsewhere, substitute the actual installed root, for example `/c/Users/<username>/.claude/skills/autopyq`.
- Text post:

```bash
run_id="$(date +%Y-%m-%d_%H%M%S)"
staging_dir="/c/Users/<username>/Pictures/Moments/$run_id"
mkdir -p "$staging_dir"
text_file="$staging_dir/text.txt"
log_file="$staging_dir/log.txt"
```

- Prepare `text.txt` as UTF-8 in `/c/Users/<username>/Pictures/Moments/<run-id>`.
- Launch the runner:

```bash
"$text_runner_win" --config "$config_win" --text-file "$(cygpath -w "$text_file")" --log-file "$(cygpath -w "$log_file")"
```

- Image or mixed post:

```bash
run_id="$(date +%Y-%m-%d_%H%M%S)"
staging_dir="/c/Users/<username>/Pictures/Moments/$run_id"
mkdir -p "$staging_dir"
image_list="$staging_dir/image_list.txt"
text_file="$staging_dir/text.txt"
log_file="$staging_dir/log.txt"
```

- Copy input images into `/c/Users/<username>/Pictures/Moments/<run-id>` before launch.
- Prepare `image_list.txt` as UTF-8 with one staged absolute image path per line.

```bash
staging_win="$(cygpath -w "$staging_dir")"
{
  echo "${staging_win}\\01_image.png"
  echo "${staging_win}\\02_image.jpg"
} > "$image_list"
```

- If there is text, also prepare `text.txt` as UTF-8.
- Launch the runner:

```bash
"$image_runner_win" --config "$config_win" --image-list-file "$(cygpath -w "$image_list")" --text-file "$(cygpath -w "$text_file")" --log-file "$(cygpath -w "$log_file")"
```

- For pure image posts, omit `--text-file`.

## Notes

- Use absolute paths for the runner, config file, staged files, and log file.
- In bash environments, prefer pure bash prep plus direct `exe` launch. Do not wrap a long PowerShell script inside `bash ... powershell -Command "..."`.
- When PowerShell logic becomes non-trivial, write a `.ps1` file and execute it with `powershell.exe -File`.
- If `after_publish.png` exists under `C:\Users\<username>\Pictures\Moments\<run-id>\` for the current launch, include it in the reply to the caller when the current session or plugin supports sending local files or images.

## Exit Codes

- `0`: success
- `10`: config missing or invalid
- `11`: text source missing or unreadable
- `12`: WeChat main window not found or not active
- `13`: Moments entry button not found
- `14`: Moments window not found or not active
- `15`: camera button not found
- `16`: editor anchor not found
- `17`: enabled publish button not found
- `18`: image file load or size read failed
- `19`: unexpected runtime failure
- `20`: image list missing or invalid
- `21`: image count is 0 or exceeds 9
- `22`: file dialog not found or not active
- `23`: file dialog interaction failed
- `24`: image editor did not become ready after import
