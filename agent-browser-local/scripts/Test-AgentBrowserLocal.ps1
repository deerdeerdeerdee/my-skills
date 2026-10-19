#requires -Version 7.2
param([switch]$Smoke, [string]$RuntimeRoot = (Join-Path $PSScriptRoot 'runtime'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Import-Module (Join-Path $RuntimeRoot 'lib\AgentBrowserLocal.psm1') -Force -PassThru
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('abl-regression-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$configPath = Join-Path $testRoot 'config.psd1'
$escapedRoot = $testRoot.Replace("'", "''")
@"
@{
    RuntimeDirectory = '$escapedRoot\runtime'
    LogDirectory = '$escapedRoot\logs'
    AuthProfilePath = '$escapedRoot\auth profile'
}
"@ | Set-Content -LiteralPath $configPath -Encoding utf8
$savedConfig = $env:AGENT_BROWSER_LOCAL_CONFIG
$env:AGENT_BROWSER_LOCAL_CONFIG = $configPath
$script:passed = 0
function Assert-Check([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}
function Assert-Rejected([scriptblock]$Action, [string]$Name) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Check $rejected $Name
}
$sessions = [Collections.Generic.List[string]]::new()
$authOwned = $false
$serverJob = $null
try {
    # Every rejected path is tested at the policy boundary without native execution.
    foreach ($mode in @('test', 'auth')) {
        foreach ($argsCase in @(
            @('open','about:blank','--auto-connect'), @('connect','9333'),
            @('open','about:blank','--config=other.json'), @('open','about:blank','--namespace=other'),
            @('open','about:blank','--provider','browserbase'), @('open','about:blank','-p','ios'),
            @('open','about:blank','--restore'), @('open','about:blank','--restore-save=always'),
            @('open','about:blank','--args=--user-data-dir=other'),
            @('open','about:blank','--profile=work'), @('doctor'), @('plugin','run','x'),
            @('open','about:blank','--headless=new'),
            @('mcp'), @('chat','do something'), @('dashboard','start'), @('unknown-new-command'),
            @('batch','["close","--all"]'), @('batch','["batch","[\"connect\",\"9333\"]"]'),
            @('batch'), @('batch','{}'), @('batch','[1]'), @('close','--all')
        )) {
            Assert-Rejected { & $module { param($a,$m) Assert-AgentBrowserLocalCliArgs -CommandArgs $a -Mode $m } $argsCase $mode } "$mode rejects $($argsCase -join ' ')"
        }
        foreach ($argsCase in @(
            @('find','text','close','click'), @('fill','@e1','install'),
            @('open','about:blank','--enable','react-devtools'),
            @('batch','--bail','["open","about:blank"]','["snapshot","-i"]'),
            @('get','url')
        )) {
            & $module { param($a,$m) Assert-AgentBrowserLocalCliArgs -CommandArgs $a -Mode $m } $argsCase $mode
            Assert-Check $true "$mode accepts ordinary arguments"
        }
    }
    Assert-Rejected { & $module { Assert-AgentBrowserGeneratedSession 'invented-1234567890123-0123456789abcdef' } } 'forged session rejected'
    $session = New-AgentBrowserTestSession -Prefix regression -Headed
    $sessions.Add($session)
    $captured = Invoke-AgentBrowserTest -Session $session -CommandArgs @('fill','@e1','close') -Executor {
        param($exe,$argv)
        [pscustomobject]@{ Exe=$exe; Argv=$argv }
    }
    Assert-Check ($captured.Exe -like '*.exe') 'uses native CLI'
    Assert-Check ($captured.Argv[0] -eq '--config') 'controlled config always supplied'
    Assert-Check ($captured.Argv[3] -eq $session) 'wrapper session preserved'
    Assert-Check ($captured.Argv[5] -eq 'true') 'visible test mode is explicit'
    Assert-Check ($captured.Argv[-1] -eq 'close') 'literal close value preserved'
    $names = @('AGENT_BROWSER_AUTO_CONNECT','AGENT_BROWSER_PLUGINS','AGENT_BROWSER_CONFIG','AGENT_BROWSER_NAMESPACE','AGENT_BROWSER_PROVIDER')
    $saved = @{}
    try {
        foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name); Set-Item "Env:$name" 'fixture-value' }
        $clean = Invoke-CleanAgentBrowserEnvironment {
            @(Get-ChildItem Env: | Where-Object { $_.Name -like 'AGENT_BROWSER_*' -and $_.Name -ne 'AGENT_BROWSER_LOCAL_CONFIG' }).Count -eq 0
        }
        Assert-Check $clean 'all upstream environment overrides removed'
        foreach ($name in $names) { Assert-Check ((Get-Item "Env:$name").Value -eq 'fixture-value') "restores $name" }
    } finally {
        foreach ($name in $names) {
            if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
            else { Set-Item "Env:$name" $saved[$name] }
        }
    }
    # Exact profile/port/flags, with only the canonical headless flag allowed.
    $config = Get-AgentBrowserLocalConfig
    $authArgs = @('--remote-debugging-address=127.0.0.1','--remote-debugging-port=9333',
        "--user-data-dir=$($config.AuthProfilePath)",'--no-first-run','--no-default-browser-check','about:blank')
    Assert-Check (& $module { param($a,$c) Test-AgentBrowserAuthArgumentSet -Arguments $a -Config $c } $authArgs $config) 'exact auth launch accepted'
    Assert-Check (& $module { param($a,$c) Test-AgentBrowserAuthArgumentSet -Arguments $a -Config $c } ($authArgs + '--headless=new') $config) 'canonical headless auth accepted'
    foreach ($flags in @(@('--headless'), @('--headless=old'), @('--headless=new','--headless=new'), @('--no-sandbox'))) {
        Assert-Check (-not (& $module { param($a,$c) Test-AgentBrowserAuthArgumentSet -Arguments $a -Config $c } ($authArgs + $flags) $config)) 'unexpected launch flags rejected'
    }
    foreach ($invalidStart in @(@('auth','start','--headed','--headless'), @('auth','start','--headless','--headless'), @('auth','start','--unknown'), @('auth','start','https://example.com','https://example.org'))) {
        Assert-Rejected { Invoke-AgentBrowserLocalCommand -Arguments $invalidStart } 'invalid auth start rejected before launch'
    }
    Assert-Check (-not (& $module { param($a,$c) Test-AgentBrowserAuthArgumentSet -Arguments $a -Config $c } ($authArgs + '--user-data-dir=foreign') $config)) 'duplicate foreign profile rejected'
    $processResult = & $module { param($exe) Invoke-BoundedAgentBrowserProcess -Executable $exe -Arguments @('-NoProfile','-Command','[Console]::WriteLine("argv-ok")') -TimeoutSeconds 5 } (Join-Path $PSHOME 'pwsh.exe')
    Assert-Check ($processResult.ExitCode -eq 0 -and $processResult.StdOut.Trim() -eq 'argv-ok') 'bounded runner captures output'
    $fixtureRoot = Join-Path $RuntimeRoot 'tests\fixtures'
    $tailResult = & $module { param($exe,$parent,$child)
        Invoke-BoundedAgentBrowserProcess -Executable $exe -Arguments @('-NoProfile','-File',$parent,'-ChildScript',$child,'-ChildLifetimeSeconds','2','-TailLineCount','40') -TimeoutSeconds 3
    } (Join-Path $PSHOME 'pwsh.exe') (Join-Path $fixtureRoot 'DaemonInheritedStdoutParent.ps1') (Join-Path $fixtureRoot 'DaemonInheritedStdoutChild.ps1')
    Assert-Check ($tailResult.ExitCode -eq 0 -and $tailResult.StdOut -match 'tail-marker:0039') 'inherited stdout captures final output'
    if ($Smoke) {
        $portProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $portProbe.Start()
        $fixturePort = $portProbe.LocalEndpoint.Port
        $portProbe.Stop()
        $fixtureUrl = "http://127.0.0.1:$fixturePort/"
        $serverStopFile = Join-Path $testRoot 'stop-server'
        $serverJob = Start-Job -ArgumentList $fixturePort,$serverStopFile -ScriptBlock {
            param($port,$stopFile)
            $listener = [Net.HttpListener]::new()
            $listener.Prefixes.Add("http://127.0.0.1:$port/")
            $listener.Start()
            try {
                while ($listener.IsListening) {
                    $pending = $listener.GetContextAsync()
                    while (-not $pending.Wait(200)) {
                        if (Test-Path -LiteralPath $stopFile) { return }
                    }
                    $ctx = $pending.GetAwaiter().GetResult()
                    $html = '<!doctype html><title>Local routing fixture</title><label>Name<input id="name"></label><button id="save" onclick="document.getElementById(''result'').textContent=document.getElementById(''name'').value">Save</button><p id="result"></p>'
                    $bytes = [Text.Encoding]::UTF8.GetBytes($html)
                    $ctx.Response.ContentType = 'text/html; charset=utf-8'
                    $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length)
                    $ctx.Response.Close()
                }
            } finally { $listener.Close() }
        }
        $serverReady = $false
        foreach ($attempt in 1..30) {
            try { $null = Invoke-WebRequest -Uri $fixtureUrl -TimeoutSec 1; $serverReady = $true; break } catch { Start-Sleep -Milliseconds 100 }
        }
        Assert-Check $serverReady 'loopback fixture server starts'
        # Deliberately set dangerous ambient config. The managed config must override it.
        $ambient = Join-Path $testRoot 'ambient.json'
        '{"autoConnect":true,"profile":"DO-NOT-USE","headed":true}' | Set-Content $ambient
        $oldAmbient = $env:AGENT_BROWSER_CONFIG
        $env:AGENT_BROWSER_CONFIG = $ambient
        try {
            $a = New-AgentBrowserTestSession -Prefix smokeA
            $b = New-AgentBrowserTestSession -Prefix smokeB
            $sessions.Add($a); $sessions.Add($b)
            Invoke-AgentBrowserTest -Session $a -CommandArgs @('open','about:blank') | Out-Null
            Invoke-AgentBrowserTest -Session $b -CommandArgs @('open','about:blank') | Out-Null
            Invoke-AgentBrowserTest -Session $a -CommandArgs @('open',$fixtureUrl) | Out-Null
            $entrySnapshot = & (Join-Path $RuntimeRoot 'agent-browser-local.ps1') test run $a snapshot -i
            Assert-Check (($entrySnapshot -join "`n") -match 'Save') 'PowerShell entry point preserves native snapshot -i'
            Invoke-AgentBrowserTest -Session $a -CommandArgs @('fill','#name','install close') | Out-Null
            Invoke-AgentBrowserTest -Session $a -CommandArgs @('click','#save') | Out-Null
            Assert-Check ((Invoke-AgentBrowserTest -Session $a -CommandArgs @('get','text','#result')) -match 'install close') 'real local form interaction'
            Invoke-AgentBrowserTest -Session $a -CommandArgs @('eval', 'localStorage.setItem("abl-test", "temporary")') | Out-Null
            Invoke-AgentBrowserTest -Session $b -CommandArgs @('open',$fixtureUrl) | Out-Null
            Assert-Check ((Invoke-AgentBrowserTest -Session $b -CommandArgs @('eval', 'localStorage.getItem("abl-test")')) -notmatch 'temporary') 'temporary sessions do not share stored data'
            Invoke-AgentBrowserTest -Session $b -CommandArgs @('open','about:blank') | Out-Null
            Invoke-AgentBrowserTest -Session $a -CommandArgs @('open','about:blank') | Out-Null
            Invoke-AgentBrowserTest -Session $a -CommandArgs @('eval','window.__ablIsolation = 123') | Out-Null
            $other = Invoke-AgentBrowserTest -Session $b -CommandArgs @('eval','typeof window.__ablIsolation')
            Assert-Check ($other -match 'undefined') 'independent browser contexts'
            $batch = Invoke-AgentBrowserTest -Session $a -CommandArgs @('batch','--bail','["get","url"]','["eval","window.__ablIsolation"]')
            Assert-Check ($batch -match '123' -and $batch -match 'about:blank') 'validated batch reaches native CLI'
            Close-AgentBrowserTest $a | Out-Null
            Assert-Rejected { Invoke-AgentBrowserTest -Session $a -CommandArgs @('get','url') } 'closed registration cannot be reused'
            Assert-Check ((Invoke-AgentBrowserTest -Session $b -CommandArgs @('get','url')) -match 'about:blank') 'targeted close preserves other session'
            Close-AgentBrowserTest $b | Out-Null
            $visible = New-AgentBrowserTestSession -Prefix smokeVisible -Headed
            $sessions.Add($visible)
            Invoke-AgentBrowserTest -Session $visible -CommandArgs @('open','about:blank') | Out-Null
            Assert-Check ((Invoke-AgentBrowserTest -Session $visible -CommandArgs @('get','url')) -match 'about:blank') 'visible isolated browser works'
            Close-AgentBrowserTest $visible | Out-Null
            # Use an empty temporary profile, never the real managed work profile.
            $authBefore = Get-AgentBrowserAuthStatus
            Assert-Check (-not $authBefore.PortOccupied) 'temporary auth port is free'
            $authOwned = $true
            $started = Start-AgentBrowserAuth -Url $fixtureUrl
            Assert-Check ($started.Ready -and $started.Headless -eq $false) 'temporary headed auth browser ready'
            Assert-Check ((Invoke-AgentBrowserAuth -CommandArgs @('get','url')) -match [regex]::Escape($fixtureUrl)) 'auth startup selects and loads requested page'
            Invoke-AgentBrowserAuth -CommandArgs @('eval', 'localStorage.setItem("abl-persist", "retained"); document.cookie="abl_cookie=retained; Max-Age=3600; Path=/"') | Out-Null
            $same = Start-AgentBrowserAuth -Url about:blank
            Assert-Check ($same.Pid -eq $started.Pid) 'same display mode reuses existing browser'
            Assert-Rejected { Start-AgentBrowserAuth -Headless -Url $fixtureUrl } 'mode change requires stop'
            Assert-Check ((Get-AgentBrowserAuthStatus).Pid -eq $started.Pid) 'mode conflict preserves existing browser'
            Assert-Check (Stop-AgentBrowserAuth).Stopped 'temporary headed auth closes'
            $authOwned = $false
            # Same temporary profile, through the real CLI entrypoint.
            $headless = & (Join-Path $RuntimeRoot 'agent-browser-local.ps1') auth start --headless $fixtureUrl
            $authOwned = $true
            Assert-Check ($headless.Ready -and $headless.Headless -eq $true) 'persistent headless entrypoint ready'
            Assert-Check ((Get-Process -Id $headless.Pid).MainWindowHandle -eq 0) 'headless auth has no main window'
            Assert-Check ((Get-AgentBrowserLocalStatus).Auth.Headless -eq $true) 'status reports actual headless mode'
            Assert-Check ((Invoke-AgentBrowserAuth -CommandArgs @('eval', 'localStorage.getItem("abl-persist")')) -match 'retained') 'storage survives headed to headless restart'
            Assert-Check ((Invoke-AgentBrowserAuth -CommandArgs @('eval', 'document.cookie.includes("abl_cookie=retained")')) -match 'true') 'synthetic persistent cookie survives headed to headless restart'
            Assert-Rejected { Start-AgentBrowserAuth -Url about:blank } 'headless to headed requires stop'
            Assert-Check (Stop-AgentBrowserAuth).Stopped 'temporary headless auth closes'
            $authOwned = $false
            $headedAgain = & (Join-Path $RuntimeRoot 'agent-browser-local.ps1') auth start $fixtureUrl --headed
            $authOwned = $true
            Assert-Check ($headedAgain.Ready -and $headedAgain.Headless -eq $false) 'explicit headed restart ready'
            Assert-Check ((Invoke-AgentBrowserAuth -CommandArgs @('eval', 'localStorage.getItem("abl-persist")')) -match 'retained') 'storage survives headless to headed restart'
            Assert-Check ((Invoke-AgentBrowserAuth -CommandArgs @('eval', 'document.cookie.includes("abl_cookie=retained")')) -match 'true') 'synthetic cookie survives headless to headed restart'
            Assert-Check (Stop-AgentBrowserAuth).Stopped 'temporary auth closes with checked ownership'
            $authOwned = $false
            Assert-Check (-not (Get-AgentBrowserAuthStatus).PortOccupied) 'temporary auth port released'
        } finally {
            if ($null -eq $oldAmbient) { Remove-Item Env:AGENT_BROWSER_CONFIG -ErrorAction SilentlyContinue }
            else { $env:AGENT_BROWSER_CONFIG = $oldAmbient }
        }
    }
    [pscustomobject]@{ Passed=$script:passed; Smoke=[bool]$Smoke; NativeVersion=(& (Resolve-AgentBrowserCli) --version); TestRoot=$testRoot }
} finally {
    if ($serverJob) {
        New-Item -ItemType File -Path $serverStopFile -Force | Out-Null
        $null = Wait-Job -Job $serverJob -Timeout 5
        if ($serverJob.State -eq 'Running') { Stop-Job -Job $serverJob }
        Remove-Job -Job $serverJob
    }
    if ($authOwned) {
        try {
            Stop-AgentBrowserAuth | Out-Null
            Close-AgentBrowserAuthDaemon | Out-Null
        } catch { Write-Warning "Temporary auth needs targeted diagnosis: $($_.Exception.Message)" }
    }
    # Never terminate unknown processes. Keep failed-session registration for diagnosis.
    foreach ($session in $sessions) {
        $record = Join-Path $testRoot "runtime\sessions\$session.json"
        if (Test-Path -LiteralPath $record) {
            if ($Smoke -and $session -like 'smoke*') {
                try { Close-AgentBrowserTest $session | Out-Null } catch { Write-Warning "Owned session needs diagnosis: $session; $($_.Exception.Message)" }
            } else { Remove-Item -LiteralPath $record }
        }
    }
    if ($null -eq $savedConfig) { Remove-Item Env:AGENT_BROWSER_LOCAL_CONFIG -ErrorAction SilentlyContinue }
    else { $env:AGENT_BROWSER_LOCAL_CONFIG = $savedConfig }
}
