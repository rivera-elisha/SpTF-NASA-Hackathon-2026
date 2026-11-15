extends RefCounted

## Shared procedural animations, VFX bursts, synth SFX, and [E] interactable
## helpers used across outpost rooms and the Mars exterior map.

static var _sfx_cache: Dictionary = {}


static func play_sfx(host: Node, kind: String, volume_db: float = -8.0) -> void:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = _get_or_build_sfx(kind)
	player.volume_db = volume_db
	host.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


static func _get_or_build_sfx(kind: String) -> AudioStreamWAV:
	if _sfx_cache.has(kind):
		return _sfx_cache[kind]

	var sample_rate := 22050
	var samples := PackedFloat32Array()
	match kind:
		"interact":
			samples = _synth_chirp(sample_rate, 0.14, 620.0, 960.0, 0.25)
		"scan":
			samples = _synth_chirp(sample_rate, 0.28, 420.0, 1240.0, 0.22)
		"heal":
			samples = _synth_arpeggio(sample_rate, [523.25, 659.25, 783.99, 1046.5], 0.08, 0.26)
		"success":
			samples = _synth_arpeggio(sample_rate, [587.33, 739.99, 880.0, 1174.66], 0.09, 0.28)
		"step":
			samples = _synth_noise_hit(sample_rate, 0.06, 0.18, 220.0)
		"lift":
			samples = _synth_chirp(sample_rate, 0.22, 180.0, 520.0, 0.30)
		"flame":
			samples = _synth_noise_hit(sample_rate, 0.26, 0.24, 340.0)
		"mist":
			samples = _synth_noise_hit(sample_rate, 0.24, 0.18, 0.0)
		"snooze":
			samples = _synth_arpeggio(sample_rate, [392.0, 329.63, 261.63], 0.14, 0.20)
		"pickup":
			samples = _synth_arpeggio(sample_rate, [659.25, 987.77, 1318.5], 0.07, 0.24)
		_:
			samples = _synth_chirp(sample_rate, 0.12, 500.0, 760.0, 0.22)

	var wav := _build_pcm_wav(samples, sample_rate)
	_sfx_cache[kind] = wav
	return wav


static func _synth_chirp(
	sample_rate: int,
	duration: float,
	f0: float,
	f1: float,
	amp: float
) -> PackedFloat32Array:
	var count := int(duration * sample_rate)
	var data := PackedFloat32Array()
	data.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / maxf(1.0, float(count))
		var freq := lerpf(f0, f1, t)
		phase += TAU * freq / float(sample_rate)
		var env := sin(PI * t)
		data[i] = sin(phase) * env * amp
	return data


static func _synth_arpeggio(
	sample_rate: int,
	notes: Array,
	note_dur: float,
	amp: float
) -> PackedFloat32Array:
	var note_samples := int(note_dur * sample_rate)
	var total := note_samples * notes.size()
	var data := PackedFloat32Array()
	data.resize(total)
	for n in notes.size():
		var freq := float(notes[n])
		var phase := 0.0
		var offset := n * note_samples
		for i in note_samples:
			var t := float(i) / maxf(1.0, float(note_samples))
			phase += TAU * freq / float(sample_rate)
			var env := pow(1.0 - t, 0.55) * minf(1.0, t * 14.0)
			data[offset + i] = (sin(phase) * 0.75 + sin(phase * 2.0) * 0.25) * env * amp
	return data


static func _synth_noise_hit(
	sample_rate: int,
	duration: float,
	amp: float,
	tone_hz: float
) -> PackedFloat32Array:
	var count := int(duration * sample_rate)
	var data := PackedFloat32Array()
	data.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4049
	var phase := 0.0
	for i in count:
		var t := float(i) / maxf(1.0, float(count))
		var env := pow(1.0 - t, 1.3) * minf(1.0, t * 20.0)
		var sample := rng.randf_range(-1.0, 1.0) * 0.65
		if tone_hz > 0.0:
			phase += TAU * lerpf(tone_hz, tone_hz * 0.45, t) / float(sample_rate)
			sample += sin(phase) * 0.45
		data[i] = sample * env * amp
	return data


