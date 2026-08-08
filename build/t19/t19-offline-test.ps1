#requires -Version 5.1
<#
.SYNOPSIS
    T-19：離線 mock 測試——沙盒可跑，不連 GitHub。比照 T-10／T-12／T-13 offline test 手法：
    覆蓋 Invoke-RestMethod 為丟錯的假函式（證明沒有真的連網、也證明 decisions-scan.ps1 的
    -HttpGetFunc／-FetchFunction 依賴注入設計徹底繞過了它），dot-source decisions-scan.ps1
    -FunctionsOnly 直接呼叫內部函式做函式級別驗證。

.DESCRIPTION
    群組 A：Split-MarkdownTableRow／Test-IsSeparatorRow（表格切列基礎函式）
    群組 B：ConvertFrom-DecisionsTable 對五份人造 fixture 檔案（過期／未過期／格式不合／
            無表格／無豁免）的解析結果——本群組即「獨立預期值來源」的具體落地：預期值來自
            fixture 檔內容本身的人為配置，不取自被測程式的輸出。
    群組 C：Get-ExemptionRows 過濾非豁免類型列
    群組 D：ConvertFrom-ExemptionContentCell 子欄位解析（完整／缺欄位／缺標記／期限格式錯）
    群組 E：Test-ExemptionEntryExpired（永久／未過期／已過期三態）
    群組 F：Invoke-DecisionsFileExemptionScan——【核心：三情境 fail-closed】不存在＝pass、
            讀取失敗＝fail、過期＝fail；另涵蓋解析失敗＝fail、格式不合＝fail、無豁免＝pass、
            全合規＝pass
    群組 G：Test-RepoScanCoverage（純函式）＋ Invoke-DecisionsExemptionScan 整合（含涵蓋範圍
            檢查：缺一 repo 未掃即算失敗）
    群組 H：sc:gate-fail 佇列項產生與冪等去重（本檔扮演 gate 角色，唯一得產生 set-labels 者；
            落地一律走佇列，不直接呼叫 GitHub 寫入 API）
    群組 I：Get-DecisionsFileFetchResult 透過 -HttpGetFunc 依賴注入驗證（成功／404／其他錯誤
            三分支，含 base64 解碼）
    群組 J：【紅燈】-BypassFailClosedForRedTest 開啟時，「讀取失敗／解析失敗／格式不合／過期
            豁免皆須 fail」四條斷言各自真的失敗一次（非檔案缺失型紅燈——本檔全程不依賴檔案
            缺失或 import 失敗充當紅燈）。關閉旗標後同一組資料回到綠燈。
    群組 K：明確標註「DECISIONS.md 不存在」為受測情境（pass-no-file），非紅燈——與群組 J 的
            紅燈斷言在同一份報告內分開陳列，避免混淆（見 README「紅燈設計」一節的專門區分）。
    群組 L：PS 5.1／StrictMode 既知陷阱哨兵（單一物件 .Count、,@() 空陣列、@(函式呼叫) 陷阱）

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t19-offline-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# ⚠️ 命名為 $T19TestDir 而非 $ScriptDir——理由同 decisions-scan.ps1 內的既有註解（T-12／T-13
# 實跑抓到的真實 bug 先例）：本檔稍後 dot-source decisions-scan.ps1，該檔內部宣告未加範圍前綴的
# $T19ScriptDir（本檔特意避開撞名），若沿用泛用的 $ScriptDir 仍可能與其他 cascade 進來的檔案衝突，
# 一律用本檔獨有變數名徹底避開。
$T19TestDir = $PSScriptRoot

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

# ============================================================
# Mock 基礎設施：覆蓋 Invoke-RestMethod，任何呼叫皆丟錯——證明本檔測試全程未連網。
# decisions-scan.ps1 的 Get-DecisionsFileFetchResult／Invoke-DecisionsExemptionScan 皆支援
# -HttpGetFunc／-FetchFunction 依賴注入，本檔測試一律走注入路徑，理論上不會觸發 Invoke-RestMethod；
# 保留此覆蓋是「若真的不小心觸發，會立刻炸而非靜默連真網」的防呆（同 T-13 先例）。
# ============================================================
function Invoke-RestMethod {
    [CmdletBinding()]
    param([Parameter()] [string]$Uri, [Parameter()] $Headers, [Parameter()] [string]$Method = 'Get', [Parameter()] $Body, [Parameter()] [string]$ContentType)
    throw "MOCK-MISS：t19-offline-test.ps1 只做函式級別測試（含依賴注入的 -HttpGetFunc），不預期任何真實 HTTP 呼叫，也證明沒有真的連網：$Method $Uri"
}

. (Join-Path $T19TestDir 'decisions-scan.ps1') -FunctionsOnly
Set-StrictMode -Version Latest

