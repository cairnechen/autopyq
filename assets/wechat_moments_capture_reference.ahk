#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Off

EXIT_SUCCESS := 0
EXIT_CONFIG_ERROR := 10
EXIT_WECHAT_WINDOW_ERROR := 12
EXIT_MOMENTS_BUTTON_ERROR := 13
EXIT_MOMENTS_WINDOW_ERROR := 14
EXIT_CAMERA_BUTTON_ERROR := 15
EXIT_EDITOR_ANCHOR_ERROR := 16
EXIT_PUBLISH_BUTTON_ERROR := 17
EXIT_IMAGE_ERROR := 18
EXIT_RUNTIME_ERROR := 19
WINDOW_SIZE_PROBE := 200

stage := "startup"
logFile := ""
exitCode := EXIT_SUCCESS
exitMessage := ""
diagnostics := Map()

CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"

try {
    args := ParseArgs(A_Args)
    requestedLogFile := args["log_file"]
    configPath := args["config"]
    configDir := GetParentDir(configPath)
    config := LoadConfig(configPath)
    target := args["target"]
    workflow := BuildWorkflow(config, configDir, target)
    logFile := ResolveConfiguredLogFile(requestedLogFile, workflow["logging_enabled"], "logging.capture_enabled")
    windowStateFile := args["window_state_file"]
    SetDiagnostic("script_path", A_ScriptFullPath)
    SetDiagnostic("config_path", configPath)
    SetDiagnostic("config_dir", configDir)
    SetDiagnostic("capture_target", target)
    SetDiagnostic("wechat_win_selector", workflow["wechat_win"])
    SetDiagnostic("moments_win_selector", workflow["moments_win"])
    SetDiagnostic("search_variation", workflow["general"]["search_variation"])
    SetDiagnostic("logging_enabled", workflow["logging_enabled"] ? "1" : "0")
    SetDiagnostic("log_file_argument", requestedLogFile = "" ? "none" : requestedLogFile)
    SetDiagnostic("log_file_effective", logFile = "" ? "none" : logFile)
    if !workflow["logging_enabled"] && requestedLogFile != "" {
        SetDiagnostic("log_file_status", "ignored_by_config")
    }
    SetDiagnostic("window_state_file", windowStateFile = "" ? "none" : windowStateFile)

    captureHwnd := 0
    shouldCapture := true

    switch target {
        case "moments_button":
            stage := "wechat_window"
            captureHwnd := ActivateWindow(workflow["wechat_win"], workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_WECHAT_WINDOW_ERROR, "WeChat window not found or not active.")
            CaptureWindowDiagnostics("wechat_window", captureHwnd)
            EnsureWechatWindowPrepared(captureHwnd, workflow, windowStateFile)
        case "camera_button":
            captureHwnd := EnsureMomentsCameraWindow(workflow, windowStateFile)
        case "editor_anchor":
            editorState := EnsureMomentsEditorWindow(workflow, windowStateFile, false)
            captureHwnd := editorState["hwnd"]
        case "publish_button":
            captureHwnd := EnsurePublishButtonWindow(workflow, windowStateFile, args["seed_text"])
        case "restore_windows":
            stage := "restore_windows"
            RestoreWindowsFromState(workflow, windowStateFile)
            shouldCapture := false
        default:
            throw RunnerError(EXIT_CONFIG_ERROR, "args", "Unsupported --target value: " target)
    }

    if shouldCapture {
        CaptureWindowDiagnostics("capture_window", captureHwnd)
        capturePath := BuildCaptureOutputPath(args["output_dir"], target)
        SetDiagnostic("capture_output_path", capturePath)
        stage := "capture_window"
        captureResult := CaptureWindowScreenshot(captureHwnd, capturePath, workflow)
        if !captureResult["success"] {
            throw RunnerError(EXIT_RUNTIME_ERROR, stage, captureResult["message"])
        }
        exitMessage := "Capture completed."
    } else {
        exitMessage := "Window sizes restored."
    }

    exitCode := EXIT_SUCCESS
} catch RunnerError as err {
    exitCode := err.ExitCode
    stage := err.Stage
    exitMessage := err.Message
    CaptureActiveWindowDiagnostics("failure_active_window")
} catch Error as err {
    exitCode := EXIT_RUNTIME_ERROR
    if stage = "" {
        stage := "runtime"
    }
    exitMessage := err.Message
    CaptureActiveWindowDiagnostics("failure_active_window")
}

if logFile != "" {
    CaptureActiveWindowDiagnostics("final_active_window")
    WriteLog(logFile, exitCode, stage, exitMessage)
}

if exitMessage = "" {
    if exitCode = EXIT_SUCCESS {
        exitMessage := "Completed successfully."
    } else {
        exitMessage := "Runner failed."
    }
}

ExitApp exitCode

