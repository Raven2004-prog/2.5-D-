# Project Status

## Current checkpoint

**Phase 6 — complete playable Windows release (2026-08-14).**

## Completed

- Audited all ten novel-bible working sources and selected the canon-complete Arc 1 scope.
- Verified Godot 4.7.1 stable and the console/headless executable.
- Chosen 2D top-down / 2.5D presentation after feasibility review.
- Generated and visually inspected original Greyfen title artwork.
- Locked the game design, Return state model, NPC agency requirements, and AI contract.
- Completed and verified the Godot project, responsive title menu, original icon, procedural ambience/cues, atomic JSON save/continue, damaged-save rejection, and input map.
- Built the complete Greyfen hub, layered rain/lighting, eight named NPCs, four investigation points, Memory Folio, dialogue portraits, player movement/dodge/focus/shove, and four perception-state patrol agents.
- Implemented the four-pass Arc 1 progression through the collaborative finale, tribunal, and complete Lysford-bound ending.
- Added an in-game pause/save flow and a one-click Windows launcher beside the project.
- Added and smoke-tested a standalone Windows x86_64 release build (`.exe` plus companion `.pck`).
- Passed the foundation regression suite, complete world-instantiation/game-state/AI test, and a full arrival-to-ending story-flow regression, including reloads during evidence, Return, consent, finale, and tribunal beats.
- Completed a canon/disclosure review covering Return resets, present-line consent, NPC agency, Tomas's non-lethal route, and all six finale contributions.
- Captured and visually reviewed 1152 × 648 title and gameplay frames; corrected HUD formatting and overlap found during review.

## Phase gates

- [x] Phase 1: clean headless boot; title → playable world; save roundtrip.
- [x] Phase 2: first arrival and authored Return preserve/reset the correct state.
- [x] Phase 3: all three threat foundations, NPC contribution logic, and enemy AI work.
- [x] Phase 4: complete new-game-to-credits story path.
- [x] Phase 5: visual/audio/accessibility polish and regression suite.
- [x] Phase 6: matching Godot 4.7.1 Windows templates installed; standalone release exported and boot-tested.

## Packaging note

The Windows build uses a separate `.pck` beside the `.exe`, following Godot's safer unsigned-build recommendation. Keep both files together when moving or sharing the game.

## Source locations

- Novel planning bible: `D:\Book records\Novel Planning Bible`
- Canon Markdown mirrors: `D:\Book records\working`
- Godot console: `D:\Game dev experiment\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe`
