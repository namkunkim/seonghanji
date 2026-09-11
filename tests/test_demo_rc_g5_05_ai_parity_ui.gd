extends SceneTree

## DEMO-RC-G5-05 — 조조·손권 AI 동일 규칙·제한 자원 운용 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const View := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G5-05 AI parity UI")
	root.size = Vector2i(1600, 900)
	await _test_ai_receipt_visibility_and_redaction()
	await _test_manual_sun_does_not_fabricate_ai_receipt()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _fixture() -> Array:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes")
	var view := View.new(); view.configure(battle, int(setup.get("formation_revision", 0)), JSON.stringify(setup)); root.add_child(view)
	return [battle, view]

func _test_ai_receipt_visibility_and_redaction() -> void:
	var fixture := _fixture(); var battle = fixture[0]; var view: Control = fixture[1]; await _settle()
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle(); view.find_child("SunAiThisTurn", true, false).pressed.emit(); await _settle()
	_eq(battle.phase(), "victory_check", "Sun AI and Cao AI resolve through normal turn")
	var sun: Dictionary = battle.viewer_ai_decision("sun_quan", 1); var cao: Dictionary = battle.viewer_ai_decision("cao_cao", 1)
	_ok(sun.ok and sun.available and cao.ok and cao.available, "own viewers receive AI receipts")
	_eq(sun.source, cao.source, "Sun and Cao receipts expose same core rules source")
	_ok(not sun.intents.is_empty() and not cao.intents.is_empty(), "both AI receipts include public intent rationale")
	var liu_log := JSON.stringify(battle.viewer_turn_log("liu_bei")); _ok(not liu_log.contains("sun_ai_decision") and not liu_log.contains("cao_ai_decision"), "Liu viewer gets no foreign AI plan")
	view._viewer_faction_id = "liu_bei"; view._refresh(); await _settle()
	var private_label: Label = view.find_child("AiDecisionPrivate", true, false); _ok(private_label != null and private_label.text.contains("다른 세력") and private_label.text.contains("비공개"), "Liu UI explains foreign AI redaction")
	var liu_text := _all_text(view.find_child("MovementOrderScroll", true, false)); _ok(not liu_text.contains(String(sun.intents[0].reason_label)) and not liu_text.contains(String(cao.intents[0].reason_label)), "Liu UI leaks no foreign selection reason")
	view._viewer_faction_id = "sun_quan"; view._refresh(); await _settle(); _assert_own_ai_panel(view, sun, "Sun")
	view._viewer_faction_id = "cao_cao"; view._refresh(); await _settle(); _assert_own_ai_panel(view, cao, "Cao")
	if DisplayServer.get_name() != "headless":
		var panel_title: Label = view.find_child("AiDecisionTitle", true, false); var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false); scroll.scroll_vertical = maxi(0, int(panel_title.position.y) - 8); await process_frame
		var output_dir := "res://out/demo-rc-g5-05-ai-parity"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU capture available")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("ai-parity-1600x900.png"))) == OK, "GPU capture saved")
	view.free()

func _assert_own_ai_panel(view: Control, decision: Dictionary, label: String) -> void:
	var evidence: Label = view.find_child("AiParityEvidence", true, false); var rows := view.find_children("AiIntentRow", "Label", true, false)
	_ok(evidence != null and evidence.text.contains(String(decision.source)) and evidence.text.contains(view._ai_posture_label(String(decision.posture))), "%s own rules evidence visible" % label)
	_eq(rows.size(), decision.intents.size(), "%s renders each own intent" % label)
	if not rows.is_empty():
		_ok(rows[0].text.contains(String(decision.intents[0].reason_label)), "%s renders core reason verbatim" % label)
		_ok(rows[0].text.contains("내 자원 여유"), "%s renders own reserve receipt" % label)
	var privacy: Label = view.find_child("AiDecisionPrivacy", true, false); _ok(privacy != null and privacy.text.contains("후보·점수·임계값"), "%s hides AI internals" % label)

func _test_manual_sun_does_not_fabricate_ai_receipt() -> void:
	var fixture := _fixture(); var battle = fixture[0]; var view: Control = fixture[1]; await _settle()
	view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle(); view.find_child("SunManualThisTurn", true, false).pressed.emit(); await _settle(); view.find_child("PrimaryTurnAction", true, false).pressed.emit(); await _settle()
	var decision: Dictionary = battle.viewer_ai_decision("sun_quan", 1); _ok(decision.ok and not decision.available, "manual Sun produces no AI receipt")
	view._viewer_faction_id = "sun_quan"; view._refresh(); await _settle()
	_ok(view.find_child("AiDecisionPrivate", true, false) != null and view.find_child("AiIntentRow", true, false) == null, "UI does not fabricate manual-turn AI intent")
	view.free()

func _settle() -> void:
	await process_frame
	await process_frame

func _all_text(node: Node) -> String:
	var result := String(node.text) if node is Label or node is Button else ""
	for child in node.get_children(): result += "\n" + _all_text(child)
	return result

func _test_source_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
	_ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "AI UI has zero 3D refs")
	for forbidden in ["minimum_confidence_basis_points", "minimum_resource_reserve_basis_points", "_select_contact", "_estimated_allowed"]: _ok(forbidden not in source, "UI does not duplicate AI rule %s" % forbidden)
