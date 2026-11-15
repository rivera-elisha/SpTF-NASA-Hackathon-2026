class_name PowerWashMinigame
extends CanvasLayer

signal washed_progress(panel_id: int, progress: float)
signal completed(panel_id: int)
signal cancelled(panel_id: int)

const PANEL_TEXTURE_PATH := "res://Assets/newsolarpanels.png"
const MASK_W := 130
const MASK_H := 62
const CANVAS_W := 520.0
const CANVAS_H := 248.0
const AUTO_FINISH_THRESHOLD := 0.95

var panel_id := 0
var turbo_nozzle := false
var is_spraying := false
var has_prev_cursor := false
var cursor_local := Vector2(CANVAS_W * 0.5, CANVAS_H * 0.5)
var prev_cursor_local := Vector2.ZERO
var _finishing := false

var total_dirty_pixels := 0
var remaining_dirty_pixels := 0
var mask_image: Image
var mask_texture: ImageTexture
var active_mask: PackedByteArray

var _canvas: Control
var _clean_bar: ProgressBar
var _pct_label: Label
var _nozzle_btn: Button
var _hint_label: Label
var _spray_player: AudioStreamPlayer
var _sparkle_time := 0.0
var _particles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	layer = 25


func _ready() -> void:
	_build_ui()
	_build_spray_audio()


func start_for_panel(target_panel_id: int) -> void:
	panel_id = target_panel_id
	_finishing = false
	is_spraying = false
	has_prev_cursor = false
	_particles.clear()
	_rng.seed = 9001 + panel_id * 1337
	_generate_dust_mask()
	_update_progress_ui()


func get_clean_progress() -> float:
	if total_dirty_pixels <= 0:
		return 1.0
	return clampf(1.0 - float(remaining_dirty_pixels) / float(total_dirty_pixels), 0.0, 1.0)


func apply_spray_stroke(from_local: Vector2, to_local: Vector2) -> void:
	if _finishing or mask_image == null:
		return
	var steps := maxi(1, int(ceil(from_local.distance_to(to_local) / 6.0)))
	var radius_tex := 6 if turbo_nozzle else 11
	var removed := 0
	for s in steps + 1:
		var u := float(s) / float(steps)
		var pt := from_local.lerp(to_local, u)
		removed += _erase_circle_at(pt, radius_tex)

	if removed > 0:
		mask_texture.update(mask_image)
		_spawn_splash_particles(to_local, mini(8, 2 + int(removed / 6)))
		_update_progress_ui()
		if get_clean_progress() >= AUTO_FINISH_THRESHOLD:
			_trigger_completion_sweep()


func _erase_circle_at(local_pos: Vector2, radius_tex: int) -> int:
	var tx := int(round((local_pos.x / CANVAS_W) * float(MASK_W)))
	var ty := int(round((local_pos.y / CANVAS_H) * float(MASK_H)))
	var r2 := radius_tex * radius_tex
	var removed := 0
	for dy in range(-radius_tex, radius_tex + 1):
		var py := ty + dy
		if py < 0 or py >= MASK_H:
			continue
		for dx in range(-radius_tex, radius_tex + 1):
			var px := tx + dx
			if px < 0 or px >= MASK_W:
				continue
			var d2 := dx * dx + dy * dy
			if d2 > r2:
				continue
			var idx := py * MASK_W + px
			if active_mask[idx] == 0:
				continue
			var c := mask_image.get_pixel(px, py)
			if c.a <= 0.04:
				continue
			var pressure := 1.0 if turbo_nozzle else (1.0 - sqrt(float(d2)) / float(radius_tex + 1) * 0.45)
			c.a = maxf(0.0, c.a - pressure)
			mask_image.set_pixel(px, py, c)
			if c.a <= 0.04:
				c.a = 0.0
				mask_image.set_pixel(px, py, c)
				active_mask[idx] = 0
				remaining_dirty_pixels = maxi(0, remaining_dirty_pixels - 1)
				removed += 1
	return removed


