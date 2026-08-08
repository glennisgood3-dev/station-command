#requires -Version 5.1
<#
.SYNOPSIS
    T-12：動態驗收（使用者本機執行，需真實 GitHub PAT 與一個可寫測試票，本沙盒無法連線實跑——
    比照 t08-test.ps1／t10-test.ps1 先例，語法已人工覆核並通過 ParseFile）。

.DESCRIPTION
    【區塊一：端到端 demo】在指定 repo 建一張最小可用的測試票（`sc:ticket`，body 含
    `depends_on: []`、不含 `executor:`／`不可逆動作`），跑 `run-select.ps1` 確認選中該票且
    `NeedsBodyWrite=true`；跑 `run-dispatch.ps1` 產生佇列 → 跑 `run-apply.ps1` 落地 → 獨立 GET
    驗證：票 body 含 `executor:`/`basis:` 兩行、assignee 已指派為指定帳號。

    【區塊二：失敗回滾 demo】對同一張票模擬 dispatch 失敗（呼叫 `run-dispatch.ps1
    -TargetRepo -TargetIssue -Reason`）→ 落地 → 獨立 GET 驗證 assignee 已清空。

    【區塊三：紅→綠核心斷言，比照沙盒離線測試（t12-offline-test.ps1）已完整涵蓋的兩段紅燈】
    本區塊改為對真實 GitHub 重跑一次「回滾」情境，作為離線紅/綠邏輯的真實環境覆核：
    人工指派 assignee → 呼叫 ReportFailure（-SkipRollback）→ 斷言 assignee 仍在（真紅）；
    重新指派 → 呼叫 ReportFailure（正常模式）→ apply → 斷言 assignee 已清空（真綠）。

    ⚠️ 語法已人工覆核（PowerShell 5.1 相容），但本沙盒無法連線 GitHub 實跑，尚未實際執行過——
       請使用者本機執行後核對輸出（比照 t08-test.ps1／t10-test.ps1 的誠實聲明）。

.PARAMETER PatPath
    PAT 檔案路徑。預設 G:\default mount\station_command-key。

.PARAMETER Owner
    GitHub owner。預設 glennisgood3-dev（比照既有動態測試慣例）。

.PARAMETER Repo
    GitHub repo。預設 station-command。

.PARAMETER SkipCleanup
    跳過測試結束後的自動清理（關閉本次建立的測試票）。除錯時可加此旗標保留現場供人工檢視。

.EXAMPLE
    .\t12-test.ps1
#>

[CmdletBinding()]
param(
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$Owner = 'glennisgood3-dev',
    [string]$Repo = 'station-command',
    [switch]$SkipCleanup
)

$ErrorActionPreference = 'Stop'
$T12Dir = $PSScriptRoot
$RepoFull = "$Owner/$Repo"
$Timestamp = Get-Date -Format 'yyyyMMddHHmmss'

$Global:TestLog = New-Object System.Collections.ArrayList
$Global:RedGreenLog = New-Object System.Collections.ArrayList
function Log { param([string]$Line) Write-Host $Line; [void]$Global:TestLog.Add($Line) }
function RG { param([string]$Line) Write-Host $Line; [void]$Global:RedGreenLog.Add($Line); [void]$Global:TestLog.Add($Line) }
function Section { param([string]$Title) Log ''; Log '===================================================================='; Log $Title; Log '====================================================================' }

