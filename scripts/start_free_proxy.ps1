# Windows PowerShell 5.1+. API token is entered locally, never passed in CLI arguments.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Python = (Get-Command python -ErrorAction Stop).Source
$Tunnel = (Get-Command cloudflared -ErrorAction Stop).Source
$Secure = Read-Host "API token alerts.in.ua (hidden)" -AsSecureString
$Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
$OldEnvironment = @{}
foreach ($Name in @("ALERTS_TOKEN", "BIND_HOST", "PORT")) {
    $OldEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
}
$Process = $null
try {
    $env:ALERTS_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
    if ([string]::IsNullOrWhiteSpace($env:ALERTS_TOKEN)) { throw "API token is empty" }
    $env:BIND_HOST = "127.0.0.1"
    $env:PORT = "8080"
    $Process = Start-Process -FilePath $Python -ArgumentList @("server/app.py") -WorkingDirectory $Root -NoNewWindow -PassThru
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
    foreach ($Name in @("ALERTS_TOKEN", "BIND_HOST", "PORT")) {
        [Environment]::SetEnvironmentVariable($Name, $OldEnvironment[$Name], "Process")
    }
}
try {
    Start-Sleep -Milliseconds 700
    $Ready = $false
    for ($i=0; $i -lt 20; $i++) {
        if ($Process.HasExited) { throw "Proxy exited. Check Python and port 8080." }
        try {
            $Health = Invoke-RestMethod http://127.0.0.1:8080/health -TimeoutSec 2
            if ($Health.service -eq "svitanok") { $Ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 250
    }
    if (-not $Ready) { throw "Proxy is not responding." }
    Write-Host "Copy the HTTPS trycloudflare.com URL printed below into the iPhone app."
    Write-Host "Temporary DEVELOPMENT tunnel. Keep computer awake. URL may change on restart."
    & $Tunnel tunnel --url http://127.0.0.1:8080
} finally {
    if ($null -ne $Process -and -not $Process.HasExited) { Stop-Process -Id $Process.Id }
}
