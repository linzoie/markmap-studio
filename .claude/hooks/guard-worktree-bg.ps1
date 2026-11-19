#!/usr/bin/env pwsh
# ============================================================
# guard-worktree-bg.ps1  --  PreToolUse hook (matcher: ^EnterWorktree$)
#
# 【為什麼存在】研究檔 #14／計畫書 §3 C3（2026-11-09 起草、11-14 依真實樣本修正）：進 worktree（尤其是在同一個
# VS Code 視窗開別的資料夾）會讓還在跑的 Workflow／背景 Agent／背景 shell 停掉或收不到結果
# （memory vscode-window-close-stops-background-workflows，機制為推測、現象多次發生）。進去之前提醒一次，
# 比事後找不到結果便宜。
#
# 【設計：只提醒（ask），不擋】
# 使用者「按允許」即照常進入；沒有 deny、沒有 allow，只有 ask 與靜默放行。誤判成本不對稱：多一個確認框是
# 小成本，漏提醒＝背景工作的結果沒了。
#
# 【判準：掃主逐字稿（transcript_path），PreToolUse 輸入沒有 background_tasks（§2-2）】
#   「發射」三種，皆取自真實逐字稿樣本（fixtures/worktree-bg/，MANIFEST.md 逐檔記來源；§9.14）：
#     1. Workflow：toolUseResult.status = async_launched 且 taskType = local_workflow（id = taskId）。
#        fallback：tool_result 文字「Workflow launched in background. Task ID: X」。
#     2. 背景 Agent：toolUseResult 沒有 taskType，靠 isAsync = true 加 status = async_launched 加 agentId。
#        fallback：tool_result 文字「Async agent launched successfully ... agentId: X」。
#     3. shell 轉背景：toolUseResult.backgroundTaskId，或 tool_result 文字以 Command 開頭、含
#        「running in background with ID: X」「was moved to the background (ID: X)」。
#   「收尾」：同一個 id 的 task-notification（user 字串訊息／attachment 的 queued_command／queue-operation
#   三種載體，常重複，以 task-id 去重；status 只要不是還在跑的字樣就算收尾，真實樣本只有 completed、failed），
#   或明確的 TaskStop／KillShell。
#   **不用 run_in_background 當判準**：Agent 的 tool_use input 它可能是字串 "false"（§9.14①）；
#   只認「結果行」（toolUseResult／tool_result），不認發射的 tool_use。
#   子代理自己的行（isSidechain = true）不算主迴圈的遺留。
#   通知字樣只在通知載體的開頭才算（tool_result 裡的 Read 輸出、句中引用、助理文字都不算收尾）。
#
# 【無法判定一律 ask（不得摺成沒有遺留）】transcript_path 缺／空／非字串／不存在／是目錄／副檔名不是 jsonl／
# 超過上限／讀取失敗／掃描逾時／含標記但解析不了的行／輸入 JSON 壞掉／hook 自己出例外。理由字串帶 UNDETERMINED 與原因代碼。
# 空 stdin 與非 EnterWorktree 的呼叫靜默放行（無輸出、exit 0）。
#
# 【唯讀】只讀逐字稿；唯一寫入是 GOVLOG（決定紀錄，GOVLOG_DIR 覆寫只認 TEMP 且拒 junction）。
# 離開碼恆 0；stdout 空或單行純 ASCII JSON；stderr 恆空。接縫環境變數：GOVLOG_DIR、
# WORKTREE_BG_MAX_BYTES（逐字稿大小上限，預設 256 MiB）。
#
# 中文字面值一律用單引號字串：5.1 讀無 BOM 檔會把 UTF-8 當 ANSI，單引號字串不會被亂碼的跳脫字元吃掉；
# 本 hook 實際由 pwsh 7 執行（settings 接線），5.1 只在測試比對決定。
# ============================================================
$ErrorActionPreference = 'Stop'

