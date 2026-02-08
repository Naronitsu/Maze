extends Node

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_RESOLUTION := Vector2i(960, 540)
const DEFAULT_ABERRATION_PX := 1.0

var crt_enabled: bool = true
var chromatic_aberration: bool = true
var resolution: Vector2i = DEFAULT_RESOLUTION
var window_mode: String = "windowed"
var master_volume: float = 1.0
var sfx_volume: float = 1.0

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
	else:
		save_settings()

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("video", "crt_enabled", crt_enabled)
	config.set_value("video", "chromatic_aberration", chromatic_aberration)
	config.set_value("video", "resolution", resolution)
	config.set_value("video", "window_mode", window_mode)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.save(SETTINGS_PATH)

func set_crt_enabled(v: bool) -> void:
	crt_enabled = v
	save_settings()
	apply_visuals_to_scene(get_tree().current_scene)

func set_chromatic_aberration(v: bool) -> void:
	chromatic_aberration = v
	save_settings()
	apply_visuals_to_scene(get_tree().current_scene)

func set_resolution(v: Vector2i) -> void:
	resolution = v
	save_settings()
	apply_display()

func set_window_mode(v: String) -> void:
	window_mode = v
	save_settings()
	apply_display()

func set_master_volume(v: float) -> void:
	master_volume = clamp(v, 0.0, 1.0)
	save_settings()
	apply_audio()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clamp(v, 0.0, 1.0)
	save_settings()
	apply_audio()

func apply_display() -> void:
	var win := get_tree().root as Window
	if win == null:
		return
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
			win.size = resolution

func apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("SFX", sfx_volume)

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