$FakeHeaders = @{ 'Authorization' = 'Bearer FAKE-TOKEN-NOT-REAL'; 'Accept' = 'application/vnd.github+json' }
$AsOf = [datetime]::ParseExact('2026-08-08', 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)

$FixtureDir = Join-Path $T19TestDir 'fixtures'
$ContentExpired      = Get-Content -LiteralPath (Join-Path $FixtureDir 'decisions-expired.md') -Raw -Encoding UTF8
$ContentNotExpired   = Get-Content -LiteralPath (Join-Path $FixtureDir 'decisions-not-expired.md') -Raw -Encoding UTF8
$ContentMalformed    = Get-Content -LiteralPath (Join-Path $FixtureDir 'decisions-malformed.md') -Raw -Encoding UTF8
$ContentNoTable      = Get-Content -LiteralPath (Join-Path $FixtureDir 'decisions-no-table.md') -Raw -Encoding UTF8
$ContentNoExemptions = Get-Content -LiteralPath (Join-Path $FixtureDir 'decisions-no-exemptions.md') -Raw -Encoding UTF8

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 A：Split-MarkdownTableRow／Test-IsSeparatorRow'
Write-Host '===================================================================='

# 🚫 不可直接 @(Split-MarkdownTableRow ...)——該函式內部用逗號運算子保護陣列型別（同型陷阱見
# decisions-scan.ps1 內的 rework 註解與 ../t21/queue-common.ps1 既有先例）：先賦值，再對已賦值變數包 @()。
$rA1 = Split-MarkdownTableRow -Line '| a | b | c |'
$rA1 = @($rA1)
Assert-True -Name 'A1 Split-MarkdownTableRow 正確切三欄並去除首尾管線' -Condition (($rA1.Count -eq 3) -and ($rA1[0] -eq 'a') -and ($rA1[2] -eq 'c')) -Detail "[$($rA1 -join ', ')]"

$rA2 = Split-MarkdownTableRow -Line '|項目：X｜理由：Y| 依據 |'
$rA2 = @($rA2)
Assert-True -Name 'A2 全形｜不被當成表格分隔符（不干擾切欄）' -Condition (($rA2.Count -eq 2) -and ($rA2[0] -eq '項目：X｜理由：Y')) -Detail "[$($rA2 -join ' <=> ')]"

Assert-True -Name 'A3 Test-IsSeparatorRow(標準分隔線) True' -Condition (Test-IsSeparatorRow -Cells @('---', '---', '---'))
Assert-True -Name 'A4 Test-IsSeparatorRow(含冒號對齊) True' -Condition (Test-IsSeparatorRow -Cells @(':---', '---:', ':---:'))
Assert-True -Name 'A5 Test-IsSeparatorRow(非分隔線) False' -Condition (-not (Test-IsSeparatorRow -Cells @('日期', 'ID')))
Assert-True -Name 'A6 Test-IsSeparatorRow(空陣列) False' -Condition (-not (Test-IsSeparatorRow -Cells @()))

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 B：ConvertFrom-DecisionsTable 對五份人造 fixture 的解析（獨立預期值來源＝fixture 本身內容）'
Write-Host '===================================================================='

$rB1 = ConvertFrom-DecisionsTable -Content $ContentExpired
Assert-True -Name 'B1 decisions-expired.md ParseOk=true 且共 2 筆列' -Condition ($rB1.ParseOk -and (@($rB1.Rows).Count -eq 2)) -Detail $rB1.Detail

$rB2 = ConvertFrom-DecisionsTable -Content $ContentNotExpired
Assert-True -Name 'B2 decisions-not-expired.md ParseOk=true 且共 3 筆列' -Condition ($rB2.ParseOk -and (@($rB2.Rows).Count -eq 3)) -Detail $rB2.Detail

$rB3 = ConvertFrom-DecisionsTable -Content $ContentMalformed
Assert-True -Name 'B3 decisions-malformed.md ParseOk=true（表格結構本身合法，壞的是豁免子欄位內容，非表格結構）' -Condition ($rB3.ParseOk -and (@($rB3.Rows).Count -eq 2)) -Detail $rB3.Detail

$rB4 = ConvertFrom-DecisionsTable -Content $ContentNoTable
Assert-True -Name 'B4 decisions-no-table.md ParseOk=false（純文字，無合法表格標頭）【核心：解析失敗情境】' -Condition (-not $rB4.ParseOk) -Detail $rB4.Detail

$rB5 = ConvertFrom-DecisionsTable -Content $ContentNoExemptions
Assert-True -Name 'B5 decisions-no-exemptions.md ParseOk=true 且共 2 筆列（皆非豁免類）' -Condition ($rB5.ParseOk -and (@($rB5.Rows).Count -eq 2)) -Detail $rB5.Detail

$rB6 = ConvertFrom-DecisionsTable -Content ''
Assert-True -Name 'B6 空字串內容 ParseOk=false' -Condition (-not $rB6.ParseOk) -Detail $rB6.Detail

