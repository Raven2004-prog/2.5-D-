# Ashen Diorama 2.5D Rebuild — Phase Status

**Active branch:** `feature/ashen-diorama-2_5d`  
**Protected playable baseline:** `pre-2.5d-stable` at `40bc7c2`  
**Current gate:** Phase 1 integration in progress; local WIP checkpoint saved  
**Updated:** 2026-08-15

The existing 2D release remains the recoverable playable baseline. The new presentation is being built in checkpoints and must not replace the release entry point until full story, save, AI, accessibility, performance, and export equivalence is proven.

## Phase ledger

| Phase | Status | Deliverable and exit gate |
| --- | --- | --- |
| 0 — Direction and provenance | **Complete** | Visual bible, source-art contract, manifest schema, selected original five-district concept, baseline tag confirmed; no runtime files changed |
| 1 — 3D technical blockout | **In progress** | Authored five-district GLB, CharacterBody3D movement, camera, collision contract, navigation, semantic landmarks, story adapter and save migration are present. The combined interaction/finale physics gate is not yet green. |
| 2 — Granary vertical slice | Pending | Finished Granary/Refuge Row slice with Evan, Mara, one agent, evidence, rain, fog, ward light and dialogue; visual sign-off before mass production |
| 3 — Environment production | Pending | Complete modular environment kit and seven art-complete districts; exploration scale, alternate routes, shortcuts and collider sweep pass |
| 4 — Characters, portraits and UI | Pending | Named cast, agent/civilian sets, animations, portraits, map, folio and responsive high-resolution UI complete |
| 5 — Lighting, camera and VFX | Pending | Lightmaps, wet materials, weather, fog, lighting states, professional effects and accessibility alternatives pass visual/performance review |
| 6 — Full story and systems port | Pending | All four passes, evidence, consent, AI, non-lethal finale, Returns, tribunal, ending and reload paths pass in 3D |
| 7 — Optimization and Windows release | Pending | Quality tiers, LOD/culling/instancing, clean logs, reference performance, complete regression and smoke-tested EXE/PCK |

## Phase 0 evidence

- `docs/ASHEN_DIORAMA_BIBLE.md` locks the original visual grammar, scale, camera, palette, asset targets, lighting/VFX language, collider contract, accessibility behavior, and approval criteria.
- `source_art/README.md` defines the editable-source and deterministic-export workflow.
- `assets/ashen/asset_manifest.json` records exact provenance, prompt, dimensions, checksum, intended use, and inspection results.
- `assets/ashen/concepts/greyfen_five_district_environment_concept.png` is the selected 16:9 visual target: 1672 × 941 RGB PNG, SHA-256 `8D8F64F59A06143CA21CABE844DA2AA5F4F26CE4B0D845F637D9BAFD99F1D9F3`.
- Visual inspection confirmed exactly five coherent district views, distinct focal landmarks, wet material definition, readable path intent, consistent storm-dusk atmosphere, and no text, logo, watermark, UI, or recognizable third-party character.
- The Phase 0 art package itself does not modify game scripts, scenes, renderer configuration, or the protected release build; runtime work is gated separately.

## Checkpoint policy

Every phase ends with:

1. A focused commit and named checkpoint/tag.
2. A playable preview build where the phase includes runtime work.
3. Automated test logs plus collision/navigation/performance evidence appropriate to the phase.
4. Fixed-camera before/after captures and a short visual-review note.
5. An updated ledger here before the next phase begins.

If a phase gate fails, work continues on that phase without removing or rewriting the protected playable baseline.

## Next gate

Resume Phase 1 from the WIP checkpoint documented in
`docs/CHECKPOINT_2026-08-15.md`. Correct the Area3D overlap/integration fixtures,
finish the procedural soundscape parse gate, switch the renderer and launch scene
only after the combined world test passes, then capture the first playable preview.
