#requires -Version 5.1
<#
.SYNOPSIS
    T-08：intake native ＋ gate 初始化路徑——本機「佇列產生器」（見 README.md §設計選擇）。

.DESCRIPTION
    設計選擇（詳細理由見 README.md）：本腳本**不直接寫 GitHub**，而是讀 GitHub 現況（讀端點正常）
    後，把該寫的動作組成 T-21 佇列格式（queue-format.md 四欄）追加進使用者本機佇列檔，
    由既有的 ../t21/apply-queue.ps1 負責真正落地（DRY：不重寫一份寫入／冪等／回驗邏輯）。

    分階段、可重複執行（idempotent producer）：
      Stage A（intake 產生權）：primary anchor 不存在 ⇒ 產生 create-issue 佇列項，停手待落地
      Stage B（intake 產生權）：anchor 已存在但某參與 repo 缺 milestone ⇒ 產生 create-milestone 佇列項，停手待落地
      Stage C（gate 產生權，§6.1 初始化路徑）：anchor＋全部 milestone 皆存在 ⇒ 跑五條判準；
        ①②③④全過（⑤依 ADR-NP-009 只檢查回報、不算入 AND 判定）⇒ 產生 set-labels（sc:station-1）佇列項

    使用者重複執行本腳本、每次落地佇列後重跑，即可推進到 anchor 已是 sc:station-1 的終態
    （此時腳本回報「已完成」，不再產生任何佇列項——冪等終態）。

.PARAMETER WorkId
    work ID，格式 W-<slug>（依 ../t07/templates.md §1）。

.PARAMETER PrimaryRepo
    <owner>/<repo>，primary anchor 所在 repo。

.PARAMETER ParticipatingRepos
    參與 repo 清單（<owner>/<repo> 陣列）；未含 PrimaryRepo 時自動補入並告知。

.PARAMETER WorkDescription
    使用者提供的工作描述原話（選填，寫入 anchor body 人讀段落）。

.PARAMETER FleetRepos
    判準③ work ID 唯一性掃描範圍；未指定時降級為 ParticipatingRepos（best-effort，見 README.md 誠實聲明）。

.PARAMETER PatPath
    PAT 檔案路徑。預設 G:\default mount\station_command-key（比照 T-07／T-21 慣例）。

.PARAMETER QueuePath
    佇列檔路徑。預設本腳本同目錄的 queue.json（與 ../t21/apply-queue.ps1 的預設不同目錄，
    套用時須以 -QueuePath 指向同一份檔案，見 README.md 使用說明）。

.PARAMETER QueueCommonPath
    T-21 共用函式庫路徑。預設同層兄弟目錄 ..\t21\queue-common.ps1（重用 T-21 地基，不重複造輪子）。

.PARAMETER BypassUniquenessGuardForRedTest
    ⚠️ 僅供 t08-test.ps1 紅燈驗證使用——開啟後判準③強制視為通過，即使真的偵測到重複 work ID。
    正式流程與一般手動執行絕對不得開啟（比照 T-21 -SkipIdempotencyCheck 的先例與命名警示風格）。

.PARAMETER FunctionsOnly
    只載入函式定義、不執行主流程（供 t08-offline-test.ps1／t08-test.ps1 dot-source 後直接呼叫
    內部函式做單元測試）。使用本旗標時仍須提供合法的必填參數值（可用任意佔位字串）以滿足參數繫結。

.EXAMPLE
    .\intake-native.ps1 -WorkId W-demo-work -PrimaryRepo owner/repo -ParticipatingRepos owner/repo
.EXAMPLE
    . .\intake-native.ps1 -WorkId W-x -PrimaryRepo o/r -ParticipatingRepos o/r -FunctionsOnly
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkId,
    [Parameter(Mandatory)][string]$PrimaryRepo,
    [Parameter(Mandatory)][string[]]$ParticipatingRepos,
    [string]$WorkDescription = '',
    [string[]]$FleetRepos = @(),
    [string]$PatPath = 'G:\default mount\station_command-key',
    [string]$QueuePath = (Join-Path $PSScriptRoot 'queue.json'),
    [string]$QueueCommonPath = (Join-Path $PSScriptRoot '..\t21\queue-common.ps1'),
    [switch]$BypassUniquenessGuardForRedTest,
    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $QueueCommonPath)) {
    throw ("找不到 T-21 共用函式庫：{0}。請確認 t08 與 t21 為同層兄弟目錄，或用 -QueueCommonPath 指定路徑。" -f $QueueCommonPath)
}
. $QueueCommonPath
Set-ConsoleUtf8