$rB7 = ConvertFrom-DecisionsTable -Content "| 日期 | ID | 類型 | 裁示內容 | 依據 | 裁示人 |`n| 不是分隔線 | x | y | z | w | v |"
Assert-True -Name 'B7 表頭下一行非分隔線 ParseOk=false' -Condition (-not $rB7.ParseOk) -Detail $rB7.Detail

$rB8 = ConvertFrom-DecisionsTable -Content "| 日期 | ID | 類型 | 裁示內容 | 依據 | 裁示人 |`n|---|---|---|---|---|---|`n| 2026-01-01 | X | 豁免 | 欄位數不符 | 依據 |"
Assert-True -Name 'B8 資料列欄位數與表頭不符 ParseOk=false（保守設計：整份判解析失敗，不部分解析）' -Condition (-not $rB8.ParseOk) -Detail $rB8.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 C：Get-ExemptionRows 過濾'
Write-Host '===================================================================='

# 同群組 A：先賦值再 @() 包裝，不可直接 @(Get-ExemptionRows ...)。
$rC1 = Get-ExemptionRows -Rows $rB1.Rows
$rC1 = @($rC1)
Assert-True -Name 'C1 decisions-expired.md 過濾後恰 1 筆豁免（另 1 筆拍板類被排除）' -Condition ($rC1.Count -eq 1) -Detail "Id=$($rC1[0].Id)"

$rC2 = Get-ExemptionRows -Rows $rB5.Rows
$rC2 = @($rC2)
Assert-True -Name 'C2 decisions-no-exemptions.md 過濾後恰 0 筆豁免' -Condition ($rC2.Count -eq 0)

$rC3 = Get-ExemptionRows -Rows @()
$rC3 = @($rC3)
Assert-True -Name 'C3 空列陣列輸入，回傳空陣列（陷阱③防呆）' -Condition ($rC3.Count -eq 0)

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 D：ConvertFrom-ExemptionContentCell 子欄位解析'
Write-Host '===================================================================='

$rD1 = ConvertFrom-ExemptionContentCell -Content '項目：X｜理由：Y｜範圍：Z｜期限：2099-01-01｜本項【未】處理'
Assert-True -Name 'D1 完整格式 WellFormed=true，DeadlineKind=date' -Condition ($rD1.WellFormed -and $rD1.DeadlineKind -eq 'date') -Detail $rD1.Detail

$rD2 = ConvertFrom-ExemptionContentCell -Content '項目：X｜理由：Y｜範圍：Z｜期限：永久｜本項【未】處理'
Assert-True -Name 'D2 期限＝永久，WellFormed=true，DeadlineKind=permanent' -Condition ($rD2.WellFormed -and $rD2.DeadlineKind -eq 'permanent') -Detail $rD2.Detail

$rD3 = ConvertFrom-ExemptionContentCell -Content '項目：X｜理由：Y｜範圍：Z'
Assert-True -Name 'D3 缺「期限」與「本項【未】處理」 WellFormed=false' -Condition (-not $rD3.WellFormed) -Detail $rD3.Detail
Assert-True -Name 'D3b 缺項具名含「期限」' -Condition ($rD3.Missing -contains '期限')

$rD4 = ConvertFrom-ExemptionContentCell -Content '項目：X｜理由：Y｜範圍：Z｜期限：不知道｜本項【未】處理'
Assert-True -Name 'D4 期限值無法解析 WellFormed=false，DeadlineKind=invalid' -Condition ((-not $rD4.WellFormed) -and $rD4.DeadlineKind -eq 'invalid') -Detail $rD4.Detail

$rD5 = ConvertFrom-ExemptionContentCell -Content '項目：X｜理由：Y｜範圍：Z｜期限：2099-01-01'
Assert-True -Name 'D5 缺「本項【未】處理」字樣 WellFormed=false（即使四個子欄位皆在）' -Condition ((-not $rD5.WellFormed) -and (-not $rD5.HasMarker)) -Detail $rD5.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 E：Test-ExemptionEntryExpired 三態'
Write-Host '===================================================================='

$rE1 = Test-ExemptionEntryExpired -ParsedContent $rD2 -AsOfDate $AsOf
Assert-True -Name 'E1 永久豁免 Expired=false' -Condition (-not $rE1.Expired) -Detail $rE1.Detail

$rD_future = ConvertFrom-ExemptionContentCell -Content '項目：X｜理由：Y｜範圍：Z｜期限：2099-01-01｜本項【未】處理'
$rE2 = Test-ExemptionEntryExpired -ParsedContent $rD_future -AsOfDate $AsOf
Assert-True -Name 'E2 未來期限 Expired=false（基準日=2026-08-08，期限=2099-01-01）' -Condition (-not $rE2.Expired) -Detail $rE2.Detail