static func _build_pcm_wav(samples: PackedFloat32Array, mix_rate: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var clamped := clampf(samples[i], -1.0, 1.0)
		var pcm := int(round(clamped * 32767.0))
		bytes.encode_s16(i * 2, pcm)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream


static func spawn_burst_vfx(
	parent: Node,
	gpos: Vector2,
	color: Color,
	amount: int = 18,
	vel_max: float = 72.0,
	particle_scale: float = 3.2,
	gravity: Vector2 = Vector2(0, 20),
	lifetime: float = 0.65
) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var p := CPUParticles2D.new()
	p.global_position = gpos
	p.z_index = 18
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = lifetime
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = vel_max * 0.35
	p.initial_velocity_max = vel_max
	p.gravity = gravity
	p.scale_amount_min = particle_scale * 0.6
	p.scale_amount_max = particle_scale * 1.25
	p.color = color
	parent.add_child(p)
	p.emitting = true
	var timer := parent.get_tree().create_timer(lifetime + 0.35)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)


static func spawn_ring_vfx(
	parent: Node,
	gpos: Vector2,
	color: Color = Color(0.45, 0.9, 1.0, 0.9),
	max_radius: float = 34.0,
	duration: float = 0.45
) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var ring := _RingPulseVFX.new()
	ring.global_position = gpos
	ring.z_index = 17
	ring.ring_color = color
	ring.max_radius = max_radius
	ring.duration = duration
	parent.add_child(ring)


static func spawn_scan_beam_vfx(
	parent: Node,
	gpos: Vector2,
	color: Color = Color(0.3, 1.0, 0.72, 0.85),
	width: float = 42.0,
	height: float = 54.0,
	duration: float = 0.7
) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var beam := _ScanBeamVFX.new()
	beam.global_position = gpos
	beam.z_index = 18
	beam.beam_color = color
	beam.beam_width = width
	beam.beam_height = height
	beam.duration = duration
	parent.add_child(beam)


