extends SceneTree

## Direct playable entry for visual review. It follows the same public Button
## signal path as the shipped home-screen flow, then leaves the battle open.

var main = null


func _init() -> void:
	call_deferred("_open_battle")


func _open_battle() -> void:
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_title("SEONGHANJI — 적벽대전 직접 플레이")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main.red_cliff_demo_button == null:
		push_error("적벽대전 데모 시작 버튼을 찾을 수 없습니다.")
		quit(1)
		return
	main.red_cliff_demo_button.emit_signal("pressed")
	await process_frame
	await process_frame
	if main.red_cliff_banner_action == null or main.red_cliff_banner_action.disabled:
		push_error("적벽대전 전투 진입 버튼이 준비되지 않았습니다.")
		quit(1)
		return
	main.red_cliff_banner_action.emit_signal("pressed")
	await process_frame
	await process_frame
	if root.find_child("TacticalMapTwoThirds", true, false) == null:
		push_error("적벽대전 전술 지도가 열리지 않았습니다.")
		quit(1)
		return
	print("DIRECT_RED_CLIFFS_READY")
