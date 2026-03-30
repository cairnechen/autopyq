#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Off

EXIT_SUCCESS := 0
EXIT_CONFIG_ERROR := 10
EXIT_TEXT_ERROR := 11
EXIT_WECHAT_WINDOW_ERROR := 12
EXIT_MOMENTS_BUTTON_ERROR := 13
EXIT_MOMENTS_WINDOW_ERROR := 14
EXIT_CAMERA_BUTTON_ERROR := 15
EXIT_EDITOR_ANCHOR_ERROR := 16
EXIT_PUBLISH_BUTTON_ERROR := 17
EXIT_IMAGE_ERROR := 18
EXIT_RUNTIME_ERROR := 19
EXIT_IMAGE_LIST_ERROR := 20
EXIT_IMAGE_COUNT_ERROR := 21
EXIT_FILE_DIALOG_ERROR := 22
EXIT_FILE_DIALOG_INTERACTION_ERROR := 23
EXIT_IMAGE_EDITOR_ERROR := 24

stage := "startup"
logFile := ""
afterPublishPath := ""
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
    workflow := BuildWorkflow(config, configDir)
    logFile := ResolveConfiguredLogFile(requestedLogFile, workflow["logging_enabled"], "logging.publish_enabled")
    SetDiagnostic("script_path", A_ScriptFullPath)
    SetDiagnostic("config_path", configPath)
    SetDiagnostic("config_dir", configDir)
    SetDiagnostic("wechat_win_selector", workflow["wechat_win"])
    SetDiagnostic("moments_win_selector", workflow["moments_win"])
    SetDiagnostic("file_dialog_win_selector", workflow["file_dialog_win"])
    SetDiagnostic("search_variation", workflow["general"]["search_variation"])
    SetDiagnostic("logging_enabled", workflow["logging_enabled"] ? "1" : "0")
    SetDiagnostic("log_file_argument", requestedLogFile = "" ? "none" : requestedLogFile)
    SetDiagnostic("log_file_effective", logFile = "" ? "none" : logFile)
    if !workflow["logging_enabled"] && requestedLogFile != "" {
        SetDiagnostic("log_file_status", "ignored_by_config")
    }
    SetDiagnostic("after_publish_screenshot_enabled", workflow["after_publish_screenshot"]["enabled"] ? "1" : "0")
    if workflow["after_publish_screenshot"]["enabled"] {
        afterPublishPath := ResolveAfterPublishScreenshotPath(args)
        SetDiagnostic("after_publish_screenshot_path", afterPublishPath)
    } else {
        SetDiagnostic("after_publish_screenshot_path", "disabled")
    }


    stage := "image_list"
    imagePaths := LoadImageList(args["image_list_file"])
    importSpec := BuildImportSpec(imagePaths)
    SetDiagnostic("image_count", importSpec["count"])
    SetDiagnostic("import_dir", importSpec["dir"])
    SetDiagnostic("import_filename_spec", importSpec["filename_spec"])

    postText := ""
    hasText := false
    stage := "text_source"
    if args["text_file"] != "" {
        postText := ReadUtf8File(args["text_file"], EXIT_TEXT_ERROR, stage)
        if IsBlank(postText) {
            throw RunnerError(EXIT_TEXT_ERROR, stage, "Text file is empty.")
        }
        hasText := true
    }

    stage := "moments_window_check"
    momentsState := ResolveMomentsImageEntryState(workflow)
    momentsHwnd := momentsState["hwnd"]
    entryMode := momentsState["mode"]
    SetDiagnostic("entry_mode_initial", entryMode)
    SetDiagnostic("moments_window_exists_initial", momentsHwnd ? "1" : "0")
    if momentsHwnd {
        CaptureWindowDiagnostics("initial_moments_window", momentsHwnd)
    }

    if entryMode = "open" {
        stage := "wechat_window"
        wechatHwnd := ActivateWindow(workflow["wechat_win"], workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_WECHAT_WINDOW_ERROR, "WeChat window not found or not active.")
        CaptureWindowDiagnostics("wechat_window", wechatHwnd)

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
        entryMode := "camera"
    }

    if entryMode = "camera" {
        stage := "camera_button"
        cameraPoint := FindActionPointInWindow(momentsHwnd, workflow["camera_button"], workflow["general"]["search_variation"], EXIT_CAMERA_BUTTON_ERROR, "Camera button not found.")
        Click cameraPoint["x"], cameraPoint["y"], "Left", 1
    }

    stage := "file_dialog_wait"
    dialogHwnd := WaitForWindow(workflow["file_dialog_win"], workflow["general"]["moments_wait_sec"], EXIT_FILE_DIALOG_ERROR, "File dialog did not appear in time.")
    ActivateWindowByHwnd(dialogHwnd, workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_FILE_DIALOG_ERROR, "File dialog not found or not active.")

    ImportImagesThroughDialog(dialogHwnd, importSpec, workflow)

    stage := "image_editor_ready"
    ActivateWindowByHwnd(momentsHwnd, workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_IMAGE_EDITOR_ERROR, "Image editor not found or not active.")
    WaitForImageEditorReady(momentsHwnd, workflow, workflow["general"]["editor_ready_wait_sec"])

    if hasText {
        stage := "editor_anchor"
        editorPoint := WaitForActionPointInWindow(momentsHwnd, workflow["editor_anchor"], workflow["general"]["search_variation"], workflow["general"]["editor_ready_wait_sec"], EXIT_EDITOR_ANCHOR_ERROR, "Editor placeholder not found.")
        Click editorPoint["x"], editorPoint["y"], "Left", 1
        Sleep workflow["general"]["activate_settle_ms"]

        stage := "paste_text"
        SetClipboardText(postText, 1, EXIT_TEXT_ERROR, stage, "Failed to load the clipboard with post text.")
        SendEvent "^v"
        Sleep workflow["general"]["paste_settle_ms"]
    }

    stage := "publish_button"
    publishPoint := WaitForActionPointInWindow(momentsHwnd, workflow["publish_button"], workflow["general"]["search_variation"], workflow["general"]["activate_timeout_sec"], EXIT_PUBLISH_BUTTON_ERROR, "Enabled publish button not found.")
    if args["dry_run"] {
        exitCode := EXIT_SUCCESS
        exitMessage := "Dry run completed. Publish button located."
    } else {
        Click publishPoint["x"], publishPoint["y"], "Left", 1
        if workflow["after_publish_screenshot"]["enabled"] {
            SetDiagnostic("after_publish_screenshot_wait_ms", workflow["after_publish_screenshot"]["wait_ms"])
            Sleep workflow["after_publish_screenshot"]["wait_ms"]
            screenshotResult := CaptureAfterPublishScreenshot(momentsHwnd, afterPublishPath, workflow)
            SetDiagnostic("after_publish_screenshot_status", screenshotResult["success"] ? "success" : "failed")
            SetDiagnostic("after_publish_screenshot_message", screenshotResult["message"])
        }
        exitCode := EXIT_SUCCESS
        exitMessage := "Published successfully."
    }
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
        "image_list_file", "",
        "text_file", "",
        "dry_run", false,
        "log_file", ""
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
            case "--image-list-file":
                index += 1
                if index > args.Length {
                    throw RunnerError(EXIT_CONFIG_ERROR, "args", "Missing value for --image-list-file.")
                }
                parsed["image_list_file"] := args[index]
            case "--text-file":
                index += 1
                if index > args.Length {
                    throw RunnerError(EXIT_CONFIG_ERROR, "args", "Missing value for --text-file.")
                }
                parsed["text_file"] := args[index]
            case "--dry-run":
                parsed["dry_run"] := true
            case "--log-file":
                index += 1
                if index > args.Length {
                    throw RunnerError(EXIT_CONFIG_ERROR, "args", "Missing value for --log-file.")
                }
                parsed["log_file"] := args[index]
            default:
                throw RunnerError(EXIT_CONFIG_ERROR, "args", "Unknown argument: " arg)
        }
        index += 1
    }

    if parsed["config"] = "" {
        throw RunnerError(EXIT_CONFIG_ERROR, "args", "The --config argument is required.")
    }
    if parsed["image_list_file"] = "" {
        throw RunnerError(EXIT_CONFIG_ERROR, "args", "The --image-list-file argument is required.")
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

BuildWorkflow(config, configDir) {
    workflow := Map()
    workflow["wechat_win"] := RequireConfigValue(config, "windows", "wechat_win")
    workflow["moments_win"] := RequireConfigValue(config, "windows", "moments_win")
    workflow["file_dialog_win"] := RequireConfigValue(config, "windows", "file_dialog_win")

    general := Map()
    general["search_variation"] := ParseInteger(RequireConfigValue(config, "general", "search_variation"), "general.search_variation")
    general["activate_timeout_sec"] := ParseNumber(RequireConfigValue(config, "general", "activate_timeout_sec"), "general.activate_timeout_sec")
    general["activate_settle_ms"] := ParseInteger(RequireConfigValue(config, "general", "activate_settle_ms"), "general.activate_settle_ms")
    general["moments_wait_sec"] := ParseNumber(RequireConfigValue(config, "general", "moments_wait_sec"), "general.moments_wait_sec")
    general["editor_ready_wait_sec"] := ParseNumber(RequireConfigValue(config, "general", "editor_ready_wait_sec"), "general.editor_ready_wait_sec")
    general["paste_settle_ms"] := ParseInteger(RequireConfigValue(config, "general", "paste_settle_ms"), "general.paste_settle_ms")
    general["long_press_ms"] := ParseInteger(RequireConfigValue(config, "general", "long_press_ms"), "general.long_press_ms")
    workflow["general"] := general
    afterPublishScreenshot := Map()
    afterPublishScreenshot["enabled"] := ParseBoolean(RequireConfigValue(config, "after_publish_screenshot", "enabled"), "after_publish_screenshot.enabled")
    afterPublishScreenshot["wait_ms"] := ParseInteger(RequireConfigValue(config, "after_publish_screenshot", "wait_ms"), "after_publish_screenshot.wait_ms")
    workflow["after_publish_screenshot"] := afterPublishScreenshot
    workflow["logging_enabled"] := ReadOptionalBooleanConfig(config, "logging", "publish_enabled", true, "logging.publish_enabled")

    workflow["moments_button"] := BuildAction(config, configDir, "moments_button")
    workflow["camera_button"] := BuildAction(config, configDir, "camera_button")
    workflow["editor_anchor"] := BuildAction(config, configDir, "editor_anchor")
    workflow["publish_button"] := BuildAction(config, configDir, "publish_button")

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

LoadImageList(path) {
    raw := ReadUtf8File(path, EXIT_IMAGE_LIST_ERROR, "image_list")
    imagePaths := []

    for line in StrSplit(raw, "`n", "`r") {
        trimmed := Trim(line)
        if trimmed != "" {
            imagePaths.Push(trimmed)
        }
    }

    if imagePaths.Length = 0 {
        throw RunnerError(EXIT_IMAGE_COUNT_ERROR, "image_list", "Image list is empty.")
    }
    if imagePaths.Length > 9 {
        throw RunnerError(EXIT_IMAGE_COUNT_ERROR, "image_list", "Image count exceeds the 9-image limit.")
    }

    return imagePaths
}

BuildImportSpec(imagePaths) {
    stagingDir := ""
    baseNames := []

    for _, imagePath in imagePaths {
        normalizedPath := Trim(imagePath)
        if !IsAbsolutePath(normalizedPath) {
            throw RunnerError(EXIT_IMAGE_LIST_ERROR, "image_list", "Image path must be absolute: " normalizedPath)
        }

        fileAttributes := FileExist(normalizedPath)
        if !fileAttributes {
            throw RunnerError(EXIT_IMAGE_LIST_ERROR, "image_list", "Image file not found: " normalizedPath)
        }
        if InStr(fileAttributes, "D") {
            throw RunnerError(EXIT_IMAGE_LIST_ERROR, "image_list", "Image path points to a directory: " normalizedPath)
        }

        SplitPath normalizedPath, &fileName, &dir, &ext
        if fileName = "" || dir = "" {
            throw RunnerError(EXIT_IMAGE_LIST_ERROR, "image_list", "Invalid image path: " normalizedPath)
        }
        if !IsSupportedPostImageExt(ext) {
            throw RunnerError(EXIT_IMAGE_LIST_ERROR, "image_list", "Unsupported image extension: " normalizedPath)
        }

        if stagingDir = "" {
            stagingDir := dir
        } else if stagingDir != dir {
            throw RunnerError(EXIT_IMAGE_LIST_ERROR, "image_list", "All staged images must be in the same directory: " normalizedPath)
        }

        baseNames.Push(fileName)
    }

    return Map(
        "dir", stagingDir,
        "filename_spec", BuildQuotedFilenameSpec(baseNames),
        "count", baseNames.Length
    )
}

BuildQuotedFilenameSpec(baseNames) {
    quote := Chr(34)
    parts := []
    for _, baseName in baseNames {
        parts.Push(quote baseName quote)
    }
    return JoinArray(parts, " ")
}

JoinArray(parts, separator) {
    joined := ""
    for index, part in parts {
        if index > 1 {
            joined .= separator
        }
        joined .= part
    }
    return joined
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

ResolveAfterPublishScreenshotPath(args) {
    return ResolveAfterPublishPathFromSourceFile(args["image_list_file"], "--image-list-file")
}

ResolveAfterPublishPathFromSourceFile(path, label) {
    sourcePath := MakeAbsolutePath(path)
    dir := GetParentDir(sourcePath)
    return BuildAfterPublishPathFromDir(dir, label)
}

BuildAfterPublishPathFromDir(dir, label) {
    normalizedDir := RTrim(Trim(dir), "\/")
    if normalizedDir = "" {
        throw RunnerError(EXIT_CONFIG_ERROR, "after_publish_screenshot", "Failed to resolve the output directory for " label ".")
    }
    return normalizedDir "\after_publish.png"
}

MakeAbsolutePath(path) {
    if RegExMatch(path, "i)^[A-Z]:\\") || SubStr(path, 1, 2) = "\\" {
        return path
    }
    if A_WorkingDir = "" {
        return path
    }
    return A_WorkingDir "\" path
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

ImportImagesThroughDialog(dialogHwnd, importSpec, workflow) {
    result := TrySubmitImageImport(dialogHwnd, importSpec, workflow, "!d")
    if result["success"] {
        return
    }

    if WinExist("ahk_id " dialogHwnd) {
        ActivateWindowByHwnd(dialogHwnd, workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_FILE_DIALOG_ERROR, "File dialog not found or not active.")
        result := TrySubmitImageImport(dialogHwnd, importSpec, workflow, "^l")
        if result["success"] {
            return
        }
    }

    throw RunnerError(EXIT_FILE_DIALOG_INTERACTION_ERROR, result["stage"], result["message"])
}

TrySubmitImageImport(dialogHwnd, importSpec, workflow, locationHotkey) {
    if !WinExist("ahk_id " dialogHwnd) {
        return Map("success", false, "stage", "file_dialog_wait", "message", "File dialog closed unexpectedly.")
    }

    ActivateWindowByHwnd(dialogHwnd, workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_FILE_DIALOG_ERROR, "File dialog not found or not active.")

    SetClipboardText(importSpec["dir"], 1, EXIT_FILE_DIALOG_INTERACTION_ERROR, "file_dialog_directory", "Failed to load the staging directory into the clipboard.")
    SendEvent locationHotkey
    Sleep workflow["general"]["activate_settle_ms"]
    SendEvent "^a"
    Sleep 50
    SendEvent "^v"
    Sleep 50
    SendEvent "{Enter}"
    Sleep workflow["general"]["activate_settle_ms"]

    if !WinExist("ahk_id " dialogHwnd) {
        return Map("success", false, "stage", "file_dialog_directory", "message", "File dialog closed before the filename step.")
    }

    SetClipboardText(importSpec["filename_spec"], 1, EXIT_FILE_DIALOG_INTERACTION_ERROR, "file_dialog_filename", "Failed to load image file names into the clipboard.")
    SendEvent "!n"
    Sleep workflow["general"]["activate_settle_ms"]
    SendEvent "^a"
    Sleep 50
    SendEvent "^v"
    Sleep 50
    SendEvent "{Enter}"

    if WaitForWindowClosedByHwnd(dialogHwnd, workflow["general"]["moments_wait_sec"]) {
        return Map("success", true, "stage", "", "message", "")
    }

    return Map("success", false, "stage", "file_dialog_filename", "message", "Failed to submit image file names in the file dialog.")
}

WaitForWindowClosedByHwnd(hwnd, timeoutSec) {
    deadline := A_TickCount + Round(timeoutSec * 1000)

    loop {
        if !WinExist("ahk_id " hwnd) {
            return true
        }
        if A_TickCount >= deadline {
            return false
        }
        Sleep 100
    }
}

WaitForImageEditorReady(hwnd, workflow, timeoutSec) {
    deadline := A_TickCount + Round(timeoutSec * 1000)

    loop {
        if HasActionInWindow(hwnd, workflow["editor_anchor"], workflow["general"]["search_variation"]) {
            return
        }
        if HasActionInWindow(hwnd, workflow["publish_button"], workflow["general"]["search_variation"]) {
            return
        }

        if A_TickCount >= deadline {
            throw RunnerError(EXIT_IMAGE_EDITOR_ERROR, "image_editor_ready", "Image editor did not become ready after import.")
        }

        Sleep 100
    }
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

SetClipboardText(text, timeoutSec, exitCode, stageName, message) {
    A_Clipboard := text
    if !ClipWait(timeoutSec) {
        throw RunnerError(exitCode, stageName, message)
    }
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

CaptureAfterPublishScreenshot(hwnd, screenshotPath, workflow) {
    if screenshotPath = "" {
        return Map("success", false, "path", "", "message", "After-publish screenshot path is empty.")
    }

    try {
        ActivateWindowByHwnd(hwnd, workflow["general"]["activate_timeout_sec"], workflow["general"]["activate_settle_ms"], EXIT_RUNTIME_ERROR, "Moments window not found or not active.")
    } catch RunnerError as err {
        return Map("success", false, "path", screenshotPath, "message", err.Message)
    }

    A_Clipboard := ""
    Sleep 50
    SendEvent "!{PrintScreen}"
    if !ClipWait(2, 1) {
        return Map("success", false, "path", screenshotPath, "message", "Clipboard did not receive a screenshot image.")
    }

    saveResult := SaveClipboardImageToPng(screenshotPath)
    return Map("success", saveResult["success"], "path", screenshotPath, "message", saveResult["message"])
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
    configuredPath := ExpandEnvironmentVariables(configuredPath)
    if RegExMatch(configuredPath, "i)^[A-Z]:\\") || SubStr(configuredPath, 1, 2) = "\\" {
        return configuredPath
    }
    if baseDir = "" {
        return configuredPath
    }
    return baseDir "\\" configuredPath
}

ExpandEnvironmentVariables(value) {
    needed := DllCall("ExpandEnvironmentStringsW", "Str", value, "Ptr", 0, "UInt", 0, "UInt")
    if !needed {
        return value
    }
    expandedBuffer := Buffer(needed * 2, 0)
    written := DllCall("ExpandEnvironmentStringsW", "Str", value, "Ptr", expandedBuffer.Ptr, "UInt", needed, "UInt")
    if !written {
        return value
    }
    return StrGet(expandedBuffer, , "UTF-16")
}

GetParentDir(path) {
    SplitPath path, , &dir
    return dir
}

IsBlank(value) {
    return RegExMatch(value, "^\s*$")
}

IsAbsolutePath(path) {
    return RegExMatch(path, "i)^[A-Z]:\\") || SubStr(path, 1, 2) = "\\"
}

IsSupportedPostImageExt(ext) {
    extLower := StrLower(ext)
    supported := Map(
        "png", true,
        "jpg", true,
        "jpeg", true,
        "bmp", true,
        "gif", true,
        "webp", true
    )
    return supported.Has(extLower)
}

class RunnerError extends Error {
    __New(exitCode, stageName, message) {
        super.__New(message)
        this.ExitCode := exitCode
        this.Stage := stageName
    }
}







