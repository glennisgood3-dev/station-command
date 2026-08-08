#requires -Version 5.1
<#
.SYNOPSIS
    T-10：動態驗收（使用者本機執行，需真實 GitHub PAT，本沙盒無法實跑——比照 t08-test.ps1 先例）。

.DESCRIPTION
    【區塊一：端到端 demo】對一個真實 anchor（station-1）跑合法推進（1→2，附齊 override）：
      gate-advance.ps1（產生模式）⇒ apply-queue.ps1 落地 ⇒ gate-advance.ps1 -VerifyAfterApply
      ⇒ 獨立 GET 確認 anchor 恰為 sc:station-2（驗收⑤：單一次完整集合、無中間態）。

    【區塊二：紅→綠——站序不可跳三組（核心斷言，驗收①②）】
      對三個真實 anchor（分別現站 1／2／3）各送出跳站請求（1→3／2→4／3→5）：
        紅：-BypassStationOrderCheck 開啟 ⇒ 斷言「Reason 必須為 station-order-violation」失敗
            （因 bypass 讓站序檢查形同虛設，Reason 落到 checklist-unmet 或其他值）——斷言失敗型紅，
            非檔案缺失／載入失敗。
        綠：不開 bypass ⇒ Reason 正確為 station-order-violation，且獨立 GET 確認 anchor 站別 label
            未變（未曾寫入）。

    ⚠️ 語法已人工覆核（PowerShell 5.1 相容），但本沙盒無法連線 GitHub 實跑，尚未實際執行過——
       請使用者本機執行後核對輸出（比照 t08-test.ps1／t21-dynamic-test.ps1 的誠實聲明）。

.PARAMETER Owner
    GitHub owner。預設 glennisgood3-dev（比照 t08-test.ps1 慣例）。

.PARAMETER Repo
    GitHub repo。預設 station-command。

.PARAMETER SkipCleanup
    跳過測試結束後的自動清理（關閉本次建立的測試 anchor issue）。

.EXAMPLE
    .\t10-test.ps1
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
function Log { param([string]$Line) Write-Host $Line; [void]$Global:TestLog.Add($Line) }
function RG { param([string]$Line) Write-Host $Line; [void]$Global:RedGreenLog.Add($Line); [void]$Global:TestLog.Add($Line) }
function Section { param([string]$Title) Log ""; Log "===================================================================="; Log $Title; Log "====================================================================" }

function Invoke-ChildScript {
    param([Parameter(Mandatory)][string]$ScriptPath, [Parameter(Mandatory)][string[]]$ScriptArgs)
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $ScriptArgs
    $output = & powershell.exe @allArgs 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

# cascade dot-source 載入三檔全部函式（比照 t08-test.ps1 對 intake-native.ps1 的作法）
. (Join-Path $ScriptDir 'gate-reset.ps1') -FunctionsOnly
. (Join-Path $ScriptDir 'gate-advance.ps1') -WorkId 'W-t10-bootstrap' -PrimaryRepo $RepoFull -AnchorIssue 1 -TargetStation 'sc:station-2' -FunctionsOnly
Set-ConsoleUtf8

$Token = Read-PatToken -PatPath $PatPath
$Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t10-dynamic-test'

$applyScript = Join-Path $ScriptDir '..\t21\apply-queue.ps1'
$advanceScript = Join-Path $ScriptDir 'gate-advance.ps1'
if (-not (Test-Path -LiteralPath $applyScript)) { throw "找不到 ../t21/apply-queue.ps1：$applyScript" }

$createdIssueNumbers = New-Object System.Collections.ArrayList
$overallOk = $true

function New-TestAnchor {
    param([string]$Station, [string]$Suffix)
    $queuePath = Join-Path $ScriptDir "t10-setup-queue-$Suffix-$Timestamp.json"
    $createItem = [pscustomobject]@{
        action  = 'create-issue'
        target  = [pscustomobject]@{ repo = $RepoFull }
        payload = [pscustomobject]@{
            title  = "T-10 動態測試 anchor（$Suffix，可安全關閉）- $Timestamp"
            body   = "work-id: W-t10-$Suffix-$Timestamp`nprimary-repo: $RepoFull`nparticipating-repos:`n- $RepoFull`n`nT-10 動態測試用 fixture"
            labels = @('sc:work')
            milestone = $null
        }
        source  = "T-10-dynamic-test-$Suffix"
    }
    Write-QueueFile -QueuePath $queuePath -Items @($createItem)
    $r1 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $queuePath)
    Log $r1.Output
    # 先賦值再包 @()，不可直接 @(函式呼叫)（Get-CurrentIssuesByTitle 內部用逗號運算子保護陣列型別，
    # 見 ../t21/queue-common.ps1 同型註解；本檔 t10-offline-test.ps1 已用 pwsh 7 實測抓到並修正過同類 bug）。
    $allIssues = Get-CurrentIssuesByTitle -Owner $Owner -Repo $Repo -Headers $Headers
    $allIssues = @($allIssues)
    $anchor = $allIssues | Where-Object { $_.title -eq "T-10 動態測試 anchor（$Suffix，可安全關閉）- $Timestamp" } | Select-Object -First 1
    if ($null -eq $anchor) { throw "建立測試 anchor 失敗（$Suffix）" }
    [void]$createdIssueNumbers.Add($anchor.number)

    $labelItem = [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $RepoFull; issue = $anchor.number }
        payload = [pscustomobject]@{ labels = @('sc:work', $Station) }
        source  = "T-10-dynamic-test-$Suffix"
    }
    Write-QueueFile -QueuePath $queuePath -Items @($labelItem)
    $r2 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $queuePath)
    Log $r2.Output
    Remove-Item -LiteralPath $queuePath -Force -ErrorAction SilentlyContinue

    $confirmed = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $anchor.number -Headers $Headers
    return $confirmed
}

