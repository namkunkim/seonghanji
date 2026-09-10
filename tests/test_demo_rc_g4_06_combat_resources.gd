extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G4-06 — 제한 전투 자원과 결정론적 소모
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Resources := preload("res://core/demo_red_cliffs/red_cliffs_combat_resources.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")

var _pass := 0
var _fail := 0


func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _init() -> void: call_deferred("_run")


func _run() -> void:
	print("DEMO-RC-G4-06 combat resources core")
	_test_initial_state_and_save_primitives()
	_test_deterministic_consumption_double_resolve_and_partial()
	_test_all_suppression_reasons_and_recovery()
	_test_battle_integration_manual_ai_and_viewer_redaction()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


func _setup() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); return loaded.setup.duplicate(true)


func _resources(setup: Dictionary):
	var resolver = Resources.new(); var initialized: Dictionary = resolver.initialize(setup)
	_ok(initialized.ok, "resource resolver initializes: %s" % str(initialized.get("errors", []))); return resolver


func _shot(event_id: String, squadron_id: String, weapon_id: String, platform_id: String) -> Dictionary:
	return {"event_id": event_id, "turn": 1, "outcome": "shot_authorized",
		"shooter_squadron_id": squadron_id, "target_squadron_id": "TARGET",
		"selected_weapon_id": weapon_id,
		"fire_control_snapshot": {"selected_platform_id": platform_id}}


func _test_initial_state_and_save_primitives() -> void:
	var resolver = _resources(_setup()); var rules: Dictionary = resolver.rules_snapshot()
	_eq(rules.profile_id, "normal-demo-resource-v1", "explicit resource profile")
	_ok(String(rules.statement).contains("역사적 사실이 아닌"), "demo quantities not presented as historical fact")
	_ok(String(rules.statement).contains("글로벌 미사일 규칙을 변경하지 않는다"), "finite special charge scope is profile-local")
	_eq(rules.resource_semantics.special, "finite_charge_in_normal-demo-resource-v1_only", "special is finite only in demo profile")
	var state: Dictionary = resolver.initial_state(); _eq(state.size(), 4, "all operational squads receive resources")
	var liu: Dictionary = state["RC-LIU-SQ-01"]
	_ok(int(liu.shared.energy) == int(liu.shared.energy_capacity) and int(liu.shared.heat) == 0, "shared energy full and heat zero")
	_eq(int(liu.weapons.line_fire.ammo), 40, "line-fire ammo derives from four line ships")
	_eq(int(liu.weapons.intercept.ammo), 24, "intercept ammo derives from three eligible interceptors; recon craft excluded")
	_eq(int(liu.weapons.torpedo.special), 0, "unavailable torpedo has zero special resource")
	var sun: Dictionary = state["RC-SUN-SQ-01"]
	_eq(int(sun.weapons.line_fire.carrier_ready), 4, "carrier sorties derive from one carrier platform")
	_eq(int(sun.weapons.torpedo.special), 16, "torpedo special reserve derives from equipped craft")
	var encoded := JSON.stringify(state); var decoded = JSON.parse_string(encoded)
	_ok(decoded is Dictionary and decoded.has("RC-LIU-SQ-01") and int(decoded["RC-LIU-SQ-01"].shared.energy) == int(liu.shared.energy), "resource state uses save-safe primitives")
	var leaked: Dictionary = state.duplicate(true); leaked["RC-LIU-SQ-01"].shared.energy = 0
	_ok(int(resolver.initial_state()["RC-LIU-SQ-01"].shared.energy) > 0, "initial state calls are deep copies")


