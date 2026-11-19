#!/usr/bin/env pwsh
# ============================================================
# record-bg-leftover.ps1
#   SubagentStop hook (matcher: 空) ＋ Stop hook (matcher: 空) ＋ SessionEnd hook（帶 per-hook timeout）
#   —— runaway-process-prevention 規格 Task 2.2（D-3）：記錄「結束時還留著背景工作」
#
# 【為什麼存在】2026-10 的 python 空轉事故（同形狀 11 次）：子代理把一個卡住的指令被 harness
# 轉進背景後就結束了，背景程序沒人收尾；其中兩件子代理的最終回報還寫了「已自行結束」，
# 而程序實際活了 4 天。訊號（背景工作還在）在 harness 手上，下游沒有任何機械後果。
# 本檔把訊號固化成一行狀態紀錄，讓之後的看門狗／SessionStart 摘要／人都有一手資料可查。
#
# 【設計：安全網不是閘門】
# 永遠 exit 0、永遠不寫 stdout、永遠不阻擋（Stop 的 exit 2 會強迫模型繼續，不能用）。
# 任何一步失敗都 fail-open：寧可少記，也不能擋住主流程。
# 但「少記」不能靜默——判定不了的情形（輸入壞掉、欄位缺又沒有逐字稿、逐字稿讀不到、快照缺或壞）
# 一律寫一行 UNDETERMINED 紀錄（bg-leftovers-undetermined.jsonl，追加式，行數＝計數），
# 不得摺進「沒有遺留」（memory query-failure-is-not-absence）。
#
# 【三路分流（計畫書 2026-11-09 §3 A；2026-11 起）】
# 舊版把主迴圈 Stop 的背景工作也當遺留記，結果主迴圈自己掛的 workflow／監看／shell 全成誤報
# （bg-leftovers.jsonl 約七成是這類）。真正的遺留只有兩種：子代理結束時留下的，與「整個 session
# 結束時還在」的。所以依事件分流：
#   SubagentStop：即時記錄子代理自己留下的背景工作，但忽略 type 恰為 workflow、monitor 的項目
#     （workflow 是父 workflow 自己、monitor 是監看，都不是子代理留下的程序）。shell、subagent
#     （背景 Agent 的 type，§9.2）、agent、缺 type、type 非字串、大小寫變體一律照記（寧可多記）。
#     欄位缺時的逐字稿備援維持原樣。
#   Stop（主迴圈）：**不寫遺留檔**。每回合把非終態背景工作寫成每 session 一個覆寫式快照檔
#     bg-snapshot-<安全化 sid>.json（空陣列也要寫，否則舊快照會讓 SessionEnd 誤報）。
#     欄位缺＝判不了：丟棄該 session 的舊快照（過期快照不得被拿去升級）並寫 UNDETERMINED
#     stop-schema-missing。Stop 不碰逐字稿備援。
#   SessionEnd：只讀該 session 的快照檔，不看 background_tasks 與逐字稿。快照裡非 aux（aux＝type 恰為
#     workflow／monitor）的非終態項目升級成一筆遺留（去重沿用 Get-RecordedIds）。reason 為 clear、
#     resume（大小寫不拘）時背景工作是否存活未知，改寫進「待觀察」檔 bg-leftovers-watch.jsonl，
#     SessionStart 不提醒；其他任何 reason（含未知值、缺 reason）照升級。快照缺／壞＝UNDETERMINED
#     （snapshot-missing／snapshot-unparsable），不寫成「沒有遺留」。快照內文的 session_id 與這次
#     SessionEnd 不同（安全化檔名撞名）＝別人的快照，不升級、也不記 UNDETERMINED（只寫 GovLog）。
#   殘餘：①session 被硬關時 SessionEnd 可能不觸發；②最後一次 Stop 之後才起的背景工作看不到；
#     ③clear／resume 只觀察不提醒；④升級當下主迴圈的 shell 可能已被 harness 結束（退出時 1.5 秒後強制結束），
#     仍屬誤報【是否收整棵程序樹未查】。接線必須帶 per-hook timeout（SessionEnd 預設 1.5 秒會被砍）。
#
# 【判據（SubagentStop）】
# 主判據：hook 輸入的 background_tasks（2026-11-07 實測，claude 2.1.319：SubagentStop 與 Stop
#   輸入都有此欄，元素形如 id／type／status／description／command（Stop 的項目用 cmd 欄）；
#   欄位只列「該層自己」的背景工作，子代理遺留只在 SubagentStop 看得到）。SessionEnd 輸入沒有此欄。
#   欄位存在且是陣列：非終態（status 不是 completed／failed／killed 等）的元素就是遺留；
#   空陣列＝這一層沒有遺留，**不**再去翻逐字稿（避免把已收尾的誤報成遺留）。
# 備援（欄位缺或不是陣列＝schema 缺欄）：讀逐字稿尾段（SubagentStop 讀 agent_transcript_path），
#   找「轉背景」的 tool_result，而同一段尾端沒有同 ID 的通知／TaskStop／TaskOutput 者。
#   三種結構形式（移植自 E1 分析器）：
#     1) 轉背景：「was moved to the background (ID: X)」或「running in background with ID: X」，
#        且該字串前方 350 字元內有 tool_result；
#     2) 通知：task-id 標籤後（12 字元內）接同一個 ID；
#     3) 收尾動作：TaskStop／TaskOutput（含舊名 KillShell／BashOutput）的 input 帶同一個 ID。
#   刻意**不**寫角括號字面值：逐字稿可能把標籤存成跳脫序列，所以標籤只比對 task-id 這個詞，
#   ID 前面不要求詞界。
#   逐字稿檔案不存在或讀不到＝UNDETERMINED，不是「沒有遺留」。
#
# 【輸出通道（誠實登記）】
# 規格原寫「以 additionalContext 對主迴圈注入」。本 repo 在 SubagentStop／Stop 沒有任何
# 輸出 additionalContext 的先例（additionalContext 的先例都是 PreToolUse／PostToolUse／SessionStart），
# 所以本檔只做兩件有先例的事：寫狀態檔、寫 stderr 一行（同 record-security-warning 的 SubagentStop 作法）。
# stderr 是否會到達主迴圈未驗證——注入通道待 M6 在真實 workflow 實測。
#
# 【狀態檔】預設 $HOME\.claude\session-state\bg-leftovers.jsonl（遺留）、bg-leftovers-watch.jsonl（待觀察）、
# bg-snapshot-<sid>.json（每 session 一個覆寫式快照）；BG_LEFTOVER_STATE_DIR 可覆寫，
# 但只在系統暫存目錄之下才採用且路徑上不得有 reparse point（settings 的 env 區塊是隱性不可信輸入）。
# 同一 (session_id, 背景 ID) 在最近 512 KB 內已記過就不重複記。
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# 終態字樣；type 恰為下列字串（區分大小寫、不 trim）的背景工作不算「遺留」
$script:TerminalStates = @('completed', 'complete', 'done', 'finished', 'exited', 'failed', 'error', 'killed', 'stopped', 'cancelled', 'canceled', 'terminated', 'success', 'succeeded')
$script:AuxTypes = @('workflow', 'monitor')

