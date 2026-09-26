$ErrorActionPreference = "Stop"

$InitialLocation = Get-Location

$OptimizationFlag = "/O2"
$TargetArch = "x64"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

$OutputLibraryName = "openssl_bridge"
$VendorLibraryName = "libcrypto-3-x64"
$LibraryExtension = "dll"

$SrcDir = Join-Path $ProjectRoot "external"
$PrebuiltDir = Join-Path $ProjectRoot "prebuilt"

$TargetOs = "windows"

function Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Clean {
    Step "Cleaning external directory via git..."
    & git -C "$SrcDir" checkout -q HEAD -- . 2>$null
    & git -C "$SrcDir" clean -fdq . 2>$null
}

Step "Build options"
Write-Host "PROJECT_ROOT: $ProjectRoot"
Write-Host ""
Write-Host "SRC_DIR: $SrcDir"
Write-Host "PREBUILT_DIR: $PrebuiltDir"
Write-Host ""
Write-Host "OUTPUT_LIBRARY_NAME: $OutputLibraryName"
Write-Host "VENDOR_LIBRARY_NAME: $VendorLibraryName"
Write-Host "LIBRARY_EXTENSION: $LibraryExtension"
Write-Host ""
Write-Host "TARGET_OS: $TargetOs"
Write-Host "TARGET_ARCH: $TargetArch"
Write-Host ""
Write-Host "OPTIMIZATION_FLAG: $OptimizationFlag"

try {
    Step "Changing directory to $SrcDir..."
    Set-Location $SrcDir

    $Makefile = Join-Path $SrcDir "Makefile"
    if (Test-Path $Makefile) {
        Step "Cleaning previous build..."
        & nmake.exe clean *>&1
    }

    $env:CFLAGS = $OptimizationFlag

    Step "Configuring OpenSSL with Perl..."
    perl Configure VC-WIN64A shared no-tests no-apps
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Configuration failed with exit code $LASTEXITCODE."
        exit 1
    }

    Step "Building $OutputLibraryName..."
    nmake.exe
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed: nmake exited with code $LASTEXITCODE."
        exit 1
    }

    $CompiledDll = Join-Path $SrcDir "$VendorLibraryName.$LibraryExtension"
    if (-not (Test-Path $CompiledDll)) {
        Write-Error "Build failed: $VendorLibraryName.$LibraryExtension not found in $SrcDir."
        exit 1
    }

    $CompiledLib = Join-Path $SrcDir "libcrypto.lib"
    if (-not (Test-Path $CompiledLib)) {
        Write-Error "Build failed: $CompiledLib not found."
        exit 1
    }

    $OutDir = Join-Path $PrebuiltDir "$TargetOs\$TargetArch"
    $OutDll = Join-Path $OutDir "$OutputLibraryName.$LibraryExtension"
    $OutLib = Join-Path $OutDir "$OutputLibraryName.lib"

    Step "Creating output directory..."
    if (Test-Path $OutDir) {
        Remove-Item -Recurse -Force $OutDir
    }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    Step "Copying files to output directory..."
    Copy-Item -Force $CompiledDll $OutDll
    Copy-Item -Force $CompiledLib $OutLib
    $OutInclude = Join-Path $OutDir "include"
    New-Item -ItemType Directory -Force -Path $OutInclude | Out-Null
    Copy-Item -Recurse -Force (Join-Path $SrcDir "include\openssl") $OutInclude

    Step "Verifying output files..."
    if (-not (Test-Path $OutDll)) {
        Write-Error "Output DLL was not created: $OutDll"
        exit 1
    }
    if (-not (Test-Path $OutLib)) {
        Write-Error "Output LIB was not created: $OutLib"
        exit 1
    }
    $OutOpenSSLHeader = Join-Path $OutDir "include\openssl\opensslv.h"
    if (-not (Test-Path $OutOpenSSLHeader)) {
        Write-Error "Library headers were not copied: $OutDir\include\openssl"
        exit 1
    }

    Step "$OutputLibraryName build completed."
    
    Write-Host "Output: $OutDir"
} finally {
    Set-Location $InitialLocation
    Clean
}
