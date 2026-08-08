#requires -Version 5.1
<#
.SYNOPSIS
    T-22：紅→綠動態測試，外加驗收條件①②③④的端對端證明。全程呼叫真正的 apply-patch.ps1
    子行程（非只測函式庫），且全程只用本機 git，**不連 GitHub**，故本檔可在沙盒 100% 真實執行
    （這是 T-22 相對 T-21 的優勢：T-21 的動態測試依賴 GitHub PAT，本票完全不需要）。

.DESCRIPTION
    段落 A（紅→綠，主線）：對一份**必然衝突**的 patch，先用 `-SkipDryRunCheck`（跳過乾跑、
    改用 `git apply --reject`）強制套用 ⇒ 斷言「工作區不得留下衝突標記／不得半套」**真的失敗**
    （已實測：--reject 會讓未衝突檔案被真的改掉、衝突檔案留下 .rej，見 patch-format.md §9）；
    再用正常模式（有乾跑）套用同一份衝突 patch ⇒ 同一斷言通過（正向乾跑攔下、完全不寫入）。

    段落 B（紅→綠，驗收條件③「未套用前不得算交付」）：對比「若信任 executor 自陳完成」
    （naive baseline，僅本測試定義，不是正式邏輯）與「真正的 Test-PatchDelivered（只認佇列
    現況與落地紀錄）」——同一情境（patch 仍在佇列，executor 自陳 'done'）下，naive baseline
    誤判為已交付 ⇒ 斷言「不得因 executor 自陳而判定已交付」對 naive baseline **真的失敗**；
    對真正的 Test-PatchDelivered 通過。

    段落 C／D／E：驗收①（乾淨套用內容相符）／②（冪等雙套不重複）／④（衝突具名回報且留佇列、
    不部分套用），全程呼叫真正的 apply-patch.ps1 子行程驗證 CLI 契約。

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t22-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir 'patch-common.ps1')
Set-StrictMode -Version Latest

$script:Log = New-Object System.Collections.ArrayList
function Log { param([string]$Msg) Write-Host $Msg; [void]$script:Log.Add($Msg) }
function Section { param([string]$Name) Log ""; Log "===================================================================="; Log $Name; Log "====================================================================" }

$script:FailCount = 0
function Assert-True {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][bool]$Condition, [string]$Detail = '')
    if ($Condition) { Log "[PASS] $Name $Detail" } else { Log "[FAIL] $Name $Detail"; $script:FailCount++ }
}

function New-TempDir {
    param([string]$Prefix)
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "$Prefix-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function New-TempGitRepo {
    param([string]$Prefix)
    $dir = New-TempDir -Prefix $Prefix
    Invoke-GitCommand -Worktree $dir -GitArgs @('init', '-q') | Out-Null
    Invoke-GitCommand -Worktree $dir -GitArgs @('config', 'user.email', 't22-test@example.com') | Out-Null
    Invoke-GitCommand -Worktree $dir -GitArgs @('config', 'user.name', 't22-test') | Out-Null
    return $dir
}

# 呼叫真正的 apply-patch.ps1 子行程（非 dot-source，驗證 CLI 契約與 exit code）
function Invoke-ApplyPatchScript {
    param([Parameter(Mandatory)][hashtable]$ScriptParams)
    $scriptPath = Join-Path $ScriptDir 'apply-patch.ps1'
    # 🔑 用 *>&1（全部串流併入成功串流）而非 2>&1——apply-patch.ps1 的進度行是 Write-Host，
    # 落在 Information 串流（6），2>&1 只併 stderr（2），不會併到 Write-Host 輸出，
    # 之前用 2>&1 曾導致斷言誤判「輸出缺少某狀態字串」（實際上有印，只是沒被捕捉到變數）。
    $rawOutput = & $scriptPath @ScriptParams *>&1
    $exitCode = $LASTEXITCODE
    $rawOutput = @($rawOutput)
    $lines = @($rawOutput | ForEach-Object { $_.ToString() })
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($lines -join [Environment]::NewLine) }
}

