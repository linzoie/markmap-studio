#!/usr/bin/env pwsh
# ============================================================
# guard-write.ps1  —  PreToolUse hook (matcher: Edit|Write|MultiEdit)
#
# S4a（2026-07-11）：保護治理層自身。防「模型自主編輯 hook/settings/agent/
# governance 檔」而**靜默自我繳械**（例如在 guard-bash.ps1 頂端插 exit 0，
# 下個 session 重啟後全線放行）。命中受保護路徑 → ASK（強制使用者確認）。
#
# 受保護：.claude/{hooks,agents}/、任何 settings.json／settings.local.json／
#         managed-settings.json（三種載體同享 permissions/hooks/env 效力，缺一即繞道
#         ——settings.local.json 曾是零確認框自我核准通道，2026-07-31 補），
#         .governance/{project-template,bin,tests}/（執行邏輯與其來源/散佈/測試）。
#   （.governance/{reports,golden-tasks,handoff} 屬文件、頻繁編輯，不保護。）
#
# 誠實邊界（非閉環）：模型仍可 Write 到他處再 `mv` 進 hooks 目錄——但 mv 走
#   guard-bash（PreToolUse Bash）。本 hook 只擋直接 Edit/Write 受保護路徑。
# 解析失敗一律 fail-open（exit 0）。
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'

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
# Input that is non-empty but not valid JSON means this guard cannot judge the call: ask (fail-visible), do not let it through.
function Write-ParseFailureAsk([string]$hookName) {
    $reason = "$hookName could not parse its input (non-empty, not valid JSON), so this tool call was NOT judged by it. Check the call yourself before allowing it."
    $o = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = 'PreToolUse'; permissionDecision = 'ask'; permissionDecisionReason = $reason } }
    [Console]::Out.WriteLine((ConvertTo-AsciiJsonText ($o | ConvertTo-Json -Depth 5 -Compress)))
}
$raw = Read-StdinUtf8
if (-not $raw) { exit 0 }
try { $data = $raw | ConvertFrom-Json } catch { if ($raw.Trim()) { Write-ParseFailureAsk 'guard-write' }; exit 0 }

# Edit/Write/MultiEdit 都用 tool_input.file_path
$fp = $data.tool_input.file_path
if (-not $fp) { exit 0 }

# 反斜線與正斜線都要涵蓋（Windows 上 file_path 為反斜線——這是 S4a 的關鍵）
$protectRx = '[\\/]\.claude[\\/](hooks|agents)[\\/]|[\\/](managed-)?settings(\.local)?\.json$|[\\/]\.governance[\\/](project-template|bin|tests)[\\/]'

