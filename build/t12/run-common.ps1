#requires -Version 5.1
<#
.SYNOPSIS
    T-12：派工共用函式庫——選件三判準、路由表預設值、票 body 欄位解析（executor／basis／
    depends_on／不可逆動作）、產生權守門、`set-assignee`／`set-ticket-fields` 兩個新動作型別的
    schema／冪等／套用邏輯。由 run-select.ps1／run-dispatch.ps1／run-apply.ps1 dot-source 引用。

.DESCRIPTION
    地基重用（依票面指示，直接重用勿重寫）：
      - dot-source ../t10/gate-check.ps1 -FunctionsOnly：取得 Get-CurrentStation（站別歸因合法性
        的結構檢查，§3.4）、Get-TicketsForWork（票集查詢，本檔另包一份 WithRepo 版本，理由見下）。
        gate-check.ps1 內部會 cascade dot-source ../t21/queue-common.ps1，故連帶取得
        Read-PatToken／Get-GithubHeaders／Read-QueueFile／Write-QueueFile／Split-RepoString／
        Get-CurrentIssue／ConvertTo-SafeArray／ConvertTo-NormalizedText／Set-ConsoleUtf8／
        Write-Utf8BomFile 等純工具函式與 GitHub 讀取函式，本檔不重寫（DRY）。
      - 本檔**不修改** t10／t21 的任何檔案（file ownership 邊界）；`Get-TicketsForWorkWithRepo`
        是本檔獨立函式，理由：t10 的 `Get-TicketsForWork` 回傳的 issue 物件不帶「來自哪個 repo」
        的標記（t10 不需要，因為它只讀不寫），但 run 之後要對該票發 PATCH，必須知道 target.repo，
        故本檔另包一份幾乎相同查詢邏輯、多標記 RepoString 屬性（比照 T-22 patch-common.ps1
        「刻意重複小工具、不強迫跨票綁死目錄結構／回傳形狀」的先例）。

    本檔引入兩個 T-21 queue-format.md 原五型之外的新動作型別（詳細規格見 ./run-queue-ext.md，
    **不修改** t21/queue-format.md／queue-common.ps1／apply-queue.ps1，比照 T-22 `apply-patch`
    型的作法——另立套用腳本 run-apply.ps1，與 t21 共讀同一份 queue.json，只認自己的動作型別，
    其餘原樣通過）：
      - `set-assignee`：payload.assignees = 完整期望的 assignee login 陣列（可為空陣列 = 移除
        assignee，即失敗回滾的手段）。
      - `set-ticket-fields`：payload.body = issue body 的完整期望內容（覆蓋式，非差量），供 run
        寫入 executor／basis 欄位使用。

    產生權守門（§4.6「產生權」不變式，本檔內落地為真正擋得住的程式碼，非僅文件宣告）：
      run 只得產生 `set-assignee`／`set-ticket-fields`／`comment` 三型；`set-labels`／
      `close-issue`／`create-issue`／`create-milestone` 一律拒絕產生（那些恆為 gate／intake 專屬，
      見 ../t21/enqueue-guard.md 與本檔同目錄 run-queue-ext.md）。`Add-RunQueueItemGuarded` 是
      run 產生佇列項的**唯一入口**——本檔與 run-dispatch.ps1 全程不繞過它直接呼叫
      `Add-RunQueueItemIfAbsent` 產生佇列項（`-SkipEnqueueGuard` 僅供紅燈驗證使用）。

    PS 5.1 / StrictMode 三個已知陷阱，本檔全程遵守（比照 T-08／T-10／T-21／T-22 慣例）：
      ① 單一物件無 `.Count`：一律先 `$x = @($x)` 再存取 `.Count`。
      ② `,@()` 在「直接賦值、未跨函式邊界」情境下是「1 元素陣列（該元素是空陣列）」，不是空陣列；
         本檔內部直接賦值一律用 `@(...)`（不加前導逗號），只有在函式 `return` 陳述式才用
         `return ,@(...)` 或 `return ,$var` 保護陣列型別不被解卷。
      ③ `@(函式呼叫本身)` 會把「已用逗號保護好的陣列」再包一層；一律「先賦值、再對已賦值變數包 @()」。
#>

Set-StrictMode -Version Latest

