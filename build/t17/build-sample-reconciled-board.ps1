#requires -Version 5.1
<#
.SYNOPSIS
    T-17 · 產生 sample-reconciled-board.html（成品範例，純離線 mock，不連網）。

.DESCRIPTION
    示範對帳三態＋漂移（同一次 render，plans/ 根目錄可用）：
      W-alpha：plans/ 有紀錄、GitHub 側一致 ⇒ 已對帳、無漂移（綠燈）
      W-beta ：plans/ 有紀錄但與 GitHub 側有落差（plans 多列一張 #202，GitHub 側沒有）⇒ 漂移 1 筆（紅燈）
      W-gamma：plans/ 整個查無此 work ⇒ 對帳範圍外（紅燈，驗收①）
    「plans/ 不可用 ⇒ 對帳未執行」（驗收④）是**全域**狀態（見票面§4.3「plans/ 不可用 ⇒ 全部標
    對帳未執行」），與上述「plans/ 可用時的三種逐 work 結果」互斥，故另外產生第二份範例
    `sample-reconciled-board-plans-unavailable.html` 單獨示範，不與前三態混在同一頁（混在一起會誤導
    讀者以為四態可以同時出現在同一次 render 裡）。
#>

$T17SampleDir = $PSScriptRoot
. "$T17SampleDir/reconcile-board.ps1" -T17FunctionsOnly

function New-T17SampleIssue {
    param(
        [int]$Number, [string]$Repo, [string]$Title, [string]$Body = '', [string[]]$Labels = @(),
        [string]$State = 'open', [bool]$HasAssignee = $false, $Milestone = $null
    )
    $issue = [pscustomobject]@{
        Number = $Number; Repo = $Repo; Title = $Title; Body = $Body; Labels = $Labels
        State = $State; UpdatedAtUtc = (Get-Date).ToUniversalTime(); HasAssignee = $HasAssignee; HtmlUrl = "https://x/$Repo/$Number"
    }
    Add-Member -InputObject $issue -NotePropertyName 'Milestone' -NotePropertyValue $Milestone -Force
    return $issue
}

function New-T17SampleAnchorBody {
    param([string]$WorkId, [string]$Repo)
    return "work-id: $WorkId`nprimary-repo: $Repo`nparticipating-repos:`n- $Repo`n`nsample work for T-17 demo"
}

# --- W-alpha：clean ---
$T17AnchorAlpha = New-T17SampleIssue -Number 1 -Repo 'acme/repo-a' -Title 'W-alpha · primary anchor' `
    -Body (New-T17SampleAnchorBody -WorkId 'W-alpha' -Repo 'acme/repo-a') -Labels @('sc:work', 'sc:station-4')
$T17TicketAlpha = New-T17SampleIssue -Number 101 -Repo 'acme/repo-a' -Title 'alpha ticket' -Labels @('sc:ticket') -State 'open'
$T17WorkAlpha = [pscustomobject]@{
    WorkId = 'W-alpha'; AnchorIssue = $T17AnchorAlpha; ParticipatingRepos = @('acme/repo-a')
    Tickets = @($T17TicketAlpha); MilestoneRows = @()
    QueueInfo = [pscustomobject]@{ Exists = $false; Count = $null; ParseError = $null }
}

# --- W-beta：drift（plans 多列 #202，GitHub 側沒有）---
$T17AnchorBeta = New-T17SampleIssue -Number 9 -Repo 'acme/repo-b' -Title 'W-beta · primary anchor' `
    -Body (New-T17SampleAnchorBody -WorkId 'W-beta' -Repo 'acme/repo-b') -Labels @('sc:work', 'sc:station-4')
$T17TicketBeta = New-T17SampleIssue -Number 201 -Repo 'acme/repo-b' -Title 'beta ticket' -Labels @('sc:ticket') -State 'open'
$T17WorkBeta = [pscustomobject]@{
    WorkId = 'W-beta'; AnchorIssue = $T17AnchorBeta; ParticipatingRepos = @('acme/repo-b')
    Tickets = @($T17TicketBeta); MilestoneRows = @()
    QueueInfo = [pscustomobject]@{ Exists = $false; Count = $null; ParseError = $null }
}

# --- W-gamma：out-of-scope（plans/ 沒有 W-gamma.json）---
$T17AnchorGamma = New-T17SampleIssue -Number 20 -Repo 'acme/repo-c' -Title 'W-gamma · primary anchor' `
    -Body (New-T17SampleAnchorBody -WorkId 'W-gamma' -Repo 'acme/repo-c') -Labels @('sc:work', 'sc:station-2')
$T17WorkGamma = [pscustomobject]@{
    WorkId = 'W-gamma'; AnchorIssue = $T17AnchorGamma; ParticipatingRepos = @('acme/repo-c')
    Tickets = @(); MilestoneRows = @()
    QueueInfo = [pscustomobject]@{ Exists = $false; Count = $null; ParseError = $null }
}

$T17SampleSnapshot = [pscustomobject]@{
    NowUtc = (Get-Date).ToUniversalTime(); Ok = $true; FailureDetail = $null
    ResultCountThisRun = 4; TotalCountReported = 4; HitPageCap = $false
    QueryDescription = 'sc:work／sc:ticket, open（T-17 sample fixture）'
    Works = @($T17WorkAlpha, $T17WorkBeta, $T17WorkGamma)
    UnresolvedTicketsCount = 0; DuplicateAnchorNotes = @()
}

$T17OutPath1 = Join-Path $T17SampleDir 'sample-reconciled-board.html'
$T17Result1 = Invoke-ReconciledBoardRender -PlansRoot (Join-Path $T17SampleDir 'plans') `
    -TemplatePath (Join-Path $T17SampleDir '../t16/fleet-board-template.html') `
    -OutputPath $T17OutPath1 -MockSnapshot $T17SampleSnapshot
Write-Host "已產生：$T17OutPath1"

# --- 第二份範例：plans/ 整個不可用（驗收④，全域「對帳未執行」，與上面三態互斥，另頁示範） ---
$T17OutPath2 = Join-Path $T17SampleDir 'sample-reconciled-board-plans-unavailable.html'
$T17Result2 = Invoke-ReconciledBoardRender -PlansRoot (Join-Path $T17SampleDir 'plans-does-not-exist') `
    -TemplatePath (Join-Path $T17SampleDir '../t16/fleet-board-template.html') `
    -OutputPath $T17OutPath2 -MockSnapshot $T17SampleSnapshot
Write-Host "已產生：$T17OutPath2"
