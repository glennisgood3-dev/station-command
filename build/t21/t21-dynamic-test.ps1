#requires -Version 5.1
<#
.SYNOPSIS
    T-21 rework：動態驗收（使用者本機執行，需真實 GitHub PAT，本沙盒無法實跑）。

.DESCRIPTION
    回應站 4 verifier FAIL 的核心要求：「紅是斷言失敗的紅，非載入／collection 失敗」。

    本腳本的核心斷言（A 段）：
        「同一佇列連續套用兩次 ⇒ 目標 issue 上『內文完全相同的留言數』不得增加」
    紅：用 -SkipIdempotencyCheck（刻意關掉套用前現況比對）連跑兩次同一佇列 ⇒ 該斷言
        **真的會失敗**（實測留言數變成 2，不是預期的 1）——這是斷言失敗的紅，不是檔案缺失的紅。
    綠：用正常模式（有現況比對）連跑兩次同一佇列 ⇒ 該斷言通過（實測留言數仍是 1，
        第二次全部 SKIPPED-ALREADY-SATISFIED）。
    兩段輸出各自印出實測數字，一併存檔 t21-dynamic-red-green.txt。

    同時涵蓋 verifier 列的其餘動態驗收：①（三型套用後 payload 相符——comment 型見 A/B/C 段、
    set-labels 型見 D-1、**close-issue 型見 D-1b，用獨立拋棄式 issue 實跑並驗冪等**）
    ③（回驗不符留佇列）④（對帳出列）⑥（遺失降級）、description ≤100 字元守門，以及兩項風險量測：
    【HIGH】comment 冪等的 CRLF 正規化風險（直接量測 GitHub 是否正規化行尾）、
    【MEDIUM】PowerShell 5.1 對繁中字元的 UTF-8 往返正確性。

    Setup 之前另有「孤兒清理」段：關閉 repo 內殘留的舊版動態測試 issue（標題「T-21 動態測試
    （自動建立」開頭且仍 open 者），本身也是一次真實的 close-issue 型佇列套用。

    ⚠️ 語法已人工覆核（PowerShell 5.1 相容：不使用 ??／?./ -AsHashtable 等 7.x 語法），
       但本沙盒無法連線 GitHub 實跑，**尚未實際執行過**——請使用者本機執行後核對輸出。

.PARAMETER PatPath
    PAT 檔案路徑。預設 G:\default mount\station_command-key。

.PARAMETER Owner
    GitHub owner。預設 glennisgood3-dev。

.PARAMETER Repo
    GitHub repo。預設 station-command。

.PARAMETER IssueNumber
    重用既有 issue 做測試靶（不自動關閉）。預設 0＝腳本自動建立一張測試 issue，
    測試結束後自動關閉（GitHub REST API 無法刪除 issue，故以關閉代替清理）。

.EXAMPLE
    .\t21-dynamic-test.ps1
#>

[CmdletBinding()]
param(
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$Owner = 'glennisgood3-dev',
    [string]$Repo = 'station-command',
    [int]$IssueNumber = 0
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir 'queue-common.ps1')
Set-ConsoleUtf8

$Token = Read-PatToken -PatPath $PatPath
$Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t21-dynamic-test'
$RepoFull = "$Owner/$Repo"

$Global:TestLog = New-Object System.Collections.ArrayList
function Log {
    param([string]$Line)
    Write-Host $Line
    [void]$Global:TestLog.Add($Line)
}
function Section {
    param([string]$Title)
    Log ""
    Log "===================================================================="
    Log $Title
    Log "===================================================================="
}

# 以獨立子行程呼叫 apply-queue.ps1 / reconcile-queue.ps1，避免其內部 exit 影響本腳本流程
# （子行程隔離：無論子腳本用什麼方式結束，都不會終止本測試 harness）。
function Invoke-ChildScript {
    param([Parameter(Mandatory)][string]$ScriptPath, [Parameter(Mandatory)][string[]]$ScriptArgs)
    $allArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $ScriptArgs
    $output = & powershell.exe @allArgs 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Write-QueueJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][array]$Items)
    $json = ConvertTo-Json -InputObject $Items -Depth 10
    Write-Utf8BomFile -Path $Path -Content $json
}