$Script:ScriptDir = $PSScriptRoot
$Script:GateCheckPath = Join-Path $Script:ScriptDir '..\t10\gate-check.ps1'
if (-not (Test-Path -LiteralPath $Script:GateCheckPath)) {
    throw ("找不到 T-10 地基：{0}。請確認 t12 與 t10 為同層兄弟目錄。" -f $Script:GateCheckPath)
}
. $Script:GateCheckPath -FunctionsOnly

# ============================================================
# 路由表 v1（正典＝../station-command/assets/routing-table.md／Spec §5.1；本檔逐字轉錄供程式引用，
# 不得各自漂移——若兩者不一致，以 routing-table.md／Spec §5.1 為準）
# 站 5 雙審不在此表：兩軸 sub-agent 的 dispatch 屬 gate 職責（§2 gate 白名單「dispatch 審查／
# verifier...sub-agent」），run 不派工站 5。
# ============================================================
function Get-RunRoutingDefault {
    param([Parameter(Mandatory)][string]$Station)
    switch ($Station) {
        'sc:station-1' {
            return [pscustomobject]@{
                Executor = 'brainstormer（產題）＋ advisor（挑戰取捨）；ak-brainstorm'
                Basis    = '拷問需要「發散」與「逆向挑戰」兩種人格，同一顆腦袋兩者互相稀釋'
            }
        }
        'sc:station-2' {
            return [pscustomobject]@{
                Executor = 'planner ＋ ak-plan（需 /ak-cli-setup）'
                Basis    = 'spec 是結構化計畫產物，planner 產出格式穩定、可被站 3 直接消費'
            }
        }
        'sc:station-3' {
            return [pscustomobject]@{
                Executor = 'planner 拆票 ＋ kongming 複核；ak-project-management'
                Basis    = '垂直切片切錯要到站 4 才爆，複核成本遠低於返工'
            }
        }
        'sc:station-4' {
            return [pscustomobject]@{
                Executor = 'fullstack-developer ＋ ak-cook／ak-test；卡關轉 debugger／ak-debug'
                Basis    = '先紅後綠需要真的能跑測試的執行體'
            }
        }
        default {
            throw "Get-RunRoutingDefault：本站別不在 run 的派工職責範圍內（僅站 1-4；站 5 雙審屬 gate 職責，見 Spec §2 gate 白名單）：$Station"
        }
    }
}

# ============================================================
# 票／anchor body 欄位解析（結構性 regex 檢查，非內容品質判斷，比照 t10 Test-TicketFieldsPresence
# 「結構性存在檢查」的定位；容忍全形／半形冒號與可能的 markdown 粗體標記）
# ============================================================
function Get-ExecutorBasisDeclaration {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Body)
    $execM = [regex]::Match($Body, '(?im)^\**executor\**[:：]\s*(.+?)\s*$')
    $basisM = [regex]::Match($Body, '(?im)^\**basis\**[:：]\s*(.+?)\s*$')
    $execPresent = $execM.Success -and -not [string]::IsNullOrWhiteSpace($execM.Groups[1].Value)
    $basisPresent = $basisM.Success -and -not [string]::IsNullOrWhiteSpace($basisM.Groups[1].Value)
    return [pscustomobject]@{
        ExecutorPresent = $execPresent
        Executor        = if ($execPresent) { $execM.Groups[1].Value.Trim() } else { $null }
        BasisPresent    = $basisPresent
        Basis           = if ($basisPresent) { $basisM.Groups[1].Value.Trim() } else { $null }
    }
}

function Get-DependsOnList {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Body)
    $m = [regex]::Match($Body, '(?im)^\**depends_on\**[:：]\s*\[([^\]]*)\]')
    if (-not $m.Success) { return ,@() }
    $inner = $m.Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($inner)) { return ,@() }
    $parts = @($inner -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return ,@($parts)
}

function Get-IrreversibleDeclaration {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Body)
    $m = [regex]::Match($Body, '(?im)^\**不可逆動作\**[:：]\s*([有無])')
    if (-not $m.Success) {
        return [pscustomobject]@{
            Present = $false; Value = $null
            Detail  = '票 body 無「不可逆動作」欄位宣告（work 級項目本無此欄，或票缺此欄——後者屬 T-13 站 3 gate 職責，本檔不代為判定，亦不因缺欄而放行，見下方呼叫端保守處理）'
        }
    }
    $val = $m.Groups[1].Value
    return [pscustomobject]@{ Present = $true; Value = $val; Detail = "票 body 宣告「不可逆動作：$val」" }
}