func _test_deterministic_consumption_double_resolve_and_partial() -> void:
	var resolver = _resources(_setup()); var initial: Dictionary = resolver.initial_state(); var digest := JSON.stringify(initial)
	var events := [_shot("FIRE-B", "RC-LIU-SQ-01", "line_fire", "SHP-04"), _shot("FIRE-A", "RC-LIU-SQ-01", "intercept", "SHP-07")]
	var first: Dictionary = resolver.resolve_shots(events, initial, 1); _ok(first.ok, "resource consumption resolves")
	_eq(first.authorized_events[0].event_id, "FIRE-A", "stable event ID order owns reservation")
	_eq(first.authorized_events[1].event_id, "FIRE-B", "stable event order independent of input")
	_eq(JSON.stringify(initial), digest, "resource resolver deep-copies caller state")
	var reversed := events.duplicate(true); reversed.reverse()
	_eq(JSON.stringify(first), JSON.stringify(resolver.resolve_shots(reversed, initial, 1)), "reversed input gives byte-stable receipt")
	var energy_before := int(first.resource_state["RC-LIU-SQ-01"].shared.energy)
	var repeated: Dictionary = resolver.resolve_shots([events[0]], first.resource_state, 1)
	_eq(repeated.authorized_events.size(), 0, "already consumed event not authorized twice")
	_eq(repeated.suppressed_fire_events[0].reason, "duplicate_event", "duplicate replay explicit")
	_eq(int(repeated.resource_state["RC-LIU-SQ-01"].shared.energy), energy_before, "duplicate replay consumes nothing")
	var limited := initial.duplicate(true); limited["RC-LIU-SQ-01"].weapons.line_fire.ammo = 1
	limited["RC-LIU-SQ-01"].shared.heat_capacity = 1000
	var partial_events := [_shot("FIRE-01", "RC-LIU-SQ-01", "line_fire", "SHP-04"), _shot("FIRE-02", "RC-LIU-SQ-01", "line_fire", "SHP-04")]
	var partial: Dictionary = resolver.resolve_shots(partial_events, limited, 1)
	_eq(partial.authorized_events.size(), 1, "partial availability authorizes first stable event")
	_eq(partial.suppressed_fire_events.size(), 1, "partial availability suppresses later event")
	_eq(partial.suppressed_fire_events[0].reason, "ammo", "later event reports ammo shortage")
	_eq(partial.suppressed_fire_events[0].weapon_id, "line_fire", "shortage does not fall back to another weapon")
	var invalid := events.duplicate(true); invalid.append(events[0].duplicate(true))
	_ok(not resolver.resolve_shots(invalid, initial, 1).ok, "duplicate event IDs in one receipt rejected atomically")
	_eq(JSON.stringify(initial), digest, "invalid receipt leaves caller digest unchanged")
	var wrong_turn := events.duplicate(true); wrong_turn[0].turn = 2
	_ok(not resolver.resolve_shots(wrong_turn, initial, 1).ok, "event turn mismatch rejected atomically")
	_eq(JSON.stringify(initial), digest, "turn mismatch leaves caller digest unchanged")
	var invalid_state := initial.duplicate(true); invalid_state["RC-LIU-SQ-01"].shared.energy = -1
	_ok(not resolver.resolve_shots([], invalid_state, 1).ok, "negative resource state rejected")
	_eq(JSON.stringify(initial), digest, "invalid state check leaves valid caller digest unchanged")


func _test_all_suppression_reasons_and_recovery() -> void:
	var resolver = _resources(_setup()); var initial: Dictionary = resolver.initial_state()
	var cases := [
		["ammo", "RC-LIU-SQ-01", "line_fire", "SHP-04"],
		["energy", "RC-LIU-SQ-01", "line_fire", "SHP-04"],
		["overheat", "RC-LIU-SQ-01", "line_fire", "SHP-04"],
		["carrier_not_returned", "RC-SUN-SQ-01", "line_fire", "SHP-01"],
		["special", "RC-SUN-SQ-01", "torpedo", "SHP-08"],
	]
	for item in cases:
		var state := initial.duplicate(true); var squadron_id := String(item[1]); var weapon_id := String(item[2])
		if item[0] == "ammo": state[squadron_id].weapons[weapon_id].ammo = 0
		elif item[0] == "energy": state[squadron_id].shared.energy = 0
		elif item[0] == "overheat": state[squadron_id].shared.heat = int(state[squadron_id].shared.heat_capacity)
		elif item[0] == "carrier_not_returned": state[squadron_id].weapons[weapon_id].carrier_ready = 0
		elif item[0] == "special": state[squadron_id].weapons[weapon_id].special = 0
		var result: Dictionary = resolver.resolve_shots([_shot("CASE-%s" % item[0], squadron_id, weapon_id, String(item[3]))], state, 1)
		_eq(result.authorized_events.size(), 0, "%s suppresses authorization" % item[0])
		_eq(result.suppressed_fire_events[0].reason, item[0], "%s reason is explicit" % item[0])
	var spent := initial.duplicate(true); var row: Dictionary = spent["RC-SUN-SQ-01"]
	row.shared.energy = 0; row.shared.heat = 80; row.weapons.line_fire.carrier_ready = 0
	row.weapons.line_fire.ammo -= 3; row.weapons.torpedo.special -= 2
	var ammo_before := int(row.weapons.line_fire.ammo); var special_before := int(row.weapons.torpedo.special)
	_ok(not resolver.recover_at_resolution_start(spent, 1).ok, "turn 1 has no recovery")
	var recovered: Dictionary = resolver.recover_at_resolution_start(spent, 2); _ok(recovered.ok, "turn 2 resolution-start recovery resolves")
	var after: Dictionary = recovered.resource_state["RC-SUN-SQ-01"]
	_ok(int(after.shared.energy) > 0 and int(after.shared.heat) == 50, "energy recovers and heat dissipates")
	_ok(int(after.weapons.line_fire.carrier_ready) > 0, "carrier sorties return at turn boundary")
	_eq(int(after.weapons.line_fire.ammo), ammo_before, "ammo does not recover")
	_eq(int(after.weapons.torpedo.special), special_before, "special resource does not recover")
	_eq(recovered.recovery_events.size(), 4, "stable recovery receipt covers all squads")
	_eq(JSON.stringify(recovered), JSON.stringify(resolver.recover_at_resolution_start(spent, 2)), "recovery deterministic")


