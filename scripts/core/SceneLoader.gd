# SceneLoader.gd (autoload)
extends Node
signal loading_started
signal loading_finished

var is_loading := false

var _path: String = ""
var _status: int = 0
var _finishing: bool = false
var _loading: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func change_scene_with_loading(path: String) -> void:
	is_loading = true
	loading_started.emit()

	# Prevent re-entry / double presses
	if _loading:
		return

	# Validate path early
	var p := path.strip_edges()
	if p.is_empty():
		push_error("SceneLoader: empty scene path passed in.")
		return
	if not ResourceLoader.exists(p):
		push_error("SceneLoader: scene does not exist: %s" % p)
		return

	_loading = true
	_finishing = false
	_path = p

	LoadingOverlay.show_loading()
	await get_tree().process_frame  # ensure overlay is drawn

	ResourceLoader.load_threaded_request(_path)
	_status = ResourceLoader.THREAD_LOAD_IN_PROGRESS
	set_process(true)


func _process(_dt: float) -> void:
	if _finishing:
		return

	var progress: Array[float] = []
	_status = ResourceLoader.load_threaded_get_status(_path, progress)

	if not progress.is_empty():
		LoadingOverlay.set_progress(progress[0])

	if _status == ResourceLoader.THREAD_LOAD_LOADED:
		_finishing = true
		LoadingOverlay.set_progress(1.0)

		# Freeze game while overlay is up
		get_tree().paused = true

		var packed := ResourceLoader.load_threaded_get(_path)
		get_tree().change_scene_to_packed(packed)

		# Let at least one frame draw with overlay on top
		await RenderingServer.frame_post_draw

		# Optional: hold at 100%
		await get_tree().create_timer(0.3, true).timeout

		# Fade overlay
		await LoadingOverlay.fade_out(0.4)

		# Now start the game
		get_tree().paused = false

		_done()

	elif _status == ResourceLoader.THREAD_LOAD_FAILED:
		_fail("threaded load failed")


func _fail(reason: String) -> void:
	_finishing = true
	push_error("SceneLoader: %s: %s" % [reason, _path])
	LoadingOverlay.visible = false
	_done()


func _done() -> void:
	is_loading = false
	loading_finished.emit()

	set_process(false)
	_loading = false
	_finishing = false
	_path = ""
	_status = 0
