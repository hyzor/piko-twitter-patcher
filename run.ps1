param(
    [string]$OutputDir = "output",
    [string]$CliVersion = "5.0.2-dev.2", 
    [string]$PatchesVersion = "auto",
    [string]$TwitterVersion = "latest",
    [switch]$Help = $false
)

# Show help
if ($Help) {
    Write-Host "Usage: run.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -OutputDir DIR          Specify output directory (default: output)"
    Write-Host "  -CliVersion VER         Specify ReVanced CLI version (default: 5.0.2-dev.2)"  
    Write-Host "  -PatchesVersion VER     Specify Piko Patches version (default: auto - fetches latest from GitHub)"
    Write-Host "  -TwitterVersion VER     Specify Twitter version (default: latest)"
    Write-Host "  -Help                   Show this help message"
    Write-Host ""
    Write-Host "Example:"
    Write-Host "  .\run.ps1"
    Write-Host "  .\run.ps1 -OutputDir custom_output"
    Write-Host ""
    exit 0
}

# Default values (PowerShell parameters override these)
$revancedCli = $CliVersion
$pikoPatches = $PatchesVersion
$outputDir = $OutputDir
$twitterVersion = $TwitterVersion

Write-Host "=== PREPARE PHASE ==="
Write-Host "Checking required tools..."

# Check if required tools exist
if (-not (Test-Path "tools\apkmd.exe")) {
    Write-Host "apkmd.exe not found. Please download it from https://github.com/tanishqmanuja/apkmirror-downloader/releases"
    exit 1
}

if (-not (Test-Path "tools\APKEditor.jar")) {
    Write-Host "APKEditor.jar not found. Please download it from https://github.com/REAndroid/APKEditor/releases"
    exit 1
}

Write-Host "Tools found successfully."

# Find Twitter APK
$twitterApk = $null
$actualVersion = $null

function Extract-VersionFromFilename($filename) {
    # Extract version from filename like com.twitter.android_11.59.0-release.0-311590000_4arch_7dpi_23lang_ca6da10a407ab1707768fc1b80fa2b26_apkmirror.com.apkm
    $parts = $filename.Split('_')
    if ($parts.Length -ge 2) {
        $fullVersion = $parts[1]
        # Extract base version (e.g., "11.59.0" from "11.59.0-release.0-311590000")
        $baseVersion = ($fullVersion -split '-')[0]
        return @{
            Full = $fullVersion
            Base = $baseVersion
        }
    }
    return $null
}

if ($twitterVersion -eq "latest") {
    Write-Host "Looking for any Twitter APK in downloads directory..."
    $apkFiles = Get-ChildItem -Path "downloads\com.twitter.android_*" -ErrorAction SilentlyContinue
    
    if ($apkFiles.Count -gt 0) {
        Write-Host "Found $($apkFiles.Count) APK files:"
        foreach ($apk in $apkFiles) {
            $versionInfo = Extract-VersionFromFilename $apk.Name
            Write-Host "  - $($apk.Name) (Version: $($versionInfo.Base), Modified: $($apk.LastWriteTime))"
        }
        
        # Sort by modification time to get latest APK
        $latestApk = $apkFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $twitterApk = $latestApk.Name
        $versionInfo = Extract-VersionFromFilename $twitterApk
        $actualVersion = $versionInfo.Base
        Write-Host "Selected latest APK: $twitterApk (Last modified: $($latestApk.LastWriteTime))"
        Write-Host "Extracted version: $actualVersion"
    }
} else {
    Write-Host "Looking for Twitter APK with version $twitterVersion..."
    $apkFiles = Get-ChildItem -Path "downloads\com.twitter.android_$twitterVersion*" -ErrorAction SilentlyContinue
    
    if ($apkFiles.Count -gt 0) {
        $twitterApk = $apkFiles[0].Name
        $versionInfo = Extract-VersionFromFilename $twitterApk
        $actualVersion = $versionInfo.Base
        Write-Host "Found existing APK: $twitterApk"
        Write-Host "Extracted version: $actualVersion"
    }
}

