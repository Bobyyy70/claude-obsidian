# Setup OpenSSH Server + authorize hetzner-agent key
# Run as admin — script self-elevates if needed

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$AgentKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFWZnjqYRgwlenRiYnkiLtxLZrOoMAWl44yhh4J2IDMQ francesco@agent-host"

Write-Host "Installing OpenSSH Server..." -ForegroundColor Cyan
$cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
if ($cap.State -ne "Installed") {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
}

Write-Host "Starting sshd..." -ForegroundColor Cyan
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType Automatic

Write-Host "Opening firewall port 22..." -ForegroundColor Cyan
$rule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH SSH Server (sshd)" `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

# Admins use ProgramData\ssh\administrators_authorized_keys
$AuthKeysDir  = "$env:ProgramData\ssh"
$AuthKeysFile = "$AuthKeysDir\administrators_authorized_keys"

if (-not (Test-Path $AuthKeysDir)) { New-Item -ItemType Directory -Path $AuthKeysDir | Out-Null }

if (-not (Test-Path $AuthKeysFile) -or -not (Select-String -Path $AuthKeysFile -Pattern "hetzner-agent" -Quiet)) {
    Add-Content -Path $AuthKeysFile -Value $AgentKey
    Write-Host "Key added to $AuthKeysFile" -ForegroundColor Green
} else {
    Write-Host "Key already present — skipping" -ForegroundColor Yellow
}

# Fix permissions (Windows OpenSSH is strict)
icacls $AuthKeysFile /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null

# Ensure sshd_config uses the admin keys file
$sshdConfig = "$env:ProgramData\ssh\sshd_config"
if (Test-Path $sshdConfig) {
    $content = Get-Content $sshdConfig -Raw
    if ($content -notmatch "administrators_authorized_keys") {
        Add-Content -Path $sshdConfig -Value "`nMatch Group administrators`n       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys"
        Restart-Service sshd
    }
}

Write-Host ""
Write-Host "Done. SSH server is running on port 22." -ForegroundColor Green
Write-Host "Test from hetzner-agent: ssh $(hostname) (via Tailscale IP)" -ForegroundColor Cyan
Read-Host "Press Enter to close"
