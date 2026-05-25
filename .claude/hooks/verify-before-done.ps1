#!/usr/bin/env pwsh
# ============================================================
# verify-before-done.ps1  —  Stop hook（markmap-studio 客製版）
#
# 為什麼客製？
#   工作區範本 verify-before-done.ps1 在 Node 分支跑
#   `npm run lint` / `typecheck` / `test`，但 markmap-studio 的
#   package.json 沒這 3 個 scripts —— 直接套會 false-block。
#
# 本專案的自動化驗證選擇：
#   ✅ prettier --check 排版檢查（與 .prettierignore 配合）
#   ❌ pnpm build (vite build) —— 實測 43 秒，放進 Stop hook 每個 turn
#       結尾 +43s 體感太重；改以「DoD 手動確認項」+ CI 自動 build（push
#       到 main 觸發 .github/workflows/deploy.yml）兜底
#   ❌ 單元測試 —— 本專案目前沒測試框架
#
# 行為：
#   prettier 未裝 → 提醒、exit 0（不誤殺）
#   prettier --check 通過 → exit 0
#   prettier --check 失敗 → exit 2（強制 Claude 繼續修）
# ============================================================
$ErrorActionPreference = 'Continue'

$projectDir = $env:CLAUDE_PROJECT_DIR
if (-not $projectDir) { $projectDir = (Get-Location).Path }

$prettier = Join-Path $projectDir 'node_modules\.bin\prettier.cmd'
if (-not (Test-Path -LiteralPath $prettier)) {
    Write-Host 'verify: prettier 未安裝（請 pnpm install），略過驗證'
    exit 0
}

Write-Host '=== Stop hook (verify-before-done): markmap-studio 客製版 ==='
Write-Host '--- prettier --check . ---'
Push-Location $projectDir
try {
    & $prettier --check . 2>&1 | Out-Host
    $rc = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($rc -ne 0) {
    Write-Host 'verify: prettier --check 失敗，請先 prettier --write 修復再宣告完成。'
    exit 2
}

Write-Host ''
Write-Host '提醒：pnpm build (vite) 沒在 Stop hook 內跑（43s 太重）。'
Write-Host '      改完功能後請手動跑 pnpm build 確認 bundle 仍正常。'
Write-Host '      CI (.github/workflows/deploy.yml) 在 push 到 main 時會自動把關。'
exit 0
