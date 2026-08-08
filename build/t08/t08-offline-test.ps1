#requires -Version 5.1
<#
.SYNOPSIS
    T-08：離線 mock 測試——沙盒可跑，不連 GitHub。比照 T-21 t21-offline-test.ps1 的手法：
    覆蓋 Invoke-RestMethod 為假函式，攔截 PowerShell 5.1 對「陣列被解卷成純量／$null」的同型風險。

.DESCRIPTION
    覆蓋 intake-native.ps1 內每個會呼叫 Invoke-RestMethod 的函式，逐一驗證 0 筆／1 筆（裸物件，
    忠實重現 PS 5.1 對「JSON 陣列只有 1 個元素」的真實解卷行為）／多筆／null 形狀皆不拋錯、
    判定正確。

    ⚠️ 已知環境落差（同 t21-offline-test.ps1）：本沙盒跑 pwsh 7.4.6，使用者環境是 Windows
       PowerShell 5.1；斷言一律用 `-is [array]` 或明確型別檢查，不單靠 .Count 不拋錯判斷。

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t08-offline-test.ps1
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

function Assert-IsArrayOrNull {
    # 用於「函式合法回傳 $null 代表『查無』」的情境（例如 Find-AnchorByWorkId 找不到時回 $null，
    # 這不是陣列解卷 bug，是設計上的哨兵值）；本函式只用來檢查非 null 分支確實是陣列/物件、
    # 不是誤把 0 筆判成 1 筆。
    param([Parameter(Mandatory)][string]$Name, $Value, [Parameter(Mandatory)][bool]$ExpectNull)
    if ($ExpectNull) {
        Assert-True -Name $Name -Condition ($null -eq $Value) -Detail "預期 `$null；實際：$(if ($null -eq $Value) { '$null' } else { $Value.GetType().Name })"
    } else {
        Assert-True -Name $Name -Condition ($null -ne $Value) -Detail "預期非 `$null；實際：$(if ($null -eq $Value) { '$null' } else { '非 null' })"
    }
}

# ============================================================
# Mock 基礎設施：覆蓋 Invoke-RestMethod，依 URL 查表回傳假資料，不連網
# ============================================================
$script:MockResponses = @{}
$script:MockCallLog = New-Object System.Collections.ArrayList

function Invoke-RestMethod {
    # 定義在 dot-source intake-native.ps1（進而 dot-source queue-common.ps1）之前；
    # PowerShell 命令解析順序：別名 > 函式 > Cmdlet，同一 scope chain 內的函式會蓋過內建 cmdlet，
    # 故 intake-native.ps1／queue-common.ps1 內部呼叫的 Invoke-RestMethod 實際執行的是這個 mock（不連網）。
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
    throw "MOCK-MISS：t08-offline-test.ps1 未替這個 URL 設定假回應，無法繼續（也證明沒有真的連網）：$Method $Uri"
}

# dot-source intake-native.ps1 只載函式（-FunctionsOnly），仍須提供合法必填參數以滿足繫結；
# QueueCommonPath 指向真實 t21 地基（相對路徑，離線測試仍是純檔案操作，不觸網）。
. (Join-Path $ScriptDir 'intake-native.ps1') -WorkId 'W-offline-dummy' -PrimaryRepo 'o/r' -ParticipatingRepos @('o/r') -FunctionsOnly
Set-StrictMode -Version Latest

$FakeHeaders = @{ 'Authorization' = 'Bearer FAKE-TOKEN-NOT-REAL'; 'Accept' = 'application/vnd.github+json' }

# ============================================================
Write-Host "===================================================================="
Write-Host "群組 A：Find-AnchorByWorkId — 0 筆／1 筆（裸物件）／多筆／不匹配"
Write-Host "===================================================================="

