#requires -Version 5.1
<#
.SYNOPSIS
    T-08：動態驗收（使用者本機執行，需真實 GitHub PAT，本沙盒無法實跑——比照 t21-dynamic-test.ps1 先例）。

.DESCRIPTION
    涵蓋兩大區塊：

    【區塊一：端到端 demo】呼叫真正的 intake-native.ps1（子行程，測完整 CLI 參數繫結與檔案輸出），
    走完整條 Stage A（建 anchor）→ apply → Stage B（建 milestone）→ apply → Stage C（gate 五條判準，
    落 sc:station-1）→ apply → 再跑一次確認冪等終態（Stage=Done，不再產生佇列項）。每個 Stage 後
    以獨立 GET 直讀 GitHub 驗證真的落地，並核對 intake-native-report.txt 含 ADR-NP-009 固定字串。

    【區塊二：紅→綠動態測試（核心斷言）】
        斷言：「判準③（work ID 全艦隊唯一）偵測到重複 work-id 時，gate 初始化整體必須拒絕」
        紅：用 -BypassUniquenessGuardForRedTest（刻意強制判準③視為通過）對一組真實構造的重複
            work-id fixture（兩張真實 anchor issue，body 皆宣告同一個 work-id）呼叫
            Test-GateInitCriteria ⇒ 斷言「OverallPass 必須為 false」**真的會失敗**（因為 bypass
            讓它變成 true）——這是斷言失敗的紅，不是檔案缺失或載入失敗的紅。
        綠：不開 bypass、對同一組 fixture 重跑 ⇒ 判準③正確偵測重複、OverallPass=false ⇒ 斷言通過。
    兩段輸出各自印出實測結果，一併存檔 t08-red-green.txt。

    ⚠️ 語法已人工覆核（PowerShell 5.1 相容），但本沙盒無法連線 GitHub 實跑，尚未實際執行過——
       請使用者本機執行後核對輸出（比照 t21-dynamic-test.ps1 的誠實聲明）。

.PARAMETER PatPath
    PAT 檔案路徑。預設 G:\default mount\station_command-key。

.PARAMETER Owner
    GitHub owner。預設 glennisgood3-dev（比照 t21-dynamic-test.ps1 慣例）。

.PARAMETER Repo
    GitHub repo。預設 station-command。

.PARAMETER SkipCleanup
    跳過測試結束後的自動清理（關閉本次建立的測試 anchor issue、刪除測試 milestone）。
    預設不跳過；除錯時可加此旗標保留現場供人工檢視。

.EXAMPLE
    .\t08-test.ps1
#>

