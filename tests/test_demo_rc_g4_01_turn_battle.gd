extends SceneTree

## Task ID: DEMO-RC-G4-01
## 공식 작업 제목: 유비 명령·손권 제어 선택·20턴 판정 루프
## 새 작업 제목: DEMO-RC-G4-01 — 유비 명령·손권 제어 선택·20턴 판정 루프

const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Draft := preload("res://core/demo_red_cliffs/red_cliffs_formation_draft.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DEMO-RC-G4-01 turn battle core")
	_test_real_g3_applied_initialize_and_copy()
	_test_manual_and_ai_flows()
	_test_prompt_policy_lifetime()
	_test_invalid_atomicity()
	_test_twenty_turn_limit()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _applied_setup() -> Dictionary:
	var loaded := Setup.load_default()
	_ok(bool(loaded.get("ok", false)), "G2 loader returns valid setup")
	var draft = Draft.new(loaded.get("setup", {}))
	_ok(draft.set_formation("RC-LIU-SQ-01", "FRM-07").ok, "G3 draft mutation succeeds")
	var applied: Dictionary = draft.apply()
	_ok(bool(applied.get("ok", false)), "G3 draft apply succeeds")
	return applied.get("setup", {})


func _orders(setup: Dictionary, faction_id: String, reverse: bool = false) -> Array:
	var ids: Array = []
	for squad in setup.get("squadrons", []):
		if String(squad.get("faction_id", "")) == faction_id and bool(squad.get("operational", true)):
			ids.append(String(squad.get("id", "")))
	ids.sort()
	if reverse: ids.reverse()
	var result: Array = []
	for squadron_id in ids: result.append({"squadron_id": squadron_id, "action": "hold"})
	return result


func _new_battle() -> Array:
	var setup := _applied_setup()
	var battle = Battle.new()
	_ok(battle.initialize(setup).ok, "battle initializes from applied setup")
	return [battle, setup]


func _test_real_g3_applied_initialize_and_copy() -> void:
	var setup := _applied_setup()
	var original := setup.duplicate(true)
	var battle = Battle.new()
	_ok(battle.initialize(setup).ok, "initialize accepts actual G2 loader to G3 apply output")
	_eq(battle.turn(), 1, "battle starts on turn 1")
	_eq(battle.phase(), "liu_command", "battle starts in Liu command phase")
	_eq(battle.snapshot().max_turns, 20, "battle maximum is 20 turns")
	_ok(not battle.snapshot().resolved, "new battle is unresolved")
	setup.squadrons[0].name = "외부 입력 변조"
	_ok(battle.snapshot().applied_setup.squadrons[0].name != "외부 입력 변조", "initialize deep copies applied input")
	var leaked := battle.snapshot()
	leaked.current_turn = 99
	leaked.turn_log[0].liu_orders.append({"squadron_id": "leak", "action": "hold"})
	_eq(battle.turn(), 1, "snapshot is a deep copy")
	_eq(battle.turn_log()[0].liu_orders, [], "nested snapshot mutation cannot leak")
	var invalid := original.duplicate(true)
	invalid.player_faction_id = "sun_quan"
	var digest_before := battle.digest()
	_ok(not battle.initialize(invalid).ok, "invalid setup is rejected")
	_eq(battle.digest(), digest_before, "invalid reinitialize is atomic")
	_ok(_serializable_only(battle.snapshot()), "state contains only save-serializable values")


