#!/usr/bin/env pwsh
# Script to create stdcall wrapper for HarfBuzz x86

param(
    [string]$LibPath,
    [string]$OutputDir
)

Write-Host "Creating stdcall wrapper for $LibPath"

# Extract all hb_* public symbols
$symbols = & dumpbin /SYMBOLS $LibPath | Select-String "External.*\s_hb_\w+" | ForEach-Object {
    if ($_ -match "External.*\s(_hb_\w+)") { $matches[1] }
} | Sort-Object -Unique

Write-Host "Found $($symbols.Count) HarfBuzz symbols to wrap"

# Generate wrapper assembly file (simpler than C with jmp)
$asmContent = "; Auto-generated stdcall wrappers for HarfBuzz x86`n"
$asmContent += ".586`n.model flat, stdcall`n.code`n`n"

foreach ($sym in $symbols) {
    $funcName = $sym.Substring(1)  # Remove underscore
    $asmContent += "PUBLIC $funcName`n"
    $asmContent += "EXTRN ${funcName}:PROC`n"
    $asmContent += "$funcName PROC`n"
    $asmContent += "    jmp ${funcName}_cdecl`n"
    $asmContent += "$funcName ENDP`n`n"
}

$asmContent += "END`n"

$asmPath = Join-Path $OutputDir "hb_stdcall_wrapper.asm"
Set-Content -Path $asmPath -Value $asmContent -Encoding ASCII

# Assemble with ML
$mlPath = "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\14.44.35207\bin\HostX86\x86\ml.exe"
$objPath = Join-Path $OutputDir "hb_stdcall_wrapper.obj"

Write-Host "Assembling wrapper..."
& $mlPath /c /coff "/Fo$objPath" $asmPath

if ($LASTEXITCODE -ne 0) {
    Write-Error "Assembly failed"
    exit 1
}

# Combine with original lib
$libTool = "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\14.44.35207\bin\HostX86\x86\lib.exe"
$wrapperLibPath = Join-Path $OutputDir "libHarfBuzzSharp_stdcall.lib"

Write-Host "Creating combined library..."
& $libTool "/OUT:$wrapperLibPath" $objPath $LibPath

if ($LASTEXITCODE -ne 0) {
    Write-Error "Lib creation failed"
    exit 1
}

Write-Host "Stdcall wrapper created: $wrapperLibPath"
return $wrapperLibPath
