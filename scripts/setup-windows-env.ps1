[CmdletBinding()]
param(
    [string]$ToolsDir = "$env:USERPROFILE\tools\dmboot",
    [string]$ArmVersion = "10.3-2021.10",
    [string]$CMakeVersion = "3.31.3",
    [string]$RenodeVersion = "1.15.3",
    [switch]$SkipArmToolchain,
    [switch]$SkipCMake,
    [switch]$SkipRenode,
    [switch]$SkipProfileSetup,
    [switch]$ForceDownload,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($DryRun) {
        Write-Host "[DRY RUN] mkdir $Path"
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-Archive {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )
    if ((Test-Path -LiteralPath $ArchivePath) -and -not $ForceDownload) {
        Write-Host "Using cached archive: $ArchivePath"
        return
    }
    if ($DryRun) {
        Write-Host "[DRY RUN] download $Url -> $ArchivePath"
        return
    }
    Write-Host "Downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $ArchivePath
}

function Expand-PortableArchive {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$OutputDir
    )
    if (Test-Path -LiteralPath $OutputDir) {
        Write-Host "Already extracted: $OutputDir"
        return
    }
    if ($DryRun) {
        Write-Host "[DRY RUN] expand $ArchivePath -> $OutputDir"
        return
    }
    Expand-Archive -Path $ArchivePath -DestinationPath $ToolsDir -Force
}

if (-not $IsWindows -and -not $DryRun) {
    throw "setup-windows-env.ps1 is intended for native Windows. Use -DryRun outside Windows."
}

Write-Host "Preparing native Windows environment for dmod-boot..."
Write-Host "Tools directory: $ToolsDir"

New-DirectoryIfMissing -Path $ToolsDir

$archivesDir = Join-Path $ToolsDir "_archives"
New-DirectoryIfMissing -Path $archivesDir

$armRoot = Join-Path $ToolsDir "arm-gnu-toolchain-$ArmVersion-win32"
$cmakeRoot = Join-Path $ToolsDir "cmake-$CMakeVersion-windows-x86_64"
$renodeRoot = Join-Path $ToolsDir "renode_${RenodeVersion}_portable"

if (-not $SkipArmToolchain) {
    $armArchive = Join-Path $archivesDir "arm-gnu-toolchain-$ArmVersion-win32.zip"
    $armUrl = "https://developer.arm.com/-/media/Files/downloads/gnu/$ArmVersion/binrel/arm-gnu-toolchain-$ArmVersion-win32.zip"
    Get-Archive -Url $armUrl -ArchivePath $armArchive
    Expand-PortableArchive -ArchivePath $armArchive -OutputDir $armRoot
}

if (-not $SkipCMake) {
    $cmakeArchive = Join-Path $archivesDir "cmake-$CMakeVersion-windows-x86_64.zip"
    $cmakeUrl = "https://github.com/Kitware/CMake/releases/download/v$CMakeVersion/cmake-$CMakeVersion-windows-x86_64.zip"
    Get-Archive -Url $cmakeUrl -ArchivePath $cmakeArchive
    Expand-PortableArchive -ArchivePath $cmakeArchive -OutputDir $cmakeRoot
}

if (-not $SkipRenode) {
    $renodeArchive = Join-Path $archivesDir "renode-$RenodeVersion.windows-portable.zip"
    $renodeUrl = "https://github.com/renode/renode/releases/download/v$RenodeVersion/renode-$RenodeVersion.windows-portable.zip"
    Get-Archive -Url $renodeUrl -ArchivePath $renodeArchive
    Expand-PortableArchive -ArchivePath $renodeArchive -OutputDir $renodeRoot
}

if (-not $DryRun) {
    $armDetected = Get-ChildItem -Path $ToolsDir -Directory -Filter "arm-gnu-toolchain-$ArmVersion*" | Select-Object -First 1
    if ($armDetected) {
        $armRoot = $armDetected.FullName
    }

    $cmakeDetected = Get-ChildItem -Path $ToolsDir -Directory -Filter "cmake-$CMakeVersion-windows*" | Select-Object -First 1
    if ($cmakeDetected) {
        $cmakeRoot = $cmakeDetected.FullName
    }

    $renodeDetected = Get-ChildItem -Path $ToolsDir -Directory -Filter "renode_${RenodeVersion}*" | Select-Object -First 1
    if ($renodeDetected) {
        $renodeRoot = $renodeDetected.FullName
    }
}

$activateScriptPath = Join-Path $ToolsDir "activate-dmboot-tools.ps1"
$activateScript = @"
`$toolPaths = @(
    "$armRoot\bin",
    "$cmakeRoot\bin",
    "$renodeRoot"
)

foreach (`$toolPath in `$toolPaths) {
    if ((Test-Path -LiteralPath `$toolPath) -and (`$env:PATH -notlike "*`$toolPath*")) {
        `$env:PATH = "`$toolPath;`$env:PATH"
    }
}

Write-Host "DMOD Boot tool paths loaded for current PowerShell session."
"@

if ($DryRun) {
    Write-Host "[DRY RUN] write $activateScriptPath"
} else {
    Set-Content -Path $activateScriptPath -Value $activateScript
}

if (-not $SkipProfileSetup) {
    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDir = Split-Path -Parent $profilePath
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        if (-not (Test-Path -LiteralPath $profilePath)) {
            New-Item -ItemType File -Path $profilePath | Out-Null
        }
    }

    $profileSnippet = @"
# DMOD Boot tools (added by setup-windows-env.ps1)
if (Test-Path "$activateScriptPath") {
    . "$activateScriptPath"
}
"@

    if ($DryRun) {
        Write-Host "[DRY RUN] append activation snippet to $profilePath"
    } else {
        $profileContent = ""
        if (Test-Path -LiteralPath $profilePath) {
            $profileContent = Get-Content -Path $profilePath -Raw
            if ($null -eq $profileContent) {
                $profileContent = ""
            }
        }
        if ($profileContent -notlike "*activate-dmboot-tools.ps1*") {
            Add-Content -Path $profilePath -Value "`n$profileSnippet"
        }
    }
}

Write-Host ""
Write-Host "Done."
Write-Host "Run this in current shell to activate tools now:"
Write-Host "  . `"$activateScriptPath`""
