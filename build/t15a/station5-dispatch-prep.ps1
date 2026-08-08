#requires -Version 5.1
<#
.SYNOPSIS
    T-15a：站 5 雙審 dispatch 準備——以「函式簽章不含禁止參數」的結構性保證組出軸 A／軸 B 兩份
    實際 sub-agent prompt，並留存為可核對的證據檔（供驗收①「輸入清單核對」使用）。

.DESCRIPTION
    依 Spec_station-command_v1.11.md §5.2 逐字：
      「軸 A 規範審輸入只有 diff ＋ repo 規範 ＋ 12 條 Fowler smell 基線；
        軸 B 規格對照審輸入只有 diff ＋ spec 原文（逐項 ✓／✗）。」

    **輸入分離的第一道防線＝結構性（本檔核心設計）**：`New-AxisAPrompt` 的參數清單裡沒有
    「spec 原文」這個欄位——不是「有傳進來但被過濾掉」，而是呼叫端**物理上無法**透過這個函式
    把 spec 原文塞進軸 A prompt（唯一漏洞是把 spec 原文貼進 `-DiffText` 本身，那已超出本函式
    能防的範圍，由下方 `Test-PromptTextMarkers` 做第二道 best-effort 文字掃描兜底）。
    `New-AxisBPrompt` 同理，簽章裡沒有 `StandardsRefs`／`SmellBaselineText`。

    本檔**只組 prompt 文字、只寫本機證據檔**，不呼叫 Task 工具、不派 sub-agent——實際的
    parallel fresh-context dispatch（Task 呼叫）是 Claude 主 session（Commander）的動作，
    不是 PowerShell 腳本能做的事（同 T-12 run-dispatch.ps1 的既有先例：「本檔不代 Commander
    呼叫 sub-agent」）。Commander 讀本檔輸出的兩份 prompt 文字，各自以之作為兩個平行
    fresh-context `general-purpose` sub-agent 的完整輸入，取回兩份報告後交給
    `station5-check.ps1` 驗證。

    重用地基（不重寫，DRY）：dot-source ../t21/queue-common.ps1（Write-Utf8BomFile／
    Set-ConsoleUtf8）。本檔**不修改** build/t21／build/station-command 任何檔案（file
    ownership 邊界）；讀取 ../station-command/assets/fowler-smells.md 與
    ../../Spec_station-command_v1.11.md 皆為唯讀。

.PARAMETER FunctionsOnly
    只載入函式、不執行主流程（供離線／動態測試 dot-source 呼叫內部函式）。
#>

[CmdletBinding(DefaultParameterSetName = 'Prep')]
param(
    [Parameter(ParameterSetName = 'Prep')]
    [string]$Ticket = 'T-15a-demo',

    [Parameter(ParameterSetName = 'Prep')]
    [string]$DiffPath,

    [Parameter(ParameterSetName = 'Prep')]
    [string[]]$StandardsRefs = @('該 repo 無落檔規範，本輪僅以基線審'),

    [Parameter(ParameterSetName = 'Prep')]
    [string]$SpecExcerptPath,

    [Parameter(ParameterSetName = 'Prep')]
    [string]$SpecSectionAnchor = '### 5.2 站 5 雙審規則',

    [Parameter(ParameterSetName = 'Prep')]
    [int]$SpecExcerptMaxChars = 3000,

    [Parameter(ParameterSetName = 'Prep')]
    [string]$SmellBaselinePath,

    [Parameter(ParameterSetName = 'Prep')]
    [string]$OutDir,

    [switch]$FunctionsOnly
)

