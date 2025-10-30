#!/usr/bin/env pwsh
# Script to create stdcall wrapper for HarfBuzz x86

param(
    [string]$LibPath,
    [string]$OutputDir
)

Write-Host "Creating stdcall wrapper for $LibPath"

# For LTCG libs, symbols aren't readable via /SYMBOLS
# Instead, list all hb_* functions we need based on error list from Native AOT
Write-Host "Using predefined HarfBuzz function list for x86 Native AOT"

$symbols = @(
    "_hb_blob_create",
    "_hb_blob_destroy",
    "_hb_buffer_add_utf16",
    "_hb_buffer_create",
    "_hb_buffer_destroy",
    "_hb_buffer_get_content_type",
    "_hb_buffer_get_direction",
    "_hb_buffer_get_glyph_infos",
    "_hb_buffer_get_glyph_positions",
    "_hb_buffer_get_length",
    "_hb_buffer_guess_segment_properties",
    "_hb_buffer_reset",
    "_hb_buffer_reverse",
    "_hb_buffer_set_direction",
    "_hb_buffer_set_language",
    "_hb_face_create_for_tables",
    "_hb_face_destroy",
    "_hb_face_get_upem",
    "_hb_face_set_upem",
    "_hb_feature_to_string",
    "_hb_font_create",
    "_hb_font_destroy",
    "_hb_font_get_glyph",
    "_hb_font_get_glyph_extents",
    "_hb_font_get_glyph_h_advance",
    "_hb_font_get_glyph_h_advances",
    "_hb_font_get_scale",
    "_hb_language_from_string",
    "_hb_language_to_string",
    "_hb_ot_font_set_funcs",
    "_hb_ot_metrics_get_position",
    "_hb_shape_full",
    "_hb_unicode_funcs_destroy"
)

Write-Host "Will wrap $($symbols.Count) HarfBuzz functions"

# Generate wrapper assembly file
$asmContent = "; Auto-generated stdcall wrappers for HarfBuzz x86`n"
$asmContent += ".586`n.model flat, stdcall`n.code`n`n"

foreach ($sym in $symbols) {
    $funcName = $sym.Substring(1)  # Remove leading underscore: _hb_xxx -> hb_xxx
    # Declare the cdecl version as external (it exists in libHarfBuzzSharp.lib)
    $asmContent += "EXTERN $sym:PROC`n"
    # Export the stdcall version with decoration
    $asmContent += "PUBLIC $sym`n"
    # Create wrapper that just jumps to the cdecl version
    # Since we're in stdcall .model, this export will get stdcall decoration
    $asmContent += "${funcName} PROC`n"
    $asmContent += "    jmp $sym`n"
    $asmContent += "${funcName} ENDP`n`n"
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