# ──────────────────────────────────────────────────────────────
# 0) 共用小工具（與 record-security-warning.ps1 同款；刻意不 dot-source guard-core，兩層各自獨立降級）
# ──────────────────────────────────────────────────────────────

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

# outcome 觀測。全程 fail-open。
function Write-GovLog([string]$hook, [string]$decision, [string]$why) {
    try {
        $dir = Join-Path $HOME '.claude\governance-logs'
        if ($env:GOVLOG_DIR) {
            try {
                $c = [IO.Path]::GetFullPath($env:GOVLOG_DIR)
                $tr = [IO.Path]::GetFullPath(([IO.Path]::GetTempPath()))
                if ($c.StartsWith($tr, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-NoReparseUnderTemp $c $tr)) { $dir = $c }
            } catch { }
        }
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $f = Join-Path $dir ('decisions-' + (Get-Date -Format 'yyyy-MM') + '.jsonl')
        $line = @{ ts = (Get-Date -Format 'o'); hook = $hook; decision = $decision; why = $why } | ConvertTo-Json -Compress
        Add-Content -Path $f -Value $line -Encoding utf8
    } catch { }
}

function Get-BgStateDir {
    $default = Join-Path $HOME '.claude\session-state'
    if (-not $env:BG_LEFTOVER_STATE_DIR) { return $default }
    try {
        $c = [IO.Path]::GetFullPath($env:BG_LEFTOVER_STATE_DIR)
        $tmp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($c.StartsWith($tmp, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-NoReparseUnderTemp $c $tmp)) { return $c }
        [Console]::Error.WriteLine("[bg-leftover] ignored BG_LEFTOVER_STATE_DIR (not under TEMP or via junction): $env:BG_LEFTOVER_STATE_DIR")
        return $default
    } catch {
        [Console]::Error.WriteLine('[bg-leftover] ignored BG_LEFTOVER_STATE_DIR (unparsable path)')
        return $default
    }
}