# ============================================================
# 三判準之①②：blocker（含跨站繼承）與 depends_on 已滿足
# ============================================================
function Test-CandidateBlocked {
    param([Parameter(Mandatory)]$CandidateIssue, $AnchorIssue, [Parameter(Mandatory)][bool]$IsTicketLevel)
    $selfLabelsRaw = ConvertTo-SafeArray -RawValue $CandidateIssue.labels
    $selfLabelsRaw = @($selfLabelsRaw)
    $selfLabels = @($selfLabelsRaw | ForEach-Object { $_.name })
    $selfBlocked = $selfLabels -contains 'sc:blocked'

    $inheritedBlocked = $false
    if ($IsTicketLevel -and $null -ne $AnchorIssue) {
        $anchorLabelsRaw = ConvertTo-SafeArray -RawValue $AnchorIssue.labels
        $anchorLabelsRaw = @($anchorLabelsRaw)
        $anchorLabels = @($anchorLabelsRaw | ForEach-Object { $_.name })
        $inheritedBlocked = $anchorLabels -contains 'sc:blocked'
    }

    $blocked = $selfBlocked -or $inheritedBlocked
    $detail = if (-not $blocked) {
        '無 sc:blocked（自身與繼承皆無）'
    } elseif ($selfBlocked -and $inheritedBlocked) {
        '自身與 anchor 皆有 sc:blocked'
    } elseif ($selfBlocked) {
        '自身有 sc:blocked'
    } else {
        'anchor 有 sc:blocked（§5.3a「含跨站繼承」）'
    }
    return [pscustomobject]@{ Blocked = $blocked; Detail = $detail }
}

function Test-DependsOnSatisfied {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DependsOn,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$AllTicketsInWork
    )
    $DependsOn = @($DependsOn)
    if ($DependsOn.Count -eq 0) {
        return [pscustomobject]@{ Satisfied = $true; Detail = 'depends_on 為空，視為已滿足'; Unresolved = @(); Open = @() }
    }
    $AllTicketsInWork = @($AllTicketsInWork)
    $unresolved = @()
    $openDeps = @()
    foreach ($dep in $DependsOn) {
        $depTrim = $dep.Trim()
        if ([string]::IsNullOrWhiteSpace($depTrim)) { continue }
        $matchList = @($AllTicketsInWork | Where-Object {
            ($_.PSObject.Properties.Name -contains 'title' -and $_.title -like "*$depTrim*") -or
            ($_.PSObject.Properties.Name -contains 'body' -and $_.body -and ($_.body -match [regex]::Escape($depTrim)))
        })
        if ($matchList.Count -eq 0) {
            $unresolved += $depTrim
            continue
        }
        $match = $matchList[0]
        if ($match.state -ne 'closed') {
            $openDeps += "$depTrim（#$($match.number)，狀態=$($match.state)）"
        }
    }
    $unresolved = @($unresolved)
    $openDeps = @($openDeps)
    $satisfied = ($unresolved.Count -eq 0) -and ($openDeps.Count -eq 0)
    $detailParts = @()
    if ($unresolved.Count -gt 0) { $detailParts += "查無對應票（best-effort，僅比對標題與 body 內文字，非精確 ID 索引，誠實聲明此限制）：$($unresolved -join '、')" }
    if ($openDeps.Count -gt 0) { $detailParts += "尚未關閉：$($openDeps -join '、')" }
    $detail = if ($satisfied) { "全部 $($DependsOn.Count) 項依賴已關閉" } else { $detailParts -join '；' }
    return [pscustomobject]@{ Satisfied = $satisfied; Detail = $detail; Unresolved = $unresolved; Open = $openDeps }
}

