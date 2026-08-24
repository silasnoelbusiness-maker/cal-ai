# Import conventions

How an authored asset has to be shaped to drop into Street Capital. Written to
be tool-neutral: anything that can export a Godot-readable GLB will do, and
nothing here depends on one modelling package.

## Format and orientation

- **GLB** (binary glTF 2.0). One file per asset.
- **+Y up**, **−Z forward**, matching Godot's convention.
- **Metres**, at true scale. A person is about 1.8 m tall, a sedan about 4.5 m
  long, a storey about 3.4 m. `AssetValidator` fails a character outside
  1.40–2.10 m.
- Apply transforms before export. A mesh with a baked-in scale of 100 will
  import at the wrong size and drag its collision proxy with it.
- Material slots named for what they are — `body`, `glass`, `trim`, `lights` —
  so a paint colour can be driven from `VehicleData` without guessing which
  slot is the bodywork.

## Characters — `assets/characters/**/*.glb`

Expected bone names, adapted rather than required if a retargeting map is
supplied:

```
root
  hips
    spine → chest → neck → head
    upper_arm_l → lower_arm_l → hand_l
    upper_arm_r → lower_arm_r → hand_r
    upper_leg_l → lower_leg_l → foot_l
    upper_leg_r → lower_leg_r → foot_r
```

The gameplay collision capsule is **not** part of the mesh. It stays on the
`CharacterBody3D`, and the visual is a child of it. Changing the mesh must never
change the capsule — that is what keeps walking, hiding, arrest and pursuit
working across an art swap.

Wrap the GLB in a `.tscn` that carries the material overrides, the attachment
points and the `AnimationPlayer`. The registry points at the `.tscn`, never at
the GLB.

## Vehicles — `assets/vehicles/**/*.glb`

Expected empties, by name:

```
body            wheel_fl   wheel_fr   wheel_rl   wheel_rr
headlight_l     headlight_r
brake_l         brake_r
driver_seat     camera_anchor (optional)
```

Wheels must be separate nodes so they can spin and steer; the body must not
contain them. Ownership, mileage, value, repair, police status and saving all
live on `VehicleData` and `OwnedVehicle` and never on the mesh.

## Buildings — `assets/buildings/**/*.glb`

Semantic points, where the module has them:

```
entrance   service_entrance   sign_anchor   roof_anchor   interior_origin
```

`entrance` is what the map, the NPC routines and the property system navigate
to. A façade mesh may move; the entrance may not.

## Props — `assets/props/**/*.glb`

Register in `art/prop_library.gd` with its footprint, whether it is solid, and
which group it joins. A decorative prop wider than three metres fails
validation unless it is marked wide by design.

## After importing

1. Add the manifest row.
2. Register the `.tscn` in `art/visual_registry.gd`.
3. Run the suite. `AssetValidator` checks scale, collision, dead registry paths
   and door alignment; the fallback stays in place for anything unregistered.