$overallOk = $true
$applyScript = Join-Path $ScriptDir 'apply-queue.ps1'
$reconcileScript = Join-Path $ScriptDir 'reconcile-queue.ps1'
$workQueuePath = Join-Path $ScriptDir 't21-dynamic-work-queue.json'

$postedCommentIds = New-Object System.Collections.ArrayList

# ============================================================
# 孤兒清理：關閉任何殘留的「T-21 動態測試（自動建立」開頭、狀態仍 open 的舊測試 issue
#   （上一輪編碼失敗留下的 #27 正好是這段的真實資料）。放在建立本輪測試 issue「之前」，
#   避免掃到自己剛建立的那張。這段本身就是一次真實的 close-issue 型佇列套用，
#   累積驗收①「三型皆實跑」所需的 close-issue 證據。
# ============================================================
Section "孤兒清理：關閉殘留的舊版動態測試 issue（若有），順帶累積 close-issue 實跑證據"

$orphanScanUrl = "https://api.github.com/repos/$Owner/$Repo/issues?state=open&per_page=100"
$openIssuesRaw = Invoke-RestMethod -Uri $orphanScanUrl -Headers $Headers -Method Get
$openIssues = ConvertTo-SafeArray -RawValue $openIssuesRaw
# rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)）。
$openIssues = @($openIssues)
$orphans = @($openIssues | Where-Object { $_.title -like 'T-21 動態測試（自動建立*' })

if ($orphans.Count -eq 0) {
    Log "未發現殘留的舊版動態測試 issue（沒有孤兒要清）。"
} else {
    foreach ($orphan in $orphans) {
        Log "發現孤兒：$RepoFull#$($orphan.number)（標題：$($orphan.title)），經佇列送 close-issue。"
        $orphanCloseItem = @(
            [pscustomobject]@{
                action  = 'close-issue'
                target  = [pscustomobject]@{ repo = $RepoFull; issue = $orphan.number }
                payload = [pscustomobject]@{ state = 'closed'; state_reason = 'not_planned' }
                source  = 'T-21-dynamic-orphan-cleanup'
            }
        )
        Write-QueueJson -Path $workQueuePath -Items $orphanCloseItem
        $orphanResult = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
        Log "套用（孤兒 #$($orphan.number) close-issue）exit=$($orphanResult.ExitCode)"
        Log $orphanResult.Output
        $orphanAfter = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $orphan.number -Headers $Headers
        if ($null -ne $orphanAfter -and $orphanAfter.state -eq 'closed') {
            Log "[PASS] 孤兒 #$($orphan.number) 已關閉（獨立 GET 確認 state=closed）。"
        } else {
            Log "[FAIL] 孤兒 #$($orphan.number) 關閉失敗，請人工複查（獨立 GET state=$($orphanAfter.state)）。"
            $overallOk = $false
        }
    }
}
if (Test-Path -LiteralPath $workQueuePath) { Remove-Item -LiteralPath $workQueuePath -Force }

# ============================================================
# Setup：建立（或重用）測試 issue
# ============================================================
Section "Setup：測試 issue"
$createdIssue = $false
if ($IssueNumber -eq 0) {
    $issueBody = @{
        title = "T-21 動態測試（自動建立，測試完成後會關閉）- $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        body  = "本 issue 由 t21-dynamic-test.ps1 自動建立，供 T-21 rework 動態驗收使用。測試完成後會被自動關閉（GitHub REST API 無法刪除 issue，故以關閉代替清理）。"
    } | ConvertTo-Json -Compress
    $createUrl = "https://api.github.com/repos/$Owner/$Repo/issues"
    $resp = Invoke-RestMethod -Uri $createUrl -Headers $Headers -Method Post -Body $issueBody -ContentType 'application/json; charset=utf-8'
    $IssueNumber = $resp.number
    $createdIssue = $true
    Log "建立測試 issue：$RepoFull#$IssueNumber"
} else {
    Log "重用使用者指定 issue：$RepoFull#$IssueNumber（測試結束後不會自動關閉）"
}

# ============================================================
# A 段（核心，rework 要求）：冪等斷言的 紅 → 綠
#   斷言：「同一佇列連續套用兩次 ⇒ 目標 issue 上『內文完全相同的留言數』不得增加」
# ============================================================
Section "A. 冪等斷言 — RED（-SkipIdempotencyCheck 關掉現況比對）"

