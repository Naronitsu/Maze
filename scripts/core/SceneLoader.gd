# SceneLoader.gd (autoload)
extends Node

## Handles scene changes with a loading overlay and threaded loading.

#region Signals
signal loading_started
signal loading_finished
#endregion

#region Public Properties
var is_loading: bool = false
#endregion

#region Private Fields
var _path: String = ""
var _status: int = 0
var _finishing: bool = false
var _loading: bool = false
#endregion

#region Lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _process(_delta: float) -> void:
	if _finishing:
		return

	var progress: Array = []
	_status = ResourceLoader.load_threaded_get_status(_path, progress)

	if not progress.is_empty():
		LoadingOverlay.set_progress(progress[0])

	if _status == ResourceLoader.THREAD_LOAD_LOADED:
		_finishing = true
		LoadingOverlay.set_progress(1.0)
		get_tree().paused = true

		var packed: PackedScene = ResourceLoader.load_threaded_get(_path)
		get_tree().change_scene_to_packed(packed)

		await RenderingServer.frame_post_draw
		await get_tree().create_timer(0.3, true).timeout
		await LoadingOverlay.fade_out(0.4)

		get_tree().paused = false
		_done()

	elif _status == ResourceLoader.THREAD_LOAD_FAILED:
		_fail("threaded load failed")
#endregion

#region Public Methods
func change_scene_with_loading(path: String) -> void:
	is_loading = true
	loading_started.emit()

	if _loading:
		return

	var p: String = path.strip_edges()
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
	await get_tree().process_frame

	ResourceLoader.load_threaded_request(_path)
	_status = ResourceLoader.THREAD_LOAD_IN_PROGRESS
	set_process(true)
#endregion

#region Private Methods
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
#endregion
