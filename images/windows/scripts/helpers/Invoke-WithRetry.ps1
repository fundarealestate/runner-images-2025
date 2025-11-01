param(
    [Parameter(Mandatory = $true)][string]$Script,
    [int]$MaxRetries = 10,
    [int]$DelaySeconds = 30
)

# Define allowed exit codes that do not trigger a retry
$AllowedExitCodes = @(0, 1, 3010)

for ($i = 1; $i -le $MaxRetries; $i++) {
    $exitCode = $null
    try {
        Write-Host "[Attempt $i/$MaxRetries] Running $Script"

        # Run the script and capture terminating errors
        & $Script

        # Determine exit code
        if ($LASTEXITCODE -ne $null) {
            $exitCode = $LASTEXITCODE
        } elseif ($?) {
            $exitCode = 0
        } else {
            $exitCode = 1
        }

        Write-Host "[Info] Script returned exit code: $exitCode"

        if ($AllowedExitCodes -contains $exitCode) {
            Write-Host "[Info] Exit code $exitCode is allowed. No retry needed."
            exit $exitCode
        }

        throw "Script failed with exit code $exitCode"
    } catch {
        Write-Warning "Attempt $i failed: $_"
        if ($i -lt $MaxRetries) {
            Write-Host "Retrying in $DelaySeconds seconds..."
            Start-Sleep -Seconds $DelaySeconds
        } else {
            Write-Error "Script $Script failed after $MaxRetries attempts (last exit code: $exitCode)."
            exit $exitCode
        }
    }
}
