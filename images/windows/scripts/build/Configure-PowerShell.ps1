Write-Host "Setup PowerShellGet"

$ErrorActionPreference = 'Stop'

# Ensure TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor `
    [Net.SecurityProtocolType]::Tls12

# Install NuGet package provider
Install-PackageProvider `
    -Name NuGet `
    -MinimumVersion 2.8.5.201 `
    -Force `
    -ErrorAction Stop

# Configure PSGallery
Set-PSRepository `
    -Name PSGallery `
    -InstallationPolicy Trusted

# Pin the tested PowerShellGet version
$powerShellGetVersion = '2.2.5'

Write-Host "Installing PowerShellGet $powerShellGetVersion"

Install-Module `
    -Name PowerShellGet `
    -RequiredVersion $powerShellGetVersion `
    -Repository PSGallery `
    -Scope AllUsers `
    -Force `
    -AllowClobber `
    -ErrorAction Stop

# Explicitly load the installed version
Import-Module PowerShellGet `
    -RequiredVersion $powerShellGetVersion `
    -Force `
    -ErrorAction Stop

# Verify active version
$loadedVersion = (Get-Module PowerShellGet).Version.ToString()

Write-Host "Active PowerShellGet version: $loadedVersion"

if ($loadedVersion -ne $powerShellGetVersion) {
    throw "Incorrect PowerShellGet version: $loadedVersion"
}
