#requires -Version 5.1
<#
.SYNOPSIS
    T-25 離線套用子程序：在隔離暫存副本中執行 T-21 apply-queue.ps1，攔截所有 REST 呼叫。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ApplyScriptPath,
    [Parameter(Mandatory)][string]$PatPath,
    [Parameter(Mandatory)][string]$QueuePath,
    [Parameter(Mandatory)][string]$CommentStorePath
)

$ErrorActionPreference = 'Stop'
$T25ApplyScriptPath = $ApplyScriptPath
$T25ApplyPatPath = $PatPath
$T25ApplyQueuePath = $QueuePath
$T25ApplyCommentStorePath = $CommentStorePath
Set-StrictMode -Version Latest

function Read-T25MockComments {
    if (-not (Test-Path -LiteralPath $T25ApplyCommentStorePath)) { return ,@() }
    $raw = Get-Content -LiteralPath $T25ApplyCommentStorePath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return ,@() }
    $parsed = $raw | ConvertFrom-Json
    if ($null -eq $parsed) { return ,@() }
    return ,@($parsed)
}

function Write-T25MockComments {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Comments)
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $json = if ($Comments.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject $Comments -Depth 10 }
    [System.IO.File]::WriteAllText($T25ApplyCommentStorePath, $json, $utf8Bom)
}

function Invoke-RestMethod {
    [CmdletBinding()]
    param(
        [string]$Uri,
        $Headers,
        [string]$Method = 'Get',
        $Body,
        [string]$ContentType
    )
    if ($Uri -notmatch '^https://api\.github\.com/repos/mock/apply/issues/77/comments(?:\?|$)') {
        throw "離線 mock 拒絕未列入白名單的 REST 呼叫：$Method $Uri"
    }
    if ($Method -eq 'Get') {
        return Read-T25MockComments
    }
    if ($Method -eq 'Post') {
        $payload = $Body | ConvertFrom-Json
        $rawComments = Read-T25MockComments
        $comments = @($rawComments)
        $nextId = $comments.Count + 1
        $comments += [pscustomobject]@{ id = $nextId; body = [string]$payload.body }
        Write-T25MockComments -Comments @($comments)
        return [pscustomobject]@{ id = $nextId; body = [string]$payload.body }
    }
    throw "離線 mock 不支援方法：$Method $Uri"
}

& $T25ApplyScriptPath -PatPath $T25ApplyPatPath -QueuePath $T25ApplyQueuePath