# ============================================================
# 佇列項冪等追加（避免重複產生同一動作的佇列項）
# ============================================================
function Add-QueueItemIfAbsent {
    param([Parameter(Mandatory)][string]$QueuePath, [Parameter(Mandatory)]$Item)
    $existing = Read-QueueFile -QueuePath $QueuePath
    # rework（實跑撞到的 bug，已用 pwsh 7 實測確認並修正）：$existing = ,@() 在「直接賦值、
    # 未跨函式邊界」的情境下，逗號運算子會把 @() 包成「1 元素陣列，該元素是空陣列」
    # （Count=1，不是 0！）——逗號只在「跨 return/pipeline 邊界」時才有「保護陣列不被解卷」
    # 的效果；同一層直接賦值時它反而是「建立單元素陣列」的一般語意。故此處不可用 ,@()，
    # 直接賦值 @() 才是「0 元素陣列」。
    if ($null -eq $existing) { $existing = @() }
    $existing = @($existing)
    $itemTargetJson = $Item.target | ConvertTo-Json -Compress
    $dupe = $existing | Where-Object {
        $_.action -eq $Item.action -and
        $_.source -eq $Item.source -and
        (($_.target | ConvertTo-Json -Compress) -eq $itemTargetJson)
    }
    $dupe = @($dupe)
    if ($dupe.Count -gt 0) {
        return [pscustomobject]@{ Added = $false; Detail = '佇列中已有相同動作待落地，未重複加入' }
    }
    $updated = @($existing) + @($Item)
    Write-QueueFile -QueuePath $QueuePath -Items $updated
    return [pscustomobject]@{ Added = $true; Detail = '已加入佇列' }
}

# ============================================================
# 讀現況：anchor（依 work-id 比對 body，best-effort 掃最近 100 筆 sc:work issue）
# ============================================================
function Find-AnchorByWorkId {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$WorkId, [Parameter(Mandatory)][hashtable]$Headers)
    $r = Split-RepoString -RepoString $Repo
    $url = "https://api.github.com/repos/$($r.Owner)/$($r.Repo)/issues?labels=sc:work&state=all&per_page=100"
    $raw = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
    $issues = ConvertTo-SafeArray -RawValue $raw
    $issues = @($issues)
    foreach ($iss in $issues) {
        $bodyText = ''
        if ($iss.PSObject.Properties.Name -contains 'body' -and $iss.body) { $bodyText = $iss.body }
        $m = [regex]::Match($bodyText, '(?m)^work-id:\s*(\S+)\s*$')
        if ($m.Success -and $m.Groups[1].Value -eq $WorkId) { return $iss }
    }
    return $null
}

# ============================================================
# 讀現況：milestone（依標題比對）
# ============================================================
function Find-MilestoneByTitle {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][hashtable]$Headers)
    $r = Split-RepoString -RepoString $Repo
    # rework 慣例：先賦值再包 @()，不可直接 @(函式呼叫)（Get-CurrentMilestonesByTitle 內部已用逗號
    # 保護回傳陣列型別，若在此再包一層 @(函式呼叫本身) 會把 0 筆結果錯誤包成 1 筆，見 t21 queue-common.ps1 同型註解）。
    $all = Get-CurrentMilestonesByTitle -Owner $r.Owner -Repo $r.Repo -Headers $Headers
    $all = @($all)
    $found = $all | Where-Object { $_.title -eq $Title }
    $found = @($found)
    if ($found.Count -gt 0) { return $found[0] }
    return $null
}

# ============================================================
# 解析 anchor body 的機讀宣告區（work-id／primary-repo／participating-repos）
# ============================================================
function Get-AnchorDeclaration {
    param([Parameter(Mandatory)]$Issue)
    $body = ''
    if ($Issue.PSObject.Properties.Name -contains 'body' -and $Issue.body) { $body = $Issue.body }
    $workIdMatch = [regex]::Match($body, '(?m)^work-id:\s*(\S+)\s*$')
    $primaryMatch = [regex]::Match($body, '(?m)^primary-repo:\s*(\S+)\s*$')
    $participating = @()
    $inBlock = $false
    foreach ($line in ($body -split "`n")) {
        $lineTrim = $line.TrimEnd("`r")
        if ($lineTrim -match '^participating-repos:\s*$') { $inBlock = $true; continue }
        if ($inBlock) {
            if ($lineTrim -match '^-\s*(\S+)') { $participating += $Matches[1]; continue }
            else { $inBlock = $false }
        }
    }
    $participating = @($participating)
    return [pscustomobject]@{
        WorkId              = if ($workIdMatch.Success) { $workIdMatch.Groups[1].Value } else { $null }
        PrimaryRepo         = if ($primaryMatch.Success) { $primaryMatch.Groups[1].Value } else { $null }
        ParticipatingRepos  = $participating
    }
}

