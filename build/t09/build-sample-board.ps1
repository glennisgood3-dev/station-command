#requires -Version 5.1
<#
.SYNOPSIS
    T-09 · 產生 sample-board.html——用「本 repo（station-command 自身）真實現況」render 一份成品範例。

.DESCRIPTION
    這不是連真實 GitHub 拉資料（plugin repo 本身依 tickets-draft.md 開頭所述「尚不存在」，站 1
    quiz 都還沒過，自然沒有一個活的 GitHub repo 可供 search）。本檔改用一份手造但**逐票對照
    tickets-draft.md／tickets-loop-draft.md 原文**的 mock SNAPSHOT（工作名、票號、票名、executor
    皆取自原文，不是憑空編造），餵給與離線測試相同的 Build-StationBoardReport 純函式，藉此展示
    render 器接上「本專案自己的 26 張票」時字卡長什麼樣。

    26 張票、11 closed／15 open、目前站別站 4 的判定依據（誠實列出，非隨意指定）：
      closed（11）：T-01／T-04／T-05／T-06／T-07／T-08／T-10／T-11／T-20／T-21／T-22
        —— 皆有 build/txx 交付物與 batch-verify-report.md／batch-verify-2.md／t21-verify-report-*.md
           等驗收證據支持 PASS 或已完成出貨；T-20 依其 depends_on（T-05、T-08 皆已完成）與其
           「不另外依賴 T-10」的自述判定為可結案。
      open（15）：T-02／T-03（batch-verify-report.md 判 FAIL，條目未落檔，須 rework）／
                 T-09（本票，執行中）／T-12／T-13／T-14／T-15a／T-15b／T-16／T-17／T-18／T-19／
                 T-24／T-25／T-26 —— 尚無 build/txx 交付物或明確 PASS 證據。
      站別＝站 4（implement）：全體未關閉票的最小站（§3.2）由未關閉票決定；T-02／T-03 雖已有草稿
        交付物但驗收 FAIL 須回到站 4 修復，其餘 open 票多數尚未開工（站 3 已過，等待 dispatch），
        依「未關閉票的最小站」公式，最小站即為已在動的站 4（T-02／T-03／T-09）。

    T-02／T-03 兩票在此樣本中掛 sc:gate-fail（對應 batch-verify-report.md 的 FAIL 判定），用來展示
    紅燈與「燈號理由具名」；T-09（本票）掛 assignee（正在執行）但不掛任何負面 label；佇列刻意設為
    非空（2 筆）以展示 T-23 併入的「寫入斷點期間不可信」揭露。

.NOTES
    產生指令（本機 Windows PowerShell 5.1 或沙盒 pwsh 皆可）：
        cd build/t09
        pwsh -NoProfile -File build-sample-board.ps1
    （沙盒環境用 /opt/pwsh/pwsh -NoProfile -File build-sample-board.ps1）
    輸出：./sample-board.html（可直接雙擊或拖進瀏覽器開啟，自包不依賴任何外部檔案）。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/render-board.ps1" -FunctionsOnly
Set-ConsoleUtf8

# 佔位 repo（誠實聲明：plugin repo 依 tickets-draft.md 開頭所述尚未建立，此為示意用途，
# 不對應任何真實存在的 GitHub repo）
$Repo = 'station-command-plugin/station-command'
$WorkId = 'W-station-command'
$NowUtc = (Get-Date).ToUniversalTime()

function New-Ticket {
    param([int]$Number, [string]$Id, [string]$Title, [string]$Executor, [string]$State,
          [string[]]$ExtraLabels = @(), [double]$HoursAgo = 2, [bool]$HasAssignee = $false)
    $labels = @('sc:ticket') + $ExtraLabels
    return [pscustomobject]@{
        Number = $Number; Repo = $Repo; Title = "$Id · $Title"
        Body = "work-id: $WorkId`nticket-id: $Id`nexecutor: $Executor`nbasis: 見 tickets-draft.md 原文"
        Labels = $labels; State = $State; UpdatedAtUtc = $NowUtc.AddHours(-1 * $HoursAgo)
        HasAssignee = $HasAssignee; HtmlUrl = "https://github.com/$Repo/issues/$Number"
    }
}

