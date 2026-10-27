
################################################################################
## File: Install-PowerShellModules.ps1
## Desc: Install common PowerShell modules with retries and HTTP diagnostics
################################################################################

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

# Ensure TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor `
    [Net.SecurityProtocolType]::Tls12

$powerShellGetVersion = '2.2.5'
$graphDependencyVersion = '2.41.2'

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

################################################################################
# PowerShellGet initialization
################################################################################

function Test-ModuleInstalled {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Version
    )

    $installed = @(Get-Module -Name $Name -ListAvailable)

    if ($Version) {
        $installed = @(
            $installed | Where-Object {
                $_.Version -eq [version]$Version
            }
        )
    }

    return ($installed.Count -gt 0)
}

if (-not (Test-ModuleInstalled `
    -Name 'PowerShellGet' `
    -Version $powerShellGetVersion)) {

    throw "PowerShellGet $powerShellGetVersion is missing. Configure-PowerShell.ps1 must install it first."
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

################################################################################
# HTTP diagnostics
################################################################################

function Test-PSGalleryPackageDownload {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $uri = "https://www.powershellgallery.com/api/v2/package/$Name/$Version"

    $destination = Join-Path $env:TEMP (
        "psgallery-test-{0}.nupkg" -f [guid]::NewGuid()
    )

    Write-Host "HTTP test: $uri"

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()

    try {
        Invoke-WebRequest `
            -Uri $uri `
            -OutFile $destination `
            -UseBasicParsing `
            -ErrorAction Stop

        $file = Get-Item -LiteralPath $destination

        if ($file.Length -eq 0) {
            throw "Downloaded package is empty"
        }

        # NuGet packages are ZIP archives.
        $archive = [System.IO.Compression.ZipFile]::OpenRead($destination)

        try {
            if ($archive.Entries.Count -eq 0) {
                throw "Downloaded package contains no entries"
            }
        }
        finally {
            $archive.Dispose()
        }

        $stopwatch.Stop()

        Write-Host (
            "HTTP download succeeded: {0} ({1} bytes, {2:N1}s)" -f `
            $Name,
            $file.Length,
            $stopwatch.Elapsed.TotalSeconds
        )

        return $true
    }
    catch {
        $stopwatch.Stop()

        Write-Warning (
            "HTTP download failed for {0} after {1:N1}s: {2}" -f `
            $Name,
            $stopwatch.Elapsed.TotalSeconds,
            $_.Exception.Message
        )

        if ($_.Exception.Response) {
            try {
                $statusCode = [int]$_.Exception.Response.StatusCode
                Write-Warning "HTTP status: $statusCode"
            }
            catch {
                Write-Warning "HTTP status unavailable"
            }
        }

        return $false
    }
    finally {
        Remove-Item `
            -LiteralPath $destination `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

################################################################################
# Microsoft.Graph preflight
################################################################################

function Test-MicrosoftGraphDependencies {
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    Write-Host "Starting Microsoft.Graph HTTP preflight"

    # These dependencies have failed in previous image builds.
    $dependencies = @(
        'Microsoft.Graph.Bookings'
        'Microsoft.Graph.People'
        'Microsoft.Graph.Sites'
        'Microsoft.Graph.DeviceManagement.Enrollment'
    )

    $failedDependencies = @()

    foreach ($dependency in $dependencies) {
        $result = Test-PSGalleryPackageDownload `
            -Name $dependency `
            -Version $Version

        if (-not $result) {
            $failedDependencies += $dependency
        }
    }

    if ($failedDependencies.Count -gt 0) {
        Write-Warning (
            "Graph HTTP preflight failed for: " +
            ($failedDependencies -join ', ')
        )
    }
    else {
        Write-Host "All selected Graph dependency HTTP tests passed"
    }

    # Diagnostic only: the installer will still run.
}

################################################################################
# Installation with retries
################################################################################

function Install-ModuleWithRetry {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Version,

        [int]$MaxAttempts = 3
    )

    if ($Name -eq 'Microsoft.Graph') {
        $MaxAttempts = 5

        Test-MicrosoftGraphDependencies `
            -Version $graphDependencyVersion
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $versionLabel = if ($Version) {
                $Version
            }
            else {
                'latest'
            }

            Write-Host (
                "Installing {0} {1} (attempt {2}/{3})" -f `
                $Name,
                $versionLabel,
                $attempt,
                $MaxAttempts
            )

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

            if (-not (Test-ModuleInstalled `
                -Name $Name `
                -Version $Version)) {

                throw "Module $Name $versionLabel was not found after installation"
            }

            Write-Host "Successfully installed $Name $versionLabel"
            return
        }
        catch {
            $errorMessage = $_.Exception.Message

            Write-Warning (
                "Installation of {0} failed (attempt {1}/{2}): {3}" -f `
                $Name,
                $attempt,
                $MaxAttempts,
                $errorMessage
            )

            # Test the exact dependency reported by PackageManagement.
            if ($errorMessage -match "Package '([^']+)' failed to download") {
                $failedPackage = $Matches[1]
                $failedVersion = $null

                # Prefer a pinned version when available.
                if ($failedPackage -eq $Name -and $Version) {
                    $failedVersion = $Version
                }
                elseif ($Name -eq 'Microsoft.Graph') {
                    # Current Graph dependency version from build logs.
                    $failedVersion = $graphDependencyVersion
                }

                if ($failedVersion) {
                    Write-Host "Diagnosing failed package: $failedPackage"

                    $httpResult = Test-PSGalleryPackageDownload `
                        -Name $failedPackage `
                        -Version $failedVersion

                    Write-Host (
                        "HTTP diagnostic result for {0}: {1}" -f `
                        $failedPackage,
                        $httpResult
                    )
                }
                else {
                    Write-Warning (
                        "Cannot determine package version for HTTP diagnostic: " +
                        $failedPackage
                    )
                }
            }

            if ($attempt -ge $MaxAttempts) {
                throw (
                    "Failed to install {0} after {1} attempts. Last error: {2}" -f `
                    $Name,
                    $MaxAttempts,
                    $errorMessage
                )
            }

            $delaySeconds = [int](
                [Math]::Pow(2, $attempt) * 10
            )

            Write-Host "Waiting $delaySeconds seconds before retry..."
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

################################################################################
# Install modules from runner-images toolset
################################################################################

$modules = (Get-ToolsetContent).powershellModules

foreach ($module in $modules) {
    $moduleName = [string]$module.name

    if ([string]::IsNullOrWhiteSpace($moduleName)) {
        throw "PowerShell module entry has no name"
    }

    Write-Host "Processing $moduleName module"

    if ($module.versions) {
        $versions = @($module.versions)
    }
    else {
        $versions = @($null)
    }

    foreach ($version in $versions) {
        # Avoid reinstalling the active PowerShellGet version.
        if (
            $moduleName -eq 'PowerShellGet' -and
            (-not $version -or
                [version]$version -eq [version]$powerShellGetVersion) -and
            (Test-ModuleInstalled `
                -Name 'PowerShellGet' `
                -Version $powerShellGetVersion)
        ) {
            Write-Host (
                "PowerShellGet $powerShellGetVersion already installed; skipping"
            )

            continue
        }

        Install-ModuleWithRetry `
            -Name $moduleName `
            -Version $version
    }
}

################################################################################
# Validation
################################################################################

Write-Host "Running PowerShellModules Pester tests..."

Import-Module Pester -ErrorAction Stop

Invoke-PesterTests `
    -TestFile "PowerShellModules" `
    -TestName "PowerShellModules"

Write-Host "PowerShell module installation and validation completed"
