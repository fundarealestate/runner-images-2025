################################################################################
##  File:  Install-PowershellAzModules.ps1
##  Desc:  Install PowerShell modules used by AzureFileCopy@4, AzureFileCopy@5, AzurePowerShell@4, AzurePowerShell@5 tasks
##  Supply chain security: package manager
################################################################################

# The correct Modules need to be saved in C:\Modules
$installPSModulePath = "C:\\Modules"
if (-not (Test-Path -LiteralPath $installPSModulePath)) {
    Write-Host "Creating ${installPSModulePath} folder to store PowerShell Azure modules..."
    New-Item -Path $installPSModulePath -ItemType Directory | Out-Null
}

# Get modules content from toolset
$modules = (Get-ToolsetContent).azureModules

$psModuleMachinePath = ""

# Set TLS 1.2 for PowerShellGet/PackageManagement
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Configured PowerShell to use TLS 1.2"

# Register or fix PSGallery repository to use API v3 endpoint
try {
    $repo = Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue
    if ($null -eq $repo) {
        Write-Host "Registering PSGallery repository (v3 endpoint)..."
        Register-PSRepository -Name "PSGallery" -SourceLocation "https://www.powershellgallery.com/api/v3" -InstallationPolicy Trusted
    }
    elseif ($repo.SourceLocation -notmatch "/api/v3$") {
        Write-Host "Updating PSGallery repository to use v3 endpoint..."
        Set-PSRepository -Name "PSGallery" -SourceLocation "https://www.powershellgallery.com/api/v3" -InstallationPolicy Trusted
    }
    else {
        Write-Host "PSGallery repository is configured correctly."
    }
}
catch {
    Write-Error "Failed to register or update PSGallery repository: $_"
    exit 1
}

Write-Host "Ensuring latest PowerShellGet and PackageManagement modules..."
Try {
    Install-Module PowerShellGet -Force -Scope AllUsers -ErrorAction Stop
    Install-Module PackageManagement -Force -Scope AllUsers -ErrorAction Stop
}
Catch {
    Write-Warning "Could not update PowerShellGet/PackageManagement - continuing anyway: $_"
}

foreach ($module in $modules) {
    $moduleName = $module.name

    Write-Host "Installing ${moduleName} to the ${installPSModulePath} path..."
    foreach ($version in $module.versions) {
        $modulePath = Join-Path -Path $installPSModulePath -ChildPath "${moduleName}_${version}"
        Write-Host " - $version [$modulePath]"
        $psModuleMachinePath += "$modulePath;"
        Save-Module -Path $modulePath -Name $moduleName -RequiredVersion $version -Force -ErrorAction Stop
    }

    foreach ($version in $module.zip_versions) {
        $modulePath = Join-Path -Path $installPSModulePath -ChildPath "${moduleName}_${version}"
        Save-Module -Path $modulePath -Name $moduleName -RequiredVersion $version -Force -ErrorAction Stop
        Compress-Archive -Path $modulePath -DestinationPath "${modulePath}.zip"
        Remove-Item $modulePath -Recurse -Force
    }
    # Append default tool version to machine path
    if ($null -ne $module.default) {
        $defaultVersion = $module.default

        Write-Host "Use ${moduleName} ${defaultVersion} as default version..."
        $psModuleMachinePath += "${installPSModulePath}\${moduleName}_${defaultVersion};"
    }
}

# Add modules to the PSModulePath
$psModuleMachinePath += $env:PSModulePath
[Environment]::SetEnvironmentVariable("PSModulePath", $psModuleMachinePath, "Machine")

Invoke-PesterTests -TestFile "PowerShellAzModules" -TestName "AzureModules"
