<#
.SYNOPSIS
    Intune Remediation - Generic Registry Management Template
.DESCRIPTION
    Self-contained script for detecting and remediating registry settings.
    Runs as SYSTEM and can modify both machine and per-user registry settings.
    Supports multiple configuration groups organized by scope (User/Machine).
    Supports both traditional AD (S-1-5-21-*) and Azure AD/Entra ID (S-1-12-1-*) joined devices.
    Supports setting, deleting values, and deleting entire registry keys.
    
    USAGE:
    1. Copy this template
    2. Modify the CONFIGURATION section below for your use case
    3. Save as detection script ($runRemediation = $false)
    4. Save as remediation script ($runRemediation = $true)
    5. Upload both to Intune Remediations
.NOTES
    Author: Martin Bengtsson
    Blog: https://www.imab.dk
    Version: 3.6
    
    Version History:
    3.6 - Added [CmdletBinding()] to Set-RegistryValue so -ErrorAction Stop propagates correctly.
          Code cleanup: removed dead variables, no-op switch cases, unused properties, simplified guard clauses.
    3.5 - Version stamp written to HKLM:\SOFTWARE\Intune-Registry-Management\<name> for fleet tracking.
          Replaced array concatenation ($results +=) with List[PSCustomObject] for O(1) performance.
    3.4 - Case-insensitive binary hex comparison to avoid false non-compliance.
          Date-stamped log rotation keeping 3 most recent old logs.
          Write-Log now emits Write-Warning on logging failures instead of silent catch.
    3.3 - Added Write-Log function for dual output (Intune portal + local log file).
          Log location: $env:ProgramData\Microsoft\IntuneManagementExtension\Logs\
          Configurable log file name ($LogFileName) and size-based rotation ($MaxLogSizeMB).
    3.2 - Removed useless HKCU fallback when no users logged on. Script now skips
          HKCU configurations gracefully and continues with HKLM processing.
    3.1 - Added Set, Delete, and DeleteKey actions. Clean multi-line formatting.
    
    Supported registry types: String, ExpandString, DWord, QWord, Binary, MultiString
    Supported actions: Set (default), Delete (value), DeleteKey (entire key)
    Scopes: $UserConfigs (per-user via HKU), $MachineConfigs (HKLM)
    
    Log format: yyyy-MM-dd HH:mm:ss [DETECT/REMEDIATE] [PREFIX] Message
#>

#region ==================== CONFIGURATION - MODIFY THIS SECTION ====================