$redBody = "T-21 rework 冪等紅燈驗證留言 - $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffffff')"
$redItem = @(
    [pscustomobject]@{
        action  = 'comment'
        target  = [pscustomobject]@{ repo = $RepoFull; issue = $IssueNumber }
        payload = [pscustomobject]@{ body = $redBody }
        source  = 'T-21-dynamic-red'
    }
)

Log "斷言內容：同一則留言（body 逐字相同）套用兩次後，issue 上應只有 1 則；-SkipIdempotencyCheck 開啟時預期會失敗（變成 2）。"

Write-QueueJson -Path $workQueuePath -Items $redItem
$r1 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath, '-SkipIdempotencyCheck')
Log "第 1 次套用（SkipIdempotencyCheck）exit=$($r1.ExitCode)"
Log $r1.Output

# 重寫同一份佇列內容（模擬「同一份佇列」再次被送到套用腳本——因為第一次套用完後
# 該筆若判定已達成會被移除，需要用同樣內容重建，代表「同一個邏輯動作再跑一次」）
Write-QueueJson -Path $workQueuePath -Items $redItem
$r2 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath, '-SkipIdempotencyCheck')
Log "第 2 次套用（SkipIdempotencyCheck）exit=$($r2.ExitCode)"
Log $r2.Output

# 獨立預期值來源：直接重新 GET 該 issue 全部留言，自行計數（不透過 apply-queue.ps1 的內部邏輯）
$commentsAfterRed = Get-CurrentIssueComments -Owner $Owner -Repo $Repo -IssueNumber $IssueNumber -Headers $Headers
# rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
# 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
$commentsAfterRed = @($commentsAfterRed)
foreach ($c in ($commentsAfterRed | Where-Object { $_.body -eq $redBody })) { [void]$postedCommentIds.Add($c.id) }
$redCount = @($commentsAfterRed | Where-Object { $_.body -eq $redBody }).Count

if ($redCount -eq 1) {
    Log "[UNEXPECTED] 斷言未失敗（實測留言數=$redCount，預期應為 2 才對，因為 SkipIdempotencyCheck 應該導致重複貼文）。"
    Log "             請人工複查：-SkipIdempotencyCheck 是否真的生效、或本次 GitHub 端有去重行為。"
    $overallOk = $false
} else {
    Log "[RED-CONFIRMED] 斷言失敗，如預期：留言數不得增加（預期 1）⇒ 實測 $redCount（>1，重複貼文已發生）。"
    Log "                這就是 Spec §6 要求的『斷言失敗的紅』——不是檔案缺失，是冪等機制被刻意關掉後真的壞給你看。"
}

Section "A. 冪等斷言 — GREEN（正常模式，套用前讀現況比對）"

$greenBody = "T-21 rework 冪等綠燈驗證留言 - $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffffff')"
$greenItem = @(
    [pscustomobject]@{
        action  = 'comment'
        target  = [pscustomobject]@{ repo = $RepoFull; issue = $IssueNumber }
        payload = [pscustomobject]@{ body = $greenBody }
        source  = 'T-21-dynamic-green'
    }
)

Write-QueueJson -Path $workQueuePath -Items $greenItem
$g1 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log "第 1 次套用（正常模式）exit=$($g1.ExitCode)"
Log $g1.Output

Write-QueueJson -Path $workQueuePath -Items $greenItem
$g2 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log "第 2 次套用（正常模式，同一份佇列內容）exit=$($g2.ExitCode)"
Log $g2.Output

$commentsAfterGreen = Get-CurrentIssueComments -Owner $Owner -Repo $Repo -IssueNumber $IssueNumber -Headers $Headers
# rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
# 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
$commentsAfterGreen = @($commentsAfterGreen)
foreach ($c in ($commentsAfterGreen | Where-Object { $_.body -eq $greenBody })) { [void]$postedCommentIds.Add($c.id) }
$greenCount = @($commentsAfterGreen | Where-Object { $_.body -eq $greenBody }).Count