# ============================================================
# 區塊一：端到端 demo — 合法推進（1→2）＋ 寫後回驗（含重試設計）
# ============================================================
Section "區塊一：端到端 demo — 合法推進 1→2，單一次完整集合，寫後回驗"

$e2eAnchor = New-TestAnchor -Station 'sc:station-1' -Suffix 'e2e'
Log "e2e anchor 就緒：$RepoFull#$($e2eAnchor.number)，現站=sc:station-1"

$overridesPath = Join-Path $ScriptDir "t10-e2e-overrides-$Timestamp.json"
@{ '1.glossary' = @{ Satisfied = $true; Detail = '動態測試固定通過' }; '1.adr' = @{ Satisfied = $true; Detail = '動態測試固定通過' }; '1.confirm' = @{ Satisfied = $true; Detail = '動態測試固定通過' } } | ConvertTo-Json | Out-File -LiteralPath $overridesPath -Encoding utf8

$e2eQueuePath = Join-Path $ScriptDir "t10-e2e-advance-queue-$Timestamp.json"
$advanceArgs = @('-WorkId', "W-t10-e2e-$Timestamp", '-PrimaryRepo', $RepoFull, '-AnchorIssue', $e2eAnchor.number, '-TargetStation', 'sc:station-2', '-ChecklistOverridesPath', $overridesPath, '-PatPath', $PatPath, '-QueuePath', $e2eQueuePath)
$advanceRun = Invoke-ChildScript -ScriptPath $advanceScript -ScriptArgs $advanceArgs
Log $advanceRun.Output
if ($advanceRun.ExitCode -eq 0) { Log "[PASS] gate-advance 產生模式 exit=0（checklist 全過，已產生佇列項）。" } else { Log "[FAIL] gate-advance 產生模式 exit=$($advanceRun.ExitCode)，預期 0。"; $overallOk = $false }

$applyE2e = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $e2eQueuePath)
Log $applyE2e.Output

$verifyArgs = @('-WorkId', "W-t10-e2e-$Timestamp", '-PrimaryRepo', $RepoFull, '-AnchorIssue', $e2eAnchor.number, '-TargetStation', 'sc:station-2', '-VerifyAfterApply', '-PatPath', $PatPath, '-RetryDelaySeconds', '2')
$verifyRun = Invoke-ChildScript -ScriptPath $advanceScript -ScriptArgs $verifyArgs
Log $verifyRun.Output
if ($verifyRun.ExitCode -eq 0) { Log "[PASS] gate-advance -VerifyAfterApply exit=0（寫後回驗成功）。" } else { Log "[FAIL] gate-advance -VerifyAfterApply exit=$($verifyRun.ExitCode)，預期 0。"; $overallOk = $false }

$e2eFinal = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $e2eAnchor.number -Headers $Headers
$e2eFinalStations = Get-StationLabelsOnIssue -Issue $e2eFinal
$e2eFinalStations = @($e2eFinalStations)
if (($e2eFinalStations.Count -eq 1) -and ($e2eFinalStations[0] -eq 'sc:station-2')) {
    Log "[PASS] 獨立 GET 確認 anchor 恰為 sc:station-2（無中間態，驗收⑤）。"
} else {
    Log "[FAIL] 獨立 GET 站別 label=[$($e2eFinalStations -join ', ')]，預期恰為 [sc:station-2]。"
    $overallOk = $false
}
Remove-Item -LiteralPath $overridesPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $e2eQueuePath -Force -ErrorAction SilentlyContinue

# ============================================================
# 區塊二：紅→綠 — 站序不可跳三組（1→3、2→4、3→5）
# ============================================================
Section "區塊二：紅→綠 — 站序不可跳三組（核心斷言：跨站請求必須拒絕且 label 未變）"

$pairs = @(
    @{ Station = 'sc:station-1'; Target = 'sc:station-3'; Suffix = 'skip1to3' }
    @{ Station = 'sc:station-2'; Target = 'sc:station-4'; Suffix = 'skip2to4' }
    @{ Station = 'sc:station-3'; Target = 'sc:station-5'; Suffix = 'skip3to5' }
)

