
################################################################################
##  File:  Install-Miniconda.ps1
##  Desc:  Install the latest version of Miniconda and set $env:CONDA
##  Supply chain security: checksum validation
################################################################################

$ErrorActionPreference = "Stop"

$condaDestination = "C:\Miniconda"
$installerName = "Miniconda3-latest-Windows-x86_64.exe"
$repositoryUrl = "https://repo.anaconda.com/miniconda/"
$installerUrl = "$repositoryUrl$installerName"

#region Supply chain security

Write-Host "Retrieving Miniconda SHA256 checksum..."

$response = Invoke-WebRequest `
    -Uri $repositoryUrl `
    -UseBasicParsing `
    -ErrorAction Stop

$html = [string]$response.Content

if ([string]::IsNullOrWhiteSpace($html)) {
    throw "Miniconda repository index is empty: $repositoryUrl"
}

# The Anaconda repository index contains one HTML table row per file.
# Find the row for the exact installer, then extract its SHA256 hash.
$escapedInstallerName = [regex]::Escape($installerName)

$rowPattern = '(?is)<tr\b[^>]*>(?:(?!</tr>).)*?' +
              $escapedInstallerName +
              '(?:(?!</tr>).)*?</tr>'

$matchingRows = [regex]::Matches($html, $rowPattern)

if ($matchingRows.Count -ne 1) {
    throw "Expected exactly one repository row for '$installerName'; found $($matchingRows.Count)."
}

# SHA256 is a 64-character hexadecimal value.
$hashMatches = [regex]::Matches(
    $matchingRows[0].Value,
    '(?i)(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])'
)

if ($hashMatches.Count -ne 1) {
    throw "Expected exactly one SHA256 hash for '$installerName'; found $($hashMatches.Count)."
}

$distributorFileHash = $hashMatches[0].Value.ToUpperInvariant()

Write-Host "Miniconda SHA256: $distributorFileHash"

#endregion

Write-Host "Installing Miniconda..."

Install-Binary `
    -Url $installerUrl `
    -InstallArgs @(
        "/S",
        "/AddToPath=0",
        "/RegisterPython=0",
        "/D=$condaDestination"
    ) `
    -ExpectedSHA256Sum $distributorFileHash

[Environment]::SetEnvironmentVariable(
    "CONDA",
    $condaDestination,
    "Machine"
)

Invoke-PesterTests -TestFile "Miniconda"