ParseArgs(args) {
    parsed := Map(
        "config", "",
        "target", "",
        "output_dir", "",
        "log_file", "",
        "seed_text", "test",
        "window_state_file", ""
    )

    index := 1
    while index <= args.Length {
        arg := args[index]
        switch arg {
            case "--config":
                index += 1
                if index > args.Length {
                    throw RunnerError(EXIT_CONFIG_ERROR, "args", "Missing value for --config.")
                }
                parsed["config"] := args[index]
            case "--target":
                index += 1
                if index > args.Length {
                    throw RunnerError(EXIT_CONFIG_ERROR, "args", "Missing value for --target.")
                }
                parsed["target"] := StrLower(args[index])
            case "--output-dir":
                index += 1
                if index > args.Length {
                    throw RunnerError(EXIT_CONFIG_ERROR, "args", "Missing value for --output-dir.")
                }
                parsed["output_dir"] := args[index]
            case "--log-file":
                index += 1
                if index > args.Length {
                    throw RunnerError(EXIT_CONFIG_ERROR, "args", "Missing value for --log-file.")
                }
                parsed["log_file"] := args[index]
            case "--seed-text":
                index += 1
                if index > args.Length {
                    throw RunnerError(EXIT_CONFIG_ERROR, "args", "Missing value for --seed-text.")
                }
                parsed["seed_text"] := args[index]
            case "--window-state-file":
                index += 1
                if index > args.Length {
                    throw RunnerError(EXIT_CONFIG_ERROR, "args", "Missing value for --window-state-file.")
                }
                parsed["window_state_file"] := args[index]
            default:
                throw RunnerError(EXIT_CONFIG_ERROR, "args", "Unknown argument: " arg)
        }
        index += 1
    }

    if parsed["config"] = "" {
        throw RunnerError(EXIT_CONFIG_ERROR, "args", "The --config argument is required.")
    }
    if parsed["target"] = "" {
        throw RunnerError(EXIT_CONFIG_ERROR, "args", "The --target argument is required.")
    }
    if parsed["target"] = "restore_windows" {
        if parsed["window_state_file"] = "" {
            throw RunnerError(EXIT_CONFIG_ERROR, "args", "The --window-state-file argument is required for restore_windows.")
        }
    } else if parsed["output_dir"] = "" {
        throw RunnerError(EXIT_CONFIG_ERROR, "args", "The --output-dir argument is required.")
    }

    return parsed
}

LoadConfig(path) {
    if !FileExist(path) {
        throw RunnerError(EXIT_CONFIG_ERROR, "config", "Config file not found: " path)
    }

    raw := ReadUtf8File(path, EXIT_CONFIG_ERROR, "config")
    config := Map()
    currentSection := ""

    for line in StrSplit(raw, "`n", "`r") {
        trimmed := Trim(line)
        if trimmed = "" {
            continue
        }
        if SubStr(trimmed, 1, 1) = ";" || SubStr(trimmed, 1, 1) = "#" {
            continue
        }
        if RegExMatch(trimmed, "^\[(.+)\]$", &sectionMatch) {
            currentSection := sectionMatch[1]
            if !config.Has(currentSection) {
                config[currentSection] := Map()
            }
            continue
        }
        if currentSection = "" {
            throw RunnerError(EXIT_CONFIG_ERROR, "config", "Key outside section: " trimmed)
        }

        separator := InStr(trimmed, "=")
        if !separator {
            throw RunnerError(EXIT_CONFIG_ERROR, "config", "Invalid config line: " trimmed)
        }

        key := Trim(SubStr(trimmed, 1, separator - 1))
        value := Trim(SubStr(trimmed, separator + 1))
        if key = "" {
            throw RunnerError(EXIT_CONFIG_ERROR, "config", "Empty config key in section [" currentSection "].")
        }
        config[currentSection][key] := value
    }

    return config
}

BuildWorkflow(config, configDir, target) {
    workflow := Map()
    workflow["wechat_win"] := RequireConfigValue(config, "windows", "wechat_win")
    workflow["moments_win"] := RequireConfigValue(config, "windows", "moments_win")

    general := Map()
    general["search_variation"] := ParseInteger(RequireConfigValue(config, "general", "search_variation"), "general.search_variation")
    general["activate_timeout_sec"] := ParseNumber(RequireConfigValue(config, "general", "activate_timeout_sec"), "general.activate_timeout_sec")
    general["activate_settle_ms"] := ParseInteger(RequireConfigValue(config, "general", "activate_settle_ms"), "general.activate_settle_ms")
    general["moments_wait_sec"] := ParseNumber(RequireConfigValue(config, "general", "moments_wait_sec"), "general.moments_wait_sec")
    general["editor_ready_wait_sec"] := ParseNumber(RequireConfigValue(config, "general", "editor_ready_wait_sec"), "general.editor_ready_wait_sec")
    general["paste_settle_ms"] := ParseInteger(RequireConfigValue(config, "general", "paste_settle_ms"), "general.paste_settle_ms")
    general["long_press_ms"] := ParseInteger(RequireConfigValue(config, "general", "long_press_ms"), "general.long_press_ms")
    workflow["general"] := general
    workflow["logging_enabled"] := ReadOptionalBooleanConfig(config, "logging", "capture_enabled", true, "logging.capture_enabled")
    captureResize := Map()
    captureResize["wechat_height_ratio"] := ParseNumber(RequireConfigValue(config, "capture_resize", "wechat_height_ratio"), "capture_resize.wechat_height_ratio")
    workflow["capture_resize"] := captureResize

    switch target {
        case "moments_button":
        {
            ; Bootstrap capture: allow pyq1 to be recaptured even when the runtime template is missing.
        }
        case "camera_button":
            workflow["moments_button"] := BuildAction(config, configDir, "moments_button")
        case "editor_anchor":
            workflow["moments_button"] := BuildAction(config, configDir, "moments_button")
            workflow["camera_button"] := BuildAction(config, configDir, "camera_button")
        case "publish_button":
            workflow["moments_button"] := BuildAction(config, configDir, "moments_button")
            workflow["camera_button"] := BuildAction(config, configDir, "camera_button")
            workflow["editor_anchor"] := BuildAction(config, configDir, "editor_anchor")
        case "restore_windows":
            workflow["restore_only"] := true
        default:
            throw RunnerError(EXIT_CONFIG_ERROR, "args", "Unsupported --target value: " target)
    }

    return workflow
}