$ErrorActionPreference = 'Stop'
# ⚠️ 用 $T15aPrepDir 而非 $ScriptDir／$T15aDir——理由同 T-12／T-14 README 記載的實跑 bug：
# 本檔與 station5-check.ps1 常被同一支離線測試 dot-source 進同一層作用域，若兩檔都用同名變數
# 後執行者會覆蓋先執行者的值，導致報告誤寫錯目錄。兩檔各自使用獨有變數名。
$T15aPrepDir = $PSScriptRoot
$QueueCommonPath = Join-Path $T15aPrepDir '..\t21\queue-common.ps1'
if (-not (Test-Path -LiteralPath $QueueCommonPath)) {
    throw ("找不到 T-21 共用函式庫：{0}。請確認 t15a 與 t21 為同層兄弟目錄。" -f $QueueCommonPath)
}
. $QueueCommonPath
Set-ConsoleUtf8

# ============================================================
# 軸 A prompt 組裝——結構性保證：簽章無任何可傳入 spec 原文的參數
# ============================================================
function New-AxisAPrompt {
    param(
        [Parameter(Mandatory)][string]$Ticket,
        [Parameter(Mandatory)][AllowEmptyString()][string]$DiffText,
        [Parameter(Mandatory)][string[]]$StandardsRefs,
        [Parameter(Mandatory)][AllowEmptyString()][string]$SmellBaselineText
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("=== 站 5 軸 A（規範審 sub-agent prompt）— 票 $Ticket ===")
    [void]$sb.AppendLine('你是站 5 兩軸雙審的軸 A（規範審）。你只審 diff 是否符合下列規範與 smell 基線，')
    [void]$sb.AppendLine('不判斷需求是否被正確實作（那是軸 B 的職責，你看不到也不需要看 spec 原文）。')
    [void]$sb.AppendLine('報告結尾須有一行摘要：本軸 findings 總數、以及本軸內的 worst issue（若有）。')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- [輸入 1/3] diff ---')
    [void]$sb.AppendLine($DiffText)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- [輸入 2/3] repo 規範清單（本輪採用之檔案與版本，須具名） ---')
    foreach ($s in $StandardsRefs) { [void]$sb.AppendLine("- $s") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- [輸入 3/3] 12 條 Fowler smell 基線（repo 規範優先，基線永遠是判斷題） ---')
    [void]$sb.AppendLine($SmellBaselineText)
    return $sb.ToString()
}

# ============================================================
# 軸 B prompt 組裝——結構性保證：簽章無 StandardsRefs／SmellBaselineText 參數
# ============================================================
function New-AxisBPrompt {
    param(
        [Parameter(Mandatory)][string]$Ticket,
        [Parameter(Mandatory)][AllowEmptyString()][string]$DiffText,
        [Parameter(Mandatory)][AllowEmptyString()][string]$SpecExcerptText
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("=== 站 5 軸 B（規格對照審 sub-agent prompt）— 票 $Ticket ===")
    [void]$sb.AppendLine('你是站 5 兩軸雙審的軸 B（規格對照審）。你只審 diff 是否逐項落實下列 spec 原文要求，')
    [void]$sb.AppendLine('逐項標 ✓／✗，不判斷程式風格或 code smell（那是軸 A 的職責，你看不到也不需要看規範清單或 smell 基線）。')
    [void]$sb.AppendLine('報告結尾須有一行摘要：本軸 findings 總數、以及本軸內的 worst issue（若有）。')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- [輸入 1/2] diff ---')
    [void]$sb.AppendLine($DiffText)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- [輸入 2/2] spec 原文（逐項 ✓／✗ 對照用） ---')
    [void]$sb.AppendLine($SpecExcerptText)
    return $sb.ToString()
}

# ============================================================
# 第二道防線（best-effort 文字掃描，defense-in-depth；非取代結構性保證）
# 用途：若 DiffText 本身意外夾帶大段 spec 原文／smell 基線文字，結構性保證防不了，
# 這裡用已知特徵字串補一道防線。未命中不代表「保證乾淨」，只代表「已知樣式庫內沒抓到」，
# 此為誠實聲明的已知限制（同 T-14 ①④ 查核的 best-effort 定性）。
#
# rework（實跑抓到並修正的設計缺陷，非憑空預防）：初版採「命中任一樣式即拒絕」，實測發現
# 兩處真實內容的合理誤傷——① 12 條 smell 基線 asset（station-command/assets/fowler-smells.md）
# 自身頁尾依 §8 慣例引用「Spec_station-command_v1.5.md §5.2」作為出處註記（合法引用，非夾帶
# spec 原文內容）；② Spec §5.2 條文本身談到「12 條 Fowler smell 基線」時提及一次 "Fowler"
# 字樣（合法談論 smell 基線的存在，非夾帶 smell 基線內容本身）。單一字樣命中不足以區分「合法
# 提及」與「真的整段夾帶」，改採**門檻計數**：須命中 ≥2 個不同樣式才判定為疑似洩漏（真的整段
# 貼上 spec 原文或 smell 基線清單，必然同時命中多個不同特徵詞；只提到一次檔名或一次概念詞不算）。
# ============================================================
function Test-PromptTextMarkers {
    param(
        [Parameter(Mandatory)][ValidateSet('AxisA', 'AxisB')][string]$Axis,
        [Parameter(Mandatory)][AllowEmptyString()][string]$PromptText,
        [int]$MatchThreshold = 2
    )
    $forbidden = if ($Axis -eq 'AxisA') {
        @('Spec_station-command', 'REQ-ID', '(?i)success criteria', '(?i)scope in.*scope out', 'ADR-NP-0\d\d', '驗收條件（可執行）')
    } else {
        @('(?i)mysterious name', '(?i)fowler', '(?i)12 code smells', '(?i)speculative generality', '(?i)feature envy', '(?i)data clumps', '(?i)message chains', '(?i)refused bequest')
    }
    $label = if ($Axis -eq 'AxisA') { '軸 A' } else { '軸 B' }
    $forbiddenName = if ($Axis -eq 'AxisA') { 'spec 原文' } else { '12 條 Fowler smell 基線' }

    $hits = @($forbidden | Where-Object { $PromptText -match $_ })
    $hits = @($hits)
    if ($hits.Count -ge $MatchThreshold) {
        return [pscustomobject]@{
            Satisfied = $false
            Detail    = "$label prompt 命中 $($hits.Count) 個不同疑似${forbiddenName}標記（門檻=$MatchThreshold，樣式：$($hits -join '、')）——best-effort 偵測，非完整語意分析，見 README 已知限制"
        }
    }
    $incidentalNote = if ($hits.Count -gt 0) { "（有 $($hits.Count) 個零星命中未達門檻，視為合法提及非夾帶：$($hits -join '、')）" } else { '' }
    return [pscustomobject]@{ Satisfied = $true; Detail = "$label prompt 未達${forbiddenName}洩漏門檻$incidentalNote" }
}

# ============================================================
# CLI：讀真實檔案（唯讀）組出兩份 prompt，寫入證據檔並自跑第二道防線
# ============================================================
function Invoke-DispatchPrepCli {
    $effOutDir = if ($OutDir) { $OutDir } else { $T15aPrepDir }
    if (-not (Test-Path -LiteralPath $effOutDir)) {
        New-Item -ItemType Directory -Path $effOutDir -Force | Out-Null
    }
    $diffText = if ($DiffPath -and (Test-Path -LiteralPath $DiffPath)) {
        Get-Content -LiteralPath $DiffPath -Raw -Encoding UTF8
    } else {
        "（未提供 -DiffPath，以佔位文字示範；正式使用時請傳入該票的實際 diff 檔路徑）`n--- placeholder diff for $Ticket ---"
    }

    $smellPath = if ($SmellBaselinePath) { $SmellBaselinePath } else { Join-Path $T15aPrepDir '..\station-command\assets\fowler-smells.md' }
    if (-not (Test-Path -LiteralPath $smellPath)) { throw "找不到 12 條 smell 基線 asset：$smellPath（T-11 交付，本檔唯讀引用不修改）" }
    $smellText = Get-Content -LiteralPath $smellPath -Raw -Encoding UTF8

    # 未指定 -SpecExcerptPath 時，🚫 不預設灌入整份 spec 檔（那會連同 spec 其他章節裡順帶
    # 引用的 Fowler smell 詞彙一起帶入，對「軸 B 只讀逐項對照所需片段」這個實務慣例不寫實，也會
    # 讓 Test-PromptTextMarkers 的門檻檢查因為「不相干章節的零星引用湊滿門檻」而誤判）——改預設
    # 只截取本票 anchor 段落附近 -SpecExcerptMaxChars 字元，貼近「軸 B 只拿到逐項對照所需的
    # spec 片段」的實際 dispatch 用法。呼叫端仍可用 -SpecExcerptPath 提供任意內容（含整份），
    # 此時視為呼叫端已自行決定範圍，本檔原樣使用、不再裁切。
    $specExcerpt = if ($SpecExcerptPath -and (Test-Path -LiteralPath $SpecExcerptPath)) {
        Get-Content -LiteralPath $SpecExcerptPath -Raw -Encoding UTF8
    } else {
        $defaultSpecPath = Join-Path $T15aPrepDir '..\..\Spec_station-command_v1.11.md'
        if (Test-Path -LiteralPath $defaultSpecPath) {
            $fullSpec = Get-Content -LiteralPath $defaultSpecPath -Raw -Encoding UTF8
            $idx = $fullSpec.IndexOf($SpecSectionAnchor)
            if ($idx -ge 0) { $fullSpec.Substring($idx, [Math]::Min($SpecExcerptMaxChars, $fullSpec.Length - $idx)) } else { $fullSpec.Substring(0, [Math]::Min($SpecExcerptMaxChars, $fullSpec.Length)) }
        } else {
            "（未提供 -SpecExcerptPath 且找不到預設 spec 檔，以佔位文字示範）"
        }
    }

    $axisAPrompt = New-AxisAPrompt -Ticket $Ticket -DiffText $diffText -StandardsRefs $StandardsRefs -SmellBaselineText $smellText
    $axisBPrompt = New-AxisBPrompt -Ticket $Ticket -DiffText $diffText -SpecExcerptText $specExcerpt

    $axisAPath = Join-Path $effOutDir 'evidence-axisA-prompt.txt'
    $axisBPath = Join-Path $effOutDir 'evidence-axisB-prompt.txt'
    Write-Utf8BomFile -Path $axisAPath -Content $axisAPrompt
    Write-Utf8BomFile -Path $axisBPath -Content $axisBPrompt

    $chkA = Test-PromptTextMarkers -Axis 'AxisA' -PromptText $axisAPrompt
    $chkB = Test-PromptTextMarkers -Axis 'AxisB' -PromptText $axisBPrompt

    $lines = @(
        "station5-dispatch-prep 執行報告 — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
        "Ticket=$Ticket",
        "軸 A prompt 證據檔：$axisAPath",
        "軸 B prompt 證據檔：$axisBPath",
        "軸 A 第二道防線（不含 spec 原文標記）：$(if ($chkA.Satisfied) { 'PASS' } else { 'FAIL' }) — $($chkA.Detail)",
        "軸 B 第二道防線（不含 smell 基線標記）：$(if ($chkB.Satisfied) { 'PASS' } else { 'FAIL' }) — $($chkB.Detail)"
    )
    $lines | ForEach-Object { Write-Host $_ }
    Write-Utf8BomFile -Path (Join-Path $effOutDir 'dispatch-prep-report.txt') -Content ($lines -join [Environment]::NewLine)

    if ((-not $chkA.Satisfied) -or (-not $chkB.Satisfied)) { exit 1 }
    exit 0
}

if (-not $FunctionsOnly) {
    Invoke-DispatchPrepCli
}
