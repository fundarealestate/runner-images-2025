################################################################################
##  File:  Configure-WindowsDefender.ps1
##  Desc:  Safely disables or skips Windows Defender configuration on
##         Windows Server 2025 / Azure base images.
################################################################################

Write-Host "=== Configure Windows Defender ==="

try {
    $startedDefender = $false
    $hasDefender = $false

    # Detect Defender service
    $defenderService = Get-Service -Name WinDefend -ErrorAction SilentlyContinue

    if ($null -eq $defenderService) {
        Write-Host "[Info] Windows Defender service not found. Likely managed by MDE or removed."
    } else {
        $hasDefender = $true
        Write-Host "[Info] Defender service state: $($defenderService.Status)"

        # Try to start temporarily if stopped
        if ($defenderService.Status -ne 'Running') {
            Write-Host "[Info] Attempting to start WinDefend service..."
            try {
                Set-Service -Name WinDefend -StartupType Manual
                Start-Service -Name WinDefend -ErrorAction Stop
                Start-Sleep -Seconds 10
                Write-Host "[Info] WinDefend service started."
                $startedDefender = $true
            } catch {
                Write-Warning "[Skip] Could not start WinDefend service: $($_.Exception.Message)"
                $hasDefender = $false
            }
        }
    }

    if ($hasDefender) {
        Write-Host "[Action] Applying Defender preferences..."

        $avPreference = @(
            @{DisableArchiveScanning = $true}
            @{DisableAutoExclusions = $true}
            @{DisableBehaviorMonitoring = $true}
            @{DisableBlockAtFirstSeen = $true}
            @{DisableCatchupFullScan = $true}
            @{DisableCatchupQuickScan = $true}
            @{DisableIntrusionPreventionSystem = $true}
            @{DisableIOAVProtection = $true}
            @{DisablePrivacyMode = $true}
            @{DisableScanningNetworkFiles = $true}
            @{DisableScriptScanning = $true}
            @{MAPSReporting = 0}
            @{PUAProtection = 0}
            @{SignatureDisableUpdateOnStartupWithoutEngine = $true}
            @{SubmitSamplesConsent = 2}
            @{ScanAvgCPULoadFactor = 5; ExclusionPath = @("D:\", "C:\")}
            @{DisableRealtimeMonitoring = $true}
            @{ScanScheduleDay = 8}
            @{EnableControlledFolderAccess = "Disable"}
            @{EnableNetworkProtection = "Disabled"}
        )

        foreach ($avParams in $avPreference) {
            try {
                $keys = ($avParams.Keys -join ", ")
                Set-MpPreference @avParams -ErrorAction Stop
                Write-Host " ==> Applied: $keys"
            } catch {
                Write-Warning "  (!) Skipped '$keys' - $($_.Exception.Message)"
            }
        }

        # Passive mode for MDE
        $atpRegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection'
        if (Test-Path $atpRegPath) {
            Write-Host "[Action] Enabling Defender passive mode (MDE compatibility)..."
            try {
                Set-ItemProperty -Path $atpRegPath -Name 'ForceDefenderPassiveMode' -Value '1' -Type 'DWORD'
                Write-Host " ==> Passive mode enabled."
            } catch {
                Write-Warning "  (!) Failed to set passive mode: $($_.Exception.Message)"
            }
        } else {
            Write-Host "[Info] MDE policy path not found; skipping passive mode configuration."
        }

        # Restore service state
        if ($startedDefender) {
            Write-Host "[Info] Stopping Defender service to restore original state..."
            try {
                Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
                Set-Service -Name WinDefend -StartupType Disabled
                Write-Host " ==> Defender service stopped and disabled."
            } catch {
                Write-Warning "  (!) Could not stop Defender service: $($_.Exception.Message)"
            }
        }
    }

    Write-Host "=== Windows Defender configuration completed ==="

} catch {
    Write-Warning "Unexpected error in Windows Defender configuration: $_"
} finally {
    # Always exit 0 to make Packer happy
    exit 0
}
