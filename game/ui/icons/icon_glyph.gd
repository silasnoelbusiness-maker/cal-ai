class_name IconGlyph
extends Control
## One icon, drawn rather than loaded.
##
## The project ships no image assets and will not download any, so an icon here
## is a handful of lines and polygons in `_draw`. That is not a compromise for
## this art direction — the game is flat-shaded stylized geometry, and a glyph
## made of the same straight lines belongs to it in a way a downloaded icon set
## would not.
##
## Every glyph is drawn inside a unit square and scaled to whatever size the
## Control has been given, so one definition serves a 14-pixel HUD icon and a
## 32-pixel dashboard heading.

## Appended to, never reordered — a saved filter or a UI layout may store one.
enum Kind {
	MONEY, HOME, CAR, BUSINESS, STAFF, WAREHOUSE, PROPERTY, POLICE, LEGAL,
	CRIME, OBJECTIVE, FOOD, ENERGY, HEALTH, JOB, CONTACT, TIME, MAP,
}

## What each icon is called, for a legend or a tooltip.
const NAMES := {
	Kind.MONEY: "Money", Kind.HOME: "Home", Kind.CAR: "Vehicle",
	Kind.BUSINESS: "Business", Kind.STAFF: "Staff", Kind.WAREHOUSE: "Depot",
	Kind.PROPERTY: "Property", Kind.POLICE: "Police", Kind.LEGAL: "Legal",
	Kind.CRIME: "Crime", Kind.OBJECTIVE: "Objective", Kind.FOOD: "Food",
	Kind.ENERGY: "Energy", Kind.HEALTH: "Health", Kind.JOB: "Work",
	Kind.CONTACT: "Contact", Kind.TIME: "Time", Kind.MAP: "Map",
}

@export var kind: Kind = Kind.MONEY:
	set(value):
		kind = value
		queue_redraw()
@export var colour: Color = Palette.UI_TEXT:
	set(value):
		colour = value
		queue_redraw()
## Line weight as a fraction of the icon's size, so a big icon is not a thin
## one blown up.
@export var weight: float = 0.11


static func make(icon: Kind, pixels: float = 16.0, tint: Color = Palette.UI_TEXT) -> IconGlyph:
	var glyph := IconGlyph.new()
	glyph.kind = icon
	glyph.colour = tint
	glyph.custom_minimum_size = Vector2(pixels, pixels)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return glyph