func _generate_dust_mask() -> void:
	mask_image = Image.create(MASK_W, MASK_H, false, Image.FORMAT_RGBA8)
	active_mask = PackedByteArray()
	active_mask.resize(MASK_W * MASK_H)
	total_dirty_pixels = 0
	remaining_dirty_pixels = 0

	var base_tex := load(PANEL_TEXTURE_PATH) as Texture2D
	var crop_rect := Rect2(96, 160, 2344, 1120) if panel_id == 0 else Rect2(120, 1328, 2320, 1144)

	# Set panel sprite region cleanly
	var panel_rect_node := _canvas.get_node("PanelSprite") as TextureRect
	var atlas := AtlasTexture.new()
	atlas.atlas = base_tex
	atlas.region = crop_rect
	panel_rect_node.texture = atlas

	var src_img := base_tex.get_image()
	for y in MASK_H:
		for x in MASK_W:
			var sx := clampi(int(crop_rect.position.x + (float(x) + 0.5) / float(MASK_W) * crop_rect.size.x), 0, src_img.get_width() - 1)
			var sy := clampi(int(crop_rect.position.y + (float(y) + 0.5) / float(MASK_H) * crop_rect.size.y), 0, src_img.get_height() - 1)
			if src_img.get_pixel(sx, sy).a < 0.2:
				mask_image.set_pixel(x, y, Color(0, 0, 0, 0))
				active_mask[y * MASK_W + x] = 0
				continue

			# Layered Martian rust dust + wind streaks
			var streak := sin(float(x) * 0.14 + float(y) * 0.25 + float(panel_id)) * 0.15
			var grain := _rng.randf_range(-0.12, 0.14)
			var grime := clampf(0.78 + streak + grain, 0.45, 0.96)
			var dust_col := Color(
				clampf(0.68 + grain * 0.6, 0.50, 0.85),
				clampf(0.31 + grain * 0.35, 0.22, 0.46),
				clampf(0.20 + grain * 0.25, 0.14, 0.34),
				clampf(0.78 + grime * 0.18, 0.72, 0.96)
			)
			mask_image.set_pixel(x, y, dust_col)
			active_mask[y * MASK_W + x] = 1
			total_dirty_pixels += 1
			remaining_dirty_pixels += 1

	mask_texture = ImageTexture.create_from_image(mask_image)
	var dust_rect := _canvas.get_node("DustOverlay") as TextureRect
	dust_rect.texture = mask_texture


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.04, 0.09, 0.74)
	add_child(backdrop)

	var frame := PanelContainer.new()
	frame.position = Vector2(280, 100)
	frame.size = Vector2(592, 438)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.16, 0.96)
	sb.border_color = Color(0.36, 0.74, 1.0, 0.95)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	frame.add_child(vbox)

	# Header Row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var title := Label.new()
	title.name = "HeaderTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.55, 0.88, 1.0))
	title.text = "POWERWASH STATION — SOLAR PANEL"
	header.add_child(title)

	_nozzle_btn = Button.new()
	_nozzle_btn.text = "Nozzle: Fan [R]"
	_nozzle_btn.custom_minimum_size = Vector2(140, 30)
	_nozzle_btn.pressed.connect(_toggle_nozzle)
	header.add_child(_nozzle_btn)

	var back_btn := Button.new()
	back_btn.text = "Step Back [Esc]"
	back_btn.custom_minimum_size = Vector2(124, 30)
	back_btn.pressed.connect(_on_cancel_pressed)
	header.add_child(back_btn)

	# Progress Row
	var prog_row := HBoxContainer.new()
	prog_row.add_theme_constant_override("separation", 12)
	vbox.add_child(prog_row)

	_clean_bar = ProgressBar.new()
	_clean_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clean_bar.custom_minimum_size = Vector2(0, 22)
	_clean_bar.min_value = 0.0
	_clean_bar.max_value = 100.0
	_clean_bar.show_percentage = false
	prog_row.add_child(_clean_bar)

	_pct_label = Label.new()
	_pct_label.custom_minimum_size = Vector2(105, 0)
	_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct_label.add_theme_font_size_override("font_size", 15)
	_pct_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	prog_row.add_child(_pct_label)

	# Washable Panel Viewport
	var bay_bg := PanelContainer.new()
	bay_bg.custom_minimum_size = Vector2(544, 272)
	var bay_sb := StyleBoxFlat.new()
	bay_sb.bg_color = Color(0.28, 0.13, 0.09, 1.0)
	bay_sb.border_color = Color(0.55, 0.28, 0.18, 0.9)
	bay_sb.set_border_width_all(2)
	bay_sb.content_margin_left = 12
	bay_sb.content_margin_right = 12
	bay_sb.content_margin_top = 12
	bay_sb.content_margin_bottom = 12
	bay_bg.add_theme_stylebox_override("panel", bay_sb)
	vbox.add_child(bay_bg)

	_canvas = _WashCanvas.new()
	_canvas.owner_minigame = self
	_canvas.custom_minimum_size = Vector2(CANVAS_W, CANVAS_H)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_on_canvas_gui_input)
	bay_bg.add_child(_canvas)

	var panel_rect := TextureRect.new()
	panel_rect.name = "PanelSprite"
	panel_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_rect.stretch_mode = TextureRect.STRETCH_SCALE
	panel_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(panel_rect)

	var dust_rect := TextureRect.new()
	dust_rect.name = "DustOverlay"
	dust_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	dust_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dust_rect.stretch_mode = TextureRect.STRETCH_SCALE
	dust_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dust_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(dust_rect)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.84, 0.92, 1.0))
	_hint_label.text = "Hold LEFT MOUSE BUTTON and drag across the solar panel to wash away Mars dust!"
	vbox.add_child(_hint_label)


