class_name WeaponData
extends Resource
## Everything an attack needs to know, as data.
##
## Fists are a WeaponData too — see items/weapons/fists.tres. That is the point:
## there is one attack routine, and a bat, a crowbar or a pistol is a different
## resource rather than a different code path. Adding one is a new .tres.
##
## RANGED exists in the enum but nothing fires yet. Phase G stops deliberately at
## the architecture: the melee loop is finished and tested, and a projectile is a
## new component that reads these same fields.

enum Kind { MELEE, RANGED }

@export var display_name: String = "Fists"
@export var kind: Kind = Kind.MELEE
## Shown on the HUD while equipped.
@export var icon_color: Color = Color(0.72, 0.70, 0.66)

@export_group("Attack")
## Damage per connecting hit. A civilian has 100 health.
@export var damage: float = 22.0
## How far in front the swing reaches, in metres.
@export var attack_range: float = 2.4
## Full width of the arc that counts as in front, in degrees. Generous on
## purpose: a top-down camera makes precise aiming with WASD miserable, and the
## brief asks for forgiving targeting rather than a duelling game.
@export var arc_degrees: float = 120.0
## Seconds between swings.
@export var cooldown: float = 0.55
## Shove applied to whoever is hit, in metres.
@export var knockback: float = 2.4

@export_group("Consequences")
## Whether using this on somebody is a crime. It always is so far; the flag is
## here so a later non-lethal or lawful use has somewhere to say so.
@export var attacks_are_crimes: bool = true


func is_melee() -> bool:
	return kind == Kind.MELEE
