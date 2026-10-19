Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ConfigPath = Join-Path $PSScriptRoot '..\config.psd1'
# The child must not inherit routing, restore, plugin or launch overrides.
$script:RoutingEnvironmentVariables = @(
    'AGENT_BROWSER_PROFILE', 'AGENT_BROWSER_SESSION', 'AGENT_BROWSER_SESSION_NAME',
    'AGENT_BROWSER_RESTORE', 'AGENT_BROWSER_STATE', 'AGENT_BROWSER_CDP', 'AGENT_BROWSER_HEADED'
)
$script:AuthCliSession = 'local-auth-cdp'
$script:AuthCliTimeoutSeconds = 25
$script:TestCliTimeoutSeconds = 25
$script:AuthOperationTimeoutSeconds = 20

function Get-AgentBrowserLocalConfig {
    param([switch]$SkipDirectoryInitialization)

    $configPath = if ($env:AGENT_BROWSER_LOCAL_CONFIG) {
        $env:AGENT_BROWSER_LOCAL_CONFIG
    }
    else {
        $script:ConfigPath
    }

    $userRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agent-browser'
    $localRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $config = @{
        SchemaVersion = 2
        CanonicalCliHint = ''
        BrowserRoot = Join-Path $userRoot 'browsers'
        AuthProfilePath = Join-Path $userRoot 'profiles\work'
        CdpAddress = '127.0.0.1'
        CdpPort = 9333
        RuntimeDirectory = Join-Path $localRoot 'runtime'
        LogDirectory = Join-Path $localRoot 'logs'
        DoctorTimeoutSeconds = 30
        BrowserStartTimeoutSeconds = 15
        LogRetentionDays = 14
    }
    if (Test-Path -LiteralPath $configPath) {
        $overrides = Import-PowerShellDataFile -LiteralPath $configPath
        foreach ($key in $overrides.Keys) { $config[$key] = $overrides[$key] }
    }
    elseif ($env:AGENT_BROWSER_LOCAL_CONFIG) {
        throw 'AGENT_BROWSER_LOCAL_CONFIG points to a missing file.'
    }
    if (-not $SkipDirectoryInitialization) {
        foreach ($pathKey in 'RuntimeDirectory', 'LogDirectory') {
            New-Item -ItemType Directory -Force -Path $config[$pathKey] | Out-Null
        }
    }
    return $config
}

function Resolve-AgentBrowserCli {
    param(
        [string[]]$Candidates,
        [switch]$SkipDirectoryInitialization
    )

    if (-not $Candidates) {
        $config = Get-AgentBrowserLocalConfig -SkipDirectoryInitialization:$SkipDirectoryInitialization
        if ($config.CanonicalCliHint) {
            if (-not (Test-Path -LiteralPath $config.CanonicalCliHint -PathType Leaf)) {
                throw 'Configured native CLI is missing. Update CanonicalCliHint or clear it to follow PATH.'
            }
            $Candidates = @($config.CanonicalCliHint)
        }
        else {
            $Candidates = @(Get-Command agent-browser -All -ErrorAction SilentlyContinue | ForEach-Object {
                $commandDir = Split-Path $_.Source -Parent
                Join-Path $commandDir 'node_modules\agent-browser\bin\agent-browser-win32-x64.exe'
                if ($_.Source -like '*.exe') { $_.Source }
            })
        }
    }

    $result = $Candidates |
        Where-Object { $_ -and $_ -like '*.exe' -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -First 1

    if (-not $result) {
        throw 'No canonical agent-browser CLI was found outside the local shadow-wrapper path.'
    }
    return $result
}

function Resolve-AgentBrowserChrome {
    param([string[]]$Candidates)

    if (-not $Candidates) {
        $config = Get-AgentBrowserLocalConfig
        $Candidates = @(Get-ChildItem -LiteralPath $config.BrowserRoot -Directory -Filter 'chrome-*' -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'chrome.exe' } |
            Where-Object { Test-Path -LiteralPath $_ })
    }

    $ranked = foreach ($candidate in $Candidates | Where-Object {
        $_ -and (Test-Path -LiteralPath $_ -PathType Leaf -ErrorAction SilentlyContinue)
    }) {
        $match = [regex]::Match($candidate, 'chrome-(?<version>\d+(?:\.\d+){1,3})', 'IgnoreCase')
        if ($match.Success) {
            [pscustomobject]@{
                Path = $candidate
                Version = [version]$match.Groups['version'].Value
            }
        }
    }
    $result = $ranked | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $result) {
        throw 'No installed Chrome for Testing executable was found.'
    }
    return $result.Path
}

function Get-CdpVersion {
    param([Parameter(Mandatory)][int]$Port)

    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2
    }
    catch {
        return $null
    }
}

function Get-AgentBrowserNormalizedPath {
    param([Parameter(Mandatory)][string]$Path)

    return [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
}

function Get-AgentBrowserCommandLineArguments {
    param([Parameter(Mandatory)][string]$CommandLine)

    if (-not ('AgentBrowserLocal.NativeCommandLine' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace AgentBrowserLocal {
    public static class NativeCommandLine {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr CommandLineToArgvW(string commandLine, out int argumentCount);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr LocalFree(IntPtr memory);
    }
}
'@
    }

    $count = 0
    $pointer = [AgentBrowserLocal.NativeCommandLine]::CommandLineToArgvW($CommandLine, [ref]$count)
    if ($pointer -eq [IntPtr]::Zero -or $count -eq 0) {
        return @()
    }

    try {
        $parsedArguments = @(for ($index = 0; $index -lt $count; $index++) {
            $argumentPointer = [Runtime.InteropServices.Marshal]::ReadIntPtr($pointer, $index * [IntPtr]::Size)
            [Runtime.InteropServices.Marshal]::PtrToStringUni($argumentPointer)
        })
        if ($parsedArguments.Count -le 1) {
            return @()
        }
        return @($parsedArguments[1..($parsedArguments.Count - 1)])
    }
    finally {
        [void][AgentBrowserLocal.NativeCommandLine]::LocalFree($pointer)
    }
}

function Test-AgentBrowserAuthArgumentSet {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)]$Config
    )

    $required = @{
        '--remote-debugging-address' = $Config.CdpAddress
        '--remote-debugging-port' = [string]$Config.CdpPort
        '--user-data-dir' = Get-AgentBrowserNormalizedPath -Path $Config.AuthProfilePath
    }

    foreach ($name in $required.Keys) {
        $matches = @()
        for ($index = 0; $index -lt $Arguments.Count; $index++) {
            $argument = $Arguments[$index]
            $value = $null
            if ($argument.Equals($name, [StringComparison]::OrdinalIgnoreCase)) {
                if ($index + 1 -lt $Arguments.Count) {
                    $value = $Arguments[$index + 1]
                    $index++
                }
            }
            elseif ($argument.StartsWith("$name=", [StringComparison]::OrdinalIgnoreCase)) {
                $value = $argument.Substring($name.Length + 1)
            }

            if ($null -ne $value) {
                $matches += $value
            }
        }

        if ($matches.Count -ne 1) {
            return $false
        }

        $actual = $matches[0]
        $expected = $required[$name]
        if ($name -eq '--user-data-dir') {
            try {
                $actual = Get-AgentBrowserNormalizedPath -Path $actual
            }
            catch {
                return $false
            }
            if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
        }
        elseif (-not $actual.Equals($expected, [StringComparison]::Ordinal)) {
            return $false
        }
    }

    foreach ($name in '--no-first-run', '--no-default-browser-check') {
        $matches = @($Arguments | Where-Object { $_.Equals($name, [StringComparison]::OrdinalIgnoreCase) })
        if ($matches.Count -ne 1) {
            return $false
        }
    }

    # Only our canonical headless flag is allowed; duplicate/alternate launch flags fail closed.
    if (@($Arguments | Where-Object { $_ -eq '--headless=new' }).Count -gt 1) { return $false }
    $positionalArguments = @()
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]
        $matchedValueSwitch = $false
        foreach ($name in $required.Keys) {
            if ($argument.Equals($name, [StringComparison]::OrdinalIgnoreCase)) {
                $index++
                $matchedValueSwitch = $true
                break
            }
            if ($argument.StartsWith("$name=", [StringComparison]::OrdinalIgnoreCase)) {
                $matchedValueSwitch = $true
                break
            }
        }
        if ($matchedValueSwitch) {
            continue
        }
        if ($argument -in @('--no-first-run', '--no-default-browser-check', '--headless=new')) {
            continue
        }
        if ($argument.StartsWith('--', [StringComparison]::Ordinal)) {
            return $false
        }
        $positionalArguments += $argument
    }

    if ($positionalArguments.Count -ne 1) {
        return $false
    }
    $url = $positionalArguments[0]
    if ($url -ceq 'about:blank') {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($url) -or $url -match '[\x00-\x20]') {
        return $false
    }
    $uri = $null
    return [bool]([Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -and
        $uri.Scheme -in @('http', 'https') -and
        -not [string]::IsNullOrEmpty($uri.Host) -and
        -not $uri.UserInfo)

}