BuildAction(config, configDir, sectionName) {
    imagePath := ResolvePath(configDir, RequireConfigValue(config, sectionName, "image"))
    if !FileExist(imagePath) {
        throw RunnerError(EXIT_IMAGE_ERROR, sectionName, "Image file not found: " imagePath)
    }

    size := GetImageSize(imagePath)
    clickMode := StrLower(RequireConfigValue(config, sectionName, "click_mode"))
    action := Map(
        "name", sectionName,
        "image_path", imagePath,
        "click_mode", clickMode,
        "width", size["width"],
        "height", size["height"]
    )

    if clickMode = "offset" {
        action["offset_x"] := ParseInteger(RequireConfigValue(config, sectionName, "offset_x"), sectionName ".offset_x")
        action["offset_y"] := ParseInteger(RequireConfigValue(config, sectionName, "offset_y"), sectionName ".offset_y")
    } else if clickMode != "center" {
        throw RunnerError(EXIT_CONFIG_ERROR, sectionName, "Unsupported click_mode: " clickMode)
    }

    return action
}

RequireConfigValue(config, section, key) {
    if !config.Has(section) {
        throw RunnerError(EXIT_CONFIG_ERROR, "config", "Missing config section: [" section "].")
    }
    sectionMap := config[section]
    if !sectionMap.Has(key) {
        throw RunnerError(EXIT_CONFIG_ERROR, "config", "Missing config key: [" section "] " key)
    }
    value := sectionMap[key]
    if value = "" {
        throw RunnerError(EXIT_CONFIG_ERROR, "config", "Empty config key: [" section "] " key)
    }
    return value
}

ReadOptionalBooleanConfig(config, section, key, defaultValue, label) {
    if !config.Has(section) {
        return defaultValue
    }
    sectionMap := config[section]
    if !sectionMap.Has(key) {
        return defaultValue
    }
    value := Trim(sectionMap[key])
    if value = "" {
        return defaultValue
    }
    return ParseBoolean(value, label)
}

ResolveConfiguredLogFile(requestedPath, loggingEnabled, label) {
    if loggingEnabled {
        if requestedPath = "" {
            throw RunnerError(EXIT_CONFIG_ERROR, "args", "The --log-file argument is required when " label " is true.")
        }
        return requestedPath
    }
    return ""
}

EnsureWechatWindowPrepared(hwnd, workflow, statePath) {
    global stage
    if statePath = "" {
        SetDiagnostic("wechat_window_prepare", "disabled")
        return
    }

    storedSize := ReadStoredWindowSize(statePath, "wechat")
    if IsObject(storedSize) {
        SetDiagnostic("wechat_window_prepare", "skipped_existing_state")
        return
    }

    originalBounds := GetWindowBounds(hwnd, "wechat_window_bounds", "Failed to read WeChat window bounds.")
    WriteStoredWindowSize(statePath, "wechat", originalBounds["width"], originalBounds["height"])
    SetDiagnostic("wechat_window_original_size", originalBounds["width"] "x" originalBounds["height"])

    stage := "wechat_window_resize"
    minBounds := ResizeWindowToSize(hwnd, WINDOW_SIZE_PROBE, originalBounds["height"], workflow["general"]["activate_settle_ms"], stage, "Failed to set WeChat window to its minimum width.")
    targetHeight := Max(1, Round(minBounds["width"] * workflow["capture_resize"]["wechat_height_ratio"]))
    resizedBounds := ResizeWindowToSize(hwnd, minBounds["width"], targetHeight, workflow["general"]["activate_settle_ms"], stage, "Failed to set WeChat window to the capture height.")
    SetDiagnostic("wechat_window_prepare", "resized")
    SetDiagnostic("wechat_window_resized_size", resizedBounds["width"] "x" resizedBounds["height"])
    CaptureWindowDiagnostics("wechat_window_resized", hwnd)
}

EnsureMomentsWindowPrepared(hwnd, workflow, statePath) {
    global stage
    if statePath = "" {
        SetDiagnostic("moments_window_prepare", "disabled")
        return
    }

    storedSize := ReadStoredWindowSize(statePath, "moments")
    if IsObject(storedSize) {
        SetDiagnostic("moments_window_prepare", "skipped_existing_state")
        return
    }

    originalBounds := GetWindowBounds(hwnd, "moments_window_bounds", "Failed to read Moments window bounds.")
    WriteStoredWindowSize(statePath, "moments", originalBounds["width"], originalBounds["height"])
    SetDiagnostic("moments_window_original_size", originalBounds["width"] "x" originalBounds["height"])

    stage := "moments_window_resize"
    resizedBounds := ResizeWindowToSize(hwnd, WINDOW_SIZE_PROBE, WINDOW_SIZE_PROBE, workflow["general"]["activate_settle_ms"], stage, "Failed to set Moments window to its minimum size.")
    SetDiagnostic("moments_window_prepare", "resized")
    SetDiagnostic("moments_window_resized_size", resizedBounds["width"] "x" resizedBounds["height"])
    CaptureWindowDiagnostics("moments_window_resized", hwnd)
}