# stdin 一律當 UTF-8 讀（理由同 record-security-warning.ps1：5.1 重導向的 Console.In 走 OEM 碼頁，中文會變亂碼）。
# IsInputRedirected 守衛：手動在主控台直接跑時不要等鍵盤 EOF。
function Read-StdinUtf8 {
    try {
        if (-not [Console]::IsInputRedirected) { return '' }
        $sin = [Console]::OpenStandardInput()
        if ($null -eq $sin) { return '' }
        $sr = New-Object System.IO.StreamReader($sin, $script:Utf8NoBom)
        try { return $sr.ReadToEnd().TrimStart([char]0xFEFF) } finally { $sr.Dispose() }
    } catch {
        try { return [Console]::In.ReadToEnd() } catch { return '' }
    }
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

# 帶 timeout 的 regex（禁止巢狀量詞）
function New-Rx([string]$pattern, [bool]$ignoreCase) {
    $opt = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    if ($ignoreCase) { $opt = $opt -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
    return [regex]::new($pattern, $opt, [TimeSpan]::FromSeconds(3))
}

# 中文詞組用碼位組字：.ps1 沒有 BOM，5.1 會把原始檔當 ANSI 讀，中文字面值會靜默失配（實測過的坑）。
function ConvertFrom-CodePoints([int[]]$cps) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($cp in $cps) { [void]$sb.Append([char]$cp) }
    return $sb.ToString()
}

# 清成單行可印字串並截長度（控制字元一律換空白；\p{Cc} 不寫 backslash-u 字面值）
function Format-OneLine([string]$s, [int]$max) {
    if ($null -eq $s) { return '' }
    $t = ($s -replace '\p{Cc}', ' ')
    $t = ($t -replace '\s{2,}', ' ').Trim()
    if ($t.Length -gt $max) { $t = $t.Substring(0, $max) }
    return $t
}

# 命令列可能帶 token：入檔前遮罩常見形狀（只是減害，不是保證）
function Hide-Secrets([string]$s) {
    try {
        $t = $s
        $t = [regex]::Replace($t, '(?i)(token|api[_-]?key|secret|passw(or)?d|authorization)(\s*[=:]\s*)\S+', '$1$3***', 'None', [TimeSpan]::FromSeconds(2))
        $t = [regex]::Replace($t, '(?i)bearer\s+\S+', 'Bearer ***', 'None', [TimeSpan]::FromSeconds(2))
        $t = [regex]::Replace($t, 'sk-[A-Za-z0-9_-]{16,}', 'sk-***', 'None', [TimeSpan]::FromSeconds(2))
        return $t
    } catch { return '(redaction-failed)' }
}

function Get-SafeKey([string]$sid) {
    if ([string]::IsNullOrWhiteSpace($sid)) { return 'no-session' }
    $s = $sid -replace '[^A-Za-z0-9_.-]', '_'
    $s = $s -replace '\.{2,}', '.'
    if ($s.Length -gt 80) { $s = $s.Substring(0, 80) }
    return $s
}

function Add-JsonLine([string]$path, $obj) {
    $line = ($obj | ConvertTo-Json -Depth 6 -Compress)
    for ($i = 0; $i -lt 3; $i++) {
        try { [IO.File]::AppendAllText($path, $line + "`n", $script:Utf8NoBom); return $true }
        catch { Start-Sleep -Milliseconds 60 }
    }
    return $false
}

function Read-Tail([string]$path, [int]$maxBytes) {
    $fs = $null
    try {
        $fs = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $len = $fs.Length
        $start = 0
        if ($len -gt $maxBytes) { $start = $len - $maxBytes }
        [void]$fs.Seek($start, [System.IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] ([int]($len - $start))
        $n = 0
        while ($n -lt $buf.Length) {
            $r = $fs.Read($buf, $n, $buf.Length - $n)
            if ($r -le 0) { break }
            $n += $r
        }
        return $script:Utf8NoBom.GetString($buf, 0, $n)
    } finally { if ($null -ne $fs) { $fs.Dispose() } }
}

# ──────────────────────────────────────────────────────────────
# 1) 狀態檔寫入器
# ──────────────────────────────────────────────────────────────
$script:StateDir = $null
$script:SessionId = ''
$script:AgentId = ''
$script:AgentType = ''
$script:EvtName = ''

function Write-Undetermined([string]$reason) {
    try {
        if (-not (Test-Path -LiteralPath $script:StateDir)) { $null = New-Item -ItemType Directory -Path $script:StateDir -Force }
        $row = [ordered]@{
            ts         = (Get-Date).ToUniversalTime().ToString('o')
            session_id = $script:SessionId
            agent_id   = $script:AgentId
            hook_event = $script:EvtName
            reason     = $reason
        }
        [void](Add-JsonLine (Join-Path $script:StateDir 'bg-leftovers-undetermined.jsonl') $row)
        Write-GovLog 'record-bg-leftover' 'undetermined' ("reason=$reason; event=$($script:EvtName)")
    } catch { }
}

function Get-RecordedIds([string]$file, [string]$sid) {
    $set = @{}
    try {
        if (-not (Test-Path -LiteralPath $file)) { return $set }
        $tail = Read-Tail $file 524288
        $marker = '"session_id":' + (ConvertTo-Json -InputObject $sid -Compress)
        foreach ($ln in ($tail -split "`n")) {
            if ($ln.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) { continue }
            foreach ($m in [regex]::Matches($ln, '"id":"([^"]{1,64})"')) { $set[$m.Groups[1].Value] = $true }
        }
    } catch { }
    return $set
}

# background_tasks 陣列 -> 非終態項目清單。
#   dropAux=$true：type 恰為 workflow／monitor 的字串項目直接略過（SubagentStop 用）。
#   keepAuxFlag=$true：每項多帶 aux 布林（快照用，SessionEnd 據此不升級 workflow／monitor）。
#   Stop 的項目用 cmd 欄、其他事件用 command 欄，兩者都認。type 不是字串（含數字、陣列、物件）一律記成
#   non-string 且不算 aux（寧可多記）。
function ConvertTo-BgTaskList($bt, [bool]$dropAux, [bool]$keepAuxFlag) {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($t in @($bt)) {
        if ($null -eq $t) { continue }
        $id = ''; $rawType = $null; $status = ''; $cmd = ''
        if ($t -is [string]) { $id = $t }
        elseif ($t -is [System.Management.Automation.PSCustomObject]) {
            $id = "$($t.id)"; $rawType = $t.type; $status = "$($t.status)"
            $cmd = "$($t.command)"
            if ([string]::IsNullOrWhiteSpace($cmd)) { $cmd = "$($t.cmd)" }
            if ([string]::IsNullOrWhiteSpace($cmd)) { $cmd = "$($t.description)" }
        }
        else { $id = "$t" }
        $statusL = $status.Trim().ToLowerInvariant()
        if ($script:TerminalStates -contains $statusL) { continue }
        $typeStr = ''
        if ($rawType -is [string]) { $typeStr = $rawType }
        elseif ($null -ne $rawType) { $typeStr = 'non-string' }
        $isAux = ($script:AuxTypes -ccontains $typeStr)
        if ($dropAux -and $isAux) { continue }
        $o = [ordered]@{
            id      = (Format-OneLine $id 64)
            type    = (Format-OneLine $typeStr 32)
            status  = (Format-OneLine $status 32)
            command = (Format-OneLine (Hide-Secrets $cmd) 200)
        }
        if ($keepAuxFlag) { $o['aux'] = [bool]$isAux }
        $list.Add([pscustomobject]$o)
    }
    return $list.ToArray()
}

# ──────────────────────────────────────────────────────────────
# 2) 備援：從逐字稿尾段找「轉背景而無收尾證據」的 ID（只給 SubagentStop 用）
#    回傳 @{ ok=$bool; reason=''; tasks=@(...) }
# ──────────────────────────────────────────────────────────────
function Find-TranscriptLeftovers([string]$tpath, [int]$tailBytes) {
    $res = @{ ok = $false; reason = ''; tasks = @() }
    if ([string]::IsNullOrWhiteSpace($tpath)) { $res.reason = 'transcript-path-missing'; return $res }
    if ($tpath -notmatch '(?i)\.jsonl$') { $res.reason = 'transcript-path-rejected-not-jsonl'; return $res }
    if (-not (Test-Path -LiteralPath $tpath -PathType Leaf)) { $res.reason = 'transcript-not-found'; return $res }
    $text = $null
    try { $text = Read-Tail $tpath $tailBytes } catch { $res.reason = 'transcript-read-failed'; return $res }
    if ($null -eq $text) { $res.reason = 'transcript-read-failed'; return $res }

    $ord = [StringComparison]::Ordinal
    $found = [ordered]@{}   # id -> @{ toolu; pos }
    try {
        foreach ($marker in @('moved to the background (ID: ', 'running in background with ID: ')) {
            $from = 0
            $guard = 0
            while ($guard -lt 2000) {
                $guard++
                $pos = $text.IndexOf($marker, $from, $ord)
                if ($pos -lt 0) { break }
                $from = $pos + $marker.Length
                $e = $from
                while ($e -lt $text.Length -and $e -lt ($from + 17) -and ($text[$e] -match '[A-Za-z0-9]')) { $e++ }
                $idLen = $e - $from
                if ($idLen -lt 6 -or $idLen -gt 16) { continue }
                $id = $text.Substring($from, $idLen)
                $ws = [Math]::Max(0, $pos - 350)
                $before = $text.Substring($ws, $pos - $ws)
                $trPos = $before.LastIndexOf('tool_result', $ord)
                if ($trPos -lt 0) { continue }
                if ($found.Contains($id)) { continue }
                $toolu = ''
                $tm = [regex]::Match($before, '"tool_use_id"\W{1,6}(toolu_[A-Za-z0-9_]+)', 'None', [TimeSpan]::FromSeconds(2))
                if ($tm.Success) { $toolu = $tm.Groups[1].Value }
                $found[$id] = $toolu
            }
        }
    } catch { $res.reason = 'transcript-scan-failed'; return $res }

    $out = New-Object System.Collections.Generic.List[object]
    try {
        $rxClose = @(
            'task[-_]id.{0,12}?{ID}(?![A-Za-z0-9])',
            '(?:TaskStop|TaskOutput|KillShell|BashOutput)\W{1,6}input.{0,250}?(?:task_id|shell_id|bash_id)\W{1,6}{ID}(?![A-Za-z0-9])'
        )
        foreach ($id in @($found.Keys)) {
            $closed = $false
            $from = 0
            $occ = 0
            while ($occ -lt 400 -and -not $closed) {
                $occ++
                $pos = $text.IndexOf($id, $from, $ord)
                if ($pos -lt 0) { break }
                $from = $pos + $id.Length
                $ws = [Math]::Max(0, $pos - 330)
                $we = [Math]::Min($text.Length, $pos + $id.Length + 1)
                $win = $text.Substring($ws, $we - $ws)
                foreach ($tpl in $rxClose) {
                    $pat = $tpl.Replace('{ID}', [regex]::Escape($id))
                    if ((New-Rx $pat $false).IsMatch($win)) { $closed = $true; break }
                }
            }
            if ($closed) { continue }
            # 盡力補指令原文（找 tool_use 紀錄）；補不到就留空
            $cmd = ''
            $toolu = "$($found[$id])"
            if ($toolu) {
                $from = 0
                $occ = 0
                while ($occ -lt 20) {
                    $occ++
                    $pos = $text.IndexOf($toolu, $from, $ord)
                    if ($pos -lt 0) { break }
                    $from = $pos + $toolu.Length
                    $win = $text.Substring($pos, [Math]::Min($text.Length - $pos, 700))
                    $cm = [regex]::Match($win, '"name"\W{1,6}(?:Bash|PowerShell|Monitor)\W{1,6}input\W{1,6}command\W{1,6}((?:[^"\\]|\\.){1,400})', 'None', [TimeSpan]::FromSeconds(2))
                    if ($cm.Success) { $cmd = $cm.Groups[1].Value; break }
                }
            }
            $out.Add([pscustomobject][ordered]@{ id = $id; type = 'shell'; status = 'no-closure-evidence'; command = $cmd })
        }
    } catch { $res.reason = 'transcript-scan-failed'; return $res }

    $res.ok = $true
    $res.tasks = $out.ToArray()
    return $res
}

# ──────────────────────────────────────────────────────────────
# 3) 快照（Stop 寫、SessionEnd 讀）
# ──────────────────────────────────────────────────────────────
function Get-SnapshotPath {
    # 檔名只由安全化後的 sid 組成（Get-SafeKey 只留 [A-Za-z0-9_.-]、壓縮連續點、截 80 字），前綴固定，逃不出狀態目錄
    return (Join-Path $script:StateDir ('bg-snapshot-' + (Get-SafeKey $script:SessionId) + '.json'))
}

function Invoke-StopSnapshot($data) {
    $path = Get-SnapshotPath
    $prop = $data.PSObject.Properties['background_tasks']
    if ($null -eq $prop -or $null -eq $prop.Value -or -not ($prop.Value -is [array])) {
        # 欄位缺＝這一回合判不了：舊快照已過期，不得留給 SessionEnd 拿去升級
        try { if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop } } catch { }
        Write-Undetermined 'stop-schema-missing'
        return
    }
    $tasks = ConvertTo-BgTaskList @($prop.Value) $false $true
    $snap = [ordered]@{
        session_id = $script:SessionId
        ts         = (Get-Date).ToUniversalTime().ToString('o')
        tasks      = @($tasks)
    }
    try {
        if (-not (Test-Path -LiteralPath $script:StateDir)) { $null = New-Item -ItemType Directory -Path $script:StateDir -Force }
        $json = ($snap | ConvertTo-Json -Depth 6 -Compress)
        [IO.File]::WriteAllText($path, $json + "`n", $script:Utf8NoBom)
    } catch { Write-Undetermined 'snapshot-write-failed' }
}

function Invoke-SessionEnd($data) {
    $reason = Format-OneLine "$($data.reason)" 40
    $path = Get-SnapshotPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Undetermined 'snapshot-missing'; return }
    $snap = $null
    try { $snap = ([IO.File]::ReadAllText($path, $script:Utf8NoBom) | ConvertFrom-Json) } catch { Write-Undetermined 'snapshot-unparsable'; return }
    $tprop = $null
    if ($snap -is [System.Management.Automation.PSCustomObject]) { $tprop = $snap.PSObject.Properties['tasks'] }
    if ($null -eq $tprop -or -not ($tprop.Value -is [array])) { Write-Undetermined 'snapshot-unparsable'; return }
    if ("$($snap.session_id)" -ne $script:SessionId) {
        # 別的 session 的快照（安全化檔名撞名）：與本 session 無關，不升級、不算判不了
        Write-GovLog 'record-bg-leftover' 'skip' 'snapshot-session-mismatch'
        return
    }
    $up = New-Object System.Collections.Generic.List[object]
    foreach ($t in @($tprop.Value)) {
        if ($null -eq $t -or $t -isnot [System.Management.Automation.PSCustomObject]) { continue }
        if ($t.aux -eq $true) { continue }
        $up.Add([pscustomobject][ordered]@{
                id      = (Format-OneLine "$($t.id)" 64)
                type    = (Format-OneLine "$($t.type)" 32)
                status  = (Format-OneLine "$($t.status)" 32)
                command = (Format-OneLine (Hide-Secrets "$($t.command)") 200)
            })
    }
    if ($up.Count -eq 0) { return }

    $watchOnly = ($reason -ieq 'clear' -or $reason -ieq 'resume')
    $leaf = if ($watchOnly) { 'bg-leftovers-watch.jsonl' } else { 'bg-leftovers.jsonl' }
    $file = Join-Path $script:StateDir $leaf
    $seen = Get-RecordedIds $file $script:SessionId
    $fresh = @($up.ToArray() | Where-Object { -not $seen.ContainsKey("$($_.id)") })
    if ($fresh.Count -eq 0) { return }
    $row = [ordered]@{
        ts              = (Get-Date).ToUniversalTime().ToString('o')
        session_id      = $script:SessionId
        agent_id        = ''
        agent_type      = ''
        hook_event      = $script:EvtName
        end_reason      = $reason
        tasks           = @($fresh)
        claimedFinished = $false
        source          = 'snapshot'
    }
    if (-not (Add-JsonLine $file $row)) { Write-Undetermined 'state-file-write-failed'; return }
    Write-GovLog 'record-bg-leftover' $(if ($watchOnly) { 'watch' } else { 'record' }) ("event=$($script:EvtName); source=snapshot; reason=$reason; n=$($fresh.Count)")
    if ($watchOnly) { return }
    $ids = (@($fresh | ForEach-Object { $_.id }) -join ',')
    if ($ids.Length -gt 120) { $ids = $ids.Substring(0, 120) }
    [Console]::Error.WriteLine("[bg-leftover] $($fresh.Count) background task(s) were still not finished when the session ended (ids: $ids; last seen at the previous turn's Stop, may already be gone). Query the terminal state (PID via two paths) before relaying any finished claim. 背景工作未收尾，轉述前先做終態查詢。")
}

