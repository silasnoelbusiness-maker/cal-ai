class_name ToneBank
extends RefCounted
## Every sound in STREET CAPITAL, synthesised.
##
## There are no audio files in this repository, for the same reason there are no
## image files: the project generates what it needs at load. That is partly a
## licensing decision — nothing here is sampled from anything, so there is no
## provenance to document — and partly practical, because a footstep set that
## varies by surface is six numbers here rather than thirty files.
##
## Everything is 22.05kHz mono 16-bit. Coarse by music standards and completely
## adequate for a door click, a footstep or an engine loop, and small enough to
## build during a load screen.
##
## Two shapes of sound: one-shots with an amplitude envelope, and loops that
## must join back to their own start without a click. The loop builders work in
## whole cycles or cross-fade their tails for exactly that reason.

const RATE := 22050

static var _cache: Dictionary = {}


## A cached stream by name. The builders are pure, so sharing is safe.
static func get_stream(id: StringName) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var stream := _build(id)
	_cache[id] = stream
	return stream


## Every name this bank answers to. The audio debug panel lists it, and a test
## walks it to prove nothing in the table is missing a builder.
static func ids() -> Array[StringName]:
	return [
		&"step_concrete", &"step_asphalt", &"step_wood", &"step_tile",
		&"step_carpet", &"step_grass",
		&"ui_click", &"ui_confirm", &"ui_back", &"ui_hover", &"ui_error", &"ui_notify",
		&"register", &"money", &"purchase", &"delivery",
		&"door", &"interact", &"car_door", &"sleep",
		&"engine_loop", &"engine_loop_heavy", &"engine_loop_light",
		&"brake", &"skid", &"impact_light", &"impact_medium", &"impact_heavy",
		&"siren", &"alert", &"busted",
		&"amb_city_day", &"amb_city_night", &"amb_park", &"amb_room",
		&"amb_store", &"amb_cafe",
		&"amb_kitchen", &"amb_gym", &"amb_venue",
	]


static func forget() -> void:
	_cache.clear()


