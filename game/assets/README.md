# Production assets

This directory is the replacement point for external art. **It is empty of art
today, and that is the honest state of the project**: Street Capital ships no
imported meshes, textures, audio files or animation clips. Everything the game
draws is built from primitives at run time by the kits in `art/`, `world/` and
`vehicles/`.

Phase T's job was not to pretend otherwise. It was to make the seams where real
assets will go explicit, so that dropping a modelled car or a rigged character
into the project is a change to one registry entry rather than a rewrite.

## How replacement works

Every visual in the game is reached through a registry that maps a **semantic
id** to a **visual source**:

| Registry | File | Semantic id | Fallback today |
| --- | --- | --- | --- |
| Characters | `art/visual_registry.gd` | `CharacterLook.Category` | `CharacterKit.build` |
| Vehicles | `art/visual_registry.gd` | `VehicleData.Profile` | `VehicleBase._build_body` |
| Props | `art/visual_registry.gd` | prop id (`bench_01`) | `PropKit` / `DistrictProps` |
| Materials | `art/palette.gd` | material name | `CityKit.make_surface` |

To replace one, add a `PackedScene` path against its id. The registry prefers a
scene when one is registered and falls back to the builder when one is not, so
a half-finished art pass never leaves a hole in the world — see
`VisualRegistry.scene_for`.

Gameplay never asks which of the two it got. A vehicle's physics, ownership,
mileage, value, repair state, police status and save record all live on
`VehicleData` and `OwnedVehicle`; the mesh is downstream of all of it.

## Directory layout

Created as the destination for imported art. Left empty rather than filled with
placeholder files, because a folder of nothing is honest and a folder of
stand-in cubes is not.

```
assets/
    characters/   player/ civilians/ employees/ police/ contacts/ shared/
    vehicles/     civilian/ police/ commercial/
    buildings/    harbour/ central/ shared/
    interiors/    residential/ retail/ restaurant/ gym/ nightclub/
                  warehouse/ office/ dealership/ mechanic/ legal/ underworld/
    props/        street/ retail/ office/ industrial/ residential/ food/
    vegetation/
    materials/
    textures/
    animations/
    vfx/
    ui/           icons/ illustrations/
    audio/        ambience/ vehicles/ footsteps/ interface/ world/
                  police/ businesses/ music/
```

## What should be replaced first

In the order they would most improve the game, which is the order Phase T
worked in and the order the remaining gaps sit in:

1. **Characters.** The figure is assembled from twenty-odd boxes and reads as a
   person, but it is a person made of boxes. A modelled, skinned humanoid with
   the same joint names would drop into `CharacterAnimator` unchanged.
2. **Vehicles.** Silhouettes are right and the parts are all there — body,
   bonnet, raked screens, arches, wheels, lamps. Curved bodywork needs meshes.
3. **Vegetation.** Trees are a trunk and a cluster of spheres.
4. **Interior fittings.** Shelves, machines and equipment are boxes with the
   right footprint.
5. **Audio.** Every sound is synthesised at run time by `audio/`. There is no
   music at all, and the Voice bus carries nothing.

## What must not be replaced carelessly

Anything in the table above is safe to swap. These are not:

- **Collision.** Characters and vehicles keep their gameplay collision shapes
  whatever mesh is used. `AssetValidator` fails a build where a visual has
  changed a collision extent.
- **Interaction points.** A door's `Interactable` position is what the map,
  the routines and the property system all navigate to. Moving a façade mesh
  must not move the door.
- **Scale.** A character is authored at its `CharacterLook.height` in metres.