$anchorUrlA0 = "https://api.github.com/repos/o/r0/issues?labels=sc:work&state=all&per_page=100"
$script:MockResponses[$anchorUrlA0] = $null   # 0 筆時 Invoke-RestMethod 真實回 $null
$rA0 = Find-AnchorByWorkId -Repo 'o/r0' -WorkId 'W-none' -Headers $FakeHeaders
Assert-True -Name "A0 Find-AnchorByWorkId(0 筆) 回傳 `$null（不拋錯）" -Condition ($null -eq $rA0)

$anchorUrlA1 = "https://api.github.com/repos/o/r1/issues?labels=sc:work&state=all&per_page=100"
$script:MockResponses[$anchorUrlA1] = [pscustomobject]@{ number = 5; title = 'W-single · primary anchor'; body = "work-id: W-single`nprimary-repo: o/r1`nparticipating-repos:`n- o/r1`n"; labels = @([pscustomobject]@{ name = 'sc:work' }) }
$rA1 = Find-AnchorByWorkId -Repo 'o/r1' -WorkId 'W-single' -Headers $FakeHeaders
Assert-True -Name "A1 Find-AnchorByWorkId(1 筆裸物件，命中) 不拋錯且找到" -Condition ($null -ne $rA1 -and $rA1.number -eq 5)

$rA1miss = Find-AnchorByWorkId -Repo 'o/r1' -WorkId 'W-not-this-one' -Headers $FakeHeaders
Assert-True -Name "A1b Find-AnchorByWorkId(1 筆裸物件，不命中) 回傳 `$null" -Condition ($null -eq $rA1miss)

$anchorUrlAN = "https://api.github.com/repos/o/rn/issues?labels=sc:work&state=all&per_page=100"
$script:MockResponses[$anchorUrlAN] = @(
    [pscustomobject]@{ number = 1; title = 'a'; body = "work-id: W-first`n"; labels = @() },
    [pscustomobject]@{ number = 2; title = 'b'; body = "work-id: W-second`n"; labels = @() },
    [pscustomobject]@{ number = 3; title = 'c'; body = "work-id: W-third`n"; labels = @() }
)
$rAN = Find-AnchorByWorkId -Repo 'o/rn' -WorkId 'W-second' -Headers $FakeHeaders
Assert-True -Name "AN Find-AnchorByWorkId(多筆，命中第 2 筆)" -Condition ($null -ne $rAN -and $rAN.number -eq 2)

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 B：Find-MilestoneByTitle（透過 Get-CurrentMilestonesByTitle，已在 t21 hardened） — 0/1/多筆"
Write-Host "===================================================================="

$msUrlB0 = "https://api.github.com/repos/o/rb0/milestones?state=all&per_page=100"
$script:MockResponses[$msUrlB0] = $null
$rB0 = Find-MilestoneByTitle -Repo 'o/rb0' -Title 'W-x' -Headers $FakeHeaders
Assert-True -Name "B0 Find-MilestoneByTitle(0 筆) 回傳 `$null" -Condition ($null -eq $rB0)

$msUrlB1 = "https://api.github.com/repos/o/rb1/milestones?state=all&per_page=100"
$script:MockResponses[$msUrlB1] = [pscustomobject]@{ number = 9; title = 'W-solo'; description = 'work-id: W-solo | primary-anchor: o/r1#5' }
$rB1 = Find-MilestoneByTitle -Repo 'o/rb1' -Title 'W-solo' -Headers $FakeHeaders
Assert-True -Name "B1 Find-MilestoneByTitle(1 筆裸物件，命中) 不拋錯且找到" -Condition ($null -ne $rB1 -and $rB1.number -eq 9)