[CmdletBinding()]
param(
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$Owner = 'glennisgood3-dev',
    [string]$Repo = 'station-command',
    [switch]$SkipCleanup
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$RepoFull = "$Owner/$Repo"
$Timestamp = Get-Date -Format 'yyyyMMddHHmmss'

$Global:TestLog = New-Object System.Collections.ArrayList
$Global:RedGreenLog = New-Object System.Collections.ArrayList
function Log {
    param([string]$Line)
    Write-Host $Line
    [void]$Global:TestLog.Add($Line)
}
function RG {
    param([string]$Line)
    Write-Host $Line
    [void]$Global:RedGreenLog.Add($Line)
    [void]$Global:TestLog.Add($Line)
}
function Section {
    param([string]$Title)
    Log ""
    Log "===================================================================="
    Log $Title
    Log "===================================================================="
}

# 以獨立子行程呼叫 .ps1，避免其內部 exit 影響本腳本流程（比照 t21-dynamic-test.ps1）
function Invoke-ChildScript {
    param([Parameter(Mandatory)][string]$ScriptPath, [Parameter(Mandatory)][string[]]$ScriptArgs)
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $ScriptArgs
    $output = & powershell.exe @allArgs 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

# 載入函式（本行也會透過 intake-native.ps1 內部的 dot-source，連帶把 queue-common.ps1 的函式
# 一併載入本測試腳本 scope；-FunctionsOnly 只載函式、不執行主流程）
. (Join-Path $ScriptDir 'intake-native.ps1') -WorkId 'W-t08-bootstrap' -PrimaryRepo $RepoFull -ParticipatingRepos @($RepoFull) -FunctionsOnly
Set-ConsoleUtf8

$Token = Read-PatToken -PatPath $PatPath
$Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t08-dynamic-test'

$applyScript = Join-Path $ScriptDir '..\t21\apply-queue.ps1'
$intakeScript = Join-Path $ScriptDir 'intake-native.ps1'
if (-not (Test-Path -LiteralPath $applyScript)) { throw "找不到 ../t21/apply-queue.ps1：$applyScript" }

$createdIssueNumbers = New-Object System.Collections.ArrayList
$createdMilestoneNumbers = New-Object System.Collections.ArrayList
$overallOk = $true

# ============================================================
# 區塊一：端到端 demo（子行程實跑 intake-native.ps1 的完整 CLI 路徑）
# ============================================================
Section "區塊一：端到端 demo — Stage A → apply → Stage B → apply → Stage C → apply → 冪等終態"

$e2eWorkId = "W-t08-e2e-$Timestamp"
$e2eQueuePath = Join-Path $ScriptDir "t08-e2e-queue-$Timestamp.json"

Log "WorkId=$e2eWorkId  PrimaryRepo=$RepoFull  ParticipatingRepos=[$RepoFull]（單一 repo，最簡合法情境：primary repo 本身即參與 repo）"

# --- Run 1：預期 Stage A-pending（exit 2），產生 create-issue 佇列項 ---
$run1Args = @('-WorkId', $e2eWorkId, '-PrimaryRepo', $RepoFull, '-ParticipatingRepos', $RepoFull, '-PatPath', $PatPath, '-QueuePath', $e2eQueuePath)
$run1 = Invoke-ChildScript -ScriptPath $intakeScript -ScriptArgs $run1Args
Log $run1.Output
if ($run1.ExitCode -eq 2) {
    Log "[PASS] Run1 exit code=2（A-pending，符合預期）。"
} else {
    Log "[FAIL] Run1 exit code=$($run1.ExitCode)，預期 2（A-pending）。"
    $overallOk = $false
}

# --- Apply：落地 anchor ---
$apply1 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $e2eQueuePath)
Log $apply1.Output

$anchorAfterA = Find-AnchorByWorkId -Repo $RepoFull -WorkId $e2eWorkId -Headers $Headers
if ($null -ne $anchorAfterA) {
    Log "[PASS] anchor 已落地：$RepoFull#$($anchorAfterA.number)（獨立 GET 驗證）。"
    [void]$createdIssueNumbers.Add($anchorAfterA.number)
} else {
    Log "[FAIL] anchor 未在獨立 GET 中找到，Stage A 落地失敗。"
    $overallOk = $false
}

# --- Run 2：預期 Stage B-pending（exit 2），產生 create-milestone 佇列項 ---
$run2 = Invoke-ChildScript -ScriptPath $intakeScript -ScriptArgs $run1Args
Log $run2.Output
if ($run2.ExitCode -eq 2) {
    Log "[PASS] Run2 exit code=2（B-pending，符合預期）。"
} else {
    Log "[FAIL] Run2 exit code=$($run2.ExitCode)，預期 2（B-pending）。"
    $overallOk = $false
}

# --- Apply：落地 milestone ---
$apply2 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $e2eQueuePath)
Log $apply2.Output

$msAfterB = Find-MilestoneByTitle -Repo $RepoFull -Title $e2eWorkId -Headers $Headers
if ($null -ne $msAfterB) {
    Log "[PASS] milestone 已落地：#$($msAfterB.number)，description='$($msAfterB.description)'（獨立 GET 驗證）。"
    [void]$createdMilestoneNumbers.Add($msAfterB.number)
} else {
    Log "[FAIL] milestone 未在獨立 GET 中找到，Stage B 落地失敗。"
    $overallOk = $false
}

# --- Run 3：預期 Stage C-pass（exit 0），產生 set-labels 佇列項，report 含 ADR-NP-009 固定字串 ---
$run3 = Invoke-ChildScript -ScriptPath $intakeScript -ScriptArgs $run1Args
Log $run3.Output
if ($run3.ExitCode -eq 0) {
    Log "[PASS] Run3 exit code=0（C-pass，符合預期）。"
} else {
    Log "[FAIL] Run3 exit code=$($run3.ExitCode)，預期 0（C-pass）。"
    $overallOk = $false
}

$reportPath = Join-Path $ScriptDir 'intake-native-report.txt'
if (Test-Path -LiteralPath $reportPath) {
    $reportText = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
    if ($reportText -like '*手動階段：無機器歸因，依 ADR-NP-009*') {
        Log "[PASS] intake-native-report.txt 含固定字串「手動階段：無機器歸因，依 ADR-NP-009」（驗收 #17a 對應要求）。"
    } else {
        Log "[FAIL] intake-native-report.txt 未含固定字串「手動階段：無機器歸因，依 ADR-NP-009」。"
        $overallOk = $false
    }
} else {
    Log "[FAIL] 找不到 intake-native-report.txt：$reportPath"
    $overallOk = $false
}

# --- Apply：落地 sc:station-1 ---
$apply3 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $e2eQueuePath)
Log $apply3.Output