if ($greenCount -eq 1) {
    Log "[GREEN-CONFIRMED] 斷言通過：留言數不得增加（預期 1）⇒ 實測 $greenCount。第二次套用應可在上方輸出看到 SKIPPED-ALREADY-SATISFIED。"
} else {
    Log "[FAIL] 斷言在正常模式下仍失敗：實測留言數=$greenCount（預期 1）。冪等機制可能有 bug，需人工複查上方兩次執行輸出。"
    $overallOk = $false
}

# ============================================================
# B. 【HIGH】comment 冪等的 CRLF 正規化風險 — 直接量測
# ============================================================
Section "B. CRLF 正規化風險量測（verifier HIGH）"

$crlfBody = "第一行`r`n第二行`r`n第三行（CRLF 測試 - $(Get-Date -Format 'HHmmss.fffffff')）"
$crlfItem = @(
    [pscustomobject]@{
        action  = 'comment'
        target  = [pscustomobject]@{ repo = $RepoFull; issue = $IssueNumber }
        payload = [pscustomobject]@{ body = $crlfBody }
        source  = 'T-21-dynamic-crlf'
    }
)
Write-QueueJson -Path $workQueuePath -Items $crlfItem
$c1 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log "第 1 次套用（CRLF 留言）exit=$($c1.ExitCode)"
Log $c1.Output

$fetchedComments = Get-CurrentIssueComments -Owner $Owner -Repo $Repo -IssueNumber $IssueNumber -Headers $Headers
# rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
# 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
$fetchedComments = @($fetchedComments)
$exactMatch = @($fetchedComments | Where-Object { $_.body -eq $crlfBody })
$normalizedMatch = @($fetchedComments | Where-Object { (ConvertTo-NormalizedText -Text $_.body) -eq (ConvertTo-NormalizedText -Text $crlfBody) })

if ($exactMatch.Count -gt 0) {
    Log "[量測結果] GitHub 原樣保留 CRLF：完全字串比對即可命中，未偵測到正規化。"
    foreach ($c in $exactMatch) { [void]$postedCommentIds.Add($c.id) }
} elseif ($normalizedMatch.Count -gt 0) {
    Log "[量測結果] GitHub 確實對行尾做了正規化（完全比對未命中、換行正規化後比對命中）——"
    Log "           queue-common.ps1 的 Test-ItemSatisfied 已內建正規化 fallback（ConvertTo-NormalizedText），此風險已預先處理。"
    foreach ($c in $normalizedMatch) { [void]$postedCommentIds.Add($c.id) }
} else {
    Log "[量測失敗] 完全比對與正規化比對皆未命中，可能是 API 延遲或其他編碼問題，需人工複查 fetchedComments 原始內容。"
    $overallOk = $false
}

# 重跑一次同一份 CRLF 佇列，驗證正規化 fallback 有沒有真的讓第二次判定為已達成（不重貼）
Write-QueueJson -Path $workQueuePath -Items $crlfItem
$c2 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log "第 2 次套用（同一份 CRLF 佇列）exit=$($c2.ExitCode)"
Log $c2.Output
$commentsForCrlfRecheck = Get-CurrentIssueComments -Owner $Owner -Repo $Repo -IssueNumber $IssueNumber -Headers $Headers
# rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
# 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
$commentsForCrlfRecheck = @($commentsForCrlfRecheck)
$crlfCountAfter = @($commentsForCrlfRecheck | Where-Object { (ConvertTo-NormalizedText -Text $_.body) -eq (ConvertTo-NormalizedText -Text $crlfBody) }).Count
if ($crlfCountAfter -eq 1) {
    Log "[PASS] CRLF 留言冪等：兩次套用後仍只有 1 則（正規化 fallback 生效）。"
} else {
    Log "[FAIL] CRLF 留言冪等失敗：實測 $crlfCountAfter 則（預期 1）。需再檢查 ConvertTo-NormalizedText 邏輯。"
    $overallOk = $false
}

# ============================================================
# C. 【MEDIUM】PowerShell 5.1 UTF-8 繁中往返
# ============================================================
Section "C. UTF-8 繁中往返量測（verifier MEDIUM）"

