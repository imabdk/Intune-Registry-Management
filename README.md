# Intune Registry Management

**Version 3.6** | Author: [Martin Bengtsson](https://www.imab.dk)

Blog post: [The only PowerShell script you need to manage registry on Windows devices using Microsoft Intune](https://www.imab.dk/the-only-powershell-script-you-need-to-manage-registry-on-windows-devices-using-microsoft-intune/)

The only PowerShell script you need to manage registry on Windows devices using **Microsoft Intune Remediations**.

## Features

- Runs as **SYSTEM** by design - manages both user and machine registry from one script without CLM issues
- Supports **HKCU** (all user profiles) and **HKLM**
- Works with **Microsoft Entra ID** and traditional AD joined devices
- All registry types: String, DWord, QWord, Binary, ExpandString, MultiString
- Three actions: **Set**, **Delete**, **DeleteKey**
- **Dual logging** - Output to Intune portal and local log file
- **Version stamp** - Writes script version and last-run info to registry for easy monitoring

## Usage

1. Download `Detect-Remediate-Registry-Template.ps1`
2. Modify the configuration section with your registry settings
3. Save two copies:
   - Detection: `$runRemediation = $false`
   - Remediation: `$runRemediation = $true`
4. Upload to **Intune** > **Devices** > **Scripts and remediations** > **Remediations**
5. (Optional) Configure logging - set `$LogFileName` to identify your script in logs

## Configuration examples

### Set user registry values (HKCU)

```powershell
$UserConfigs = @(
    @{
        Name        = "Hide New Outlook Toggle"
        Description = "Hide the Try the new Outlook toggle in classic Outlook"
        BasePath    = "SOFTWARE\Microsoft\Office\16.0\Outlook\Options\General"
        Settings    = @(
            @{
                Name  = "HideNewOutlookToggle"
                Type  = "DWord"
                Value = 1
            }
        )
    }
    @{
        Name        = "OneDrive Known Folders"
        Description = "Silence the Known Folder Move prompt"
        BasePath    = "SOFTWARE\Microsoft\OneDrive"
        Settings    = @(
            @{
                Name  = "SilentAccountConfig"
                Type  = "DWord"
                Value = 1
            }
        )
    }
)
```

### Set machine registry values (HKLM)

```powershell
$MachineConfigs = @(
    @{
        Name        = "Disable Windows Copilot"
        Description = "Turn off Windows Copilot via policy"
        BasePath    = "SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
        Settings    = @(
            @{
                Name  = "TurnOffWindowsCopilot"
                Type  = "DWord"
                Value = 1
            }
        )
    }
    @{
        Name        = "Edge Browser Settings"
        Description = "Configure Edge homepage and startup"
        BasePath    = "SOFTWARE\Policies\Microsoft\Edge"
        Settings    = @(
            @{
                Name  = "HomepageLocation"
                Type  = "String"
                Value = "https://intranet.company.com"
            }
            @{
                Name  = "RestoreOnStartup"
                Type  = "DWord"
                Value = 4
            }
        )
    }
)
```

### Delete registry values

```powershell
$UserConfigs = @(
    @{
        Name        = "Remove Teams Classic"
        Description = "Delete leftover Teams Machine-Wide Installer entries"
        BasePath    = "SOFTWARE\Microsoft\Office\Teams"
        Settings    = @(
            @{
                Action = "Delete"
                Name   = "PreventInstallationFromMsi"
            }
        )
    }
)
```

### Delete entire registry keys

```powershell
$MachineConfigs = @(
    @{
        Name        = "Remove Legacy App"
        Description = "Clean up registry from uninstalled application"
        BasePath    = "SOFTWARE"
        Settings    = @(
            @{
                Action = "DeleteKey"
                Name   = "OldVendor"
            }
        )
    }
)
```

## 32-bit applications

For apps that store settings in the 32-bit registry view (e.g., 32-bit Office), create a separate Intune Remediation and uncheck **"Run this script in 64-bit PowerShell"** in the remediation properties. Windows automatically redirects `SOFTWARE\` to `SOFTWARE\WOW6432Node\` - no path changes needed in the script. Keep 32-bit and 64-bit settings in separate scripts.

## Version History

| Version | Changes |
|---------|---------|
| 3.6 | Fixed `-ErrorAction Stop` not propagating into `Set-RegistryValue`. General code cleanup. |
| 3.5 | Version stamp written to registry. Performance fix for large config sets. |
| 3.4 | Fixed binary comparison being case-sensitive. Log rotation now keeps 3 dated backups. Logging errors show a warning instead of failing silently. |
| 3.3 | Added local log file for complete audit trail. Dual output to Intune portal and log file. |
| 3.2 | Removed broken HKCU fallback. Script now skips HKCU when no users are logged on. |
| 3.1 | Added Set, Delete, and DeleteKey actions. Clean multi-line formatting. |

## Logging

Script output is written to both:
- **Intune portal** - Visible in remediation output
- **Local log file** - `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<LogFileName>.log`

### Configuration

```powershell
$LogFileName = "Intune-Registry-Management-MyScript"  # Name your log file
```

### Log format

```
2026-02-01 14:30:00 [REMEDIATE] [START] Registry Management - REMEDIATION
2026-02-01 14:30:00 [REMEDIATE] [COMPLIANT] BlogURL (String)
2026-02-01 14:30:00 [REMEDIATE] [REMEDIATED] Author (String)
2026-02-01 14:30:00 [REMEDIATE] [REGISTRYMGMT] SUCCESS - All settings remediated successfully
```