$rD_past = ConvertFrom-ExemptionContentCell -Content '項目：X｜理由：Y｜範圍：Z｜期限：2026-08-01｜本項【未】處理'
$rE3 = Test-ExemptionEntryExpired -ParsedContent $rD_past -AsOfDate $AsOf
Assert-True -Name 'E3 過去期限 Expired=true（基準日=2026-08-08，期限=2026-08-01）【核心：過期判定】' -Condition $rE3.Expired -Detail $rE3.Detail

$rD_today = ConvertFrom-ExemptionContentCell -Content '項目：X｜理由：Y｜範圍：Z｜期限：2026-08-08｜本項【未】處理'
$rE4 = Test-ExemptionEntryExpired -ParsedContent $rD_today -AsOfDate $AsOf
Assert-True -Name 'E4 期限恰為基準日當天 Expired=false（期限當天仍有效，隔天才過期）' -Condition (-not $rE4.Expired) -Detail $rE4.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 F：Invoke-DecisionsFileExemptionScan——【核心】三情境 fail-closed 語意'
Write-Host '===================================================================='

$frNotFound = [pscustomobject]@{ Exists = $false; ErrorKind = 'not-found'; Content = $null; ErrorDetail = $null }
$rF1 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/not-found-repo' -FetchResult $frNotFound -AsOfDate $AsOf
Assert-True -Name 'F1 檔案不存在 Outcome=pass-no-file【驗收情境①：檔案不存在必 pass，非紅燈（見群組 K）】' -Condition ($rF1.Outcome -eq 'pass-no-file') -Detail $rF1.Detail

$frReadError = [pscustomobject]@{ Exists = $false; ErrorKind = 'read-error'; Content = $null; ErrorDetail = '模擬 403 Resource not accessible' }
$rF2 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/read-error-repo' -FetchResult $frReadError -AsOfDate $AsOf
Assert-True -Name 'F2 讀取失敗 Outcome=fail-read-error【驗收情境②：讀取失敗必 fail】' -Condition ($rF2.Outcome -eq 'fail-read-error') -Detail $rF2.Detail

$frExpired = [pscustomobject]@{ Exists = $true; ErrorKind = 'none'; Content = $ContentExpired; ErrorDetail = $null }
$rF3 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/expired-repo' -FetchResult $frExpired -AsOfDate $AsOf
Assert-True -Name 'F3 過期豁免 Outcome=fail-expired-exemption【驗收情境③：過期豁免必 fail】' -Condition ($rF3.Outcome -eq 'fail-expired-exemption') -Detail $rF3.Detail
Assert-True -Name 'F3b ExpiredEntries 具名含 EX-ALPHA-001' -Condition ((@($rF3.ExpiredEntries) | ForEach-Object { $_.Id }) -contains 'EX-ALPHA-001')

$frNotExpired = [pscustomobject]@{ Exists = $true; ErrorKind = 'none'; Content = $ContentNotExpired; ErrorDetail = $null }
$rF4 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/not-expired-repo' -FetchResult $frNotExpired -AsOfDate $AsOf
Assert-True -Name 'F4 未過期豁免（含永久＋未來期限）Outcome=pass-all-valid' -Condition ($rF4.Outcome -eq 'pass-all-valid') -Detail $rF4.Detail

$frMalformed = [pscustomobject]@{ Exists = $true; ErrorKind = 'none'; Content = $ContentMalformed; ErrorDetail = $null }
$rF5 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/malformed-repo' -FetchResult $frMalformed -AsOfDate $AsOf
Assert-True -Name 'F5 豁免條目格式不合 Outcome=fail-malformed-exemption【延伸情境：格式不合必 fail】' -Condition ($rF5.Outcome -eq 'fail-malformed-exemption') -Detail $rF5.Detail
Assert-True -Name 'F5b MalformedEntries 恰 2 筆（EX-GAMMA-001／002 皆命中）' -Condition (@($rF5.MalformedEntries).Count -eq 2)

$frNoTable = [pscustomobject]@{ Exists = $true; ErrorKind = 'none'; Content = $ContentNoTable; ErrorDetail = $null }
$rF6 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/no-table-repo' -FetchResult $frNoTable -AsOfDate $AsOf
Assert-True -Name 'F6 解析失敗 Outcome=fail-parse-error【延伸情境：解析失敗必 fail】' -Condition ($rF6.Outcome -eq 'fail-parse-error') -Detail $rF6.Detail

$frNoExemptions = [pscustomobject]@{ Exists = $true; ErrorKind = 'none'; Content = $ContentNoExemptions; ErrorDetail = $null }
$rF7 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/no-exemptions-repo' -FetchResult $frNoExemptions -AsOfDate $AsOf
Assert-True -Name 'F7 無任何豁免條目 Outcome=pass-no-exemptions' -Condition ($rF7.Outcome -eq 'pass-no-exemptions') -Detail $rF7.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 G：Test-RepoScanCoverage（純函式）＋ Invoke-DecisionsExemptionScan 整合'
Write-Host '===================================================================='

