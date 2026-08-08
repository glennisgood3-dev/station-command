#requires -Version 5.1
<#
.SYNOPSIS
    T-21 rework：離線 mock 測試——沙盒可跑，不連 GitHub，攔截「陣列被解卷成純量／$null」同型 bug。

.DESCRIPTION
    起因：實跑撞到 `queue-common.ps1` 的 Get-CurrentIssueComments 在 PowerShell 5.1 下，
    對只回 1 筆的 API 回應取 `.Count` 直接拋錯（StrictMode + 5.1 無「純量也有 .Count」相容層）。
    本檔用假的 `Invoke-RestMethod`（mock，本 session 定義的同名函式會蓋過真正的 cmdlet，
    queue-common.ps1 內部呼叫 Invoke-RestMethod 時會解析到這個假版本，不連網）覆蓋四種
    API 回應形狀，直接呼叫 queue-common.ps1 的純邏輯函式驗證行為：

        A. 回傳 1 筆（模擬 PowerShell 對「JSON 陣列只有 1 個元素」的真實解卷行為——
           mock 直接回一個裸 [pscustomobject]，不包陣列，忠實重現 5.1 的真實形狀）
        B. 回傳 0 筆（模擬 API 回應空陣列時、Invoke-RestMethod 捕捉端點會拿到 $null 的真實行為）
        C. 回傳多筆（正常案例，回歸檢查用）
        D. labels 為空（issue 物件的 .labels 屬性為 $null，模擬「issue 目前無任何 label」）

    ⚠️ 已知環境落差（本沙盒跑 pwsh 7.4.6，使用者環境是 Windows PowerShell 5.1）：
       PowerShell 6+ 對「純量物件」加了 `.Count`／`.Length` 相容屬性（會回 1，不拋錯），
       5.1 沒有這個相容層，`.Count` 在 StrictMode 下對純量物件會直接拋
       "The property 'Count' cannot be found on this object"（已用 pwsh 7 實測確認：
       此相容層只对 $null 例外——對 $null 取 .Count 兩版皆拋錯，這條路徑本測試仍攔得住）。
       因此本測試的斷言**一律用 `-is [array]` 或型別名稱檢查**驗證「回傳值真的是陣列」，
       不能只靠 `.Count` 不拋錯來判定通過，否則在 pwsh 7 下會有假陰性（測不出 5.1 才會炸的 bug）。
       本檔案本身以 5.1 相容語法撰寫（不用 ??／?./ -AsHashtable），但**只在沙盒 pwsh 7 跑過**，
       尚未在真正的 Windows PowerShell 5.1 上驗證。

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t21-offline-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

$script:TestResults = New-Object System.Collections.ArrayList
$script:FailCount = 0

function Assert-True {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-Host "[PASS] $Name $Detail"
        [void]$script:TestResults.Add("[PASS] $Name $Detail")
    } else {
        Write-Host "[FAIL] $Name $Detail"
        [void]$script:TestResults.Add("[FAIL] $Name $Detail")
        $script:FailCount++
    }
}

function Assert-IsArray {
    # 明確用 -is [array] 而非 .Count 判斷（理由見檔頭說明：.Count 在 pwsh7 對純量也不拋錯，
    # 靠它驗證會有假陰性，測不出 PS 5.1 才會爆的「純量而非陣列」回歸）。
    param([Parameter(Mandatory)][string]$Name, $Value, [Parameter(Mandatory)][int]$ExpectedCount)
    $isArray = $Value -is [array]
    $actualCount = if ($isArray) { $Value.Count } elseif ($null -eq $Value) { -1 } else { -2 }
    $shapeDesc = if ($isArray) { "陣列，Count=$actualCount" } elseif ($null -eq $Value) { "純量 `$null（未包陣列！）" } else { "純量物件（未包陣列！型別：$($Value.GetType().Name)）" }
    $ok = $isArray -and ($Value.Count -eq $ExpectedCount)
    Assert-True -Name $Name -Condition $ok -Detail "預期陣列且 Count=$ExpectedCount；實際：$shapeDesc"
}

# ============================================================
# Mock 基礎設施：覆蓋 Invoke-RestMethod，依 URL 查表回傳假資料，不連網
# ============================================================
$script:MockResponses = @{}
$script:MockCallLog = New-Object System.Collections.ArrayList

function Invoke-RestMethod {
    # 本函式定義在 dot-source queue-common.ps1 之前；queue-common.ps1 內部呼叫的
    # Invoke-RestMethod 是「未限定命名空間」的呼叫，PowerShell 的命令解析順序是
    # 別名 > 函式 > Cmdlet，函式定義在同一個 scope chain 內會蓋過內建 cmdlet，
    # 因此 queue-common.ps1 的函式實際執行時會呼叫到這個 mock 版本，不會真的連網。
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Uri,
        [Parameter()] $Headers,
        [Parameter()] [string]$Method = 'Get',
        [Parameter()] $Body,
        [Parameter()] [string]$ContentType
    )
    [void]$script:MockCallLog.Add([pscustomobject]@{ Uri = $Uri; Method = $Method })
    if ($script:MockResponses.ContainsKey($Uri)) {
        return $script:MockResponses[$Uri]
    }
    throw "MOCK-MISS：t21-offline-test.ps1 未替這個 URL 設定假回應，無法繼續（也證明沒有真的連網）：$Method $Uri"
}