$anchorAfterC = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $anchorAfterA.number -Headers $Headers
if ($null -ne $anchorAfterC) {
    $labelsRaw = ConvertTo-SafeArray -RawValue $anchorAfterC.labels
    $labelsRaw = @($labelsRaw)
    $labelNames = $labelsRaw | ForEach-Object { $_.name }
    $labelNames = @($labelNames)
    if ($labelNames -contains 'sc:station-1' -and $labelNames -contains 'sc:work') {
        Log "[PASS] anchor 已落 sc:station-1（且保留 sc:work），獨立 GET 驗證，現有 label=[$($labelNames -join ', ')]。"
    } else {
        Log "[FAIL] anchor 未如預期含 sc:station-1／sc:work，現有 label=[$($labelNames -join ', ')]。"
        $overallOk = $false
    }
} else {
    Log "[FAIL] 無法獨立 GET 到 anchor，Stage C 落地驗證失敗。"
    $overallOk = $false
}

# --- Run 4：冪等終態，預期 Stage=Done（exit 0），不再產生新佇列項 ---
Remove-Item -LiteralPath $e2eQueuePath -Force -ErrorAction SilentlyContinue
'[]' | Out-File -LiteralPath $e2eQueuePath -Encoding utf8 -NoNewline
$run4 = Invoke-ChildScript -ScriptPath $intakeScript -ScriptArgs $run1Args
Log $run4.Output
if ($run4.ExitCode -eq 0 -and $run4.Output -like '*已完成初始化*') {
    Log "[PASS] Run4（重跑於空佇列）exit code=0 且回報已完成初始化（冪等終態，不再產生佇列項）。"
} else {
    Log "[FAIL] Run4 未如預期回報冪等終態；exit=$($run4.ExitCode)。"
    $overallOk = $false
}
$queueAfterRun4 = Read-QueueFile -QueuePath $e2eQueuePath
$queueAfterRun4 = @($queueAfterRun4)
if ($queueAfterRun4.Count -eq 0) {
    Log "[PASS] Run4 後佇列檔仍是空陣列（未因重跑而誤產生新佇列項）。"
} else {
    Log "[FAIL] Run4 後佇列檔非空（Count=$($queueAfterRun4.Count)），冪等性可能有誤。"
    $overallOk = $false
}

# ============================================================
# 區塊二：紅→綠動態測試（核心斷言：判準③偵測重複 work-id 時必須拒絕）
# ============================================================
Section "區塊二：紅→綠 — 判準③（work ID 全艦隊唯一）偵測重複 work-id 時，gate 初始化整體必須拒絕"

$dupWorkId = "W-t08-dup-$Timestamp"
$dupQueuePath = Join-Path $ScriptDir "t08-dup-queue-$Timestamp.json"

# 直接構造兩張「已存在」的 anchor issue（皆宣告同一個 work-id），繞過 intake-native 自身的
# Stage A 去重（那邊找到既有 anchor 就會直接沿用，不會產生第二張）——本測試就是要刻意製造
# 「兩張 anchor 撞同一個 work-id」的異常現況，驗證 gate 判準③抓不抓得到。
function New-RawAnchorQueueItem {
    param([string]$Suffix)
    return [pscustomobject]@{
        action  = 'create-issue'
        target  = [pscustomobject]@{ repo = $RepoFull }
        payload = [pscustomobject]@{
            title  = "$dupWorkId · primary anchor $Suffix"
            body   = "work-id: $dupWorkId`nprimary-repo: $RepoFull`nparticipating-repos:`n- $RepoFull`n`nT-08 紅綠測試用重複 work-id fixture（$Suffix，可安全關閉）"
            labels = @('sc:work')
            milestone = $null
        }
        source  = $dupWorkId
    }
}

$dupItem1 = New-RawAnchorQueueItem -Suffix '(existing)'
$dupItem2 = New-RawAnchorQueueItem -Suffix '(candidate)'
Write-QueueFile -QueuePath $dupQueuePath -Items @($dupItem1, $dupItem2)

$applyDup = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $dupQueuePath)
Log $applyDup.Output

# 讀回兩張 anchor（依標題後綴區分）
$allDupIssues = @(Get-CurrentIssuesByTitle -Owner $Owner -Repo $Repo -Headers $Headers)
$existingAnchor = $allDupIssues | Where-Object { $_.title -eq "$dupWorkId · primary anchor (existing)" } | Select-Object -First 1
$candidateAnchor = $allDupIssues | Where-Object { $_.title -eq "$dupWorkId · primary anchor (candidate)" } | Select-Object -First 1

