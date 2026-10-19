param(
    [Parameter(Mandatory)][string]$ChildScript,
    [Parameter(Mandatory)][ValidateRange(1, 30)][int]$ChildLifetimeSeconds,
    [ValidateRange(0, 5000)][int]$TailLineCount = 0,
    [AllowEmptyString()][string]$ChildPostExitTailMarker = '',
    [ValidateRange(0, 1000)][int]$ChildPostExitTailDelayMilliseconds = 0,
    [AllowEmptyString()][string]$ChildReadyFile = '',
    [AllowEmptyString()][string]$ChildReleaseFile = ''
)

Write-Output 'parent-output'

$childStartInfo = [Diagnostics.ProcessStartInfo]::new()
$childStartInfo.FileName = (Get-Process -Id $PID).Path
$childStartInfo.UseShellExecute = $false
$childStartInfo.ArgumentList.Add('-NoProfile')
$childStartInfo.ArgumentList.Add('-File')
$childStartInfo.ArgumentList.Add($ChildScript)
$childStartInfo.ArgumentList.Add('-LifetimeSeconds')
$childStartInfo.ArgumentList.Add([string]$ChildLifetimeSeconds)
if ($ChildPostExitTailMarker) {
    $childStartInfo.ArgumentList.Add('-PostExitTailMarker')
    $childStartInfo.ArgumentList.Add($ChildPostExitTailMarker)
    $childStartInfo.ArgumentList.Add('-PostExitTailDelayMilliseconds')
    $childStartInfo.ArgumentList.Add([string]$ChildPostExitTailDelayMilliseconds)
}
if ($ChildReadyFile -or $ChildReleaseFile) {
    if (-not $ChildReadyFile -or -not $ChildReleaseFile) { throw 'ChildReadyFile and ChildReleaseFile must be supplied together.' }
    $childStartInfo.ArgumentList.Add('-ReadyFile')
    $childStartInfo.ArgumentList.Add($ChildReadyFile)
    $childStartInfo.ArgumentList.Add('-ReleaseFile')
    $childStartInfo.ArgumentList.Add($ChildReleaseFile)
}

$child = [Diagnostics.Process]::Start($childStartInfo)
Write-Output ("child-pid:{0}" -f $child.Id)
if ($ChildReadyFile) {
    $deadline = (Get-Date).AddSeconds(5)
    while (-not (Test-Path -LiteralPath $ChildReadyFile -PathType Leaf)) {
        if ((Get-Date) -ge $deadline) { throw 'Timed out waiting for child post-exit tail readiness.' }
        Start-Sleep -Milliseconds 10
    }
    Set-Content -LiteralPath $ChildReleaseFile -Value 'release' -Encoding Ascii
}
for ($index = 0; $index -lt $TailLineCount; $index++) {
    Write-Output ("tail-marker:{0:D4}" -f $index)
}
