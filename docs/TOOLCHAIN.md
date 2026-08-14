# Ashen Diorama production toolchain

Pinned on 2026-08-15 for the Windows production workspace. The tools are portable
and live outside the game repository under `D:\Game dev experiment\Toolchain`.
They are not required to play or export the checked-in Godot project; they are the
reproducible source-art toolchain.

| Tool | Pinned version | Portable executable | Download archive SHA-256 |
| --- | --- | --- | --- |
| Godot | 4.7.1 stable, official `a13da4feb` | `Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe` | Bundled with the workspace |
| Blender | 4.5.12 LTS | `Toolchain\apps\blender-4.5.12-windows-x64\blender.exe` | `317EF64E7A2C3CC79EC810C766AE9828AFF865BEA78039DC695B3F1118C34B4F` |
| Krita | 6.0.2 | `Toolchain\apps\krita-6.0.2\krita-x64-6.0.2\bin\krita.exe` | `80EB339BB302D8BE2015D8027BE93F5D4EFEA345169BECD20963167279E61B57` |
| Pixelorama | 1.2.0 | `Toolchain\apps\pixelorama-1.2\Pixelorama-Windows-64bit\Pixelorama.exe` | `1DDC65930DDD435612519E293D1927849D4D4C18928A856B5BD4F058FE2F4A72` |
| Audacity | 3.7.8 | `Toolchain\apps\audacity-3.7.8\audacity-win-3.7.8-64bit\Audacity.exe` | `900620F6E9BB6A9F6D1C0A1A10B58EAF480C0C8A4BFCE134F89E80EDDC83979F` |
| FFmpeg | 9.0.1 essentials | `Toolchain\apps\ffmpeg-release-essentials\ffmpeg-9.0.1-essentials_build\bin\ffmpeg.exe` | `FEC81AE03971D9DD4BE3EBE02E263BD2EC1D789483F931BDBA5F5715E65DA2E9` |

## Sources

- Blender: official 4.5 LTS Windows archive from `download.blender.org`.
- Krita: official Windows archive from `download.kde.org`.
- Pixelorama: official Orama Interactive GitHub release, tag `v1.2`.
- Audacity: official Audacity GitHub release, tag `Audacity-3.7.8`. The archive
  checksum matches the checksum published on audacityteam.org.
- FFmpeg: Gyan.dev Windows essentials build of upstream FFmpeg 9.0.1.

## Deterministic environment export

Run Blender in background mode with
`source_art/blender/build_greyfen_diorama.py`. The script regenerates the original
procedural texture set, the editable `.blend`, semantic `anchor__*` empties,
landmark-owned `-colonly` collision proxies, and
`assets/ashen/environment/greyfen_diorama.glb`.

Production raster cleanup is saved as editable Krita or Pixelorama source under
`source_art/`; runtime atlases are exported as PNG under `assets/ashen/`. Audio
masters belong under `source_art/audio/`; runtime WAV/OGG exports belong under
`assets/ashen/audio/`. FFmpeg is used only for deterministic conversion and phase
capture encoding.