# ──────────────────────────────────────────────────────────────
# 4) 主流程
# ──────────────────────────────────────────────────────────────
function Invoke-Main {
    $script:StateDir = Get-BgStateDir
    $raw = Read-StdinUtf8
    if ([string]::IsNullOrWhiteSpace($raw)) { Write-Undetermined 'stdin-empty'; return }
    $data = $null
    try { $data = $raw | ConvertFrom-Json } catch { Write-Undetermined 'stdin-unparsable'; return }
    if ($null -eq $data -or $data -isnot [System.Management.Automation.PSCustomObject]) { Write-Undetermined 'stdin-not-object'; return }

    $evt = "$($data.hook_event_name)"
    if ([string]::IsNullOrWhiteSpace($evt)) { $evt = 'unknown' }
    $script:EvtName = (Format-OneLine $evt 40)
    $sidRaw = "$($data.session_id)"
    $script:SessionId = (Format-OneLine $sidRaw 80)
    $script:AgentId = (Format-OneLine "$($data.agent_id)" 80)
    $script:AgentType = (Format-OneLine "$($data.agent_type)" 80)

    # ── 三路分流：SessionEnd 與 Stop 不走下面的即時記錄路徑 ──
    if ($evt -eq 'SessionEnd') { Invoke-SessionEnd $data; return }
    if ($evt -eq 'Stop') { Invoke-StopSnapshot $data; return }

    # ── 以下＝SubagentStop（含 hook_event_name 缺漏的舊行為）──
    # ── last_assistant_message：「已結束／自行結束」類宣稱 ──
    $claimed = $false
    try {
        $lam = ''
        $lamV = $data.last_assistant_message
        if ($lamV -is [string]) { $lam = $lamV }
        elseif ($null -ne $lamV) { try { $lam = ($lamV | ConvertTo-Json -Depth 10 -Compress) } catch { $lam = "$lamV" } }
        if ($lam) {
            $zh = @(
                (ConvertFrom-CodePoints @(0x5DF2, 0x7D50, 0x675F)),
                (ConvertFrom-CodePoints @(0x5DF2, 0x7D93, 0x7D50, 0x675F)),
                (ConvertFrom-CodePoints @(0x81EA, 0x884C, 0x7D50, 0x675F)),
                (ConvertFrom-CodePoints @(0x81EA, 0x52D5, 0x7D50, 0x675F)),
                (ConvertFrom-CodePoints @(0x5DF2, 0x81EA, 0x884C)),
                (ConvertFrom-CodePoints @(0x5DF2, 0x5B8C, 0x6210, 0x4E26, 0x9000, 0x51FA)),
                (ConvertFrom-CodePoints @(0x5DF2, 0x9000, 0x51FA)),
                (ConvertFrom-CodePoints @(0x5DF2, 0x7D42, 0x6B62)),
                (ConvertFrom-CodePoints @(0x5DF2, 0x505C, 0x6B62)),
                (ConvertFrom-CodePoints @(0x6C92, 0x6709, 0x6B98, 0x7559)),
                (ConvertFrom-CodePoints @(0x5DF2, 0x7ED3, 0x675F)),
                (ConvertFrom-CodePoints @(0x81EA, 0x884C, 0x7ED3, 0x675F))
            ) | ForEach-Object { [regex]::Escape($_) }
            $en = 'self[- ]?(?:terminat|exit|finish)|exited on its own|ended on its own|finished on its own|already (?:finished|exited|terminated|ended|stopped)|no (?:leftover|remaining) (?:process|task|job)'
            $rxClaim = New-Rx ($en + '|' + ($zh -join '|')) $true
            $claimed = $rxClaim.IsMatch($lam)
        }
    } catch { $claimed = $false }

    # ── 主判據：background_tasks ──
    $prop = $data.PSObject.Properties['background_tasks']
    $bt = $null
    $schemaOk = $false
    if ($null -ne $prop -and $null -ne $prop.Value -and ($prop.Value -is [array])) { $schemaOk = $true; $bt = @($prop.Value) }

    $tasks = @()
    $source = ''
    if ($schemaOk) {
        $source = 'background_tasks'
        $tasks = ConvertTo-BgTaskList $bt $true $false
    }
    else {
        # ── 備援：逐字稿 ──
        $source = 'transcript'
        $tpath = ''
        if ($evt -eq 'SubagentStop') { $tpath = "$($data.agent_transcript_path)" } else { $tpath = "$($data.transcript_path)" }
        $tail = 8388608
        if ($env:BG_LEFTOVER_TAIL_BYTES) {
            $tb = 0
            if ([int]::TryParse($env:BG_LEFTOVER_TAIL_BYTES, [ref]$tb) -and $tb -ge 4096 -and $tb -le 67108864) { $tail = $tb }
        }
        $fr = Find-TranscriptLeftovers $tpath $tail
        if (-not $fr.ok) { Write-Undetermined ('schema-missing; ' + $fr.reason); return }
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($t in @($fr.tasks)) {
            $cmdText = "$($t.command)"
            $cmdText = $cmdText.Replace('\n', ' ').Replace('\r', ' ').Replace('\t', ' ').Replace('\"', '"')
            $list.Add([pscustomobject][ordered]@{
                    id      = (Format-OneLine "$($t.id)" 64)
                    type    = "$($t.type)"
                    status  = "$($t.status)"
                    command = (Format-OneLine (Hide-Secrets $cmdText) 200)
                })
        }
        $tasks = $list.ToArray()
    }

    if (@($tasks).Count -eq 0) { return }

    # ── 去重：同 session 同 ID 最近已記過就不再記 ──
    if (-not (Test-Path -LiteralPath $script:StateDir)) { $null = New-Item -ItemType Directory -Path $script:StateDir -Force }
    $file = Join-Path $script:StateDir 'bg-leftovers.jsonl'
    $seen = Get-RecordedIds $file $script:SessionId
    $fresh = @($tasks | Where-Object { -not $seen.ContainsKey("$($_.id)") })
    if ($fresh.Count -eq 0) { return }

    $row = [ordered]@{
        ts              = (Get-Date).ToUniversalTime().ToString('o')
        session_id      = $script:SessionId
        agent_id        = $script:AgentId
        agent_type      = $script:AgentType
        hook_event      = $script:EvtName
        tasks           = @($fresh)
        claimedFinished = $claimed
        source          = $source
    }
    if (-not (Add-JsonLine $file $row)) { Write-Undetermined 'state-file-write-failed'; return }

    Write-GovLog 'record-bg-leftover' 'record' ("event=$($script:EvtName); source=$source; n=$($fresh.Count); claimedFinished=$claimed")
    $ids = (@($fresh | ForEach-Object { $_.id }) -join ',')
    if ($ids.Length -gt 120) { $ids = $ids.Substring(0, 120) }
    [Console]::Error.WriteLine("[bg-leftover] $($fresh.Count) background task(s) still not finished at $($script:EvtName) (ids: $ids). Query the terminal state (PID via two paths) before relaying any finished claim. 背景工作未收尾，轉述前先做終態查詢。")
    if ($claimed) {
        [Console]::Error.WriteLine('[bg-leftover] the last message claims the work ended on its own - UNVERIFIED (no terminal-state evidence). 該訊息含已結束類措辭，未經查證。')
    }
}

try { Invoke-Main } catch { try { Write-Undetermined 'hook-internal-error' } catch { } }
exit 0
