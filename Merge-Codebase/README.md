# Merge-Codebase (PowerShell)

A drop-in script to merge key project files into one reviewable text snapshot.

## Why
- Share a compact snapshot with collaborators or AI agents.
- Quickly diff snapshots across commits.
- Keep noise low with configurable excludes.

## Files
- `Merge-Codebase.ps1` — the merger  
- `merge.config.json` — per-project config  

## Quick Start

Use PowerShell commands like:

    # From the project root
    .\tools\Merge-Codebase.ps1 -InitConfig   # creates merge.config.json if missing
    .\tools\Merge-Codebase.ps1               # writes output per config
    .\tools\Merge-Codebase.ps1 -WhatIf       # dry-run; shows what would be included

> By default the output is written to `./merged-codebase.txt`.  
> Adjust in `merge.config.json`.

## Configuration

- `output.directory` — where to place the merged file (relative or absolute)  
- `output.filename` — name of the merged file  
- `output.encoding` — `utf8` (default), `utf8BOM`, `ascii`, `unicode`, `utf32`  
- `includes.rootFiles` — explicit files at repo root  
- `includes.directories` — directories to scan recursively  
- `includes.extensions` — file patterns to include  
- `excludes.directoryNames` — directory **names** to skip anywhere in the path  
- `excludes.rootFiles` — explicit root files to skip  
- `excludes.globs` — glob patterns (match against relative paths)  
- `behavior.maxFileSizeKB` — skip files larger than this (0 = unlimited)  
- `behavior.detectBinary` — skip files containing null bytes (first 64 KB)  
- `behavior.sortMode` — `path` or `none`  
- `behavior.followSymlinks` — include symlink targets if `true`  
- `behavior.addSectionSpacer` — blank line between files  
- `behavior.newLine` — affects headers only: `CRLF` or `LF`  

## Notes

- Headers use ASCII only to avoid console encoding issues.  
- To include images or binaries, set `detectBinary: false` and add extensions; consider keeping `maxFileSizeKB` conservative.  
- The script automatically ignores its own output file.

## Troubleshooting

- **Weird box-drawing characters?** Headers are plain ASCII; if you still see odd glyphs, ensure your editor is set to UTF-8.  
- **Nothing written?** Try `-WhatIf` to confirm matches, then relax excludes (globs or directory names).
