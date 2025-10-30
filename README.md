# SkiaSharp.Static

Static library of Skia Sharp for Avalonia UI

For **Skia 3**, you must use with **Avalonia 12**.

## Supported Architectures

This project builds static libraries for the following architectures:
- **x64** (64-bit) - Default configuration using `args.gn`
- **x86** (32-bit) - Configuration using `args_x86.gn`

Each architecture produces separate artifacts with the naming pattern:
- `libSkiaSharp-{version}-{arch}-{ucrt_version}.7z`
- `libHarfBuzzSharp-{version}-{arch}-{ucrt_version}.7z`

A sample project here: <https://github.com/peaceshi/Avalonia-NativeAOT-SingleFile>
