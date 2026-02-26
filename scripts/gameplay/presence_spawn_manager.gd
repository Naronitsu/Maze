extends Node

## Presence spawn orchestrator. Listens to level_started and emits presence_should_spawn
## after head start and player history are ready (only if at least one shrine charged).

#region Public Properties
var controller: GameController
#endregion

#region Lifecycle
func _ready() -> void:
	EventBus.level_started.connect(_on_level_started)
#endregion

#region Signal Handlers
func _on_level_started(_player_pos: Vector2i, _maze: Node) -> void:
	controller = _get_controller()
	if controller == null:
		push_error("[PresenceSpawnManager] Could not find GameController")
		return

	if GameConfig.shrines_charged < 1:
		print("[PresenceSpawn] No shrines charged yet; not spawning Presence.")
		return

	print("[PresenceSpawn] Waiting for head start (%fs)" % GameConfig.presence_head_start_time)
	await get_tree().create_timer(GameConfig.presence_head_start_time).timeout

	print("[PresenceSpawn] Waiting for player history...")
	await _wait_for_player_history(
		GameConfig.presence_min_history_steps, GameConfig.presence_wait_history_max_seconds
	)

	var hist: Array = controller.player_history if "player_history" in controller else []
	print("[PresenceSpawn] Emitting presence_should_spawn (history: %d cells)" % hist.size())
	EventBus.presence_should_spawn.emit(hist)
#endregion

#region Private Methods
func _wait_for_player_history(min_len: int, max_seconds: float) -> void:
	if controller == null or not is_inside_tree():
		return

	var waited: float = 0.0
	while waited < max_seconds:
		if not is_inside_tree():
			return

		var hist_v: Variant = controller.get("player_history")
		if typeof(hist_v) == TYPE_ARRAY and (hist_v as Array).size() >= min_len:
			print("[PresenceSpawn] History ready (%d cells)" % (hist_v as Array).size())
			return

		await get_tree().process_frame
		waited += get_process_delta_time()

	print("[PresenceSpawn] History timeout, proceeding anyway")


func _get_controller() -> Node:
	if SceneReferences.controller != null:
		return SceneReferences.controller
	var game: Node = get_tree().current_scene
	if game != null and game.has_node("GameController"):
		return game.get_node("GameController")
	return null
#endregion