function Test-AgentBrowserAuthProcess {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)]$Config
    )

    if (-not $Process -or -not $Process.Name -or -not $Process.CommandLine) {
        return $false
    }
    if (-not $Process.Name.Equals('chrome.exe', [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    $processExecutableProperty = $Process.PSObject.Properties['ExecutablePath']
    if (-not $processExecutableProperty -or -not $processExecutableProperty.Value) {
        return $false
    }

    try {
        $expectedExecutable = Resolve-AgentBrowserChrome
        $actualExecutable = Get-AgentBrowserNormalizedPath -Path ([string]$processExecutableProperty.Value)
        $expectedExecutable = Get-AgentBrowserNormalizedPath -Path $expectedExecutable
    }
    catch {
        return $false
    }
    if (-not $actualExecutable.Equals($expectedExecutable, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    return Test-AgentBrowserAuthArgumentSet -Arguments (Get-AgentBrowserCommandLineArguments -CommandLine $Process.CommandLine) -Config $Config
}

function New-AgentBrowserAuthMutex {
    return [Threading.Mutex]::new($false, 'Local\AgentBrowserAuthOperation')
}

function Wait-AgentBrowserAuthMutex {
    param(
        [Parameter(Mandatory)]$Mutex,
        [Parameter(Mandatory)][TimeSpan]$Timeout
    )

    return $Mutex.WaitOne($Timeout)
}

function Invoke-AgentBrowserAuthOperation {
    param(
        [Parameter(Mandatory)][scriptblock]$Operation,
        [string]$TimeoutMessage = 'Timed out waiting for the authenticated browser operation lock.'
    )

    $mutex = New-AgentBrowserAuthMutex
    $mutexAcquired = $false
    try {
        try {
            $mutexAcquired = [bool](Wait-AgentBrowserAuthMutex -Mutex $mutex -Timeout ([TimeSpan]::FromSeconds($script:AuthOperationTimeoutSeconds)))
        }
        catch [Threading.AbandonedMutexException] {
            $mutexAcquired = $true
        }
        if (-not $mutexAcquired) {
            throw $TimeoutMessage
        }
        return & $Operation
    }
    finally {
        try {
            if ($mutexAcquired) {
                $mutex.ReleaseMutex()
            }
        }
        finally {
            $mutex.Dispose()
        }
    }
}

function New-AgentBrowserAuthWebSocket {
    return [Net.WebSockets.ClientWebSocket]::new()
}

function New-AgentBrowserAuthCancellationTokenSource {
    param([Parameter(Mandatory)][TimeSpan]$Timeout)

    return [Threading.CancellationTokenSource]::new($Timeout)
}

function Assert-AgentBrowserLocalCliArgs {
    param([string[]]$CommandArgs, [ValidateSet('test', 'auth')][string]$Mode, [int]$Depth = 0)
    if (-not $CommandArgs -or $Depth -gt 8) {
        Throw-AgentBrowserLocalUsageError 'Missing command or batch nesting exceeds eight levels.'
    }
    # Require command-first syntax; unknown/new command families require review.
    $allowed = @('open','navigate','read','click','dblclick','type','fill','press','keyboard',
        'hover','focus','check','uncheck','select','drag','upload','download','scroll','scrollintoview',
        'wait','screenshot','pdf','snapshot','eval','back','forward','reload','get','is','find',
        'mouse','set','network','cookies','storage','tab','diff','trace','profiler','record',
        'console','errors','highlight','inspect','clipboard','react','vitals','pushstate',
        'removeinitscript','addinitscript','frame','dialog','a11y','confirm','deny','batch','close')
    $command = $CommandArgs[0]
    if ($command -notin $allowed -or ($Mode -eq 'auth' -and $command -eq 'close')) {
        Throw-AgentBrowserLocalUsageError "Command '$command' is outside managed $Mode mode."
    }
    # CLI flags can occur after the command. Never allow a second routing source.
    foreach ($arg in $CommandArgs) {
        if ($arg -match '^--(?:profile|session|session-name|namespace|restore(?:-[a-z-]+)?|state|cdp|headed|headless|auto-connect|config|provider|engine|executable-path|args|extension|extensions|plugins)(?:=|$)' -or $arg -match '^-p') {
            Throw-AgentBrowserLocalUsageError "Prohibited agent-browser $Mode argument '$arg'."
        }
    }
    if ($command -eq 'close' -and $Depth -gt 0) { Throw-AgentBrowserLocalUsageError 'Close sessions outside batch.' }
    if ($command -eq 'close' -and $CommandArgs.Count -ne 1) {
        Throw-AgentBrowserLocalUsageError 'Only a targeted close without extra arguments is allowed.'
    }
    if ($command -eq 'batch') {
        if ($Depth -gt 0) { Throw-AgentBrowserLocalUsageError 'Nested batches are unsupported; pass a flat list of command arrays.' }
        $commands = @($CommandArgs | Select-Object -Skip 1 | Where-Object { $_ -notin @('--bail','--json') })
        if (-not $commands) { Throw-AgentBrowserLocalUsageError 'Pass batch JSON arrays as arguments; stdin batch is not supported.' }
        foreach ($json in $commands) {
            try { $parsed = ConvertFrom-Json -InputObject $json -NoEnumerate -ErrorAction Stop }
            catch { Throw-AgentBrowserLocalUsageError 'Invalid batch JSON array.' }
            if ($parsed -isnot [array] -or $parsed.Count -eq 0 -or @($parsed | Where-Object { $_ -isnot [string] }).Count) {
                Throw-AgentBrowserLocalUsageError 'Each batch item must be a nonempty JSON array of strings.'
            }
            Assert-AgentBrowserLocalCliArgs -CommandArgs $parsed -Mode $Mode -Depth ($Depth + 1)
        }
    }
    if ($command -eq 'eval' -and '--stdin' -in $CommandArgs) {
        Throw-AgentBrowserLocalUsageError 'stdin forwarding is unsupported; use eval -b <base64>.'
    }
}

function ConvertTo-AgentBrowserBatchInput {
    param([string[]]$CommandArgs)
    $items = [Collections.Generic.List[object]]::new()
    foreach ($json in @($CommandArgs | Select-Object -Skip 1 | Where-Object { $_ -notin @('--bail','--json') })) {
        $items.Add((ConvertFrom-Json -InputObject $json -NoEnumerate))
    }
    return ConvertTo-Json -InputObject $items.ToArray() -Depth 12 -Compress
}

function Assert-AgentBrowserAuthCommandArgs {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$CommandArgs)
    Assert-AgentBrowserLocalCliArgs -CommandArgs $CommandArgs -Mode auth
}

function Get-AgentBrowserAuthStatus {
    param([switch]$SkipDirectoryInitialization)

    $config = Get-AgentBrowserLocalConfig -SkipDirectoryInitialization:$SkipDirectoryInitialization
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $config.CdpPort -ErrorAction SilentlyContinue)

    if (-not $listeners) {
        return [pscustomobject]@{
            Ready = $false
            Headless = $null
            PortOccupied = $false
            Pid = $null
            OwnerPid = $null
            Reason = 'not-running'
            WebSocketDebuggerUrl = $null
        }
    }

    $listener = $listeners | Where-Object {
        $config.CdpAddress -eq '127.0.0.1' -and [string]$_.LocalAddress -eq $config.CdpAddress
    } | Select-Object -First 1
    if (-not $listener) {
        $owner = $listeners | Select-Object -First 1
        return [pscustomobject]@{
            Ready = $false
            Headless = $null
            PortOccupied = $true
            Pid = $owner.OwningProcess
            OwnerPid = $owner.OwningProcess
            Reason = 'unexpected-owner'
            WebSocketDebuggerUrl = $null
        }
    }

    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)" -ErrorAction SilentlyContinue
    $expected = Test-AgentBrowserAuthProcess -Process $process -Config $config
    $cdp = if ($expected) { Get-CdpVersion -Port $config.CdpPort } else { $null }
    $webSocketDebuggerUrl = if ($cdp) { $cdp.webSocketDebuggerUrl } else { $null }
    $ready = [bool]($expected -and $cdp -and $webSocketDebuggerUrl)

    return [pscustomobject]@{
        Ready = $ready
        Headless = if ($expected) { '--headless=new' -in (Get-AgentBrowserCommandLineArguments -CommandLine $process.CommandLine) } else { $null }
        PortOccupied = $true
        Pid = $listener.OwningProcess
        OwnerPid = $listener.OwningProcess
        Reason = if ($ready) { 'ready' } else { 'unexpected-owner' }
        Browser = if ($cdp) { $cdp.Browser } else { $null }
        WebSocketDebuggerUrl = if ($ready) { $webSocketDebuggerUrl } else { $null }
    }
}

function Assert-AgentBrowserAuthStartUrl {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url) -or $Url -match '[\x00-\x20]' -or $Url.StartsWith('-', [StringComparison]::Ordinal)) {
        Throw-AgentBrowserLocalUsageError "Invalid auth start URL '$Url'. Use about:blank or an absolute http:// or https:// URL.`n$(Get-AgentBrowserLocalHelpHint)"
    }
    if ($Url -ceq 'about:blank') {
        return
    }

    $uri = $null
    $valid = [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)
    if (-not $valid -or $uri.Scheme -notin @('http', 'https') -or [string]::IsNullOrEmpty($uri.Host) -or $uri.UserInfo) {
        Throw-AgentBrowserLocalUsageError "Invalid auth start URL '$Url'. Use about:blank or an absolute http:// or https:// URL.`n$(Get-AgentBrowserLocalHelpHint)"
    }
}

