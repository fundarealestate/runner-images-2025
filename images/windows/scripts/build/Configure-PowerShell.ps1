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

# Initialize PowerShellGet
Import-Module PowerShellGet -ErrorAction Stop

# Ensure PSGallery is registered
Write-Host "Checking PSGallery repository..."

$repository = Get-PSRepository `
    -Name PSGallery `
    -ErrorAction SilentlyContinue

if (-not $repository) {
    Write-Host "PSGallery not found. Registering default repository..."

    Register-PSRepository `
        -Default `
        -ErrorAction Stop
}

# Verify repository registration
$repository = Get-PSRepository `
    -Name PSGallery `
    -ErrorAction Stop

Write-Host "PSGallery registered: $($repository.SourceLocation)"

# Configure PSGallery
Set-PSRepository `
    -Name PSGallery `
    -InstallationPolicy Trusted `
    -ErrorAction Stop

Get-PSRepository -Name PSGallery |
    Format-List Name, SourceLocation, InstallationPolicy

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

# Show loaded versions
Write-Host "Loaded PowerShellGet modules:"
Get-Module PowerShellGet |
    Select-Object Name, Version, Path |
    Format-Table -AutoSize

# Verify that 2.2.5 is loaded
$loadedModule = Get-Module PowerShellGet |
    Where-Object { $_.Version -eq [version]$powerShellGetVersion }

if (-not $loadedModule) {
    throw "PowerShellGet $powerShellGetVersion is not loaded"
}

Write-Host "PowerShellGet $powerShellGetVersion successfully loaded"

# Verify the version used by Install-Module
Write-Host "Verifying Install-Module command..."

$installModuleCommand = Get-Command Install-Module -ErrorAction Stop

Write-Host "Install-Module version: $($installModuleCommand.Version)"
Write-Host "Install-Module source: $($installModuleCommand.Source)"

if ($installModuleCommand.Version -ne [version]$powerShellGetVersion) {
    throw "Install-Module is using PowerShellGet $($installModuleCommand.Version), expected $powerShellGetVersion"
}

Write-Host "PowerShellGet $powerShellGetVersion is active and ready"
