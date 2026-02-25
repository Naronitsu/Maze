extends Node

# Signals for live updates
signal master_volume_changed(new_value)
signal sfx_volume_changed(new_value)
signal music_volume_changed(new_value)
signal crt_enabled_changed(new_value)
signal chromatic_aberration_changed(new_value)
signal resolution_changed(new_value)
signal window_mode_changed(new_value)
signal minimap_size_changed(new_value)

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_RESOLUTION := Vector2i(960, 540)
const DEFAULT_ABERRATION_PX := 1.0
const DEFAULT_MINIMAP_SIZE_PX := 200

var crt_enabled: bool = true
var chromatic_aberration: bool = true
var resolution: Vector2i = DEFAULT_RESOLUTION
var window_mode: String = "windowed"
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 1.0
var minimap_size_px: int = DEFAULT_MINIMAP_SIZE_PX


func _ready() -> void:
	add_to_group("persist")
	load_settings()
	apply_display()
	apply_audio()


func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err == OK:
		crt_enabled = config.get_value("video", "crt_enabled", true)
		chromatic_aberration = config.get_value("video", "chromatic_aberration", true)
		resolution = config.get_value("video", "resolution", DEFAULT_RESOLUTION)
		window_mode = config.get_value("video", "window_mode", "windowed")
		master_volume = config.get_value("audio", "master_volume", 1.0)
		sfx_volume = config.get_value("audio", "sfx_volume", 1.0)
		music_volume = config.get_value("audio", "music_volume", 1.0)
		minimap_size_px = int(config.get_value("ui", "minimap_size_px", DEFAULT_MINIMAP_SIZE_PX))
	else:
		save_settings()

	minimap_size_px = clampi(minimap_size_px, 120, 400)
	_apply_ui()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("video", "crt_enabled", crt_enabled)
	config.set_value("video", "chromatic_aberration", chromatic_aberration)
	config.set_value("video", "resolution", resolution)
	config.set_value("video", "window_mode", window_mode)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("ui", "minimap_size_px", minimap_size_px)
	config.save(SETTINGS_PATH)


func set_music_volume(v: float) -> void:
	music_volume = clamp(v, 0.0, 1.0)
	save_settings()
	apply_audio()
	music_volume_changed.emit(music_volume)


func set_crt_enabled(v: bool) -> void:
	crt_enabled = v
	save_settings()
	apply_visuals_to_scene(get_tree().current_scene)
	crt_enabled_changed.emit(crt_enabled)


func set_chromatic_aberration(v: bool) -> void:
	chromatic_aberration = v
	save_settings()
	apply_visuals_to_scene(get_tree().current_scene)
	chromatic_aberration_changed.emit(chromatic_aberration)


func set_resolution(v: Vector2i) -> void:
	resolution = v
	save_settings()
	apply_display()
	resolution_changed.emit(resolution)


func set_window_mode(v: String) -> void:
	window_mode = v
	save_settings()
	apply_display()
	window_mode_changed.emit(window_mode)


func set_master_volume(v: float) -> void:
	master_volume = clamp(v, 0.0, 1.0)
	save_settings()
	apply_audio()
	master_volume_changed.emit(master_volume)


func set_sfx_volume(v: float) -> void:
	sfx_volume = clamp(v, 0.0, 1.0)
	save_settings()
	apply_audio()
	sfx_volume_changed.emit(sfx_volume)


func set_minimap_size_px(v: int) -> void:
	minimap_size_px = clampi(v, 120, 400)
	save_settings()
	_apply_ui()
	minimap_size_changed.emit(minimap_size_px)


func apply_display() -> void:
	var win := get_tree().root as Window
	if win == null:
		return

	# Change window mode first
	match window_mode:
		"fullscreen":
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
			win.borderless = false
		"windowed_fullscreen":
			win.mode = Window.MODE_FULLSCREEN
			win.borderless = true
		"windowed":
			win.mode = Window.MODE_WINDOWED
			win.borderless = false

	# Only set size for windowed mode - fullscreen uses monitor resolution
	if window_mode == "windowed":
		win.size = resolution


func apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Music", music_volume)


func apply_visuals_to_scene(scene_root: Node) -> void:
	if scene_root == null:
		return
	var crt_layer := scene_root.get_node_or_null("CRT")
	if crt_layer:
		crt_layer.visible = crt_enabled
	var overlay := scene_root.get_node_or_null("CRT/CRTOverlay")
	if overlay and overlay.material is ShaderMaterial:
		var mat := overlay.material as ShaderMaterial
		var ab = DEFAULT_ABERRATION_PX if chromatic_aberration else 0.0
		mat.set_shader_parameter("aberration_px", ab)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var db := _linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)


func _linear_to_db(value: float) -> float:
	var v: float = clamp(value, 0.0, 1.0)
	if v <= 0.0001:
		return -80.0
	return linear_to_db(v)


func _apply_ui() -> void:
	# GameConfig is the single source of truth for runtime tuning.
	GameConfig.minimap_size = Vector2(float(minimap_size_px), float(minimap_size_px))
	# Broadcast for any live UI components (e.g., in-game minimap).
	EventBus.minimap_size_changed.emit(GameConfig.minimap_size)