func _update_progress_ui() -> void:
	var title := find_child("HeaderTitle", true, false) as Label
	if title:
		title.text = "POWERWASH STATION — SOLAR PANEL %d/2" % (panel_id + 1)
	var pct := get_clean_progress()
	_clean_bar.value = pct * 100.0
	_pct_label.text = "%d%% Clean" % int(round(pct * 100.0))
	washed_progress.emit(panel_id, pct)


func _toggle_nozzle() -> void:
	turbo_nozzle = not turbo_nozzle
	_nozzle_btn.text = "Nozzle: Turbo [R]" if turbo_nozzle else "Nozzle: Fan [R]"
	InteractiveAssets.play_sfx(self, "interact", -10.0)


func _on_cancel_pressed() -> void:
	if _finishing:
		return
	is_spraying = false
	_stop_spray_audio()
	cancelled.emit(panel_id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _finishing:
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_viewport().set_input_as_handled()
		_toggle_nozzle()


func _on_canvas_gui_input(event: InputEvent) -> void:
	if _finishing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		cursor_local = mb.position.clamp(Vector2.ZERO, Vector2(CANVAS_W, CANVAS_H))
		is_spraying = mb.pressed
		has_prev_cursor = mb.pressed
		prev_cursor_local = cursor_local
		if is_spraying:
			apply_spray_stroke(cursor_local, cursor_local)
			_ensure_spray_audio_playing()
		else:
			_stop_spray_audio()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		cursor_local = mm.position.clamp(Vector2.ZERO, Vector2(CANVAS_W, CANVAS_H))
		if is_spraying or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_spraying = true
			if not has_prev_cursor:
				prev_cursor_local = cursor_local
				has_prev_cursor = true
			apply_spray_stroke(prev_cursor_local, cursor_local)
			prev_cursor_local = cursor_local
			_ensure_spray_audio_playing()


func _process(delta: float) -> void:
	_sparkle_time += delta
	if is_spraying and not _finishing:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_spraying = false
			has_prev_cursor = false
			_stop_spray_audio()
		else:
			# Continuous erosion even if held steady on stubborn grime
			apply_spray_stroke(cursor_local, cursor_local)

	for i in range(_particles.size() - 1, -1, -1):
		var p := _particles[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			_particles.remove_at(i)
			continue
		p["vel"] = (p["vel"] as Vector2) + Vector2(0, 140.0) * delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta

	if is_instance_valid(_canvas):
		_canvas.queue_redraw()


func _spawn_splash_particles(at: Vector2, count: int) -> void:
	for i in count:
		if _particles.size() > 140:
			break
		var ang := _rng.randf_range(0.0, TAU)
		var spd := _rng.randf_range(40.0, 130.0)
		var is_rust := _rng.randf() < 0.28
		_particles.append({
			"pos": at + Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-5, 5)),
			"vel": Vector2(cos(ang), sin(ang)) * spd - Vector2(0, 40.0),
			"life": _rng.randf_range(0.18, 0.36),
			"max_life": 0.36,
			"r": _rng.randf_range(1.8, 3.8),
			"col": Color(0.75, 0.36, 0.22, 0.9) if is_rust else Color(0.76, 0.95, 1.0, 0.92),
		})