# --- closed（11） ---
$closed = @(
    New-Ticket -Number 101 -Id 'T-01' -Title '建立 plugin repo 與兩本 Log 種子' -Executor 'docs-manager' -State 'closed' -HoursAgo 60
    New-Ticket -Number 104 -Id 'T-04' -Title '舊 fleet-command 仍生效規則盤點' -Executor 'Explore' -State 'closed' -HoursAgo 55
    New-Ticket -Number 105 -Id 'T-05' -Title '仍生效規則搬移落檔（停用前置條件）' -Executor 'docs-manager' -State 'closed' -HoursAgo 50
    New-Ticket -Number 106 -Id 'T-06' -Title 'plugin 骨架與動作白名單宣告' -Executor 'fullstack-developer' -State 'closed' -HoursAgo 48
    New-Ticket -Number 107 -Id 'T-07' -Title 'label scheme 與 anchor／milestone 慣例落地' -Executor 'fullstack-developer' -State 'closed' -HoursAgo 46
    New-Ticket -Number 108 -Id 'T-08' -Title '進線：intake native ＋ gate 初始化路徑' -Executor 'fullstack-developer' -State 'closed' -HoursAgo 40
    New-Ticket -Number 110 -Id 'T-10' -Title 'gate 推進、寫後回驗與歸因復位' -Executor 'fullstack-developer' -State 'closed' -HoursAgo 20
    New-Ticket -Number 111 -Id 'T-11' -Title '路由表與 12 條 smell 基線 asset' -Executor 'docs-manager' -State 'closed' -HoursAgo 44
    New-Ticket -Number 120 -Id 'T-20' -Title '舊 fleet-command 停用' -Executor 'git-manager' -State 'closed' -HoursAgo 18
    New-Ticket -Number 121 -Id 'T-21' -Title '待寫佇列基礎設施' -Executor 'fullstack-developer' -State 'closed' -HoursAgo 22
    New-Ticket -Number 122 -Id 'T-22' -Title '程式碼 patch 落地路徑' -Executor 'fullstack-developer' -State 'closed' -HoursAgo 19
)