function Start-AgentBrowserAuthCore {
    param([Parameter(Mandatory)][string]$Url, [switch]$Headless)

    $config = Get-AgentBrowserLocalConfig
    $status = Get-AgentBrowserAuthStatus
    if ($status.Ready) {
        if ([bool]$status.Headless -ne [bool]$Headless) {
            throw 'Authenticated browser is running in a different display mode. Use auth stop, then auth start with --headed or --headless. The existing browser was left running.'
        }
        if ($Url -and $Url -ne 'about:blank') {
            Invoke-AgentBrowserAuthCore -CommandArgs @('open', $Url) | Out-Null
        }
        return $status
    }

    if ($status.PortOccupied) {
        throw "CDP port $($config.CdpPort) is occupied by unexpected PID $($status.Pid)."
    }

    $chrome = Resolve-AgentBrowserChrome
    New-Item -ItemType Directory -Force -Path $config.AuthProfilePath | Out-Null
    $arguments = @(
        "--remote-debugging-address=$($config.CdpAddress)",
        "--remote-debugging-port=$($config.CdpPort)",
        '--no-first-run',
        '--no-default-browser-check',
        "--user-data-dir=$($config.AuthProfilePath)"
    ) + $(if ($Headless) { @('--headless=new') } else { @() }) + @(
        $Url
    )
    # ArgumentList on Start-Process flattens strings and breaks profile paths with spaces.
    $browserStart = [Diagnostics.ProcessStartInfo]::new()
    $browserStart.FileName = $chrome
    $browserStart.UseShellExecute = $false
    foreach ($argument in $arguments) { $browserStart.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($browserStart)
    $deadline = (Get-Date).AddSeconds($config.BrowserStartTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 250
        $status = Get-AgentBrowserAuthStatus
    } until ($status.Ready -or (Get-Date) -ge $deadline -or $process.HasExited)

    if (-not $status.Ready) {
        throw "Authenticated browser did not expose the expected CDP endpoint. Started PID: $($process.Id)."
    }

    Set-Content -LiteralPath (Join-Path $config.RuntimeDirectory 'auth-browser.pid') -Value $status.Pid
    Write-AgentBrowserLocalLog -Event 'auth.start' -Data @{ pid = $status.Pid; port = $config.CdpPort; headless = [bool]$Headless }
    # CDP readiness does not imply the CLI's selected page has loaded the launch URL.
    if ($Url -ne 'about:blank') {
        Invoke-AgentBrowserAuthCore -CommandArgs @('open', $Url) | Out-Null
    }
    return $status
}

function Start-AgentBrowserAuth {
    param([string]$Url = 'about:blank', [switch]$Headless)

    Assert-AgentBrowserAuthStartUrl -Url $Url
    return Invoke-AgentBrowserAuthOperation -TimeoutMessage 'Timed out waiting for the authenticated browser startup lock.' -Operation {
        Start-AgentBrowserAuthCore -Url $Url -Headless:$Headless
    }
}

function Invoke-AgentBrowserAuthCore {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$CommandArgs,
        [scriptblock]$Executor
    )

    Assert-AgentBrowserAuthCommandArgs -CommandArgs $CommandArgs
    $config = Get-AgentBrowserLocalConfig
    $status = Get-AgentBrowserAuthStatus
    if (-not $status.Ready) {
        throw 'Authenticated browser is not running. Use auth start first.'
    }

    $cli = Resolve-AgentBrowserCli
    $batchInput = $null
    $nativeCommandArgs = $CommandArgs
    if ($CommandArgs[0] -eq 'batch') {
        $batchInput = ConvertTo-AgentBrowserBatchInput $CommandArgs
        $nativeCommandArgs = @('batch') + @($CommandArgs | Where-Object { $_ -in @('--bail','--json') })
    }
    $arguments = @('--config', (Join-Path $PSScriptRoot '..\cli-config.json'), '--session', $script:AuthCliSession, '--cdp', [string]$config.CdpPort) + $nativeCommandArgs
    Write-AgentBrowserLocalLog -Event 'auth.invoke' -Data @{ command = $CommandArgs[0]; pid = $status.Pid }
    return Invoke-CleanAgentBrowserEnvironment {
        if ($Executor) {
            return & $Executor $cli $arguments
        }

        $result = Invoke-BoundedAgentBrowserProcess -Executable $cli -Arguments $arguments -TimeoutSeconds $script:AuthCliTimeoutSeconds -InputText $batchInput
        if ($result.TimedOut) {
            $exception = [InvalidOperationException]::new(
                "Authenticated agent-browser command timed out after $($script:AuthCliTimeoutSeconds) seconds. PID: $($result.Pid). It was not terminated."
            )
            $exception.Data['AgentBrowserPid'] = $result.Pid
            $exception.Data['AgentBrowserProcessTree'] = $result.ProcessTree
            throw $exception
        }
        if ($result.ExitCode -ne 0) {
            $exception = [InvalidOperationException]::new(
                "Authenticated agent-browser command failed with exit code $($result.ExitCode)."
            )
            $exception.Data['AgentBrowserPid'] = $result.Pid
            $exception.Data['AgentBrowserStdErr'] = [string]$result.StdErr
            throw $exception
        }
        return ([string]$result.StdOut).Trim()
    }
}

function Invoke-AgentBrowserAuth {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$CommandArgs,
        [scriptblock]$Executor
    )

    Assert-AgentBrowserAuthCommandArgs -CommandArgs $CommandArgs
    return Invoke-AgentBrowserAuthOperation -Operation {
        Invoke-AgentBrowserAuthCore -CommandArgs $CommandArgs -Executor $Executor
    }
}

function Close-AgentBrowserAuthDaemon {
    param([scriptblock]$Executor)

    $cli = Resolve-AgentBrowserCli
    $arguments = @('--config', (Join-Path $PSScriptRoot '..\cli-config.json'), '--session', $script:AuthCliSession, 'close')
    return Invoke-CleanAgentBrowserEnvironment {
        if ($Executor) {
            return & $Executor $cli $arguments
        }

        $result = Invoke-BoundedAgentBrowserProcess -Executable $cli -Arguments $arguments -TimeoutSeconds $script:AuthCliTimeoutSeconds
        if ($result.TimedOut) {
            $exception = [InvalidOperationException]::new(
                "Reserved auth daemon close timed out after $($script:AuthCliTimeoutSeconds) seconds. PID: $($result.Pid). It was not terminated."
            )
            $exception.Data['AgentBrowserPid'] = $result.Pid
            $exception.Data['AgentBrowserProcessTree'] = $result.ProcessTree
            throw $exception
        }
        if ($result.ExitCode -ne 0) {
            $exception = [InvalidOperationException]::new(
                "Reserved auth daemon close failed with exit code $($result.ExitCode)."
            )
            $exception.Data['AgentBrowserPid'] = $result.Pid
            $exception.Data['AgentBrowserStdErr'] = [string]$result.StdErr
            throw $exception
        }
        return ([string]$result.StdOut).Trim()
    }
}