static func name_of(icon: Kind) -> String:
	return String(NAMES.get(icon, "Icon"))


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	if s <= 1.0:
		return
	var w: float = s * weight
	# Everything below is expressed in the unit square and scaled here, so a
	# glyph never has to know what size it is being drawn at.
	var p := func(x: float, y: float) -> Vector2:
		return Vector2(x * s, y * s)
	match kind:
		Kind.MONEY:
			# A note: a rectangle with a bar across it.
			_frame(p.call(0.10, 0.26), p.call(0.90, 0.74), w)
			draw_line(p.call(0.30, 0.50), p.call(0.70, 0.50), colour, w)
		Kind.HOME:
			draw_polyline([
				p.call(0.12, 0.52), p.call(0.50, 0.16), p.call(0.88, 0.52),
			], colour, w)
			_frame(p.call(0.22, 0.50), p.call(0.78, 0.86), w)
		Kind.CAR:
			_frame(p.call(0.08, 0.46), p.call(0.92, 0.70), w)
			draw_polyline([
				p.call(0.24, 0.46), p.call(0.34, 0.28),
				p.call(0.68, 0.28), p.call(0.78, 0.46),
			], colour, w)
			draw_circle(p.call(0.28, 0.76), s * 0.09, colour)
			draw_circle(p.call(0.72, 0.76), s * 0.09, colour)
		Kind.BUSINESS:
			# A shopfront: an awning over a door.
			draw_line(p.call(0.08, 0.34), p.call(0.92, 0.34), colour, w)
			_frame(p.call(0.16, 0.34), p.call(0.84, 0.88), w)
			draw_line(p.call(0.50, 0.56), p.call(0.50, 0.88), colour, w)
		Kind.STAFF:
			draw_circle(p.call(0.50, 0.28), s * 0.15, colour)
			draw_polyline([
				p.call(0.20, 0.86), p.call(0.24, 0.58),
				p.call(0.76, 0.58), p.call(0.80, 0.86),
			], colour, w)
		Kind.WAREHOUSE:
			draw_polyline([
				p.call(0.08, 0.44), p.call(0.50, 0.18), p.call(0.92, 0.44),
			], colour, w)
			_frame(p.call(0.16, 0.44), p.call(0.84, 0.86), w)
			draw_line(p.call(0.16, 0.66), p.call(0.84, 0.66), colour, w)
		Kind.PROPERTY:
			_frame(p.call(0.14, 0.14), p.call(0.56, 0.86), w)
			_frame(p.call(0.56, 0.40), p.call(0.88, 0.86), w)
		Kind.POLICE:
			# A shield.
			draw_polyline([
				p.call(0.50, 0.12), p.call(0.86, 0.28), p.call(0.80, 0.62),
				p.call(0.50, 0.88), p.call(0.20, 0.62), p.call(0.14, 0.28),
				p.call(0.50, 0.12),
			], colour, w)
		Kind.LEGAL:
			# Scales: a beam on a post.
			draw_line(p.call(0.50, 0.16), p.call(0.50, 0.84), colour, w)
			draw_line(p.call(0.16, 0.32), p.call(0.84, 0.32), colour, w)
			draw_line(p.call(0.26, 0.84), p.call(0.74, 0.84), colour, w)
			draw_line(p.call(0.16, 0.32), p.call(0.16, 0.52), colour, w)
			draw_line(p.call(0.84, 0.32), p.call(0.84, 0.52), colour, w)
		Kind.CRIME:
			# A mask: two eyes on a band. No skull, no swag bag.
			_frame(p.call(0.10, 0.36), p.call(0.90, 0.64), w)
			draw_circle(p.call(0.34, 0.50), s * 0.07, colour)
			draw_circle(p.call(0.66, 0.50), s * 0.07, colour)
		Kind.OBJECTIVE:
			draw_arc(p.call(0.50, 0.50), s * 0.34, 0.0, TAU, 28, colour, w)
			draw_circle(p.call(0.50, 0.50), s * 0.10, colour)
		Kind.FOOD:
			# A fork and a plate edge.
			draw_arc(p.call(0.50, 0.54), s * 0.32, PI * 0.15, PI * 0.85, 20, colour, w)
			draw_line(p.call(0.32, 0.18), p.call(0.32, 0.48), colour, w)
			draw_line(p.call(0.68, 0.18), p.call(0.68, 0.48), colour, w)
		Kind.ENERGY:
			draw_polyline([
				p.call(0.58, 0.10), p.call(0.32, 0.52), p.call(0.52, 0.52),
				p.call(0.42, 0.90), p.call(0.70, 0.44), p.call(0.50, 0.44),
				p.call(0.58, 0.10),
			], colour, w)
		Kind.HEALTH:
			draw_line(p.call(0.50, 0.16), p.call(0.50, 0.84), colour, w * 1.6)
			draw_line(p.call(0.16, 0.50), p.call(0.84, 0.50), colour, w * 1.6)
		Kind.JOB:
			# A case with a handle.
			_frame(p.call(0.10, 0.36), p.call(0.90, 0.84), w)
			draw_polyline([
				p.call(0.36, 0.36), p.call(0.36, 0.20),
				p.call(0.64, 0.20), p.call(0.64, 0.36),
			], colour, w)
		Kind.CONTACT:
			draw_circle(p.call(0.50, 0.30), s * 0.14, colour)
			draw_arc(p.call(0.50, 0.86), s * 0.30, PI, TAU, 20, colour, w)
		Kind.TIME:
			draw_arc(p.call(0.50, 0.50), s * 0.36, 0.0, TAU, 30, colour, w)
			draw_line(p.call(0.50, 0.50), p.call(0.50, 0.28), colour, w)
			draw_line(p.call(0.50, 0.50), p.call(0.68, 0.58), colour, w)
		Kind.MAP:
			draw_polyline([
				p.call(0.10, 0.24), p.call(0.37, 0.14), p.call(0.63, 0.28),
				p.call(0.90, 0.18), p.call(0.90, 0.76), p.call(0.63, 0.86),
				p.call(0.37, 0.72), p.call(0.10, 0.82), p.call(0.10, 0.24),
			], colour, w)
			draw_line(p.call(0.37, 0.14), p.call(0.37, 0.72), colour, w * 0.7)
			draw_line(p.call(0.63, 0.28), p.call(0.63, 0.86), colour, w * 0.7)


## An open rectangle. Godot's draw_rect with a width draws inside the bounds,
## which at this size loses a pixel on each edge, so this walks the corners.
func _frame(from: Vector2, to: Vector2, w: float) -> void:
	draw_polyline([
		from, Vector2(to.x, from.y), to, Vector2(from.x, to.y), from,
	], colour, w)
