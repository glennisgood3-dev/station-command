#requires -Version 5.1
<#
.SYNOPSIS
    T-22：沙盒可跑的真實測試（不連 GitHub；本型套用本來就不連 GitHub，故沙盒可百分之百真實跑，
    不需要任何 mock——這是 T-22 相對 T-21 的優勢，見票面提示）。

.DESCRIPTION
    每個案例都在暫存目錄用**真正的 git**（沙盒 git 2.43.0）建立臨時工作區、產生真正的 patch、
    呼叫 patch-common.ps1 的函式做真實的 git apply --check／apply，斷言真實輸出。
    涵蓋：schema 驗證邊界、sha256 完整性核對、worktree 合法性、反向乾跑冪等判準、
    正向乾跑衝突偵測、二進位檔套用、多檔案 all-or-nothing 原子性、Invoke-GitCommand 的
    陣列安全性（PS 5.1 對 0/1/N 行輸出的解卷風險，比照 T-21 offline test 同型防禦）。

    ⚠️ 環境落差誠實聲明：本檔在沙盒 pwsh 7.4.6 下執行；PS 6+ 對純量物件加了 .Count 相容屬性
    （會回 1，不拋錯），5.1 沒有這層。故本檔涉及陣列型別的斷言一律用 `-is [array]` 而非只測
    `.Count` 不拋錯，避免假陰性（測不出 5.1 才會炸的問題）。本檔案本身以 5.1 相容語法撰寫，
    但終究只在 pwsh 7 跑過，尚未在真正的 Windows PowerShell 5.1 上驗證。

.EXAMPLE
    /opt/pwsh/pwsh -NoProfile -File t22-offline-test.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
. (Join-Path $ScriptDir 'patch-common.ps1')
Set-StrictMode -Version Latest

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
    param([Parameter(Mandatory)][string]$Name, $Value, [Parameter(Mandatory)][int]$ExpectedCount)
    $isArray = $Value -is [array]
    $actualCount = if ($isArray) { $Value.Count } elseif ($null -eq $Value) { -1 } else { -2 }
    $shapeDesc = if ($isArray) { "陣列，Count=$actualCount" } elseif ($null -eq $Value) { "純量 `$null（未包陣列！）" } else { "純量物件（未包陣列！型別：$($Value.GetType().Name)）" }
    $ok = $isArray -and ($Value.Count -eq $ExpectedCount)
    Assert-True -Name $Name -Condition $ok -Detail "預期陣列且 Count=$ExpectedCount；實際：$shapeDesc"
}

# 每個測試用一個乾淨的暫存目錄，避免互相污染
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

Write-Host "===================================================================="
Write-Host "A. Invoke-GitCommand 陣列安全性：0/1/多行輸出（真實 git，非 mock）"
Write-Host "===================================================================="

$repoA = New-TempGitRepo -Prefix 'a'
'x' | Set-Content -LiteralPath (Join-Path $repoA 'f.txt') -NoNewline
Invoke-GitCommand -Worktree $repoA -GitArgs @('add', '-A') | Out-Null
Invoke-GitCommand -Worktree $repoA -GitArgs @('commit', '-q', '-m', 'base') | Out-Null

# 0 行輸出情境：status --porcelain 在乾淨工作區回傳空字串
$r0 = Invoke-GitCommand -Worktree $repoA -GitArgs @('status', '--porcelain')
Assert-True -Name "A1 Invoke-GitCommand(0 行輸出) 不拋錯且 Output 為字串" -Condition ($r0.Output -is [string]) -Detail "Output='$($r0.Output)'"
Assert-True -Name "A2 Invoke-GitCommand(0 行輸出) ExitCode=0" -Condition ($r0.ExitCode -eq 0)

# 1 行輸出情境：rev-parse --is-inside-work-tree 回單行 "true"
$r1 = Invoke-GitCommand -Worktree $repoA -GitArgs @('rev-parse', '--is-inside-work-tree')
Assert-True -Name "A3 Invoke-GitCommand(1 行輸出) Output.Trim()='true'" -Condition ($r1.Output.Trim() -eq 'true') -Detail "Output='$($r1.Output)'"