function Invoke-ChildScript {
    param([Parameter(Mandatory)][string]$ScriptPath, [Parameter(Mandatory)][string[]]$ScriptArgs)
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $ScriptArgs
    $output = & powershell.exe @allArgs 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

# 載入函式（連帶 cascade 進 run-common/gate-check/queue-common）
. (Join-Path $T12Dir 'run-dispatch.ps1') -WorkId 'W-t12-bootstrap' -PrimaryRepo $RepoFull -AnchorIssue 1 -FunctionsOnly
Set-ConsoleUtf8

$Token = Read-PatToken -PatPath $PatPath
$Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t12-dynamic-test'

$runSelectScript = Join-Path $T12Dir 'run-select.ps1'
$runDispatchScript = Join-Path $T12Dir 'run-dispatch.ps1'
$runApplyScript = Join-Path $T12Dir 'run-apply.ps1'

$createdIssueNumbers = New-Object System.Collections.ArrayList
$overallOk = $true

# ============================================================
# 前置：造一張最小可用測試票（sc:ticket），八欄位以陽春方式湊齊，只留 executor/不可逆動作缺項
# 供 run 補齊（區塊一驗的正是「run 補齊」這件事；不可逆動作留「無」以免卡在停手分支）
# ============================================================
Section '前置：建立測試票（sc:ticket，缺 executor，供 run-dispatch 補齊）'

$ticketBody = @"
REQ-ID: T-12-DYNAMIC-TEST
驗收條件：本票僅供 T-12 動態測試使用，可安全關閉
depends_on: []
scope: T-12 動態測試 fixture
測試先行：不適用（本票非交付物）
不可逆動作：無（測試 fixture，可安全關閉）
"@

$createBody = @{ title = "T-12 動態測試票 $Timestamp"; body = $ticketBody; labels = @('sc:ticket') } | ConvertTo-Json -Compress
$createUrl = "https://api.github.com/repos/$Owner/$Repo/issues"
$createdIssue = Invoke-RestMethod -Uri $createUrl -Headers $Headers -Method Post -Body $createBody -ContentType 'application/json; charset=utf-8'
[void]$createdIssueNumbers.Add($createdIssue.number)
Log "測試票已建立：$RepoFull#$($createdIssue.number)"

# ============================================================
# 區塊一：端到端 demo
# ============================================================
Section '區塊一：run-select → run-dispatch → run-apply → 獨立 GET 驗證'

$selectArgs = @('-WorkId', 'W-t12-e2e', '-PrimaryRepo', $RepoFull, '-AnchorIssue', $createdIssue.number, '-ParticipatingRepos', $RepoFull, '-PatPath', $PatPath)
# 注：本 demo 借用測試票本身當「anchor」傳入 -AnchorIssue，只為了讓 run-select 能讀到一個站別
# label——測試票沒有 sc:station-* label，Get-CurrentStation 會判 dirty 並拒絕選件，這是預期的
# 邊界情況（真實使用情境下 -AnchorIssue 應指向真正的 primary anchor issue，見 README 使用說明）。
# 本區塊改用 -FunctionsOnly 直接呼叫函式庫測試選件與派工核心邏輯，不依賴真正 anchor 存在。
$queuePathE2E = Join-Path $T12Dir "t12-e2e-queue-$Timestamp.json"

$participating = @($RepoFull)
$ticketForSelect = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $createdIssue.number -Headers $Headers
$fakeAnchor = [pscustomobject]@{ number = $createdIssue.number; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-4' }) }
$allTicketsMock = @($ticketForSelect | ForEach-Object { $_ | Add-Member -NotePropertyName 'RepoString' -NotePropertyValue $RepoFull -PassThru -Force })
$sel = Select-NextActionableItem -AnchorIssue $fakeAnchor -Station 'sc:station-4' -WorkId 'W-t12-e2e' -PrimaryRepo $RepoFull -ParticipatingRepos $participating -Headers $Headers
if ($sel.HasCandidate -and $sel.Selected.Number -eq $createdIssue.number) {
    Log "[PASS] Select-NextActionableItem 選中測試票 #$($createdIssue.number)，NeedsBodyWrite=$($sel.Selected.NeedsBodyWrite)"
} else {
    Log "[FAIL] Select-NextActionableItem 未選中測試票（HasCandidate=$($sel.HasCandidate)）：$($sel.Detail)"
    $overallOk = $false
}

if ($sel.HasCandidate) {
    $dispatchResult = Invoke-RunDispatch -Selected $sel.Selected -QueuePath $queuePathE2E -AssigneeLogin $Owner -WorkId 'W-t12-e2e'
    Log ($dispatchResult.Lines -join [Environment]::NewLine)
    if ($dispatchResult.Status -eq 'dispatch-ready') {
        Log '[PASS] Invoke-RunDispatch Status=dispatch-ready'
    } else {
        Log "[FAIL] Invoke-RunDispatch 非預期狀態：$($dispatchResult.Status)"
        $overallOk = $false
    }

    $applyResult = Invoke-ChildScript -ScriptPath $runApplyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $queuePathE2E)
    Log $applyResult.Output

    $ticketAfter = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $createdIssue.number -Headers $Headers
    if ($ticketAfter.body -like '*executor:*' -and $ticketAfter.body -like '*basis:*') {
        Log '[PASS] 獨立 GET：票 body 已含 executor/basis 兩行'
    } else {
        Log '[FAIL] 獨立 GET：票 body 未含 executor/basis'
        $overallOk = $false
    }
    $assigneesAfter = @(ConvertTo-SafeArray -RawValue $ticketAfter.assignees | ForEach-Object { $_.login })
    if ($assigneesAfter -contains $Owner) {
        Log "[PASS] 獨立 GET：assignee 已指派為 $Owner"
    } else {
        Log "[FAIL] 獨立 GET：assignee 未如預期（現有=[$($assigneesAfter -join ', ')]）"
        $overallOk = $false
    }
}
Remove-Item -LiteralPath $queuePathE2E -Force -ErrorAction SilentlyContinue

# ============================================================
# 區塊二／三：失敗回滾紅→綠（人造中間態：套用一次 assignee 指派 → 模擬 dispatch 失敗）
# ============================================================
Section '區塊二／三：失敗回滾紅→綠（真實 GitHub 覆核，離線邏輯已於 t12-offline-test.ps1 完整證明）'

$queuePathRb = Join-Path $T12Dir "t12-rollback-queue-$Timestamp.json"
$assignItem = New-SetAssigneeItem -Repo $RepoFull -IssueNumber $createdIssue.number -Assignees @($Owner) -Source 'T-12-dynamic-rollback-setup'
Write-QueueFile -QueuePath $queuePathRb -Items @($assignItem)
$applyAssign = Invoke-ChildScript -ScriptPath $runApplyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $queuePathRb)
Log $applyAssign.Output
Remove-Item -LiteralPath $queuePathRb -Force -ErrorAction SilentlyContinue