func _trigger_completion_sweep() -> void:
	if _finishing:
		return
	_finishing = true
	is_spraying = false
	_stop_spray_audio()

	# Clear remaining ~5% specs in a crystal final rinse
	for y in MASK_H:
		for x in MASK_W:
			mask_image.set_pixel(x, y, Color(0, 0, 0, 0))
			active_mask[y * MASK_W + x] = 0
	remaining_dirty_pixels = 0
	mask_texture.update(mask_image)
	_clean_bar.value = 100.0
	_pct_label.text = "100% CLEAN!"
	_hint_label.text = "Crystal clean! Solar array output restored to 100%!"
	_hint_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.68))

	InteractiveAssets.play_sfx(self, "success", -6.0)
	for i in 36:
		_particles.append({
			"pos": Vector2(_rng.randf_range(24.0, CANVAS_W - 24.0), _rng.randf_range(20.0, CANVAS_H - 20.0)),
			"vel": Vector2(_rng.randf_range(-35.0, 35.0), _rng.randf_range(-85.0, -25.0)),
			"life": 0.72,
			"max_life": 0.72,
			"r": _rng.randf_range(2.2, 4.4),
			"col": Color(0.85, 0.98, 1.0, 0.95),
		})

	washed_progress.emit(panel_id, 1.0)
	await get_tree().create_timer(0.8).timeout
	completed.emit(panel_id)


func _build_spray_audio() -> void:
	_spray_player = AudioStreamPlayer.new()
	var sample_rate := 22050
	var count := int(0.4 * sample_rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7711
	var lp := 0.0
	for i in count:
		var white := rng.randf_range(-1.0, 1.0)
		lp = lp * 0.65 + white * 0.35
		var s := clampf((white * 0.55 + lp * 0.45) * 0.22, -1.0, 1.0)
		data.encode_s16(i * 2, int(round(s * 32767.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	wav.data = data
	_spray_player.stream = wav
	_spray_player.volume_db = -10.0
	add_child(_spray_player)


func _ensure_spray_audio_playing() -> void:
	if is_instance_valid(_spray_player) and not _spray_player.playing:
		_spray_player.play()


func _stop_spray_audio() -> void:
	if is_instance_valid(_spray_player) and _spray_player.playing:
		_spray_player.stop()


class _WashCanvas extends Control:
	var owner_minigame: PowerWashMinigame

	func _draw() -> void:
		if owner_minigame == null:
			return
		# Draw sparkle gleam sweep on completion
		if owner_minigame._finishing:
			var gx := fmod(owner_minigame._sparkle_time * 420.0, CANVAS_W + 80.0) - 40.0
			draw_line(Vector2(gx, 0.0), Vector2(gx - 38.0, CANVAS_H), Color(0.85, 0.98, 1.0, 0.55), 14.0)

		# Draw water splash / dust particles
		for p in owner_minigame._particles:
			var col: Color = p["col"]
			col.a *= clampf(float(p["life"]) / float(p["max_life"]), 0.0, 1.0)
			draw_circle(p["pos"] as Vector2, float(p["r"]), col)

		var target := owner_minigame.cursor_local
		var nozzle_base := Vector2(CANVAS_W - 22.0, CANVAS_H + 14.0)
		var dir := (target - nozzle_base).normalized()
		var nozzle_tip := nozzle_base + dir * 48.0

		if owner_minigame.is_spraying:
			var spread := 5.0 if owner_minigame.turbo_nozzle else 14.0
			var perp := Vector2(-dir.y, dir.x)
			var pts := PackedVector2Array([
				nozzle_tip,
				target + perp * spread,
				target - perp * spread,
			])
			draw_colored_polygon(pts, Color(0.62, 0.92, 1.0, 0.34))
			draw_line(nozzle_tip, target, Color(0.92, 0.99, 1.0, 0.85), 3.0 if owner_minigame.turbo_nozzle else 2.0)
			draw_circle(target, spread * 1.15, Color(0.85, 0.98, 1.0, 0.32))
			draw_arc(target, spread * 1.25, 0.0, TAU, 24, Color(0.95, 1.0, 1.0, 0.75), 1.5)
		elif not owner_minigame._finishing:
			var aim_r := 18.0 if owner_minigame.turbo_nozzle else 30.0
			draw_arc(target, aim_r, 0.0, TAU, 24, Color(0.55, 0.9, 1.0, 0.6), 1.5)

		# Metallic washer wand barrel
		draw_line(nozzle_base, nozzle_tip, Color(0.24, 0.30, 0.42, 1.0), 8.0)
		draw_line(nozzle_tip - dir * 8.0, nozzle_tip, Color(0.88, 0.72, 0.25, 1.0), 6.0)
		draw_circle(nozzle_tip, 4.0, Color(0.75, 0.95, 1.0, 1.0))
