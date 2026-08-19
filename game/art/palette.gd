class_name Palette
extends RefCounted
## The city's material library, and the colours the UI reads meaning from.
##
## One cached instance per named material, shared by everything that asks. That
## matters twice over: a hundred benches built from `Palette.of(&"metal_dark")`
## are a hundred references to one StandardMaterial3D rather than a hundred
## materials to bind, and a change to the city's concrete is one edit here
## rather than a search across eight files.
##
## Names are what the material *is*, never where it is used — `brick_warm`, not
## `harbour_wall` — so the same entry can dress a shopfront in one district and
## a stairwell in the other without lying about itself.

## Meaning, not decoration. Everything that reports state to the player — the
## HUD, the map, the dashboards, a shop sign — takes its colour from here so the
## same idea is never two different greens.
const MONEY := Color(0.396, 0.851, 0.545)
const LOSS := Color(0.949, 0.435, 0.416)
const DANGER := Color(0.937, 0.325, 0.314)
const WARNING := Color(0.976, 0.741, 0.361)
const CALM := Color(0.478, 0.694, 0.961)
const POLICE_BLUE := Color(0.239, 0.451, 0.949)
const POLICE_RED := Color(0.925, 0.259, 0.267)
const NEUTRAL := Color(0.741, 0.769, 0.816)
const DIM := Color(0.522, 0.553, 0.612)

## Panel and text colours for the UI, kept beside the world palette so the two
## cannot drift apart.
const UI_BACKDROP := Color(0.043, 0.051, 0.075, 0.90)
const UI_PANEL := Color(0.078, 0.090, 0.122, 0.96)
const UI_RAISED := Color(0.114, 0.129, 0.169, 1.0)
const UI_LINE := Color(1.0, 1.0, 1.0, 0.09)
const UI_TEXT := Color(0.898, 0.918, 0.953)
const UI_MUTED := Color(0.588, 0.620, 0.678)
const UI_ACCENT := Color(0.408, 0.678, 0.965)

static var _cache: Dictionary = {}


