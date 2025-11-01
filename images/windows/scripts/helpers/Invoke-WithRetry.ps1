param(
  [Parameter(Mandatory = $true)][string]$Script,
  [int]$MaxRetries = 10,
  [int]$DelaySeconds = 30
)

for ($i = 1; $i -le $MaxRetries; $i++) {
  try {
    Write-Host "[Attempt $i/$MaxRetries] Running $Script"
    & $Script
    if ($LASTEXITCODE -eq 0) { exit 0 }
    throw "Script failed with exit code $LASTEXITCODE"
  } catch {
    Write-Warning "Attempt $i failed: $_"
    if ($i -lt $MaxRetries) {
      Write-Host "Retrying in $DelaySeconds seconds..."
      Start-Sleep -Seconds $DelaySeconds
    } else {
      Write-Error "Script $Script failed after $MaxRetries attempts."
      exit 1
    }
  }
}