# ============================================================
# 三判準之③：尚無在跑 executor（以 assignee 是否為空判定，即 §2「二元開工訊號」的讀端）
# ============================================================
function Test-CandidateRunning {
    param([Parameter(Mandatory)]$CandidateIssue)
    $assigneesRaw = ConvertTo-SafeArray -RawValue $CandidateIssue.assignees
    $assigneesRaw = @($assigneesRaw)
    $running = ($assigneesRaw.Count -gt 0)
    $detail = if ($running) {
        $logins = @($assigneesRaw | ForEach-Object { $_.login })
        "已有在跑 executor（assignee=[$($logins -join ', ')]）"
    } else {
        '尚無在跑 executor（assignee 為空）'
    }
    return [pscustomobject]@{ Running = $running; Detail = $detail }
}

# ============================================================
# 讀現況：某 work 的全部票，且標記來源 repo（t10 Get-TicketsForWork 不標記，本檔獨立函式，見檔頭說明）
# ============================================================
function Get-TicketsForWorkWithRepo {
    param([Parameter(Mandatory)][string]$WorkId, [Parameter(Mandatory)][string[]]$ParticipatingRepos, [Parameter(Mandatory)][hashtable]$Headers)
    $all = @()
    foreach ($repoStr in $ParticipatingRepos) {
        $r = Split-RepoString -RepoString $repoStr
        $url = "https://api.github.com/repos/$($r.Owner)/$($r.Repo)/issues?labels=sc:ticket&state=all&per_page=100"
        $raw = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get
        $issues = ConvertTo-SafeArray -RawValue $raw
        $issues = @($issues)
        foreach ($iss in $issues) {
            $msTitle = $null
            if ($iss.PSObject.Properties.Name -contains 'milestone' -and $null -ne $iss.milestone) { $msTitle = $iss.milestone.title }
            if ($msTitle -eq $WorkId) {
                $iss | Add-Member -NotePropertyName 'RepoString' -NotePropertyValue $repoStr -Force
                $all += $iss
            }
        }
    }
    return ,@($all)
}