# ============================================================
# 判準① milestone description 首行格式
# ============================================================
function Test-MilestoneDescriptionFormat {
    param([Parameter(Mandatory)]$Milestone, [Parameter(Mandatory)][string]$WorkId, [Parameter(Mandatory)][string]$PrimaryAnchorPointer)
    $desc = ''
    if ($Milestone.PSObject.Properties.Name -contains 'description' -and $Milestone.description) { $desc = $Milestone.description }
    $firstLine = ($desc -split "`n")[0].TrimEnd("`r")
    $expected = "work-id: $WorkId | primary-anchor: $PrimaryAnchorPointer"
    return [pscustomobject]@{ Satisfied = ($firstLine -eq $expected); Detail = "首行='$firstLine'；期望='$expected'" }
}

# ============================================================
# 判準③ work ID 全艦隊唯一（best-effort：掃描指定 FleetRepos）
# ============================================================
function Test-WorkIdUniqueness {
    param(
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][string[]]$FleetRepos,
        [int]$ExcludeIssueNumber = -1,
        [string]$ExcludeRepo = '',
        [Parameter(Mandatory)][hashtable]$Headers
    )
    $hits = @()
    foreach ($repoStr in $FleetRepos) {
        $r = Split-RepoString -RepoString $repoStr
        $url = "https://api.github.com/repos/$($r.Owner)/$($r.Repo)/issues?labels=sc:work&state=all&per_page=100"
        $raw = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
        $issues = ConvertTo-SafeArray -RawValue $raw
        $issues = @($issues)
        foreach ($iss in $issues) {
            if ($repoStr -eq $ExcludeRepo -and [int]$iss.number -eq $ExcludeIssueNumber) { continue }
            $bodyText = ''
            if ($iss.PSObject.Properties.Name -contains 'body' -and $iss.body) { $bodyText = $iss.body }
            $m = [regex]::Match($bodyText, '(?m)^work-id:\s*(\S+)\s*$')
            if ($m.Success -and $m.Groups[1].Value -eq $WorkId) {
                $hits += [pscustomobject]@{ Repo = $repoStr; Issue = $iss.number; Title = $iss.title }
            }
        }
    }
    $hits = @($hits)
    $unique = ($hits.Count -eq 0)
    $detail = if ($unique) {
        "掃描 $($FleetRepos.Count) 個 fleet repo（$($FleetRepos -join ', ')），無同 work-id 衝突"
    } else {
        $hitDesc = ($hits | ForEach-Object { "$($_.Repo)#$($_.Issue)" }) -join '、'
        "發現 $($hits.Count) 筆同 work-id 衝突：$hitDesc"
    }
    return [pscustomobject]@{ Satisfied = $unique; Detail = $detail; Hits = $hits }
}

# ============================================================
# 判準④ anchor 上無既有站別 label
# ============================================================
function Test-NoExistingStationLabel {
    param([Parameter(Mandatory)]$Issue)
    $labelsRaw = ConvertTo-SafeArray -RawValue $Issue.labels
    $labelsRaw = @($labelsRaw)
    $labels = $labelsRaw | ForEach-Object { $_.name }
    $labels = @($labels)
    $stationLabels = $labels | Where-Object { $_ -match '^sc:station-' }
    $stationLabels = @($stationLabels)
    $ok = ($stationLabels.Count -eq 0)
    $detail = if ($ok) {
        "anchor 無既有站別 label（現有：[$($labels -join ', ')]）"
    } else {
        "anchor 已有站別 label：$($stationLabels -join ', ')，須轉復位模式（Spec §3.4，T-10 範圍），本次初始化到此停止"
    }
    return [pscustomobject]@{ Satisfied = $ok; Detail = $detail; ExistingLabels = $labels }
}

