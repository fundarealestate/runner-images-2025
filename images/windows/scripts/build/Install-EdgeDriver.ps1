
################################################################################
##  File:  Install-EdgeDriver.ps1
##  Desc:  Install Edge WebDriver and configure Microsoft Edge
################################################################################

$ErrorActionPreference = "Stop"

if (Test-IsArm64) {
    $driverArch = "arm64"
    $edgeArch = "arm64"
} else {
    $driverArch = "win64"
    $edgeArch = "x64"
}

# Install the latest Edge Stable explicitly, the background updater can fail during the build
Write-Host "Get the latest Microsoft Edge Stable version..."

$edgeProducts = Invoke-RestMethod -Uri "https://edgeupdates.microsoft.com/api/products"

$edgeRelease = ($edgeProducts | Where-Object { $_.Product -eq "Stable" }).Releases |
    Where-Object { $_.Platform -eq "Windows" -and $_.Architecture -eq $edgeArch } |
    Sort-Object { [version] $_.ProductVersion } -Descending |
    Select-Object -First 1

if (-not $edgeRelease) {
    throw "Unable to find a Microsoft Edge Stable release for Windows $edgeArch"
}

$edgeMsi = $edgeRelease.Artifacts |
    Where-Object { $_.ArtifactName -eq "msi" } |
    Select-Object -First 1

if (-not $edgeMsi -or
    [string]::IsNullOrWhiteSpace($edgeMsi.Location) -or
    [string]::IsNullOrWhiteSpace($edgeMsi.Hash)) {
    throw "Microsoft Edge Stable MSI metadata is missing or incomplete"
}

Write-Host "Install Microsoft Edge $($edgeRelease.ProductVersion)..."

Install-Binary -Type MSI `
    -Url $edgeMsi.Location `
    -ExpectedSHA256Sum $edgeMsi.Hash `
    -ExpectedSubject $(Get-MicrosoftPublisher)

# Disable Edge auto-updates
# The MSI starts Edge Update in the background, let it finish so it does not
# restore the executable after the rename.
Get-Process -Name "MicrosoftEdgeUpdate*" -ErrorAction SilentlyContinue |
    Wait-Process -Timeout 300 -ErrorAction SilentlyContinue

Stop-Service -Name "edgeupdate", "edgeupdatem" -Force -ErrorAction SilentlyContinue

$edgeUpdatePath = "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate"

Rename-Item `
    -Path "$edgeUpdatePath\MicrosoftEdgeUpdate.exe" `
    -NewName "Disabled_MicrosoftEdgeUpdate.exe" `
    -ErrorAction Stop

Write-Host "Get the Microsoft Edge WebDriver version..."

$edgeBinaryPath = (Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe").'(default)'

if ([string]::IsNullOrWhiteSpace($edgeBinaryPath) -or
    -not (Test-Path -LiteralPath $edgeBinaryPath -PathType Leaf)) {
    throw "Microsoft Edge executable not found: '$edgeBinaryPath'"
}

[version] $edgeVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
    $edgeBinaryPath
).ProductVersion

if ($edgeVersion -lt [version] $edgeRelease.ProductVersion) {
    throw "Microsoft Edge $edgeVersion is installed, expected $($edgeRelease.ProductVersion)"
}

Write-Host "Installed Microsoft Edge version: $edgeVersion"

$edgeDriverPath = Join-Path $env:SystemDrive "SeleniumWebDrivers\EdgeDriver"

if (-not (Test-Path -LiteralPath $edgeDriverPath)) {
    New-Item -Path $edgeDriverPath -ItemType Directory -Force | Out-Null
}

# Download the latest EdgeDriver version for the installed Edge major version.
$versionInfoUrl = "https://msedgedriver.microsoft.com/LATEST_RELEASE_$($edgeVersion.Major)_WINDOWS"
$versionInfoPath = Join-Path $edgeDriverPath "versioninfo.txt"

Write-Host "Download EdgeDriver version metadata from $versionInfoUrl"

Invoke-DownloadWithRetry `
    -Url $versionInfoUrl `
    -Path $versionInfoPath | Out-Null

if (-not (Test-Path -LiteralPath $versionInfoPath -PathType Leaf)) {
    throw "EdgeDriver version metadata was not downloaded: $versionInfoPath"
}

$latestVersion = (Get-Content -LiteralPath $versionInfoPath -Raw).Trim()

if ($latestVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    throw "Invalid EdgeDriver version from '$versionInfoUrl': '$latestVersion'"
}

[version] $driverVersion = $latestVersion

Write-Host "Microsoft EdgeDriver version: $driverVersion"

# Microsoft requires the first three version components to match.
if ($driverVersion.Major -ne $edgeVersion.Major -or
    $driverVersion.Minor -ne $edgeVersion.Minor -or
    $driverVersion.Build -ne $edgeVersion.Build) {

    throw "EdgeDriver $driverVersion is incompatible with installed Edge $edgeVersion. The first three version components must match."
}

# Use an explicit destination. Do not depend on the helper's
# default temporary download path.
$downloadUrl = "https://msedgedriver.microsoft.com/$latestVersion/edgedriver_$driverArch.zip"
$archivePath = Join-Path $edgeDriverPath "edgedriver_$driverArch.zip"

Write-Host "Download Microsoft Edge WebDriver from $downloadUrl"

Invoke-DownloadWithRetry `
    -Url $downloadUrl `
    -Path $archivePath | Out-Null

if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "EdgeDriver archive was not downloaded: $archivePath"
}

if ((Get-Item -LiteralPath $archivePath).Length -eq 0) {
    throw "Downloaded EdgeDriver archive is empty: $archivePath"
}

Write-Host "Expand Microsoft Edge WebDriver archive..."

Expand-7ZipArchive `
    -Path $archivePath `
    -DestinationPath $edgeDriverPath

$driverExePath = Join-Path $edgeDriverPath "msedgedriver.exe"

if (-not (Test-Path -LiteralPath $driverExePath -PathType Leaf)) {
    throw "EdgeDriver executable not found after extraction: $driverExePath"
}

# Validate the EdgeDriver publisher signature.
Test-FileSignature `
    -Path $driverExePath `
    -ExpectedSubject $(Get-MicrosoftPublisher)

Write-Host "Setting the environment variables..."

[Environment]::SetEnvironmentVariable(
    "EdgeWebDriver",
    $edgeDriverPath,
    "Machine"
)

Add-MachinePathItem "$edgeDriverPath\"

Invoke-PesterTests -TestFile "Browsers" -TestName "Edge"
