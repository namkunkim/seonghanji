extends SceneTree

## DEMO-RC-QA-03 — full 20-turn loop acceptance: determinism and public
## rejection boundaries on the canonical G2-G6 turn battle.
##
## The superseded SCN-03 preceding-event selection, long-range assembly, and
## home-map-banner entry are out of scope for this demo and are not driven
## here (see docs/07-production/demo-rc-completion-review-checklist.md §2).
## This test uses only the public RedCliffsTurnBattle command API and the
## real Main product button path; it never writes turn, phase, or resource
## state directly, and it never injects a winner.

const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value:
		_pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DEMO-RC-QA-03 full 20-turn loop: determinism and boundaries")
	await _test_product_entry_smoke()
	_test_full_loop_reaches_limit()
	_test_determinism()
	_test_invalid_boundaries()
	print("통과 %d · 실패 %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _orders(setup: Dictionary, faction_id: String) -> Array:
	var result: Array = []
	for squad in setup.get("squadrons", []):
		if String(squad.get("faction_id", "")) == faction_id and bool(squad.get("operational", true)):
			result.append({"squadron_id": String(squad.get("id", "")), "action": "hold"})
	return result


func _drive_full_loop(battle, setup: Dictionary) -> void:
	for turn_number in range(1, 21):
		var liu_result: Dictionary = battle.submit_liu_orders(_orders(setup, "liu_bei"))
		_ok(bool(liu_result.get("ok", false)), "turn %d Liu HOLD orders accepted" % turn_number)
		if turn_number == 1:
			_ok(bool(battle.submit_sun_control_choice("no", true).get("ok", false)),
				"turn 1 Sun AI/dont-ask policy accepted")
		_ok(bool(battle.resolve_turn().get("ok", false)), "turn %d resolves" % turn_number)
		if turn_number < 20:
			_ok(bool(battle.continue_turn().get("ok", false)), "turn %d continues" % turn_number)


func _test_product_entry_smoke() -> void:
	print("0. real button entry reaches the turn battle without preceding SCN-03 events")
	root.size = Vector2i(1600, 900)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.red_cliff_demo_button.pressed.emit()
	await process_frame
	main.red_cliff_preparation_view.find_child("StartTurnBattle", true, false).pressed.emit()
	await process_frame
	_eq(main.red_cliff_turn_battle_state.get("turn"), 1, "product entry starts directly at turn 1")
	_eq(main.red_cliff_turn_battle_state.get("phase"), "liu_command",
		"no preceding briefing/choice stage exists before Liu's first command")
	main.free()


func _test_full_loop_reaches_limit() -> void:
	print("1. direct driver: full 20-turn loop reaches the pending-result ceiling")
	var loaded := Setup.load_default()
	_ok(bool(loaded.get("ok", false)), "setup fixture validates")
	var setup: Dictionary = loaded.get("setup", {})
	var battle = Battle.new()
	_ok(bool(battle.initialize(setup).get("ok", false)), "battle initializes")
	_drive_full_loop(battle, setup)
	_eq(battle.phase(), "turn_limit_reached", "20 turns reach turn_limit_reached")
	for turn_log_row in battle.turn_log():
		var receipt: Dictionary = turn_log_row.get("resolution_receipt", {})
		_ok(not receipt.has("winner") and not receipt.has("damage") and not receipt.has("casualties"),
			"turn log never contains a fabricated winner, damage, or casualties")


func _test_determinism() -> void:
	print("2. same setup and same commands produce identical digests")
	var loaded := Setup.load_default()
	var setup: Dictionary = loaded.get("setup", {})
	var a = Battle.new()
	a.initialize(setup)
	_drive_full_loop(a, setup)
	var b = Battle.new()
	b.initialize(setup)
	_drive_full_loop(b, setup)
	_eq(a.digest(), b.digest(), "identical setup and orders produce the identical final digest")
	_eq(JSON.stringify(a.turn_log()), JSON.stringify(b.turn_log()), "identical turn logs")


func _test_invalid_boundaries() -> void:
	print("3. public rejection boundaries")
	var loaded := Setup.load_default()
	var setup: Dictionary = loaded.get("setup", {})
	var battle = Battle.new()
	battle.initialize(setup)
	_ok(not bool(battle.submit_liu_orders([{"squadron_id": "RC-UNKNOWN", "action": "hold"}]).get("ok", true)),
		"unknown squadron ID is rejected")
	_ok(not bool(battle.submit_sun_orders(_orders(setup, "sun_quan")).get("ok", true)),
		"Sun orders are rejected outside sun_command phase")
	_ok(not bool(battle.resolve_turn().get("ok", true)), "resolve is rejected before commands are submitted")
	_ok(not bool(battle.continue_turn().get("ok", true)), "continue is rejected before the turn resolves")
	_ok(not bool(battle.set_formation_order("RC-LIU-SQ-01", "FRM-UNKNOWN").get("ok", true)),
		"unknown formation ID is rejected")
	_drive_full_loop(battle, setup)
	_ok(not bool(battle.submit_liu_orders(_orders(setup, "liu_bei")).get("ok", true)),
		"orders are rejected once the 20-turn limit is reached")
	_ok(not bool(battle.continue_turn().get("ok", true)),
		"continue is rejected at the 20-turn limit")
