param(
  [string]$Script,
  [int]$MaxRetries = 10,
  [int]$DelaySeconds = 30
)

for ($i = 1; $i -le $MaxRetries; $i++) {
  try {
    Write-Host "[Attempt $i/$MaxRetries] Running $Script"
    & $Script
    if ($LASTEXITCODE -eq 0) { exit 0 }
    else { throw "Exit code $LASTEXITCODE" }
  } catch {
    Write-Warning "Attempt $i failed: $_"
    if ($i -lt $MaxRetries) { Start-Sleep -Seconds $DelaySeconds }
    else { exit 1 }
  }
}