# ============================================================
# 選件核心：三判準過濾 ＋ 依路由表定 executor／basis（含 2nd layer override 判讀）
# 站別對應：1/2/3 ⇒ work 級（可動作項＝anchor 本身，§3.2）；4 ⇒ 票級（open 且無 sc:red-proven，
# 即尚待實作的票）；5 ⇒ 票級但一律不進 frontier（雙審 dispatch 屬 gate 職責，非 run）；
# done ⇒ 無可動作項。
# ============================================================
function Select-NextActionableItem {
    param(
        [Parameter(Mandatory)]$AnchorIssue,
        [Parameter(Mandatory)][string]$Station,
        [Parameter(Mandatory)][string]$WorkId,
        [Parameter(Mandatory)][string]$PrimaryRepo,
        [Parameter(Mandatory)][string[]]$ParticipatingRepos,
        [Parameter(Mandatory)][hashtable]$Headers
    )
    if ($Station -eq 'sc:station-done') {
        return [pscustomobject]@{ HasCandidate = $false; Selected = $null; Eligible = @(); Rejected = @(); Detail = 'work 已完成態（sc:station-done），無可動作項' }
    }

    $isTicketLevel = ($Station -eq 'sc:station-4' -or $Station -eq 'sc:station-5')
    $allTicketsCache = @()
    $rawCandidates = @()

    if (-not $isTicketLevel) {
        $rawCandidates = @([pscustomobject]@{ Kind = 'anchor'; RepoString = $PrimaryRepo; Number = [int]$AnchorIssue.number; Issue = $AnchorIssue })
    } else {
        $allTicketsCache = Get-TicketsForWorkWithRepo -WorkId $WorkId -ParticipatingRepos $ParticipatingRepos -Headers $Headers
        $allTicketsCache = @($allTicketsCache)
        $openNonRedProven = @($allTicketsCache | Where-Object {
            $lbls = ConvertTo-SafeArray -RawValue $_.labels
            $lbls = @($lbls)
            $names = @($lbls | ForEach-Object { $_.name })
            ($_.state -eq 'open') -and (-not ($names -contains 'sc:red-proven'))
        })
        # 站5票（open 且已 sc:red-proven）刻意不進候選清單——雙審 dispatch 屬 gate 職責（§2 gate 白名單）
        $rawCandidates = @($openNonRedProven | Sort-Object number | ForEach-Object {
            [pscustomobject]@{ Kind = 'ticket'; RepoString = $_.RepoString; Number = [int]$_.number; Issue = $_ }
        })
    }

    $eligible = @()
    $rejected = @()

    foreach ($c in $rawCandidates) {
        $blockedChk = Test-CandidateBlocked -CandidateIssue $c.Issue -AnchorIssue $AnchorIssue -IsTicketLevel $isTicketLevel
        $runningChk = Test-CandidateRunning -CandidateIssue $c.Issue
        $bodyText = if ($c.Issue.PSObject.Properties.Name -contains 'body' -and $c.Issue.body) { $c.Issue.body } else { '' }

        $dependsChk = if ($isTicketLevel) {
            $dependsOnList = Get-DependsOnList -Body $bodyText
            Test-DependsOnSatisfied -DependsOn $dependsOnList -AllTicketsInWork $allTicketsCache
        } else {
            [pscustomobject]@{ Satisfied = $true; Detail = 'work 級項目（站 1-3），depends_on 不適用' }
        }

        $reasons = @()
        if ($blockedChk.Blocked) { $reasons += "有未解 blocker：$($blockedChk.Detail)" }
        if (-not $dependsChk.Satisfied) { $reasons += "depends_on 未滿足：$($dependsChk.Detail)" }
        if ($runningChk.Running) { $reasons += "已有在跑 executor：$($runningChk.Detail)" }
        $reasons = @($reasons)

        $execBasisDecl = Get-ExecutorBasisDeclaration -Body $bodyText
        $stationForRouting = if ($isTicketLevel) { 'sc:station-4' } else { $Station }
        $routingDefault = Get-RunRoutingDefault -Station $stationForRouting

        $invalid = $false
        $invalidReason = ''
        $effExecutor = $null
        $effBasis = $null
        $needsBodyWrite = $false
        if ($execBasisDecl.ExecutorPresent) {
            if (-not $execBasisDecl.BasisPresent) {
                $invalid = $true
                $invalidReason = '[INVALID] 票 body 已宣告 executor 但缺 basis（§3.5：無 basis 即 [INVALID]），需使用者裁示，覆寫預設須說明理由'
            } else {
                $effExecutor = $execBasisDecl.Executor
                $effBasis = $execBasisDecl.Basis
            }
        } else {
            $effExecutor = $routingDefault.Executor
            $effBasis = $routingDefault.Basis
            $needsBodyWrite = $true
        }

        $item = [pscustomobject]@{
            Kind               = $c.Kind
            RepoString         = $c.RepoString
            Number             = $c.Number
            Title              = $c.Issue.title
            Issue              = $c.Issue
            Blocked            = $blockedChk.Blocked
            DependsOnSatisfied = $dependsChk.Satisfied
            Running            = $runningChk.Running
            Invalid            = $invalid
            InvalidReason      = $invalidReason
            RoutingDefault     = $routingDefault
            DeclaredExecutor   = $execBasisDecl
            EffectiveExecutor  = $effExecutor
            EffectiveBasis     = $effBasis
            NeedsBodyWrite     = $needsBodyWrite
            RejectReasons      = $reasons
        }

        if ($reasons.Count -gt 0) { $rejected += $item } else { $eligible += $item }
    }

    $eligible = @($eligible)
    $rejected = @($rejected)
    $selected = if ($eligible.Count -gt 0) { $eligible[0] } else { $null }
    $detail = if ($null -ne $selected) {
        "選出 $($selected.Kind)：$($selected.RepoString)#$($selected.Number)（frontier 共 $($eligible.Count) 項合格，取編號最小者）"
    } else {
        "frontier 為空：候選 $($rawCandidates.Count) 項，全數被排除或無候選（見 Rejected 具名理由）"
    }

    return [pscustomobject]@{ HasCandidate = ($null -ne $selected); Selected = $selected; Eligible = $eligible; Rejected = $rejected; Detail = $detail }
}

# ============================================================
# 產生權守門（§4.6「產生權」不變式，run 只得產生三型）
# 詳細對照表見 ./run-queue-ext.md；本表是實際擋得住的程式碼版本，文件版本須與此同步。
# ============================================================
$Script:RunAllowedQueueActions = @('set-assignee', 'set-ticket-fields', 'comment')

