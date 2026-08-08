#requires -Version 5.1
<#
.SYNOPSIS
    T-16 · sample-fleet-board.html 的產生腳本。

.DESCRIPTION
    純離線（-MockSnapshot），不連網，不呼叫任何真實 GitHub API。展示三個 work 併陳一頁：
      W-alpha    正常在跑，milestone 分散兩個 repo（驗收①的視覺化）
      W-beta     正常在跑，單一 repo
      W-tampered 站別被竄改（雙重 station label），字卡紅燈標「站別來源不明」（驗收⑥的視覺化）
    並附一則「工作消失」橫幅（驗收③的視覺化：模擬 W-vanished 上一輪在 sc:station-3，本輪 anchor 不在）。

.NOTES
    執行：/opt/pwsh/pwsh -NoProfile -File build-sample-fleet-board.ps1
    輸出：sample-fleet-board.html（本目錄）
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$T16SampleDir = $PSScriptRoot
. "$T16SampleDir/aggregate-board.ps1" -T16FunctionsOnly

$T16SampleNow = (Get-Date).ToUniversalTime()

$T16SampleAlphaBody = @"
work-id: W-alpha
primary-repo: acme/checkout-svc
participating-repos:
- acme/checkout-svc
- acme/payments-lib

重構結帳流程以支援分期付款。
"@
$T16SampleAnchorAlpha = [pscustomobject]@{
    Number = 42; Repo = 'acme/checkout-svc'; Title = '結帳流程分期付款支援 · primary anchor'
    Body = $T16SampleAlphaBody; Labels = @('sc:work', 'sc:station-4'); State = 'open'
    UpdatedAtUtc = $T16SampleNow.AddHours(-2); HasAssignee = $false; HtmlUrl = 'https://github.com/acme/checkout-svc/issues/42'
}
$T16SampleMsAlphaA = [pscustomobject]@{ Number = 5; Title = 'W-alpha 分期付款'; Description = 'work-id: W-alpha | primary-anchor: acme/checkout-svc#42'; OpenIssues = 2; ClosedIssues = 6 }
$T16SampleMsAlphaB = [pscustomobject]@{ Number = 3; Title = 'W-alpha 分期付款'; Description = 'work-id: W-alpha | primary-anchor: acme/checkout-svc#42'; OpenIssues = 1; ClosedIssues = 1 }
$T16SampleTicketAlpha1 = [pscustomobject]@{
    Number = 101; Repo = 'acme/checkout-svc'; Title = '拆分期付款 API'; Body = '**executor**：fullstack-developer｜basis：需真跑測試'
    Labels = @('sc:ticket'); State = 'open'; UpdatedAtUtc = $T16SampleNow.AddHours(-1); HasAssignee = $true; HtmlUrl = 'https://github.com/acme/checkout-svc/issues/101'
}
Add-Member -InputObject $T16SampleTicketAlpha1 -NotePropertyName 'Milestone' -NotePropertyValue $T16SampleMsAlphaA -Force
$T16SampleTicketAlpha2 = [pscustomobject]@{
    Number = 55; Repo = 'acme/payments-lib'; Title = '調整分期利率計算模組'; Body = ''
    Labels = @('sc:ticket'); State = 'open'; UpdatedAtUtc = $T16SampleNow.AddHours(-30); HasAssignee = $false; HtmlUrl = 'https://github.com/acme/payments-lib/issues/55'
}
Add-Member -InputObject $T16SampleTicketAlpha2 -NotePropertyName 'Milestone' -NotePropertyValue $T16SampleMsAlphaB -Force

$T16SampleBetaBody = @"
work-id: W-beta
primary-repo: acme/notif-svc
participating-repos:
- acme/notif-svc

新增簡訊通知管道。
"@
$T16SampleAnchorBeta = [pscustomobject]@{
    Number = 7; Repo = 'acme/notif-svc'; Title = '簡訊通知管道 · primary anchor'
    Body = $T16SampleBetaBody; Labels = @('sc:work', 'sc:station-5'); State = 'open'
    UpdatedAtUtc = $T16SampleNow.AddMinutes(-20); HasAssignee = $false; HtmlUrl = 'https://github.com/acme/notif-svc/issues/7'
}
$T16SampleMsBeta = [pscustomobject]@{ Number = 2; Title = 'W-beta 簡訊通知'; Description = 'work-id: W-beta | primary-anchor: acme/notif-svc#7'; OpenIssues = 1; ClosedIssues = 9 }
$T16SampleTicketBeta = [pscustomobject]@{
    Number = 88; Repo = 'acme/notif-svc'; Title = '簡訊供應商 API 整合'; Body = '**executor**：fullstack-developer'
    Labels = @('sc:ticket', 'sc:red-proven'); State = 'open'; UpdatedAtUtc = $T16SampleNow.AddMinutes(-10); HasAssignee = $true; HtmlUrl = 'https://github.com/acme/notif-svc/issues/88'
}
Add-Member -InputObject $T16SampleTicketBeta -NotePropertyName 'Milestone' -NotePropertyValue $T16SampleMsBeta -Force

# W-tampered：站別 label 被竄改（雙重存在），驗收⑥的視覺化
$T16SampleTamperedBody = @"
work-id: W-tampered
primary-repo: acme/legacy-billing
participating-repos:
- acme/legacy-billing

