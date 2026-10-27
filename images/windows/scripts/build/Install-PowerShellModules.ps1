
################################################################################
## File: Install-PowerShellModules.ps1
## Desc: Install common PowerShell modules with retry and validation
################################################################################

$ErrorActionPreference = 'Stop'

# Ensure TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor `
    [Net.SecurityProtocolType]::Tls12

# Use the PowerShellGet version installed by Configure-PowerShell.ps1
$powerShellGetVersion = '2.2.5'

$uri = 'https://www.powershellgallery.com/api/v2/package/PowerShellGet/2.2.5'
$destination = Join-Path $env:TEMP 'PowerShellGet.2.2.5.nupkg'

try {
    Invoke-WebRequest `
        -Uri $uri `
        -OutFile $destination `
        -UseBasicParsing `
        -ErrorAction Stop

    $file = Get-Item $destination
    Write-Host "Direct download succeeded: $($file.Length) bytes"
}
catch {
    Write-Warning "Direct download failed: $($_.Exception.Message)"

    if ($_.Exception.Response) {
        Write-Warning "HTTP status: $([int]$_.Exception.Response.StatusCode)"
    }
}

Import-Module PowerShellGet `
    -RequiredVersion $powerShellGetVersion `
    -Force `
    -ErrorAction Stop

$installCommand = Get-Command Install-Module -ErrorAction Stop

if ($installCommand.Version -ne [version]$powerShellGetVersion) {
    throw "Install-Module resolves to version $($installCommand.Version), expected $powerShellGetVersion"
}

Write-Host "Using PowerShellGet $($installCommand.Version)"

function Test-ModuleInstalled {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Version
    )

    $installed = Get-Module -Name $Name -ListAvailable

    if ($Version) {
        $installed = $installed |
            Where-Object { $_.Version -eq [version]$Version }
    }

    return [bool]$installed
}

function Install-ModuleWithRetry {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Version,

        [int]$MaxAttempts = 3
    )

    # The Microsoft.Graph metapackage has many dependencies.
    # Give it additional retries for transient download failures.
    if ($Name -eq 'Microsoft.Graph') {
        $MaxAttempts = 5
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Write-Host "Installing $Name $Version (attempt $attempt/$MaxAttempts)"

            $installParams = @{
                Name               = $Name
                Repository         = 'PSGallery'
                Scope              = 'AllUsers'
                SkipPublisherCheck = $true
                Force              = $true
                AllowClobber       = $true
                Confirm            = $false
                ErrorAction        = 'Stop'
            }

            if ($Version) {
                $installParams.RequiredVersion = $Version
            }

            Install-Module @installParams

            if (-not (Test-ModuleInstalled -Name $Name -Version $Version)) {
                throw "Module $Name $Version was not found after installation"
            }

            Write-Host "Successfully installed $Name $Version"
            return
        }
        catch {
            $errorMessage = $_.Exception.Message

            Write-Warning (
                "Installation of $Name $Version failed " +
                "(attempt $attempt/$MaxAttempts): $errorMessage"
            )

            if ($attempt -ge $MaxAttempts) {
                throw "Failed to install $Name $Version after $MaxAttempts attempts. Last error: $errorMessage"
            }

            $delaySeconds = [int]([Math]::Pow(2, $attempt) * 10)

            Write-Host "Waiting $delaySeconds seconds before retry..."
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

# Read module configuration from the runner-images toolset
$modules = (Get-ToolsetContent).powershellModules

foreach ($module in $modules) {
    $moduleName = [string]$module.name

    if ([string]::IsNullOrWhiteSpace($moduleName)) {
        throw "A PowerShell module entry has no name"
    }

    Write-Host "Processing $moduleName module"

    if ($module.versions) {
        $versions = @($module.versions)
    } else {
        $versions = @($null)
    }

    foreach ($version in $versions) {
        # PowerShellGet was installed in Configure-PowerShell.ps1.
        # Avoid reinstalling it while PackageManagement is in use.
        if ($moduleName -eq 'PowerShellGet' -and
            (-not $version -or [version]$version -eq [version]$powerShellGetVersion) -and
            (Test-ModuleInstalled -Name $moduleName -Version $powerShellGetVersion)) {

            Write-Host "PowerShellGet $powerShellGetVersion already installed; skipping"
            continue
        }

        Install-ModuleWithRetry `
            -Name $moduleName `
            -Version $version
    }
}

# Validate installed modules
Write-Host "Running PowerShellModules Pester tests..."

Import-Module Pester -ErrorAction Stop

Invoke-PesterTests `
    -TestFile "PowerShellModules" `
    -TestName "PowerShellModules"

Write-Host "PowerShell module installation and validation completed"
