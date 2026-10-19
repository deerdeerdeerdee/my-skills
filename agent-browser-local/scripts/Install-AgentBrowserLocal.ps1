#requires -Version 7.2
[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agent-browser\local'),
    [string]$SkillRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agents\skills\agent-browser-local'),
    [string]$BinRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local\bin')
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This skill runtime requires Windows and PowerShell 7.2+.' }
$packageRoot = Split-Path $PSScriptRoot -Parent
$sourceRuntime = Join-Path $PSScriptRoot 'runtime'
# Never copy an installation over the maintained source tree.
foreach ($target in @($InstallRoot, $BinRoot)) {
    $resolved = [IO.Path]::GetFullPath($target).TrimEnd('\')
    $source = [IO.Path]::GetFullPath($packageRoot).TrimEnd('\')
    if ($resolved -eq $source -or $resolved.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Installation targets must be outside the source skill directory.'
    }
}
$files = @('agent-browser-local.ps1', 'cli-config.json', 'lib\AgentBrowserLocal.psm1',
    'tests\fixtures\DaemonInheritedStdoutParent.ps1', 'tests\fixtures\DaemonInheritedStdoutChild.ps1')
$backupRoot = Join-Path $InstallRoot ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
foreach ($relative in $files + @('README.md', 'POLICY.md', 'TROUBLESHOOTING.md')) {
    $destination = Join-Path $InstallRoot $relative
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $backup = Join-Path $backupRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $backup -Parent) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup
    }
}
foreach ($relative in $files) {
    $destination = Join-Path $InstallRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRuntime $relative) -Destination $destination -Force
}
New-Item -ItemType Directory -Force -Path $SkillRoot,(Join-Path $SkillRoot 'references'),$BinRoot | Out-Null
if ([IO.Path]::GetFullPath($SkillRoot).TrimEnd('\') -ne [IO.Path]::GetFullPath($packageRoot).TrimEnd('\')) {
Copy-Item -LiteralPath (Join-Path $packageRoot 'SKILL.md') -Destination (Join-Path $SkillRoot 'SKILL.md') -Force
Copy-Item -LiteralPath (Join-Path $packageRoot 'references\policy.md') -Destination (Join-Path $SkillRoot 'references\policy.md') -Force
Copy-Item -LiteralPath (Join-Path $packageRoot 'references\troubleshooting.md') -Destination (Join-Path $SkillRoot 'references\troubleshooting.md') -Force
Copy-Item -LiteralPath (Join-Path $packageRoot 'README.md') -Destination (Join-Path $SkillRoot 'README.md') -Force
# Keep the installed skill self-contained for later updates and redistribution.
Copy-Item -LiteralPath $PSScriptRoot -Destination $SkillRoot -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $packageRoot 'references\policy.md') -Destination (Join-Path $InstallRoot 'POLICY.md') -Force
$skillReadme = Join-Path $SkillRoot 'README.md'
$testScript = Join-Path $SkillRoot 'scripts\Test-AgentBrowserLocal.ps1'
@"
# Installed agent-browser-local runtime

Maintained source and installation guide: [$skillReadme]($skillReadme).
Reinstall from the maintained my-skills package after source updates. Machine settings belong to config.psd1; profiles, registrations and logs remain local.

The CLI follows the active nvm/PATH installation unless CanonicalCliHint pins a real native executable. Use agent-browser-local status for actual selected versions. Old DESIGN/IMPLEMENTATION_PLAN/version-selection and legacy test files in this directory are historical artifacts; the installed skill and current packaged tests own today's behavior and validation.

Run regression checks with:

    pwsh -NoProfile -File "$testScript" -RuntimeRoot "$InstallRoot"

Add -Smoke for isolated browsers and an empty temporary auth profile. Ordinary diagnostics start with status; do not run doctor or global cleanup.

See [POLICY.md](POLICY.md) and [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
"@ | Set-Content -LiteralPath (Join-Path $InstallRoot 'README.md') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $packageRoot 'references\troubleshooting.md') -Destination (Join-Path $InstallRoot 'TROUBLESHOOTING.md') -Force
$entry = (Join-Path $InstallRoot 'agent-browser-local.ps1').Replace("'", "''")
$shimPath = Join-Path $BinRoot 'agent-browser-local.ps1'
if (Test-Path -LiteralPath $shimPath) {
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    Copy-Item -LiteralPath $shimPath -Destination (Join-Path $backupRoot 'command-shim.ps1')
}
@"
#requires -Version 7.2
# Managed by agent-browser-local installer. Re-run installer after source updates.
`$global:LASTEXITCODE = 0
& '$entry' @args
if (`$global:LASTEXITCODE -ne 0) { exit `$global:LASTEXITCODE }
"@ | Set-Content -LiteralPath $shimPath -Encoding utf8
[pscustomobject]@{
    InstallRoot = $InstallRoot; SkillRoot = $SkillRoot; Command = $shimPath
    BackupRoot = $backupRoot
    BinOnCurrentPath = @($env:PATH -split ';' | Where-Object { $_.TrimEnd('\') -eq $BinRoot.TrimEnd('\') }).Count -gt 0
    Note = 'Preserved config.psd1, profiles, logs and runtime state. Add BinRoot to PATH if needed.'
}