static func _build(id: StringName) -> AudioStreamWAV:
	match id:
		# Footsteps: a filtered noise burst with a fast decay. The surface is
		# the filter and the decay, which is most of what tells concrete from
		# carpet without recording either.
		&"step_concrete":
			return _noise_hit(0.085, 0.35, 2600.0, 0.55)
		&"step_asphalt":
			return _noise_hit(0.090, 0.30, 2000.0, 0.60)
		&"step_wood":
			return _noise_hit(0.075, 0.42, 1500.0, 0.45, 220.0)
		&"step_tile":
			return _noise_hit(0.070, 0.40, 4200.0, 0.35)
		&"step_carpet":
			return _noise_hit(0.100, 0.18, 900.0, 0.85)
		&"step_grass":
			return _noise_hit(0.110, 0.22, 3400.0, 0.75)

		# Interface. Confirmations rise, cancellations fall — a convention
		# worth keeping because it needs no explaining.
		&"ui_click":
			return _blip(880.0, 0.045, 0.30)
		&"ui_confirm":
			return _sweep(520.0, 880.0, 0.13, 0.30)
		&"ui_back":
			return _sweep(660.0, 400.0, 0.11, 0.26)
		&"ui_hover":
			return _blip(1320.0, 0.028, 0.10)
		&"ui_error":
			return _sweep(320.0, 190.0, 0.20, 0.32)
		&"ui_notify":
			return _chime([784.0, 1046.0], 0.34, 0.24)

		# Money and business.
		&"register":
			return _chime([1046.0, 1568.0], 0.26, 0.30)
		&"money":
			return _chime([659.0, 988.0, 1318.0], 0.45, 0.26)
		&"purchase":
			return _blip(523.0, 0.09, 0.26)
		&"delivery":
			return _chime([440.0, 587.0], 0.30, 0.22)
		# Logistics. A shipment landing is a delivery an octave up, so the two
		# read as the same family of event; a shipment leaving is the same
		# interval the other way round.
		&"shipment_in":
			return _chime([587.0, 880.0], 0.32, 0.20)
		&"shipment_out":
			return _chime([880.0, 587.0], 0.28, 0.18)
		&"shutter":
			return _noise_hit(0.42, 0.30, 520.0, 0.85, 60.0)
		&"warning":
			return _chime([392.0, 330.0], 0.52, 0.22)

		# Crime and police. §130 asks for restraint, so these are short and
		# none of them loops: a rising pair when the heat goes up, the same
		# falling when it comes off, a low sweep when the police lose you and
		# start looking, a sharp one when they find you again.
		&"wanted_up":
			return _chime([440.0, 587.0, 740.0], 0.40, 0.24)
		&"wanted_down":
			return _chime([740.0, 587.0, 440.0], 0.44, 0.18)
		&"search_start":
			return _sweep(520.0, 240.0, 0.7, 0.16)
		&"reacquired":
			return _blip(880.0, 0.10, 0.28)
		&"wanted_clear":
			return _chime([523.0, 659.0, 880.0], 0.55, 0.20)
		&"reputation":
			return _chime([494.0, 622.0, 784.0], 0.60, 0.20)

		# Legal. §123 asks for subtle cues and explicitly not courtroom drama,
		# so these are quieter and flatter than the police set: a case opening
		# is two low notes, a reminder is a single soft one, a resolution
		# settles downward, and the record tier changing is the only one with
		# any weight to it.
		&"case_opened":
			return _chime([392.0, 330.0], 0.50, 0.16)
		&"court_reminder":
			return _blip(523.0, 0.14, 0.14)
		&"case_resolved":
			return _chime([587.0, 494.0, 392.0], 0.55, 0.16)
		&"record_tier":
			return _chime([330.0, 392.0, 466.0], 0.65, 0.18)
		&"scandal":
			return _sweep(420.0, 200.0, 0.6, 0.15)

		# Underworld career. §124 — restrained, and distinct from the legal set
		# by being brighter rather than louder.
		&"contact_trust":
			return _chime([659.0, 784.0], 0.36, 0.18)
		&"request_posted":
			return _blip(740.0, 0.09, 0.20)
		&"career_tier":
			return _chime([523.0, 659.0, 784.0, 988.0], 0.70, 0.18)

		# World interaction.
		&"door":
			return _noise_hit(0.22, 0.26, 1100.0, 0.70, 90.0)
		&"interact":
			return _blip(660.0, 0.05, 0.20)
		&"car_door":
			return _noise_hit(0.18, 0.34, 800.0, 0.55, 70.0)
		&"sleep":
			return _sweep(300.0, 120.0, 0.9, 0.18)

		# Vehicles.
		&"engine_loop":
			return _engine_loop(72.0)
		&"engine_loop_heavy":
			return _engine_loop(52.0)
		&"engine_loop_light":
			return _engine_loop(96.0)
		&"brake":
			return _noise_loop(0.6, 3200.0, 0.30)
		&"skid":
			return _noise_loop(0.5, 1800.0, 0.75)
		&"impact_light":
			return _noise_hit(0.16, 0.45, 1600.0, 0.60, 110.0)
		&"impact_medium":
			return _noise_hit(0.28, 0.70, 1100.0, 0.70, 80.0)
		&"impact_heavy":
			return _noise_hit(0.45, 0.95, 700.0, 0.80, 55.0)

		# Police.
		&"siren":
			return _siren_loop()
		&"alert":
			return _sweep(440.0, 880.0, 0.28, 0.34)
		&"busted":
			return _chime([392.0, 294.0, 196.0], 0.85, 0.34)

		# Ambience beds.
		&"amb_city_day":
			return _noise_loop(2.4, 620.0, 0.16, 0.35)
		&"amb_city_night":
			return _noise_loop(2.8, 400.0, 0.11, 0.45)
		&"amb_park":
			return _noise_loop(2.6, 1500.0, 0.10, 0.55)
		&"amb_room":
			return _noise_loop(2.2, 260.0, 0.07, 0.30)
		&"amb_store":
			return _hum_loop(120.0, 2.0, 0.09)
		&"amb_cafe":
			return _hum_loop(88.0, 2.0, 0.10)
		# Phase O rooms. All three are the same two builders the rest of the
		# beds use, at different frequencies — original synthesis, nothing
		# sampled, nothing licensed.
		&"amb_kitchen":
			# Extractor fan, and the clatter of a room with hard surfaces.
			return _hum_loop(146.0, 2.0, 0.11)
		&"amb_gym":
			return _noise_loop(2.6, 340.0, 0.08, 0.40)
		&"amb_venue":
			# A slow pulse under a low bed: the shape of music heard through a
			# wall, without being music. See §110.
			return _pulse_loop(58.0, 2.0, 0.13, 2.0)
		_:
			push_warning("ToneBank has no sound called '%s'." % id)
			return _blip(440.0, 0.05, 0.1)