function Test-RunProducerAllowed {
    param([Parameter(Mandatory)][string]$Action)
    $allowed = $Script:RunAllowedQueueActions -contains $Action
    $detail = if ($allowed) {
        "動作類型 '$Action' 屬 run 產生權範圍（[$($Script:RunAllowedQueueActions -join '／')]，見 run-queue-ext.md）"
    } else {
        "拒絕產生：動作類型 '$Action' 不在 run 產生權範圍內（run 僅得產生 [$($Script:RunAllowedQueueActions -join '／')]；label／開關 issue 類恆為 gate 專屬，issue／milestone 建立恆為 intake 專屬，見 ../t21/enqueue-guard.md 與 run-queue-ext.md）"
    }
    return [pscustomobject]@{ Allowed = $allowed; Detail = $detail }
}

# 佇列項冪等追加（比照 T-08／T-10 各自本地一份的既有模式：產生權自查與去重邏輯屬各 skill 自己的
# 產生階段責任，不下放共用檔改動既有 T-21 交付）
function Add-RunQueueItemIfAbsent {
    param([Parameter(Mandatory)][string]$QueuePath, [Parameter(Mandatory)]$Item)
    $existing = Read-QueueFile -QueuePath $QueuePath
    if ($null -eq $existing) { $existing = @() }
    $existing = @($existing)
    $itemTargetJson = $Item.target | ConvertTo-Json -Compress
    $dupe = @($existing | Where-Object {
        $_.action -eq $Item.action -and $_.source -eq $Item.source -and
        (($_.target | ConvertTo-Json -Compress) -eq $itemTargetJson)
    })
    if ($dupe.Count -gt 0) {
        return [pscustomobject]@{ Added = $false; Detail = '佇列中已有相同動作待落地，未重複加入' }
    }
    $updated = @($existing) + @($Item)
    Write-QueueFile -QueuePath $QueuePath -Items $updated
    return [pscustomobject]@{ Added = $true; Detail = '已加入佇列' }
}

# run 產生佇列項的唯一入口——一律經過本函式，不得繞道直接呼叫 Add-RunQueueItemIfAbsent。
function Add-RunQueueItemGuarded {
    param(
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)]$Item,
        [switch]$SkipEnqueueGuard
    )
    if (-not $SkipEnqueueGuard) {
        $guard = Test-RunProducerAllowed -Action $Item.action
        if (-not $guard.Allowed) {
            return [pscustomobject]@{ Added = $false; Blocked = $true; Detail = $guard.Detail }
        }
    } else {
        Write-Warning "⚠️⚠️⚠️ -SkipEnqueueGuard 已開啟：略過產生權自查，僅供紅燈驗證使用，正式流程絕對不得使用。"
    }
    $r = Add-RunQueueItemIfAbsent -QueuePath $QueuePath -Item $Item
    return [pscustomobject]@{ Added = $r.Added; Blocked = $false; Detail = $r.Detail }
}

# ============================================================
# 佇列項建構（新兩型：set-assignee／set-ticket-fields，見 run-queue-ext.md）
# ============================================================
function New-SetAssigneeItem {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Assignees,
        [Parameter(Mandatory)][string]$Source
    )
    return [pscustomobject]@{
        action  = 'set-assignee'
        target  = [pscustomobject]@{ repo = $Repo; issue = $IssueNumber }
        payload = [pscustomobject]@{ assignees = @($Assignees) }
        source  = $Source
    }
}

function New-SetTicketFieldsItem {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Body,
        [Parameter(Mandatory)][string]$Source
    )
    return [pscustomobject]@{
        action  = 'set-ticket-fields'
        target  = [pscustomobject]@{ repo = $Repo; issue = $IssueNumber }
        payload = [pscustomobject]@{ body = $Body }
        source  = $Source
    }
}

function New-BodyWithExecutorBasis {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$OriginalBody,
        [Parameter(Mandatory)][string]$Executor,
        [Parameter(Mandatory)][string]$Basis
    )
    $appendix = "`n`n---`n**派工資訊（由 /station-run 依路由表 v1 寫入，見 ../station-command/assets/routing-table.md）**`nexecutor: $Executor`nbasis: $Basis`n"
    return ($OriginalBody + $appendix)
}