foreach ($pair in $pairs) {
    RG ""
    RG "--- 組別：$($pair.Station) → $($pair.Target)（跳站） ---"
    $anchor = New-TestAnchor -Station $pair.Station -Suffix $pair.Suffix
    RG "fixture 就緒：$RepoFull#$($anchor.number)，現站=$($pair.Station)"

    RG "紅（RED）：-BypassStationOrderCheck 開啟，強制放行站序檢查"
    $redResult = Invoke-GateCheck -AnchorIssue $anchor -TargetStation $pair.Target -Tickets @() -BypassStationOrderCheck
    RG "實測 Reason=$($redResult.Reason)（bypass 開啟）"
    $redAssertionPass = ($redResult.Reason -eq 'station-order-violation')
    if ($redAssertionPass) {
        RG "[UNEXPECTED-PASS] 斷言「Reason 必須為 station-order-violation」在 bypass 開啟時仍然通過——不符紅燈設計預期，需人工複查。"
        $overallOk = $false
    } else {
        RG "[FAIL-AS-EXPECTED（真紅）] 斷言「跨站請求必須被拒（Reason=station-order-violation）」失敗：實測 Reason='$($redResult.Reason)'（因 -BypassStationOrderCheck 強制放行站序檢查，符合預期的斷言失敗紅，非檔案缺失／載入失敗）。"
    }

    RG "綠（GREEN）：正常模式（無 bypass），同一組 fixture 重跑"
    $greenResult = Invoke-GateCheck -AnchorIssue $anchor -TargetStation $pair.Target -Tickets @()
    RG "實測 Reason=$($greenResult.Reason)　Detail=$($greenResult.Detail)"
    $anchorAfter = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $anchor.number -Headers $Headers
    $stationsAfter = Get-StationLabelsOnIssue -Issue $anchorAfter
    $stationsAfter = @($stationsAfter)
    $labelUnchanged = ($stationsAfter.Count -eq 1) -and ($stationsAfter[0] -eq $pair.Station)
    $greenAssertionPass = ($greenResult.Reason -eq 'station-order-violation') -and (-not $greenResult.OverallPass) -and $labelUnchanged
    if ($greenAssertionPass) {
        RG "[PASS（真綠）] 斷言「跨站請求被拒且 label 未變」通過：Reason=station-order-violation，獨立 GET 確認站別仍為 '$($stationsAfter -join ', ')'。"
    } else {
        RG "[FAIL] 綠燈斷言未通過：Reason=$($greenResult.Reason)，OverallPass=$($greenResult.OverallPass)，獨立 GET 站別=[$($stationsAfter -join ', ')]（預期仍為 $($pair.Station)）。"
        $overallOk = $false
    }
}

# ============================================================
# 清理
# ============================================================
if (-not $SkipCleanup) {
    Section "清理：關閉本次建立的測試 anchor issue"
    $cleanupItems = @()
    foreach ($num in @($createdIssueNumbers)) {
        $cleanupItems += [pscustomobject]@{
            action  = 'close-issue'
            target  = [pscustomobject]@{ repo = $RepoFull; issue = $num }
            payload = [pscustomobject]@{ state = 'closed'; state_reason = 'not_planned' }
            source  = 'T-10-dynamic-test-cleanup'
        }
    }
    if (@($cleanupItems).Count -gt 0) {
        $cleanupQueuePath = Join-Path $ScriptDir "t10-cleanup-queue-$Timestamp.json"
        Write-QueueFile -QueuePath $cleanupQueuePath -Items $cleanupItems
        $cleanupApply = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $cleanupQueuePath)
        Log $cleanupApply.Output
        Remove-Item -LiteralPath $cleanupQueuePath -Force -ErrorAction SilentlyContinue
    }
} else {
    Log "已跳過清理（-SkipCleanup），現場保留供人工檢視。"
}

# ============================================================
# 總結
# ============================================================
Section "總結"
Log "整體結果：$(if ($overallOk) { 'GREEN（所有斷言皆符合預期）' } else { 'RED（有斷言未如預期，見上方 [FAIL] 項目）' })"

$reportOut = Join-Path $ScriptDir 't10-dynamic-test-report.txt'
Write-Utf8BomFile -Path $reportOut -Content (($Global:TestLog) -join [Environment]::NewLine)
Write-Host "完整報告已寫入：$reportOut"

$redGreenOut = Join-Path $ScriptDir 't10-red-green.txt'
$rgHeader = @("t10-red-green.txt — 站序不可跳三組紅綠對照 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "")
Write-Utf8BomFile -Path $redGreenOut -Content (($rgHeader + $Global:RedGreenLog) -join [Environment]::NewLine)
Write-Host "紅綠對照已寫入：$redGreenOut"

if (-not $overallOk) { exit 1 }
exit 0