function Stop-AgentBrowserAuthCore {
    $config = Get-AgentBrowserLocalConfig
    $markerPath = Join-Path $config.RuntimeDirectory 'auth-browser.pid'
    $status = Get-AgentBrowserAuthStatus
    if ($status.Reason -eq 'not-running') {
        Remove-Item -LiteralPath $markerPath -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Stopped = $true; Reason = 'not-running' }
    }
    if (-not $status.Ready) {
        throw "Refusing to stop authenticated browser: $($status.Reason) PID $($status.Pid)."
    }

    $ownerPid = if ($null -ne $status.OwnerPid) { $status.OwnerPid } else { $status.Pid }
    $webSocketDebuggerUrl = $status.WebSocketDebuggerUrl
    if (-not $webSocketDebuggerUrl) {
        throw 'Authenticated browser status did not include a validated CDP WebSocket URL.'
    }

    $markerPid = 0
    $markerText = Get-Content -Raw -LiteralPath $markerPath -ErrorAction SilentlyContinue
    if (-not [int]::TryParse(([string]$markerText).Trim(), [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$markerPid) -or $markerPid -le 0 -or $markerPid -ne $ownerPid) {
        throw "Refusing to stop authenticated browser: PID marker does not match validated owner PID $ownerPid."
    }

    $beforeConnect = Get-AgentBrowserAuthStatus
    $connectOwnerPid = if ($null -ne $beforeConnect.OwnerPid) { $beforeConnect.OwnerPid } else { $beforeConnect.Pid }
    if (-not $beforeConnect.Ready -or $connectOwnerPid -ne $ownerPid -or $beforeConnect.WebSocketDebuggerUrl -ne $webSocketDebuggerUrl) {
        throw 'Authenticated browser ownership changed before Browser.close.'
    }

    $socket = New-AgentBrowserAuthWebSocket
    $connectTokenSource = $null
    $sendTokenSource = $null
    try {
        $connectTokenSource = New-AgentBrowserAuthCancellationTokenSource -Timeout ([TimeSpan]::FromSeconds(5))
        $uri = [Uri]$webSocketDebuggerUrl
        [void]$socket.ConnectAsync($uri, $connectTokenSource.Token).GetAwaiter().GetResult()

        $beforeSend = Get-AgentBrowserAuthStatus
        $sendOwnerPid = if ($null -ne $beforeSend.OwnerPid) { $beforeSend.OwnerPid } else { $beforeSend.Pid }
        if (-not $beforeSend.Ready -or $sendOwnerPid -ne $ownerPid -or $beforeSend.WebSocketDebuggerUrl -ne $webSocketDebuggerUrl) {
            throw 'Authenticated browser ownership changed before Browser.close.'
        }

        $sendTokenSource = New-AgentBrowserAuthCancellationTokenSource -Timeout ([TimeSpan]::FromSeconds(5))
        $payload = [Text.Encoding]::UTF8.GetBytes('{"id":1,"method":"Browser.close"}')
        $segment = [ArraySegment[byte]]::new($payload)
        [void]$socket.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, $sendTokenSource.Token).GetAwaiter().GetResult()
    }
    finally {
        if ($sendTokenSource) {
            [void]$sendTokenSource.Dispose()
        }
        if ($connectTokenSource) {
            [void]$connectTokenSource.Dispose()
        }
        if ($socket) {
            [void]$socket.Dispose()
        }
    }

    $deadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 250
        $stillRunning = Get-Process -Id $status.Pid -ErrorAction SilentlyContinue
    } until (-not $stillRunning -or (Get-Date) -ge $deadline)

    if ($stillRunning) {
        throw "Chrome PID $($status.Pid) did not exit after Browser.close. It was not force-terminated."
    }

    Remove-Item -LiteralPath $markerPath -ErrorAction SilentlyContinue
    # Release the reserved CLI connection before the next CDP endpoint starts.
    Close-AgentBrowserAuthDaemon | Out-Null
    Write-AgentBrowserLocalLog -Event 'auth.stop' -Data @{ pid = $status.Pid }
    return [pscustomobject]@{ Stopped = $true; Reason = 'graceful-close' }
}

function Stop-AgentBrowserAuth {
    return Invoke-AgentBrowserAuthOperation -TimeoutMessage 'Timed out waiting for the authenticated browser stop lock.' -Operation {
        Stop-AgentBrowserAuthCore
    }
}

function Invoke-CleanAgentBrowserEnvironment {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock)

    $saved = @{}
    $names = @($script:RoutingEnvironmentVariables) + @(Get-ChildItem Env: | Where-Object { $_.Name -like 'AGENT_BROWSER_*' -and $_.Name -ne 'AGENT_BROWSER_LOCAL_CONFIG' } | ForEach-Object Name) | Select-Object -Unique
    foreach ($name in $names) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    try {
        & $ScriptBlock
    }
    finally {
        foreach ($name in $names) {
            if ($null -eq $saved[$name]) {
                Remove-Item "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item "Env:$name" $saved[$name]
            }
        }
    }
}

function Test-AgentBrowserSidecarStale {
    param(
        [Parameter(Mandatory)][bool]$PidAlive,
        [Parameter(Mandatory)][bool]$PortListening
    )

    return (-not $PidAlive) -and (-not $PortListening)
}

function Get-AgentBrowserPortListening {
    param([Parameter(Mandatory)][int]$Port)

    if ($Port -le 0) {
        return $false
    }

    return (@(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue).Count -gt 0)
}

function Get-AgentBrowserChromeSnapshot {
    $deadline = (Get-Date).AddSeconds(2)
    $records = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'chrome.exe'" -OperationTimeoutSec 2 -ErrorAction SilentlyContinue |
        Select-Object ProcessId, ParentProcessId, ExecutablePath, CommandLine, Name)
    $chromePids = @{}
    foreach ($record in $records) {
        $chromePids[[string]$record.ProcessId] = $true
    }

    $snapshot = foreach ($record in $records) {
        if ((Get-Date) -ge $deadline) {
            break
        }

        $native = Get-Process -Id $record.ProcessId -ErrorAction SilentlyContinue
        $processId = [int]$record.ProcessId
        $parentProcessId = [int]$record.ParentProcessId
        $executablePath = if ($native -and $native.Path) { [string]$native.Path } else { [string]$record.ExecutablePath }
        $mainWindowHandle = if ($native) { [int64]$native.MainWindowHandle } else { [int64]0 }
        [pscustomobject]@{
            ProcessId = $processId
            ParentProcessId = $parentProcessId
            ExecutablePath = $executablePath
            CommandLine = [string]$record.CommandLine
            MainWindowHandle = $mainWindowHandle
            Pid = $processId
            ParentPid = $parentProcessId
            TopLevel = -not $chromePids.ContainsKey([string]$record.ParentProcessId)
            Visible = $mainWindowHandle -ne 0
        }
    }
    return @($snapshot)
}

function Get-AgentBrowserMaintenanceProcessTree {
    param(
        [Parameter(Mandatory)][int]$RootPid,
        [object[]]$ProcessSnapshot
    )

    $records = if ($PSBoundParameters.ContainsKey('ProcessSnapshot')) {
        @($ProcessSnapshot)
    }
    else {
        @(Get-CimInstance -ClassName Win32_Process -OperationTimeoutSec 2 -ErrorAction SilentlyContinue |
            Select-Object ProcessId, ParentProcessId, Name)
    }

    $processesById = @{}
    $childrenByParentId = @{}
    foreach ($record in $records) {
        $processId = [int]$record.ProcessId
        $parentProcessId = [int]$record.ParentProcessId
        if ($processesById.ContainsKey($processId)) {
            continue
        }

        $processesById[$processId] = [pscustomobject]@{
            Pid = $processId
            ParentPid = $parentProcessId
            Name = [string]$record.Name
        }
        if (-not $childrenByParentId.ContainsKey($parentProcessId)) {
            $childrenByParentId[$parentProcessId] = [Collections.Generic.List[int]]::new()
        }
        $childrenByParentId[$parentProcessId].Add($processId)
    }

    $seen = @{}
    $pending = [Collections.Generic.Queue[int]]::new()
    $pending.Enqueue($RootPid)
    $snapshot = [Collections.Generic.List[object]]::new()
    while ($pending.Count -gt 0) {
        $processId = $pending.Dequeue()
        if ($seen.ContainsKey($processId)) {
            continue
        }
        $seen[$processId] = $true

        if ($processesById.ContainsKey($processId)) {
            $snapshot.Add($processesById[$processId])
        }
        elseif ($processId -eq $RootPid) {
            $snapshot.Add([pscustomobject]@{ Pid = $RootPid; ParentPid = $null; Name = $null })
        }

        if ($childrenByParentId.ContainsKey($processId)) {
            foreach ($childProcessId in $childrenByParentId[$processId]) {
                if (-not $seen.ContainsKey($childProcessId)) {
                    $pending.Enqueue($childProcessId)
                }
            }
        }
    }
    return @($snapshot)
}

