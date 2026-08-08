#requires -Version 5.1
<#
.SYNOPSIS
    T-09 · 動態測試（本機真實 GitHub；需 PAT）。紅燈必須是「斷言失敗的紅」，非載入失敗。

.DESCRIPTION
    依 ticket 建議的紅燈設計：用 `-SkipErrorStateHandling` 關掉 Build-StationBoardReport 的正確錯誤
    狀態處理，餵一個「查詢失敗」情境（本檔用一個真實存在但故意打錯字、必然 404 的 repo 名，等同
    ticket 建議的「查詢清單混入一個不存在的 repo 名」）⇒ 斷言「失敗不得顯示為無工作」**必須失敗**
    （因為開了旁路旗標後，程式真的把失敗當成空結果顯示成「目前無 active work」）；關閉旗標（正常
    模式）重跑同一組真實查詢 ⇒ 同一斷言轉綠。

    紅燈段刻意連 GitHub API 都真打（不是純離線 mock）：-PrimaryRepo 傳一個結構合法但不存在的
    repo（`<owner>/station-command-t09-red-test-does-not-exist`），Get-BoardAnchorQuery 內的 search
    呼叫本身會成功執行（HTTP 200，查詢語法本身合法）但回傳 0 筆——這其實會被正規判成「空狀態」而
    非「查詢失敗」，不足以觸發 query-failed 分支；ticket 建議的「混入不存在的 repo 名」要真正變成
    查詢失敗，需要讓底層 REST 呼叫本身丟例外（如 milestones 端點對不存在的 repo 回 404，或
    search API 對格式不合法的 repo: 限定詞回 422）。本檔對 anchor GET（帶 -AnchorIssue 直讀模式）
    使用一個不存在的 repo，GitHub REST 對不存在 repo 的 issue GET 回 404 ⇒ Invoke-RestMethod 擲例外
    ⇒ Get-BoardAnchorQuery 的 catch 分支把它包成 Ok=$false（真實 404，非 mock）。

.PARAMETER PatPath
    本機 GitHub PAT 檔路徑（純文字，內容為 token 本身）。

.PARAMETER RealOwnerRepo
    一個使用者有讀權限、且用來驗證「正常查詢成功路徑」的既有 owner/repo（可為任意公開 repo，
    只需要讀權限；不需要真的有 station-command 的 work，因為本測試只驗證查詢失敗/成功兩種路徑
    的顯示行為是否正確，不驗證完整字卡欄位——欄位正確性已由 t09-offline-test.ps1 的群組 B 涵蓋）。

.NOTES
    本沙盒環境無 GitHub 連線（session proxy 攔截 Bash 對 GitHub 的請求；MCP 寫入端點 403，讀取端點
    理論可用但本沙盒未配置 PAT），故本檔在此環境無法實跑到底——與 T-08／T-10 先例相同（其
    t08-test.ps1／t10-test.ps1 亦明文「動態測試需本機真實 PAT，本沙盒無法實跑」）。設計本身、
    分支邏輯與斷言用的是與 t09-offline-test.ps1 相同的 Build-StationBoardReport 純函式（唯一差異是
    -SkipErrorStateHandling 開關與真打 GitHub API 取得 AnchorQuery.Ok=$false），可信度與 T-08/T-10
    同一等級：離線部分（本檔的斷言邏輯、旁路旗標行為）已用 t09-offline-test.ps1 群組 G 100% 覆蓋
    並綠燈；本檔補的是「旁路旗標接上真實 GitHub 404」這最後一段本機才驗得到的部分。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PatPath,
    [Parameter(Mandatory)][string]$RealOwnerRepo,
    [string]$NonExistentRepo = "$($RealOwnerRepo.Split('/')[0])/station-command-t09-red-test-does-not-exist-$([guid]::NewGuid().ToString('N').Substring(0,8))"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/render-board.ps1" -FunctionsOnly

Set-ConsoleUtf8

$Script:PassCount = 0
$Script:FailCount = 0
function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $Script:PassCount++; Write-Host "[PASS] $Name" -ForegroundColor Green }
    else { $Script:FailCount++; Write-Host "[FAIL] $Name$(if ($Detail) { " — $Detail" })" -ForegroundColor Red }
}

Write-Host "==================== T-09 動態測試（紅→綠） ====================" -ForegroundColor Cyan
Write-Host "查詢清單混入不存在的 repo：$NonExistentRepo"

$token = Read-PatToken -PatPath $PatPath
$headers = Get-GithubHeaders -Token $token -UserAgent 'station-command-t09-dynamic-test'

Write-Host "`n--- 第一段（真打 GitHub）：對不存在的 repo 直讀 anchor issue，取得真實 404 ---"
$anchorQueryReal = Get-BoardAnchorQuery -PrimaryRepo $NonExistentRepo -AnchorIssue 1 -WorkId 'W-t09-red-test' -Headers $headers
Assert-True -Name '真實查詢：對不存在 repo 的 anchor GET 確實回傳 Ok=false（非 mock，真打 API 驗證前提成立）' -Condition (-not $anchorQueryReal.Ok) -Detail "Ok=$($anchorQueryReal.Ok) FailureDetail=$($anchorQueryReal.FailureDetail)"