$rG1 = Test-RepoScanCoverage -Expected @('o/a', 'o/b', 'o/c') -Actual @('o/a', 'o/b', 'o/c')
Assert-True -Name 'G1 三個參與 repo 全掃 Complete=true' -Condition $rG1.Complete -Detail $rG1.Detail

$rG2 = Test-RepoScanCoverage -Expected @('o/a', 'o/b', 'o/c') -Actual @('o/a', 'o/b')
Assert-True -Name 'G2 缺一 repo（o/c）未掃 Complete=false【核心：涵蓋範圍檢查】' -Condition (-not $rG2.Complete) -Detail $rG2.Detail
Assert-True -Name 'G2b 具名缺漏 repo=o/c' -Condition ($rG2.Missing -contains 'o/c')

$rG3 = Test-RepoScanCoverage -Expected @('Owner/Repo') -Actual @('owner/repo')
Assert-True -Name 'G3 大小寫不敏感比對 Complete=true' -Condition $rG3.Complete -Detail $rG3.Detail

# 整合：三個參與 repo 分別掛不同 FetchResult（透過 -FetchFunction 依賴注入，鍵值切換三種情境）
$fetchMapG = @{
    'o/all-valid-repo' = $frNotExpired
    'o/expired-repo2'  = $frExpired
    'o/not-found-repo2' = $frNotFound
}
$fetchFnG = {
    param($Owner, $Repo, $Headers)
    $key = "$Owner/$Repo"
    if ($fetchMapG.ContainsKey($key)) { return $fetchMapG[$key] }
    throw "測試設定缺漏：未替 $key 掛 FetchResult"
}.GetNewClosure()

$rG4 = Invoke-DecisionsExemptionScan -ParticipatingRepos @('o/all-valid-repo', 'o/expired-repo2', 'o/not-found-repo2') -Headers $FakeHeaders -AsOfDate $AsOf -FetchFunction $fetchFnG
Assert-True -Name 'G4 三 repo 混合情境（合規／過期／不存在）整體 OverallPass=false（一個 repo 過期即整體 fail）' -Condition (-not $rG4.OverallPass) -Detail $rG4.Detail
Assert-True -Name 'G4b 涵蓋範圍完整（三個都掃到了）' -Condition $rG4.Coverage.Complete
Assert-True -Name 'G4c NamedGaps 具名指向 o/expired-repo2 的過期原因' -Condition ((@($rG4.NamedGaps | Where-Object { $_ -like '*o/expired-repo2*' })).Count -gt 0) -Detail ($rG4.NamedGaps -join '｜')

$fetchMapG2 = @{ 'o/only-valid' = $frNotExpired }
$fetchFnG2 = {
    param($Owner, $Repo, $Headers)
    $key = "$Owner/$Repo"
    if ($fetchMapG2.ContainsKey($key)) { return $fetchMapG2[$key] }
    throw "測試設定缺漏：未替 $key 掛 FetchResult"
}.GetNewClosure()
$rG5 = Invoke-DecisionsExemptionScan -ParticipatingRepos @('o/only-valid') -Headers $FakeHeaders -AsOfDate $AsOf -FetchFunction $fetchFnG2
Assert-True -Name 'G5 單一 repo 全合規 OverallPass=true' -Condition $rG5.OverallPass -Detail $rG5.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 H：sc:gate-fail 佇列項產生與冪等去重（唯一得產生 set-labels 者；一律走佇列）'
Write-Host '===================================================================='

