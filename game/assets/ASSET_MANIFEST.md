# Asset manifest

Every asset the game draws, with its provenance. Street Capital may be released
commercially, so nothing goes in this project without a known source and a
licence that permits commercial distribution and modification.

## The state of it today

**There are no external assets.** Not one imported mesh, texture, audio file,
animation clip, font file or icon. Every visual and every sound in the running
game is constructed at load time from primitives by the kits in `art/`,
`world/`, `vehicles/` and `audio/`.

That means every row below reads `STREET CAPITAL ORIGINAL`, and the interesting
part of this document is not the table — it is the list of import slots that are
prepared and empty, which is in `assets/README.md` and in the Phase T2 report.

## Originals

| Asset ID | Display name | Category | Author / source | Licence | Commercial | Modify | Attribution | Import path |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `character_kit` | Stylized humanoid | Character | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `art/character_kit.gd` |
| `character_animator` | Joint animation | Animation | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `art/character_animator.gd` |
| `vehicle_body` | Vehicle bodywork | Vehicle | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `vehicles/vehicle_base.gd` |
| `building_kit` | Façade modules | Building | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `art/building_kit.gd` |
| `city_kit` | Primitive geometry | Building | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `world/city_kit.gd` |
| `prop_kit` | Street and retail props | Prop | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `art/prop_kit.gd` |
| `street_dressing` | Pavement furniture | Prop | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `world/props/street_dressing.gd` |
| `district_props` | Benches, machines | Prop | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `world/props/district_props.gd` |
| `tree_street` | Street tree | Vegetation | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `world/city_kit.gd` (`add_tree`) |
| `tree_park` | Park tree | Vegetation | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `world/city_kit.gd` (`add_tree`) |
| `tree_sparse` | Yard tree | Vegetation | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `world/city_kit.gd` (`add_tree`) |
| `palette` | Material library | Material | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `art/palette.gd` |
| `surface_noise` | Procedural detail | Texture | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `world/city_kit.gd` (`_noise`) |
| `icon_glyphs` | UI iconography | UI | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `ui/icons/icon_glyph.gd` |
| `ui_theme` | Interface theme | UI | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `ui/theme/ui_theme.gd` |
| `sound_bank` | Synthesised audio | Audio | STREET CAPITAL ORIGINAL | Project-owned | Yes | Yes | None | `audio/` |

Fonts are the engine's own defaults. No font file is distributed with the
project.

## What must never appear here

Assets ripped or extracted from another game; models, textures, UI graphics or
music copied from a proprietary product; anything whose author or licence is not
known. A row with an unknown source is a build failure, not a note to follow up
— `AssetValidator.check_manifest` fails on one.

## Adding an external asset

1. Put the file under the matching `assets/` directory.
2. Add a row here with every column filled in. `Author / source` may not be
   blank and may not be "unknown".
3. If the licence requires attribution, add the required text to the row and to
   the game's credits.
4. Register the scene against its semantic id in `art/visual_registry.gd`.
5. Run the suite. The manifest check will tell you if anything is unaccounted
   for.