<#
.QUICK START GUIDE
    
    This script manages registry settings for Intune Remediations.
    Modify the configuration sections below to suit your needs.
    
    STEP 1: CHOOSE YOUR SCOPE
    -------------------------
    • $UserConfigs  = Settings applied to EACH USER (HKCU/HKU)
                      Use for: User preferences, app settings per user
    • $MachineConfigs = Settings applied to the MACHINE (HKLM)
                      Use for: System-wide policies, machine settings
    
    STEP 2: ADD A CONFIGURATION GROUP
    ----------------------------------
    Copy this template and fill in your values:
    
    @{
        Name        = "My Setting Name"           # Friendly name (shown in logs)
        Description = "What this setting does"    # Description (shown in logs)
        BasePath    = "SOFTWARE\MyCompany\MyApp"  # Registry path WITHOUT HKCU/HKLM
        Settings    = @(
            # Add your settings here (see Step 3)
        )
    }
    
    STEP 3: ADD SETTINGS (choose one action type per setting)
    ---------------------------------------------------------
    
    ACTION: SET (create or update a value) - This is the default if Action is omitted
    @{
        Name  = "ValueName"
        Type  = "String"
        Value = "MyValue"
    }
    
    ACTION: DELETE (remove a specific value)
    @{
        Action = "Delete"
        Name   = "ValueName"
    }
    
    ACTION: DELETEKEY (remove an entire registry key and all its contents)
    @{
        Action = "DeleteKey"
        Name   = "SubKeyName"
    }
    
    SUPPORTED TYPES FOR SET ACTION
    ------------------------------
    • String       = Text value                    Example: "Hello World"
    • DWord        = 32-bit number (0-4294967295)  Example: 1
    • QWord        = 64-bit number                 Example: 9999999999
    • Binary       = Hex bytes, comma-separated   Example: "00,01,ff,ab"
    • ExpandString = String with %variables%       Example: "%USERPROFILE%\Desktop"
    • MultiString  = Multiple strings, pipe-sep   Example: "Value1|Value2|Value3"
    
    EXAMPLES
    --------
    Example 1: Set a simple string value in HKCU
        $UserConfigs = @(
            @{
                Name        = "App Setting"
                Description = "Configure my app"
                BasePath    = "SOFTWARE\MyApp"
                Settings    = @(
                    @{
                        Name  = "Language"
                        Type  = "String"
                        Value = "en-US"
                    }
                )
            }
        )
    
    Example 2: Set a DWORD policy in HKLM
        $MachineConfigs = @(
            @{
                Name        = "Disable Feature X"
                Description = "Disable Feature X via registry"
                BasePath    = "SOFTWARE\Policies\MyCompany"
                Settings    = @(
                    @{
                        Name  = "DisableFeatureX"
                        Type  = "DWord"
                        Value = 1
                    }
                )
            }
        )
    
    Example 3: Delete an unwanted value from HKCU
        $UserConfigs = @(
            @{
                Name        = "Remove Telemetry"
                Description = "Delete telemetry setting"
                BasePath    = "SOFTWARE\MyApp"
                Settings    = @(
                    @{
                        Action = "Delete"
                        Name   = "TelemetryEnabled"
                    }
                )
            }
        )
    
    Example 4: Delete an entire registry key from HKLM
        $MachineConfigs = @(
            @{
                Name        = "Remove Legacy App"
                Description = "Delete old app registry key"
                BasePath    = "SOFTWARE"
                Settings    = @(
                    @{
                        Action = "DeleteKey"
                        Name   = "OldAppToRemove"
                    }
                )
            }
        )
    
    STEP 4: SET SCRIPT MODE
    -----------------------
    At the bottom of this configuration section:
    • $runRemediation = $false  → Detection only (reports issues, no changes)
    • $runRemediation = $true   → Remediation (fixes issues)
    
    For Intune: Create TWO copies of this script:
    1. Detection script:   $runRemediation = $false
    2. Remediation script: $runRemediation = $true
    
    STEP 5: CONFIGURE LOGGING (optional)
    ------------------------------------
    • $LogFileName  = Name of the log file (without .log extension)
                      Example: "Intune-Registry-Management-OutlookFonts"
    • $MaxLogSizeMB = Maximum log file size before rotation (default: 4)
    
    Log files are stored in: $env:ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

# ============ USER CONFIGURATIONS (HKCU / HKU) ============
$UserConfigs = @(
    @{
        Name        = "imab.dk Settings"
        Description = "Sample per-user registry configuration"
        BasePath    = "SOFTWARE\imab.dk"
        Settings    = @(
            @{
                Name  = "BlogURL"
                Type  = "String"
                Value = "https://www.imab.dk"
            }
            @{
                Name  = "Author"
                Type  = "String"
                Value = "Martin Bengtsson"
            }
            @{
                Name  = "AwesomeLevel"
                Type  = "DWord"
                Value = 100
            }
        )
    }
)

# ============ MACHINE CONFIGURATIONS (HKLM) ============
$MachineConfigs = @(
    @{
        Name        = "imab.dk Settings"
        Description = "Sample machine-wide registry configuration"
        BasePath    = "SOFTWARE\imab.dk"
        Settings    = @(
            @{
                Name  = "BlogURL"
                Type  = "String"
                Value = "https://www.imab.dk"
            }
            @{
                Name  = "Author"
                Type  = "String"
                Value = "Martin Bengtsson"
            }
            @{
                Name  = "AwesomeLevel"
                Type  = "DWord"
                Value = 100
            }
        )
    }
)

# Script behavior - change this for detection vs remediation script
$runRemediation = $true  # $false = detection only, $true = detection + remediation

# Logging configuration
$LogFileName = "Intune-Registry-Management-imabdk"  # Change per script (e.g., "Intune-Registry-Management-OutlookFonts")
$MaxLogSizeMB = 4

# Version stamp - written to HKLM:\SOFTWARE\Intune-Registry-Management\<LogFileName>
$ScriptVersion = "3.6"

#endregion ==================== END CONFIGURATION ========================================


#region ==================== DO NOT MODIFY BELOW THIS LINE ===============================