## The library. Each entry is [colour, roughness, detail metres, bump, mottle,
## metallic, noise seed] — the arguments CityKit.make_surface takes — or a
## four-entry [colour, roughness, metallic, "flat"] for the smooth ones.
const LIBRARY := {
	# --- Ground and street ---
	&"asphalt": [Color(0.157, 0.163, 0.180), 0.93, 6.0, 1.5, 0.22, 0.0, 2],
	&"asphalt_worn": [Color(0.196, 0.200, 0.212), 0.95, 4.0, 1.9, 0.30, 0.0, 21],
	&"road_paint": [Color(0.878, 0.878, 0.847), 0.72, 0.0, 0.0, 0.0, 0.0, 0],
	&"road_paint_amber": [Color(0.902, 0.741, 0.298), 0.72, 0.0, 0.0, 0.0, 0.0, 0],
	&"sidewalk": [Color(0.529, 0.529, 0.514), 0.90, 1.2, 0.9, 0.14, 0.0, 3],
	&"sidewalk_fine": [Color(0.573, 0.573, 0.561), 0.86, 0.9, 0.7, 0.10, 0.0, 31],
	&"kerb": [Color(0.686, 0.682, 0.663), 0.84, 2.0, 0.5, 0.08, 0.0, 32],
	&"paving_stone": [Color(0.596, 0.584, 0.549), 0.82, 1.1, 1.0, 0.16, 0.0, 8],
	&"gravel": [Color(0.451, 0.443, 0.416), 0.96, 0.7, 2.0, 0.34, 0.0, 33],

	# --- Walls ---
	&"brick_warm": [Color(0.510, 0.322, 0.267), 0.90, 0.9, 1.4, 0.22, 0.0, 6],
	&"brick_dark": [Color(0.376, 0.263, 0.239), 0.92, 0.9, 1.4, 0.24, 0.0, 34],
	&"render_pale": [Color(0.769, 0.749, 0.706), 0.84, 2.5, 0.6, 0.12, 0.0, 35],
	&"render_warm": [Color(0.757, 0.671, 0.573), 0.86, 2.5, 0.6, 0.13, 0.0, 36],
	&"concrete": [Color(0.588, 0.596, 0.608), 0.86, 3.0, 0.7, 0.14, 0.0, 8],
	&"concrete_dark": [Color(0.400, 0.412, 0.435), 0.88, 3.0, 0.7, 0.15, 0.0, 37],
	&"stone_trim": [Color(0.729, 0.714, 0.678), 0.80, 2.0, 0.5, 0.09, 0.0, 38],
	&"panel_teal": [Color(0.243, 0.353, 0.365), 0.82, 2.0, 0.4, 0.10, 0.0, 39],
	&"panel_navy": [Color(0.180, 0.220, 0.298), 0.80, 2.0, 0.4, 0.10, 0.0, 40],
	&"panel_sand": [Color(0.741, 0.663, 0.510), 0.84, 2.0, 0.4, 0.10, 0.0, 41],

	# --- Glass, metal, wood ---
	&"glass_dark": [Color(0.114, 0.145, 0.180), 0.10, 0.55, "flat"],
	&"glass_shop": [Color(0.365, 0.435, 0.475), 0.08, 0.40, "flat"],
	&"glass_lit": [Color(0.988, 0.910, 0.741), 0.25, 0.0, "flat"],
	&"metal_dark": [Color(0.196, 0.208, 0.231), 0.45, 0.60, "flat"],
	&"metal_mid": [Color(0.435, 0.451, 0.478), 0.40, 0.65, "flat"],
	&"metal_pale": [Color(0.706, 0.722, 0.749), 0.35, 0.70, "flat"],
	&"steel_blue": [Color(0.290, 0.353, 0.427), 0.42, 0.55, "flat"],
	&"wood_floor": [Color(0.400, 0.286, 0.192), 0.72, 0.5, 1.1, 0.16, 0.0, 10],
	&"wood_dark": [Color(0.361, 0.263, 0.184), 0.78, 0.6, 1.0, 0.18, 0.0, 42],
	&"wood_pale": [Color(0.729, 0.596, 0.427), 0.74, 0.5, 0.9, 0.14, 0.0, 43],

	# --- Interiors ---
	&"tile_floor": [Color(0.427, 0.435, 0.447), 0.55, 0.8, 0.5, 0.07, 0.0, 44],
	&"tile_checker": [Color(0.365, 0.380, 0.400), 0.58, 0.8, 0.6, 0.10, 0.0, 45],
	&"lino_grey": [Color(0.345, 0.353, 0.365), 0.68, 1.4, 0.4, 0.08, 0.0, 46],
	&"carpet_warm": [Color(0.529, 0.443, 0.376), 0.94, 0.4, 1.4, 0.18, 0.0, 47],
	&"wall_paint": [Color(0.569, 0.580, 0.596), 0.88, 3.0, 0.3, 0.06, 0.0, 48],
	&"wall_warm": [Color(0.576, 0.514, 0.439), 0.88, 3.0, 0.3, 0.06, 0.0, 49],
	&"wall_sage": [Color(0.604, 0.647, 0.604), 0.88, 3.0, 0.3, 0.06, 0.0, 50],
	&"wall_slate": [Color(0.325, 0.353, 0.400), 0.88, 3.0, 0.3, 0.06, 0.0, 51],
	&"counter_top": [Color(0.294, 0.310, 0.341), 0.35, 1.0, 0.3, 0.06, 0.10, 52],

	# --- Greenery ---
	&"grass": [Color(0.286, 0.400, 0.216), 0.95, 1.6, 1.8, 0.28, 0.0, 4],
	&"grass_dry": [Color(0.400, 0.427, 0.263), 0.95, 1.6, 1.8, 0.30, 0.0, 53],
	&"foliage_deep": [Color(0.220, 0.353, 0.216), 0.92, 0.6, 1.6, 0.26, 0.0, 54],
	&"foliage_mid": [Color(0.290, 0.427, 0.259), 0.92, 0.6, 1.6, 0.24, 0.0, 55],
	&"foliage_light": [Color(0.373, 0.494, 0.298), 0.92, 0.6, 1.6, 0.22, 0.0, 56],
	&"bark": [Color(0.318, 0.243, 0.176), 0.94, 0.4, 1.6, 0.24, 0.0, 12],
	&"soil": [Color(0.263, 0.216, 0.180), 0.96, 0.5, 1.6, 0.26, 0.0, 57],

	# --- Roofs ---
	&"roof_flat": [Color(0.267, 0.275, 0.290), 0.92, 2.0, 1.0, 0.18, 0.0, 5],
	&"roof_shingle": [Color(0.510, 0.286, 0.180), 0.92, 1.0, 1.6, 0.26, 0.0, 6],
	&"roof_slate": [Color(0.290, 0.306, 0.337), 0.88, 1.0, 1.4, 0.22, 0.0, 7],

	# --- Skin and cloth, for the character kit ---
	# Read from two metres away rather than two hundred, so these carry no
	# relief at all: the same triplanar noise that makes a road look like asphalt
	# makes a jacket look like gravel.
	&"cloth": [Color(0.404, 0.435, 0.502), 0.86, 0.0, "flat"],
	&"denim": [Color(0.267, 0.318, 0.404), 0.90, 0.0, "flat"],
	&"leather": [Color(0.176, 0.184, 0.204), 0.55, 0.05, "flat"],
	&"skin": [Color(0.792, 0.616, 0.478), 0.74, 0.0, "flat"],
}


## The shared material for a library name. Never duplicate the result — anything
## that needs its own colour should build one with CityKit directly.
static func of(id: StringName) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id]
	var entry: Array = LIBRARY.get(id, [])
	var material: StandardMaterial3D
	if entry.is_empty():
		push_warning("Palette has no material called '%s'." % id)
		material = CityKit.make_material(Color(1.0, 0.0, 1.0))
	elif entry.size() == 4:
		material = CityKit.make_material(entry[0], entry[1], entry[2])
	else:
		material = CityKit.make_surface(
			entry[0], entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
		)
	_cache[id] = material
	return material


## The authored colour of a library entry, without building the material. For
## anything that wants to tint from the palette — a UI swatch, a light.
static func colour_of(id: StringName) -> Color:
	var entry: Array = LIBRARY.get(id, [])
	return entry[0] if not entry.is_empty() else Color.MAGENTA


## A one-off material in the family of a library entry: same finish, different
## colour. This is how a shop gets its own paint without a new library name.
static func tinted(id: StringName, colour: Color) -> StandardMaterial3D:
	var entry: Array = LIBRARY.get(id, [])
	if entry.is_empty():
		return CityKit.make_material(colour)
	if entry.size() == 4:
		return CityKit.make_material(colour, entry[1], entry[2])
	return CityKit.make_surface(
		colour, entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
	)


## An emissive material, cached by colour and strength so a street of lit
## windows shares one.
static func glow(colour: Color, energy: float = 1.0) -> StandardMaterial3D:
	var key := StringName("glow_%s_%.2f" % [colour.to_html(false), energy])
	if _cache.has(key):
		return _cache[key]
	var material := CityKit.make_emissive_material(colour, energy)
	_cache[key] = material
	return material


## Development and testing entry point: forgets every cached material so a
## palette edit can be re-read without restarting.
static func forget() -> void:
	_cache.clear()