. (Join-Path $ScriptDir 'queue-common.ps1')
Set-StrictMode -Version Latest

$FakeHeaders = @{ 'Authorization' = 'Bearer FAKE-TOKEN-NOT-REAL'; 'Accept' = 'application/vnd.github+json' }

Write-Host "===================================================================="
Write-Host "形狀 A：API 回傳 1 筆（mock 回裸物件，忠實重現 PS 5.1 的真實解卷行為）"
Write-Host "===================================================================="

$commentsUrlA = "https://api.github.com/repos/o/r/issues/1/comments?per_page=100&page=1"
# 关键：故意回傳「裸 pscustomobject」而非陣列——這就是 Invoke-RestMethod 對「JSON 陣列只有
# 1 個元素」的真實回傳形狀（已用 pwsh 7 實測確認：函式/cmdlet 輸出 1 元素陣列時，捕捉端會
# 拿到純量，不是陣列）。
$script:MockResponses[$commentsUrlA] = [pscustomobject]@{ id = 111; body = 'single comment' }

$resultA = Get-CurrentIssueComments -Owner 'o' -Repo 'r' -IssueNumber 1 -Headers $FakeHeaders
Assert-IsArray -Name "A1 Get-CurrentIssueComments(1 筆) 回傳值型別" -Value $resultA -ExpectedCount 1
Assert-True -Name "A2 Get-CurrentIssueComments(1 筆) 內容正確" -Condition ($resultA.Count -eq 1 -and $resultA[0].id -eq 111)

# 這正是原本實跑爆掉的路徑：Test-ItemSatisfied 的 comment 分支對 1 筆留言做冪等比對
$itemA = [pscustomobject]@{
    action  = 'comment'
    target  = [pscustomobject]@{ repo = 'o/r'; issue = 1 }
    payload = [pscustomobject]@{ body = 'single comment' }
    source  = 'offline-test-A'
}
$satA = Test-ItemSatisfied -Item $itemA -Headers $FakeHeaders
Assert-True -Name "A3 Test-ItemSatisfied(comment, 1 筆已存在) 不拋錯且判定 Satisfied" -Condition $satA.Satisfied -Detail $satA.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "形狀 B：API 回傳 0 筆（mock 回 `$null，重現 Invoke-RestMethod 對空陣列回應的真實行為）"
Write-Host "===================================================================="

$commentsUrlB = "https://api.github.com/repos/o/r/issues/2/comments?per_page=100&page=1"
$script:MockResponses[$commentsUrlB] = $null

$resultB = Get-CurrentIssueComments -Owner 'o' -Repo 'r' -IssueNumber 2 -Headers $FakeHeaders
Assert-IsArray -Name "B1 Get-CurrentIssueComments(0 筆) 回傳值型別" -Value $resultB -ExpectedCount 0

$itemB = [pscustomobject]@{
    action  = 'comment'
    target  = [pscustomobject]@{ repo = 'o/r'; issue = 2 }
    payload = [pscustomobject]@{ body = 'not posted yet' }
    source  = 'offline-test-B'
}
$satB = Test-ItemSatisfied -Item $itemB -Headers $FakeHeaders
Assert-True -Name "B2 Test-ItemSatisfied(comment, 0 筆現況) 不拋錯且判定未達成" -Condition (-not $satB.Satisfied) -Detail $satB.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "形狀 C：API 回傳多筆（正常情況，回歸檢查）"
Write-Host "===================================================================="

$commentsUrlC = "https://api.github.com/repos/o/r/issues/3/comments?per_page=100&page=1"
$script:MockResponses[$commentsUrlC] = @(
    [pscustomobject]@{ id = 301; body = 'first' },
    [pscustomobject]@{ id = 302; body = 'second' },
    [pscustomobject]@{ id = 303; body = 'third' }
)

$resultC = Get-CurrentIssueComments -Owner 'o' -Repo 'r' -IssueNumber 3 -Headers $FakeHeaders
Assert-IsArray -Name "C1 Get-CurrentIssueComments(3 筆) 回傳值型別" -Value $resultC -ExpectedCount 3

$itemC = [pscustomobject]@{
    action  = 'comment'
    target  = [pscustomobject]@{ repo = 'o/r'; issue = 3 }
    payload = [pscustomobject]@{ body = 'second' }
    source  = 'offline-test-C'
}
$satC = Test-ItemSatisfied -Item $itemC -Headers $FakeHeaders
Assert-True -Name "C2 Test-ItemSatisfied(comment, 3 筆中命中第 2 筆) 判定 Satisfied" -Condition $satC.Satisfied -Detail $satC.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "形狀 D：issue.labels 為空（`$null，模擬 issue 目前無任何 label）"
Write-Host "===================================================================="