# ============================================================
# 判準⑤ gate 執行身分檢查與具名回報（依 ADR-NP-009，不作 fail 條件）
# ============================================================
function Get-GateIdentityReport {
    param([Parameter(Mandatory)][hashtable]$Headers)
    try {
        $me = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $Headers -Method Get
        $login = $me.login
        $detail = "gate 執行身分實查：actor login='$login'。手動階段：無機器歸因，依 ADR-NP-009"
        return [pscustomobject]@{ Satisfied = $true; Login = $login; Detail = $detail }
    } catch {
        $detail = "gate 執行身分實查失敗（讀取 /user 發生錯誤：$($_.Exception.Message)）。手動階段：無機器歸因，依 ADR-NP-009（讀取異常不作 fail 條件，僅具名回報此異常）"
        return [pscustomobject]@{ Satisfied = $true; Login = $null; Detail = $detail }
    }
}

# ============================================================
# gate 初始化路徑：五條判準整合（Spec §6.1）
# ============================================================
function Test-GateInitCriteria {
    param(
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][string]$PrimaryRepo,
        [Parameter(Mandatory)][string[]]$ParticipatingRepos,
        [Parameter(Mandatory)]$AnchorIssue,
        [Parameter(Mandatory)][string[]]$FleetRepos,
        [Parameter(Mandatory)][hashtable]$Headers,
        [switch]$BypassUniquenessGuardForRedTest
    )
    $results = [ordered]@{}

    # 判準②
    $labelsRaw = ConvertTo-SafeArray -RawValue $AnchorIssue.labels
    $labelsRaw = @($labelsRaw)
    $labels = $labelsRaw | ForEach-Object { $_.name }
    $labels = @($labels)
    $hasWorkLabel = $labels -contains 'sc:work'
    $decl = Get-AnchorDeclaration -Issue $AnchorIssue
    $expectedSet = @($ParticipatingRepos | Sort-Object)
    $actualSet = @($decl.ParticipatingRepos | Sort-Object)
    $participatingOk = ($expectedSet.Count -eq $actualSet.Count) -and ((@(Compare-Object $expectedSet $actualSet -SyncWindow 0)).Count -eq 0)
    $c2ok = $hasWorkLabel -and ($decl.WorkId -eq $WorkId) -and ($decl.PrimaryRepo -eq $PrimaryRepo) -and $participatingOk
    $c2detail = "sc:work=$hasWorkLabel；body work-id='$($decl.WorkId)'（期望='$WorkId'）；primary-repo='$($decl.PrimaryRepo)'（期望='$PrimaryRepo'）；participating=[$($actualSet -join ', ')]（期望=[$($expectedSet -join ', ')]）"
    $results['2'] = [pscustomobject]@{ Satisfied = $c2ok; Detail = $c2detail }

    # 判準①
    $anchorPointer = "$PrimaryRepo#$($AnchorIssue.number)"
    $msDetails = @()
    $c1ok = $true
    foreach ($repo in $ParticipatingRepos) {
        $ms = Find-MilestoneByTitle -Repo $repo -Title $WorkId -Headers $Headers
        if ($null -eq $ms) {
            $c1ok = $false
            $msDetails += "$repo：milestone 不存在"
            continue
        }
        $chk = Test-MilestoneDescriptionFormat -Milestone $ms -WorkId $WorkId -PrimaryAnchorPointer $anchorPointer
        if (-not $chk.Satisfied) { $c1ok = $false }
        $msDetails += "$repo：$($chk.Detail)"
    }
    $results['1'] = [pscustomobject]@{ Satisfied = $c1ok; Detail = ($msDetails -join '｜') }

    # 判準③
    $uniq = Test-WorkIdUniqueness -WorkId $WorkId -FleetRepos $FleetRepos -ExcludeIssueNumber ([int]$AnchorIssue.number) -ExcludeRepo $PrimaryRepo -Headers $Headers
    $c3ok = if ($BypassUniquenessGuardForRedTest) { $true } else { $uniq.Satisfied }
    $c3detail = $uniq.Detail
    if ($BypassUniquenessGuardForRedTest) {
        $c3detail += "（⚠️ -BypassUniquenessGuardForRedTest 已開啟，本次判定強制視為通過，僅供 t08-test.ps1 紅燈驗證使用，正式流程絕對不得使用）"
    }
    $results['3'] = [pscustomobject]@{ Satisfied = $c3ok; Detail = $c3detail; RawUniquenessCheck = $uniq }

    # 判準④
    $c4 = Test-NoExistingStationLabel -Issue $AnchorIssue
    $results['4'] = $c4

    # 判準⑤（永不算入 AND 判定）
    $idReport = Get-GateIdentityReport -Headers $Headers
    $results['5'] = $idReport

    $overallPass = $results['1'].Satisfied -and $results['2'].Satisfied -and $results['3'].Satisfied -and $results['4'].Satisfied

    return [pscustomobject]@{ OverallPass = $overallPass; Criteria = $results; IdentityNote = $idReport.Detail }
}