RestoreWindowsFromState(workflow, statePath) {
    global stage
    if statePath = "" {
        throw RunnerError(EXIT_CONFIG_ERROR, "args", "The --window-state-file argument is required for restore_windows.")
    }
    if !FileExist(statePath) {
        throw RunnerError(EXIT_RUNTIME_ERROR, "restore_windows", "Window state file not found: " statePath)
    }

    wechatSize := ReadStoredWindowSize(statePath, "wechat")
    if IsObject(wechatSize) {
        wechatHwnd := WinExist(workflow["wechat_win"])
        if wechatHwnd {
            stage := "restore_wechat_window"
            resizedBounds := ResizeWindowToSize(wechatHwnd, wechatSize["width"], wechatSize["height"], workflow["general"]["activate_settle_ms"], stage, "Failed to restore WeChat window size.")
            SetDiagnostic("restore_wechat", "restored")
            SetDiagnostic("restore_wechat_size", resizedBounds["width"] "x" resizedBounds["height"])
        } else {
            SetDiagnostic("restore_wechat", "skipped_window_not_found")
        }
    } else {
        SetDiagnostic("restore_wechat", "skipped_no_state")
    }

    momentsSize := ReadStoredWindowSize(statePath, "moments")
    if IsObject(momentsSize) {
        momentsHwnd := WinExist(workflow["moments_win"])
        if momentsHwnd {
            stage := "restore_moments_window"
            resizedBounds := ResizeWindowToSize(momentsHwnd, momentsSize["width"], momentsSize["height"], workflow["general"]["activate_settle_ms"], stage, "Failed to restore Moments window size.")
            SetDiagnostic("restore_moments", "restored")
            SetDiagnostic("restore_moments_size", resizedBounds["width"] "x" resizedBounds["height"])
        } else {
            SetDiagnostic("restore_moments", "skipped_window_not_found")
        }
    } else {
        SetDiagnostic("restore_moments", "skipped_no_state")
    }

    stage := "restore_windows"
    if DeleteFileIfExists(statePath) {
        SetDiagnostic("window_state_file_cleanup", "deleted")
    } else {
        SetDiagnostic("window_state_file_cleanup", "kept")
    }
}

EnsureMomentsCameraWindow(workflow, statePath := "") {
    global stage
    momentsHwnd := WinExist(workflow["moments_win"])
    SetDiagnostic("entry_mode_initial", "open")
    SetDiagnostic("moments_window_exists_initial", momentsHwnd ? "1" : "0")
    if momentsHwnd {
        SetDiagnostic("moments_window_reuse", "reset")
        CaptureWindowDiagnostics("moments_window_reuse_candidate", momentsHwnd)
        ResetMomentsWindow(momentsHwnd, workflow["general"]["moments_wait_sec"])
    } else {
        SetDiagnostic("moments_window_reuse", "not_found")
    }

    stage := "wechat_window"
    wechatHwnd := ActivateWindow(workflow["wechat_win"], workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_WECHAT_WINDOW_ERROR, "WeChat window not found or not active.")
    CaptureWindowDiagnostics("wechat_window", wechatHwnd)
    EnsureWechatWindowPrepared(wechatHwnd, workflow, statePath)

    stage := "moments_button"
    CaptureWindowDiagnostics("moments_button_target_window", wechatHwnd)
    momentsButtonVariations := BuildVariationFallbacks(workflow["general"]["search_variation"])
    SetDiagnostic("moments_button_attempts", momentsButtonVariations.Length)
    SetDiagnostic("moments_button_variation_chain", JoinIntegersForLog(momentsButtonVariations))
    clickPoint := FindActionPointAcrossVariationsInWindow(wechatHwnd, workflow["moments_button"], momentsButtonVariations, EXIT_MOMENTS_BUTTON_ERROR, "Moments entry button not found.", "moments_button_variation_used")
    Click clickPoint["x"], clickPoint["y"], "Left", 1

    stage := "moments_window"
    momentsHwnd := WaitForWindow(workflow["moments_win"], workflow["general"]["moments_wait_sec"], EXIT_MOMENTS_WINDOW_ERROR, "Moments window did not appear in time.")
    ActivateWindowByHwnd(momentsHwnd, workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_MOMENTS_WINDOW_ERROR, "Moments window not found or not active.")
    EnsureMomentsWindowPrepared(momentsHwnd, workflow, statePath)
    return momentsHwnd
}

