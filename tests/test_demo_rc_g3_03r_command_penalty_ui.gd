extends SceneTree

## DEMO-RC-G3-03R — 지휘 한도 초과 명중·진형 변경 불이익 실제 적용 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Editor := preload("res://scripts/red_cliff_turn/red_cliff_formation_editor.gd")
const BattleView := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")

class ReceiptBattle:
	extends RefCounted
	var tier := 1
	var formation_basis_points := 9200
	var accuracy_basis_points := 9600
	func viewer_command_penalty_metrics(_viewer: String, _squadron_id: String) -> Dictionary:
		return {"ok":true, "penalty_tier":tier, "mobility_percent":-5 * tier, "accuracy_percent":-4 * tier, "formation_change_percent":-8 * tier}
	func viewer_phase(_viewer: String, _phase: String) -> Dictionary:
		return {"ok":true, "phase":{"events":[{"source":"formation_events", "payload":{"squadron_id":"RC-LIU-SQ-01", "changed":true,
			"command_penalty":{"penalty_tier":tier, "formation_change_percent":-8 * tier, "modifier_effectiveness_basis_points":formation_basis_points, "change_turn_only":true}}}]}}
	func visible_tactical_events(_viewer: String) -> Dictionary:
		return {"ok":true, "events":[
			{"event_type":"shot_authorized", "command_penalty":{"accuracy_basis_points":accuracy_basis_points, "applied":true}},
			{"event_type":"estimated_fire_authorized", "command_penalty":{"accuracy_basis_points":accuracy_basis_points, "applied":true}},
			{"event_type":"shot_authorized"}]}

var _pass := 0
var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G3-03R — 지휘 한도 초과 명중·진형 변경 불이익 실제 적용 UI")
	root.size = Vector2i(1600, 900)
	await _test_formation_editor_receipt()
	await _test_real_battle_viewer_receipt()
	await _test_resolved_phase_result_visibility()
	_test_battle_receipt_rendering()
	_test_tier_display_matrix()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _test_formation_editor_receipt() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads")
	var editor := Editor.new(); _ok(editor.configure(loaded.setup).ok, "formation editor configures"); root.add_child(editor); await _settle()
	var draft = editor.draft_controller()
	for change in [["SHP-01",1], ["SHP-02",2], ["SHP-03",3], ["SHP-04",7], ["SHP-05",2], ["SHP-06",3], ["SHP-07",6], ["SHP-08",10]]:
		_ok(draft.set_ship_count("RC-LIU-SQ-01", String(change[0]), int(change[1])).ok, "inventory-valid overcap row %s" % change[0])
	editor._refresh(); await _settle()
	var receipt: Dictionary = draft.squadron_metrics("RC-LIU-SQ-01"); _ok(receipt.warning and receipt.penalty_tier > 0, "fixture is over command limit")
	var metrics: Label = editor.find_child("CommandMetrics", true, false)
	_ok(metrics.text.contains("기동 %d%%" % int(receipt.mobility_percent)) and metrics.text.contains("명중 %d%%" % int(receipt.accuracy_percent)) and metrics.text.contains("진형변경 %d%%" % int(receipt.formation_change_percent)), "formation UI renders exact public receipt")
	var application: Label = editor.find_child("CommandPenaltyApplication", true, false)
	_ok(application.text.contains("기동(이동) 실제 적용") and application.text.contains("명중(자원 소모 전) 실제 적용") and application.text.contains("진형 변경(해결 시작) 실제 적용"), "all three active consumers are honest")
	_ok(application.text.contains("수동 명령과 AI 명령이 같은 코어 판정"), "manual and AI common-core contract visible")
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g3-03r-command-penalty"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); await process_frame
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600,900), "1600x900 GPU image")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("command-penalty-1600x900.png"))) == OK, "GPU capture saved")
	editor.free()

func _test_real_battle_viewer_receipt() -> void:
	var loaded := Setup.load_default(); var battle = Battle.new(); _ok(battle.initialize(loaded.setup).ok, "real battle initializes")
	var view := BattleView.new(); _ok(view.configure(battle, int(loaded.setup.formation_revision), JSON.stringify(loaded.setup)).ok, "real battle view configures"); root.add_child(view); await _settle()
	var status: Label = view.find_child("CommandPenaltyLiveStatus", true, false)
	_ok(status != null and status.text.contains("지휘 한도 실제 적용") and status.text.contains("수동·AI 명령 공통 코어 영수증"), "real viewer-safe receipt reaches battle UI")
	_ok(not battle.viewer_command_penalty_metrics("liu_bei", "RC-CAO-SQ-01").ok, "enemy exact command penalty remains redacted")
	view.free()