static func spawn_floating_text(
	parent: Node,
	gpos: Vector2,
	text: String,
	color: Color = Color(0.7, 0.96, 1.0, 1.0),
	duration: float = 1.15
) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var holder := Node2D.new()
	holder.global_position = gpos + Vector2(-90, -24)
	holder.z_index = 20

	var label := Label.new()
	label.text = text
	label.size = Vector2(180, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.14, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	holder.add_child(label)
	parent.add_child(holder)

	var tween := holder.create_tween()
	tween.set_parallel(true)
	tween.tween_property(holder, "global_position:y", holder.global_position.y - 26.0, duration)
	tween.tween_property(holder, "modulate:a", 0.0, duration).set_delay(duration * 0.45)
	tween.chain().tween_callback(holder.queue_free)


static func attach_ambient_fx(
	target_sprite: Node2D,
	mode: String,
	fx_offset: Vector2 = Vector2.ZERO,
	fx_size: Vector2 = Vector2(40, 40)
) -> Node2D:
	if not is_instance_valid(target_sprite):
		return null
	var fx := _AmbientSpriteFX.new()
	fx.name = "AmbientFX_" + mode
	fx.mode = mode
	fx.fx_offset = fx_offset
	fx.fx_size = fx_size
	fx.z_index = 4
	# Counteract huge scale differences when attached directly to scaled Sprite2Ds
	target_sprite.add_child(fx)
	return fx


static func attach_world_fx(
	parent: Node2D,
	gpos: Vector2,
	mode: String,
	fx_size: Vector2 = Vector2(48, 48)
) -> Node2D:
	var fx := _AmbientSpriteFX.new()
	fx.name = "WorldFX_" + mode + "_" + str(randi() % 9999)
	fx.mode = mode
	fx.fx_size = fx_size
	fx.z_index = 5
	parent.add_child(fx)
	fx.global_position = gpos
	return fx


static func create_interact_manager(
	scene_root: Node,
	player: Node2D,
	is_blocked_fn: Callable = Callable()
) -> InteractManager:
	var mgr := InteractManager.new()
	mgr.name = "InteractManager"
	mgr.player = player
	mgr.is_blocked_fn = is_blocked_fn
	scene_root.add_child(mgr)
	return mgr


class InteractManager extends Node2D:
	var player: Node2D
	var is_blocked_fn: Callable
	var entries: Array[Dictionary] = []
	var active_entry: Dictionary = {}
	var prompt_node: Node2D
	var prompt_panel: PanelContainer
	var prompt_label: Label
	var bracket_fx: _SelectionBracketFX
	var _pulse_time := 0.0

	func _ready() -> void:
		z_index = 25
		prompt_node = Node2D.new()
		prompt_node.visible = false
		prompt_node.z_index = 30

		prompt_panel = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.1, 0.2, 0.92)
		sb.border_color = Color(0.42, 0.85, 1.0, 0.95)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(5)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		prompt_panel.add_theme_stylebox_override("panel", sb)

		prompt_label = Label.new()
		prompt_label.add_theme_font_size_override("font_size", 11)
		prompt_label.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
		prompt_panel.add_child(prompt_label)
		prompt_node.add_child(prompt_panel)
		add_child(prompt_node)

		bracket_fx = _SelectionBracketFX.new()
		bracket_fx.visible = false
		bracket_fx.z_index = 14
		add_child(bracket_fx)

	func add_interactable(
		id: String,
		world_pos: Vector2,
		prompt_text: String,
		callback: Callable,
		radius: float = 72.0,
		box_size: Vector2 = Vector2(56, 56),
		condition: Callable = Callable()
	) -> void:
		entries.append({
			"id": id,
			"pos": world_pos,
			"prompt": prompt_text,
			"callback": callback,
			"radius": radius,
			"box_size": box_size,
			"condition": condition,
		})

	func _process(delta: float) -> void:
		_pulse_time += delta
		if not is_instance_valid(player) or (is_blocked_fn.is_valid() and bool(is_blocked_fn.call())):
			prompt_node.visible = false
			bracket_fx.visible = false
			active_entry = {}
			return

		var best: Dictionary = {}
		var best_dist := INF
		for item in entries:
			var cond: Callable = item["condition"]
			if cond.is_valid() and not bool(cond.call()):
				continue
			var d := player.global_position.distance_to(item["pos"])
			if d <= float(item["radius"]) and d < best_dist:
				best_dist = d
				best = item

		active_entry = best
		if active_entry.is_empty():
			prompt_node.visible = false
			bracket_fx.visible = false
			return

		var target_pos: Vector2 = active_entry["pos"]
		var sz: Vector2 = active_entry["box_size"]
		prompt_label.text = "[E] %s" % str(active_entry["prompt"])
		prompt_panel.reset_size()
		var bob := sin(_pulse_time * 4.2) * 2.5
		prompt_node.global_position = target_pos + Vector2(-prompt_panel.size.x * 0.5, -sz.y * 0.5 - 28.0 + bob)
		prompt_node.visible = true

		bracket_fx.global_position = target_pos
		bracket_fx.box_size = sz
		bracket_fx.visible = true
		bracket_fx.queue_redraw()

	func _unhandled_input(event: InputEvent) -> void:
		if not event.is_action_pressed("interact") or event.is_echo():
			return
		if active_entry.is_empty():
			return
		if is_blocked_fn.is_valid() and bool(is_blocked_fn.call()):
			return
		get_viewport().set_input_as_handled()
		var cb: Callable = active_entry["callback"]
		var target_pos: Vector2 = active_entry["pos"]
		_play_interact_sfx()
		var ring := _RingPulseVFX.new()
		ring.global_position = target_pos
		ring.z_index = 17
		ring.ring_color = Color(0.4, 0.9, 1.0, 0.9)
		ring.max_radius = 28.0
		ring.duration = 0.36
		add_child(ring)
		if cb.is_valid():
			cb.call()

	func _play_interact_sfx() -> void:
		var stream := preload("res://Scripts/interactive_assets.gd")._get_or_build_sfx("interact") if false else null
		# Built inline to avoid cyclic script reference while sharing audio cache cleanly
		var ap := AudioStreamPlayer.new()
		ap.volume_db = -10.0
		var sr := 22050
		var cnt := int(0.12 * sr)
		var bytes := PackedByteArray()
		bytes.resize(cnt * 2)
		var ph := 0.0
		for i in cnt:
			var t := float(i) / float(cnt)
			ph += TAU * lerpf(620.0, 960.0, t) / float(sr)
			bytes.encode_s16(i * 2, int(round(sin(ph) * sin(PI * t) * 0.25 * 32767.0)))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = sr
		wav.data = bytes
		ap.stream = wav
		add_child(ap)
		ap.finished.connect(ap.queue_free)
		ap.play()


