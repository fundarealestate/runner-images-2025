
################################################################################
## File: Install-PyPy.ps1
## Desc: Install PyPy
## Supply chain security: SHA256 checksum validation
################################################################################

$ErrorActionPreference = 'Stop'

function Get-PyPyChecksum {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Html,

        [Parameter(Mandatory = $true)]
        [string] $FileName
    )

    # Match a SHA256 checksum followed by the exact archive filename.
    # No ConvertFrom-HTML dependency is required.
    $escapedName = [regex]::Escape($FileName)

    $pattern = '(?i)(?<![0-9a-f])(?<hash>[0-9a-f]{64})\s+' +
               $escapedName +
               '(?![a-zA-Z0-9._-])'

    $matches = [regex]::Matches($Html, $pattern)

    if ($matches.Count -ne 1) {
        throw "Expected exactly one SHA256 checksum for '$FileName'; found $($matches.Count)."
    }

    return $matches[0].Groups['hash'].Value.ToUpperInvariant()
}

function Install-PyPy {
    param(
        [Parameter(Mandatory = $true)]
        [string] $PackagePath,

        [Parameter(Mandatory = $true)]
        [string] $Architecture
    )

    $pypyToolcachePath = Join-Path $env:AGENT_TOOLSDIRECTORY 'PyPy'

    if (-not (Test-Path $pypyToolcachePath)) {
        Write-Host "Create PyPy toolcache folder"
        New-Item -ItemType Directory -Path $pypyToolcachePath -Force |
            Out-Null
    }

    # Expand the archive using the runner-images helper.
    $packageName = [IO.Path]::GetFileNameWithoutExtension(
        (Split-Path -Path $PackagePath -Leaf)
    )

    $tempFolder = Join-Path $pypyToolcachePath $packageName

    Write-Host "Extracting PyPy archive: $PackagePath"

    Expand-7ZipArchive `
        -Path $PackagePath `
        -DestinationPath $pypyToolcachePath

    if (-not (Test-Path $tempFolder -PathType Container)) {
        throw "Expected extracted PyPy folder not found: $tempFolder"
    }

    # Discover the executable from the extracted archive.
    $pypyApp = Get-ChildItem -Path $tempFolder -Filter 'pypy*.exe' -File |
        Where-Object { $_.Name -match '^pypy(\d+)?\.exe$' } |
        Select-Object -First 1

    if (-not $pypyApp) {
        throw "PyPy executable not found in '$tempFolder'."
    }

    $pythonVersion = & $pypyApp.FullName -c `
        "import sys;print('{}.{}.{}'.format(*sys.version_info[:3]))"

    if ($LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($pythonVersion)) {
        throw "Failed to determine Python version from '$($pypyApp.FullName)'."
    }

    $pypyFullVersion = & $pypyApp.FullName -c `
        "import sys;print('{}.{}.{}'.format(*sys.pypy_version_info[:3]))"

    if ($LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($pypyFullVersion)) {
        throw "Failed to determine PyPy version from '$($pypyApp.FullName)'."
    }

    $pythonVersion = $pythonVersion.Trim()
    $pypyFullVersion = $pypyFullVersion.Trim()

    Write-Host "Python version: $pythonVersion"
    Write-Host "PyPy version: $pypyFullVersion"

    Set-Content `
        -Path (Join-Path $tempFolder 'PYPY_VERSION') `
        -Value $pypyFullVersion `
        -Encoding ASCII

    $pypyVersionPath = Join-Path $pypyToolcachePath $pythonVersion
    $pypyArchPath = Join-Path $pypyVersionPath $Architecture

    New-Item -ItemType Directory -Path $pypyVersionPath -Force |
        Out-Null

    if (Test-Path $pypyArchPath) {
        throw "PyPy installation directory already exists: $pypyArchPath"
    }

    Write-Host "Moving PyPy files to '$pypyArchPath'"

    Invoke-ScriptBlockWithRetry -Command {
        Move-Item `
            -Path $tempFolder `
            -Destination $pypyArchPath `
            -ErrorAction Stop
    }

    # Some PyPy archives do not contain python.exe.
    $pythonExe = Join-Path $pypyArchPath 'python.exe'

    if (-not (Test-Path $pythonExe)) {
        $pypyExe = Join-Path $pypyArchPath $pypyApp.Name

        if (-not (Test-Path $pypyExe)) {
            throw "PyPy executable missing after installation: $pypyExe"
        }

        Write-Host "Creating python.exe from '$($pypyApp.Name)'"

        # A copy avoids requiring mklink privileges and works with
        # the standard Windows PowerShell provisioning environment.
        Copy-Item -Path $pypyExe -Destination $pythonExe
    }

    Write-Host "Installing pip for PyPy $pythonVersion"

    & $pythonExe -m ensurepip

    if ($LASTEXITCODE -ne 0) {
        throw "PyPy ensurepip failed with exit code $LASTEXITCODE"
    }

    & $pythonExe -m pip install --upgrade pip

    if ($LASTEXITCODE -ne 0) {
        throw "PyPy pip upgrade failed with exit code $LASTEXITCODE"
    }

    # Create pip.exe if only pip3.exe exists.
    $pipPath = Join-Path $pypyArchPath 'Scripts\pip.exe'

    if (-not (Test-Path $pipPath)) {
        $pip3Path = Join-Path $pypyArchPath 'Scripts\pip3.exe'

        if (-not (Test-Path $pip3Path)) {
            throw "Neither pip.exe nor pip3.exe exists in '$pypyArchPath'."
        }

        Copy-Item -Path $pip3Path -Destination $pipPath
    }

    # Validate the installed interpreter before marking it complete.
    $installedPythonVersion = & $pythonExe -c `
        "import sys;print('{}.{}.{}'.format(*sys.version_info[:3]))"

    if ($LASTEXITCODE -ne 0 -or
        $installedPythonVersion.Trim() -ne $pythonVersion) {
        throw "Installed PyPy interpreter validation failed."
    }

    # setup-python expects an architecture-specific .complete marker.
    $completeFile = Join-Path $pypyVersionPath "$Architecture.complete"

    New-Item -ItemType File -Path $completeFile -Force |
        Out-Null

    Write-Host "PyPy $pythonVersion ($Architecture) installed successfully"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($env:AGENT_TOOLSDIRECTORY)) {
    throw 'AGENT_TOOLSDIRECTORY environment variable is not set.'
}

# TLS 1.2 is needed for compatibility with Windows PowerShell 5.1.
$originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        $originalSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    # Get the PyPy configuration from runner-images toolset.
    $toolsetVersions = Get-ToolsetContent |
        Select-Object -ExpandProperty toolcache |
        Where-Object { $_.name -eq 'PyPy' }

    if (-not $toolsetVersions) {
        throw 'PyPy configuration not found in the toolset.'
    }

    if (-not $toolsetVersions.versions) {
        throw 'No PyPy versions specified in the toolset.'
    }

    if (-not $toolsetVersions.arch) {
        throw 'PyPy architecture not specified in the toolset.'
    }

    # The official PyPy release metadata.
    $versionsUrl = 'https://downloads.python.org/pypy/versions.json'

    Write-Host "Fetching PyPy releases from $versionsUrl"

    $pypyVersions = Invoke-RestMethod `
        -Uri $versionsUrl `
        -ErrorAction Stop

    if (-not $pypyVersions) {
        throw 'PyPy versions metadata is empty.'
    }

    # The official checksums page.
    $checksumsUrl = 'https://www.pypy.org/checksums.html'

    Write-Host "Fetching PyPy checksums from $checksumsUrl"

    $response = Invoke-WebRequest `
        -Uri $checksumsUrl `
        -UseBasicParsing `
        -ErrorAction Stop

    $checksumsHtml = [string]$response.Content

    if ([string]::IsNullOrWhiteSpace($checksumsHtml)) {
        throw 'PyPy checksums page is empty.'
    }

    Write-Host 'Start PyPy installation'

    foreach ($toolsetVersion in $toolsetVersions.versions) {

        Write-Host "Resolving PyPy for Python $toolsetVersion"

        # Preserve the upstream release-selection approach:
        # select the first stable release matching the requested
        # Python major.minor version, then its Windows archive.
        $release = $pypyVersions |
            Where-Object {
                $_.stable -eq $true -and
                $_.python_version.StartsWith("$toolsetVersion")
            } |
            Select-Object -First 1

        if (-not $release) {
            throw "No stable PyPy release found for Python $toolsetVersion"
        }

        $package = $release.files |
            Where-Object {
                $_.platform -like 'win*' -and
                $_.filename -like '*-win64.zip'
            } |
            Select-Object -First 1

        if (-not $package) {
            throw "No Windows x64 PyPy archive found for Python $toolsetVersion"
        }

        $filename = [string]$package.filename
        $downloadUrl = [string]$package.download_url

        if ([string]::IsNullOrWhiteSpace($filename) -or
            [string]::IsNullOrWhiteSpace($downloadUrl)) {
            throw "Incomplete PyPy release metadata for Python $toolsetVersion"
        }

        Write-Host "Found PyPy package: $filename"

        # Read the checksum BEFORE downloading and extracting.
        $expectedHash = Get-PyPyChecksum `
            -Html $checksumsHtml `
            -FileName $filename

        Write-Host "Expected SHA256: $expectedHash"

        # runner-images helper downloads the archive with retry.
        $tempPyPyPackagePath = Invoke-DownloadWithRetry $downloadUrl

        if (-not (Test-Path $tempPyPyPackagePath -PathType Leaf)) {
            throw "PyPy download file not found: $tempPyPyPackagePath"
        }

        # Validate the downloaded archive against the distributor hash.
        Test-FileChecksum `
            $tempPyPyPackagePath `
            -ExpectedSHA256Sum $expectedHash

        Write-Host "Checksum validation passed for $filename"

        Install-PyPy `
            -PackagePath $tempPyPyPackagePath `
            -Architecture $toolsetVersions.arch
    }

    Write-Host 'PyPy installation completed successfully'
}
finally {
    [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
}