EnsureMomentsEditorWindow(workflow, statePath := "", waitForAnchor := false) {
    global stage
    momentsHwnd := EnsureMomentsCameraWindow(workflow, statePath)

    stage := "camera_button"
    cameraPoint := FindActionPointInWindow(momentsHwnd, workflow["camera_button"], workflow["general"]["search_variation"], EXIT_CAMERA_BUTTON_ERROR, "Camera button not found.")
    LongPressAt(cameraPoint["x"], cameraPoint["y"], workflow["general"]["long_press_ms"])

    if waitForAnchor {
        stage := "editor_anchor"
        editorPoint := WaitForActionPointInWindow(momentsHwnd, workflow["editor_anchor"], workflow["general"]["search_variation"], workflow["general"]["editor_ready_wait_sec"], EXIT_EDITOR_ANCHOR_ERROR, "Editor placeholder not found.")
        return Map("hwnd", momentsHwnd, "editor_point", editorPoint)
    }

    settleMs := Round(workflow["general"]["editor_ready_wait_sec"] * 1000)
    SetDiagnostic("editor_capture_mode", "settle_only")
    SetDiagnostic("editor_capture_wait_ms", settleMs)
    Sleep settleMs
    return Map("hwnd", momentsHwnd)
}

EnsurePublishButtonWindow(workflow, statePath := "", seedText := "test") {
    global stage
    editorState := EnsureMomentsEditorWindow(workflow, statePath, true)
    momentsHwnd := editorState["hwnd"]
    editorPoint := editorState["editor_point"]

    stage := "focus_editor"
    Click editorPoint["x"], editorPoint["y"], "Left", 1
    Sleep workflow["general"]["activate_settle_ms"]

    stage := "seed_text"
    SetClipboardText(seedText, 1, EXIT_RUNTIME_ERROR, stage, "Failed to load the clipboard with seed text.")
    SendEvent "^v"
    waitMs := Max(workflow["general"]["paste_settle_ms"], workflow["general"]["activate_settle_ms"])
    SetDiagnostic("publish_button_capture_mode", "seed_text_only")
    SetDiagnostic("publish_button_capture_wait_ms", waitMs)
    Sleep waitMs

    stage := "publish_button"
    return momentsHwnd
}

FindActionPointInWindow(hwnd, action, variation, exitCode, message) {
    found := FindImageInWindow(hwnd, action["image_path"], variation)
    if !found["found"] {
        throw RunnerError(exitCode, action["name"], message)
    }
    return ComputeClickPoint(found["x"], found["y"], action)
}

WaitForActionPointInWindow(hwnd, action, variation, timeoutSec, exitCode, message) {
    deadline := A_TickCount + Round(timeoutSec * 1000)

    loop {
        found := FindImageInWindow(hwnd, action["image_path"], variation)
        if found["found"] {
            return ComputeClickPoint(found["x"], found["y"], action)
        }
        if A_TickCount >= deadline {
            throw RunnerError(exitCode, action["name"], message)
        }
        Sleep 100
    }
}

FindActionPointAcrossVariationsInWindow(hwnd, action, variations, exitCode, message, diagnosticKey := "") {
    for _, variation in variations {
        found := FindImageInWindow(hwnd, action["image_path"], variation)
        if found["found"] {
            if diagnosticKey != "" {
                SetDiagnostic(diagnosticKey, variation)
            }
            return ComputeClickPoint(found["x"], found["y"], action)
        }
    }

    if diagnosticKey != "" {
        SetDiagnostic(diagnosticKey, "none")
    }
    throw RunnerError(exitCode, action["name"], message)
}

BuildVariationFallbacks(primaryVariation) {
    variations := []
    for _, variation in [primaryVariation, 30, 40] {
        if !HasIntegerValue(variations, variation) {
            variations.Push(variation)
        }
    }
    return variations
}

HasIntegerValue(values, target) {
    for _, value in values {
        if value = target {
            return true
        }
    }
    return false
}

JoinIntegersForLog(values) {
    joined := ""
    for index, value in values {
        if index > 1 {
            joined .= ","
        }
        joined .= value
    }
    return joined
}