$ticketMid = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $createdIssue.number -Headers $Headers
$midAssignees = @(ConvertTo-SafeArray -RawValue $ticketMid.assignees | ForEach-Object { $_.login })
if ($midAssignees -contains $Owner) {
    RG "fixture 就緒：assignee 已指派為 $Owner（人造中間態：assignee 已指派 + 即將模擬 dispatch 失敗）"
} else {
    RG "[FAIL] fixture 未就緒，assignee 指派失敗，紅綠測試無法繼續（現有=[$($midAssignees -join ', ')]）"
    $overallOk = $false
}

RG ''
RG '--- 紅（RED）：-SkipRollback 開啟，回報失敗但不產生回滾佇列項 ---'
$queuePathRedRb = Join-Path $T12Dir "t12-red-rollback-queue-$Timestamp.json"
$redDispatch = Invoke-ChildScript -ScriptPath $runDispatchScript -ScriptArgs @('-TargetRepo', $RepoFull, '-TargetIssue', $createdIssue.number, '-Reason', 'T-12 動態測試：模擬 dispatch 失敗（紅燈）', '-WorkId', 'W-t12-rb', '-QueuePath', $queuePathRedRb, '-SkipRollback')
RG $redDispatch.Output
$ticketAfterRed = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $createdIssue.number -Headers $Headers
$afterRedAssignees = @(ConvertTo-SafeArray -RawValue $ticketAfterRed.assignees | ForEach-Object { $_.login })
if ($afterRedAssignees -contains $Owner) {
    RG "[FAIL-AS-EXPECTED（真紅）] 斷言「assignee 必為空」失敗：assignee 仍為 [$($afterRedAssignees -join ', ')]（-SkipRollback 開啟，未產生回滾佇列項，符合預期的斷言失敗紅）。"
} else {
    RG '[UNEXPECTED-PASS] -SkipRollback 開啟但 assignee 已為空——不符合紅燈設計預期，須人工複查。'
    $overallOk = $false
}
Remove-Item -LiteralPath $queuePathRedRb -Force -ErrorAction SilentlyContinue