func _test_battle_integration_manual_ai_and_viewer_redaction() -> void:
	var setup := _setup(); var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 800],
		"RC-SUN-SQ-01": [100, 700], "RC-CAO-SQ-01": [400, 100]}
	for squad in setup.squadrons:
		squad.initial_position = positions[String(squad.id)].duplicate()
		if squad.id == "RC-CAO-SQ-01": squad.initial_facing_deg = 180
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes resource authority")
	var initial_energy := int(battle.combat_resource_state()["RC-CAO-SQ-01"].shared.energy)
	_ok(battle.set_order_move("RC-LIU-SQ-01", [[240, 100]], 0).ok, "Liu target moves into Cao fire")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok, "player and AI orders submit")
	var receipt: Dictionary = battle.resolve_turn(); _ok(receipt.ok, "integrated resource turn resolves")
	_ok(receipt.resource_consumption_events.size() > 0, "authorized shot consumes resources")
	_ok(int(battle.combat_resource_state()["RC-CAO-SQ-01"].shared.energy) < initial_energy, "live resource state persists consumption")
	_ok(not receipt.has("hit") and not receipt.has("damage") and not receipt.has("casualties") and not receipt.has("winner"), "no combat result fabricated")
	var cao_view: Dictionary = battle.visible_tactical_events("cao_cao")
	_ok(JSON.stringify(cao_view).contains("resource_consumed"), "shooter viewer sees own resource delta")
	var liu_view: Dictionary = battle.visible_tactical_events("liu_bei")
	_ok(not JSON.stringify(liu_view).contains("resource_consumed") and not JSON.stringify(liu_view).contains("resource_reservation"), "target viewer sees no enemy resources")
	var liu_state: Dictionary = battle.visible_combat_resources("liu_bei")
	_ok(liu_state.resource_state.has("RC-LIU-SQ-01") and not liu_state.resource_state.has("RC-CAO-SQ-01"), "viewer resource state is own-only")
	var before_continue := JSON.stringify(battle.combat_resource_state())
	_ok(battle.continue_turn().ok, "turn 2 command phase begins without early recovery")
	_eq(JSON.stringify(battle.combat_resource_state()), before_continue, "continue_turn does not recover resources")
	_ok(battle.viewer_snapshot("cao_cao").resource_recovery_events.is_empty(), "no recovery receipt before turn 2 resolution")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("manual").ok, "manual Sun phase starts")
	_ok(battle.submit_command_draft().ok, "manual Sun shares command/resource resolver")
	var second: Dictionary = battle.resolve_turn(); _ok(second.ok, "manual Sun/AI Cao turn resolves")
	_eq(second.resource_recovery_events.size(), 4, "turn 2 resolution start recovers every squad exactly once")
	var after_second_digest := battle.digest()
	_ok(not battle.resolve_turn().ok, "duplicate turn 2 resolve is rejected")
	_eq(battle.digest(), after_second_digest, "duplicate resolve cannot recover or consume twice")
	_ok(JSON.stringify(battle.visible_tactical_events("cao_cao")).contains("resource_recovered"), "own recovery event visible after resolution")
	_ok(not battle.viewer_snapshot("cao_cao").resource_recovery_events.is_empty(), "viewer snapshot exposes resolution-start recovery receipt")
	_eq(second.weapon_allocation_events.size(), 4, "manual Sun and AI use same allocation resolver")
	_eq(battle.combat_resource_state().size(), 4, "all factions retain resource state")