$issueUrlD = "https://api.github.com/repos/o/r/issues/4"
$script:MockResponses[$issueUrlD] = [pscustomobject]@{
    number = 4
    state  = 'open'
    state_reason = $null
    labels = $null   # 關鍵：模擬 GitHub 回應「無 label」時 labels 屬性為 $null 的情況
}

$itemD = [pscustomobject]@{
    action  = 'set-labels'
    target  = [pscustomobject]@{ repo = 'o/r'; issue = 4 }
    payload = [pscustomobject]@{ labels = @('sc:ticket') }
    source  = 'offline-test-D'
}
# 這正是原本會在 $issue.labels | ForEach-Object { $_.name } 拋「The property 'name' cannot
# be found」的路徑（已用 pwsh 7 + StrictMode 實測重現此例外，見 rework 說明）。
$satD = Test-ItemSatisfied -Item $itemD -Headers $FakeHeaders
Assert-True -Name "D1 Test-ItemSatisfied(set-labels, issue.labels=`$null) 不拋錯" -Condition ($null -ne $satD) -Detail $satD.Detail
Assert-True -Name "D2 判定為未達成（現有 0 個 label != 期望 1 個）" -Condition (-not $satD.Satisfied) -Detail $satD.Detail

# 額外：issue.labels 為「只有 1 個 label」的裸物件形狀（同形狀 A 的問題，但發生在巢狀屬性）
$issueUrlD2 = "https://api.github.com/repos/o/r/issues/5"
$script:MockResponses[$issueUrlD2] = [pscustomobject]@{
    number = 5
    state  = 'open'
    state_reason = $null
    labels = @([pscustomobject]@{ name = 'sc:ticket' })  # ConvertFrom-Json 的巢狀陣列屬性正常情況下仍是陣列
}
$itemD2 = [pscustomobject]@{
    action  = 'set-labels'
    target  = [pscustomobject]@{ repo = 'o/r'; issue = 5 }
    payload = [pscustomobject]@{ labels = @('sc:ticket') }
    source  = 'offline-test-D2'
}
$satD2 = Test-ItemSatisfied -Item $itemD2 -Headers $FakeHeaders
Assert-True -Name "D3 Test-ItemSatisfied(set-labels, issue 恰有 1 個既有 label) 判定已達成" -Condition $satD2.Satisfied -Detail $satD2.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "額外回歸：Get-DescriptionLengthViolations 對「恰好 1 筆違規」不拋錯（apply-queue.ps1 曾經的隱性風險）"
Write-Host "===================================================================="

$payloadOneViolation = [pscustomobject]@{
    title       = 'ok title'
    description = ('x' * 145)
}
$violations = Get-DescriptionLengthViolations -Payload $payloadOneViolation
# rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
# 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
$violations = @($violations)
Assert-IsArray -Name "E1 Get-DescriptionLengthViolations(恰好 1 筆違規) 回傳值型別" -Value $violations -ExpectedCount 1

$payloadZeroViolation = [pscustomobject]@{ title = 'ok title'; description = 'short' }
$violationsZero = Get-DescriptionLengthViolations -Payload $payloadZeroViolation
# rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
# 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
$violationsZero = @($violationsZero)
Assert-IsArray -Name "E2 Get-DescriptionLengthViolations(0 筆違規) 回傳值型別" -Value $violationsZero -ExpectedCount 0

Write-Host ""
Write-Host "===================================================================="
Write-Host "額外回歸：Read-QueueFile 對「檔內恰好 1 筆」與「檔內 0 筆（空陣列）」不拋錯"
Write-Host "===================================================================="

$tmpQueueOne = Join-Path $ScriptDir 't21-offline-test-tmp-one.json'
Write-Utf8BomFile -Path $tmpQueueOne -Content '[{"action":"comment","target":{"repo":"o/r","issue":1},"payload":{"body":"x"},"source":"s"}]'
$readOne = Read-QueueFile -QueuePath $tmpQueueOne
Assert-IsArray -Name "F1 Read-QueueFile(檔內恰 1 筆) 回傳值型別" -Value $readOne -ExpectedCount 1
Remove-Item -LiteralPath $tmpQueueOne -Force

$tmpQueueEmpty = Join-Path $ScriptDir 't21-offline-test-tmp-empty.json'
Write-Utf8BomFile -Path $tmpQueueEmpty -Content '[]'
$readEmpty = Read-QueueFile -QueuePath $tmpQueueEmpty
Assert-IsArray -Name "F2 Read-QueueFile(檔內 0 筆) 回傳值型別" -Value $readEmpty -ExpectedCount 0
Remove-Item -LiteralPath $tmpQueueEmpty -Force

$readMissing = Read-QueueFile -QueuePath (Join-Path $ScriptDir 't21-offline-test-does-not-exist.json')
Assert-True -Name "F3 Read-QueueFile(檔案不存在) 回傳 `$null（哨兵值，非空陣列）" -Condition ($null -eq $readMissing)

# ============================================================
# 總結
# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Host "===================================================================="

$reportPath = Join-Path $ScriptDir 't21-offline-test-report.txt'
$reportLines = @("t21-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", "")
$reportLines += $script:TestResults
$reportLines += ""
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
