Write-Host "Set TLS1.2"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Write-Host "Install Chocolatey"

# Add to system PATH
Add-MachinePathItem 'C:\ProgramData\Chocolatey\bin'
Update-Environment

# Variables
$chocoInstallUrl = 'https://chocolatey.org/install.ps1'
# Optional: your internal/cached fallback URL (if you host a copy)
$cachedInstallUrl = 'https://my.internal.repo/chocolatey/install.ps1'

$maxRetries = 5
$retryDelaySeconds = 15
$installScriptPath = $null
$downloadSucceeded = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        Write-Host "Downloading Chocolatey install script (attempt $i of $maxRetries) ..."
        $installScriptPath = Invoke-DownloadWithRetry $chocoInstallUrl
        Write-Host "Download succeeded."
        $downloadSucceeded = $true
        break
    }
    catch {
        Write-Host "Download attempt $i failed: $_" -ForegroundColor Yellow
        if ($i -lt $maxRetries) {
            Write-Host "Waiting $retryDelaySeconds seconds before retry ..."
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }
}

if (-not $downloadSucceeded) {
    Write-Host "Primary download failed after $maxRetries attempts. Trying cached URL ..." -ForegroundColor Yellow
    try {
        $installScriptPath = Invoke-DownloadWithRetry $cachedInstallUrl
        Write-Host "Cached download succeeded."
    }
    catch {
        throw "ERROR: Could not download the Chocolatey install script from either URL."
    }
}

# Verify signature (same as original)
Test-FileSignature -Path $installScriptPath -ExpectedSubject 'CN="Chocolatey Software, Inc", O="Chocolatey Software, Inc", L=Topeka, S=Kansas, C=US'

# Invoke install
Write-Host "Running Chocolatey install script ..."
Invoke-Expression $installScriptPath

# Turn off confirmation
Write-Host "Enabling global confirmation (so choco custom installs won't prompt) ..."
choco feature enable -n allowGlobalConfirmation

# Initialize environmental variable ChocolateyToolsLocation
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1" -Force
Get-ToolsLocation