$zhBody = "T-21 動態測試：繁體中文往返驗證，含常用字元「驗收」「佇列」「冪等」「回驗」與符號「⇒」「§4.6」- $(Get-Date -Format 'HHmmss.fffffff')"
$zhItem = @(
    [pscustomobject]@{
        action  = 'comment'
        target  = [pscustomobject]@{ repo = $RepoFull; issue = $IssueNumber }
        payload = [pscustomobject]@{ body = $zhBody }
        source  = 'T-21-dynamic-utf8'
    }
)
Write-QueueJson -Path $workQueuePath -Items $zhItem
$z1 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log "套用繁中留言 exit=$($z1.ExitCode)"
Log $z1.Output

$zhComments = Get-CurrentIssueComments -Owner $Owner -Repo $Repo -IssueNumber $IssueNumber -Headers $Headers
# rework：對「已賦值變數」再包 @() 是安全的（不同於直接 @(函式呼叫本身)，
# 後者對本檔內部已用逗號保留陣列型別的函式會把 0 筆結果錯誤包成 1 筆，已用 pwsh 7 實測抓到並修正）。
$zhComments = @($zhComments)
$zhMatch = @($zhComments | Where-Object { $_.body -eq $zhBody })
if ($zhMatch.Count -gt 0) {
    Log "[PASS] 繁中字元逐字往返相符（送出與讀回完全一致）。"
    foreach ($c in $zhMatch) { [void]$postedCommentIds.Add($c.id) }
} else {
    Log "[FAIL] 繁中字元往返不相符——送出內容與讀回內容不相等，需人工比對逐字元差異（可能是 PowerShell 5.1 主控台編碼或 Invoke-RestMethod 回應解析問題）。"
    $overallOk = $false
}

# ============================================================
# D. 其餘動態驗收：①③④⑥ + description 守門
# ============================================================
Section "D-1. 驗收① 三型套用後 payload 相符（set-labels 段；close-issue 段見 D-1b 獨立拋棄式 issue；comment 型已於 A/B/C 段實跑）"

$labelItem = @(
    [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $RepoFull; issue = $IssueNumber }
        payload = [pscustomobject]@{ labels = @('sc:awaiting-user') }
        source  = 'T-21-dynamic-labels'
    }
)
Write-QueueJson -Path $workQueuePath -Items $labelItem
$d1 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log $d1.Output
$issueNow = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $IssueNumber -Headers $Headers
# rework：$issueNow.labels 為 $null 時（issue 剛好無任何 label）直接 pipe 進 ForEach-Object
# 會在 StrictMode 下對 $_.name 拋錯（已用 pwsh 7 實測重現）；用 ConvertTo-SafeArray 擋一層。
$issueNowLabels = ConvertTo-SafeArray -RawValue $issueNow.labels
$labelNames = @($issueNowLabels | ForEach-Object { $_.name })
if (@($labelNames | Where-Object { $_ -eq 'sc:awaiting-user' }).Count -eq 1) {
    Log "[PASS] set-labels 套用後 label 集合含 sc:awaiting-user（獨立 GET 驗證）。"
} else {
    Log "[FAIL] set-labels 套用後未在獨立 GET 中看到 sc:awaiting-user，實際：[$($labelNames -join ', ')]"
    $overallOk = $false
}

Section "D-1b. 驗收① close-issue 型實跑（獨立拋棄式 issue，避免影響主測試 issue 的狀態流程）"

$d1bIssueBody = @{
    title = "T-21 動態測試 D-1b close-issue 子測試（拋棄式）- $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    body  = "本 issue 由 t21-dynamic-test.ps1 的 D-1b 段自動建立，專門驗證 close-issue 型佇列項。測試本身就是把它關閉，關閉即代表通過，不需另外清理。"
} | ConvertTo-Json -Compress
$d1bCreateResp = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/issues" -Headers $Headers -Method Post -Body $d1bIssueBody -ContentType 'application/json; charset=utf-8'
$d1bIssueNumber = $d1bCreateResp.number
Log "建立 D-1b 拋棄式測試 issue：$RepoFull#$d1bIssueNumber"

$closeItem = @(
    [pscustomobject]@{
        action  = 'close-issue'
        target  = [pscustomobject]@{ repo = $RepoFull; issue = $d1bIssueNumber }
        payload = [pscustomobject]@{ state = 'closed'; state_reason = 'not_planned' }
        source  = 'T-21-dynamic-d1b-close'
    }
)

Write-QueueJson -Path $workQueuePath -Items $closeItem
$d1b1 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log "第 1 次套用（close-issue）exit=$($d1b1.ExitCode)"
Log $d1b1.Output