# outcome 觀測（2026-07-11）：記 ask 到 governance-logs。fail-open。
#
# 【2026-09-20 補 target 欄】起因：使用者被確認框打斷打字，事後問「我剛剛批准了什麼」
# ——而 log 只有 hook／decision／ts，**答不出來**，只能靠檔案 mtime 反推。
# 守門有動作卻查不到它對什麼動作，等於沒有事後可稽核性。
#
# ⚠️ **這個「記路徑」的決定只適用本檔，不得外推到 guard-secrets／guard-read-secrets**：
#   - 本檔的 target 必定是**受保護治理檔**（.claude/hooks、settings、.governance/{bin,tests,
#     project-template}），依定義不是機密；而且同一個路徑本來就已經印在使用者看到的
#     確認框裡（下方 $reason 的「檔案：$fp」），記進 log 不增加任何暴露面。
#   - guard-secrets.ps1 檔頭明寫「**不記檔名/內容，避免洩密**」，那是刻意的相反決定：
#     它處理的正是機密檔。兩者不可統一（memory: rule-compression-drops-exceptions——
#     把六份 Write-GovLog 重構成一份共用時，最容易靜默丟掉的就是這種但書）。
# 2026-09-22：StartsWith(TEMP) 不解析 reparse point——%TEMP% 內一個 junction 就能把 log 導到 TEMP 外。
# 逐層檢查既存祖先，任一是 reparse point（junction／symlink）即拒（讀不到＝fail-closed）。
function Test-NoReparseUnderTemp([string]$full, [string]$tmpRoot) {
    $stop = $tmpRoot.TrimEnd('\', '/'); $p = $full
    while ($p -and $p.StartsWith($stop, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $p) { try { if ((Get-Item -LiteralPath $p -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false } } catch { return $false } }
        $parent = [IO.Path]::GetDirectoryName($p); if (-not $parent -or $parent -eq $p) { break }; $p = $parent
    }
    return $true
}

function Write-GovLog([string]$hook, [string]$decision, [string]$why, [string]$target = '') {
    try {
        # 2026-07-31：env 重導向限 TEMP（settings 的 env 區塊是隱性不可信輸入，防守門 log 被導走）；2026-09-22 補 junction 解析
        $dir = Join-Path $HOME '.claude\governance-logs'
        if ($env:GOVLOG_DIR) { try { $c = [IO.Path]::GetFullPath($env:GOVLOG_DIR); $tr = [IO.Path]::GetFullPath(([IO.Path]::GetTempPath())); if ($c.StartsWith($tr, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-NoReparseUnderTemp $c $tr)) { $dir = $c } } catch { } }
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $f = Join-Path $dir ('decisions-' + (Get-Date -Format 'yyyy-MM') + '.jsonl')
        $rec = @{ ts = (Get-Date -Format 'o'); hook = $hook; decision = $decision; why = $why }
        # 只在有值時才加欄位：舊紀錄沒有 target，讀取端要能容忍缺欄（別讓新欄位變成必填）
        if (-not [string]::IsNullOrWhiteSpace($target)) { $rec['target'] = $target }
        $line = $rec | ConvertTo-Json -Compress
        Add-Content -Path $f -Value $line -Encoding utf8
    } catch { }
}

# 2026-10-02（webfetch-preapproval spec §2「自我核准的縫」；2026-10-02 修補簡報
# F6）：claude-guard-webfetch 目錄（WebFetch 預放行檔＋既有 session dedup
# state）只准 guard-mcp.ps1 本身與使用者在終端親手執行的
# .governance/bin/preapprove-webfetch.ps1 寫入；Write／Edit／MultiEdit 對該目錄
# 一律 DENY（比下面 S4a 的治理檔保護更嚴格——那組是 ASK，因為使用者可能真的要
# 改治理檔，這裡沒有那個正當情境）。
#
# 正規化後再比對（F6）：小寫化、正斜線化、去 `\\?\`／`//?/` 長路徑前綴、去尾點，
# 讓 `\\?\C:\...\CLAUDE-GUARD-WEBFETCH\x`、大小寫變體、尾點變體都躲不掉——原版
# 只比對原始字面，這些變形未實測過，審查列為待補。
# 邊界只要求「前面」是斜線或字串起點，**不要求後面也接斜線**（能命中目錄本身，
# 或尾點被去除後落在字串結尾的情況）；但後面若有其他字元，仍要求是斜線或字串
# 結尾，避免誤殺單純提到這個詞彙的一般檔名／文件（例如
# notes-about-claude-guard-webfetch-design.md 前後接的是連字號，不是這個目錄
# 底下的檔案）。
# 2026-10-10（termination-guard 階段 1 審查 minor-8）：兩個目錄保護共用同一個正規化。除了原本的長路徑前綴、
# 小寫、正斜線、整串尾點之外，補 Win32 會自己吃掉的三種寫法——**每個**路徑元件的尾點／尾空白
# （`with-child.\x`、`with-child \x`）、`.` 元件（`session-state\.\with-child`）、連續斜線（雙反斜線寫法）。
# 殘餘（明文）：8.3 短名（SESSIO~1）要查磁碟才解得開，這一層不做。
function Get-GuardNormalizedPath([string]$path) {
    $n = $path.ToLowerInvariant()
    $n = $n -replace '^\\\\\?\\', ''
    $n = $n -replace '^//\?/', ''
    $n = $n -replace '\\', '/'
    $n = $n -replace '/+', '/'
    $n = $n -replace '(?<=/)\.(?=/)', ''      # /./ 元件
    $n = $n -replace '/+', '/'
    $n = $n -replace '[. ]+(?=/|$)', ''        # 每個元件的尾點／尾空白（含整串尾端）
    return $n
}
function Test-PathHasWebfetchDir([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    $n = Get-GuardNormalizedPath $path
    return [bool]($n -match '(^|/)claude-guard-webfetch(/|$)')
}
if (Test-PathHasWebfetchDir $fp) {
    Write-GovLog 'guard-write' 'deny' '寫入 WebFetch 預放行檔目錄（claude-guard-webfetch）' "$fp"
    [Console]::Error.WriteLine('[BLOCKED] guard-write 攔截：claude-guard-webfetch 目錄只准使用者親手執行 .governance/bin/preapprove-webfetch.ps1 寫入，Write/Edit/MultiEdit 一律拒絕。')
    [Console]::Error.WriteLine("  檔案：$fp")
    exit 2
}

# 2026-10-10（spec 2026-10-10-termination-guard-redesign.md v0.3 D2 R1）：with-child 登記目錄
# （session-state/with-child）只准 with-child run 或使用者親手 adopt 寫入；Edit/Write/MultiEdit 一律 DENY。
# 攻擊語料 registry-1～6 證實現況零規則（偽造登記＝之後合法 stop 殺掉任意程序）。Bash 殼層寫入由 guard-core R1 擋。
function Test-PathHasWithChildRegistry([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    $n = Get-GuardNormalizedPath $path
    # 雙反斜線寫法（C:\\Users\\…\\session-state\\with-child\\x）正規化後曾是兩個斜線、單一 / 會漏（實測一次）；現由正規化收斂連續斜線
    return [bool]($n -match '(^|/)session-state/with-child(/|$)')
}
if (Test-PathHasWithChildRegistry $fp) {
    Write-GovLog 'guard-write' 'deny' '寫入 with-child 登記目錄（session-state/with-child）' "$fp"
    [Console]::Error.WriteLine('[BLOCKED] guard-write 攔截：with-child 登記目錄只准 with-child run 或使用者親手 adopt 建立，Write/Edit/MultiEdit 一律拒絕（偽造登記＝之後能合法終止任意程序）。')
    [Console]::Error.WriteLine("  檔案：$fp")
    exit 2
}

# 2026-11-18（next-batch-1 C2，計畫書 §3 C2／§9.4）：測試檔上鎖。
# 主迴圈在 RED 測試定稿後用 .governance/bin/test-lock.mjs lock 把測試檔上鎖；子代理（stdin 帶 agent_id／subagent_id，
# 判斷同 guard-bash 的 D5 計數）對上鎖路徑做 Edit／Write／MultiEdit 一律 DENY（沿用上面兩段的 exit 2＋stderr [BLOCKED]＋GovLog deny）。
# 主迴圈（沒有 agent_id）不受限；需要改測試時，子代理把「要改的檔、改什麼、理由」寫進回傳的 testChangeRequests，由主迴圈決定。
# 鎖檔：<鎖目錄>\<session_id>.json（對所有 session 生效的是 _any.json）；鎖目錄預設 $HOME\.claude\session-state\test-locks，
#   TEST_LOCK_STATE_DIR 可覆寫，但只在 %TEMP% 之下且路徑上沒有 junction／symlink 才採用（同 BG_LEFTOVER_STATE_DIR 的接縫），否則忽略。
# 檔案格式 { version:1, session, created, entries:[ { path, real, dir } ] }；path／real 兩種寫法都比對（real＝工具上鎖當下解掉
#   junction／symlink／8.3 的真實路徑），dir=true 代表整個目錄樹。
# 輸入路徑比對前先正規化：去 \\?\ 前綴、/c/ 風格轉 c:/、相對路徑以 stdin 的 cwd 為底、GetFullPath 收斂 .. 與重複斜線，
#   再用同一個 Get-GuardNormalizedPath（小寫、正斜線、元件尾點／尾空白），並另外跟穿 junction／symlink 後的真實路徑比一次。
# 鎖檔壞掉（讀不到、不是合法 JSON、version 不是 1）：對子代理 DENY（fail-visible，不靜默放行）；主迴圈照放行。
# 殘餘（Q-T 已裁定）：Bash／PowerShell 寫檔不經本 hook；8.3 短名靠 GetFullPath 對含 ~ 路徑的內建展開（本機磁碟關閉 8.3，無法實測）。
function Get-TestLockAgentId($d) {
    foreach ($cand in @("$($d.agent_id)", "$($d.subagent_id)")) { if (-not [string]::IsNullOrWhiteSpace($cand)) { return $cand } }
    return ''
}
function Get-TestLockDir {
    $default = Join-Path $HOME '.claude\session-state\test-locks'
    if (-not $env:TEST_LOCK_STATE_DIR) { return $default }
    try {
        $c = [IO.Path]::GetFullPath($env:TEST_LOCK_STATE_DIR); $tr = [IO.Path]::GetFullPath(([IO.Path]::GetTempPath()))
        if ($c.StartsWith($tr, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-NoReparseUnderTemp $c $tr)) { return $c }
    } catch { }
    return $default
}
function Get-TestLockFullPath([string]$p, [string]$cwd) {
    $s = $p
    if ($s -match '^\\\\\?\\UNC\\') { $s = '\\' + $s.Substring(8) }
    elseif ($s.StartsWith('\\?\') -or $s.StartsWith('//?/')) { $s = $s.Substring(4) }
    if ($s -match '^/([A-Za-z])(/|$)') { $s = $Matches[1] + ':' + $s.Substring(2) }
    if (-not [IO.Path]::IsPathRooted($s) -and $cwd -and [IO.Path]::IsPathRooted($cwd)) { return [IO.Path]::GetFullPath($s, $cwd) }
    return [IO.Path]::GetFullPath($s)
}
function Resolve-TestLockReal([string]$full) {
    try {
        $root = [IO.Path]::GetPathRoot($full)
        $cur = $root
        foreach ($part in $full.Substring($root.Length).Split([char[]]@('\', '/'), [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $next = [IO.Path]::Combine($cur, $part)
            if (Test-Path -LiteralPath $next) {
                $item = Get-Item -LiteralPath $next -Force
                if ($item -and $item.LinkType) { $t = $item.ResolveLinkTarget($true); if ($t) { $next = $t.FullName } }
            }
            $cur = $next
        }
        return [IO.Path]::GetFullPath($cur)
    } catch { return $full }
}
function Stop-TestLockBroken([string]$lockFile, [string]$why) {
    Write-GovLog 'guard-write' 'deny' "測試檔鎖的鎖檔無法判定（$why）" "$fp"
    [Console]::Error.WriteLine("[BLOCKED] guard-write 攔截：測試檔鎖的鎖檔讀不到或格式不對（$why：$lockFile），無法判定這個檔案有沒有被上鎖，子代理的寫入一律拒絕（fail-visible）。請停手，把情況寫進回傳的 testChangeRequests／concerns 交主迴圈處理。")
    [Console]::Error.WriteLine("  檔案：$fp")
    exit 2
}
# 2026-11-18（C2 fix-1，審查 B1）：鎖目錄本身受保護。鎖檔只准 test-lock.mjs（node）寫；子代理與主迴圈的 Edit／Write／MultiEdit 一律 DENY。
# 缺口：子代理先 Write 一個空 entries 的鎖檔，下一個 Edit 就能改上鎖檔（解鎖）。比對 $HOME 預設鎖目錄與 TEST_LOCK_STATE_DIR 解析後的鎖目錄，
# 候選路徑：原字串、完整路徑（收斂 .. 與相對路徑）、穿 junction／symlink 後的真實路徑；比對前去掉 NTFS 資料流後綴（::$DATA）。
# 殘餘（Q-T 已裁定）：Bash／PowerShell 直接寫檔或刪鎖檔、或在殼裡跑 test-lock.mjs unlock，仍不經本 hook。
function Test-PathInTestLockDir([string]$path, [string]$cwd) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    $p = $path -replace '::\$[^\\/]*$', ''
    $full = $p
    try { $full = Get-TestLockFullPath $p $cwd } catch { }
    $real = $full
    try { $real = Resolve-TestLockReal $full } catch { }
    $eff = (Get-GuardNormalizedPath (Get-TestLockDir)).TrimEnd('/')
    foreach ($c in @($p, $full, $real)) {
        $n = Get-GuardNormalizedPath $c
        if ($n -match '(^|/)session-state/test-locks(/|$)') { return $true }
        if ($eff -and ($n -eq $eff -or $n.StartsWith($eff + '/'))) { return $true }
    }
    return $false
}
if (Test-PathInTestLockDir "$fp" "$($data.cwd)") {
    Write-GovLog 'guard-write' 'deny' '寫入測試檔鎖目錄（session-state/test-locks）' "$fp"
    [Console]::Error.WriteLine('[BLOCKED] guard-write 攔截：測試檔鎖目錄（session-state/test-locks）只准 .governance/bin/test-lock.mjs 寫入，Write/Edit/MultiEdit 一律拒絕（改寫鎖檔＝自我解鎖）。需要改上鎖的測試時，把要改的檔、改什麼、理由寫進回傳的 testChangeRequests，由主迴圈決定。')
    [Console]::Error.WriteLine("  檔案：$fp")
    exit 2
}

if (Get-TestLockAgentId $data) {
    $tlDir = Get-TestLockDir
    $tlFiles = @()
    if ("$($data.session_id)" -match '^[A-Za-z0-9_-]{1,64}$') { $tlFiles += (Join-Path $tlDir "$($data.session_id).json") }
    $tlFiles += (Join-Path $tlDir '_any.json')
    $tlCands = $null
    foreach ($tlFile in $tlFiles) {
        if (-not (Test-Path -LiteralPath $tlFile -PathType Leaf)) { continue }
        $tlObj = $null
        try { $tlObj = (Get-Content -LiteralPath $tlFile -Raw -Encoding UTF8) | ConvertFrom-Json -ErrorAction Stop } catch { Stop-TestLockBroken $tlFile '不是合法 JSON' }
        if ($null -eq $tlObj -or "$($tlObj.version)" -ne '1' -or $null -eq $tlObj.PSObject.Properties['entries']) { Stop-TestLockBroken $tlFile '缺 version=1 或 entries' }
        if ($null -eq $tlCands) {
            $tlFull = $null
            try { $tlFull = Get-TestLockFullPath "$fp" "$($data.cwd)" } catch { $tlFull = "$fp" }
            $tlCands = @((Get-GuardNormalizedPath $tlFull), (Get-GuardNormalizedPath (Resolve-TestLockReal $tlFull))) | Select-Object -Unique
        }
        foreach ($tlEntry in @($tlObj.entries)) {
            if ($null -eq $tlEntry) { continue }
            $tlForms = @("$($tlEntry.path)", "$($tlEntry.real)") | Where-Object { $_ } | ForEach-Object { (Get-GuardNormalizedPath $_).TrimEnd('/') } | Select-Object -Unique
            foreach ($e in $tlForms) {
                foreach ($c in $tlCands) {
                    if ($c -eq $e -or ($tlEntry.dir -eq $true -and $c.StartsWith($e + '/'))) {
                        Write-GovLog 'guard-write' 'deny' '子代理寫入已上鎖的測試檔（test-lock）' "$fp"
                        [Console]::Error.WriteLine('[BLOCKED] guard-write 攔截：這個檔案已被主迴圈上鎖（測試檔鎖，.governance/bin/test-lock.mjs），子代理不得 Edit／Write／MultiEdit。需要改測試時不要自己改：把要改的檔、改什麼、理由寫進回傳的 testChangeRequests，由主迴圈決定。')
                        [Console]::Error.WriteLine("  檔案：$fp")
                        exit 2
                    }
                }
            }
        }
    }
}

if ($fp -imatch $protectRx) {
    Write-GovLog 'guard-write' 'ask' '寫入受保護治理檔' "$fp"
    $reason = "使用者硬規則「保護治理層自身」：正在寫入治理檔（hook/settings/agent/governance）" +
              "——這會改動安全防線本身，請確認不是被誘導的自我繳械後再放行。檔案：$fp"
    $out = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'ask'
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Depth 5 -Compress
    [Console]::Out.WriteLine((ConvertTo-AsciiJsonText $out))
    exit 0
}
exit 0
