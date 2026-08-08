#requires -Version 5.1
<# T-28：掃描對話輸出、repo、log、待寫佇列四處是否含指定 key。輸出永不包含 key 值。 #>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-T28ScannableFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return ,([IO.FileInfo]$Path) }

    $rawFiles = Get-ChildItem -LiteralPath $Path -File -Recurse
    $files = @($rawFiles)
    $result = New-Object System.Collections.Generic.List[object]
    $gitPart = [IO.Path]::DirectorySeparatorChar + '.git' + [IO.Path]::DirectorySeparatorChar
    foreach ($file in $files) {
        if ($file.FullName.IndexOf($gitPart, [StringComparison]::OrdinalIgnoreCase) -ge 0) { continue }
        $result.Add($file)
    }
    return $result.ToArray()
}

function Test-T28KeyLeakAcrossSurfaces {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Secret,
        [string[]]$ConversationPaths = @(),
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [string[]]$LogPaths = @(),
        [string[]]$QueuePaths = @()
    )

    if ([string]::IsNullOrWhiteSpace($Secret)) { throw '掃描用 key 不得為空。' }
    $matches = New-Object System.Collections.Generic.List[object]
    $surfaceSets = @(
        [pscustomobject]@{ Name = '對話輸出'; Paths = [string[]]$ConversationPaths },
        [pscustomobject]@{ Name = 'repo 內容'; Paths = [string[]]@($RepoPath) },
        [pscustomobject]@{ Name = 'log'; Paths = [string[]]$LogPaths },
        [pscustomobject]@{ Name = '待寫佇列'; Paths = [string[]]$QueuePaths }
    )

    foreach ($surfaceSet in $surfaceSets) {
        foreach ($path in $surfaceSet.Paths) {
            $rawFiles = Get-T28ScannableFiles -Path $path
            $files = @($rawFiles)
            foreach ($file in $files) {
                try { $content = [IO.File]::ReadAllText($file.FullName) }
                catch { continue }
                if ($content.Contains($Secret)) {
                    $matches.Add([pscustomobject]@{ Surface = $surfaceSet.Name; Path = $file.FullName })
                }
            }
        }
    }

    return [pscustomobject]@{
        Safe = ($matches.Count -eq 0)
        MatchCount = $matches.Count
        Matches = $matches.ToArray()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Write-Output @'
T-28 key-leak-scan.ps1：純函式庫，不是可獨立執行的掃描器。

用法：先 dot-source 本檔，再呼叫 Test-T28KeyLeakAcrossSurfaces：
  . .\key-leak-scan.ps1
  Test-T28KeyLeakAcrossSurfaces -Secret <key> -ConversationPaths <paths> -RepoPath <path> -LogPaths <paths> -QueuePaths <paths>

直接執行本檔不會掃描任何路徑。T-28 的實際四表面掃描發生在
t28-offline-test.ps1 群組 C／E；該測試會 dot-source 本檔並呼叫上述函式。
'@
}