$msUrlBN = "https://api.github.com/repos/o/rbn/milestones?state=all&per_page=100"
$script:MockResponses[$msUrlBN] = @(
    [pscustomobject]@{ number = 10; title = 'W-alpha'; description = 'work-id: W-alpha | primary-anchor: o/r#1' },
    [pscustomobject]@{ number = 11; title = 'W-beta'; description = 'work-id: W-beta | primary-anchor: o/r#2' }
)
$rBN = Find-MilestoneByTitle -Repo 'o/rbn' -Title 'W-beta' -Headers $FakeHeaders
Assert-True -Name "BN Find-MilestoneByTitle(多筆，命中第 2 筆)" -Condition ($null -ne $rBN -and $rBN.number -eq 11)

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 C：Get-AnchorDeclaration — 單一／多筆 participating-repos 解析"
Write-Host "===================================================================="

$issueC1 = [pscustomobject]@{ body = "work-id: W-c1`nprimary-repo: o/r1`nparticipating-repos:`n- o/r1`n`n人讀描述" }
$declC1 = Get-AnchorDeclaration -Issue $issueC1
Assert-True -Name "C1 Get-AnchorDeclaration(單一參與 repo) work-id 正確" -Condition ($declC1.WorkId -eq 'W-c1')
Assert-True -Name "C1b Get-AnchorDeclaration(單一參與 repo) participating 陣列 Count=1" -Condition (@($declC1.ParticipatingRepos).Count -eq 1 -and $declC1.ParticipatingRepos[0] -eq 'o/r1')

$issueCN = [pscustomobject]@{ body = "work-id: W-cn`nprimary-repo: o/r1`nparticipating-repos:`n- o/r1`n- o/r2`n- o/r3`n`n人讀描述多行`n第二行" }
$declCN = Get-AnchorDeclaration -Issue $issueCN
Assert-True -Name "CN Get-AnchorDeclaration(多筆參與 repo) Count=3" -Condition (@($declCN.ParticipatingRepos).Count -eq 3)
Assert-True -Name "CNb Get-AnchorDeclaration(多筆參與 repo) 內容依序正確" -Condition (($declCN.ParticipatingRepos -join ',') -eq 'o/r1,o/r2,o/r3')

$issueC0 = [pscustomobject]@{ body = $null }
$declC0 = Get-AnchorDeclaration -Issue $issueC0
Assert-True -Name "C0 Get-AnchorDeclaration(body=`$null) 不拋錯且回傳空 participating" -Condition ($null -eq $declC0.WorkId -and (@($declC0.ParticipatingRepos)).Count -eq 0)

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 D：Test-WorkIdUniqueness — 0 筆衝突／1 筆衝突／多筆衝突／排除自身"
Write-Host "===================================================================="

$uniqUrlD0 = "https://api.github.com/repos/o/rd0/issues?labels=sc:work&state=all&per_page=100"
$script:MockResponses[$uniqUrlD0] = $null
$rD0 = Test-WorkIdUniqueness -WorkId 'W-fresh' -FleetRepos @('o/rd0') -Headers $FakeHeaders
Assert-True -Name "D0 Test-WorkIdUniqueness(0 筆) Satisfied=true" -Condition $rD0.Satisfied -Detail $rD0.Detail

$uniqUrlD1 = "https://api.github.com/repos/o/rd1/issues?labels=sc:work&state=all&per_page=100"
$script:MockResponses[$uniqUrlD1] = [pscustomobject]@{ number = 42; title = 't'; body = "work-id: W-dup`n" }
$rD1 = Test-WorkIdUniqueness -WorkId 'W-dup' -FleetRepos @('o/rd1') -Headers $FakeHeaders
Assert-True -Name "D1 Test-WorkIdUniqueness(1 筆裸物件衝突) Satisfied=false" -Condition (-not $rD1.Satisfied) -Detail $rD1.Detail
Assert-True -Name "D1b Test-WorkIdUniqueness(1 筆裸物件衝突) Hits.Count=1" -Condition ((@($rD1.Hits)).Count -eq 1)

