#!/usr/bin/env pwsh
# Script to create stdcall wrapper for HarfBuzz x86

param(
    [string]$LibPath,
    [string]$OutputDir
)

Write-Host "Creating stdcall wrapper for $LibPath"

# For LTCG libs, symbols aren't readable via /SYMBOLS
# Map of function names to their stdcall parameter sizes (in bytes)
# Extracted from Native AOT link errors showing required stdcall decorations
Write-Host "Using predefined HarfBuzz function list for x86 Native AOT"

$functionSizes = @{
    "_hb_blob_create" = 20
    "_hb_blob_destroy" = 4
    "_hb_buffer_add_utf16" = 20
    "_hb_buffer_create" = 0
    "_hb_buffer_destroy" = 4
    "_hb_buffer_get_content_type" = 4
    "_hb_buffer_get_direction" = 4
    "_hb_buffer_get_glyph_infos" = 8
    "_hb_buffer_get_glyph_positions" = 8
    "_hb_buffer_get_length" = 4
    "_hb_buffer_guess_segment_properties" = 4
    "_hb_buffer_reset" = 4
    "_hb_buffer_reverse" = 4
    "_hb_buffer_set_direction" = 8
    "_hb_buffer_set_language" = 8
    "_hb_face_create_for_tables" = 12
    "_hb_face_destroy" = 4
    "_hb_face_get_upem" = 4
    "_hb_face_set_upem" = 8
    "_hb_feature_to_string" = 16
    "_hb_font_create" = 4
    "_hb_font_destroy" = 4
    "_hb_font_get_glyph" = 16
    "_hb_font_get_glyph_extents" = 12
    "_hb_font_get_glyph_h_advance" = 8
    "_hb_font_get_glyph_h_advances" = 20
    "_hb_font_get_scale" = 12
    "_hb_language_from_string" = 8
    "_hb_language_to_string" = 4
    "_hb_ot_font_set_funcs" = 4
    "_hb_ot_metrics_get_position" = 12
    "_hb_shape_full" = 20
    "_hb_unicode_funcs_destroy" = 4
}

Write-Host "Will wrap $($functionSizes.Count) HarfBuzz functions"

# Generate wrapper assembly file
$asmContent = "; Auto-generated stdcall wrappers for HarfBuzz x86`n"
$asmContent += ".586`n.model flat`n"
$asmContent += "OPTION DOTNAME`n"  # Prevent name decoration
$asmContent += "ASSUME fs:nothing`n`n"

# First declare all external cdecl functions
foreach ($sym in $functionSizes.Keys) {
    $asmContent += "EXTERN C ${sym}:PROC`n"
}

$asmContent += "`n.code`n`n"

# Then create stdcall wrappers with proper parameter counts
foreach ($entry in $functionSizes.GetEnumerator()) {
    $sym = $entry.Key
    $sizeBytes = $entry.Value
    $funcName = $sym.Substring(1)  # Remove leading underscore: _hb_xxx -> hb_xxx
    $numParams = $sizeBytes / 4  # Each DWORD = 4 bytes on x86
    
    # Build parameter list for PROTO (:DWORD for each parameter)
    $protoParams = if ($numParams -gt 0) {
        (1..$numParams | ForEach-Object { ":DWORD" }) -join ", "
    } else {
        ""
    }
    
    # Build parameter list for PROC (needs names: p1:DWORD, p2:DWORD, etc.)
    $procParams = if ($numParams -gt 0) {
        (1..$numParams | ForEach-Object { "p${_}:DWORD" }) -join ", "
    } else {
        ""
    }
    
    # Declare the function prototype so MASM knows how to decorate it
    if ($protoParams) {
        $asmContent += "${funcName} PROTO STDCALL $protoParams`n"
    } else {
        $asmContent += "${funcName} PROTO STDCALL`n"
    }
    
    # Create the wrapper procedure
    if ($procParams) {
        $asmContent += "${funcName} PROC STDCALL $procParams`n"
    } else {
        $asmContent += "${funcName} PROC STDCALL`n"
    }
    $asmContent += "    jmp $sym`n"
    $asmContent += "${funcName} ENDP`n"
    
    # Register as safe for SEH
    $asmContent += ".safeseh $funcName`n`n"
}

$asmContent += "END`n"

$asmPath = Join-Path $OutputDir "hb_stdcall_wrapper.asm"
Set-Content -Path $asmPath -Value $asmContent -Encoding ASCII

Write-Host "`nGenerated ASM file (first 20 lines):"
Get-Content $asmPath | Select-Object -First 20 | ForEach-Object { Write-Host $_ }

# Assemble with ML
$mlPath = "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\14.44.35207\bin\HostX86\x86\ml.exe"
$objPath = Join-Path $OutputDir "hb_stdcall_wrapper.obj"

Write-Host "`nAssembling wrapper..."
$mlOutput = & $mlPath /c /coff /safeseh "/Fo$objPath" $asmPath 2>&1
$mlOutput | ForEach-Object { Write-Host $_ }

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nFull ASM content:"
    Get-Content $asmPath | ForEach-Object { Write-Host $_ }
    Write-Error "Assembly failed with exit code $LASTEXITCODE"
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

# Return the path to the combined library (this will be captured by caller)
$wrapperLibPath