# stdin is read as raw bytes and decoded as UTF-8. [Console]::In decodes with the console input
# code page (950 on zh-TW), which corrupts non-ASCII text and eats backslashes (Bad JSON escape).
# The byte read happens only when stdin is redirected (the real hook case: Claude Code pipes it). When stdin
# is the interactive console, OpenStandardInput().CopyTo() waits for keyboard EOF forever, so it is skipped.
# Console.In is the fallback when stdin is not redirected, the byte read fails, or it yields nothing
# (this also serves in-process callers that inject stdin via [Console]::SetIn, e.g. test-adapter-parity).
function Read-StdinUtf8 {
    $b = $null
    if ([Console]::IsInputRedirected) {
        try {
            $ms = New-Object System.IO.MemoryStream
            [Console]::OpenStandardInput().CopyTo($ms)
            $b = $ms.ToArray()
        } catch { $b = $null }
    }
    if ($null -ne $b -and $b.Length -gt 0) {
        $start = 0
        if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $start = 3 }
        return [System.Text.Encoding]::UTF8.GetString($b, $start, $b.Length - $start).TrimStart([char]0xFEFF)
    }
    try { return [Console]::In.ReadToEnd() } catch { return '' }
}
# Output: stdout/stderr leave as UTF-8 bytes on the raw handles, never through the console code page (at 950 the
# default writer emits Big5: reason text turns into mojibake and a JSON reason can break). Only when redirected (the
# real hook case); an interactive console keeps its default writer. Any failure keeps the default writer.
function Initialize-HookUtf8Output {
    try {
        if ([Console]::IsOutputRedirected) { $w = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), (New-Object System.Text.UTF8Encoding $false)); $w.AutoFlush = $true; [Console]::SetOut($w) }
        if ([Console]::IsErrorRedirected) { $w = New-Object System.IO.StreamWriter([Console]::OpenStandardError(), (New-Object System.Text.UTF8Encoding $false)); $w.AutoFlush = $true; [Console]::SetError($w) }
    } catch { }
}
Initialize-HookUtf8Output
# JSON handed to Claude Code is pure ASCII: every char above 126 becomes a backslash-u escape (no dependence on the console encoding).
function ConvertTo-AsciiJsonText([string]$j) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $j.ToCharArray()) {
        if ([int]$ch -gt 126) { [void]$sb.Append([char]92).Append('u').Append(([int]$ch).ToString('x4')) }
        else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

# GetFullPath().StartsWith(TEMP) 只比字串、不解析 reparse point：逐層檢查既存祖先，任一是 reparse point 即拒。
function Test-NoReparseUnderTemp([string]$full, [string]$tmpRoot) {
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

# outcome 觀測（與其他 hook 同款）。全程 fail-open。
function Write-GovLog([string]$hookName, [string]$decision, [string]$why) {
    try {
        $dir = Join-Path $HOME '.claude\governance-logs'
        if ($env:GOVLOG_DIR) {
            try {
                $c = [IO.Path]::GetFullPath($env:GOVLOG_DIR)
                $tr = [IO.Path]::GetFullPath(([IO.Path]::GetTempPath()))
                if ($c.StartsWith($tr, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-NoReparseUnderTemp $c $tr)) { $dir = $c }
            } catch { }
        }
        if (-not (Test-Path $dir)) { [void][IO.Directory]::CreateDirectory($dir) }
        $f = Join-Path $dir ('decisions-' + (Get-Date -Format 'yyyy-MM') + '.jsonl')
        $line = @{ ts = (Get-Date -Format 'o'); hook = $hookName; decision = $decision; why = $why } | ConvertTo-Json -Compress
        Add-Content -Path $f -Value $line -Encoding utf8
    } catch { }
}

# 清成單行可印字串並截長度（控制字元一律換空白）
function Format-OneLine([string]$s, [int]$max) {
    if ($null -eq $s) { return '' }
    $t = ($s -replace '\p{Cc}', ' ')
    $t = ($t -replace '\s{2,}', ' ').Trim()
    if ($t.Length -gt $max) { $t = $t.Substring(0, $max) }
    return $t
}

# 說明文字會進確認框：入框前遮罩常見金鑰形狀（只是減害）
function Hide-Secrets([string]$s) {
    try {
        $t = $s
        $t = [regex]::Replace($t, '(?i)(token|api[_-]?key|secret|passw(or)?d|authorization)(\s*[=:]\s*)\S+', '$1$3***', 'None', [TimeSpan]::FromSeconds(2))
        $t = [regex]::Replace($t, '(?i)bearer\s+\S+', 'Bearer ***', 'None', [TimeSpan]::FromSeconds(2))
        $t = [regex]::Replace($t, 'sk-[A-Za-z0-9_-]{16,}', 'sk-***', 'None', [TimeSpan]::FromSeconds(2))
        return $t
    } catch { return '(redaction-failed)' }
}

function Write-Ask([string]$reason, [string]$logWhy) {
    $o = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = 'PreToolUse'; permissionDecision = 'ask'; permissionDecisionReason = $reason } }
    [Console]::Out.WriteLine((ConvertTo-AsciiJsonText ($o | ConvertTo-Json -Depth 5 -Compress)))
    Write-GovLog 'guard-worktree-bg' 'ask' $logWhy
}