# 多行輸出情境：log 兩個 commit
'y' | Set-Content -LiteralPath (Join-Path $repoA 'g.txt') -NoNewline
Invoke-GitCommand -Worktree $repoA -GitArgs @('add', '-A') | Out-Null
Invoke-GitCommand -Worktree $repoA -GitArgs @('commit', '-q', '-m', 'second') | Out-Null
$rN = Invoke-GitCommand -Worktree $repoA -GitArgs @('log', '--oneline')
$rNLines = @($rN.Output -split [Environment]::NewLine)
Assert-True -Name "A4 Invoke-GitCommand(多行輸出) 含 2 個 commit" -Condition ($rNLines.Count -eq 2) -Detail "行數=$($rNLines.Count)"

Write-Host ""
Write-Host "===================================================================="
Write-Host "B. Test-ApplyPatchItemSchema 邊界"
Write-Host "===================================================================="

$validItem = [pscustomobject]@{
    action  = 'apply-patch'
    target  = [pscustomobject]@{ repo = 'o/r'; worktree = 'C:\x' }
    payload = [pscustomobject]@{ patchFile = 'p.patch'; sha256 = 'abc'; files = @('f.txt') }
    source  = 'T-99'
}
$s1 = Test-ApplyPatchItemSchema -Item $validItem
Assert-True -Name "B1 合法 apply-patch 項目 Schema 通過" -Condition $s1.Valid -Detail $s1.Detail

$missingWorktree = [pscustomobject]@{
    action  = 'apply-patch'
    target  = [pscustomobject]@{ repo = 'o/r' }
    payload = [pscustomobject]@{ patchFile = 'p.patch'; sha256 = 'abc' }
    source  = 'T-99'
}
$s2 = Test-ApplyPatchItemSchema -Item $missingWorktree
Assert-True -Name "B2 缺 target.worktree ⇒ Invalid" -Condition (-not $s2.Valid) -Detail $s2.Detail

$wrongAction = [pscustomobject]@{
    action  = 'set-labels'
    target  = [pscustomobject]@{ repo = 'o/r'; worktree = 'C:\x' }
    payload = [pscustomobject]@{ patchFile = 'p.patch'; sha256 = 'abc' }
    source  = 'T-99'
}
$s3 = Test-ApplyPatchItemSchema -Item $wrongAction
Assert-True -Name "B3 action 非 apply-patch ⇒ Invalid（本腳本不處理）" -Condition (-not $s3.Valid) -Detail $s3.Detail

$missingSha = [pscustomobject]@{
    action  = 'apply-patch'
    target  = [pscustomobject]@{ repo = 'o/r'; worktree = 'C:\x' }
    payload = [pscustomobject]@{ patchFile = 'p.patch' }
    source  = 'T-99'
}
$s4 = Test-ApplyPatchItemSchema -Item $missingSha
Assert-True -Name "B4 缺 payload.sha256 ⇒ Invalid" -Condition (-not $s4.Valid) -Detail $s4.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "C. sha256 完整性：正確／竄改兩種情況"
Write-Host "===================================================================="

$tmpPatchFile = Join-Path (New-TempDir -Prefix 'sha') 'x.patch'
Write-Utf8BomFile -Path $tmpPatchFile -Content 'dummy content'
# 注意：patch 檔本身規格要求無 BOM（見 patch-format.md §3a 精神與 git 慣例），此處用 BOM 版只為
# 測 Get-FileSha256Hex 這個工具函式本身「同一檔案兩次算出同一雜湊」與「內容改變雜湊跟著變」，
# 不涉及 git apply 實際套用（那些案例見下方 D／E 段，使用真正 git diff 產生的無 BOM patch）。
$hash1 = Get-FileSha256Hex -Path $tmpPatchFile
$hash2 = Get-FileSha256Hex -Path $tmpPatchFile
Assert-True -Name "C1 同一檔案兩次算出同一 sha256" -Condition ($hash1 -eq $hash2) -Detail "hash=$hash1"

Write-Utf8BomFile -Path $tmpPatchFile -Content 'tampered content'
$hash3 = Get-FileSha256Hex -Path $tmpPatchFile
Assert-True -Name "C2 內容改變後 sha256 跟著變" -Condition ($hash1 -ne $hash3) -Detail "hash1=$hash1 hash3=$hash3"

Write-Host ""
Write-Host "===================================================================="
Write-Host "D. Test-WorktreeValid：存在合法 repo／不存在路徑／存在但非 git 目錄"
Write-Host "===================================================================="