# 獨立預期值來源：直接重新 GET 該 issue，自行核對 state（不透過 apply-queue.ps1 的內部邏輯）
$d1bIssueAfter1 = Get-CurrentIssue -Owner $Owner -Repo $Repo -IssueNumber $d1bIssueNumber -Headers $Headers
if ($d1b1.Output -match 'APPLIED-VERIFIED' -and $null -ne $d1bIssueAfter1 -and $d1bIssueAfter1.state -eq 'closed') {
    Log "[PASS] D-1b-1：close-issue 套用後輸出含 APPLIED-VERIFIED，且獨立 GET 確認 state=closed。"
} else {
    $afterState = if ($null -eq $d1bIssueAfter1) { '(GET 失敗)' } else { $d1bIssueAfter1.state }
    Log "[FAIL] D-1b-1：close-issue 套用未如預期（exit=$($d1b1.ExitCode)；獨立 GET state=$afterState）。"
    $overallOk = $false
}

# 冪等：同一筆再套用一次 ⇒ 已關閉的 issue 不該重複呼叫 API，預期 SKIPPED-ALREADY-SATISFIED
Write-QueueJson -Path $workQueuePath -Items $closeItem
$d1b2 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log "第 2 次套用（同一筆 close-issue，驗冪等）exit=$($d1b2.ExitCode)"
Log $d1b2.Output
if ($d1b2.Output -match 'SKIPPED-ALREADY-SATISFIED') {
    Log "[PASS] D-1b-2：已關閉的 issue 重套 close-issue ⇒ SKIPPED-ALREADY-SATISFIED（未重複呼叫寫入 API）。"
} else {
    Log "[FAIL] D-1b-2：預期輸出含 SKIPPED-ALREADY-SATISFIED，實際未命中，請人工複查上方輸出。"
    $overallOk = $false
}

Section "D-2. 驗收③ 回驗不符 ⇒ 留在佇列並具名回報（用不存在的 issue 號製造真實失敗）"

$badItem = @(
    [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $RepoFull; issue = 999999999 }
        payload = [pscustomobject]@{ labels = @('sc:blocked') }
        source  = 'T-21-dynamic-bad-target'
    }
)
Write-QueueJson -Path $workQueuePath -Items $badItem
$d3 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log "exit=$($d3.ExitCode)"
Log $d3.Output
$remainingAfterBad = Read-QueueFile -QueuePath $workQueuePath
if ($null -ne $remainingAfterBad -and @($remainingAfterBad).Count -eq 1) {
    Log "[PASS] 不存在的目標套用失敗後，該筆確實留在佇列（未被誤標為已套用）。"
} else {
    Log "[FAIL] 預期該筆應留在佇列，實際佇列筆數：$(@($remainingAfterBad).Count)"
    $overallOk = $false
}

Section "D-3. 驗收④ 對帳出列（先手動落地，再跑 reconcile-queue.ps1，且過程不寫 GitHub）"

$landedLabelSet = @('sc:ticket', 'sc:awaiting-user')
$putUrl = "https://api.github.com/repos/$Owner/$Repo/issues/$IssueNumber/labels"
$putBody = @{ labels = $landedLabelSet } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri $putUrl -Headers $Headers -Method Put -Body $putBody -ContentType 'application/json; charset=utf-8' | Out-Null
Log "已用獨立 API 呼叫（非套用腳本）手動把 label 集合設為 [$($landedLabelSet -join ', ')]，模擬『已由他途落地』。"

$reconcileItem = @(
    [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $RepoFull; issue = $IssueNumber }
        payload = [pscustomobject]@{ labels = $landedLabelSet }
        source  = 'T-21-dynamic-reconcile'
    }
)
Write-QueueJson -Path $workQueuePath -Items $reconcileItem
$d4 = Invoke-ChildScript -ScriptPath $reconcileScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log $d4.Output
$remainingAfterReconcile = Read-QueueFile -QueuePath $workQueuePath
if ($null -ne $remainingAfterReconcile -and @($remainingAfterReconcile).Count -eq 0) {
    Log "[PASS] 已落地項目經 reconcile-queue.ps1 對帳後自動出列（佇列變空）。"
} else {
    Log "[FAIL] 預期對帳後佇列應為空，實際筆數：$(@($remainingAfterReconcile).Count)"
    $overallOk = $false
}