# Download Twitter APK if not found
if (-not $twitterApk) {
    Write-Host "Running apkmd.exe for version $twitterVersion..."
    $apkmdResult = & .\tools\apkmd.exe download x-corp twitter --version $twitterVersion --type bundle --dpi * --outdir downloads
    if ($LASTEXITCODE -ne 0) {
        Write-Host "apkmd.exe failed with error code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    Write-Host "apkmd.exe completed successfully."
    
    # Find downloaded APK (should be the latest downloaded)
    if ($twitterVersion -eq "latest") {
        $apkFiles = Get-ChildItem -Path "downloads\com.twitter.android_*" -ErrorAction SilentlyContinue
        if ($apkFiles.Count -gt 0) {
            $latestApk = $apkFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $twitterApk = $latestApk.Name
            $versionInfo = Extract-VersionFromFilename $twitterApk
            $actualVersion = $versionInfo.Base
            Write-Host "Found downloaded APK: $twitterApk (Last modified: $($latestApk.LastWriteTime))"
            Write-Host "Extracted version: $actualVersion"
        }
    } else {
        $apkFiles = Get-ChildItem -Path "downloads\com.twitter.android_$twitterVersion*" -ErrorAction SilentlyContinue
        if ($apkFiles.Count -gt 0) {
            $twitterApk = $apkFiles[0].Name
            $versionInfo = Extract-VersionFromFilename $twitterApk
            $actualVersion = $versionInfo.Base
            Write-Host "Found downloaded APK: $twitterApk"
            Write-Host "Extracted version: $actualVersion"
        }
    }
}

if (-not $twitterApk) {
    Write-Host "Error: Could not find or download Twitter APK"
    exit 1
}

if ($actualVersion) {
    Write-Host "Actual Twitter version detected: $actualVersion"
} else {
    $actualVersion = $twitterVersion
}

# Run APKEditor if needed
$mergedApk = "merged\com.twitter.android_$actualVersion.apk"
if (-not (Test-Path $mergedApk)) {
    Write-Host "Running APKEditor..."
    Write-Host "Input file: downloads\$twitterApk"
    Write-Host "Output file: $mergedApk"
    
    # Clean up APKEditor temp files first (they can interfere with new runs)
    $apkEditorTempDirs = @(
        "APKEditor\APKEditor",
        "APKEditor\decode.apk",
        "APKEditor\out.apk"
    )
    
    foreach ($tempDir in $apkEditorTempDirs) {
        if (Test-Path $tempDir) {
            try {
                Write-Host "Removing APKEditor temporary directory: $tempDir"
                Remove-Item -Path $tempDir -Recurse -Force
            } catch {
                Write-Host "Warning: Could not remove $tempDir - $($_.Exception.Message)"
            }
        }
    }
    
    $apkEditorResult = & java -jar tools\APKEditor.jar m -i "downloads\$twitterApk" -o $mergedApk
    if ($LASTEXITCODE -ne 0) {
        Write-Host "APKEditor failed with error code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    Write-Host "APKEditor completed successfully."
} else {
    Write-Host "Twitter APK already run through APKEditor."
}

Write-Host "=== PREPARE PHASE COMPLETED ==="

# === RUN PHASE ===
Write-Host ""
Write-Host "=== RUN PHASE ==="
Write-Host "Configuration:"
Write-Host "- Twitter Version: $twitterVersion"
Write-Host "- Output Directory: $outputDir"
Write-Host "- ReVanced CLI Version: $revancedCli"
Write-Host "- Piko Patches Version: $pikoPatches"

# Create output directory if needed
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Find merged APK
$mergedFiles = Get-ChildItem -Path "merged\com.twitter.android_$actualVersion*" -ErrorAction SilentlyContinue
if ($mergedFiles.Count -eq 0) {
    Write-Host "Error: Twitter APK not found in merged directory"
    exit 1
}

$finalApk = $mergedFiles[0].Name
Write-Host "Twitter APK: $finalApk"

# Download tools if needed
$cliFile = "revanced-cli-$revancedCli-all.jar"
if (-not (Test-Path $cliFile)) {
    Write-Host "Downloading ReVanced CLI..."
    Invoke-WebRequest -Uri "https://github.com/ReVanced/revanced-cli/releases/download/v$revancedCli/$cliFile" -OutFile $cliFile
}

# Fetch latest Piko patches if auto
if ($pikoPatches -eq "auto") {
    Write-Host "Fetching latest Piko patches pre-release version from GitHub..."
    try {
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/crimera/piko/releases" -ErrorAction Stop
        $latestPreRelease = $releases | Where-Object { $_.prerelease -eq $true } | Select-Object -First 1
        $pikoPatches = $latestPreRelease.tag_name.TrimStart('v')
        Write-Host "Latest Piko patches pre-release version detected: $pikoPatches"
    } catch {
        Write-Host "Failed to fetch latest version, using fallback"
        $pikoPatches = "2.0.0-dev.22"
    }
}

$patchesFile = "patches-$pikoPatches.rvp"
if (-not (Test-Path $patchesFile)) {
    Write-Host "Downloading Piko Patches v$pikoPatches..."
    try {
        Invoke-WebRequest -Uri "https://github.com/crimera/piko/releases/download/v$pikoPatches/$patchesFile" -OutFile $patchesFile
        Write-Host "Successfully downloaded $patchesFile"
        
        # Clean up old patch files
        Get-ChildItem -Path "patches-*.rvp" | Where-Object { $_.Name -ne $patchesFile } | ForEach-Object {
            Write-Host "Removing old patch file: $($_.Name)"
            Remove-Item $_.FullName
        }
    } catch {
        Write-Host "Failed to download $patchesFile"
        exit 1
    }
} else {
    Write-Host "Piko Patches v$pikoPatches already exists"
}

# Run ReVanced CLI
Write-Host "Running ReVanced CLI..."
$outputFile = "$outputDir\twitter-piko_v$actualVersion-patches_v$pikoPatches.apk"

# Check if keystore exists
$keystoreFile = "twitter-piko.keystore"
if (-not (Test-Path $keystoreFile)) {
    Write-Host "Warning: Keystore file $keystoreFile not found. Running without keystore..."
    $revancedResult = & java -jar $cliFile patch "merged\$finalApk" -p $patchesFile -o $outputFile
} else {
    Write-Host "Using keystore: $keystoreFile"
    $revancedResult = & java -jar $cliFile patch "merged\$finalApk" -p $patchesFile -o $outputFile --keystore=$keystoreFile
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "ReVanced CLI failed with error code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "=== PROCESS COMPLETED SUCCESSFULLY ==="
Write-Host "Output file: $outputFile"

# Cleanup phase
Write-Host ""
Write-Host "=== CLEANUP PHASE ==="
Write-Host "Cleaning up temporary files..."

# Clean up temporary directories from apkmd
$tempDirs = Get-ChildItem -Path "downloads\tmp_*" -Directory -ErrorAction SilentlyContinue
foreach ($dir in $tempDirs) {
    Write-Host "Removing temporary directory: $($dir.Name)"
    Remove-Item -Path $dir.FullName -Recurse -Force
}

# Clean up APKEditor temp directories
$apkEditorTempDirs = @(
    "APKEditor\APKEditor",
    "APKEditor\decode.apk", 
    "APKEditor\out.apk"
)

foreach ($tempDir in $apkEditorTempDirs) {
    if (Test-Path $tempDir) {
        try {
            Write-Host "Removing APKEditor temporary directory: $tempDir"
            Remove-Item -Path $tempDir -Recurse -Force
        } catch {
            Write-Host "Warning: Could not remove $tempDir - $($_.Exception.Message)"
        }
    }
}

# Clean up output folder temp files
if (Test-Path $outputDir) {
    $outputTempFiles = Get-ChildItem -Path $outputDir -Filter "*tmp*" -ErrorAction SilentlyContinue
    foreach ($tempFile in $outputTempFiles) {
        Write-Host "Removing output temp file: $($tempFile.Name)"
        Remove-Item -Path $tempFile.FullName -Force
    }
    
    # Also clean up any directories that look like temp directories
    $outputTempDirs = Get-ChildItem -Path $outputDir -Directory -Filter "*tmp*" -ErrorAction SilentlyContinue
    foreach ($tempDir in $outputTempDirs) {
        Write-Host "Removing output temp directory: $($tempDir.Name)"
        Remove-Item -Path $tempDir.FullName -Recurse -Force
    }
    
    # Clean up ReVanced CLI temp directories (they often create temp folders in output)
    $revancedTempDirs = Get-ChildItem -Path $outputDir -Directory -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -match "revanced|temp|tmp|cache" 
    }
    foreach ($tempDir in $revancedTempDirs) {
        Write-Host "Removing ReVanced temp directory: $($tempDir.Name)"
        Remove-Item -Path $tempDir.FullName -Recurse -Force
    }
}

# Clean up any failed patch files
if (Test-Path "patches-auto.rvp") {
    Remove-Item "patches-auto.rvp" -Force
}

Write-Host "Cleanup completed."
exit 0