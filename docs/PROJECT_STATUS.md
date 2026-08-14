# Project Status

## Current checkpoint

**Phase 3 — Greyfen systems in progress (2026-08-14).**

## Completed

- Audited all ten novel-bible working sources and selected the canon-complete Arc 1 scope.
- Verified Godot 4.7.1 stable and the console/headless executable.
- Chosen 2D top-down / 2.5D presentation after feasibility review.
- Generated and visually inspected original Greyfen title artwork.
- Locked the game design, Return state model, NPC agency requirements, and AI contract.
- Completed and verified the Godot project, responsive title menu, original icon, procedural ambience/cues, atomic JSON save/continue, and input map.
- Built the complete Greyfen hub, layered rain/lighting, eight named NPCs, four investigation points, Memory Folio, dialogue portraits, player movement/dodge/focus/shove, and four perception-state patrol agents.
- Implemented the four-pass Arc 1 progression through the collaborative finale, tribunal, G-1, and ending screen.
- Passed the foundation regression suite and complete world-instantiation/game-state/AI test.
- Captured and visually reviewed 1152 × 648 title and gameplay frames; corrected HUD formatting and overlap found during review.

## In progress

- End-to-end automated story-flow coverage.
- Playthrough tuning, dialogue timing, accessibility propagation, and visual polish.

## Phase gates

- [x] Phase 1: clean headless boot; title → playable world; save roundtrip.
- [x] Phase 2: first arrival and authored Return preserve/reset the correct state.
- [ ] Phase 3: all three threat foundations, NPC contribution logic, and enemy AI work. (systems implemented; end-to-end gate pending)
- [ ] Phase 4: complete new-game-to-credits story path.
- [ ] Phase 5: visual/audio/accessibility polish and regression suite.
- [ ] Phase 6: Windows export after matching Godot export templates are available.

## Known environment constraint

Godot export templates are not installed. The project can run and be tested in the editor now; producing a standalone `.exe` is a later packaging step.

## Source locations

- Novel planning bible: `D:\Book records\Novel Planning Bible`
- Canon Markdown mirrors: `D:\Book records\working`
- Godot console: `D:\Game dev experiment\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe`