function Write-AskUndetermined([string]$code) {
    $msg = 'EnterWorktree 前無法判定背景工作狀態（UNDETERMINED {0}）：這次沒有檢查到有沒有未完成的 Workflow／背景 Agent／背景 shell，請自己確認後再允許。' -f $code
    Write-Ask $msg ('undetermined ' + $code)
}

$script:Ord = [StringComparison]::Ordinal
$script:RunningStates = @('running', 'in_progress', 'in-progress', 'started', 'pending', 'queued', 'launched', 'starting')
# 逐行預篩的標記（含任一才值得解析 JSON；不含的行不可能是發射／通知／收尾）。
# 不含角括號：有些序列化會把它跳脫成 u003c，所以通知用不帶角括號的字樣。
$script:Markers = @('async_launched', 'backgroundTaskId', 'running in background with ID', 'moved to the background (ID: ', 'Workflow launched in background', 'Async agent launched', 'task-notification', 'TaskStop', 'KillShell')

function Test-IdText($v) {
    return (($v -is [string]) -and ($v.Length -ge 1) -and ($v.Length -le 64) -and ($v -cmatch '^[A-Za-z0-9_-]+$'))
}

function Add-Launch($launch, [string]$id, [string]$kind, [string]$name) {
    if (-not $launch.Contains($id)) {
        $launch[$id] = [pscustomobject]@{ kind = $kind; name = (Format-OneLine (Hide-Secrets $name) 60) }
    }
}

# tool_result 區塊的文字（content 是字串，或 text 區塊陣列）
function Get-ToolResultTexts($content) {
    $texts = New-Object System.Collections.Generic.List[string]
    if ($content -is [System.Array]) {
        foreach ($blk in $content) {
            if ($blk -is [System.Management.Automation.PSCustomObject] -and "$($blk.type)" -ceq 'tool_result') {
                $c = $blk.content
                if ($c -is [string]) { $texts.Add($c) }
                elseif ($c -is [System.Array]) {
                    $sb = New-Object System.Text.StringBuilder
                    foreach ($t in $c) { if ($t -is [System.Management.Automation.PSCustomObject] -and $t.text -is [string]) { [void]$sb.Append($t.text).Append("`n") } }
                    $texts.Add($sb.ToString())
                }
            }
        }
    }
    return $texts.ToArray()
}

# 通知載體的文字：只收「開頭就是 task-notification」的 user 字串／text 區塊／attachment.prompt／queue-operation.content
function Get-NotificationTexts($o) {
    $cands = New-Object System.Collections.Generic.List[string]
    $type = "$($o.type)"
    if ($type -ceq 'user') {
        $c = $o.message.content
        if ($c -is [string]) { $cands.Add($c) }
        elseif ($c -is [System.Array]) {
            foreach ($blk in $c) { if ($blk -is [System.Management.Automation.PSCustomObject] -and "$($blk.type)" -ceq 'text' -and $blk.text -is [string]) { $cands.Add($blk.text) } }
        }
    }
    elseif ($type -ceq 'attachment') {
        $pr = $o.attachment.prompt
        if ($pr -is [string]) { $cands.Add($pr) }
    }
    elseif ($type -ceq 'queue-operation') {
        if ($o.content -is [string]) { $cands.Add($o.content) }
    }
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($t in $cands) { if ($t.TrimStart().StartsWith('<task-notification>', $script:Ord)) { $keep.Add($t) } }
    return $keep.ToArray()
}