# --- open（15） ---
$open = @(
    (New-Ticket -Number 102 -Id 'T-02' -Title '獨立 bot token 可行性實測（翻盤前提）' -Executor 'researcher' -State 'open' `
        -ExtraLabels @('sc:gate-fail') -HoursAgo 30 -HasAssignee $true)
    (New-Ticket -Number 103 -Id 'T-03' -Title 'sub-agent context 隔離實測（SC#6 解除條件）' -Executor 'researcher' -State 'open' `
        -ExtraLabels @('sc:gate-fail') -HoursAgo 28 -HasAssignee $true)
    (New-Ticket -Number 109 -Id 'T-09' -Title '面板最小可用（單 work 字卡＋四種異常狀態）' -Executor 'fullstack-developer' -State 'open' `
        -HoursAgo 0.5 -HasAssignee $true)
    (New-Ticket -Number 112 -Id 'T-12' -Title '派工：選件、executor 寫入、開工訊號與失敗回滾' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 113 -Id 'T-13' -Title '站 3 拆票與七欄位 gate' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 114 -Id 'T-14' -Title '站 4 驗收與 red-proven' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 115 -Id 'T-15a' -Title '站 5 票級雙審、修復復驗與關票' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 116 -Id 'T-15b' -Title 'work 級完成態收尾' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 117 -Id 'T-16' -Title '跨 repo 聚合、work ID 分組、逐 repo 進度與消失偵測' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 118 -Id 'T-17' -Title '對帳三態（範圍外／未對帳／漂移）' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 119 -Id 'T-18' -Title 'legacy 收編：auditor、定站上限站 3、badge 生命週期' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 123 -Id 'T-19' -Title '豁免有牙與 DECISIONS.md 掃描 fail-closed' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 124 -Id 'T-24' -Title 'session 內 loop 主體（選件三判準＋五條停止條件）' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 125 -Id 'T-25' -Title '停因通知與收尾批次摘要' -Executor 'fullstack-developer' -State 'open' -HoursAgo 3)
    (New-Ticket -Number 126 -Id 'T-26' -Title 'CI 階段 spec（收攏全部 deferred-to-CI 條目）' -Executor 'planner' -State 'open' -HoursAgo 3)
)

if ($closed.Count -ne 11) { throw "closed 票數應為 11，實際 $($closed.Count)（生成腳本內部一致性檢查失敗）" }
if ($open.Count -ne 15) { throw "open 票數應為 15，實際 $($open.Count)（生成腳本內部一致性檢查失敗）" }

$allTickets = @($open + $closed)
if ($allTickets.Count -ne 26) { throw "總票數應為 26，實際 $($allTickets.Count)" }

$anchor = [pscustomobject]@{
    Number = 1; Repo = $Repo; Title = "$WorkId · primary anchor"
    Body = @"
work-id: $WorkId
primary-repo: $Repo
participating-repos:
- $Repo

station-command：五站生產線的薄編排層 Cowork plugin。目前 26 張票（11 closed／15 open），
站別站 4（implement）——依「未關閉票的最小站」公式，T-02／T-03 驗收 FAIL 待修復、
T-09（本票）執行中，其餘 open 票多數等待 dispatch。
"@
    Labels = @('sc:work', 'sc:station-4')
    State = 'open'; UpdatedAtUtc = $NowUtc.AddHours(-0.5); HasAssignee = $false
    HtmlUrl = "https://github.com/$Repo/issues/1"
}

$openTicketsInSearch = @($open)  # search 只回 open（§4.1：一次跨 repo issue search 抓 open 的 sc:ticket）

$snapshot = [pscustomobject]@{
    WorkId = $WorkId; PrimaryRepo = $Repo; ParticipatingReposDeclared = @($Repo)
    NowUtc = $NowUtc
    AnchorQuery = [pscustomobject]@{ Ok = $true; Found = $true; FailureDetail = $null; Issue = $anchor }
    TicketsQuery = [pscustomobject]@{
        Ok = $true; FailedRepos = @(); Tickets = $openTicketsInSearch
        ResultCountThisRun = $openTicketsInSearch.Count; TotalCountReported = $openTicketsInSearch.Count; HitPageCap = $false
    }
    MilestoneProgress = @(
        [pscustomobject]@{
            Repo = $Repo; QueryOk = $true; FailureDetail = $null; MilestoneFound = $true; Title = $WorkId
            OpenIssues = $open.Count; ClosedIssues = $closed.Count
            PercentComplete = [math]::Round(($closed.Count / $allTickets.Count) * 100, 0)
        }
    )
    # 待寫佇列刻意設為非空（2 筆）以展示 T-23 併入的「待寫 N 筆」＋「寫入斷點期間不可信」揭露
    Queue = [pscustomobject]@{ Exists = $true; Count = 2; Path = '../t21/queue.json（示意）'; ParseError = $null }
}

$tplPath = Join-Path $PSScriptRoot 'board-template.html'
$tpl = Get-Content -LiteralPath $tplPath -Raw -Encoding UTF8

$report = Build-StationBoardReport -Snapshot $snapshot -TemplateContent $tpl -CacheBaseline $null `
    -NowLocal (Get-Date) -TimeZoneLabel 'UTC+8'

$outPath = Join-Path $PSScriptRoot 'sample-board.html'
$saveResult = Save-StationBoardArtifact -Html $report.Html -OutputPath $outPath
if (-not $saveResult.Ok) { throw "寫入 sample-board.html 失敗：$($saveResult.Detail)" }

Write-Host "sample-board.html 已產生：$outPath" -ForegroundColor Green
Write-Host "`n--- 文字摘要 ---"
Write-Host $report.TextSummary
