param(
    [string]$OutputDir = "output",
    [string]$CliVersion = "auto",
    [string]$PatchesVersion = "auto",
    [string]$TwitterVersion = "latest",
    [switch]$Help = $false
)

# --- Configuration & Helpers ---
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host "$Message"
}

function Show-Help {
    Write-Host @"
Usage: run.ps1 [options]
Options:
  -OutputDir DIR          Specify output directory (default: output)
  -CliVersion VER         Specify Morphe CLI version (default: auto)
  -PatchesVersion VER     Specify Piko Patches version (default: auto)
  -TwitterVersion VER     Specify Twitter version (default: latest)
  -Help                   Show this help message
"@
    exit 0
}

if ($Help) { Show-Help }

# Log initial configuration
Write-Log "==============================================="
Write-Log "Starting Twitter Piko Patcher"
Write-Log "==============================================="
Write-Log "Output Directory: $OutputDir"
Write-Log "Morphe CLI Version: $CliVersion"
Write-Log "Piko Patches Version: $PatchesVersion"
Write-Log "Twitter Version: $TwitterVersion"
Write-Log "==============================================="
Write-Log ""

# --- Phase 1: Preparation ---
Write-Log "Checking dependencies..."
$RequiredTools = @("tools\apkmd.exe", "tools\APKEditor.jar")
foreach ($Tool in $RequiredTools) {
    if (-not (Test-Path $Tool)) {
        Write-Error "Required tool missing: $Tool"
        exit 1
    }
}

# Resolve versions
if ($CliVersion -eq "auto") {
    try {
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/MorpheApp/morphe-cli/releases"
        $CliVersion = ($releases | Where-Object { $_.prerelease } | Select-Object -First 1).tag_name.TrimStart('v')
        Write-Log "Detected Morphe CLI: $CliVersion"
    } catch {
        $CliVersion = "1.4.0-dev.5"
    }
}

# --- Phase 2: APK Acquisition ---
function Get-VersionInfo {
    param($Filename)
    if ($Filename -match 'com\.twitter\.android_([\d.]+)') {
        return $matches[1]
    }
    return $null
}

$twitterApk = $null
if ($TwitterVersion -eq "latest") {
    try {
        $result = & .\tools\apkmd.exe versions x-corp twitter --exclude-beta
        if ($LASTEXITCODE -eq 0) {
            $TwitterVersion = ($result -split '[\r\n]+' | Where-Object { $_ -match '^\d+\.\s' } | Select-Object -First 1) -replace '^\d+\.\s*[A-Za-z]*\s*', ''
            Write-Log "Latest detected version: $TwitterVersion"
        }
    } catch { Write-Log "Could not fetch latest version from apkmd, checking local cache..." }
}

$localApks = Get-ChildItem -Path "downloads\com.twitter.android_$TwitterVersion*"
if ($localApks.Count -gt 0) {
    $twitterApk = $localApks | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Log "Found existing APK: $($twitterApk.Name)"
} else {
    Write-Log "Downloading Twitter APK version $TwitterVersion..."
    & .\tools\apkmd.exe download x-corp twitter --version $TwitterVersion --type bundle --dpi * --outdir downloads
    $twitterApk = Get-ChildItem -Path "downloads\com.twitter.android_$TwitterVersion*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($twitterApk) { Write-Log "Downloaded APK: $($twitterApk.Name)" }
}

if (-not $twitterApk) { Write-Error "Failed to locate/download APK"; exit 1 }
$actualVersion = Get-VersionInfo $twitterApk.Name

# --- Phase 3: Merge ---
$mergedApk = "merged\com.twitter.android_$actualVersion.apk"
if (-not (Test-Path $mergedApk)) {
    Write-Log "Merging APK..."
    Remove-Item -Path "APKEditor\*" -Recurse -Force -ErrorAction SilentlyContinue
    & java -jar tools\APKEditor.jar m -i "$($twitterApk.FullName)" -o $mergedApk
    if ($LASTEXITCODE -ne 0) { Write-Error "APKEditor failed"; exit $LASTEXITCODE }
}

# --- Phase 4: Patching ---
if ($PatchesVersion -eq "auto") {
    try {
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/crimera/piko/releases"
        $PatchesVersion = ($releases | Where-Object { $_.prerelease } | Select-Object -First 1).tag_name.TrimStart('v')
        Write-Log "Detected Piko Patches: $PatchesVersion"
    } catch { $PatchesVersion = "3.0.0-dev.1" }
}

$patchesFile = "patches-$PatchesVersion.mpp"
if (-not (Test-Path $patchesFile)) {
    Invoke-WebRequest -Uri "https://github.com/crimera/piko/releases/download/v$PatchesVersion/$patchesFile" -OutFile $patchesFile
}

$cliFile = "morphe-cli-$CliVersion-all.jar"
if (-not (Test-Path $cliFile)) {
    Invoke-WebRequest -Uri "https://github.com/MorpheApp/morphe-cli/releases/download/v$CliVersion/$cliFile" -OutFile $cliFile
}

$outputFile = "$OutputDir\twitter-piko_v$actualVersion-patches_v$PatchesVersion.apk"
$keystoreArg = if (Test-Path "twitter-piko.keystore") { "--keystore=twitter-piko.keystore" } else { "" }

# Log resolved versions summary
Write-Log ""
Write-Log "----------- Configuration Summary -----------"
Write-Log "Morphe CLI: $CliVersion"
Write-Log "Piko Patches: $PatchesVersion"
Write-Log "Twitter APK: $actualVersion"
Write-Log "Output: $outputFile"
Write-Log "---------------------------------------------"
Write-Log ""

Write-Log "Applying patches..."
# Added --continue-on-error to allow build completion if individual patches fail
& java -jar $cliFile patch $mergedApk -p $patchesFile -o $outputFile $keystoreArg --continue-on-error
if ($LASTEXITCODE -ne 0) { Write-Error "Patching failed"; exit $LASTEXITCODE }

Write-Log "Process completed successfully: $outputFile"

# --- Phase 5: Cleanup ---
Write-Log "Cleaning up..."
Remove-Item -Path "downloads\tmp_*", "APKEditor\*", "$OutputDir\*tmp*", "$OutputDir\*morphe*" -Recurse -Force -ErrorAction SilentlyContinue
exit 0
