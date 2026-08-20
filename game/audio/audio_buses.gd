class_name AudioBuses
extends RefCounted
## The mixer, built in code at boot.
##
## Godot ships one bus called Master. Everything past that has to exist before
## anything can be routed to it, and a `.tres` bus layout is a binary-ish file
## nobody can review in a diff. Building the layout here means the mix is
## readable, and the names below are the same strings the settings screen shows
## the player.
##
## Every bus is a child of Master, so one master slider moves the lot and the
## per-category sliders stay independent of each other.

const MASTER := &"Master"
const MUSIC := &"Music"
const SFX := &"SFX"
const AMBIENCE := &"Ambience"
const UI := &"UI"
const VEHICLES := &"Vehicles"
const VOICE := &"Voice"

## The order is the order they appear in the settings screen.
const ALL: Array[StringName] = [MASTER, MUSIC, SFX, AMBIENCE, UI, VEHICLES, VOICE]

## Where each bus sits before the player touches anything, as a 0..1 fraction.
##
## This is a mix, not defaults-by-convenience: effects sit loudest because they
## are the things the player caused, vehicles just under them, ambience well
## back so the city is a bed rather than a noise, and music lowest of all
## because a life sim that talks over itself is exhausting.
const DEFAULT_VOLUMES := {
	MASTER: 0.9,
	MUSIC: 0.55,
	SFX: 0.9,
	AMBIENCE: 0.6,
	UI: 0.7,
	VEHICLES: 0.8,
	VOICE: 0.8,
}


## Creates any bus that is missing and routes it to Master. Safe to call twice —
## the headless harness boots the tree more than once per process.
static func ensure_layout() -> void:
	for bus in ALL:
		if bus == MASTER:
			continue
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, MASTER)

	# A limiter on the master, so a chase — sirens, engines, traffic, a
	# collision and music at once — compresses instead of clipping.
	var master := AudioServer.get_bus_index(MASTER)
	if master >= 0 and AudioServer.get_bus_effect_count(master) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -0.8
		limiter.threshold_db = -2.0
		limiter.soft_clip_db = 2.0
		AudioServer.add_bus_effect(master, limiter)


static func index_of(bus: StringName) -> int:
	return AudioServer.get_bus_index(bus)


## Volume as a 0..1 fraction, which is what a slider holds and what gets saved.
## Muting is a fraction of zero rather than a separate flag.
static func set_volume(bus: StringName, fraction: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	var clamped := clampf(fraction, 0.0, 1.0)
	AudioServer.set_bus_mute(index, clamped <= 0.001)
	# A linear slider maps to decibels through a square, or the top quarter of
	# the travel does almost nothing and the bottom quarter does everything.
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(clamped * clamped, 0.0001)))


static func get_volume(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return 0.0
	if AudioServer.is_bus_mute(index):
		return 0.0
	return sqrt(clampf(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.0, 1.0))


## Human-readable name for the settings screen.
static func display_name(bus: StringName) -> String:
	match bus:
		SFX:
			return "Sound Effects"
		UI:
			return "Interface"
		_:
			return String(bus)
