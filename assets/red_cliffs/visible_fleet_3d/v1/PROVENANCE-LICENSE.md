# S5-02 visible fleet 3D asset provenance

These seven optimized runtime GLB files and the starfield background were copied from the user-owned POC at `C:\WorkSpace\Re_Legend_of_the_Galactic_Heroes` for `S5-02 — 적벽 실제 3D 전투 증거창 통합`.

- The user confirmed that the `user_ver3_runtime` ship assets are user-owned and available for use without separate restrictions.
- The starfield is an original POC asset generated with OpenAI ImageGen on 2026-09-12. The POC notes state that no copyrighted franchise image was used as an input or copied.
- Embedded PBR materials are preserved. Runtime material replacement is prohibited for these hulls.
- Source filenames, byte sizes, SHA-256 values, orientation, display scale, LOD policy, and ship-type mapping are recorded in `visible_fleet_3d_manifest.json`.
- `SHP-08` has no imported hull. It is represented by a procedural small-craft glyph and is not aliased to another ship class.
- The 21 adjacent `*_Image_0..2.jpg` PBR texture sidecars are copied with the seven runtime GLBs. Their combined size and a reproducible aggregate manifest hash are recorded in `visible_fleet_3d_manifest.json`; generated Godot `.import` sidecars are kept beside these runtime assets.

This directory is deliberately isolated from the existing shared ship models so the S5-02 slice can be reviewed or removed without changing other battle or voyage rendering paths.