func _test_resolved_phase_result_visibility() -> void:
	var loaded := Setup.load_default(); var battle = Battle.new(); _ok(battle.initialize(loaded.setup).ok, "resolved-view battle initializes")
	_ok(battle.submit_liu_orders(_hold_orders(loaded.setup, "liu_bei")).ok, "Liu orders submit")
	_ok(battle.submit_sun_control_choice("no", true).ok and battle.resolve_turn().ok, "AI common-core turn resolves")
	var view := BattleView.new(); view.configure(battle, int(loaded.setup.formation_revision), JSON.stringify(loaded.setup)); root.add_child(view); await _settle()
	_ok(view.find_child("CommandPenaltyFormationResult_RC-LIU-SQ-01", true, false) != null, "resolved result remains visible while command input is locked")
	view.free()

func _test_tier_display_matrix() -> void:
	var formation_values := [9200, 8400, 7600, 6800]; var accuracy_values := [9600, 9200, 8800, 8400]
	for index in range(4):
		var fake := ReceiptBattle.new(); fake.tier = index + 1; fake.formation_basis_points = formation_values[index]; fake.accuracy_basis_points = accuracy_values[index]
		var view := BattleView.new(); view._battle = fake; view._orders = VBoxContainer.new(); view.add_child(view._orders); view._selected_squadron_id = "RC-LIU-SQ-01"; view._viewer_faction_id = "liu_bei"; view._add_command_penalty_results()
		var formation: Label = view._orders.find_child("CommandPenaltyFormationResult_RC-LIU-SQ-01", true, false)
		_ok(formation.text.contains("변경 턴 유효 %d%%" % int(formation_values[index] / 100)), "tier %d formation effectiveness exact" % (index + 1))
		var accuracy: Label = view._orders.find_child("CommandPenaltyAccuracyResult_1", true, false)
		_ok(accuracy.text.contains("지휘 명중 %d%%" % int(accuracy_values[index] / 100)), "tier %d accuracy effectiveness exact" % (index + 1))
		view.free()

func _test_battle_receipt_rendering() -> void:
	var view := BattleView.new(); view._battle = ReceiptBattle.new(); view._orders = VBoxContainer.new(); view.add_child(view._orders); view._selected_squadron_id = "RC-LIU-SQ-01"; view._viewer_faction_id = "liu_bei"
	view._add_command_penalty_status()
	var status: Label = view._orders.find_child("CommandPenaltyLiveStatus", true, false)
	_ok(status != null and status.text.contains("단계 1") and status.text.contains("명중 -4%") and status.text.contains("수동·AI 명령 공통"), "battle preview renders core metrics receipt")
	view._add_command_penalty_results()
	var formation: Label = view._orders.find_child("CommandPenaltyFormationResult_RC-LIU-SQ-01", true, false)
	_ok(formation != null and formation.text.contains("변경 턴 유효 92%") and formation.text.contains("유지 다음 턴 100%"), "formation command result renders 92-percent change turn and 100-percent next turn")
	var accuracy := view._orders.find_children("CommandPenaltyAccuracyResult_*", "Label", true, false)
	_eq(accuracy.size(), 2, "actual and estimated own-fire accuracy receipts render")
	_ok(accuracy.all(func(label): return label.text.contains("지휘 명중 96%") and label.text.contains("자원 소모 전 실제 적용")), "accuracy result is exact and ordered before resources")
	_ok(view._orders.find_children("CommandPenaltyAccuracyResult_*", "Label", true, false).size() == 2, "event without viewer-safe command receipt reveals no penalty")
	view.free()

func _test_source_boundary() -> void:
	for path in ["res://scripts/red_cliff_turn/red_cliff_formation_editor.gd", "res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd"]:
		var source := FileAccess.get_file_as_string(path); _ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "%s remains 2D only" % path)

func _settle() -> void:
	await process_frame
	await process_frame

func _hold_orders(setup: Dictionary, faction_id: String) -> Array:
	var result: Array = []
	for squad in setup.squadrons:
		if String(squad.faction_id) == faction_id and bool(squad.get("operational", true)): result.append({"squadron_id":String(squad.id), "action":"hold"})
	return result
