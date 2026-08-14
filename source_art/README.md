# Ashen Diorama Source Art

This directory is the editable production source for the 2.5D rebuild. Files here are not game-ready resources and must not be referenced by runtime scenes.

## Toolchain

- **Blender stable LTS:** modular meshes, collision proxies, UVs, original character rigs, animation passes, lighting references, and deterministic GLB exports.
- **Krita stable:** concept paint-over, hand-painted texture sources, portrait masters, sprite cleanup, palette work, masks, and UI masters.
- **Pixelorama, if needed:** final directional-sprite cleanup and animation timing. It is optional; no paid editor is required by the baseline pipeline.

Pin the exact installed versions and installer checksums before the first native source asset is committed. Official distributions are required.

## Planned layout

```text
source_art/
  environment/blender/
  environment/textures/
  characters/blender/
  characters/sprite_work/
  portraits/
  ui/
  vfx/
  export_tools/
```

Directories are created only when their first real asset lands; empty scaffolding is avoided.

## Naming and units

- Lowercase snake case only.
- Asset IDs follow `<family>.<subject>.<variant>.<version>` in the manifest.
- Blender scenes use metres, Y up, and transforms applied before export.
- Modular environment pieces snap to 1 m horizontally and 0.25 m vertically.
- Origins sit on a logical placement point: building modules at lower grid corner, props at ground-centre, characters between the feet.
- Collision proxies use `col_` prefixes; navigation-only helpers use `nav_`; occluders use `occ_`; sockets and landmarks use `socket_` and `mark_`.

## Export contract

1. Keep the editable `.blend` or `.kra` master and nondestructive layers.
2. Export game geometry as GLB into `assets/ashen/environment/` or `assets/ashen/characters/`; do not make runtime scenes depend on direct `.blend` import.
3. Export textures as PNG unless a reviewed Godot import setting requires another lossless source format.
4. Use albedo, packed ORM, normal, emission when needed, and wetness masks with consistent suffixes: `_albedo`, `_orm`, `_normal`, `_emission`, `_wet`.
5. Generate sprite albedo, normal, depth, and emission passes from the same locked camera and rig revision; retain the unflattened cleanup source.
6. Verify scale, origin, normals, UVs, material slots, collision alignment, and animation names in a clean Godot import scene.
7. Add or update `assets/ashen/asset_manifest.json` before any exported resource enters a gameplay scene.
8. Record tool version, source path, export path, author or generation method, prompt where applicable, license, checksum, and inspection status.

Source files should eventually be excluded from Godot import and release packaging once the first native art sources are added. Exported runtime assets remain self-contained so a player does not need Blender, Krita, or Pixelorama installed.

## Originality and provenance

- Do not place downloaded game assets, traced imagery, third-party logos, or unlicensed brushes/textures here.
- Do not use a living artist's name, a studio name, or a named game's style in generation prompts.
- Generated concepts are reference layers only unless a manifest entry explicitly approves another use after inspection.
- Rebuild production meshes and textures from the Greyfen visual bible; never project or crop the concept sheet onto geometry.
- Every third-party input, if one is ever approved, carries its original license file and attribution beside the editable source and in the project attribution record.

## Phase 0 contents

No Blender, Krita, or Pixelorama production source exists yet. The selected environment concept is stored under `assets/ashen/concepts/` because it is a reviewed project reference, with exact prompt and provenance in the asset manifest.
