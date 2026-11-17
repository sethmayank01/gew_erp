[CmdletBinding()]
param(
    [string]$BackendDirectory = 'C:\Users\Admin\flask_backend',
    [string]$UpdateDirectory = 'C:\Users\Public\gew_erp',
    [string]$ServiceName = 'FlaskAppService'
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
Start-Transcript -Path (Join-Path $workspace 'tmp\deployment_1.2.10.log') -Append | Out-Null
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator elevation is required to replace the running service.'
}
$backend = (Resolve-Path -LiteralPath $BackendDirectory).Path
$updates = (Resolve-Path -LiteralPath $UpdateDirectory).Path
$manifestPath = Join-Path $updates 'Version.json'
$manifestSource = Join-Path $PSScriptRoot 'release_version.json'
$manifest = Get-Content -LiteralPath $manifestSource -Raw | ConvertFrom-Json
$version = $manifest.android.version
if ($version -ne '1.2.10' -or $manifest.windows.version -ne $version) {
    throw 'This deployment script is reviewed for release 1.2.10 only.'
}
$serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName\Parameters"
$settings = Get-ItemProperty -LiteralPath $serviceKey
if ($settings.AppDirectory.TrimEnd('\') -ne $backend.TrimEnd('\') -or
    $settings.AppParameters -ne (Join-Path $backend 'app.py')) {
    throw 'Service paths do not match the intended backend. No files were changed.'
}
$python = $settings.Application
$apk = Join-Path $workspace 'build\app\outputs\flutter-apk\app-release.apk'
$installer = Join-Path $workspace 'tmp\release_1.2.10\gewerp_setup.exe'
$modules = @('app.py', 'authentication.py', 'write_safety.py', 'stock_issue.py', 'indent_submission.py')
foreach ($path in @($apk, $installer, $manifestPath, $python)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required file: $path" }
}
foreach ($name in $modules) {
    $source = Join-Path $workspace "flaskcode\$name"
    & $python -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' $source
    if ($LASTEXITCODE -ne 0) { throw "Invalid Python module: $name" }
}

$stamp = Get-Date -Format 'yyyyMMddTHHmmss'
$backup = Join-Path $workspace "tmp\deployment-backup-$version-$stamp"
New-Item -ItemType Directory -Path $backup | Out-Null
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $backup 'Version.json')
foreach ($name in $modules) {
    $existing = Join-Path $backend $name
    if (Test-Path -LiteralPath $existing) { Copy-Item -LiteralPath $existing -Destination $backup }
}

$release = Join-Path $updates "releases\$version"
New-Item -ItemType Directory -Path $release -Force | Out-Null
foreach ($pair in @(@($apk, 'app-release.apk'), @($installer, 'gewerp_setup.exe'))) {
    $published = Join-Path $release $pair[1]
    if (-not (Test-Path -LiteralPath $published)) {
        Copy-Item -LiteralPath $pair[0] -Destination $published
    }
    if ((Get-FileHash -LiteralPath $pair[0]).Hash -ne (Get-FileHash -LiteralPath $published).Hash) {
        throw "Published file failed checksum verification: $published"
    }
    $url = "http://192.168.2.205:8000/releases/$version/$($pair[1])"
    $head = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 20
    if ([long]($head.Headers['Content-Length'] | Select-Object -First 1) -ne (Get-Item -LiteralPath $published).Length) {
        throw "Update server is not serving the expected release file: $url"
    }
}

$registryKey = Get-Item -LiteralPath $serviceKey
$previousEnvironment = $registryKey.GetValue('AppEnvironmentExtra')
$environment = @($previousEnvironment | Where-Object { $_ })
$secretEntry = $environment | Where-Object { $_ -like 'GEW_ERP_SECRET_KEY=*' } | Select-Object -First 1
if (-not $secretEntry) {
    $secret = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
    $environment += "GEW_ERP_SECRET_KEY=$secret"
} else {
    $secret = $secretEntry.Substring('GEW_ERP_SECRET_KEY='.Length)
    if ($secret.Length -lt 32) { throw 'Existing signing key is too short; configure a strong key before deployment.' }
}
$changed = $false
$previousProcessSecret = $env:GEW_ERP_SECRET_KEY
try {
    # Artifacts are reachable before interrupting service or advertising an update.
    Stop-Service -Name $ServiceName -ErrorAction Stop
    (Get-Service -Name $ServiceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    $changed = $true
    New-ItemProperty -LiteralPath $serviceKey -Name AppEnvironmentExtra -PropertyType MultiString -Value $environment -Force | Out-Null
    foreach ($name in $modules) {
        Copy-Item -LiteralPath (Join-Path $workspace "flaskcode\$name") -Destination (Join-Path $backend $name) -Force
    }
    Start-Service -Name $ServiceName
    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $health = Invoke-RestMethod 'http://127.0.0.1:5005/health' -TimeoutSec 2
            if ($health.version -eq $version) { $ready = $true; break }
        } catch { }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'New backend did not become healthy.' }
    $env:GEW_ERP_SECRET_KEY = $secret
    Push-Location $workspace
    try {
        & $python (Join-Path $PSScriptRoot 'verify_deployment.py')
        if ($LASTEXITCODE -ne 0) { throw 'Backend smoke checks failed.' }
    } finally { Pop-Location }
    $pendingManifest = Join-Path $updates 'version.pending.json'
    Copy-Item -LiteralPath $manifestSource -Destination $pendingManifest
    [IO.File]::Replace($pendingManifest, $manifestPath, (Join-Path $backup 'Version.before-publish.json'))
    $advertised = Invoke-RestMethod 'http://192.168.2.205:8000/version.json' -TimeoutSec 10
    if ($advertised.android.version -ne $version -or $advertised.windows.version -ne $version) {
        throw 'Update manifest verification failed.'
    }
    Write-Host "Deployed $version. Backup: $backup"
    Write-Host 'Database rows were not modified by deployment checks. Clients must update and log in again.'
} catch {
    $failure = $_
    Write-Warning "Deployment check failed: $($failure.Exception.Message)"
    if ($changed) {
        Stop-Service -Name $ServiceName -ErrorAction SilentlyContinue
        (Get-Service -Name $ServiceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
        foreach ($name in $modules) {
            $old = Join-Path $backup $name
            if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination (Join-Path $backend $name) -Force }
        }
        Copy-Item -LiteralPath (Join-Path $backup 'Version.json') -Destination $manifestPath -Force
        if ($null -eq $previousEnvironment) {
            Remove-ItemProperty -LiteralPath $serviceKey -Name AppEnvironmentExtra -ErrorAction SilentlyContinue
        } else {
            New-ItemProperty -LiteralPath $serviceKey -Name AppEnvironmentExtra -PropertyType MultiString -Value $previousEnvironment -Force | Out-Null
        }
        Start-Service -Name $ServiceName
        Write-Warning "Deployment failed; previous backend and manifest restored. Backup: $backup"
    }
    throw $failure
} finally {
    $env:GEW_ERP_SECRET_KEY = $previousProcessSecret
    Stop-Transcript | Out-Null
}
