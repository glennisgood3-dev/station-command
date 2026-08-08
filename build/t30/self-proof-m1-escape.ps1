#requires -Version 5.1
<#
.SYNOPSIS
    M-1 自證腳本：模擬 Windows PowerShell 5.1 的 ConvertTo-Json（JavaScriptSerializer）
    逸出行為，證明「修法之前」的序列化字串比對對逸出形態不命中（守門失效），
    以及「修法之後」直接對物件字串欄位比對能命中（守門有效）。

.DESCRIPTION
    本機（pwsh 7.4.6）的 ConvertTo-Json 不會逸出中文字元，所以無法在本機直接重現
    5.1 的失效現場。本腳本改用「手動模擬」：先用本機 ConvertTo-Json 取得結構正確的
    JSON 字串（含未逸出的中文字面），再依 .NET JavaScriptSerializer 已知的逸出規則
    （任何 code point > 127 的字元一律轉為小寫 \uXXXX），把字串中的非 ASCII 字元
    逐字轉成 \uXXXX，藉此重建「5.1 風格逸出後」的 JSON 字串，作為兩段比對的輸入。

    這只是「模擬」，不是在真 5.1 執行期上直接量測；差距與殘留風險見報告最後一節。

.OUTPUTS
    Console 與 evidence\m1-escape-self-proof.txt 皆會寫入完整證據；
    exit 0 = 自證成功（修前不命中、修後命中皆如預期）；exit 1 = 自證本身有異常。
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SelfProofDir = $PSScriptRoot
. (Join-Path $SelfProofDir 't30-core.ps1') -FunctionsOnly

$script:ProofLines = New-Object System.Collections.Generic.List[string]
function Write-ProofLine {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    Write-Output $Text
    $script:ProofLines.Add($Text)
}

function ConvertTo-Simulated51Escape {
    <#
    .SYNOPSIS
        把字串中所有 code point > 127 的字元轉成 \uXXXX（小寫十六進位四碼），
        模擬 .NET JavaScriptSerializer（PowerShell 5.1 ConvertTo-Json 底層）的逸出規則。
    #>
    param([Parameter(Mandatory = $true)][string]$Text)
    $builder = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if ($code -gt 127) {
            [void]$builder.Append('\u' + ('{0:x4}' -f $code))
        }
        else {
            [void]$builder.Append($ch)
        }
    }
    return $builder.ToString()
}

$forbiddenPattern = '多數決|以\s*Claude\s*為準'

# 樣本涵蓋票面禁止的兩種措辭，欄位名稱與 New-T30GateResult 實際輸出一致。
$sample = [pscustomobject][ordered]@{
    decisionMethod = '以 Claude 為準'
    note = '本輪合議機制採多數決'
}

Write-ProofLine '=== M-1 自證：PowerShell 5.1 逸出形態下，序列化 regex 比對 vs 物件直接比對 ==='
Write-ProofLine ''
Write-ProofLine '【樣本物件（記憶體中原生字串，未逸出）】'
Write-ProofLine "decisionMethod = $($sample.decisionMethod)"
Write-ProofLine "note           = $($sample.note)"
Write-ProofLine ''

# 先用本機（pwsh 7.4.6）ConvertTo-Json 取得結構正確、中文未逸出的 JSON。
$nativeJson = $sample | ConvertTo-Json -Depth 5 -Compress
Write-ProofLine '【本機 pwsh 7.4.6 ConvertTo-Json 原始輸出（中文未逸出，非本次自證重點）】'
Write-ProofLine $nativeJson
$nativeMatch = [bool]($nativeJson -match $forbiddenPattern)
Write-ProofLine "  舊寫法（序列化字串 -match）在『未逸出』JSON 上命中：$nativeMatch （符合預期，這正是現況在 pwsh7 上全綠、掩蓋問題的原因）"
Write-ProofLine ''

# 手動模擬 5.1 的逸出結果。
$simulated51Json = ConvertTo-Simulated51Escape -Text $nativeJson
Write-ProofLine '【模擬 Windows PowerShell 5.1 JavaScriptSerializer 逸出後的 JSON】'
Write-ProofLine $simulated51Json
Write-ProofLine ''

# === 修法之前：對逸出後字串跑 regex（舊寫法，等同 t30-core.ps1 修改前的邏輯） ===
$beforeFixHit = [bool]($simulated51Json -match $forbiddenPattern)
Write-ProofLine '【修法之前：$simulated51Json -match ''多數決|以\s*Claude\s*為準''】'
Write-ProofLine "  命中結果：$beforeFixHit （預期 False = 守門在 5.1 逸出形態下靜默失效）"
Write-ProofLine ''

# === 修法之後：不序列化，直接對物件的原生字串欄位比對 ===
$afterFixHit = Test-T30ContainsForbiddenDecisionLanguage -InputObject $sample
Write-ProofLine '【修法之後：Test-T30ContainsForbiddenDecisionLanguage -InputObject $sample（不經序列化）】'
Write-ProofLine "  命中結果：$afterFixHit （預期 True = 守門在同一組逸出風險下依然有效，因為比對對象根本不是逸出後的字串）"
Write-ProofLine ''

$proofOk = ($beforeFixHit -eq $false) -and ($afterFixHit -eq $true)
Write-ProofLine "=== 自證結論：修前不命中=$($beforeFixHit -eq $false)；修後命中=$($afterFixHit -eq $true)；自證整體$(if ($proofOk) { '成立' } else { '不成立，請檢查腳本或修法邏輯' }) ==="

$evidenceDir = Join-Path $SelfProofDir 'evidence'
if (-not (Test-Path -LiteralPath $evidenceDir -PathType Container)) { [void](New-Item -ItemType Directory -Path $evidenceDir -Force) }
$evidencePath = Join-Path $evidenceDir 'm1-escape-self-proof.txt'
[IO.File]::WriteAllText($evidencePath, ($script:ProofLines -join [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))
Write-Output ''
Write-Output "證據檔已寫入：$evidencePath"

if (-not $proofOk) { exit 1 }
exit 0