# 排除自身：同一筆若剛好是被排除的 repo+issue，應視為「無衝突」（模擬檢查自己時排除自己）
$rD1self = Test-WorkIdUniqueness -WorkId 'W-dup' -FleetRepos @('o/rd1') -ExcludeIssueNumber 42 -ExcludeRepo 'o/rd1' -Headers $FakeHeaders
Assert-True -Name "D1c Test-WorkIdUniqueness(排除自身) Satisfied=true" -Condition $rD1self.Satisfied -Detail $rD1self.Detail

$uniqUrlDNa = "https://api.github.com/repos/o/rdna/issues?labels=sc:work&state=all&per_page=100"
$uniqUrlDNb = "https://api.github.com/repos/o/rdnb/issues?labels=sc:work&state=all&per_page=100"
$script:MockResponses[$uniqUrlDNa] = @(
    [pscustomobject]@{ number = 1; title = 'a'; body = "work-id: W-multi`n" },
    [pscustomobject]@{ number = 2; title = 'b'; body = "work-id: W-other`n" }
)
$script:MockResponses[$uniqUrlDNb] = [pscustomobject]@{ number = 7; title = 'c'; body = "work-id: W-multi`n" }
$rDN = Test-WorkIdUniqueness -WorkId 'W-multi' -FleetRepos @('o/rdna', 'o/rdnb') -Headers $FakeHeaders
Assert-True -Name "DN Test-WorkIdUniqueness(跨多 repo 多筆衝突) Satisfied=false 且 Hits.Count=2" -Condition ((-not $rDN.Satisfied) -and ((@($rDN.Hits)).Count -eq 2)) -Detail $rDN.Detail

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 E：Test-NoExistingStationLabel — labels=`$null／裸物件單一 label／多筆 label"
Write-Host "===================================================================="

$issueE0 = [pscustomobject]@{ labels = $null }
$rE0 = Test-NoExistingStationLabel -Issue $issueE0
Assert-True -Name "E0 Test-NoExistingStationLabel(labels=`$null) 不拋錯且 Satisfied=true" -Condition $rE0.Satisfied -Detail $rE0.Detail

$issueE1 = [pscustomobject]@{ labels = [pscustomobject]@{ name = 'sc:work' } }  # 裸物件（非陣列），模擬只有 1 個 label 時的真實解卷形狀
$rE1 = Test-NoExistingStationLabel -Issue $issueE1
Assert-True -Name "E1 Test-NoExistingStationLabel(1 個裸物件 label，非站別) Satisfied=true" -Condition $rE1.Satisfied -Detail $rE1.Detail

$issueE1b = [pscustomobject]@{ labels = [pscustomobject]@{ name = 'sc:station-3' } }
$rE1b = Test-NoExistingStationLabel -Issue $issueE1b
Assert-True -Name "E1b Test-NoExistingStationLabel(1 個裸物件 label，是站別) Satisfied=false" -Condition (-not $rE1b.Satisfied) -Detail $rE1b.Detail