# ============================================================
# 冪等比對（讀現況，§4.6：不設動作指紋）
# ============================================================
function Test-SetAssigneeSatisfied {
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)][hashtable]$Headers)
    $r = Split-RepoString -RepoString $Item.target.repo
    $issue = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber ([int]$Item.target.issue) -Headers $Headers
    if ($null -eq $issue) {
        return [pscustomobject]@{ Satisfied = $false; Detail = "目標 issue 不存在：$($Item.target.repo)#$($Item.target.issue)" }
    }
    $currentRaw = ConvertTo-SafeArray -RawValue $issue.assignees
    $currentRaw = @($currentRaw)
    $current = @($currentRaw | ForEach-Object { $_.login } | Sort-Object)
    $desired = @($Item.payload.assignees | Sort-Object)
    $same = ($current.Count -eq $desired.Count) -and (@(Compare-Object $current $desired -SyncWindow 0).Count -eq 0)
    $detail = if ($same) { "現有 assignees 集合已符合：[$($current -join ', ')]" } else { "現有 [$($current -join ', ')] != 期望 [$($desired -join ', ')]" }
    return [pscustomobject]@{ Satisfied = $same; Detail = $detail; CurrentAssignees = $current }
}

function Test-SetTicketFieldsSatisfied {
    param([Parameter(Mandatory)]$Item, [Parameter(Mandatory)][hashtable]$Headers)
    $r = Split-RepoString -RepoString $Item.target.repo
    $issue = Get-CurrentIssue -Owner $r.Owner -Repo $r.Repo -IssueNumber ([int]$Item.target.issue) -Headers $Headers
    if ($null -eq $issue) {
        return [pscustomobject]@{ Satisfied = $false; Detail = "目標 issue 不存在：$($Item.target.repo)#$($Item.target.issue)" }
    }
    $currentBody = if ($issue.PSObject.Properties.Name -contains 'body' -and $null -ne $issue.body) { $issue.body } else { '' }
    $curNorm = ConvertTo-NormalizedText -Text $currentBody
    $desNorm = ConvertTo-NormalizedText -Text $Item.payload.body
    $same = ($curNorm -eq $desNorm)
    $detail = if ($same) { 'body 已符合期望內容（換行正規化後比對，沿用 t21 ConvertTo-NormalizedText）' } else { 'body 與期望內容不符（換行正規化後比對）' }
    return [pscustomobject]@{ Satisfied = $same; Detail = $detail }
}

# ============================================================
# 寫入端點（PATCH .../issues/{n}，與 t21 Invoke-CloseIssueWrite 同端點、不同欄位）
# ============================================================
function Invoke-SetAssigneeWrite {
    param($Repo, $IssueNumber, $Assignees, $Headers)
    $url = "https://api.github.com/repos/$($Repo.Owner)/$($Repo.Repo)/issues/$IssueNumber"
    $body = @{ assignees = @($Assignees) } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $url -Headers $Headers -Method Patch -Body $body -ContentType 'application/json; charset=utf-8' | Out-Null
}

function Invoke-SetTicketFieldsWrite {
    param($Repo, $IssueNumber, $Body, $Headers)
    $url = "https://api.github.com/repos/$($Repo.Owner)/$($Repo.Repo)/issues/$IssueNumber"
    $bodyObj = @{ body = $Body } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $url -Headers $Headers -Method Patch -Body $bodyObj -ContentType 'application/json; charset=utf-8' | Out-Null
}

