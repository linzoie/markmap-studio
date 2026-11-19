# ============================================================
# lib-lang-reminder.ps1 -- dot-sourced library (NOT a hook; wired nowhere in settings)
#
# 2026-11-18 next-batch-1 item L (design: .governance/specs/2026-11-14-next-batch-L-lang-reminder-design.md, 11-08 user ruling A).
#
# What it does: once detect-language-drift.ps1 (Stop) has blocked a session for English narration, every later covered tool call of that
# session gets ONE fixed Traditional-Chinese reminder injected as PostToolUse additionalContext. The reminder reaches the model before its
# NEXT sampling step; it cannot prevent the sentence already written (honest limit, same as detect-language-drift boundary 1).
#
#   Write side : detect-language-drift.ps1 calls AglrMarkBlocked $data when it is about to exit 2.
#   Read side  : record-branch-switch.ps1 (Bash|PowerShell, section D, project copy only) and record-reads.ps1 (Read|Grep|Glob|Edit|Write|
#                MultiEdit|NotebookEdit) call AglrGetReminder $data and print AglrContextJson $text (record-branch-switch merges with its own
#                section B output through AglrMergeContext so stdout is always ONE JSON line).
#   Marker     : <state dir>\lang-drift-blocked-<sanitised sid>.json  {schema, session_id, first_ts, last_ts, count}
#                state dir = $HOME\.claude\session-state, or LANG_DRIFT_STATE_DIR when it is under TEMP and no reparse point on the way.
#
# Fail direction (this is a quality reminder, not a security boundary): every function never throws. A failed write only loses the reminder;
# a failed read means "no reminder" (undeterminable state is treated as absent on purpose). Nothing here can block a tool or change a decision.
#
# Reminder text (kept in base64 so the code is pure ASCII on any console code page; the original is the next line, a test compares them):
# REMINDER_TEXT: 提醒：工具呼叫之間的過場句一律用繁體中文（本 session 已被語言檢查擋過）。
#
# Code is ASCII only; helper functions use the Aglr prefix. The library never calls exit and never writes stdout (callers print what it returns).
# ============================================================

$AglrMsgB64 = '5o+Q6YaS77ya5bel5YW35ZG85Y+r5LmL6ZaT55qE6YGO5aC05Y+l5LiA5b6L55So57mB6auU5Lit5paH77yI5pysIHNlc3Npb24g5bey6KKr6Kqe6KiA5qqi5p+l5pOL6YGO77yJ44CC'

function AglrGetUtf8 { return (New-Object System.Text.UTF8Encoding $false) }

function AglrDecode([string]$b64) { return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }

function AglrToAsciiJson($obj) {
    $j = $obj | ConvertTo-Json -Depth 6 -Compress
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $j.ToCharArray()) {
        if ([int]$ch -gt 126) { [void]$sb.Append([char]92).Append('u').Append(([int]$ch).ToString('x4')) }
        else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

# GetFullPath().StartsWith(TEMP) compares strings only and never resolves reparse points: check every existing ancestor.
# (Same text as Ag2bNoReparseUnderTemp in lib-process-query-stall.ps1; test-lang-reminder.ps1 compares them so the copies cannot drift.)
function AglrNoReparseUnderTemp([string]$full, [string]$tmpRoot) {
    $stop = $tmpRoot.TrimEnd('\', '/')
    $p = $full
    while ($p -and $p.StartsWith($stop, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $p) {
            try {
                if ((Get-Item -LiteralPath $p -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
            } catch { return $false }
        }
        $parent = [IO.Path]::GetDirectoryName($p)
        if (-not $parent -or $parent -eq $p) { break }
        $p = $parent
    }
    return $true
}

# Session id -> file-name-safe key. Same rule as Ag2bSafeKey (including the Trim of dots). Blank or all-dot ids give '' = never write, never read
# (no shared "no-session" bucket: one blocked session would remind every id-less call).
function AglrSafeKey([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $k = $s -replace '[^A-Za-z0-9_.-]', '_'
    $k = $k -replace '\.{2,}', '.'
    $k = $k.Trim('.')
    if ($k.Length -gt 80) { $k = $k.Substring(0, 80) }
    return $k
}

# State directory. LANG_DRIFT_STATE_DIR is honoured only under TEMP with no reparse point on the way; otherwise ignored (default used).
# $notify prints one stderr line when an override is ignored (write side only; the read side stays silent).
function AglrStateDir([bool]$notify) {
    $default = Join-Path $HOME '.claude\session-state'
    $envValue = $env:LANG_DRIFT_STATE_DIR
    if (-not $envValue) { return $default }
    try {
        $c = [IO.Path]::GetFullPath($envValue)
        $tmp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($c.StartsWith($tmp, [System.StringComparison]::OrdinalIgnoreCase) -and (AglrNoReparseUnderTemp $c $tmp)) { return $c }
        if ($notify) { [Console]::Error.WriteLine('[lang-reminder] ignored state dir override (not under TEMP or via junction)') }
        return $default
    } catch {
        if ($notify) { [Console]::Error.WriteLine('[lang-reminder] ignored state dir override (unparsable path)') }
        return $default
    }
}

# Write side. Returns $true when the marker was written, $false otherwise (no session id, unwritable directory, anything). Never throws.
function AglrMarkBlocked($data) {
    try {
        if ($null -eq $data) { return $false }
        $key = AglrSafeKey "$($data.session_id)"
        if (-not $key) { return $false }
        $dir = AglrStateDir $true
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $file = Join-Path $dir ('lang-drift-blocked-' + $key + '.json')
        $now = (Get-Date).ToUniversalTime().ToString('o')
        $n = 1
        $first = $now
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            try {
                $txt = [IO.File]::ReadAllText($file, (AglrGetUtf8))
                $mc = [regex]::Match($txt, '"count"\s*:\s*([0-9]{1,6})')
                $mf = [regex]::Match($txt, '"first_ts"\s*:\s*"([^"]{1,64})"')
                if ($mc.Success) { $n = [Math]::Min([int]$mc.Groups[1].Value + 1, 99) }
                if ($mf.Success) { $first = $mf.Groups[1].Value }
            } catch { $n = 1; $first = $now }
        }
        $o = [ordered]@{ schema = 1; session_id = $key; first_ts = $first; last_ts = $now; count = $n }
        [IO.File]::WriteAllText($file, ($o | ConvertTo-Json -Compress), (AglrGetUtf8))
        return $true
    } catch { return $false }
}

# Read side. Returns the reminder text, or '' (nothing to say / cannot tell). Only a Leaf file at the marker path counts (directory or junction = no).
# Not PostToolUse, a subagent call (agent_id present) or a blank session id = no reminder.
function AglrGetReminder($data) {
    try {
        if ($null -eq $data) { return '' }
        if ("$($data.hook_event_name)" -ne 'PostToolUse') { return '' }
        if (-not [string]::IsNullOrEmpty("$($data.agent_id)")) { return '' }
        $key = AglrSafeKey "$($data.session_id)"
        if (-not $key) { return '' }
        $dir = AglrStateDir $false
        $file = Join-Path $dir ('lang-drift-blocked-' + $key + '.json')
        if (Test-Path -LiteralPath $file -PathType Leaf) { return (AglrDecode $AglrMsgB64) }
        return ''
    } catch { return '' }
}

# One-line ASCII JSON for PostToolUse additionalContext.
function AglrContextJson([string]$text) {
    $o = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = 'PostToolUse'; additionalContext = $text } }
    return (AglrToAsciiJson $o)
}

# Merge the reminder into an existing one-line JSON (section B of record-branch-switch) so stdout stays a single JSON object.
# Any problem returns the existing JSON unchanged (the process-query reminder wins).
function AglrMergeContext([string]$existingJson, [string]$text) {
    try {
        $j = $existingJson | ConvertFrom-Json
        $ev = "$($j.hookSpecificOutput.hookEventName)"
        if (-not $ev) { $ev = 'PostToolUse' }
        $ctx = "$($j.hookSpecificOutput.additionalContext)"
        if (-not $ctx) { return $existingJson }
        $o = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = $ev; additionalContext = ($ctx + "`n" + $text) } }
        return (AglrToAsciiJson $o)
    } catch { return $existingJson }
}