# Derived logging values
[string]$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\$LogFileName.log"
[string]$ScriptMode = if ($runRemediation) { "REMEDIATE" } else { "DETECT" }

#region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes to both console (for Intune portal) and local log file.
    #>
    param([string]$Message)
    
    Write-Output $Message
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    
    try {
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length / 1MB) -ge $MaxLogSizeMB) {
            $rotatedName = "$LogFile.$(Get-Date -Format 'yyyyMMdd-HHmmss').old"
            Move-Item -Path $LogFile -Destination $rotatedName -Force -ErrorAction SilentlyContinue
            # Keep only the 3 most recent rotated logs
            Get-ChildItem -Path "$LogFile.*.old" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -Skip 3 |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
        Add-Content -Path $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$ScriptMode] $Message" -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write to log file '$LogFile': $($_.Exception.Message)"
    }
}

function Get-RegistryValue {
    <#
    .SYNOPSIS
        Gets a registry value, returning appropriate format based on type.
    #>
    param (
        [string]$Path,
        [string]$Name,
        [string]$Type
    )
    
    try {
        if (-not (Test-Path -Path $Path)) { return $null }
        
        $value = Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop
        
        # Convert binary to lowercase hex string for case-insensitive comparison
        if ($Type -eq "Binary") {
            return (($value | ForEach-Object { '{0:x2}' -f $_ }) -join ',').ToLower()
        }
        
        # Convert MultiString array to comparable format
        if ($Type -eq "MultiString") {
            return ($value -join "|")
        }
        
        return $value
    }
    catch {
        return $null
    }
}

function Set-RegistryValue {
    <#
    .SYNOPSIS
        Sets a registry value with the specified type.
    #>
    [CmdletBinding()]
    param (
        [string]$Path,
        [string]$Name,
        [string]$Type,
        $Value
    )
    
    # Ensure registry key exists
    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    
    # Convert value based on type
    $regType = $Type
    $regValue = $Value
    
    switch ($Type) {
        "Binary" {
            [byte[]]$regValue = $Value.Split(',') | ForEach-Object { [Convert]::ToByte($_, 16) }
        }
        "DWord" {
            $regValue = [int]$Value
        }
        "QWord" {
            $regValue = [long]$Value
        }
        "MultiString" {
            if ($Value -is [string]) {
                $regValue = $Value -split '\|'
            }
        }
    }
    
    Set-ItemProperty -Path $Path -Name $Name -Value $regValue -Type $regType -Force
}

function Compare-RegistryValue {
    <#
    .SYNOPSIS
        Compares current registry value with expected value.
    #>
    param (
        $CurrentValue,
        $ExpectedValue,
        [string]$Type
    )
    
    if ($null -eq $CurrentValue) { return $false }
    
    switch ($Type) {
        "Binary" {
            # Case-insensitive comparison for hex strings
            return ([string]$CurrentValue).ToLower() -eq ([string]$ExpectedValue).ToLower()
        }
        "MultiString" {
            $expected = if ($ExpectedValue -is [array]) { $ExpectedValue -join "|" } else { $ExpectedValue }
            return ($CurrentValue -eq $expected)
        }
        default {
            return ($CurrentValue -eq $ExpectedValue)
        }
    }
}