# --- Builders --------------------------------------------------------------

## A low tone that swells and falls on a fixed beat. Deliberately not a tune:
## it is the felt part of a room with a system in it, and it is ours.
static func _pulse_loop(
	hz: float, seconds: float, amplitude: float, beats_per_second: float
) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var data := PackedFloat32Array()
	data.resize(count)
	for i in count:
		var t := float(i) / RATE
		var beat := 0.55 + 0.45 * pow(maxf(sin(TAU * beats_per_second * t * 0.5), 0.0), 2.0)
		var body := sin(TAU * hz * t) * 0.7 + sin(TAU * hz * 2.0 * t) * 0.3
		data[i] = body * beat * amplitude
	return _to_stream(data, true)

## A burst of noise through a one-pole low-pass, with an optional resonant thump
## under it. The workhorse: footsteps, doors, impacts.
static func _noise_hit(
	seconds: float, amplitude: float, cutoff: float, decay_shape: float,
	thump_hz: float = 0.0
) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var data := PackedFloat32Array()
	data.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%f%f%f" % [seconds, cutoff, amplitude])

	var alpha: float = clampf(cutoff / float(RATE), 0.0, 1.0)
	var filtered := 0.0
	for i in count:
		var t := float(i) / float(count)
		filtered += alpha * (rng.randf_range(-1.0, 1.0) - filtered)
		# Below 1 is a sharp click, above it a softer brush.
		var envelope := pow(1.0 - t, 1.0 + decay_shape * 5.0)
		var value := filtered * envelope
		if thump_hz > 0.0:
			value += sin(TAU * thump_hz * float(i) / float(RATE)) * envelope * 0.55
		data[i] = value * amplitude
	return _to_stream(data, false)


static func _blip(hz: float, seconds: float, amplitude: float) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var data := PackedFloat32Array()
	data.resize(count)
	for i in count:
		var t := float(i) / float(count)
		var envelope: float = minf(t * 12.0, 1.0) * pow(1.0 - t, 2.2)
		data[i] = sin(TAU * hz * float(i) / float(RATE)) * envelope * amplitude
	return _to_stream(data, false)


static func _sweep(
	from_hz: float, to_hz: float, seconds: float, amplitude: float
) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var data := PackedFloat32Array()
	data.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var hz := lerpf(from_hz, to_hz, t * t)
		phase += TAU * hz / float(RATE)
		var envelope: float = minf(t * 14.0, 1.0) * pow(1.0 - t, 1.8)
		data[i] = sin(phase) * envelope * amplitude
	return _to_stream(data, false)


