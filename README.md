# Piko Twitter Patcher

## Prerequisites

1. **PowerShell** - Required (comes with Windows 10/11)
2. Download `apkmd.exe` from https://github.com/hyzor/apkmirror-downloader/releases
3. Download `APKEditor.jar` from https://github.com/REAndroid/APKEditor/releases

Put `apkmd.exe` and `APKEditor.jar` in the `tools` folder.

## How to use

### PowerShell Script (Recommended)

Run the PowerShell script which handles both preparation and patching in one go:

```powershell
# Basic usage
.\run.ps1

# Custom output directory
.\run.ps1 -OutputDir custom_output

# Specify specific versions
.\run.ps1 -PatchesVersion 2.0.0-dev.21
.\run.ps1 -TwitterVersion 11.59.0
.\run.ps1 -CliVersion 5.0.2-dev.3

# Get help
.\run.ps1 -Help
```

### Options

**Note**: PowerShell uses `-` prefix for parameters, not `--`

- `-OutputDir DIR` - Specify output directory (default: `output`)
- `-CliVersion VER` - Specify Morphe CLI version (default: `1.4.0-dev.5`)
- `-PatchesVersion VER` - Specify Piko Patches version (default: `auto` - fetches latest from GitHub)
- `-TwitterVersion VER` - Specify Twitter version (default: `latest`)
- `-Help` - Show help message

## Features

✅ **Automatic version detection** - Fetches latest Piko patches pre-release  
✅ **Smart APK selection** - Uses most recent Twitter APK when `latest` is specified  
✅ **Automatic cleanup** - Removes temporary files and directories  
✅ **Version management** - Downloads correct versions and cleans up old ones  
✅ **Error handling** - Clear error messages and proper exit codes  
✅ **Flexible configuration** - Customizable via command-line parameters  

## File Structure

```
twitter/
├── tools/                    # Required tools
│   ├── apkmd.exe           # APK downloader
│   └── APKEditor.jar       # APK merger
├── downloads/               # Downloaded APKs
├── merged/                  # Processed APKs  
├── output/                  # Patched APKs (output folder)
├── run.ps1                 # Main PowerShell script
└── README.md               # This file
```

## What it does

1. **Preparation Phase**
   - Checks for required tools
   - Downloads Twitter APK (latest or specified version)
   - Runs APKEditor to merge split APKs
   - Extracts actual version from filename

2. **Patching Phase**  
   - Downloads required tools if missing
   - Fetches latest Piko patches (if auto)
   - Downloads correct patches version
   - Runs Morphe CLI to patch the APK

3. **Cleanup Phase**
   - Removes temporary directories from all tools
   - Cleans up old patch files
   - Maintains clean working environment

## Output

The patched APK will be in the `output` folder with the naming format:
`twitter-piko_v{version}-patches_v{patches_version}.apk`

Example: `output/twitter-piko_v11.59.0-patches_v2.0.0-dev.22.apk`

## Troubleshooting

- **PowerShell execution policy**: If blocked, run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- **Missing tools**: Ensure `tools\apkmd.exe` and `tools\APKEditor.jar` exist
- **APKEditor errors**: Script automatically cleans up temp directories that may cause conflicts
- **Version conflicts**: Script always picks the newest Twitter APK when using `latest`