function Test-RegistryCompliance {
    <#
    .SYNOPSIS
        Tests a single registry setting for compliance and optionally remediates.
        Supports Set (default), Delete, and DeleteKey actions.
    #>
    param (
        [string]$Path,
        [hashtable]$Setting,
        [bool]$Remediate
    )
    
    # Default action is Set if not specified
    $action = if ($Setting.Action) { $Setting.Action } else { "Set" }
    
    $result = [PSCustomObject]@{
        Name               = $Setting.Name
        NeedsRemediation   = $false
        RemediationSuccess = $null
        Message            = ""
    }
    
    switch ($action) {
        "DeleteKey" {
            # Check if key exists (path + subkey name)
            $keyPath = Join-Path $Path $Setting.Name
            $keyExists = Test-Path -Path $keyPath
            
            if ($keyExists) {
                $result.NeedsRemediation = $true
                
                if ($Remediate) {
                    try {
                        Remove-Item -Path $keyPath -Recurse -Force -ErrorAction Stop
                        
                        if (-not (Test-Path -Path $keyPath)) {
                            $result.RemediationSuccess = $true
                            $result.Message = "[DELETED KEY] $($Setting.Name)"
                        }
                        else {
                            $result.RemediationSuccess = $false
                            $result.Message = "[ERROR] $($Setting.Name) - Key still exists after deletion"
                        }
                    }
                    catch {
                        $result.RemediationSuccess = $false
                        $result.Message = "[ERROR] $($Setting.Name) - $($_.Exception.Message)"
                    }
                }
                else {
                    $result.Message = "[NON-COMPLIANT] $($Setting.Name) (key exists, should be deleted)"
                }
            }
            else {
                $result.Message = "[COMPLIANT] $($Setting.Name) (key absent)"
            }
        }
        
        "Delete" {
            # Check if value exists
            $valueExists = $false
            if (Test-Path -Path $Path) {
                $regKey = Get-Item -Path $Path -ErrorAction SilentlyContinue
                if ($regKey -and $Setting.Name -in $regKey.GetValueNames()) {
                    $valueExists = $true
                }
            }
            
            if ($valueExists) {
                $result.NeedsRemediation = $true
                
                if ($Remediate) {
                    try {
                        Remove-ItemProperty -Path $Path -Name $Setting.Name -Force -ErrorAction Stop
                        
                        # Verify deletion
                        $regKey = Get-Item -Path $Path -ErrorAction SilentlyContinue
                        if (-not ($Setting.Name -in $regKey.GetValueNames())) {
                            $result.RemediationSuccess = $true
                            $result.Message = "[DELETED] $($Setting.Name)"
                        }
                        else {
                            $result.RemediationSuccess = $false
                            $result.Message = "[ERROR] $($Setting.Name) - Value still exists after deletion"
                        }
                    }
                    catch {
                        $result.RemediationSuccess = $false
                        $result.Message = "[ERROR] $($Setting.Name) - $($_.Exception.Message)"
                    }
                }
                else {
                    $result.Message = "[NON-COMPLIANT] $($Setting.Name) (exists, should be deleted)"
                }
            }
            else {
                $result.Message = "[COMPLIANT] $($Setting.Name) (absent)"
            }
        }
        
        default {
            # "Set" action - original behavior
            $currentValue = Get-RegistryValue -Path $Path -Name $Setting.Name -Type $Setting.Type
            $isCompliant = Compare-RegistryValue -CurrentValue $currentValue -ExpectedValue $Setting.Value -Type $Setting.Type
            
            if (-not $isCompliant) {
                $result.NeedsRemediation = $true
                
                if ($Remediate) {
                    try {
                        Set-RegistryValue -Path $Path -Name $Setting.Name -Type $Setting.Type -Value $Setting.Value -ErrorAction Stop
                        
                        # Verify
                        $newValue = Get-RegistryValue -Path $Path -Name $Setting.Name -Type $Setting.Type
                        if (Compare-RegistryValue -CurrentValue $newValue -ExpectedValue $Setting.Value -Type $Setting.Type) {
                            $result.RemediationSuccess = $true
                            $result.Message = "[REMEDIATED] $($Setting.Name) ($($Setting.Type))"
                        }
                        else {
                            $result.RemediationSuccess = $false
                            $result.Message = "[ERROR] $($Setting.Name) ($($Setting.Type)) - Verification failed"
                        }
                    }
                    catch {
                        $result.RemediationSuccess = $false
                        $result.Message = "[ERROR] $($Setting.Name) ($($Setting.Type)) - $($_.Exception.Message)"
                    }
                }
                else {
                    $result.Message = "[NON-COMPLIANT] $($Setting.Name) ($($Setting.Type))"
                }
            }
            else {
                $result.Message = "[COMPLIANT] $($Setting.Name) ($($Setting.Type))"
            }
        }
    }
    
    return $result
}

#endregion

#region Main Execution

Write-Log "[START] Registry Management - $(if ($runRemediation) { 'REMEDIATION' } else { 'DETECTION' })"

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# Cache user SIDs once if any User configs exist
$cachedUserSIDs = $null
if ($UserConfigs.Count -gt 0) {
    $cachedUserSIDs = (Get-ChildItem "Registry::HKEY_USERS" -ErrorAction SilentlyContinue).PSChildName | 
        Where-Object { $_ -match '^S-1-(5-21|12-1)-\d+-\d+-\d+-\d+$' }
    
    if (-not $cachedUserSIDs) {
        Write-Log "[SKIPPED] No user profiles loaded in registry - HKCU settings will be skipped"
    }
}