# ============================================================
# 主流程
# ============================================================
function Invoke-IntakeNativeFlow {
    if (-not ($WorkId -match '^W-[a-z0-9-]+$')) {
        throw ("WorkId 格式錯誤（須符合 ^W-[a-z0-9-]+`$，依 ../t07/templates.md §1 慣例）：{0}" -f $WorkId)
    }

    $script:ParticipatingRepos = @($ParticipatingRepos | Select-Object -Unique)
    if ($script:ParticipatingRepos -notcontains $PrimaryRepo) {
        Write-Host "注意：ParticipatingRepos 未含 PrimaryRepo，已自動補入（依 Spec §3.1「含 primary repo 自身在內」）。"
        $script:ParticipatingRepos = @($script:ParticipatingRepos + @($PrimaryRepo))
    }

    $script:FleetRepos = $FleetRepos
    if (@($script:FleetRepos).Count -eq 0) {
        $script:FleetRepos = @($script:ParticipatingRepos)
        Write-Host "注意：未指定 -FleetRepos，work ID 唯一性掃描範圍降級為本次參與 repo 集合（best-effort，見 README.md 誠實聲明）：$($script:FleetRepos -join ', ')"
    }

    $Token = Read-PatToken -PatPath $PatPath
    $Headers = Get-GithubHeaders -Token $Token -UserAgent 'station-command-t08-intake-native'

    $reportLines = New-Object System.Collections.ArrayList
    function Rep([string]$s) { Write-Host $s; [void]$reportLines.Add($s) }

    Rep "intake-native 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
    Rep "WorkId=$WorkId  PrimaryRepo=$PrimaryRepo  ParticipatingRepos=[$($script:ParticipatingRepos -join ', ')]"
    Rep ""

    # --- Stage A：anchor（intake 產生權） ---
    Rep "--- Stage A（intake 產生權）：primary anchor ---"
    $anchor = Find-AnchorByWorkId -Repo $PrimaryRepo -WorkId $WorkId -Headers $Headers
    if ($null -eq $anchor) {
        $bodyParts = @()
        $bodyParts += "work-id: $WorkId"
        $bodyParts += "primary-repo: $PrimaryRepo"
        $bodyParts += "participating-repos:"
        foreach ($p in $script:ParticipatingRepos) { $bodyParts += "- $p" }
        $bodyParts += ""
        if ($WorkDescription) { $bodyParts += $WorkDescription }
        $bodyText = ($bodyParts -join "`n")
        $item = [pscustomobject]@{
            action  = 'create-issue'
            target  = [pscustomobject]@{ repo = $PrimaryRepo }
            payload = [pscustomobject]@{ title = "$WorkId · primary anchor"; body = $bodyText; labels = @('sc:work'); milestone = $null }
            source  = $WorkId
        }
        $addResult = Add-QueueItemIfAbsent -QueuePath $QueuePath -Item $item
        Rep "anchor 尚不存在於 GitHub；$($addResult.Detail)（動作類型 create-issue，產生權=intake）。"
        Rep ""
        Rep "=> 請先執行 ..\t21\apply-queue.ps1 -QueuePath `"$QueuePath`" 落地 anchor，落地後重跑本腳本以繼續。"
        Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'intake-native-report.txt') -Content ($reportLines -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'A-pending'; OverallPass = $false }
    }
    Rep "anchor 已存在：$PrimaryRepo#$($anchor.number)"
    Rep ""

    # --- Stage B：milestones（intake 產生權） ---
    Rep "--- Stage B（intake 產生權）：milestones ---"
    $anchorPointer = "$PrimaryRepo#$($anchor.number)"
    $pendingAny = $false
    foreach ($repo in $script:ParticipatingRepos) {
        $ms = Find-MilestoneByTitle -Repo $repo -Title $WorkId -Headers $Headers
        if ($null -eq $ms) {
            $desc = "work-id: $WorkId | primary-anchor: $anchorPointer"
            $msItem = [pscustomobject]@{
                action  = 'create-milestone'
                target  = [pscustomobject]@{ repo = $repo }
                payload = [pscustomobject]@{ title = $WorkId; description = $desc }
                source  = $WorkId
            }
            $violations = Get-DescriptionLengthViolations -Payload $msItem.payload
            $violations = @($violations)
            if ($violations.Count -gt 0) {
                Rep "$repo：milestone description 逾 100 字元（實際 $($desc.Length) 字元），已擋下未加入佇列。請縮短 WorkId slug 後重試。"
                $pendingAny = $true
                continue
            }
            $addResult = Add-QueueItemIfAbsent -QueuePath $QueuePath -Item $msItem
            Rep "$repo`：milestone 尚不存在；$($addResult.Detail)。"
            $pendingAny = $true
        } else {
            Rep "$repo`：milestone 已存在（#$($ms.number)）。"
        }
    }
    Rep ""
    if ($pendingAny) {
        Rep "=> 尚有 milestone 待落地或有逾長 description 待處理，請先執行 ..\t21\apply-queue.ps1 -QueuePath `"$QueuePath`" 落地後重跑本腳本以繼續。"
        Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'intake-native-report.txt') -Content ($reportLines -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'B-pending'; OverallPass = $false }
    }

    # --- Stage C：gate 初始化路徑五條判準（gate 產生權） ---
    Rep "--- Stage C（gate 產生權，Spec §6.1 初始化路徑）：五條判準 ---"
    $existingLabelsRaw = ConvertTo-SafeArray -RawValue $anchor.labels
    $existingLabelsRaw = @($existingLabelsRaw)
    $existingLabels = $existingLabelsRaw | ForEach-Object { $_.name }
    $existingLabels = @($existingLabels)
    if ($existingLabels -contains 'sc:station-1') {
        Rep "anchor 已是 sc:station-1，本工作已完成初始化，無需動作（冪等終態）。"
        Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'intake-native-report.txt') -Content ($reportLines -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'Done'; OverallPass = $true }
    }

    $gateResult = Test-GateInitCriteria -WorkId $WorkId -PrimaryRepo $PrimaryRepo -ParticipatingRepos $script:ParticipatingRepos `
        -AnchorIssue $anchor -FleetRepos $script:FleetRepos -Headers $Headers -BypassUniquenessGuardForRedTest:$BypassUniquenessGuardForRedTest

    foreach ($k in '1', '2', '3', '4') {
        $c = $gateResult.Criteria[$k]
        $mark = if ($c.Satisfied) { '✓' } else { '✗' }
        Rep "判準$k`：$mark — $($c.Detail)"
    }
    Rep "判準5（身分檢查，依 ADR-NP-009 不作 fail 條件）：$($gateResult.Criteria['5'].Detail)"
    Rep ""

    if (-not $gateResult.OverallPass) {
        Rep "=> gate 初始化未過，未落 sc:station-1，具名缺項如上。"
        Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'intake-native-report.txt') -Content ($reportLines -join [Environment]::NewLine)
        return [pscustomobject]@{ Stage = 'C-fail'; OverallPass = $false; GateResult = $gateResult }
    }

    $desiredLabels = @($existingLabels + @('sc:station-1') | Select-Object -Unique)
    $labelItem = [pscustomobject]@{
        action  = 'set-labels'
        target  = [pscustomobject]@{ repo = $PrimaryRepo; issue = $anchor.number }
        payload = [pscustomobject]@{ labels = $desiredLabels }
        source  = $WorkId
    }
    $addResult = Add-QueueItemIfAbsent -QueuePath $QueuePath -Item $labelItem
    Rep "五條判準核心四條全過（⑤依 ADR-NP-009 檢查回報不作 fail）；$($addResult.Detail)（動作類型 set-labels，產生權=gate）。"
    Rep "=> 請執行 ..\t21\apply-queue.ps1 -QueuePath `"$QueuePath`" 落地 sc:station-1。"

    Write-Utf8BomFile -Path (Join-Path $PSScriptRoot 'intake-native-report.txt') -Content ($reportLines -join [Environment]::NewLine)
    return [pscustomobject]@{ Stage = 'C-pass'; OverallPass = $true; GateResult = $gateResult }
}

if (-not $FunctionsOnly) {
    $result = Invoke-IntakeNativeFlow
    switch ($result.Stage) {
        'Done'      { exit 0 }
        'C-pass'    { exit 0 }
        'A-pending' { exit 2 }
        'B-pending' { exit 2 }
        'C-fail'    { exit 1 }
        default     { exit 1 }
    }
}