## Notes struck in quick succession and left to ring, so a chime arpeggiates
## rather than landing as one chord.
static func _chime(notes: Array, seconds: float, amplitude: float) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var data := PackedFloat32Array()
	data.resize(count)
	for i in count:
		var t := float(i) / float(count)
		var value := 0.0
		for n in notes.size():
			var start := float(n) / float(notes.size()) * 0.35
			if t < start:
				continue
			var local := (t - start) / maxf(1.0 - start, 0.001)
			var envelope: float = minf(local * 20.0, 1.0) * pow(1.0 - local, 2.6)
			value += sin(TAU * float(notes[n]) * float(i) / float(RATE)) * envelope
		data[i] = value / float(notes.size()) * amplitude
	return _to_stream(data, false)


## Filtered noise that loops seamlessly: the tail is cross-faded into the head
## so the join is inaudible. Wind, room tone, tyre scrub.
static func _noise_loop(
	seconds: float, cutoff: float, amplitude: float, smoothing: float = 0.5
) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var data := PackedFloat32Array()
	data.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("loop%f%f" % [seconds, cutoff])
	var alpha: float = clampf(cutoff / float(RATE), 0.0, 1.0)
	var filtered := 0.0
	for i in count:
		filtered += alpha * (rng.randf_range(-1.0, 1.0) - filtered)
		data[i] = filtered * amplitude

	var fade := maxi(int(float(count) * 0.1 * clampf(smoothing, 0.05, 1.0)), 1)
	for i in fade:
		var mix := float(i) / float(fade)
		data[i] = lerpf(data[count - fade + i], data[i], mix)
	return _to_stream(data, true)


## A low harmonic drone: fridges, coffee machines, plant rooms — the sound a
## building makes when nothing is happening in it. Whole cycles only, so the
## loop point lands on a zero crossing.
static func _hum_loop(hz: float, seconds: float, amplitude: float) -> AudioStreamWAV:
	var cycles := maxi(int(hz * seconds), 1)
	var count := int(round(float(cycles) * float(RATE) / hz))
	var data := PackedFloat32Array()
	data.resize(count)
	for i in count:
		var phase := TAU * hz * float(i) / float(RATE)
		data[i] = (
			sin(phase) * 0.6 + sin(phase * 2.0) * 0.25 + sin(phase * 3.0) * 0.12
		) * amplitude
	return _to_stream(data, true)


## An engine: a soft sawtooth at the firing frequency with rumble on it,
## harmonically rich enough to sound mechanical without the buzz of a hard edge.
## Whole cycles, so it can be pitch-shifted without the loop drifting.
static func _engine_loop(hz: float) -> AudioStreamWAV:
	var cycles := 8
	var count := int(round(float(cycles) * float(RATE) / hz))
	var data := PackedFloat32Array()
	data.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hz)
	var rumble := 0.0
	for i in count:
		var phase := fmod(hz * float(i) / float(RATE), 1.0)
		var saw := phase * 2.0 - 1.0
		saw = saw - saw * saw * saw * 0.4
		rumble += 0.08 * (rng.randf_range(-1.0, 1.0) - rumble)
		data[i] = saw * 0.34 + rumble * 0.22
	return _to_stream(data, true)


## Two tones alternating: the two-note emergency pattern, built as one loop so a
## car's siren needs one player and no scheduling.
static func _siren_loop() -> AudioStreamWAV:
	var half := 0.42
	var count := int(RATE * half * 2.0)
	var data := PackedFloat32Array()
	data.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var hz := 740.0 if t < half else 588.0
		phase += TAU * hz / float(RATE)
		# A short ramp at each change, so the switch is a note change rather
		# than a click.
		var since := fmod(t, half)
		var envelope: float = (
			clampf(since * 40.0, 0.0, 1.0) * clampf((half - since) * 40.0, 0.0, 1.0)
		)
		data[i] = (sin(phase) * 0.7 + sin(phase * 2.0) * 0.3) * envelope * 0.34
	return _to_stream(data, true)


static func _to_stream(data: PackedFloat32Array, looping: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = data.size()
	return stream
