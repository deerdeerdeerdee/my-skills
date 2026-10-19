param(
    [Parameter(Mandatory)][ValidateRange(1, 30)][int]$LifetimeSeconds,
    [AllowEmptyString()][string]$PostExitTailMarker = '',
    [ValidateRange(0, 1000)][int]$PostExitTailDelayMilliseconds = 0,
    [AllowEmptyString()][string]$ReadyFile = '',
    [AllowEmptyString()][string]$ReleaseFile = ''
)

if ($ReadyFile -or $ReleaseFile) {
    if (-not $ReadyFile -or -not $ReleaseFile) { throw 'ReadyFile and ReleaseFile must be supplied together.' }
    Set-Content -LiteralPath $ReadyFile -Value 'ready' -Encoding Ascii
    $deadline = (Get-Date).AddSeconds(5)
    while (-not (Test-Path -LiteralPath $ReleaseFile -PathType Leaf)) {
        if ((Get-Date) -ge $deadline) { throw 'Timed out waiting for post-exit tail release.' }
        Start-Sleep -Milliseconds 10
    }
}

if ($PostExitTailMarker) {
    Start-Sleep -Milliseconds $PostExitTailDelayMilliseconds
    Write-Output $PostExitTailMarker
}

Start-Sleep -Seconds $LifetimeSeconds