$issueH1 = [pscustomobject]@{ number = 42; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-3' }) }
$labelsH1 = Get-FullLabelSetWithGateFail -Issue $issueH1
Assert-True -Name 'H1 Get-FullLabelSetWithGateFail 保留既有 label 且加入 sc:gate-fail' -Condition (($labelsH1 -contains 'sc:work') -and ($labelsH1 -contains 'sc:station-3') -and ($labelsH1 -contains 'sc:gate-fail')) -Detail "[$($labelsH1 -join ', ')]"

$issueH2 = [pscustomobject]@{ number = 43; labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:gate-fail' }) }
$labelsH2 = Get-FullLabelSetWithGateFail -Issue $issueH2
Assert-True -Name 'H2 已有 sc:gate-fail 時不重複加入（去重）' -Condition ((@($labelsH2 | Where-Object { $_ -eq 'sc:gate-fail' })).Count -eq 1) -Detail "[$($labelsH2 -join ', ')]"

$itemH3 = New-DecisionsGateFailQueueItem -Repo 'o/r' -IssueNumber 42 -Issue $issueH1 -Source 'W-t19' -Detail '測試用缺項說明'
Assert-True -Name 'H3 New-DecisionsGateFailQueueItem action=set-labels 且 payload 為完整集合' -Condition (($itemH3.action -eq 'set-labels') -and ($itemH3.payload.labels -contains 'sc:gate-fail') -and ($itemH3.payload.labels -contains 'sc:work')) -Detail "action=$($itemH3.action)"

$tmpQueuePathH = Join-Path $T19TestDir 't19-offline-test-tmp-queue.json'
if (Test-Path -LiteralPath $tmpQueuePathH) { Remove-Item -LiteralPath $tmpQueuePathH -Force }
$addH4 = Add-T19QueueItemIfAbsent -QueuePath $tmpQueuePathH -Item $itemH3
Assert-True -Name 'H4 首次加入佇列 Added=true' -Condition $addH4.Added -Detail $addH4.Detail
$addH5 = Add-T19QueueItemIfAbsent -QueuePath $tmpQueuePathH -Item $itemH3
Assert-True -Name 'H5 重複加入（同 action+target+source）Added=false（去重）' -Condition (-not $addH5.Added) -Detail $addH5.Detail
$afterH5 = @(Read-QueueFile -QueuePath $tmpQueuePathH)
Assert-True -Name 'H5b 去重後仍恰 1 筆' -Condition ($afterH5.Count -eq 1)
Assert-True -Name 'H5c 佇列項 action 恰為 set-labels（無任何直接呼叫 GitHub 寫入 API 的路徑）' -Condition ($afterH5[0].action -eq 'set-labels')
Remove-Item -LiteralPath $tmpQueuePathH -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 I：Get-DecisionsFileFetchResult（-HttpGetFunc 依賴注入，成功／404／其他錯誤）'
Write-Host '===================================================================='

$bytesI1 = [System.Text.Encoding]::UTF8.GetBytes($ContentNotExpired)
$b64I1 = [Convert]::ToBase64String($bytesI1)
$httpGetSuccess = { param($Uri, $Headers) [pscustomobject]@{ Success = $true; StatusCode = 200; Body = [pscustomobject]@{ content = $b64I1; encoding = 'base64' }; ErrorMessage = $null } }
$rI1 = Get-DecisionsFileFetchResult -Owner 'o' -Repo 'success-repo' -Headers $FakeHeaders -HttpGetFunc $httpGetSuccess
Assert-True -Name 'I1 成功讀取＋base64 解碼還原內容（含中文字元）正確' -Condition ($rI1.Exists -and $rI1.ErrorKind -eq 'none' -and $rI1.Content -eq $ContentNotExpired) -Detail "ErrorKind=$($rI1.ErrorKind)"

$httpGet404 = { param($Uri, $Headers) [pscustomobject]@{ Success = $false; StatusCode = 404; Body = $null; ErrorMessage = 'Not Found' } }
$rI2 = Get-DecisionsFileFetchResult -Owner 'o' -Repo '404-repo' -Headers $FakeHeaders -HttpGetFunc $httpGet404
Assert-True -Name 'I2 HTTP 404 ⇒ Exists=false, ErrorKind=not-found' -Condition ((-not $rI2.Exists) -and $rI2.ErrorKind -eq 'not-found') -Detail $rI2.ErrorDetail

$httpGet403 = { param($Uri, $Headers) [pscustomobject]@{ Success = $false; StatusCode = 403; Body = $null; ErrorMessage = 'Resource not accessible by integration' } }
$rI3 = Get-DecisionsFileFetchResult -Owner 'o' -Repo '403-repo' -Headers $FakeHeaders -HttpGetFunc $httpGet403
Assert-True -Name 'I3 HTTP 403 ⇒ Exists=false, ErrorKind=read-error（非 not-found，403≠404）' -Condition ((-not $rI3.Exists) -and $rI3.ErrorKind -eq 'read-error') -Detail $rI3.ErrorDetail

$httpGet500 = { param($Uri, $Headers) [pscustomobject]@{ Success = $false; StatusCode = 500; Body = $null; ErrorMessage = 'Internal Server Error' } }
$rI4 = Get-DecisionsFileFetchResult -Owner 'o' -Repo '500-repo' -Headers $FakeHeaders -HttpGetFunc $httpGet500
Assert-True -Name 'I4 HTTP 500 ⇒ ErrorKind=read-error' -Condition ($rI4.ErrorKind -eq 'read-error') -Detail $rI4.ErrorDetail

$httpGetBadB64 = { param($Uri, $Headers) [pscustomobject]@{ Success = $true; StatusCode = 200; Body = [pscustomobject]@{ content = '這不是合法的 base64！！！'; encoding = 'base64' }; ErrorMessage = $null } }
$rI5 = Get-DecisionsFileFetchResult -Owner 'o' -Repo 'bad-b64-repo' -Headers $FakeHeaders -HttpGetFunc $httpGetBadB64
Assert-True -Name 'I5 base64 解碼失敗 ⇒ ErrorKind=read-error（fail-closed，非靜默視為空內容）' -Condition ($rI5.ErrorKind -eq 'read-error') -Detail $rI5.ErrorDetail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 J：【紅燈】-BypassFailClosedForRedTest 開啟時，四條 fail-closed 斷言各自真的失敗一次'
Write-Host '===================================================================='

Write-Host '--- J-RED-1：讀取失敗本應 fail，旗標開啟後被錯誤地判為通過 ---'
$rJ_red1 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/red1' -FetchResult $frReadError -AsOfDate $AsOf -BypassFailClosedForRedTest
# 🔴 刻意不走 Assert-True／FailCount：斷言「讀取失敗必須 fail（Outcome 以 fail- 開頭）」在
# -BypassFailClosedForRedTest 開啟時應該真的失敗——證明沒有 fail-closed 分支保護的話，讀取失敗
# 這種最基本的情境會被誤判為「查不到就放行」，這正是 §6 附註明文禁止的反面教材，不是紙上談兵。
if ($rJ_red1.Outcome -like 'fail-*') {
    Write-Host "[UNEXPECTED] J-RED-1 未能重現（斷言意外通過）——需人工複查 Invoke-DecisionsFileExemptionScan 的 -BypassFailClosedForRedTest 分支。"
    [void]$script:TestResults.Add('[FAIL] J-RED-1 未如預期重現')
    $script:FailCount++
} else {
    Write-Host "[RED-CONFIRMED] 斷言『讀取失敗必須 Outcome=fail-*』如預期失敗：旗標開啟後 Outcome='$($rJ_red1.Outcome)'（非 fail-*）。證明若無 fail-closed 分支，讀取失敗會被誤判為通過——這正是 §6 附註『讀取失敗＝gate fail』要防的事。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] J-RED-1：BypassFailClosedForRedTest 開啟後讀取失敗被誤判為通過')
}

Write-Host '--- J-RED-2：過期豁免本應 fail，旗標開啟後被錯誤地判為通過 ---'
$rJ_red2 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/red2' -FetchResult $frExpired -AsOfDate $AsOf -BypassFailClosedForRedTest
if ($rJ_red2.Outcome -like 'fail-*') {
    Write-Host "[UNEXPECTED] J-RED-2 未能重現（斷言意外通過）——需人工複查。"
    [void]$script:TestResults.Add('[FAIL] J-RED-2 未如預期重現')
    $script:FailCount++
} else {
    Write-Host "[RED-CONFIRMED] 斷言『過期豁免必須 Outcome=fail-*』如預期失敗：旗標開啟後 Outcome='$($rJ_red2.Outcome)'（非 fail-*）。證明若無 fail-closed 分支，過期豁免會被誤判為通過——這正是本票標題『豁免有牙』要防的事：豁免一旦過期就不該再有效，若掃描邏輯本身可被繞過而不 fail，豁免『有牙』就是空話。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] J-RED-2：BypassFailClosedForRedTest 開啟後過期豁免被誤判為通過')
}

Write-Host '--- J-RED-3：豁免條目格式不合本應 fail，旗標開啟後被錯誤地判為通過 ---'
$rJ_red3 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/red3' -FetchResult $frMalformed -AsOfDate $AsOf -BypassFailClosedForRedTest
if ($rJ_red3.Outcome -like 'fail-*') {
    Write-Host "[UNEXPECTED] J-RED-3 未能重現（斷言意外通過）——需人工複查。"
    [void]$script:TestResults.Add('[FAIL] J-RED-3 未如預期重現')
    $script:FailCount++
} else {
    Write-Host "[RED-CONFIRMED] 斷言『格式不合必須 Outcome=fail-*』如預期失敗：旗標開啟後 Outcome='$($rJ_red3.Outcome)'（非 fail-*）。證明若無格式檢查的 fail-closed 分支，殘缺的豁免條目（缺期限、缺『本項【未】處理』）會被誤判為有效豁免。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] J-RED-3：BypassFailClosedForRedTest 開啟後格式不合被誤判為通過')
}

Write-Host '--- J-RED-4：解析失敗本應 fail，旗標開啟後被錯誤地判為通過 ---'
$rJ_red4 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/red4' -FetchResult $frNoTable -AsOfDate $AsOf -BypassFailClosedForRedTest
if ($rJ_red4.Outcome -like 'fail-*') {
    Write-Host "[UNEXPECTED] J-RED-4 未能重現（斷言意外通過）——需人工複查。"
    [void]$script:TestResults.Add('[FAIL] J-RED-4 未如預期重現')
    $script:FailCount++
} else {
    Write-Host "[RED-CONFIRMED] 斷言『解析失敗必須 Outcome=fail-*』如預期失敗：旗標開啟後 Outcome='$($rJ_red4.Outcome)'（非 fail-*）。證明讀得到位元組不代表讀得懂內容——若無解析檢查的 fail-closed 分支，格式跑掉的 DECISIONS.md 會被誤判為『內容正常、無豁免』。"
    [void]$script:TestResults.Add('[RED-CONFIRMED] J-RED-4：BypassFailClosedForRedTest 開啟後解析失敗被誤判為通過')
}

Write-Host '--- J-GREEN：關閉旗標，同一組四份資料重來一次（首尾呼應，等同群組 F2／F3／F5／F6） ---'
$rJ_green1 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/green1' -FetchResult $frReadError -AsOfDate $AsOf
Assert-True -Name 'J-GREEN-1 關閉旗標後，讀取失敗恢復 fail-read-error' -Condition ($rJ_green1.Outcome -eq 'fail-read-error') -Detail $rJ_green1.Outcome
$rJ_green2 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/green2' -FetchResult $frExpired -AsOfDate $AsOf
Assert-True -Name 'J-GREEN-2 關閉旗標後，過期豁免恢復 fail-expired-exemption' -Condition ($rJ_green2.Outcome -eq 'fail-expired-exemption') -Detail $rJ_green2.Outcome
$rJ_green3 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/green3' -FetchResult $frMalformed -AsOfDate $AsOf
Assert-True -Name 'J-GREEN-3 關閉旗標後，格式不合恢復 fail-malformed-exemption' -Condition ($rJ_green3.Outcome -eq 'fail-malformed-exemption') -Detail $rJ_green3.Outcome
$rJ_green4 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/green4' -FetchResult $frNoTable -AsOfDate $AsOf
Assert-True -Name 'J-GREEN-4 關閉旗標後，解析失敗恢復 fail-parse-error' -Condition ($rJ_green4.Outcome -eq 'fail-parse-error') -Detail $rJ_green4.Outcome

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 K：「DECISIONS.md 不存在」為受測情境（pass），明確標註非紅燈（與群組 J 區分）'
Write-Host '===================================================================='

# 本群組刻意不使用 -BypassFailClosedForRedTest：不存在的檔案本來就應該 pass，這是設計如此、
# 一次就綠，不是先紅後綠的紅燈標的。若誤把它當紅燈素材（例如「刪掉 fixture 檔看程式會不會爆」），
# 那是用「檔案缺失」冒充「斷言失敗」的紅——Spec §6 註 A 明文禁止的型態，本群組即示範正確作法：
# 直接用「Exists=false, ErrorKind=not-found」的合法 FetchResult 驗證 pass 語意，不製造任何錯誤。
$rK1 = Invoke-DecisionsFileExemptionScan -RepoLabel 'o/k1' -FetchResult $frNotFound -AsOfDate $AsOf
Assert-True -Name 'K1 檔案不存在 Outcome=pass-no-file（受測情境，非紅燈；一次驗證即綠，無需 Bypass 旗標）' -Condition ($rK1.Outcome -eq 'pass-no-file') -Detail $rK1.Detail

$rK2 = Invoke-DecisionsExemptionScan -ParticipatingRepos @('o/k2') -Headers $FakeHeaders -AsOfDate $AsOf -FetchFunction { param($Owner, $Repo, $Headers) $frNotFound }
Assert-True -Name 'K2 唯一參與 repo 的 DECISIONS.md 不存在 ⇒ 整體 OverallPass=true（不因此拖累整個 work）' -Condition $rK2.OverallPass -Detail $rK2.Detail

# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host '群組 L：PS 5.1／StrictMode 既知陷阱哨兵'
Write-Host '===================================================================='

$singleRow = @($rC1[0])
Assert-True -Name 'L1 單一物件陣列 .Count=1（陷阱①：單一物件無 .Count，須先 @() 包裝）' -Condition ($singleRow.Count -eq 1)

# 先賦值再 @() 包裝（陷阱③本體：若在此直接寫 @(Get-ExemptionRows -Rows @())，0 筆結果會被誤包成
# 「1 元素陣列，該元素是空陣列」，Count 變成 1 而非 0——本檔開發過程中實跑抓到，已於 decisions-scan.ps1
# 內對應函式加註解修正，此處測試改用安全的兩步寫法）。
$rL2 = Get-ExemptionRows -Rows @()
$rL2 = @($rL2)
Assert-True -Name 'L2 零列時回傳空陣列，安全兩步寫法包裝後 .Count=0（陷阱②③：,@() 與 @(函式呼叫) 不誤包成 1 筆）' -Condition ($rL2.Count -eq 0)

$singleFetch = Get-ExemptionRows -Rows @($rC1[0].PSObject.Copy())
Assert-True -Name 'L3 函式回傳單一元素陣列時，呼叫端對已賦值變數包 @() 仍正確（非直接 @(函式呼叫本身)）' -Condition (@($singleFetch).Count -eq 1)

# ============================================================
# 總結
# ============================================================
Write-Host ''
Write-Host '===================================================================='
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Host '===================================================================='

$reportPath = Join-Path $T19TestDir 't19-offline-test-report.txt'
$reportLines = @("t19-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", '')
$reportLines += $script:TestResults
$reportLines += ''
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