class _SelectionBracketFX extends Node2D:
	var box_size := Vector2(56, 56)
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta

	func _draw() -> void:
		var pulse := 1.0 + sin(_t * 5.0) * 0.05
		var half := box_size * 0.5 * pulse
		var corner := 8.0
		var col := Color(0.45, 0.92, 1.0, 0.85)
		var corners := [
			[Vector2(-half.x, -half.y), Vector2(1, 0), Vector2(0, 1)],
			[Vector2(half.x, -half.y), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(-half.x, half.y), Vector2(1, 0), Vector2(0, -1)],
			[Vector2(half.x, half.y), Vector2(-1, 0), Vector2(0, -1)],
		]
		for c in corners:
			var p: Vector2 = c[0]
			var dx: Vector2 = c[1]
			var dy: Vector2 = c[2]
			draw_line(p, p + dx * corner, col, 2.0)
			draw_line(p, p + dy * corner, col, 2.0)


class _RingPulseVFX extends Node2D:
	var ring_color := Color(0.45, 0.9, 1.0, 0.9)
	var max_radius := 34.0
	var duration := 0.45
	var _elapsed := 0.0

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := clampf(_elapsed / maxf(0.01, duration), 0.0, 1.0)
		var r := lerpf(6.0, max_radius, 1.0 - pow(1.0 - t, 2.0))
		var col := ring_color
		col.a = (1.0 - t) * ring_color.a
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, lerpf(3.2, 1.0, t))


class _ScanBeamVFX extends Node2D:
	var beam_color := Color(0.3, 1.0, 0.72, 0.85)
	var beam_width := 42.0
	var beam_height := 54.0
	var duration := 0.7
	var _elapsed := 0.0

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := clampf(_elapsed / maxf(0.01, duration), 0.0, 1.0)
		var y := lerpf(-beam_height * 0.5, beam_height * 0.5, sin(t * PI))
		var alpha := (1.0 - pow(absf(t - 0.5) * 2.0, 2.0))
		var glow := beam_color
		glow.a = alpha * 0.35
		draw_rect(Rect2(-beam_width * 0.5, y - 5.0, beam_width, 10.0), glow, true)
		var line_col := beam_color
		line_col.a = alpha * 0.95
		draw_line(Vector2(-beam_width * 0.55, y), Vector2(beam_width * 0.55, y), line_col, 2.2)


