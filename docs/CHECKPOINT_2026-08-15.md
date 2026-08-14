# Ashen Diorama WIP checkpoint — 2026-08-15

This is an intentional recovery checkpoint, not a phase-complete release.
The protected 2D baseline remains tag `pre-2.5d-stable` at `40bc7c2` and the
shipping entry point has not yet been switched to the new world.

## Preserved work

- Original five-district concept, art bible, provenance manifest and portable
  Blender/Krita/Pixelorama/Audacity/FFmpeg toolchain record.
- Editable Blender source, deterministic build script, imported GLB environment,
  original wet-material textures, landmark anchors and landmark-owned collision.
- Original Evan, named-NPC, enemy and dialogue-portrait atlases.
- Save schema V2 with safe V1 migration, semantic checkpoints and stable enemy IDs.
- 3D player/camera/collision/landmark/navigation/enemy/weather/billboard systems.
- Hidden story-director adapter preserving the complete four-pass narrative and UI.
- First integrated 3D world wrapper, NPC/evidence targets, granary defense volume,
  lighting, pass grading and initial procedural soundscape work.

## Validation at checkpoint

Passing: foundation, legacy gameplay, complete arrival-to-ending story flow, save
V2 migration, spatial contracts, imported-world validation, story adapter and
billboard/portrait atlas suites.

Known incomplete gates:

- `test_ashen_soundscape.gd` is paused on strict Variant-inference errors at
  `soundscape_3d.gd` lines 95–96; the agent was interrupted specifically so this
  checkpoint could be made.
- `test_ashen_gameplay_3d.gd` currently reports deterministic fixture failures for
  Area3D overlap, the defense-volume query, the shove line probe, one missing ward
  anchor and a too-strict arrival-height tolerance. Diagnostic values are retained
  in the test for the next session.
- The project deliberately remains on the Compatibility renderer and old 2D main
  entry point until the integrated 3D gate passes. Forward+ warnings in this WIP
  state are expected.

## Exact continuation

1. Fix the soundscape type annotations and rerun its dedicated suite.
2. Resolve collision-query masks/monitoring and deterministic defense-volume
   containment, then rerun `test_ashen_gameplay_3d.gd`.
3. Run every existing and new suite plus editor parse.
4. Commit/tag Phase 1 only after those gates are green; then switch Forward+ and
   the default world entry point for the playable vertical-slice checkpoint.