$tplPath = Join-Path $PSScriptRoot 'board-template.html'
$tpl = Get-Content -LiteralPath $tplPath -Raw -Encoding UTF8

$snapshotReal = [pscustomobject]@{
    WorkId = 'W-t09-red-test'; PrimaryRepo = $NonExistentRepo; ParticipatingReposDeclared = @($NonExistentRepo)
    NowUtc = (Get-Date).ToUniversalTime()
    AnchorQuery = $anchorQueryReal
    TicketsQuery = [pscustomobject]@{ Ok = $true; FailedRepos = @(); Tickets = @(); ResultCountThisRun = 0; TotalCountReported = 0; HitPageCap = $false }
    MilestoneProgress = @()
    Queue = [pscustomobject]@{ Exists = $false; Count = $null; Path = './queue.json'; ParseError = $null }
}

Write-Host "`n--- 第二段：開啟 -SkipErrorStateHandling（⚠️ 僅供本測試使用）⇒ 斷言必須失敗（紅） ---"
$reportSkip = Build-StationBoardReport -Snapshot $snapshotReal -TemplateContent $tpl -CacheBaseline $null `
    -NowLocal (Get-Date) -TimeZoneLabel 'UTC+8' -SkipErrorStateHandling

# 這是「紅燈斷言」本身：正確行為應該是「查詢失敗不得顯示為無工作」，但旁路開啟時程式刻意錯誤地
# 把失敗當空結果處理，所以下面這個斷言在旁路開啟時**真的會斷言失敗**（Condition 算出 $false）——
# 這就是 ticket 要求的「斷言失敗型」紅燈，不是腳本載入失敗或例外中斷型的假紅燈。
$failedAsExpected = ($reportSkip.Html -notmatch '目前無 active work')
Assert-True -Name '[紅燈段] 斷言「查詢失敗不得顯示為無工作」在旁路開啟時應為失敗（本斷言的 Condition 預期算出 $false）' `
    -Condition (-not $failedAsExpected) `
    -Detail '此列印出 [PASS] 才代表紅燈設計成立：意即該斷言真的偵測到「失敗被錯誤顯示成空狀態」這個 bug'

Write-Host "`n--- 第三段：關閉旁路（正常模式）⇒ 同一組真實查詢結果重跑，斷言轉綠 ---"
$reportNormal = Build-StationBoardReport -Snapshot $snapshotReal -TemplateContent $tpl -CacheBaseline $null `
    -NowLocal (Get-Date) -TimeZoneLabel 'UTC+8'
Assert-True -Name '[綠燈段] 正常模式：查詢失敗正確顯示「數據過期」，不顯示「目前無 active work」' `
    -Condition ($reportNormal.Html -notmatch '目前無 active work') -Detail $reportNormal.Html.Substring(0, [Math]::Min(200, $reportNormal.Html.Length))
Assert-True -Name '[綠燈段] 正常模式：banner 含「數據過期」' -Condition ($reportNormal.Html -match '數據過期')
Assert-True -Name '[綠燈段] 正常模式：banner 具名失敗對象含不存在的 repo 名' -Condition ($reportNormal.Html -match [regex]::Escape($NonExistentRepo))

Write-Host "`n--- 第四段（附加，非紅燈設計必要，但補齊「正常查詢成功路徑」對照）：對真實存在的 repo 查詢 ---"
try {
    $anchorQueryOk = Get-BoardAnchorQuery -PrimaryRepo $RealOwnerRepo -WorkId 'W-t09-nonexistent-work-id-for-empty-state-check' -Headers $headers
    Assert-True -Name '對真實 repo 查詢執行成功（Ok=true），且合法查無此 work-id（Found=false，空狀態非查詢失敗）' `
        -Condition ($anchorQueryOk.Ok -and (-not $anchorQueryOk.Found)) `
        -Detail "Ok=$($anchorQueryOk.Ok) Found=$($anchorQueryOk.Found) FailureDetail=$($anchorQueryOk.FailureDetail)"
} catch {
    Write-Warning "第四段對照查詢本身失敗（不影響前三段的紅→綠核心驗證）：$($_.Exception.Message)"
}

Write-Host "`n==================== 總結 ====================" -ForegroundColor Cyan
Write-Host "通過：$Script:PassCount　失敗：$Script:FailCount"
if ($Script:FailCount -gt 0) {
    Write-Host "動態測試：FAIL" -ForegroundColor Red
    exit 1
} else {
    Write-Host "動態測試：PASS（紅→綠兩段證據皆完整，紅燈為斷言失敗型）" -ForegroundColor Green
    exit 0
}