ComputeClickPoint(foundX, foundY, action) {
    if action["click_mode"] = "center" {
        return Map(
            "x", foundX + (action["width"] // 2),
            "y", foundY + (action["height"] // 2)
        )
    }

    return Map(
        "x", foundX + action["offset_x"],
        "y", foundY + action["offset_y"]
    )
}

ResolveMomentsImageEntryState(workflow) {
    momentsHwnd := WinExist(workflow["moments_win"])
    if !momentsHwnd {
        SetDiagnostic("moments_window_reuse", "not_found")
        return Map("hwnd", 0, "mode", "open")
    }

    SetDiagnostic("moments_window_reuse", "candidate")
    CaptureWindowDiagnostics("moments_window_reuse_candidate", momentsHwnd)
    ActivateWindowByHwnd(momentsHwnd, workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_MOMENTS_WINDOW_ERROR, "Moments window not found or not active.")

    if HasActionInWindow(momentsHwnd, workflow["camera_button"], workflow["general"]["search_variation"]) {
        SetDiagnostic("moments_window_reuse", "reused")
        SetDiagnostic("moments_window_reuse_mode", "camera")
        return Map("hwnd", momentsHwnd, "mode", "camera")
    }

    SetDiagnostic("moments_window_reuse", "reset")
    ResetMomentsWindow(momentsHwnd, workflow["general"]["moments_wait_sec"])
    return Map("hwnd", 0, "mode", "open")
}

ResolveMomentsEntryState(workflow) {
    momentsHwnd := WinExist(workflow["moments_win"])
    if !momentsHwnd {
        SetDiagnostic("moments_window_reuse", "not_found")
        return Map("hwnd", 0, "mode", "open")
    }

    SetDiagnostic("moments_window_reuse", "candidate")
    CaptureWindowDiagnostics("moments_window_reuse_candidate", momentsHwnd)
    ActivateWindowByHwnd(momentsHwnd, workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_MOMENTS_WINDOW_ERROR, "Moments window not found or not active.")

    entryMode := DetectMomentsWindowMode(momentsHwnd, workflow)
    if entryMode != "" {
        SetDiagnostic("moments_window_reuse", "reused")
        SetDiagnostic("moments_window_reuse_mode", entryMode)
        return Map("hwnd", momentsHwnd, "mode", entryMode)
    }

    SetDiagnostic("moments_window_reuse", "reset")
    ResetMomentsWindow(momentsHwnd, workflow["general"]["moments_wait_sec"])
    return Map("hwnd", 0, "mode", "open")
}

DetectMomentsWindowMode(hwnd, workflow) {
    if HasActionInWindow(hwnd, workflow["editor_anchor"], workflow["general"]["search_variation"]) {
        return "editor"
    }
    if HasActionInWindow(hwnd, workflow["camera_button"], workflow["general"]["search_variation"]) {
        return "camera"
    }
    return ""
}

HasActionInWindow(hwnd, action, variation) {
    found := FindImageInWindow(hwnd, action["image_path"], variation)
    return found["found"]
}

ResetMomentsWindow(hwnd, timeoutSec) {
    try WinClose "ahk_id " hwnd
    catch TargetError {
        return
    }

    deadline := A_TickCount + Round(timeoutSec * 1000)
    loop {
        if !WinExist("ahk_id " hwnd) {
            return
        }
        if A_TickCount >= deadline {
            throw RunnerError(EXIT_MOMENTS_WINDOW_ERROR, "moments_window_reset", "Failed to close the current Moments window.")
        }
        Sleep 100
    }
}

ReadStoredWindowSize(statePath, section) {
    if statePath = "" || !FileExist(statePath) {
        return ""
    }

    width := IniRead(statePath, section, "original_width", "")
    height := IniRead(statePath, section, "original_height", "")
    if width = "" || height = "" {
        return ""
    }
    if !RegExMatch(width, "^-?\d+$") || !RegExMatch(height, "^-?\d+$") {
        throw RunnerError(EXIT_RUNTIME_ERROR, "window_state_parse", "Invalid stored window size in [" section "] of " statePath)
    }

    return Map("width", width + 0, "height", height + 0)
}

WriteStoredWindowSize(statePath, section, width, height) {
    dir := GetParentDir(statePath)
    if dir != "" {
        DirCreate dir
    }

    IniWrite width, statePath, section, "original_width"
    IniWrite height, statePath, section, "original_height"
}

GetWindowBounds(hwnd, stageName, message) {
    try WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    catch TargetError {
        throw RunnerError(EXIT_RUNTIME_ERROR, stageName, message)
    }

    return Map("x", x, "y", y, "width", w, "height", h)
}

ResizeWindowToSize(hwnd, width, height, settleMs, stageName, message) {
    windowRef := "ahk_id " hwnd
    try WinRestore windowRef
    catch Error {
    }

    bounds := GetWindowBounds(hwnd, stageName, message)
    try WinMove bounds["x"], bounds["y"], width, height, windowRef
    catch TargetError {
        throw RunnerError(EXIT_RUNTIME_ERROR, stageName, message)
    }

    Sleep settleMs
    return GetWindowBounds(hwnd, stageName, "Failed to read resized window bounds.")
}

DeleteFileIfExists(path) {
    if !FileExist(path) {
        return true
    }

    try FileDelete path
    catch Error {
        return false
    }
    return !FileExist(path)
}

FindImageInWindow(hwnd, imagePath, variation) {
    SetDiagnostic("last_image_search_image", imagePath)
    SetDiagnostic("last_image_search_variation", variation)
    CaptureWindowDiagnostics("last_image_search_window", hwnd)
    try WinGetPos &winX, &winY, &winW, &winH, "ahk_id " hwnd
    catch TargetError {
        throw RunnerError(EXIT_RUNTIME_ERROR, "window_bounds", "Failed to read window bounds.")
    }

    searchRight := winX + winW - 1
    searchBottom := winY + winH - 1
    imageSpec := "*" variation " " imagePath
    foundX := 0
    foundY := 0

    try matched := ImageSearch(&foundX, &foundY, winX, winY, searchRight, searchBottom, imageSpec)
    catch Error as err {
        throw RunnerError(EXIT_RUNTIME_ERROR, "image_search", err.Message)
    }

    return Map(
        "found", matched ? true : false,
        "x", foundX,
        "y", foundY
    )
}

ActivateWindow(winTitle, timeoutSec, settleMs, exitCode, message) {
    hwnd := WinExist(winTitle)
    if !hwnd {
        throw RunnerError(exitCode, "window_match", message)
    }
    ActivateWindowByHwnd(hwnd, timeoutSec, settleMs, exitCode, message)
    return hwnd
}

ActivateWindowByHwnd(hwnd, timeoutSec, settleMs, exitCode, message) {
    try WinActivate "ahk_id " hwnd
    catch TargetError {
        throw RunnerError(exitCode, "window_activate", message)
    }

    if !WinWaitActive("ahk_id " hwnd, , timeoutSec) {
        throw RunnerError(exitCode, "window_active", message)
    }

    Sleep settleMs
}

WaitForWindow(winTitle, timeoutSec, exitCode, message) {
    hwnd := WinWait(winTitle, , timeoutSec)
    if !hwnd {
        throw RunnerError(exitCode, "window_wait", message)
    }
    return hwnd
}

LongPressAt(x, y, durationMs) {
    MouseMove x, y, 0
    SendEvent "{LButton down}"
    Sleep durationMs
    SendEvent "{LButton up}"
}

SetClipboardText(text, timeoutSec, exitCode, stageName, message) {
    A_Clipboard := text
    if !ClipWait(timeoutSec) {
        throw RunnerError(exitCode, stageName, message)
    }
}

CaptureWindowScreenshot(hwnd, targetPath, workflow) {
    try {
        ActivateWindowByHwnd(hwnd, workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_RUNTIME_ERROR, "Capture window not found or not active.")
    } catch RunnerError as err {
        return Map("success", false, "message", err.Message)
    }

    A_Clipboard := ""
    Sleep 50
    SendEvent "!{PrintScreen}"
    if !ClipWait(2, 1) {
        return Map("success", false, "message", "Clipboard did not receive a screenshot image.")
    }

    return SaveClipboardImageToPng(targetPath)
}

BuildCaptureOutputPath(outputDir, target) {
    DirCreate outputDir
    fileName := ""
    switch target {
        case "moments_button": fileName := "capture_moments_button.png"
        case "camera_button": fileName := "capture_camera_button.png"
        case "editor_anchor": fileName := "capture_editor_anchor.png"
        case "publish_button": fileName := "capture_publish_button.png"
        default: throw RunnerError(EXIT_CONFIG_ERROR, "args", "Unsupported capture target: " target)
    }
    return outputDir "\\" fileName
}

ReadUtf8File(path, exitCode, stageName) {
    try stream := FileOpen(path, "r", "UTF-8")
    catch Error {
        throw RunnerError(exitCode, stageName, "Unable to open file: " path)
    }
    if !IsObject(stream) {
        throw RunnerError(exitCode, stageName, "Unable to open file: " path)
    }
    try {
        return stream.Read()
    } finally {
        stream.Close()
    }
}

WriteLog(path, exitCode, stageName, message) {
    global diagnostics
    dir := GetParentDir(path)
    if dir != "" {
        DirCreate dir
    }

    stream := FileOpen(path, "w", "UTF-8")
    if !IsObject(stream) {
        return
    }
    try {
        stream.WriteLine("exit_code=" exitCode)
        stream.WriteLine("stage=" stageName)
        stream.WriteLine("message=" message)
        for key, value in diagnostics {
            stream.WriteLine(key "=" value)
        }
    } finally {
        stream.Close()
    }
}

SetDiagnostic(key, value) {
    global diagnostics
    diagnostics[key] := SanitizeLogValue(value)
}

CaptureActiveWindowDiagnostics(prefix) {
    hwnd := WinExist("A")
    if hwnd {
        CaptureWindowDiagnostics(prefix, hwnd)
    }
}

CaptureWindowDiagnostics(prefix, hwnd) {
    SetDiagnostic(prefix "_hwnd", hwnd)
    if !hwnd {
        return
    }

    windowRef := "ahk_id " hwnd
    try SetDiagnostic(prefix "_title", WinGetTitle(windowRef))
    catch Error {
    }
    try SetDiagnostic(prefix "_class", WinGetClass(windowRef))
    catch Error {
    }
    try SetDiagnostic(prefix "_pid", WinGetPID(windowRef))
    catch Error {
    }
    try SetDiagnostic(prefix "_process_name", WinGetProcessName(windowRef))
    catch Error {
    }
    try {
        WinGetPos &x, &y, &w, &h, windowRef
        SetDiagnostic(prefix "_bounds", x "," y "," w "," h)
    } catch Error {
    }
}

SanitizeLogValue(value) {
    text := value ""
    text := StrReplace(text, "`r", "\\r")
    text := StrReplace(text, "`n", "\\n")
    return text
}

GetImageSize(path) {
    SplitPath path, , , &ext
    if StrLower(ext) != "png" {
        throw RunnerError(EXIT_IMAGE_ERROR, "image_size", "Only PNG templates are supported for automatic size detection: " path)
    }

    file := FileOpen(path, "r")
    if !IsObject(file) {
        throw RunnerError(EXIT_IMAGE_ERROR, "image_size", "Failed to open image: " path)
    }

    try {
        if file.Length < 24 {
            throw RunnerError(EXIT_IMAGE_ERROR, "image_size", "PNG file is too small: " path)
        }

        signature := Buffer(8, 0)
        if file.RawRead(signature, 8) != 8 {
            throw RunnerError(EXIT_IMAGE_ERROR, "image_size", "Failed to read PNG signature: " path)
        }

        if NumGet(signature, 0, "UChar") != 137
            || NumGet(signature, 1, "UChar") != 80
            || NumGet(signature, 2, "UChar") != 78
            || NumGet(signature, 3, "UChar") != 71
            || NumGet(signature, 4, "UChar") != 13
            || NumGet(signature, 5, "UChar") != 10
            || NumGet(signature, 6, "UChar") != 26
            || NumGet(signature, 7, "UChar") != 10 {
            throw RunnerError(EXIT_IMAGE_ERROR, "image_size", "Invalid PNG signature: " path)
        }

        file.Pos := 16
        header := Buffer(8, 0)
        if file.RawRead(header, 8) != 8 {
            throw RunnerError(EXIT_IMAGE_ERROR, "image_size", "Failed to read PNG dimensions: " path)
        }

        width := ReadUInt32BE(header, 0)
        height := ReadUInt32BE(header, 4)
        if width <= 0 || height <= 0 {
            throw RunnerError(EXIT_IMAGE_ERROR, "image_size", "Invalid PNG dimensions: " path)
        }

        return Map("width", width, "height", height)
    } finally {
        file.Close()
    }
}

SaveClipboardImageToPng(targetPath) {
    psExe := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(psExe) {
        return Map("success", false, "message", "powershell.exe not found.")
    }

    tempBase := A_Temp "\moments_save_clipboard_" A_TickCount
    tempScript := tempBase ".ps1"
    errorPath := tempBase ".err.txt"
    psLines := [
        "param([string]__DOLLAR__TargetPath, [string]__DOLLAR__ErrorPath)",
        "try {",
        "    Add-Type -AssemblyName System.Windows.Forms",
        "    Add-Type -AssemblyName System.Drawing",
        "    __DOLLAR__image = [System.Windows.Forms.Clipboard]::GetImage()",
        "    if (__DOLLAR__null -eq __DOLLAR__image) { throw 'Clipboard does not contain an image.' }",
        "    try {",
        "        __DOLLAR__dir = Split-Path -Parent __DOLLAR__TargetPath",
        "        if (__DOLLAR__dir -and -not (Test-Path __DOLLAR__dir)) { New-Item -ItemType Directory -Path __DOLLAR__dir -Force | Out-Null }",
        "        __DOLLAR__image.Save(__DOLLAR__TargetPath, [System.Drawing.Imaging.ImageFormat]::Png)",
        "    } finally {",
        "        __DOLLAR__image.Dispose()",
        "    }",
        "    exit 0",
        "} catch {",
        "    [System.IO.File]::WriteAllText(__DOLLAR__ErrorPath, __DOLLAR___.Exception.Message, [System.Text.Encoding]::UTF8)",
        "    exit 1",
        "}"
    ]
    psContent := ""
    for index, line in psLines {
        if index > 1 {
            psContent .= "`r`n"
        }
        psContent .= line
    }
    psContent := StrReplace(psContent, "__DOLLAR__", Chr(36)) "`r`n"

    try FileDelete tempScript
    catch Error {
    }
    try FileDelete errorPath
    catch Error {
    }

    try {
        FileAppend psContent, tempScript, "UTF-8"
        command := '"' psExe '" -Sta -NoProfile -ExecutionPolicy Bypass -File "' tempScript '" -TargetPath "' targetPath '" -ErrorPath "' errorPath '"'
        exitCode := RunWait(command, , "Hide")
    } catch Error as err {
        try FileDelete tempScript
        catch Error {
        }
        try FileDelete errorPath
        catch Error {
        }
        return Map("success", false, "message", err.Message)
    }

    errorMessage := ""
    if FileExist(errorPath) {
        try errorMessage := Trim(FileRead(errorPath, "UTF-8"))
        catch Error {
        }
    }

    try FileDelete tempScript
    catch Error {
    }
    try FileDelete errorPath
    catch Error {
    }

    if exitCode != 0 {
        if errorMessage = "" {
            errorMessage := "PowerShell screenshot save failed."
        }
        return Map("success", false, "message", errorMessage)
    }

    if !FileExist(targetPath) {
        return Map("success", false, "message", "Screenshot file was not created.")
    }

    return Map("success", true, "message", "Screenshot saved.")
}

ReadUInt32BE(buffer, offset) {
    return (NumGet(buffer, offset, "UChar") << 24)
        | (NumGet(buffer, offset + 1, "UChar") << 16)
        | (NumGet(buffer, offset + 2, "UChar") << 8)
        | NumGet(buffer, offset + 3, "UChar")
}

ParseBoolean(value, label) {
    lowered := StrLower(Trim(value))
    if lowered = "true" {
        return true
    }
    if lowered = "false" {
        return false
    }
    throw RunnerError(EXIT_CONFIG_ERROR, "config", "Expected true or false for " label ".")
}

ParseInteger(value, label) {
    if !RegExMatch(value, "^-?\d+$") {
        throw RunnerError(EXIT_CONFIG_ERROR, "config", "Expected integer for " label ".")
    }
    return value + 0
}

ParseNumber(value, label) {
    if !RegExMatch(value, "^-?(?:\d+(?:\.\d+)?|\.\d+)$") {
        throw RunnerError(EXIT_CONFIG_ERROR, "config", "Expected number for " label ".")
    }
    return value + 0
}

ResolvePath(baseDir, configuredPath) {
    if RegExMatch(configuredPath, "i)^[A-Z]:\\") || SubStr(configuredPath, 1, 2) = "\\" {
        return configuredPath
    }
    if baseDir = "" {
        return configuredPath
    }
    return baseDir "\\" configuredPath
}

GetParentDir(path) {
    SplitPath path, , &dir
    return dir
}

class RunnerError extends Error {
    __New(exitCode, stageName, message) {
        super.__New(message)
        this.ExitCode := exitCode
        this.Stage := stageName
    }
}





