# Run once in an elevated PowerShell window to enable startup hosting.
[CmdletBinding()]
param(
    [string]$Directory = 'C:\Users\Public\gew_erp',
    [ValidateRange(1, 65535)]
    [int]$Port = 8000,
    [string]$PythonPath,
    [string]$TaskName = 'GEW ERP Update Server'
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from PowerShell as Administrator.'
}

$root = (Resolve-Path -LiteralPath $Directory).Path
if (-not (Test-Path -LiteralPath (Join-Path $root 'version.json') -PathType Leaf)) {
    throw "No version.json found in $root."
}
if ($root.Contains('"')) {
    throw 'The update directory cannot contain quotation marks.'
}

if (-not $PythonPath) {
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($launcher) {
        $PythonPath = & $launcher.Source -3 -c 'import sys; print(sys.executable)'
        if ($LASTEXITCODE -ne 0) { throw 'Python launcher could not locate Python 3.' }
    } else {
        $PythonPath = (Get-Command python.exe -ErrorAction Stop).Source
    }
}
$PythonPath = (Resolve-Path -LiteralPath $PythonPath).Path
& $PythonPath -c 'import http.server'
if ($LASTEXITCODE -ne 0) { throw 'Python HTTP server is unavailable.' }

$description = 'GEW ERP update files served by Python HTTP server at Windows startup.'
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing -and $existing.Description -ne $description) {
    throw "Task '$TaskName' already exists and is not managed by this script."
}
if ($existing -and $existing.State -eq 'Running') {
    throw "Task '$TaskName' is already running. Stop that task before reconfiguring it."
}

$action = New-ScheduledTaskAction -Execute $PythonPath `
    -Argument "-m http.server $Port --bind 0.0.0.0 --directory `"$root`"" `
    -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtStartup
$account = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -Hidden `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew
$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $account `
    -Settings $settings -Description $description
Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null

if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    Write-Host "Startup task installed. Port $Port is already in use; the current server was left running."
    Write-Host 'The task will start automatically after the next restart.'
} else {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Startup task installed and started. Serving $root on port $Port."
}
Write-Host "Task name: $TaskName"