func _test_manual_and_ai_flows() -> void:
	var fixture := _new_battle()
	var battle = fixture[0]
	var setup: Dictionary = fixture[1]
	var liu_input := _orders(setup, "liu_bei", true)
	_ok(battle.submit_liu_orders(liu_input).ok, "Liu orders accept complete reversed input")
	liu_input[0].action = "move"
	_eq(battle.turn_log()[0].liu_orders[0].action, "hold", "submitted order input is deep copied")
	_eq(battle.phase(), "sun_control_prompt", "Liu orders lead to per-turn Sun prompt")
	_ok(battle.submit_sun_control_choice("yes").ok, "yes selects manual Sun control")
	_eq(battle.phase(), "sun_command", "manual answer leads to Sun command")
	_ok(battle.submit_sun_orders(_orders(setup, "sun_quan")).ok, "manual Sun orders submit")
	_eq(battle.phase(), "resolution", "manual Sun orders create Cao AI orders and resolution")
	var receipt: Dictionary = battle.resolve_turn()
	_ok(receipt.ok, "resolution commits the command ledger")
	_eq(battle.phase(), "victory_check", "resolution waits at external victory check")
	_ok(battle.snapshot().resolved, "resolution marks current turn resolved")
	_ok(receipt.victory_check_required, "resolution explicitly requires victory check")
	_eq(receipt.rules_pending, ["movement", "weapon_fire", "formation_change", "detection", "damage", "casualties", "victory"], "pending detailed rules are explicit")
	_ok(not receipt.has("winner") and not receipt.has("damage") and not receipt.has("casualties"), "resolution invents no winner, damage, or casualties")
	var log: Dictionary = battle.turn_log()[0]
	_eq(log.turn, 1, "turn log records turn number")
	_eq(log.liu_orders.size(), 2, "turn log records every Liu squadron")
	_eq(log.sun_control_decision.control, "manual", "turn log records Sun decision")
	_eq(log.sun_orders.size(), 1, "turn log records Sun orders")
	_eq(log.cao_orders.size(), 1, "turn log records Cao orders")
	_ok(not log.resolution_receipt.is_empty() and log.victory_check_required, "turn log records resolution boundary")
	_ok(battle.continue_turn().ok, "external resolver can continue after victory check")
	_eq(battle.turn(), 2, "continue increments turn")
	_eq(battle.phase(), "liu_command", "new turn returns to Liu command")

	fixture = _new_battle(); battle = fixture[0]; setup = fixture[1]
	battle.submit_liu_orders(_orders(setup, "liu_bei"))
	_ok(battle.submit_sun_control_choice("no").ok, "no selects Sun AI for this turn")
	_eq(battle.phase(), "resolution", "AI choice prepares resolution directly")
	log = battle.turn_log()[0]
	_eq(log.sun_orders, _orders(setup, "sun_quan"), "Sun AI hold orders are stable ID order")
	_eq(log.cao_orders, _orders(setup, "cao_cao"), "Cao AI hold orders are stable ID order")


func _test_prompt_policy_lifetime() -> void:
	var fixture := _new_battle()
	var battle = fixture[0]
	var setup: Dictionary = fixture[1]
	battle.submit_liu_orders(_orders(setup, "liu_bei"))
	battle.submit_sun_control_choice("ai")
	battle.resolve_turn(); battle.continue_turn()
	battle.submit_liu_orders(_orders(setup, "liu_bei"))
	_eq(battle.phase(), "sun_control_prompt", "AI answer without dont-ask prompts again next turn")
	battle.submit_sun_control_choice("no", true)
	_ok(not battle.prompt_policy().enabled, "no plus dont-ask disables future prompts")
	battle.resolve_turn(); battle.continue_turn()
	battle.submit_liu_orders(_orders(setup, "liu_bei"))
	_eq(battle.phase(), "resolution", "disabled prompt automatically prepares Sun and Cao AI")
	_eq(battle.turn_log()[2].sun_control_decision.source, "saved_policy", "automatic decision records saved policy source")
	battle.resolve_turn(); battle.continue_turn()
	_ok(battle.set_sun_prompt_enabled(true).ok, "public setting restores Sun prompt")
	battle.submit_liu_orders(_orders(setup, "liu_bei"))
	_eq(battle.phase(), "sun_control_prompt", "restored setting prompts on next turn")
	var before: String = battle.digest()
	_ok(not battle.submit_sun_control_choice("manual", true).ok, "manual plus dont-ask is rejected")
	_eq(battle.digest(), before, "invalid manual plus dont-ask leaves digest unchanged")