$repoD = New-TempGitRepo -Prefix 'd'
$dValid = Test-WorktreeValid -Worktree $repoD
Assert-True -Name "D1 合法 git 工作區 ⇒ Valid" -Condition $dValid.Valid -Detail $dValid.Detail

$dMissing = Test-WorktreeValid -Worktree (Join-Path ([System.IO.Path]::GetTempPath()) 'does-not-exist-t22')
Assert-True -Name "D2 不存在路徑 ⇒ Invalid" -Condition (-not $dMissing.Valid) -Detail $dMissing.Detail

$plainDir = New-TempDir -Prefix 'plain'
$dNotGit = Test-WorktreeValid -Worktree $plainDir
Assert-True -Name "D3 存在但非 git 工作區 ⇒ Invalid" -Condition (-not $dNotGit.Valid) -Detail $dNotGit.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "E. 冪等判準（反向乾跑）：套用前 false／套用後 true（真實 git apply）"
Write-Host "===================================================================="

$repoE = New-TempGitRepo -Prefix 'e'
Set-Content -LiteralPath (Join-Path $repoE 'greeting.txt') -Value "Hello`nWorld" -NoNewline
Invoke-GitCommand -Worktree $repoE -GitArgs @('add', '-A') | Out-Null
Invoke-GitCommand -Worktree $repoE -GitArgs @('commit', '-q', '-m', 'base') | Out-Null
Set-Content -LiteralPath (Join-Path $repoE 'greeting.txt') -Value "Hello, Universe`nWorld" -NoNewline
$patchE = Join-Path (New-TempDir -Prefix 'e-patch') 'e.patch'
$diffE = Invoke-GitCommand -Worktree $repoE -GitArgs @('diff', '--no-color', '--binary', '--', 'greeting.txt')
[System.IO.File]::WriteAllText($patchE, $diffE.Output + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
Invoke-GitCommand -Worktree $repoE -GitArgs @('checkout', '--', 'greeting.txt') | Out-Null

$eBefore = Test-PatchAlreadyApplied -Worktree $repoE -PatchFile $patchE
Assert-True -Name "E1 套用前反向乾跑 ⇒ AlreadyApplied=false" -Condition (-not $eBefore.AlreadyApplied) -Detail $eBefore.Detail

$eApplicable = Test-PatchAppliesCleanly -Worktree $repoE -PatchFile $patchE
Assert-True -Name "E2 套用前正向乾跑 ⇒ Applicable=true" -Condition $eApplicable.Applicable -Detail $eApplicable.Detail

$eApplyResult = Invoke-PatchApply -Worktree $repoE -PatchFile $patchE
Assert-True -Name "E3 真套用 ExitCode=0" -Condition ($eApplyResult.ExitCode -eq 0) -Detail $eApplyResult.Output

$eContent = Get-Content -LiteralPath (Join-Path $repoE 'greeting.txt') -Raw
Assert-True -Name "E4 套用後檔案內容逐字相符（獨立預期值＝patch 宣告目標）" -Condition ($eContent -eq "Hello, Universe`nWorld") -Detail "實際='$eContent'"

$eAfter = Test-PatchAlreadyApplied -Worktree $repoE -PatchFile $patchE
Assert-True -Name "E5 套用後反向乾跑 ⇒ AlreadyApplied=true（回驗通過）" -Condition $eAfter.AlreadyApplied -Detail $eAfter.Detail

Write-Host ""
Write-Host "===================================================================="
Write-Host "F. 衝突偵測：base 不同導致正向乾跑失敗，且 --ignore-whitespace 診斷不誤判非行尾衝突"
Write-Host "===================================================================="

$repoF = New-TempGitRepo -Prefix 'f'
Set-Content -LiteralPath (Join-Path $repoF 'greeting.txt') -Value "Hello`nEveryone" -NoNewline
Invoke-GitCommand -Worktree $repoF -GitArgs @('add', '-A') | Out-Null
Invoke-GitCommand -Worktree $repoF -GitArgs @('commit', '-q', '-m', 'diverged-base') | Out-Null

$fApplicable = Test-PatchAppliesCleanly -Worktree $repoF -PatchFile $patchE
Assert-True -Name "F1 base 已分歧 ⇒ 正向乾跑失敗" -Condition (-not $fApplicable.Applicable) -Detail $fApplicable.Detail

$fBeforeContent = Get-Content -LiteralPath (Join-Path $repoF 'greeting.txt') -Raw
Assert-True -Name "F2 乾跑失敗後檔案內容完全未變（🚫 不得部分套用）" -Condition ($fBeforeContent -eq "Hello`nEveryone") -Detail "實際='$fBeforeContent'"

$fLineEndingHint = Test-ConflictLooksLikeLineEndingOnly -Worktree $repoF -PatchFile $patchE
Assert-True -Name "F3 真正內容衝突（非行尾差異）⇒ 行尾診斷回傳 false（不誤發行尾提示）" -Condition (-not $fLineEndingHint)

Write-Host ""
Write-Host "===================================================================="
Write-Host "G. 多檔案 all-or-nothing 原子性：一檔衝突時另一檔案也不會被寫入"
Write-Host "===================================================================="

$repoG = New-TempGitRepo -Prefix 'g'
Set-Content -LiteralPath (Join-Path $repoG 'a.txt') -Value "Hello`nWorld" -NoNewline
Set-Content -LiteralPath (Join-Path $repoG 'b.txt') -Value "Foo`nBar" -NoNewline
Invoke-GitCommand -Worktree $repoG -GitArgs @('add', '-A') | Out-Null
Invoke-GitCommand -Worktree $repoG -GitArgs @('commit', '-q', '-m', 'base') | Out-Null
Set-Content -LiteralPath (Join-Path $repoG 'a.txt') -Value "Hello, Changed`nWorld" -NoNewline
Set-Content -LiteralPath (Join-Path $repoG 'b.txt') -Value "Foo, Changed`nBar" -NoNewline
$diffG = Invoke-GitCommand -Worktree $repoG -GitArgs @('diff', '--no-color', '--binary', '--', 'a.txt', 'b.txt')
$patchG = Join-Path (New-TempDir -Prefix 'g-patch') 'multi.patch'
[System.IO.File]::WriteAllText($patchG, $diffG.Output + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
Invoke-GitCommand -Worktree $repoG -GitArgs @('checkout', '--', 'a.txt', 'b.txt') | Out-Null
# 讓 a.txt 在「伺服端」分歧，b.txt 保持原樣（patch 對 b.txt 而言仍可乾淨套用）
Set-Content -LiteralPath (Join-Path $repoG 'a.txt') -Value "Hello`nDifferent" -NoNewline
Invoke-GitCommand -Worktree $repoG -GitArgs @('add', '-A') | Out-Null
Invoke-GitCommand -Worktree $repoG -GitArgs @('commit', '-q', '-m', 'diverge-a') | Out-Null

$gApplicable = Test-PatchAppliesCleanly -Worktree $repoG -PatchFile $patchG
Assert-True -Name "G1 多檔案 patch 其中一檔衝突 ⇒ 正向乾跑整體失敗" -Condition (-not $gApplicable.Applicable) -Detail $gApplicable.Detail

$gBContentBefore = Get-Content -LiteralPath (Join-Path $repoG 'b.txt') -Raw
Assert-True -Name "G2 未衝突的 b.txt 也未被寫入（真正的 all-or-nothing，非逐檔各自套用）" -Condition ($gBContentBefore -eq "Foo`nBar") -Detail "實際='$gBContentBefore'"

Write-Host ""
Write-Host "===================================================================="
Write-Host "H. 二進位檔套用：base64 編碼二進位 patch 逐位元組還原"
Write-Host "===================================================================="

$repoH = New-TempGitRepo -Prefix 'h'
[System.IO.File]::WriteAllBytes((Join-Path $repoH 'blob.bin'), [byte[]](0,1,2,79,76,68))
Invoke-GitCommand -Worktree $repoH -GitArgs @('add', '-A') | Out-Null
Invoke-GitCommand -Worktree $repoH -GitArgs @('commit', '-q', '-m', 'base') | Out-Null
[System.IO.File]::WriteAllBytes((Join-Path $repoH 'blob.bin'), [byte[]](0,1,2,78,69,87,255,254))
$diffH = Invoke-GitCommand -Worktree $repoH -GitArgs @('diff', '--no-color', '--binary', '--', 'blob.bin')
$patchH = Join-Path (New-TempDir -Prefix 'h-patch') 'bin.patch'
[System.IO.File]::WriteAllText($patchH, $diffH.Output + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
Invoke-GitCommand -Worktree $repoH -GitArgs @('checkout', '--', 'blob.bin') | Out-Null

$hApply = Invoke-PatchApply -Worktree $repoH -PatchFile $patchH
Assert-True -Name "H1 二進位 patch 套用 ExitCode=0" -Condition ($hApply.ExitCode -eq 0) -Detail $hApply.Output
$hBytes = [System.IO.File]::ReadAllBytes((Join-Path $repoH 'blob.bin'))
$hExpected = [byte[]](0,1,2,78,69,87,255,254)
$hMatch = ($hBytes.Length -eq $hExpected.Length)
if ($hMatch) { for ($i = 0; $i -lt $hBytes.Length; $i++) { if ($hBytes[$i] -ne $hExpected[$i]) { $hMatch = $false; break } } }
Assert-True -Name "H2 二進位內容逐位元組相符" -Condition $hMatch -Detail "實際位元組數=$($hBytes.Length)"

Write-Host ""
Write-Host "===================================================================="
Write-Host "I. Test-PatchDelivered：交付判定（驗收條件③，見 patch-format.md §6）"
Write-Host "===================================================================="

$queueDirI = New-TempDir -Prefix 'i-queue'
$queuePathI = Join-Path $queueDirI 'queue.json'
$logPathI = Join-Path $queueDirI 'applied-patches.log'

# 情境 1：source 仍在佇列中 ⇒ 未交付
Write-QueueFile -QueuePath $queuePathI -Items @(
    [pscustomobject]@{ action = 'apply-patch'; target = [pscustomobject]@{ repo='o/r'; worktree='x' }; payload = [pscustomobject]@{ patchFile='p'; sha256='s' }; source = 'T-14' }
)
$i1 = Test-PatchDelivered -Source 'T-14' -QueuePath $queuePathI -AppliedLogPath $logPathI
Assert-True -Name "I1 patch 仍在佇列 ⇒ Delivered=false（未套用不得算交付）" -Condition (-not $i1.Delivered) -Detail $i1.Reason

# 情境 2：佇列已清空但無落地紀錄 ⇒ 安全預設未交付
Write-QueueFile -QueuePath $queuePathI -Items @()
$i2 = Test-PatchDelivered -Source 'T-14' -QueuePath $queuePathI -AppliedLogPath $logPathI
Assert-True -Name "I2 佇列已空但無落地紀錄 ⇒ 安全預設 Delivered=false" -Condition (-not $i2.Delivered) -Detail $i2.Reason

# 情境 3：佇列已清空且有落地紀錄 ⇒ 已交付
Add-AppliedPatchLogEntry -LogPath $logPathI -Status 'APPLIED-VERIFIED' -Source 'T-14' -Worktree 'x' -PatchFile 'p'
$i3 = Test-PatchDelivered -Source 'T-14' -QueuePath $queuePathI -AppliedLogPath $logPathI
Assert-True -Name "I3 佇列已空且有落地紀錄 ⇒ Delivered=true" -Condition $i3.Delivered -Detail $i3.Reason

# 情境 4：不同 source 的落地紀錄不能誤判別的票已交付
$i4 = Test-PatchDelivered -Source 'T-99-NEVER-QUEUED' -QueuePath $queuePathI -AppliedLogPath $logPathI
Assert-True -Name "I4 查無此 source 任何紀錄 ⇒ Delivered=false（不誤判）" -Condition (-not $i4.Delivered) -Detail $i4.Reason

Write-Host ""
Write-Host "===================================================================="
Write-Host "總結：共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Host "===================================================================="

$reportPath = Join-Path $ScriptDir 't22-offline-test-report.txt'
$reportLines = @("t22-offline-test.ps1 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')", "PSVersion: $($PSVersionTable.PSVersion)", "")
$reportLines += $script:TestResults
$reportLines += ""
$reportLines += "共 $($script:TestResults.Count) 項，FAIL=$($script:FailCount)"
Write-Utf8BomFile -Path $reportPath -Content ($reportLines -join [Environment]::NewLine)
Write-Host "報告已寫入：$reportPath"

if ($script:FailCount -gt 0) { exit 1 }
exit 0