function New-AgentBrowserConcurrentLineCapture {
    param([Parameter(Mandatory)]$CallbackGate)

    if (-not ('AgentBrowserLocal.ConcurrentLineCaptureV3' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Threading;

namespace AgentBrowserLocal {
    public sealed class ConcurrentLineCaptureV3 {
        private readonly object callbackSyncRoot;
        public ConcurrentQueue<string> Lines { get; } = new ConcurrentQueue<string>();
        public DataReceivedEventHandler Handler { get; }
        public bool HandlerAttached { get; private set; }
        public int CallbackDelayMilliseconds { get; set; }

        public ConcurrentLineCaptureV3(object callbackSyncRoot) {
            this.callbackSyncRoot = callbackSyncRoot ?? throw new ArgumentNullException(nameof(callbackSyncRoot));
            Handler = OnDataReceived;
        }

        public void MarkAttached() {
            HandlerAttached = true;
        }

        public void MarkDetached() {
            HandlerAttached = false;
        }

        private void OnDataReceived(object sender, DataReceivedEventArgs eventArgs) {
            bool lockTaken = false;
            try {
                Monitor.Enter(callbackSyncRoot, ref lockTaken);
                if (eventArgs.Data != null) {
                    if (CallbackDelayMilliseconds > 0) {
                        Thread.Sleep(CallbackDelayMilliseconds);
                    }
                    Lines.Enqueue(eventArgs.Data);
                }
            }
            finally {
                if (lockTaken) {
                    Monitor.Exit(callbackSyncRoot);
                }
            }
        }
    }
}
'@
    }
    return [AgentBrowserLocal.ConcurrentLineCaptureV3]::new($CallbackGate)
}

function Add-AgentBrowserCapturedLines {
    param(
        [Parameter(Mandatory)]$Capture,
        [Parameter(Mandatory)][Text.StringBuilder]$Builder
    )

    $line = $null
    $count = 0
    while ($Capture.Lines.TryDequeue([ref]$line)) {
        [void]$Builder.AppendLine($line)
        $line = $null
        $count++
    }
    return $count
}

function Wait-AgentBrowserPostExitQuietWindow {
    param(
        [Parameter(Mandatory)]$CallbackGate,
        [Parameter(Mandatory)]$StdOutCapture,
        [Parameter(Mandatory)]$StdErrCapture,
        [ValidateRange(1, 500)][int]$MaximumMilliseconds = 500,
        [ValidateRange(2, 5)][int]$ConsecutiveStableSamples = 3,
        [ValidateRange(10, 100)][int]$SampleIntervalMilliseconds = 100
    )

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $previousStdOutCount = $null
    $previousStdErrCount = $null
    $stableSamples = 0
    do {
        $lockTaken = $false
        try {
            [Threading.Monitor]::Enter($CallbackGate, [ref]$lockTaken)
            $stdOutCount = $StdOutCapture.Lines.Count
            $stdErrCount = $StdErrCapture.Lines.Count
        }
        finally {
            if ($lockTaken) {
                [Threading.Monitor]::Exit($CallbackGate)
            }
        }

        if ($stdOutCount -eq $previousStdOutCount -and $stdErrCount -eq $previousStdErrCount) {
            $stableSamples++
        }
        else {
            $previousStdOutCount = $stdOutCount
            $previousStdErrCount = $stdErrCount
            $stableSamples = 0
        }
        if ($stableSamples -ge $ConsecutiveStableSamples -or $stopwatch.ElapsedMilliseconds -ge $MaximumMilliseconds) {
            return
        }

        $remainingMilliseconds = $MaximumMilliseconds - [int]$stopwatch.ElapsedMilliseconds
        Start-Sleep -Milliseconds ([Math]::Min($SampleIntervalMilliseconds, [Math]::Max(1, $remainingMilliseconds)))
    } while ($stopwatch.ElapsedMilliseconds -lt $MaximumMilliseconds)
}

function Invoke-BoundedAgentBrowserProcess {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments,
        [Parameter(Mandatory)][ValidateRange(1, 300)][int]$TimeoutSeconds,
        [scriptblock]$AfterStdOutReaderStarted,
        [AllowNull()][string]$InputText
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.UseShellExecute = $false
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $PSBoundParameters.ContainsKey('InputText') -and $null -ne $InputText
    $startInfo.CreateNoWindow = $true

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stdout = [Text.StringBuilder]::new()
    $stderr = [Text.StringBuilder]::new()
    $callbackGate = [object]::new()
    $stdoutCapture = New-AgentBrowserConcurrentLineCapture -CallbackGate $callbackGate
    $stderrCapture = New-AgentBrowserConcurrentLineCapture -CallbackGate $callbackGate
    $readerState = [pscustomobject]@{
        Process = $process
        StdOutReaderStarted = $false
        StdErrReaderStarted = $false
        StdOutHandlerAttached = $false
        StdErrHandlerAttached = $false
        StdOutCapture = $stdoutCapture
        StdErrCapture = $stderrCapture
    }
    $timedOut = $false
    $processId = $null
    $processTree = @()
    $exitCode = $null
    try {
        [void]$process.Start()
        $processId = $process.Id
        $process.add_OutputDataReceived($stdoutCapture.Handler)
        $stdoutCapture.MarkAttached()
        $readerState.StdOutHandlerAttached = $true
        $process.BeginOutputReadLine()
        $readerState.StdOutReaderStarted = $true
        if ($AfterStdOutReaderStarted) {
            & $AfterStdOutReaderStarted $readerState
        }

        $process.add_ErrorDataReceived($stderrCapture.Handler)
        $stderrCapture.MarkAttached()
        $readerState.StdErrHandlerAttached = $true
        $process.BeginErrorReadLine()
        $readerState.StdErrReaderStarted = $true
        $inputClock = [Diagnostics.Stopwatch]::StartNew()
        if ($startInfo.RedirectStandardInput) {
            $inputWrite = $process.StandardInput.WriteAsync($InputText)
            if (-not $inputWrite.Wait($TimeoutSeconds * 1000)) { $timedOut = $true }
            if (-not $timedOut) { $process.StandardInput.Close() }
        }
        $remaining = [Math]::Max(0, $TimeoutSeconds * 1000 - [int]$inputClock.ElapsedMilliseconds)
        if ($timedOut -or -not $process.WaitForExit($remaining)) {
            $timedOut = $true
            $processTree = Get-AgentBrowserMaintenanceProcessTree -RootPid $processId
        }
        else {
            $exitCode = $process.ExitCode
            Wait-AgentBrowserPostExitQuietWindow -CallbackGate $callbackGate -StdOutCapture $stdoutCapture -StdErrCapture $stderrCapture
        }
    }
    finally {
        if ($readerState.StdOutReaderStarted) {
            try { $process.CancelOutputRead() } catch { }
            $readerState.StdOutReaderStarted = $false
        }
        if ($readerState.StdErrReaderStarted) {
            try { $process.CancelErrorRead() } catch { }
            $readerState.StdErrReaderStarted = $false
        }
        if ($readerState.StdOutHandlerAttached) {
            $process.remove_OutputDataReceived($stdoutCapture.Handler)
            $stdoutCapture.MarkDetached()
            $readerState.StdOutHandlerAttached = $false
        }
        if ($readerState.StdErrHandlerAttached) {
            $process.remove_ErrorDataReceived($stderrCapture.Handler)
            $stderrCapture.MarkDetached()
            $readerState.StdErrHandlerAttached = $false
        }
        $callbackLockTaken = $false
        try {
            [Threading.Monitor]::Enter($callbackGate, [ref]$callbackLockTaken)
            [void](Add-AgentBrowserCapturedLines -Capture $stdoutCapture -Builder $stdout)
            [void](Add-AgentBrowserCapturedLines -Capture $stderrCapture -Builder $stderr)
        }
        finally {
            if ($callbackLockTaken) {
                [Threading.Monitor]::Exit($callbackGate)
            }
            $process.Dispose()
        }
    }

    if ($timedOut) {
        return [pscustomobject]@{
            TimedOut = $true
            Pid = $processId
            ProcessTree = $processTree
            ExitCode = $null
            StdOut = $null
            StdErr = $null
        }
    }
    return [pscustomobject]@{
        TimedOut = $false
        Pid = $processId
        ProcessTree = @()
        ExitCode = $exitCode
        StdOut = $stdout.ToString()
        StdErr = $stderr.ToString()
    }
}

function Test-AgentBrowserPathUnderRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    try {
        $normalizedPath = [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
        $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
        return $normalizedPath.StartsWith($normalizedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Get-AgentBrowserCliVersion {
    param([Parameter(Mandatory)][string]$Cli)

    if ([IO.Path]::GetExtension($Cli) -ne '.exe') {
        return 'unavailable: canonical CLI is not a native .exe'
    }

    try {
        $result = Invoke-CleanAgentBrowserEnvironment {
            Invoke-BoundedAgentBrowserProcess -Executable $Cli -Arguments @('--version') -TimeoutSeconds 5
        }
    }
    catch {
        return "unavailable: $($_.Exception.Message)"
    }

    if ($result.TimedOut) {
        return 'unavailable: --version timed out after 5 seconds'
    }
    if ($result.ExitCode -ne 0) {
        return "unavailable: --version exited with code $($result.ExitCode)"
    }

    $versionLine = @(([string]$result.StdOut -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) | Select-Object -First 1
    if (-not $versionLine) {
        return 'unavailable: --version returned no output'
    }

    if ($versionLine -match '^(?i:agent-browser)\s+(?:version\s+)?(.+)$') {
        return $matches[1].Trim()
    }
    return $versionLine
}

function New-AgentBrowserMaintenanceMutex {
    return [Threading.Mutex]::new($false, 'Local\AgentBrowserMaintenance')
}

function Wait-AgentBrowserMaintenanceMutex {
    param(
        [Parameter(Mandatory)]$Mutex,
        [Parameter(Mandatory)][TimeSpan]$Timeout
    )

    return $Mutex.WaitOne($Timeout)
}

function Get-AgentBrowserLocalStatus {
    $config = Get-AgentBrowserLocalConfig -SkipDirectoryInitialization
    $cli = Resolve-AgentBrowserCli -SkipDirectoryInitialization
    $authStatus = Get-AgentBrowserAuthStatus -SkipDirectoryInitialization
    $auth = [pscustomobject]@{
        Ready = $authStatus.Ready
        Headless = $authStatus.Headless
        PortOccupied = $authStatus.PortOccupied
        Pid = $authStatus.Pid
        OwnerPid = $authStatus.OwnerPid
        Reason = $authStatus.Reason
    }
    $daemons = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'agent-browser-win32-x64.exe'" -OperationTimeoutSec 2 -ErrorAction SilentlyContinue)
    $chrome = @(Get-AgentBrowserChromeSnapshot)
    $agentChrome = @($chrome | Where-Object {
        $_.ExecutablePath -and (Test-AgentBrowserPathUnderRoot -Path $_.ExecutablePath -Root $config.BrowserRoot)
    })
    $headlessChrome = @($agentChrome | Where-Object {
        $_.TopLevel -and $_.CommandLine -match '(?i)(?:^|\s)--headless(?:=|\s|$)'
    })
    $visibleAgentChrome = @($agentChrome | Where-Object { $_.MainWindowHandle -ne 0 })
    $packagePath = Join-Path (Split-Path (Split-Path $cli -Parent) -Parent) 'package.json'
    $packageVersion = $null
    if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        try { $packageVersion = (Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json).version } catch { }
    }

    return [pscustomobject]@{
        CanonicalCli = $cli
        CliVersion = Get-AgentBrowserCliVersion -Cli $cli
        PackageVersion = $packageVersion
        Auth = $auth
        DaemonCount = $daemons.Count
        ChromeCount = $chrome.Count
        HeadlessChromeCount = $headlessChrome.Count
        VisibleAgentChromeCount = $visibleAgentChrome.Count
        GlobalProfile = [Environment]::GetEnvironmentVariable('AGENT_BROWSER_PROFILE', 'User')
        GlobalSession = [Environment]::GetEnvironmentVariable('AGENT_BROWSER_SESSION', 'User')
    }
}

function Get-StaleAgentBrowserSidecars {
    $root = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agent-browser'
    $results = foreach ($pidFile in Get-ChildItem -LiteralPath $root -Filter '*.pid' -File -ErrorAction SilentlyContinue) {
        $session = [IO.Path]::GetFileNameWithoutExtension($pidFile.Name)
        $pidValue = 0
        $pidText = [string](Get-Content -Raw -LiteralPath $pidFile.FullName -ErrorAction SilentlyContinue)
        [void][int]::TryParse($pidText.Trim(), [ref]$pidValue)

        $daemonPort = 0
        $streamPort = 0
        $portPath = Join-Path $root "$session.port"
        $streamPath = Join-Path $root "$session.stream"
        if (Test-Path -LiteralPath $portPath -PathType Leaf) {
            [void][int]::TryParse(([string](Get-Content -Raw -LiteralPath $portPath -ErrorAction SilentlyContinue)).Trim(), [ref]$daemonPort)
        }
        if (Test-Path -LiteralPath $streamPath -PathType Leaf) {
            [void][int]::TryParse(([string](Get-Content -Raw -LiteralPath $streamPath -ErrorAction SilentlyContinue)).Trim(), [ref]$streamPort)
        }

        $pidAlive = [bool](Get-Process -Id $pidValue -ErrorAction SilentlyContinue)
        $daemonListening = Get-AgentBrowserPortListening -Port $daemonPort
        $streamListening = Get-AgentBrowserPortListening -Port $streamPort
        $anyPortListening = $daemonListening -or $streamListening
        [pscustomobject]@{
            Session = $session
            Pid = $pidValue
            PidAlive = $pidAlive
            DaemonPort = $daemonPort
            DaemonListening = $daemonListening
            StreamPort = $streamPort
            StreamListening = $streamListening
            StaleCandidate = Test-AgentBrowserSidecarStale -PidAlive $pidAlive -PortListening $anyPortListening
        }
    }
    return @($results)
}

function Invoke-AgentBrowserLocalDoctor {
    param([scriptblock]$Executor)

    $config = Get-AgentBrowserLocalConfig
    $mutex = New-AgentBrowserMaintenanceMutex
    $mutexAcquired = $false
    try {
        try {
            $mutexAcquired = [bool](Wait-AgentBrowserMaintenanceMutex -Mutex $mutex -Timeout ([TimeSpan]::FromSeconds(5)))
        }
        catch [Threading.AbandonedMutexException] {
            $mutexAcquired = $true
        }
        if (-not $mutexAcquired) {
            throw 'Another agent-browser maintenance operation is active.'
        }

        $cli = Resolve-AgentBrowserCli
        if ([IO.Path]::GetExtension($cli) -ne '.exe') {
            throw "Doctor requires the canonical native .exe, got '$cli'."
        }

        $arguments = @('doctor', '--offline', '--quick', '--json')
        $beforeChrome = Get-AgentBrowserChromeSnapshot
        $result = Invoke-CleanAgentBrowserEnvironment {
            if ($Executor) {
                return & $Executor $cli $arguments $config.DoctorTimeoutSeconds
            }
            return Invoke-BoundedAgentBrowserProcess -Executable $cli -Arguments $arguments -TimeoutSeconds $config.DoctorTimeoutSeconds
        }
        $afterChrome = Get-AgentBrowserChromeSnapshot
        $newChrome = @($afterChrome | Where-Object {
            $_.Pid -notin @($beforeChrome | ForEach-Object Pid) -and ($_.TopLevel -or $_.Visible)
        })
        $newChromePids = @($newChrome | ForEach-Object Pid)

        if ($result.PSObject.Properties.Match('TimedOut').Count -gt 0 -and $result.TimedOut) {
            $tree = @($result.ProcessTree | ConvertTo-Json -Compress -Depth 3)
            Write-AgentBrowserLocalLog -Event 'maintenance.doctor.timeout' -Data @{
                pid = $result.Pid
                processTree = $tree
                newTopLevelOrVisibleChromePids = $newChromePids
            }
            throw "Doctor timed out after $($config.DoctorTimeoutSeconds) seconds. PID: $($result.Pid). Process tree: $($tree -join ' '). It was not terminated."
        }

        $exitCode = if ($result.PSObject.Properties.Match('ExitCode').Count -gt 0) { $result.ExitCode } else { $null }
        $doctorPid = if ($result.PSObject.Properties.Match('Pid').Count -gt 0) { $result.Pid } else { $null }
        Write-AgentBrowserLocalLog -Event 'maintenance.doctor' -Data @{
            exitCode = $exitCode
            pid = $doctorPid
            newTopLevelOrVisibleChromePids = $newChromePids
        }
        if ($null -ne $exitCode -and $exitCode -ne 0) {
            $stderr = if ($result.PSObject.Properties.Match('StdErr').Count -gt 0) { [string]$result.StdErr } else { '' }
            $detail = if ($stderr) { " $stderr" } else { '' }
            throw "Doctor failed with exit code $exitCode.$detail"
        }
        if ($newChromePids.Count -gt 0) {
            throw "Doctor created top-level or visible Chrome process(es): $($newChromePids -join ', '). They were not terminated automatically."
        }
        return $result
    }
    finally {
        try {
            if ($mutexAcquired) {
                $mutex.ReleaseMutex()
            }
        }
        finally {
            $mutex.Dispose()
        }
    }
}

function Write-AgentBrowserLocalLog {
    param(
        [Parameter(Mandatory)][string]$Event,
        [hashtable]$Data = @{}
    )

    $config = Get-AgentBrowserLocalConfig
    $record = [ordered]@{
        timestamp = [DateTimeOffset]::Now.ToString('o')
        event = $Event
        pid = $PID
        data = $Data
    }
    $line = $record | ConvertTo-Json -Compress -Depth 5
    Add-Content -LiteralPath (Join-Path $config.LogDirectory 'agent-browser-local.jsonl') -Value $line -Encoding utf8
}

function Assert-AgentBrowserTestPrefix {
    param([Parameter(Mandatory)][string]$Prefix)

    if ($Prefix -notmatch '^[A-Za-z0-9_-]+$') {
        Throw-AgentBrowserLocalUsageError "Invalid test session prefix '$Prefix'. Use only letters, digits, hyphens, and underscores.`n$(Get-AgentBrowserLocalHelpHint)"
    }
}

function Get-AgentBrowserSessionRecordPath {
    param([string]$Session)
    $config = Get-AgentBrowserLocalConfig
    return Join-Path $config.RuntimeDirectory "sessions\$Session.json"
}

function Assert-AgentBrowserGeneratedSession {
    param([Parameter(Mandatory)][string]$Session)
    if ($Session -notmatch '^[A-Za-z0-9_-]+-\d{13}-[0-9a-f]{16}$') {
        Throw-AgentBrowserLocalUsageError 'Use the exact session returned by test new.'
    }
    if (-not (Test-Path -LiteralPath (Get-AgentBrowserSessionRecordPath $Session) -PathType Leaf)) {
        Throw-AgentBrowserLocalUsageError 'Test session is unregistered or already closed. Create a new session.'
    }
}

function New-AgentBrowserTestSession {
    param([string]$Prefix = 'test', [switch]$Headed)
    Assert-AgentBrowserTestPrefix -Prefix $Prefix
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $randomBytes = [byte[]]::new(8)
    [Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
    $suffix = [Convert]::ToHexString($randomBytes).ToLowerInvariant()
    $session = "$Prefix-$stamp-$suffix"
    $path = Get-AgentBrowserSessionRecordPath $session
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    @{ session = $session; headed = [bool]$Headed; createdAt = [DateTimeOffset]::UtcNow.ToString('o') } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $path -Encoding utf8
    return $session
}

function Assert-AgentBrowserTestCommandArgs {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$CommandArgs)
    Assert-AgentBrowserLocalCliArgs -CommandArgs $CommandArgs -Mode test
}

function Invoke-AgentBrowserTest {
    param(
        [Parameter(Mandatory)][string]$Session,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$CommandArgs,
        [scriptblock]$Executor
    )

    Assert-AgentBrowserGeneratedSession -Session $Session
    Assert-AgentBrowserTestCommandArgs -CommandArgs $CommandArgs
    $cli = Resolve-AgentBrowserCli
    $record = Get-Content -Raw -LiteralPath (Get-AgentBrowserSessionRecordPath $Session) | ConvertFrom-Json
    $batchInput = $null
    $nativeCommandArgs = $CommandArgs
    if ($CommandArgs[0] -eq 'batch') {
        $batchInput = ConvertTo-AgentBrowserBatchInput $CommandArgs
        $nativeCommandArgs = @('batch') + @($CommandArgs | Where-Object { $_ -in @('--bail','--json') })
    }
    $arguments = @('--config', (Join-Path $PSScriptRoot '..\cli-config.json'), '--session', $Session, '--headed', ([string][bool]$record.headed).ToLowerInvariant()) + $nativeCommandArgs

    Write-AgentBrowserLocalLog -Event 'test.invoke' -Data @{ session = $Session; command = $CommandArgs[0] }
    return Invoke-CleanAgentBrowserEnvironment {
        if ($Executor) {
            return & $Executor $cli $arguments
        }

        $result = Invoke-BoundedAgentBrowserProcess -Executable $cli -Arguments $arguments -TimeoutSeconds $script:TestCliTimeoutSeconds -InputText $batchInput
        if ($result.TimedOut) {
            $exception = [InvalidOperationException]::new(
                "Test agent-browser command timed out after $($script:TestCliTimeoutSeconds) seconds. PID: $($result.Pid). It was not terminated."
            )
            $exception.Data['AgentBrowserPid'] = $result.Pid
            $exception.Data['AgentBrowserProcessTree'] = $result.ProcessTree
            throw $exception
        }
        if ($result.ExitCode -ne 0) {
            $exception = [InvalidOperationException]::new(
                "Test agent-browser command failed with exit code $($result.ExitCode)."
            )
            $exception.Data['AgentBrowserPid'] = $result.Pid
            $exception.Data['AgentBrowserStdErr'] = [string]$result.StdErr
            throw $exception
        }
        if ($CommandArgs[0] -eq 'close') {
            Remove-Item -LiteralPath (Get-AgentBrowserSessionRecordPath $Session)
        }
        return ([string]$result.StdOut).Trim()
    }
}

function Close-AgentBrowserTest {
    param(
        [Parameter(Mandatory)][string]$Session,
        [scriptblock]$Executor
    )

    Invoke-AgentBrowserTest -Session $Session -CommandArgs @('close') -Executor $Executor
}

function Get-AgentBrowserLocalHelp {
    param([string]$Mode)

    switch ($Mode) {
        'test' {
            return @'
agent-browser-local test - 测试模式帮助 / Test mode help

用法 / Usage:
  agent-browser-local test new [prefix] [--headed]
  agent-browser-local test run <session> <command> [args...]
  agent-browser-local test close <session>

run 和 close 必须使用 test new 返回的完整会话值；不要手写 default、local-auth-cdp 或其他名称。生成值包含时间戳和 64 位随机能力令牌，可供同一任务的其他进程使用。
Run and close require the exact value returned by test new; do not hand-write default, local-auth-cdp, or other names. The generated value contains a timestamp and a 64-bit random capability token and works across processes in the same task.
每个任务使用独立的临时会话；独立测试任务可以并行运行。不要传入 profiles\work、--profile、--session、--cdp、--restore、--state 或 --headed，也不要使用 close --all。
Use one isolated temporary session per task. Independent test tasks may run in parallel. Do not share the work profile or pass global profile/session routing options.
'@.Trim()
        }
        'auth' {
            return @'
agent-browser-local auth - 认证模式帮助 / Auth mode help

用法 / Usage:
  agent-browser-local auth start [url] [--headed|--headless]
  agent-browser-local auth run <command> [args...]
  agent-browser-local auth status
  agent-browser-local auth stop

认证模式是串行的，并持续写入 profiles\work。默认有头；--headless 使用同一资料目录后台运行。切换模式前先 auth stop。手动关闭窗口通常会保留登录状态，但优先使用 auth stop 以便优雅关闭。手动关闭后，运行 auth status 和 status 检查所有权与状态。
Auth mode is serial and continuously writes the work profile. Default is headed; --headless uses the same profile without a window. Stop before switching modes. Manually closing the window usually preserves state, but prefer auth stop for graceful shutdown. After a manual close, run auth status and status to check ownership and state.

不要启动第二个共享 profiles\work 的 Chrome，不要设置全局 profile/session 环境变量，也不要检查认证数据。
Do not launch a second Chrome sharing profiles\work, set global profile/session variables, or inspect authentication data.
'@.Trim()
        }
        'status' {
            return @'
agent-browser-local status - 状态帮助 / Status help

用法 / Usage:
  agent-browser-local status

状态命令是只读诊断入口。发生启动或所有权问题时，记录会话、PID、端口和模式；不要终止未知 Chrome 进程。
Status is the read-only diagnostic entry point. For launch or ownership issues, record the session, PID, port, and mode; do not terminate unknown Chrome processes.
'@.Trim()
        }
        'maintenance' {
            return @'
agent-browser-local maintenance - 维护模式帮助 / Maintenance mode help

用法 / Usage:
  agent-browser-local maintenance doctor
  agent-browser-local maintenance cleanup-report

本机 Chrome for Testing 150 的 chrome.exe --version 会打开可见窗口且不退出，因此 doctor 在此主机受限，不能用于常规诊断。禁止使用 doctor --fix 或广泛清理。
On this host, Chrome for Testing 150 opens a visible chrome.exe --version window that does not exit, so doctor is limited and unavailable for ordinary diagnosis. Do not use doctor --fix or broad cleanup.
'@.Trim()
        }
        default {
            return @'
agent-browser-local - 本机浏览器路由帮助 / Local browser routing help

用法 / Usage:
  agent-browser-local <test|auth|status|maintenance> ...
  agent-browser-local help
  agent-browser-local <mode> help

test: 独立临时会话；独立任务可并行。 / Isolated temporary sessions; independent tasks may run in parallel.
auth: 串行认证浏览器，持续写入 profiles\work。 / Serial authenticated browser with continuous profiles\work writes.
status: 只读诊断。 / Read-only diagnostics.
maintenance: 受限维护信息。 / Restricted maintenance information.

认证窗口手动关闭通常会保留状态，但优先使用 auth stop；手动关闭后运行 auth status 和 status。不要设置全局 profile/session 变量、共享 profiles\work、使用 close --all 或 doctor --fix，或终止未知 Chrome 进程。
Manual auth-window closure usually preserves state, but prefer auth stop; after manual closure run auth status and status. Do not set global profile/session variables, share profiles\work, use close --all or doctor --fix, or terminate unknown Chrome processes.
'@.Trim()
        }
    }
}

function Get-AgentBrowserLocalHelpHint {
    return "Run 'agent-browser-local help' for bilingual help."
}

function Throw-AgentBrowserLocalUsageError {
    param([Parameter(Mandatory)][string]$Message)

    $exception = [ArgumentException]::new($Message)
    $exception.Data['AgentBrowserLocalExitCode'] = 2
    throw $exception
}

function Invoke-AgentBrowserLocalCommand {
    param([AllowEmptyCollection()][string[]]$Arguments)

    if (-not $Arguments) {
        return Get-AgentBrowserLocalHelp
    }

    if ($Arguments.Count -eq 1 -and $Arguments[0] -in @('help', '--help', '-h')) {
        return Get-AgentBrowserLocalHelp
    }

    $mode = $Arguments[0]
    $rest = @($Arguments | Select-Object -Skip 1)
    switch ($mode) {
        'test' {
            if ($rest.Count -eq 1 -and $rest[0] -in @('help', '--help', '-h')) { return Get-AgentBrowserLocalHelp -Mode 'test' }
            if (-not $rest) { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local test <new|run|close> ...`n$(Get-AgentBrowserLocalHelpHint)" }
            switch ($rest[0]) {
                'new' {
                    $newArgs = @($rest | Select-Object -Skip 1)
                    $headed = '--headed' -in $newArgs
                    $prefixArgs = @($newArgs | Where-Object { $_ -ne '--headed' })
                    if ($prefixArgs.Count -gt 1) { Throw-AgentBrowserLocalUsageError 'Usage: test new [prefix] [--headed]' }
                    $prefix = if ($prefixArgs.Count) { $prefixArgs[0] } else { 'test' }
                    return New-AgentBrowserTestSession -Prefix $prefix -Headed:$headed
                }
                'run' {
                    if ($rest.Count -lt 3) { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local test run <session> <command> [args...]`n$(Get-AgentBrowserLocalHelpHint)" }
                    return Invoke-AgentBrowserTest -Session $rest[1] -CommandArgs @($rest | Select-Object -Skip 2)
                }
                'close' {
                    if ($rest.Count -ne 2) { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local test close <session>`n$(Get-AgentBrowserLocalHelpHint)" }
                    return Close-AgentBrowserTest -Session $rest[1]
                }
                default { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local test <new|run|close> ...`n$(Get-AgentBrowserLocalHelpHint)" }
            }
        }
        'auth' {
            if ($rest.Count -eq 1 -and $rest[0] -in @('help', '--help', '-h')) { return Get-AgentBrowserLocalHelp -Mode 'auth' }
            if (-not $rest) { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local auth <start|run|status|stop> ...`n$(Get-AgentBrowserLocalHelpHint)" }
            switch ($rest[0]) {
                'start' {
                    $startArgs = @($rest | Select-Object -Skip 1)
                    $modeArgs = @($startArgs | Where-Object { $_ -in @('--headed', '--headless') })
                    $urlArgs = @($startArgs | Where-Object { $_ -notin @('--headed', '--headless') })
                    if ($modeArgs.Count -gt 1 -or $urlArgs.Count -gt 1) {
                        Throw-AgentBrowserLocalUsageError 'Usage: agent-browser-local auth start [url] [--headed|--headless]'
                    }
                    $url = if ($urlArgs.Count) { $urlArgs[0] } else { 'about:blank' }
                    return Start-AgentBrowserAuth -Url $url -Headless:('--headless' -in $modeArgs)
                }
                'run' {
                    if ($rest.Count -lt 2) { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local auth run <command> [args...]`n$(Get-AgentBrowserLocalHelpHint)" }
                    return Invoke-AgentBrowserAuth -CommandArgs @($rest | Select-Object -Skip 1)
                }
                'status' {
                    if ($rest.Count -ne 1) { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local auth status`n$(Get-AgentBrowserLocalHelpHint)" }
                    return Get-AgentBrowserAuthStatus
                }
                'stop' {
                    if ($rest.Count -ne 1) { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local auth stop`n$(Get-AgentBrowserLocalHelpHint)" }
                    return Stop-AgentBrowserAuth
                }
                default { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local auth <start|run|status|stop> ...`n$(Get-AgentBrowserLocalHelpHint)" }
            }
        }
        'status' {
            if ($rest.Count -eq 1 -and $rest[0] -in @('help', '--help', '-h')) { return Get-AgentBrowserLocalHelp -Mode 'status' }
            if ($rest.Count -ne 0) { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local status`n$(Get-AgentBrowserLocalHelpHint)" }
            return Get-AgentBrowserLocalStatus
        }
        'maintenance' {
            if ($rest.Count -eq 1 -and $rest[0] -in @('help', '--help', '-h')) { return Get-AgentBrowserLocalHelp -Mode 'maintenance' }
            if (-not $rest) { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local maintenance <doctor|cleanup-report>`n$(Get-AgentBrowserLocalHelpHint)" }
            if ($rest.Count -ne 1) { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local maintenance <doctor|cleanup-report>`n$(Get-AgentBrowserLocalHelpHint)" }
            switch ($rest[0]) {
                'doctor' { return Invoke-AgentBrowserLocalDoctor }
                'cleanup-report' { return Get-StaleAgentBrowserSidecars }
                default { Throw-AgentBrowserLocalUsageError "Usage: agent-browser-local maintenance <doctor|cleanup-report>`n$(Get-AgentBrowserLocalHelpHint)" }
            }
        }
        default { Throw-AgentBrowserLocalUsageError "Unknown mode '$mode'. $(Get-AgentBrowserLocalHelpHint)" }
    }
}

Export-ModuleMember -Function @(
    'Close-AgentBrowserAuthDaemon',
    'Get-AgentBrowserLocalConfig',
    'Resolve-AgentBrowserCli',
    'Resolve-AgentBrowserChrome',
    'Get-AgentBrowserLocalStatus',
    'Get-StaleAgentBrowserSidecars',
    'Invoke-AgentBrowserLocalDoctor',
    'Get-AgentBrowserAuthStatus',
    'Start-AgentBrowserAuth',
    'Invoke-AgentBrowserAuth',
    'Stop-AgentBrowserAuth',
    'Invoke-CleanAgentBrowserEnvironment',
    'Write-AgentBrowserLocalLog',
    'New-AgentBrowserTestSession',
    'Invoke-AgentBrowserTest',
    'Close-AgentBrowserTest',
    'Invoke-AgentBrowserLocalCommand'
)