（示範：有人手動加了 sc:station-4 但沒清掉原本的 sc:station-2，字卡應紅燈標「站別來源不明」）
"@
$T16SampleAnchorTampered = [pscustomobject]@{
    Number = 3; Repo = 'acme/legacy-billing'; Title = '帳務對帳修正 · primary anchor'
    Body = $T16SampleTamperedBody; Labels = @('sc:work', 'sc:station-2', 'sc:station-4'); State = 'open'
    UpdatedAtUtc = $T16SampleNow.AddDays(-3); HasAssignee = $false; HtmlUrl = 'https://github.com/acme/legacy-billing/issues/3'
}

$T16QueueInfoNone = [pscustomobject]@{ Exists = $false; Count = $null; ParseError = $null }

function New-FleetMockWorkForSample {
    <# 本檔專用（不與 aggregate-board.ps1 的頂層變數同名，避免 dot-source cascade 疑慮）。 #>
    param([string]$WorkId, $AnchorIssue, [array]$ParticipatingRepos, [array]$Tickets, [array]$MilestoneRows, $QueueInfo)
    return [pscustomobject]@{
        WorkId = $WorkId; AnchorIssue = $AnchorIssue; ParticipatingRepos = $ParticipatingRepos
        Tickets = $Tickets; MilestoneRows = $MilestoneRows; QueueInfo = $QueueInfo
    }
}

$T16SampleWorks = @(
    (New-FleetMockWorkForSample -WorkId 'W-alpha' -AnchorIssue $T16SampleAnchorAlpha `
        -ParticipatingRepos @('acme/checkout-svc', 'acme/payments-lib') `
        -Tickets @($T16SampleTicketAlpha1, $T16SampleTicketAlpha2) `
        -MilestoneRows @(
            [pscustomobject]@{ Repo = 'acme/checkout-svc'; QueryOk = $true; FailureDetail = $null; MilestoneFound = $true; Title = 'W-alpha 分期付款'; OpenIssues = 2; ClosedIssues = 6; PercentComplete = 75 }
            [pscustomobject]@{ Repo = 'acme/payments-lib'; QueryOk = $true; FailureDetail = $null; MilestoneFound = $true; Title = 'W-alpha 分期付款'; OpenIssues = 1; ClosedIssues = 1; PercentComplete = 50 }
        ) -QueueInfo $T16QueueInfoNone),
    (New-FleetMockWorkForSample -WorkId 'W-beta' -AnchorIssue $T16SampleAnchorBeta `
        -ParticipatingRepos @('acme/notif-svc') -Tickets @($T16SampleTicketBeta) `
        -MilestoneRows @(
            [pscustomobject]@{ Repo = 'acme/notif-svc'; QueryOk = $true; FailureDetail = $null; MilestoneFound = $true; Title = 'W-beta 簡訊通知'; OpenIssues = 1; ClosedIssues = 9; PercentComplete = 90 }
        ) -QueueInfo $T16QueueInfoNone),
    (New-FleetMockWorkForSample -WorkId 'W-tampered' -AnchorIssue $T16SampleAnchorTampered `
        -ParticipatingRepos @('acme/legacy-billing') -Tickets @() `
        -MilestoneRows @(
            [pscustomobject]@{ Repo = 'acme/legacy-billing'; QueryOk = $true; FailureDetail = $null; MilestoneFound = $false; Title = $null; OpenIssues = $null; ClosedIssues = $null; PercentComplete = $null }
        ) -QueueInfo $T16QueueInfoNone)
)

$T16SampleSnapshot = [pscustomobject]@{
    NowUtc = $T16SampleNow; Ok = $true; FailureDetail = $null
    ResultCountThisRun = 5; TotalCountReported = 5; HitPageCap = $false
    QueryDescription = '跨 repo：acme/checkout-svc, acme/payments-lib, acme/notif-svc, acme/legacy-billing（示範資料，非真實 repo）'
    Works = $T16SampleWorks
    UnresolvedTicketsCount = 0; DuplicateAnchorNotes = @()
}

# 顯示快取基線：模擬「上一輪還看得到 W-vanished（站 3），本輪找不到它的 anchor」⇒ 觸發驗收③消失偵測
$T16SampleCacheBaseline = [pscustomobject]@{
    lastFullSyncTimeUtc = $T16SampleNow.AddHours(-6).ToString('o')
    lastReconcileTimeUtc = $null
    works = @(
        @{ workId = 'W-alpha'; station = 'sc:station-4'; primaryRepo = 'acme/checkout-svc' }
        @{ workId = 'W-beta'; station = 'sc:station-5'; primaryRepo = 'acme/notif-svc' }
        @{ workId = 'W-tampered'; station = $null; primaryRepo = 'acme/legacy-billing' }
        @{ workId = 'W-vanished'; station = 'sc:station-3'; primaryRepo = 'acme/reporting-svc' }
    )
}

$T16SampleTemplatePath = Join-Path $T16SampleDir 'fleet-board-template.html'
$T16SampleOutputPath = Join-Path $T16SampleDir 'sample-fleet-board.html'
$T16SampleTemplateContent = Get-Content -LiteralPath $T16SampleTemplatePath -Raw -Encoding UTF8

$T16SampleReport = Build-FleetBoardReport -Snapshot $T16SampleSnapshot -TemplateContent $T16SampleTemplateContent `
    -CacheBaseline $T16SampleCacheBaseline -NowLocal (Get-Date) -TimeZoneLabel 'UTC+8'

$T16SampleSaveResult = Save-StationBoardArtifact -Html $T16SampleReport.Html -OutputPath $T16SampleOutputPath
if (-not $T16SampleSaveResult.Ok) {
    throw "範例面板寫入失敗：$($T16SampleSaveResult.Detail)"
}

Write-Host "已產生：$T16SampleOutputPath"
Write-Host ''
Write-Host $T16SampleReport.TextSummary