Section "D-4. 驗收⑥ 遺失降級（刪佇列檔後兩支腳本皆具名回報且 exit 0）"

if (Test-Path -LiteralPath $workQueuePath) { Remove-Item -LiteralPath $workQueuePath -Force }
$d6a = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
$d6b = Invoke-ChildScript -ScriptPath $reconcileScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log "apply-queue.ps1 exit=$($d6a.ExitCode)：$($d6a.Output)"
Log "reconcile-queue.ps1 exit=$($d6b.ExitCode)：$($d6b.Output)"
if ($d6a.ExitCode -eq 0 -and $d6a.Output -match '待寫佇列不存在' -and $d6b.ExitCode -eq 0 -and $d6b.Output -match '待寫佇列不存在') {
    Log "[PASS] 兩支腳本在佇列檔不存在時皆具名回報且 exit 0。"
} else {
    Log "[FAIL] 遺失降級行為不符預期，請人工複查上方輸出。"
    $overallOk = $false
}

Section "D-5. description ≤100 字元守門（fixtures/description-too-long.json）"

$descFixture = Join-Path $ScriptDir 'fixtures\description-too-long.json'
Copy-Item -LiteralPath $descFixture -Destination $workQueuePath -Force
$d5 = Invoke-ChildScript -ScriptPath $applyScript -ScriptArgs @('-PatPath', $PatPath, '-QueuePath', $workQueuePath)
Log $d5.Output
if ($d5.Output -match 'FAILED-VALIDATION') {
    Log "[PASS] description 逾 100 字元的佇列項被送出前擋下（FAILED-VALIDATION），未嘗試呼叫 GitHub API。"
} else {
    Log "[FAIL] 未看到 FAILED-VALIDATION，守門邏輯可能未生效。"
    $overallOk = $false
}
if (Test-Path -LiteralPath $workQueuePath) { Remove-Item -LiteralPath $workQueuePath -Force }

# ============================================================
# Cleanup
# ============================================================
Section "Cleanup"

foreach ($cid in $postedCommentIds) {
    try {
        $delUrl = "https://api.github.com/repos/$Owner/$Repo/issues/comments/$cid"
        Invoke-RestMethod -Uri $delUrl -Headers $Headers -Method Delete | Out-Null
        Log "已刪除測試留言 id=$cid"
    } catch {
        Log "刪除測試留言 id=$cid 失敗（非致命，可忽略或手動清理）：$($_.Exception.Message)"
    }
}

if ($createdIssue) {
    try {
        $closeUrl = "https://api.github.com/repos/$Owner/$Repo/issues/$IssueNumber"
        $closeBody = @{ state = 'closed'; state_reason = 'not_planned' } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $closeUrl -Headers $Headers -Method Patch -Body $closeBody -ContentType 'application/json; charset=utf-8' | Out-Null
        Log "已關閉自動建立的測試 issue：$RepoFull#$IssueNumber（GitHub REST API 無法刪除 issue，以關閉代替）"
    } catch {
        Log "關閉測試 issue 失敗，請人工到 $RepoFull#$IssueNumber 手動關閉：$($_.Exception.Message)"
    }
} else {
    Log "測試 issue 為使用者指定重用，不自動關閉。"
}

if (Test-Path -LiteralPath $workQueuePath) { Remove-Item -LiteralPath $workQueuePath -Force }

# ============================================================
# 總結與存檔
# ============================================================
Section "總結"
if ($overallOk) {
    Log "整體：GREEN — A 段冪等斷言的紅（SkipIdempotencyCheck）與綠（正常模式）皆如預期；其餘動態驗收皆 PASS。"
} else {
    Log "整體：存在未預期結果（見上方 [UNEXPECTED]／[FAIL] 標記），需人工複查。"
}

$reportPath = Join-Path $ScriptDir 't21-dynamic-red-green.txt'
Write-Utf8BomFile -Path $reportPath -Content ($Global:TestLog -join [Environment]::NewLine)
Write-Host ""
Write-Host "完整輸出已存檔：$reportPath"

if ($overallOk) { exit 0 }
exit 1
