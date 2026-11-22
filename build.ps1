<#
.SYNOPSIS
    Builds HotspotManager.exe from source with embedded manifest and icon.
#>
$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$csc = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if (-not (Test-Path $csc)) {
    throw "C# Compiler (csc.exe) not found at: $csc"
}

Write-Host "Compiling HotspotManager.exe..." -ForegroundColor Cyan

$params = @(
    "/target:winexe",
    "/optimize+",
    "/win32manifest:$scriptDir\src\app.manifest",
    "/win32icon:$scriptDir\Hotspot.ico",
    "/resource:$scriptDir\HotspotManager.ps1,HotspotManager.ps1",
    "/reference:System.Windows.Forms.dll",
    "/out:$scriptDir\HotspotManager.exe",
    "$scriptDir\src\Program.cs",
    "$scriptDir\src\AssemblyInfo.cs"
)

& $csc $params

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build Successful: $scriptDir\HotspotManager.exe" -ForegroundColor Green
} else {
    Write-Host "Build Failed with exit code $LASTEXITCODE" -ForegroundColor Red
}