function Invoke-Main {
    $raw = Read-StdinUtf8
    if (-not $raw) { return }
    $data = $null
    try { $data = $raw | ConvertFrom-Json } catch {
        if ($raw.Trim()) { Write-AskUndetermined 'input-unparsable' }
        return
    }
    if ("$($data.tool_name)" -cne 'EnterWorktree') { return }
    $script:IsEnter = $true

    $tp = $data.transcript_path
    if (($tp -isnot [string]) -or [string]::IsNullOrWhiteSpace($tp)) { Write-AskUndetermined 'transcript-path-missing'; return }
    if ($tp -notmatch '(?i)\.jsonl$') { Write-AskUndetermined 'transcript-path-rejected-not-jsonl'; return }
    $exists = $false
    try { $exists = [IO.File]::Exists($tp) } catch { $exists = $false }
    if (-not $exists) { Write-AskUndetermined 'transcript-not-found'; return }

    $maxBytes = 268435456L
    if ($env:WORKTREE_BG_MAX_BYTES) { $mb = 0L; if ([long]::TryParse($env:WORKTREE_BG_MAX_BYTES, [ref]$mb) -and $mb -gt 0) { $maxBytes = $mb } }
    $len = -1L
    try { $len = (New-Object System.IO.FileInfo $tp).Length } catch { Write-AskUndetermined 'transcript-unreadable'; return }
    if ($len -gt $maxBytes) { Write-AskUndetermined 'transcript-too-large'; return }

    $launch = [ordered]@{}
    $closed = @{}
    $unparsable = 0
    $timedOut = $false
    $readFailed = $false
    $fs = $null
    $sr = $null
    try {
        $fs = New-Object System.IO.FileStream($tp, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding $false), $true, 65536)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $n = 0
        while ($true) {
            $line = $sr.ReadLine()
            if ($null -eq $line) { break }
            $n++
            if (($n % 500) -eq 0 -and $sw.ElapsedMilliseconds -gt 20000) { $timedOut = $true; break }
            if ($line.Length -lt 30) { continue }
            $hit = $false
            foreach ($m in $script:Markers) { if ($line.IndexOf($m, $script:Ord) -ge 0) { $hit = $true; break } }
            if (-not $hit) { continue }
            $o = $null
            try { $o = $line | ConvertFrom-Json } catch {
                if ($line.IndexOf('toolUseResult', $script:Ord) -ge 0 -or $line.IndexOf('task-notification', $script:Ord) -ge 0 -or $line.IndexOf('tool_result', $script:Ord) -ge 0) { $unparsable++ }
                continue
            }
            if ($o -isnot [System.Management.Automation.PSCustomObject]) { continue }
            if ($o.isSidechain -eq $true) { continue }
            try {
                $type = "$($o.type)"
                if ($type -ceq 'user') {
                    # 發射：結構化的 toolUseResult
                    $tur = $o.toolUseResult
                    if ($tur -is [System.Management.Automation.PSCustomObject]) {
                        if ("$($tur.status)" -ceq 'async_launched') {
                            if ("$($tur.taskType)" -ceq 'local_workflow' -and (Test-IdText $tur.taskId)) { Add-Launch $launch $tur.taskId 'workflow' "$($tur.workflowName)" }
                            elseif ("$($tur.isAsync)" -eq 'true' -and (Test-IdText $tur.agentId)) { Add-Launch $launch $tur.agentId 'agent' "$($tur.description)" }
                        }
                        if (Test-IdText $tur.backgroundTaskId) { Add-Launch $launch $tur.backgroundTaskId 'shell' '' }
                    }
                    # 發射：tool_result 文字句型（只認文字開頭，Read 輸出與句中引用不算）
                    foreach ($t in (Get-ToolResultTexts $o.message.content)) {
                        $m1 = [regex]::Match($t, '^\s*Command\b[^\r\n]{0,400}?(?:running in background with ID: |was moved to the background \(ID: )([A-Za-z0-9_-]{1,64})')
                        if ($m1.Success) { Add-Launch $launch $m1.Groups[1].Value 'shell' '' }
                        $m2 = [regex]::Match($t, '^\s*Workflow launched in background\. Task ID: ([A-Za-z0-9_-]{1,64})')
                        if ($m2.Success) { Add-Launch $launch $m2.Groups[1].Value 'workflow' '' }
                        $m3 = [regex]::Match($t, '^\s*Async agent launched successfully\.[\s\S]{0,800}?agentId: ([A-Za-z0-9_-]{1,64})')
                        if ($m3.Success) { Add-Launch $launch $m3.Groups[1].Value 'agent' '' }
                    }
                }
                elseif ($type -ceq 'assistant') {
                    # 明確收尾：TaskStop／KillShell
                    $ac = $o.message.content
                    if ($ac -is [System.Array]) {
                        foreach ($blk in $ac) {
                            if ($blk -is [System.Management.Automation.PSCustomObject] -and "$($blk.type)" -ceq 'tool_use' -and (@('TaskStop', 'KillShell') -ccontains "$($blk.name)")) {
                                foreach ($key in @('task_id', 'shell_id', 'bash_id', 'id')) {
                                    $v = $blk.input.$key
                                    if (Test-IdText $v) { $closed[$v] = $true }
                                }
                            }
                        }
                    }
                }
                # 收尾：通知（user 字串／text 區塊／attachment.prompt／queue-operation.content）
                foreach ($nt in (Get-NotificationTexts $o)) {
                    foreach ($chunk in ($nt -split '<task-notification>')) {
                        $mi = [regex]::Match($chunk, '<task-id>([^<]{1,64})</task-id>')
                        if (-not $mi.Success) { continue }
                        $ms = [regex]::Match($chunk, '<status>([^<]{0,32})</status>')
                        $st = ''
                        if ($ms.Success) { $st = $ms.Groups[1].Value.Trim().ToLowerInvariant() }
                        if ($script:RunningStates -notcontains $st) { $closed[$mi.Groups[1].Value.Trim()] = $true }
                    }
                }
            } catch { $unparsable++ }
        }
    } catch { $readFailed = $true }
    finally {
        if ($null -ne $sr) { try { $sr.Dispose() } catch { } }
        if ($null -ne $fs) { try { $fs.Dispose() } catch { } }
    }

    if ($readFailed) { Write-AskUndetermined 'transcript-unreadable'; return }
    if ($timedOut) { Write-AskUndetermined 'transcript-scan-timeout'; return }

    $open = @($launch.Keys | Where-Object { -not $closed.ContainsKey($_) })
    if ($open.Count -eq 0) {
        if ($unparsable -gt 0) { Write-AskUndetermined ('unparsable-lines=' + $unparsable) }
        return
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('EnterWorktree 前提醒：這個 session 的逐字稿顯示還有 {0} 項背景工作沒收到完成通知（Workflow／背景 Agent／背景 shell）：' -f $open.Count))
    $shown = 0
    foreach ($id in $open) {
        if ($shown -ge 8) { break }
        $shown++
        $info = $launch[$id]
        $label = '  - {0} {1}' -f $info.kind, $id
        if ($info.name) { $label += (' ' + [string][char]0xFF08 + $info.name + [string][char]0xFF09) }
        $lines.Add($label)
    }
    if ($open.Count -gt $shown) { $lines.Add(('  - ...還有 {0} 項未列出' -f ($open.Count - $shown))) }
    if ($unparsable -gt 0) { $lines.Add(('UNDETERMINED unparsable-lines={0}：另有 {0} 行含標記但解析不了，清單可能不完整。' -f $unparsable)) }
    $lines.Add('進 worktree（尤其是在同一個 VS Code 視窗開別的資料夾）可能讓它們停止，或收不到結果。建議先等完成通知，或確認它們已不需要。')
    $lines.Add('這只是提醒、不擋：若它們其實早已結束（例如這是 resume 的 session、通知沒進逐字稿），按允許即可。')
    Write-Ask ($lines -join "`n") ('open=' + $open.Count + ' unparsable=' + $unparsable)
}

$script:IsEnter = $false
try { Invoke-Main }
catch {
    # hook 自己出例外：還沒確定是 EnterWorktree 就靜默放行（不是我們該管的呼叫）；確定是了就 ask（fail-visible）。
    if ($script:IsEnter) { try { Write-AskUndetermined 'hook-error' } catch { } }
}
exit 0
