#!/usr/bin/env pwsh
# Script to create stdcall wrapper for HarfBuzz x86

param(
    [string]$LibPath,
    [string]$OutputDir
)

Write-Host "Creating stdcall wrapper for $LibPath"

# Debug: show first few lines of dumpbin output
Write-Host "`nDumpbin symbol sample:"
& dumpbin /SYMBOLS $LibPath | Select-Object -First 30 | ForEach-Object { Write-Host $_ }

# Extract all hb_* public symbols (look for both External and public symbols)
$symbols = & dumpbin /SYMBOLS $LibPath | Select-String "\s_hb_\w+" | ForEach-Object {
    if ($_ -match "\s(_hb_\w+)\s*\|") { $matches[1] }
    elseif ($_ -match "External.*\s(_hb_\w+)") { $matches[1] }
} | Where-Object { $_ } | Sort-Object -Unique

Write-Host "`nFound $($symbols.Count) HarfBuzz symbols to wrap"

if ($symbols.Count -eq 0) {
    Write-Error "No HarfBuzz symbols found in library!"
    Write-Host "Trying alternative pattern..."
    # Try simpler pattern
    $symbols = & dumpbin /SYMBOLS $LibPath | Select-String "hb_" | ForEach-Object {
        if ($_ -match "(\w+hb_\w+)") { 
            Write-Host "Match: $_"
            $matches[1] 
        }
    } | Where-Object { $_ -and $_.StartsWith("_hb_") } | Sort-Object -Unique
    Write-Host "Found $($symbols.Count) symbols with alternative pattern"
}

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