# ============================================================
# 派工核心（不含 CLI 讀取／輸出，供 run-dispatch.ps1 與測試共用）
# ============================================================
function Invoke-RunDispatch {
    param(
        [Parameter(Mandatory)]$Selected,
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)][string]$AssigneeLogin,
        [Parameter(Mandatory)][string]$WorkId,
        [switch]$SkipEnqueueGuard
    )
    $lines = @()

    if ($Selected.Invalid) {
        $lines += "拒絕派工：$($Selected.InvalidReason)"
        return [pscustomobject]@{ Status = 'invalid'; Lines = $lines }
    }

    $bodyText = if ($Selected.Issue.PSObject.Properties.Name -contains 'body' -and $Selected.Issue.body) { $Selected.Issue.body } else { '' }
    $irr = Get-IrreversibleDeclaration -Body $bodyText
    if ($irr.Present -and $irr.Value -eq '有') {
        $lines += "停手待裁示（§5.3a 停止條件①，第八欄不可逆動作＝有）：$($irr.Detail)。dispatch 前擋下，不產生任何佇列項，需使用者裁示後方可續派。"
        return [pscustomobject]@{ Status = 'irreversible-stop'; Lines = $lines }
    }
    $lines += "第八欄不可逆檢查：$($irr.Detail)（未觸發停手條件）"

    $enqueueResults = @()

    if ($Selected.NeedsBodyWrite) {
        $newBody = New-BodyWithExecutorBasis -OriginalBody $bodyText -Executor $Selected.EffectiveExecutor -Basis $Selected.EffectiveBasis
        $bodyItem = New-SetTicketFieldsItem -Repo $Selected.RepoString -IssueNumber $Selected.Number -Body $newBody -Source $WorkId
        $addBody = Add-RunQueueItemGuarded -QueuePath $QueuePath -Item $bodyItem -SkipEnqueueGuard:$SkipEnqueueGuard
        $lines += "executor／basis 欄位寫入：$($addBody.Detail)"
        $enqueueResults += $addBody
    } else {
        $lines += "executor／basis 欄位已存在於票 body（第二層覆寫，見 §5.1），無需寫入：executor='$($Selected.EffectiveExecutor)' basis='$($Selected.EffectiveBasis)'"
    }

    $assigneeItem = New-SetAssigneeItem -Repo $Selected.RepoString -IssueNumber $Selected.Number -Assignees @($AssigneeLogin) -Source $WorkId
    $addAssignee = Add-RunQueueItemGuarded -QueuePath $QueuePath -Item $assigneeItem -SkipEnqueueGuard:$SkipEnqueueGuard
    $lines += "assignee 開工訊號：$($addAssignee.Detail)"
    $enqueueResults += $addAssignee

    $enqueueResults = @($enqueueResults)
    $blockedResults = @($enqueueResults | Where-Object { $_.Blocked })
    if ($blockedResults.Count -gt 0) {
        $lines += "⚠️ 有佇列項被產生權守門擋下（見上），dispatch 中止。"
        return [pscustomobject]@{ Status = 'guard-blocked'; Lines = $lines }
    }

    $lines += ""
    $lines += "=> 佇列已就緒，請執行 ./run-apply.ps1（連同 ../t21/apply-queue.ps1）落地後，由 Commander 實際 dispatch $($Selected.EffectiveExecutor) 執行 $($Selected.RepoString)#$($Selected.Number)。"
    return [pscustomobject]@{
        Status = 'dispatch-ready'; Lines = $lines
        Target = [pscustomobject]@{ Repo = $Selected.RepoString; Issue = $Selected.Number; Executor = $Selected.EffectiveExecutor; Basis = $Selected.EffectiveBasis }
    }
}

# ============================================================
# 失敗回滾（dispatch 失敗 ⇒ 立即移除 assignee 並具名回報，§2／驗收②）
# ============================================================
function Invoke-DispatchFailureRollback {
    param(
        [Parameter(Mandatory)][string]$TargetRepo,
        [Parameter(Mandatory)][int]$TargetIssue,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string]$QueuePath,
        [Parameter(Mandatory)][string]$Source,
        [switch]$SkipRollback,
        [switch]$SkipEnqueueGuard
    )
    $lines = @()
    $lines += "dispatch 失敗具名回報：$TargetRepo#$TargetIssue — $Reason"

    if ($SkipRollback) {
        $lines += "⚠️⚠️⚠️ -SkipRollback 已開啟：略過回滾，未產生移除 assignee 的佇列項；assignee 將殘留於現況（僅供紅燈驗證，正式流程絕對不得使用）。"
        return [pscustomobject]@{ Status = 'skip-rollback-demo'; Lines = $lines; RollbackAdded = $false }
    }

    $item = New-SetAssigneeItem -Repo $TargetRepo -IssueNumber $TargetIssue -Assignees @() -Source $Source
    $add = Add-RunQueueItemGuarded -QueuePath $QueuePath -Item $item -SkipEnqueueGuard:$SkipEnqueueGuard
    $lines += "立即移除 assignee（回滾佇列項）：$($add.Detail)"
    return [pscustomobject]@{ Status = 'rolled-back'; Lines = $lines; RollbackAdded = $add.Added }
}