$issueEN = [pscustomobject]@{ labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:blocked' }, [pscustomobject]@{ name = 'sc:station-2' }) }
$rEN = Test-NoExistingStationLabel -Issue $issueEN
Assert-True -Name "EN Test-NoExistingStationLabel(多筆 label，含站別) Satisfied=false" -Condition (-not $rEN.Satisfied) -Detail $rEN.Detail

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 F：Get-GateIdentityReport — 正常讀值與讀取失敗兩分支皆不 fail"
Write-Host "===================================================================="

$userUrl = 'https://api.github.com/user'
$script:MockResponses[$userUrl] = [pscustomobject]@{ login = 'glennisgood3-dev' }
$rF1 = Get-GateIdentityReport -Headers $FakeHeaders
Assert-True -Name "F1 Get-GateIdentityReport(正常讀值) Satisfied=true（依 ADR-NP-009 不作 fail 條件）" -Condition $rF1.Satisfied -Detail $rF1.Detail
Assert-True -Name "F1b Get-GateIdentityReport 報告含固定字串「手動階段：無機器歸因，依 ADR-NP-009」" -Condition ($rF1.Detail -like '*手動階段：無機器歸因，依 ADR-NP-009*')

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 G：Test-GateInitCriteria 整合 — 全過情境／某條不過情境／Bypass 旗標情境"
Write-Host "===================================================================="

# --- G1：全過情境 ---
$g1AnchorIssue = [pscustomobject]@{
    number = 100
    labels = @([pscustomobject]@{ name = 'sc:work' })
    body   = "work-id: W-g1`nprimary-repo: o/g1`nparticipating-repos:`n- o/g1`n"
}
$script:MockResponses["https://api.github.com/repos/o/g1/milestones?state=all&per_page=100"] = [pscustomobject]@{ number = 1; title = 'W-g1'; description = 'work-id: W-g1 | primary-anchor: o/g1#100' }
$script:MockResponses["https://api.github.com/repos/o/g1/issues?labels=sc:work&state=all&per_page=100"] = $g1AnchorIssue
$script:MockResponses[$userUrl] = [pscustomobject]@{ login = 'glennisgood3-dev' }

$g1 = Test-GateInitCriteria -WorkId 'W-g1' -PrimaryRepo 'o/g1' -ParticipatingRepos @('o/g1') -AnchorIssue $g1AnchorIssue -FleetRepos @('o/g1') -Headers $FakeHeaders
Assert-True -Name "G1 Test-GateInitCriteria(全過情境) OverallPass=true" -Condition $g1.OverallPass -Detail ($g1.Criteria['1'].Detail + ' | ' + $g1.Criteria['2'].Detail + ' | ' + $g1.Criteria['3'].Detail + ' | ' + $g1.Criteria['4'].Detail)

# --- G2：判準④不過（anchor 已有站別 label）情境，其餘皆合格 ---
$g2AnchorIssue = [pscustomobject]@{
    number = 200
    labels = @([pscustomobject]@{ name = 'sc:work' }, [pscustomobject]@{ name = 'sc:station-3' })
    body   = "work-id: W-g2`nprimary-repo: o/g2`nparticipating-repos:`n- o/g2`n"
}
$script:MockResponses["https://api.github.com/repos/o/g2/milestones?state=all&per_page=100"] = [pscustomobject]@{ number = 2; title = 'W-g2'; description = 'work-id: W-g2 | primary-anchor: o/g2#200' }
$script:MockResponses["https://api.github.com/repos/o/g2/issues?labels=sc:work&state=all&per_page=100"] = $g2AnchorIssue

$g2 = Test-GateInitCriteria -WorkId 'W-g2' -PrimaryRepo 'o/g2' -ParticipatingRepos @('o/g2') -AnchorIssue $g2AnchorIssue -FleetRepos @('o/g2') -Headers $FakeHeaders
Assert-True -Name "G2 Test-GateInitCriteria(判準④不過：既有站別 label) OverallPass=false" -Condition (-not $g2.OverallPass) -Detail $g2.Criteria['4'].Detail
Assert-True -Name "G2b 判準①②③仍應各自獨立通過（不因④失敗而連帶誤判）" -Condition ($g2.Criteria['1'].Satisfied -and $g2.Criteria['2'].Satisfied -and $g2.Criteria['3'].Satisfied)

# --- G3：判準⑤讀取失敗，其餘皆合格 ⇒ 整體仍 OverallPass=true（⑤不算入 AND） ---
$script:MockResponses.Remove($userUrl) | Out-Null   # 移除 mock ⇒ 觸發 MOCK-MISS，模擬讀取異常路徑
$g3AnchorIssue = [pscustomobject]@{
    number = 300
    labels = @([pscustomobject]@{ name = 'sc:work' })
    body   = "work-id: W-g3`nprimary-repo: o/g3`nparticipating-repos:`n- o/g3`n"
}
$script:MockResponses["https://api.github.com/repos/o/g3/milestones?state=all&per_page=100"] = [pscustomobject]@{ number = 3; title = 'W-g3'; description = 'work-id: W-g3 | primary-anchor: o/g3#300' }
$script:MockResponses["https://api.github.com/repos/o/g3/issues?labels=sc:work&state=all&per_page=100"] = $g3AnchorIssue

$g3 = Test-GateInitCriteria -WorkId 'W-g3' -PrimaryRepo 'o/g3' -ParticipatingRepos @('o/g3') -AnchorIssue $g3AnchorIssue -FleetRepos @('o/g3') -Headers $FakeHeaders
Assert-True -Name "G3 Test-GateInitCriteria(判準⑤讀取異常) OverallPass 仍為 true（⑤不作 fail 條件，依 ADR-NP-009）" -Condition $g3.OverallPass -Detail $g3.Criteria['5'].Detail
$script:MockResponses[$userUrl] = [pscustomobject]@{ login = 'glennisgood3-dev' }   # 復原供後續測試使用

# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "群組 H：Add-QueueItemIfAbsent — 檔案不存在／已存在相同動作（去重）／新動作附加"
Write-Host "===================================================================="

$tmpQueuePath = Join-Path $ScriptDir 't08-offline-test-tmp-queue.json'
if (Test-Path -LiteralPath $tmpQueuePath) { Remove-Item -LiteralPath $tmpQueuePath -Force }

$itemH1 = [pscustomobject]@{ action = 'create-issue'; target = [pscustomobject]@{ repo = 'o/h' }; payload = [pscustomobject]@{ title = 't1' }; source = 'W-h' }
$addH1 = Add-QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemH1
Assert-True -Name "H1 Add-QueueItemIfAbsent(檔案不存在，首次加入) Added=true" -Condition $addH1.Added -Detail $addH1.Detail

$afterH1 = Read-QueueFile -QueuePath $tmpQueuePath
$afterH1 = @($afterH1)
Assert-True -Name "H1b 首次加入後檔內恰 1 筆" -Condition ($afterH1.Count -eq 1)

# 重複加入相同 action+target+source ⇒ 應被去重擋下
$addH1dupe = Add-QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemH1
Assert-True -Name "H2 Add-QueueItemIfAbsent(重複相同動作) Added=false（去重）" -Condition (-not $addH1dupe.Added) -Detail $addH1dupe.Detail
$afterH2 = Read-QueueFile -QueuePath $tmpQueuePath
$afterH2 = @($afterH2)
Assert-True -Name "H2b 去重後檔內仍恰 1 筆（未重複寫入）" -Condition ($afterH2.Count -eq 1)

# 加入不同 target 的同型動作 ⇒ 應成功附加
$itemH3 = [pscustomobject]@{ action = 'create-issue'; target = [pscustomobject]@{ repo = 'o/h2' }; payload = [pscustomobject]@{ title = 't2' }; source = 'W-h2' }
$addH3 = Add-QueueItemIfAbsent -QueuePath $tmpQueuePath -Item $itemH3
Assert-True -Name "H3 Add-QueueItemIfAbsent(不同 target，新動作) Added=true" -Condition $addH3.Added -Detail $addH3.Detail
$afterH3 = Read-QueueFile -QueuePath $tmpQueuePath
$afterH3 = @($afterH3)
Assert-True -Name "H3b 附加後檔內恰 2 筆" -Condition ($afterH3.Count -eq 2)

Remove-Item -LiteralPath $tmpQueuePath -Force -ErrorAction SilentlyContinue

# ============================================================
# 總結
# ============================================================
Write-Host ""
Write-Host "===================================================================="
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Host "===================================================================="

$reportPath = Join-Path $ScriptDir 't08-offline-test-report.txt'
$reportLines = @("t08-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", "")
$reportLines += $script:TestResults
$reportLines += ""
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