class _AmbientSpriteFX extends Node2D:
	var mode := "monitor_radar"
	var fx_offset := Vector2.ZERO
	var fx_size := Vector2(48, 48)
	var _t := 0.0
	var _motes: Array[Dictionary] = []

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(mode) + int(global_position.x)
		for i in 10:
			_motes.append({
				"x": rng.randf_range(-0.42, 0.42),
				"y": rng.randf_range(-0.42, 0.42),
				"spd": rng.randf_range(0.25, 0.65),
				"phase": rng.randf_range(0.0, TAU),
				"r": rng.randf_range(1.2, 2.4),
			})

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := fx_offset
		var hw := fx_size.x * 0.5
		var hh := fx_size.y * 0.5
		match mode:
			"monitor_radar":
				# Radar sweep + telemetry bars + carrier blink
				var radar_c := c + Vector2(hw * 0.34, hh * 0.25)
				var rr := minf(hw, hh) * 0.30
				var sweep_ang := fmod(_t * 2.4, TAU)
				draw_arc(radar_c, rr, 0.0, TAU, 20, Color(0.25, 0.95, 0.45, 0.32), 1.2)
				draw_line(radar_c, radar_c + Vector2(cos(sweep_ang), sin(sweep_ang)) * rr, Color(0.4, 1.0, 0.55, 0.85), 1.6)
				# Telemetry text lines on left screen
				for row in 4:
					var w := hw * (0.28 + 0.14 * sin(_t * 3.0 + float(row) * 1.4))
					var lp := c + Vector2(-hw * 0.62, -hh * 0.48 + float(row) * 4.5)
					draw_line(lp, lp + Vector2(maxf(5.0, w), 0.0), Color(0.35, 1.0, 0.5, 0.68), 1.6)
				# Urgent static or link LED
				var urgent := bool(get_meta("urgent_mode", false))
				var blink := sin(_t * (12.0 if urgent else 3.2)) > 0.0
				var led_col := Color(1.0, 0.38, 0.25, 0.95) if urgent else Color(0.25, 1.0, 0.55, 0.9)
				if blink:
					draw_circle(c + Vector2(hw * 0.55, -hh * 0.55), 2.8, led_col)
				if urgent:
					var arc_r := fmod(_t * 22.0, 26.0) + 6.0
					draw_arc(c, arc_r, -0.7, 0.7, 12, Color(1.0, 0.55, 0.25, 1.0 - (arc_r - 6.0) / 26.0), 1.8)

			"monitor_vitals":
				# Moving ECG pulse trace + cyan scan bar
				var y0 := c.y - hh * 0.1
				var pts := PackedVector2Array()
				for i in 18:
					var u := float(i) / 17.0
					var px := lerpf(c.x - hw * 0.46, c.x + hw * 0.46, u)
					var phase := fmod(u * 2.2 - _t * 1.4, 1.0)
					if phase < 0.0:
						phase += 1.0
					var bump := 0.0
					if phase > 0.42 and phase < 0.58:
						bump = sin((phase - 0.42) / 0.16 * TAU) * (hh * 0.26)
					pts.append(Vector2(px, y0 - bump))
				draw_polyline(pts, Color(0.28, 1.0, 0.62, 0.9), 1.6)
				if sin(_t * 4.0) > 0.15:
					draw_circle(c + Vector2(hw * 0.36, -hh * 0.45), 2.5, Color(0.3, 0.95, 1.0, 0.9))

			"server_racks":
				# Cascading server activity LEDs
				for i in 8:
					var row := int(i / 2)
					var col_idx := i % 2
					var on := sin(_t * (5.2 + float(i) * 0.7) + float(i)) > 0.05
					if on:
						var pos := c + Vector2(-hw * 0.25 + float(col_idx) * hw * 0.5, -hh * 0.45 + float(row) * hh * 0.28)
						var c_led := Color(0.25, 0.85, 1.0, 0.9) if (i % 3 == 0) else (Color(0.35, 1.0, 0.45, 0.9) if (i % 2 == 0) else Color(1.0, 0.72, 0.25, 0.9))
						draw_circle(pos, 2.2, c_led)

			"reactor_engine":
				var pulse := 0.5 + 0.5 * sin(_t * 4.5)
				draw_circle(c, minf(hw, hh) * (0.28 + pulse * 0.08), Color(1.0, 0.58, 0.18, 0.18 + pulse * 0.12))
				for i in 3:
					var py := c.y - hh * 0.35 + fmod(_t * 14.0 + float(i) * 9.0, 22.0) * -1.0
					var px := c.x + sin(_t * 3.0 + float(i) * 2.1) * (hw * 0.28)
					draw_circle(Vector2(px, py), 1.8, Color(0.55, 0.92, 1.0, 0.7))

			"scrubber_panel":
				for i in 6:
					var gx := -hw * 0.25 + float(i % 2) * hw * 0.42
					var gy := -hh * 0.3 + float(int(i / 2)) * hh * 0.28
					var active := sin(_t * 3.6 + float(i) * 1.1) > 0.0
					if active:
						draw_circle(c + Vector2(gx, gy), 2.1, Color(0.32, 0.95, 0.88, 0.88))

			"eva_suit":
				# Visor glint line + chest LED
				var glint_u := fmod(_t * 0.55, 2.6)
				if glint_u < 1.0:
					var x_g := lerpf(c.x - hw * 0.28, c.x + hw * 0.28, glint_u)
					draw_line(Vector2(x_g, c.y - hh * 0.55), Vector2(x_g + 4.0, c.y - hh * 0.36), Color(0.82, 0.96, 1.0, 0.8), 2.0)
				var chest_col := Color(0.25, 0.88, 1.0, 0.85) if sin(_t * 2.8) > 0.0 else Color(0.25, 1.0, 0.55, 0.8)
				draw_circle(c + Vector2(0, -hh * 0.05), 2.1, chest_col)

			"treadmill":
				var fast := bool(get_meta("fast_mode", false))
				var belt_spd := 48.0 if fast else 12.0
				var stripe_col := Color(0.32, 0.95, 1.0, 0.78 if fast else 0.35)
				for i in 4:
					var u := fmod((_t * belt_spd / maxf(1.0, fx_size.x)) + float(i) * 0.25, 1.0)
					var sx := lerpf(c.x - hw * 0.45, c.x + hw * 0.45, 1.0 - u)
					draw_line(Vector2(sx, c.y - 6.0), Vector2(sx, c.y + 6.0), stripe_col, 2.0 if fast else 1.2)
				draw_circle(c + Vector2(-hw * 0.4, -hh * 0.45), 2.4, Color(0.35, 1.0, 0.5, 0.9))

			"ared":
				var active := bool(get_meta("active_mode", false))
				var pulse := 0.5 + 0.5 * sin(_t * (9.0 if active else 2.2))
				var col := Color(1.0, 0.78, 0.22, 0.72) if active else Color(0.38, 0.86, 1.0, 0.42)
				var lift_y := c.y + lerpf(5.0, -9.0, pulse)
				draw_line(Vector2(c.x - hw * 0.5, lift_y), Vector2(c.x + hw * 0.5, lift_y), col, 2.8 if active else 1.6)
				draw_circle(Vector2(c.x - hw * 0.36, c.y - hh * 0.2), 2.6, col)
				draw_circle(Vector2(c.x + hw * 0.36, c.y - hh * 0.2), 2.6, col)

			"medical_cab":
				var glow := 0.45 + 0.55 * sin(_t * 2.5)
				draw_circle(c, minf(hw, hh) * 0.32, Color(0.3, 0.88, 1.0, 0.14 * glow))
				draw_rect(Rect2(c.x - 1.5, c.y - 5.5, 3.0, 11.0), Color(0.35, 1.0, 0.65, 0.75 * glow), true)
				draw_rect(Rect2(c.x - 5.5, c.y - 1.5, 11.0, 3.0), Color(0.35, 1.0, 0.65, 0.75 * glow), true)

			"bed_berth":
				var alpha := 0.35 + 0.45 * (0.5 + 0.5 * sin(_t * 1.8))
				draw_circle(c + Vector2(0, -hh * 0.4), 2.4, Color(0.5, 0.78, 1.0, alpha))

			"galley":
				var warm := 0.5 + 0.5 * sin(_t * 2.6)
				draw_circle(c + Vector2(hw * 0.2, -hh * 0.35), 2.2, Color(1.0, 0.72, 0.28, 0.45 + 0.4 * warm))
				for i in 3:
					var u := fmod(_t * 0.45 + float(i) * 0.33, 1.0)
					var sx := c.x + sin(_t * 2.0 + float(i)) * 4.0
					var sy := c.y - hh * 0.3 - u * 16.0
					draw_circle(Vector2(sx, sy), 1.6, Color(0.95, 0.96, 1.0, (1.0 - u) * 0.45))

			"hygiene_rack":
				var seal := sin(_t * 2.1) > 0.0
				draw_circle(c + Vector2(4.0, -4.0), 2.4, Color(0.28, 1.0, 0.48, 0.85) if seal else Color(1.0, 0.35, 0.28, 0.85))
				var ang := -0.8 + sin(_t * 3.1) * 0.5
				draw_line(c + Vector2(-10.0, -14.0), c + Vector2(-10.0, -14.0) + Vector2(cos(ang), sin(ang)) * 5.0, Color(0.75, 0.95, 1.0, 0.8), 1.3)

			"glovebox":
				draw_rect(Rect2(c - fx_size * 0.32, fx_size * 0.64), Color(0.32, 0.9, 1.0, 0.14), true)
				for m in _motes:
					var px := c.x + float(m["x"]) * hw * 1.1 + sin(_t * float(m["spd"]) + float(m["phase"])) * 4.0
					var py := c.y + float(m["y"]) * hh * 0.9 + cos(_t * float(m["spd"]) + float(m["phase"])) * 4.0
					draw_circle(Vector2(px, py), float(m["r"]), Color(0.6, 0.96, 1.0, 0.72))

			"combustion_rack":
				# Spherical microgravity cool-flame orb pulsing inside chamber
				var flicker := 0.82 + 0.18 * sin(_t * 11.0) * cos(_t * 6.3)
				var fpos := c + Vector2(0, 2.0)
				draw_circle(fpos, 11.0 * flicker, Color(0.25, 0.62, 1.0, 0.22))
				draw_circle(fpos, 6.8 * flicker, Color(0.35, 0.82, 1.0, 0.55))
				draw_circle(fpos, 3.4 * flicker, Color(1.0, 0.76, 0.35, 0.88))

			"greenhouse":
				# Hydroponic UV grow shimmer + rising O2 bubbles
				var grow := 0.5 + 0.5 * sin(_t * 1.9)
				draw_rect(Rect2(c - fx_size * 0.42, fx_size * 0.84), Color(0.55, 1.0, 0.62, 0.10 + grow * 0.08), true)
				for i in 5:
					var u := fmod(_t * 0.38 + float(i) * 0.2, 1.0)
					var bx := c.x + lerpf(-hw * 0.6, hw * 0.6, float(i) / 4.0) + sin(_t * 2.0 + float(i)) * 3.0
					var by := c.y + hh * 0.2 - u * (hh * 0.9)
					draw_circle(Vector2(bx, by), 1.8, Color(0.65, 1.0, 0.78, (1.0 - u) * 0.7))

			"comms_phone":
				var urgent := bool(get_meta("urgent_mode", false))
				var col := Color(1.0, 0.45, 0.25, 0.92) if urgent else Color(0.3, 0.92, 1.0, 0.82)
				if sin(_t * (10.0 if urgent else 2.5)) > 0.0:
					draw_circle(c + Vector2(14.0, -14.0), 2.8, col)

			"mars_rover":
				# Optical MastCam lens glint + mast telemetry LED
				var glint := fmod(_t * 0.45, 3.0)
				var mast_pos := c + Vector2(-hw * 0.56, -hh * 0.52)
				if glint < 0.7:
					var a := sin(glint / 0.7 * PI)
					draw_circle(mast_pos, 5.5, Color(0.38, 0.95, 1.0, 0.75 * a))
					draw_line(mast_pos + Vector2(2, 0), mast_pos + Vector2(22, 8), Color(1.0, 0.32, 0.28, 0.45 * a), 1.4)
				if sin(_t * 4.0) > 0.0:
					draw_circle(c + Vector2(-hw * 0.2, -hh * 0.1), 2.0, Color(0.3, 1.0, 0.6, 0.85))

			"building_beacon":
				var dusty := bool(get_meta("dusty_mode", false))
				var pulse := 0.5 + 0.5 * sin(_t * (6.0 if dusty else 2.2))
				var col := Color(1.0, 0.62, 0.2, 0.55 + pulse * 0.35) if dusty else Color(0.3, 1.0, 0.58, 0.45 + pulse * 0.35)
				draw_circle(c, 3.2, col)
				draw_arc(c, 5.0 + pulse * 3.0, 0.0, TAU, 16, Color(col.r, col.g, col.b, (1.0 - pulse) * 0.45), 1.2)

			"solar_panel_glint":
				var top_dirty := bool(get_meta("dirty_top", false))
				var bot_dirty := bool(get_meta("dirty_bottom", false))
				for idx in 2:
					var dirty: bool = top_dirty if idx == 0 else bot_dirty
					var py: float = c.y + (-hh * 0.52 if idx == 0 else hh * 0.52)
					if dirty:
						var blink := 0.5 + 0.5 * sin(_t * 6.5 + float(idx))
						draw_circle(Vector2(c.x + hw * 0.62, py), 3.6, Color(1.0, 0.68, 0.22, 0.45 + blink * 0.45))
					else:
						var sweep := fmod(_t * 0.55 + float(idx) * 0.5, 2.8)
						if sweep < 1.0:
							var gx := lerpf(c.x - hw * 0.72, c.x + hw * 0.72, sweep)
							draw_line(Vector2(gx, py - 8.0), Vector2(gx + 10.0, py + 8.0), Color(0.8, 0.96, 1.0, 0.72), 2.2)

			"rocket_cryo":
				var active := bool(get_meta("rocket_ready", false))
				for i in 4:
					var u := fmod(_t * 0.42 + float(i) * 0.25, 1.0)
					var vx := c.x + sin(_t * 2.0 + float(i) * 1.7) * 8.0 - u * 18.0
					var vy := c.y - u * 26.0
					draw_circle(Vector2(vx, vy), lerpf(2.2, 6.0, u), Color(0.85, 0.95, 1.0, (1.0 - u) * 0.28))
				if active:
					var p_col := Color(0.32, 1.0, 0.62, 0.4 + 0.4 * sin(_t * 6.0))
					draw_arc(c + Vector2(0, hh * 0.6), 24.0, 0.0, TAU, 24, p_col, 2.0)
