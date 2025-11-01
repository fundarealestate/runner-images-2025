param(
    [Parameter(Mandatory = $true)][string]$Script,
    [int]$MaxRetries = 10,
    [int]$DelaySeconds = 30
)

# Global allowed exit codes
$GlobalAllowedExitCodes = @(0, 1, 3010)

# # Per-script allowed exit codes
# $PerScriptAllowedExitCodes = @{
#     "Configure-WindowsDefender.ps1" = @(0, 1)  
#     "Configure-PowerShell.ps1"      = @(0, 1)  
#     "Install‑VisualStudio.ps1"      = @(0, 3010)  
#     "Install‑KubernetesTools.ps1"   = @(0, 3010)  
# }

# # Determine which exit codes are allowed for this script
$scriptName = Split-Path $Script -Leaf
# $allowedExitCodes = if ($PerScriptAllowedExitCodes.ContainsKey($scriptName)) {
#     $PerScriptAllowedExitCodes[$scriptName]
# } else {
#     $GlobalAllowedExitCodes
# }
$allowedExitCodes = $GlobalAllowedExitCodes

for ($i = 1; $i -le $MaxRetries; $i++) {
    Write-Host "[Attempt $i/$MaxRetries] Running $Script"
    
    & $Script
    $exitCode = $LASTEXITCODE

    if ($allowedExitCodes -contains $exitCode) {
        Write-Host "Script $scriptName finished with allowed exit code $exitCode."
        exit 0
    }

    Write-Warning "Script $scriptName failed with exit code $exitCode"

    if ($i -lt $MaxRetries) {
        Write-Host "Retrying in $DelaySeconds seconds..."
        Start-Sleep -Seconds $DelaySeconds
    } else {
        Write-Error "Script $scriptName failed after $MaxRetries attempts."
        exit $exitCode
    }
}