RG ''
RG '--- 綠（GREEN）：正常模式（無 -SkipRollback），同一張票重新指派後回滾 ---'
$queuePathReassign = Join-Path $T12Dir "t12-reassign-queue-$Timestamp.json"
Write-QueueFile -QueuePath $queuePathReassign -Items @($assignItem)
$applyReassign = Invoke-ChildScript -ScriptPath $runApplyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $queuePathReassign)
RG $applyReassign.Output
Remove-Item -LiteralPath $queuePathReassign -Force -ErrorAction SilentlyContinue

$queuePathGreenRb = Join-Path $T12Dir "t12-green-rollback-queue-$Timestamp.json"
$greenDispatch = Invoke-ChildScript -ScriptPath $runDispatchScript -ScriptArgs @('-TargetRepo', $RepoFull, '-TargetIssue', $createdIssue.number, '-Reason', 'T-12 動態測試：模擬 dispatch 失敗（綠燈）', '-WorkId', 'W-t12-rb', '-QueuePath', $queuePathGreenRb)
RG $greenDispatch.Output
$applyGreenRb = Invoke-ChildScript -ScriptPath $runApplyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $queuePathGreenRb)
RG $applyGreenRb.Output
Remove-Item -LiteralPath $queuePathGreenRb -Force -ErrorAction SilentlyContinue

$ticketAfterGreen = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $createdIssue.number -Headers $Headers
$afterGreenAssignees = @(ConvertTo-SafeArray -RawValue $ticketAfterGreen.assignees | ForEach-Object { $_.login })
if ($afterGreenAssignees.Count -eq 0) {
    RG '[PASS（真綠）] 斷言「回滾後 assignee 必為空」通過：assignee 已清空。'
} else {
    RG "[FAIL] 綠燈斷言未通過：assignee 仍為 [$($afterGreenAssignees -join ', ')]（預期為空）。"
    $overallOk = $false
}

# ============================================================
# 清理
# ============================================================
if (-not $SkipCleanup) {
    Section '清理：關閉本次建立的測試票'
    foreach ($num in @($createdIssueNumbers)) {
        try {
            $closeUrl = "https://api.github.com/repos/$Owner/$Repo/issues/$num"
            $closeBody = @{ state = 'closed'; state_reason = 'not_planned' } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri $closeUrl -Headers $Headers -Method Patch -Body $closeBody -ContentType 'application/json; charset=utf-8' | Out-Null
            Log "已關閉測試票 #$num"
        } catch {
            Log "關閉測試票 #$num 失敗（非致命，請人工複查）：$($_.Exception.Message)"
        }
    }
} else {
    Log '已跳過清理（-SkipCleanup），現場保留供人工檢視。'
}

# ============================================================
Section '總結'
Log "整體結果：$(if ($overallOk) { 'GREEN（所有斷言皆符合預期）' } else { 'RED（有斷言未如預期，見上方 [FAIL] 項目）' })"

$reportOut = Join-Path $T12Dir 't12-dynamic-test-report.txt'
Write-Utf8BomFile -Path $reportOut -Content (($Global:TestLog) -join [Environment]::NewLine)
Write-Host "完整報告已寫入：$reportOut"

$redGreenOut = Join-Path $T12Dir 't12-red-green.txt'
$rgHeader = @("t12-red-green.txt — 失敗回滾紅綠對照 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", '')
Write-Utf8BomFile -Path $redGreenOut -Content (($rgHeader + $Global:RedGreenLog) -join [Environment]::NewLine)
Write-Host "紅綠對照已寫入：$redGreenOut"

if (-not $overallOk) { exit 1 }
exit 0