func _test_invalid_atomicity() -> void:
	var fixture := _new_battle()
	var battle = fixture[0]
	var setup: Dictionary = fixture[1]
	var valid_liu := _orders(setup, "liu_bei")
	var before: String = battle.digest()
	_ok(not battle.submit_sun_orders(_orders(setup, "sun_quan")).ok, "wrong-phase Sun submit rejected")
	_eq(battle.digest(), before, "wrong-phase submit keeps digest")
	var missing := valid_liu.duplicate(true); missing.pop_back()
	_ok(not battle.submit_liu_orders(missing).ok, "missing operational squadron rejected")
	_eq(battle.digest(), before, "missing order keeps digest")
	var duplicate := [valid_liu[0].duplicate(true), valid_liu[0].duplicate(true)]
	_ok(not battle.submit_liu_orders(duplicate).ok, "duplicate squadron order rejected")
	_eq(battle.digest(), before, "duplicate order keeps digest")
	var foreign := valid_liu.duplicate(true); foreign[0] = _orders(setup, "sun_quan")[0]
	_ok(not battle.submit_liu_orders(foreign).ok, "foreign faction order rejected")
	_eq(battle.digest(), before, "foreign order keeps digest")
	var action := valid_liu.duplicate(true); action[0] = action[0].duplicate(true); action[0].action = "move"
	_ok(not battle.submit_liu_orders(action).ok, "unknown future action rejected")
	_eq(battle.digest(), before, "unknown action keeps digest")
	var extra := valid_liu.duplicate(true); extra[0] = extra[0].duplicate(true); extra[0].target = [1, 2]
	_ok(not battle.submit_liu_orders(extra).ok, "expanded order schema rejected in G4-01")
	_eq(battle.digest(), before, "expanded schema keeps digest")
	_ok(battle.submit_liu_orders(valid_liu).ok, "valid Liu submit succeeds once")
	before = battle.digest()
	_ok(not battle.submit_liu_orders(valid_liu).ok, "duplicate Liu submit rejected")
	_ok(not battle.resolve_turn().ok, "wrong-phase early resolve rejected")
	_ok(not battle.continue_turn().ok, "wrong-phase early continue rejected")
	_ok(not battle.submit_sun_control_choice("sometimes").ok, "invalid prompt answer rejected")
	_eq(battle.digest(), before, "all wrong-phase and invalid prompt calls are atomic")
	battle.submit_sun_control_choice("ai")
	battle.resolve_turn()
	before = battle.digest()
	_ok(not battle.resolve_turn().ok, "duplicate resolve rejected")
	_eq(battle.digest(), before, "duplicate resolve keeps digest")
	battle.continue_turn()
	before = battle.digest()
	_ok(not battle.continue_turn().ok, "duplicate continue rejected")
	_eq(battle.digest(), before, "duplicate continue keeps digest")


func _test_twenty_turn_limit() -> void:
	var fixture := _new_battle()
	var battle = fixture[0]
	var setup: Dictionary = fixture[1]
	_ok(battle.set_sun_prompt_enabled(false).ok, "20-turn loop uses explicit Sun AI setting")
	for turn_number in range(1, 21):
		_eq(battle.turn(), turn_number, "loop current turn %d" % turn_number)
		_ok(battle.submit_liu_orders(_orders(setup, "liu_bei")).ok, "loop Liu orders %d" % turn_number)
		_eq(battle.phase(), "resolution", "loop AI resolution phase %d" % turn_number)
		_ok(battle.resolve_turn().ok, "loop resolution %d" % turn_number)
		if turn_number < 20:
			_eq(battle.phase(), "victory_check", "loop victory boundary %d" % turn_number)
			_ok(battle.continue_turn().ok, "loop continue %d" % turn_number)
	_eq(battle.phase(), "turn_limit_reached", "turn 20 reaches explicit limit phase")
	_eq(battle.turn(), 20, "turn limit does not increment to 21")
	_eq(battle.turn_log().size(), 20, "turn log preserves all 20 turns")
	_ok(battle.turn_log()[19].victory_check_required, "turn 20 still requires follow-up victory comparison")
	var before: String = battle.digest()
	_ok(not battle.continue_turn().ok, "turn limit rejects next turn")
	_ok(not battle.submit_liu_orders(_orders(setup, "liu_bei")).ok, "turn limit rejects further orders")
	_eq(battle.digest(), before, "turn-limit rejections keep digest")
	for log in battle.turn_log():
		_ok(not log.resolution_receipt.has("winner") and not log.resolution_receipt.has("damage"), "turn %d has no invented outcome" % log.turn)


func _serializable_only(value) -> bool:
	if value == null or value is bool or value is int or value is float or value is String:
		return true
	if value is Array:
		for item in value:
			if not _serializable_only(item): return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _serializable_only(value[key]): return false
		return true
	return false