function New-ConflictScenario {
    # 產生一組「必然衝突」的 worktree + patch：worktree 目前是 "Hello`nEveryone"，
    # patch 期望的 base 是 "Hello`nWorld"，第二行 context 不吻合 ⇒ 正向乾跑必敗。
    param([string]$Prefix)
    $baseRepo = New-TempGitRepo -Prefix "$Prefix-basegen"
    Set-Content -LiteralPath (Join-Path $baseRepo 'greeting.txt') -Value "Hello`nWorld" -NoNewline
    Invoke-GitCommand -Worktree $baseRepo -GitArgs @('add', '-A') | Out-Null
    Invoke-GitCommand -Worktree $baseRepo -GitArgs @('commit', '-q', '-m', 'base') | Out-Null
    Set-Content -LiteralPath (Join-Path $baseRepo 'greeting.txt') -Value "Hello, Universe`nWorld" -NoNewline
    $diff = Invoke-GitCommand -Worktree $baseRepo -GitArgs @('diff', '--no-color', '--binary', '--', 'greeting.txt')

    $worktree = New-TempGitRepo -Prefix "$Prefix-target"
    Set-Content -LiteralPath (Join-Path $worktree 'greeting.txt') -Value "Hello`nEveryone" -NoNewline
    Invoke-GitCommand -Worktree $worktree -GitArgs @('add', '-A') | Out-Null
    Invoke-GitCommand -Worktree $worktree -GitArgs @('commit', '-q', '-m', 'diverged') | Out-Null

    $queueDir = New-TempDir -Prefix "$Prefix-queue"
    $patchPath = Join-Path $queueDir 'conflict.patch'
    [System.IO.File]::WriteAllText($patchPath, $diff.Output + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    $sha = Get-FileSha256Hex -Path $patchPath
    $queuePath = Join-Path $queueDir 'queue.json'
    Write-QueueFile -QueuePath $queuePath -Items @(
        [pscustomobject]@{
            action  = 'apply-patch'
            target  = [pscustomobject]@{ repo = 'owner/repo'; worktree = $worktree }
            payload = [pscustomobject]@{ patchFile = 'conflict.patch'; sha256 = $sha; files = @('greeting.txt') }
            source  = 'T-CONFLICT-DEMO'
        }
    )
    return [pscustomobject]@{ Worktree = $worktree; QueuePath = $queuePath; LogPath = (Join-Path $queueDir 'applied-patches.log') }
}

# ============================================================
Section "段落 A（紅→綠）：-SkipDryRunCheck 對必然衝突 patch 強制套用 ⇒ 半套斷言"
# ============================================================

Log "--- A-RED：SkipDryRunCheck 開啟，強制套用必然衝突的 patch ---"
$scenA_red = New-ConflictScenario -Prefix 'a-red'
$redResult = Invoke-ApplyPatchScript -ScriptParams @{ QueuePath = $scenA_red.QueuePath; AppliedLogPath = $scenA_red.LogPath; SkipDryRunCheck = $true }
Log $redResult.Output

$redRejCheck = Test-WorktreeHasRejectArtifacts -Worktree $scenA_red.Worktree
$redFileContent = Get-Content -LiteralPath (Join-Path $scenA_red.Worktree 'greeting.txt') -Raw
$redInvariantHolds = (-not $redRejCheck.HasRejects) -and ($redFileContent -eq "Hello`nEveryone")
# 🔴 刻意不走 Assert-True／$script:FailCount：這裡的斷言「工作區不得留下衝突標記／不得半套」
# 在 SkipDryRunCheck 模式下**應該失敗**（那正是紅燈的定義），若真的失敗才是符合預期，
# 不應該因此把整支測試判定為 FAIL（比照 T-21 t21-dynamic-test.ps1 對 RED 段落的處理方式：
# 用明確的 [RED-CONFIRMED]／[UNEXPECTED] 分支，只有「該紅卻沒紅」才計入整體失敗）。
if (-not $redInvariantHolds) {
    Log "[RED-CONFIRMED] 斷言「工作區不得留下衝突標記／不得半套」如預期失敗：HasRejects=$($redRejCheck.HasRejects)，檔案內容='$redFileContent'。SkipDryRunCheck 模式下 git apply --reject 確實留下 .rej 殘留（半套的具體樣貌），證明「不設乾跑保護」是真的危險，不是紙上談兵。"
} else {
    Log "[UNEXPECTED] 紅燈段落未能重現半套情況（斷言意外通過）——需要人工複查 New-ConflictScenario／apply-patch.ps1 的 SkipDryRunCheck 邏輯是否有變化。"
    $script:FailCount++
}

Log ""
Log "--- A-GREEN：正常模式（無 SkipDryRunCheck），對同一份必然衝突 patch 重新產生場景並套用 ---"
$scenA_green = New-ConflictScenario -Prefix 'a-green'
$greenResult = Invoke-ApplyPatchScript -ScriptParams @{ QueuePath = $scenA_green.QueuePath; AppliedLogPath = $scenA_green.LogPath }
Log $greenResult.Output

$greenRejCheck = Test-WorktreeHasRejectArtifacts -Worktree $scenA_green.Worktree
$greenFileContent = Get-Content -LiteralPath (Join-Path $scenA_green.Worktree 'greeting.txt') -Raw
$greenInvariantHolds = (-not $greenRejCheck.HasRejects) -and ($greenFileContent -eq "Hello`nEveryone")
Assert-True -Name "A-GREEN 斷言「工作區不得留下衝突標記／不得半套」（正常模式）" -Condition $greenInvariantHolds `
    -Detail "HasRejects=$($greenRejCheck.HasRejects)，檔案內容='$greenFileContent'"

# 🚫 不可 @(函式呼叫本身)——先賦值再包 @() 一層（同 T-21 queue-common.ps1 的陣列解卷防禦，
# 已實測：直接 @(Read-QueueFile ...) 會把 0 筆結果錯誤包成 1 筆，見本檔除錯記錄）。
$greenQueueAfterRaw = Read-QueueFile -QueuePath $scenA_green.QueuePath
$greenQueueAfter = @($greenQueueAfterRaw)
Assert-True -Name "A-GREEN 衝突項目仍留在佇列（未被誤標為已套用）" -Condition ($greenQueueAfter.Count -eq 1) -Detail "剩餘筆數=$($greenQueueAfter.Count)"
Assert-True -Name "A-GREEN exit code 非 0（有失敗項目）" -Condition ($greenResult.ExitCode -ne 0) -Detail "ExitCode=$($greenResult.ExitCode)"

# ============================================================
Section "段落 B（紅→綠）：驗收條件③——不得因 executor 自陳完成就判定已交付"
# ============================================================

$scenB = New-ConflictScenario -Prefix 'b-delivery'   # 借用衝突場景：patch 保證「仍在佇列、未套用」

function Test-DeliveredBySelfReport {
    # ⚠️ 僅本測試定義的 naive baseline，代表「若信任 executor 自陳」的錯誤實作，
    # 用來對照真正的 Test-PatchDelivered——不是正式程式碼的一部分，不會被 apply-patch.ps1 使用。
    param([string]$ExecutorSelfReport)
    return ($ExecutorSelfReport -eq 'done')
}

$executorClaim = 'done'   # executor 回報「我做完了」——但 patch 其實還在佇列裡，尚未真正套用成功

Log "--- B-RED：naive self-report baseline ---"
$naiveDelivered = Test-DeliveredBySelfReport -ExecutorSelfReport $executorClaim
# 🔴 同 A 段：naive baseline 下「不得因自陳判定已交付」這條斷言應該失敗才是正確的紅，
# 不走 Assert-True／FailCount，改用明確的 RED-CONFIRMED／UNEXPECTED 分支。
if ($naiveDelivered) {
    Log "[RED-CONFIRMED] 斷言「executor 自陳完成不得被當成已交付」如預期失敗：naive baseline 只看 executor 自陳='$executorClaim'，誤判 Delivered=true。證明『只信任 executor 自陳』會誤判為已交付，驗收條件③正是為了防這個錯誤模式。"
} else {
    Log "[UNEXPECTED] naive baseline 意外沒有誤判——需要人工複查 Test-DeliveredBySelfReport 定義是否有變化。"
    $script:FailCount++
}

Log ""
Log "--- B-GREEN：真正的 Test-PatchDelivered（只認佇列現況與落地紀錄，不看 executor 自陳） ---"
$realDelivered = Test-PatchDelivered -Source 'T-CONFLICT-DEMO' -QueuePath $scenB.QueuePath -AppliedLogPath $scenB.LogPath
Assert-True -Name "B-GREEN 斷言「executor 自陳完成不得被當成已交付」（真正實作）" -Condition (-not $realDelivered.Delivered) -Detail $realDelivered.Reason

# ============================================================
Section "段落 C：驗收① — 乾淨套用後工作區內容與 patch 宣告目標相符"
# ============================================================

$repoC = New-TempGitRepo -Prefix 'c-clean'
Set-Content -LiteralPath (Join-Path $repoC 'greeting.txt') -Value "Hello`nWorld" -NoNewline
Invoke-GitCommand -Worktree $repoC -GitArgs @('add', '-A') | Out-Null
Invoke-GitCommand -Worktree $repoC -GitArgs @('commit', '-q', '-m', 'base') | Out-Null
Set-Content -LiteralPath (Join-Path $repoC 'greeting.txt') -Value "Hello, Universe`nWorld" -NoNewline
$diffC = Invoke-GitCommand -Worktree $repoC -GitArgs @('diff', '--no-color', '--binary', '--', 'greeting.txt')
Invoke-GitCommand -Worktree $repoC -GitArgs @('checkout', '--', 'greeting.txt') | Out-Null

$queueDirC = New-TempDir -Prefix 'c-queue'
$patchC = Join-Path $queueDirC 'T-14-0001.patch'
[System.IO.File]::WriteAllText($patchC, $diffC.Output + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
$shaC = Get-FileSha256Hex -Path $patchC
$queuePathC = Join-Path $queueDirC 'queue.json'
$logPathC = Join-Path $queueDirC 'applied-patches.log'
Write-QueueFile -QueuePath $queuePathC -Items @(
    [pscustomobject]@{
        action = 'apply-patch'
        target = [pscustomobject]@{ repo = 'owner/repo'; worktree = $repoC }
        payload = [pscustomobject]@{ patchFile = 'T-14-0001.patch'; sha256 = $shaC; files = @('greeting.txt') }
        source = 'T-14'
    }
)

$deliveredBeforeC = Test-PatchDelivered -Source 'T-14' -QueuePath $queuePathC -AppliedLogPath $logPathC
Assert-True -Name "C0 套用前查交付狀態 ⇒ 未交付" -Condition (-not $deliveredBeforeC.Delivered) -Detail $deliveredBeforeC.Reason

$resultC = Invoke-ApplyPatchScript -ScriptParams @{ QueuePath = $queuePathC; AppliedLogPath = $logPathC }
Log $resultC.Output
Assert-True -Name "C1 apply-patch.ps1 exit code = 0" -Condition ($resultC.ExitCode -eq 0) -Detail "ExitCode=$($resultC.ExitCode)"

$contentC = Get-Content -LiteralPath (Join-Path $repoC 'greeting.txt') -Raw
Assert-True -Name "C2 套用後檔案內容與 patch 宣告目標逐字相符" -Condition ($contentC -eq "Hello, Universe`nWorld") -Detail "實際='$contentC'"

$queueAfterCRaw = Read-QueueFile -QueuePath $queuePathC
$queueAfterC = @($queueAfterCRaw)
Assert-True -Name "C3 套用成功後該項目已出列" -Condition ($queueAfterC.Count -eq 0) -Detail "剩餘筆數=$($queueAfterC.Count)"

$deliveredAfterC = Test-PatchDelivered -Source 'T-14' -QueuePath $queuePathC -AppliedLogPath $logPathC
Assert-True -Name "C4 套用後查交付狀態 ⇒ 已交付" -Condition $deliveredAfterC.Delivered -Detail $deliveredAfterC.Reason

# ============================================================
Section "段落 D：驗收② — 同一 patch 套用兩次，第二次因現況已符而跳過"
# ============================================================

# 把已出列的項目重新貼回佇列（模擬使用者不小心把同一筆重新加回），驗證重跑會跳過而非重複套用/報衝突
Write-QueueFile -QueuePath $queuePathC -Items @(
    [pscustomobject]@{
        action = 'apply-patch'
        target = [pscustomobject]@{ repo = 'owner/repo'; worktree = $repoC }
        payload = [pscustomobject]@{ patchFile = 'T-14-0001.patch'; sha256 = $shaC; files = @('greeting.txt') }
        source = 'T-14'
    }
)
$resultD = Invoke-ApplyPatchScript -ScriptParams @{ QueuePath = $queuePathC; AppliedLogPath = $logPathC }
Log $resultD.Output
Assert-True -Name "D1 重跑 exit code = 0（跳過不是失敗）" -Condition ($resultD.ExitCode -eq 0) -Detail "ExitCode=$($resultD.ExitCode)"
Assert-True -Name "D2 重跑輸出含 SKIPPED-ALREADY-APPLIED" -Condition ($resultD.Output -like '*SKIPPED-ALREADY-APPLIED*')

$contentD = Get-Content -LiteralPath (Join-Path $repoC 'greeting.txt') -Raw
Assert-True -Name "D3 重跑後檔案內容不變（未重複套用造成損壞或疊加）" -Condition ($contentD -eq "Hello, Universe`nWorld") -Detail "實際='$contentD'"

$queueAfterDRaw = Read-QueueFile -QueuePath $queuePathC
$queueAfterD = @($queueAfterDRaw)
Assert-True -Name "D4 重跑後該項目再次出列" -Condition ($queueAfterD.Count -eq 0) -Detail "剩餘筆數=$($queueAfterD.Count)"

# ============================================================
Section "段落 E：驗收④ — 套用衝突（目標已被改動）⇒ 具名回報並留在佇列，不部分套用"
# ============================================================

$scenE = New-ConflictScenario -Prefix 'e-final-accept'
$resultE = Invoke-ApplyPatchScript -ScriptParams @{ QueuePath = $scenE.QueuePath; AppliedLogPath = $scenE.LogPath }
Log $resultE.Output
Assert-True -Name "E1 exit code 非 0" -Condition ($resultE.ExitCode -ne 0) -Detail "ExitCode=$($resultE.ExitCode)"
Assert-True -Name "E2 輸出含 FAILED-CONFLICT 且具名 source" -Condition ($resultE.Output -like '*FAILED-CONFLICT*' -and $resultE.Output -like '*T-CONFLICT-DEMO*')

$queueAfterERaw = Read-QueueFile -QueuePath $scenE.QueuePath
$queueAfterE = @($queueAfterERaw)
Assert-True -Name "E3 衝突項目留在佇列（未出列）" -Condition ($queueAfterE.Count -eq 1) -Detail "剩餘筆數=$($queueAfterE.Count)"

$contentE = Get-Content -LiteralPath (Join-Path $scenE.Worktree 'greeting.txt') -Raw
Assert-True -Name "E4 衝突後工作區內容完全未變（🚫 不得部分套用後宣稱成功）" -Condition ($contentE -eq "Hello`nEveryone") -Detail "實際='$contentE'"

$deliveredE = Test-PatchDelivered -Source 'T-CONFLICT-DEMO' -QueuePath $scenE.QueuePath -AppliedLogPath $scenE.LogPath
Assert-True -Name "E5 衝突後查交付狀態 ⇒ 未交付" -Condition (-not $deliveredE.Delivered) -Detail $deliveredE.Reason

# ============================================================
Section "總結"
# ============================================================
Log "共執行完成，FAIL=$($script:FailCount)"

$reportPath = Join-Path $ScriptDir 't22-red-green.txt'
Write-Utf8BomFile -Path $reportPath -Content (($script:Log) -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
