################################################################################
##  File:  Install-PowershellAzModules.ps1
##  Desc:  Install PowerShell modules used by Azure DevOps tasks
##  Supply chain security: package manager
################################################################################

$ErrorActionPreference = "Stop"

$installPSModulePath = "C:\\Modules"

if (-not (Test-Path -LiteralPath $installPSModulePath)) {
    Write-Host "Creating $installPSModulePath folder to store PowerShell Azure modules..."
    New-Item -Path $installPSModulePath -ItemType Directory -Force | Out-Null
}

# Ensure TLS 1.2 is available for PowerShell Gallery
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor `
    [Net.SecurityProtocolType]::Tls12

Import-Module PowerShellGet `
-RequiredVersion '2.2.5' `
-Force `
-ErrorAction Stop

# Get modules content from toolset
$modules = (Get-ToolsetContent).azureModules

$psModuleMachinePath = ""

$maxRetries = 5
$initialDelaySeconds = 15

foreach ($module in $modules) {
    $moduleName = $module.name

    Write-Host "Installing ${moduleName} to the ${installPSModulePath} path..."

    foreach ($version in $module.versions) {
        $modulePath = Join-Path -Path $installPSModulePath -ChildPath "${moduleName}_${version}"

        Write-Host " - $version [$modulePath]"

        $installed = $false

        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                Write-Host "Attempt $attempt of $maxRetries"

                # Remove partial installation from previous attempts
                if (Test-Path -LiteralPath $modulePath) {
                    Remove-Item -LiteralPath $modulePath `
                        -Recurse -Force -ErrorAction Stop
                }

                New-Item -Path $modulePath `
                    -ItemType Directory -Force | Out-Null

                Save-Module `
                    -Path $modulePath `
                    -Name $moduleName `
                    -RequiredVersion $version `
                    -Repository PSGallery `
                    -Force `
                    -ErrorAction Stop

                Write-Host "Successfully installed $moduleName $version"

                $installed = $true
                break
            }
            catch {
                Write-Warning "Failed to install $moduleName $version"
                Write-Warning $_.Exception.Message

                if ($attempt -eq $maxRetries) {
                    throw "Failed to install $moduleName $version after $maxRetries attempts."
                }

                $delay = $initialDelaySeconds * [math]::Pow(2, $attempt - 1)

                Write-Host "Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
            }
        }

        if ($installed) {
            $psModuleMachinePath += "$modulePath;"
        }
    }
}

# Add modules to PSModulePath
$psModuleMachinePath += $env:PSModulePath

[Environment]::SetEnvironmentVariable(
    "PSModulePath",
    $psModuleMachinePath,
    "Machine"
)

Invoke-PesterTests -TestFile "PowerShellAzModules" -TestName "AzureModules"
