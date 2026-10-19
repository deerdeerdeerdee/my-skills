#requires -Version 7.2
# Keep this a simple script: advanced parameter binding consumes native flags
# such as snapshot -i as ambiguous PowerShell Information* common parameters.
$cliArguments = @($args)

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'lib\AgentBrowserLocal.psm1'
Import-Module $module -Force
try {
    Invoke-AgentBrowserLocalCommand -Arguments $cliArguments
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    if ($_.Exception.Data['AgentBrowserLocalExitCode'] -eq 2) {
        exit 2
    }
    exit 1
}