# Process USER configurations
if ($UserConfigs.Count -gt 0 -and $cachedUserSIDs) {
    $configNum = 0
    foreach ($config in $UserConfigs) {
        $configNum++
        Write-Log "[USER] Config $configNum of $($UserConfigs.Count): $($config.Name) - $($config.Description)"
        Write-Log "[PATH] HKU:\<SID>\$($config.BasePath)"
        
        foreach ($sid in $cachedUserSIDs) {
            $regPath = "Registry::HKEY_USERS\$sid\$($config.BasePath)"
            foreach ($setting in $config.Settings) {
                $result = Test-RegistryCompliance -Path $regPath -Setting $setting -Remediate $runRemediation
                $results.Add($result)
                Write-Log $result.Message
            }
        }
    }
}

# Process MACHINE configurations
if ($MachineConfigs.Count -gt 0) {
    $configNum = 0
    foreach ($config in $MachineConfigs) {
        $configNum++
        Write-Log "[MACHINE] Config $configNum of $($MachineConfigs.Count): $($config.Name) - $($config.Description)"
        Write-Log "[PATH] HKLM:\$($config.BasePath)"
        
        $regPath = "HKLM:\$($config.BasePath)"
        
        foreach ($setting in $config.Settings) {
            $result = Test-RegistryCompliance -Path $regPath -Setting $setting -Remediate $runRemediation
            $results.Add($result)
            Write-Log $result.Message
        }
    }
}

#endregion

#region Version Stamp

try {
    $stampName = $LogFileName -replace '^Intune-Registry-Management-?', ''
    if (-not $stampName) { $stampName = $LogFileName }
    $stampPath = "HKLM:\SOFTWARE\Intune-Registry-Management\$stampName"
    if (-not (Test-Path $stampPath)) { New-Item -Path $stampPath -Force | Out-Null }
    Set-ItemProperty -Path $stampPath -Name "ScriptVersion" -Value $ScriptVersion -Type String -Force
    Set-ItemProperty -Path $stampPath -Name "LastRun" -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Type String -Force
    Set-ItemProperty -Path $stampPath -Name "LastRunMode" -Value $ScriptMode -Type String -Force
    Write-Log "[STAMP] Version $ScriptVersion ($ScriptMode) stamped to $stampPath"
}
catch {
    Write-Log "[WARNING] Failed to write version stamp: $($_.Exception.Message)"
}

#endregion

#region Exit Logic

# Check if HKCU was skipped due to no users
$hkcuSkipped = ($UserConfigs.Count -gt 0 -and -not $cachedUserSIDs)

$nonCompliant = @($results | Where-Object { $_.NeedsRemediation -eq $true })
$remediationFailed = @($results | Where-Object { $_.RemediationSuccess -eq $false })
$remediationSucceeded = @($results | Where-Object { $_.RemediationSuccess -eq $true })

# Summary
$totalSettings = $results.Count
$compliantCount = $totalSettings - $nonCompliant.Count
Write-Log "[SUMMARY] Total: $totalSettings | Compliant: $compliantCount | Non-Compliant: $($nonCompliant.Count)"
if ($hkcuSkipped) {
    Write-Log "[WARNING] HKCU settings were skipped (no users logged on)"
}

if ($remediationFailed.Count -gt 0) {
    Write-Log "[REGISTRYMGMT] FAILED - $($remediationFailed.Count) remediation(s) failed"
    exit 1
}

if ($remediationSucceeded.Count -gt 0) {
    Write-Log "[REGISTRYMGMT] SUCCESS - All settings remediated successfully"
    exit 0
}

if ($nonCompliant.Count -gt 0) {
    Write-Log "[REGISTRYMGMT] NON-COMPLIANT - Remediation needed"
    exit 1
}

# If nothing was processed (e.g., only HKCU configs but no users), exit compliant
if ($totalSettings -eq 0 -and $hkcuSkipped) {
    Write-Log "[REGISTRYMGMT] COMPLIANT - No settings to process (HKCU skipped, no HKLM configs)"
    exit 0
}

Write-Log "[REGISTRYMGMT] COMPLIANT - All settings are correct"
exit 0

#endregion