if ($null -eq $existingAnchor -or $null -eq $candidateAnchor) {
    Log "[FAIL] 重複 work-id fixture 建立失敗（找不到兩張測試 anchor），紅綠測試無法繼續。"
    $overallOk = $false
} else {
    [void]$createdIssueNumbers.Add($existingAnchor.number)
    [void]$createdIssueNumbers.Add($candidateAnchor.number)
    Log "fixture 就緒：existing=$RepoFull#$($existingAnchor.number)，candidate=$RepoFull#$($candidateAnchor.number)，皆宣告 work-id: $dupWorkId"

    # 以 candidate 作為「正在初始化」的那張 anchor，existing 是「艦隊裡已存在的另一張」
    RG ""
    RG "--- 紅（RED）：-BypassUniquenessGuardForRedTest 開啟，強制判準③視為通過 ---"
    $redResult = Test-GateInitCriteria -WorkId $dupWorkId -PrimaryRepo $RepoFull -ParticipatingRepos @($RepoFull) `
        -AnchorIssue $candidateAnchor -FleetRepos @($RepoFull) -Headers $Headers -BypassUniquenessGuardForRedTest
    RG "判準③實測：$($redResult.Criteria['3'].Detail)"
    $redAssertionPass = (-not $redResult.OverallPass)
    if ($redAssertionPass) {
        RG "[UNEXPECTED-PASS] 斷言「OverallPass 必須為 false」在 Bypass 開啟時仍然通過——這不符合紅燈設計預期，須人工複查（理論上 Bypass 應讓它變 true）。"
        $overallOk = $false
    } else {
        RG "[FAIL-AS-EXPECTED（真紅）] 斷言「OverallPass 必須為 false（重複 work-id 須被拒）」失敗：實測 OverallPass=$($redResult.OverallPass)（因 -BypassUniquenessGuardForRedTest 強制判準③視為通過，符合預期的斷言失敗紅，非檔案缺失／載入失敗）。"
    }

    RG ""
    RG "--- 綠（GREEN）：正常模式（無 Bypass），同一組 fixture 重跑 ---"
    $greenResult = Test-GateInitCriteria -WorkId $dupWorkId -PrimaryRepo $RepoFull -ParticipatingRepos @($RepoFull) `
        -AnchorIssue $candidateAnchor -FleetRepos @($RepoFull) -Headers $Headers
    RG "判準③實測：$($greenResult.Criteria['3'].Detail)"
    $greenAssertionPass = (-not $greenResult.OverallPass) -and (-not $greenResult.Criteria['3'].Satisfied)
    if ($greenAssertionPass) {
        RG "[PASS（真綠）] 斷言「OverallPass 必須為 false 且判準③須具名偵測到衝突」通過：實測 OverallPass=$($greenResult.OverallPass)，判準③.Satisfied=$($greenResult.Criteria['3'].Satisfied)。"
    } else {
        RG "[FAIL] 綠燈斷言未通過：OverallPass=$($greenResult.OverallPass)，判準③.Satisfied=$($greenResult.Criteria['3'].Satisfied)（預期兩者皆為 false）。"
        $overallOk = $false
    }
}

# ============================================================
# 清理（預設執行；-SkipCleanup 可保留現場）
# ============================================================
if (-not $SkipCleanup) {
    Section "清理：關閉本次建立的測試 anchor issue（milestone 不刪除，保留最小清理範圍）"
    $cleanupItems = @()
    foreach ($num in @($createdIssueNumbers)) {
        $cleanupItems += [pscustomobject]@{
            action  = 'close-issue'
            target  = [pscustomobject]@{ repo = $RepoFull; issue = $num }
            payload = [pscustomobject]@{ state = 'closed'; state_reason = 'not_planned' }
            source  = 'T-08-dynamic-test-cleanup'
        }
    }
    if (@($cleanupItems).Count -gt 0) {
        $cleanupQueuePath = Join-Path $ScriptDir "t08-cleanup-queue-$Timestamp.json"
        Write-QueueFile -QueuePath $cleanupQueuePath -Items $cleanupItems
        $cleanupApply = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $cleanupQueuePath)
        Log $cleanupApply.Output
        Remove-Item -LiteralPath $cleanupQueuePath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $e2eQueuePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $dupQueuePath -Force -ErrorAction SilentlyContinue
} else {
    Log "已跳過清理（-SkipCleanup），現場保留供人工檢視。"
}

# ============================================================
# 總結與存檔
# ============================================================
Section "總結"
Log "整體結果：$(if ($overallOk) { 'GREEN（所有斷言皆符合預期）' } else { 'RED（有斷言未如預期，見上方 [FAIL] 項目）' })"

$reportOut = Join-Path $ScriptDir 't08-dynamic-test-report.txt'
Write-Utf8BomFile -Path $reportOut -Content (($Global:TestLog) -join [Environment]::NewLine)
Write-Host "完整報告已寫入：$reportOut"

$redGreenOut = Join-Path $ScriptDir 't08-red-green.txt'
$rgHeader = @("t08-red-green.txt — 判準③重複 work-id 紅綠對照 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "")
Write-Utf8BomFile -Path $redGreenOut -Content (($rgHeader + $Global:RedGreenLog) -join [Environment]::NewLine)
Write-Host "紅綠對照已寫入：$redGreenOut"

if (-not $overallOk) { exit 1 }
exit 0
