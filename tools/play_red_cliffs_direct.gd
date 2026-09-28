extends SceneTree

## Direct playable entry for visual review. It follows the same public Button
## signal path as the shipped home-screen flow: 적벽 → G2-01 Liu Bei
## preparation → G4-01 turn battle. It never touches the superseded
## SCN-03 briefing/manifest/long-range-voyage path or the legacy
## RedCliffBattleView, and it leaves the turn battle open on turn 1.

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
	if main.red_cliff_demo_button == null or main.red_cliff_demo_button.disabled:
		push_error("적벽대전 데모 시작 버튼을 찾을 수 없습니다.")
		quit(1)
		return
	main.red_cliff_demo_button.emit_signal("pressed")
	await process_frame
	await process_frame
	var prep: Control = main.get("red_cliff_preparation_view")
	if prep == null or not prep.visible:
		push_error("적벽대전 준비 화면이 열리지 않았습니다.")
		quit(1)
		return
	var start_button: Button = prep.find_child("StartTurnBattle", true, false)
	if start_button == null or start_button.disabled:
		push_error("전투 시작 버튼이 준비되지 않았습니다.")
		quit(1)
		return
	start_button.emit_signal("pressed")
	await process_frame
	await process_frame
	var view: Control = main.get("red_cliff_turn_battle_view")
	if view == null or not view.visible:
		push_error("적벽대전 턴 전투 화면이 열리지 않았습니다.")
		quit(1)
		return
	if view.find_child("AppliedSquadronMap", true, false) == null:
		push_error("적벽대전 전술 지도가 열리지 않았습니다.")
		quit(1)
		return
	print("DIRECT_RED_CLIFFS_READY")
