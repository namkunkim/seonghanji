extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G5-06 — 연쇄 폭발 작전 조건·방해·발동
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Chain := preload("res://core/demo_red_cliffs/red_cliffs_chain_explosion.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const Planner := preload("res://core/demo_red_cliffs/red_cliffs_ai_planner.gd")
var _pass := 0; var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G5-06 chain explosion operation")
	_test_rules_and_readiness_boundaries()
	_test_state_machine_atomicity_retry_and_irreversibility()
	_test_ai_interference_and_hidden_independence()
	_test_battle_public_api_redaction_and_phase_contract()
	print("PASS %d / FAIL %d" % [_pass, _fail]); quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _fixture() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [590, 180], "RC-LIU-SQ-02": [590, 0], "RC-LIU-FC-01": [580, 200], "RC-SUN-SQ-01": [600, 100], "RC-CAO-SQ-01": [700, 100]}
	for squad in setup.squadrons:
		squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
		if String(squad.id) == "RC-CAO-SQ-01": squad.commander = {"id": "CHR-0043", "name": "하후돈"}
		if String(squad.id) == "RC-LIU-SQ-01":
			for row in squad.composition:
				if String(row.ship_type_id) == "SHP-08": row.count = 16
			squad.declared_total_cost = 109
	for faction in setup.factions:
		if String(faction.id) == "liu_bei": faction.inventory["SHP-08"] = 22
	return setup

func _chain(setup: Dictionary):
	var chain = Chain.new(); var initialized: Dictionary = chain.initialize(setup); _ok(initialized.ok, "chain resolver initializes: %s" % str(initialized.get("errors", []))); return chain

func _navigation() -> Dictionary:
	return {"RC-LIU-SQ-01": {"position": [590, 180]}, "RC-LIU-SQ-02": {"position": [590, 0]}, "RC-SUN-SQ-01": {"position": [600, 100]}, "RC-CAO-SQ-01": {"position": [700, 100]}}

func _formation() -> Dictionary:
	return {"RC-LIU-SQ-01": {"formation_id": "FRM-01"}, "RC-LIU-SQ-02": {"formation_id": "FRM-03"}, "RC-SUN-SQ-01": {"formation_id": "FRM-02"}, "RC-CAO-SQ-01": {"formation_id": "FRM-04"}}

func _contact() -> Dictionary:
	return {"contact_id": "CONTACT-LIU-CAO", "target_squadron_id": "RC-CAO-SQ-01", "state": "confirmed", "disposition": "hostile", "display_position": [700, 100]}

func _ready(chain, state: Dictionary = {}) -> Dictionary:
	var actual: Dictionary = chain.initial_state() if state.is_empty() else state
	return chain.readiness("liu_bei", actual, "RC-SUN-SQ-01", _contact(), _navigation(), _formation())

func _test_rules_and_readiness_boundaries() -> void:
	var chain = _chain(_fixture()); var state: Dictionary = chain.initial_state(); var ready: Dictionary = _ready(chain)
	_ok(ready.ok and ready.ready, "all six normal-demo conditions produce ready receipt")
	_eq(ready.conditions.map(func(row): return String(row.id)), ["detachment_available", "cao_dense_formation", "legal_detection", "designated_range", "solar_nebula_flow", "interception_screen_clear"], "condition ids and order are stable")
	_eq(chain.rules_snapshot().allied_operation_detachment.modeling_boundary, "allied_special_operation_payload_not_a_new_ship_type_or_squadron", "payload is not a new ship type or squadron")
	var estimated := _contact(); estimated.state = "estimated"; _ok(not chain.readiness("liu_bei", state, "RC-SUN-SQ-01", estimated, _navigation(), _formation()).ready, "estimated contact cannot arm operation")
	var dispersed := _formation(); dispersed["RC-CAO-SQ-01"].formation_id = "FRM-05"; _ok(not chain.readiness("liu_bei", state, "RC-SUN-SQ-01", _contact(), _navigation(), dispersed).ready, "Cao dispersed formation blocks operation")
	var far := _navigation(); far["RC-CAO-SQ-01"].position = [1000, 100]; _ok(not chain.readiness("liu_bei", state, "RC-SUN-SQ-01", _contact(), far, _formation()).ready, "range exit blocks operation")
	var reverse := _navigation(); reverse["RC-SUN-SQ-01"].position = [710, 100]; _ok(not chain.readiness("liu_bei", state, "RC-SUN-SQ-01", _contact(), reverse, _formation()).ready, "wrong solar-nebula flow blocks operation")
	var fire := [{"event_id": "SHOT-1", "target_squadron_id": "RC-SUN-SQ-01", "selected_weapon_id": "intercept"}]
	_ok(not chain.readiness("liu_bei", state, "RC-SUN-SQ-01", _contact(), _navigation(), _formation(), fire).ready, "interception screen shot evidence blocks route without destroying payload")
	var ai_screen := [{"turn": 2, "squadron_id": "RC-CAO-SQ-01", "category": "chain_counter_interception_screen"}]
	_ok(chain.readiness("liu_bei", state, "RC-SUN-SQ-01", _contact(), _navigation(), _formation(), [], ai_screen).ready, "AI interception-screen intent alone cannot fabricate disruption")
	_ok(not chain.readiness("sun_quan", state, "RC-SUN-SQ-01", _contact(), _navigation(), _formation()).ok, "Sun cannot directly stage Liu-invoked operation")

func _test_state_machine_atomicity_retry_and_irreversibility() -> void:
	var chain = _chain(_fixture()); var idle: Dictionary = chain.initial_state(); var ready: Dictionary = _ready(chain)
	var staged: Dictionary = chain.stage(idle, ready, 2); _ok(staged.ok and staged.state.status == "staged", "ready operation stages")
	var duplicate: Dictionary = chain.stage(staged.state, ready, 2); _ok(duplicate.ok and duplicate.idempotent and duplicate.state == staged.state, "duplicate identical stage is idempotent")
	var invalid_ready := ready.duplicate(true); invalid_ready.ready = false; var digest := JSON.stringify(idle)
	_ok(not chain.stage(idle, invalid_ready, 2).ok and JSON.stringify(idle) == digest, "invalid stage is atomic")
	var cancelled: Dictionary = chain.cancel(staged.state); _ok(cancelled.ok and cancelled.state.status == "idle", "cancel returns to idle before trigger")
	var screen := [{"event_id": "SHOT-RESOURCE-VALID", "target_squadron_id": "RC-SUN-SQ-01", "selected_weapon_id": "intercept"}]
	var blocked: Dictionary = chain.readiness("liu_bei", staged.state, "RC-SUN-SQ-01", _contact(), _navigation(), _formation(), screen)
	var disrupted: Dictionary = chain.resolve_staged(staged.state, blocked, 2); _ok(disrupted.ok and disrupted.state.status == "disrupted", "pre-trigger interference disrupts operation")
	_eq(disrupted.events[0].retry_allowed_from_turn, 3, "retry opens next Liu command turn")
	_ok(not chain.stage(disrupted.state, ready, 2).ok, "same-turn retry rejected")
	var retry: Dictionary = chain.stage(disrupted.state, ready, 3); _ok(retry.ok and retry.state.status == "staged", "next-turn retry succeeds only after conditions reacquired")
	var triggered: Dictionary = chain.resolve_staged(retry.state, ready, 3); _ok(triggered.ok and triggered.state.status == "triggered", "probability-free operation triggers")
	_ok(triggered.events[0].irreversible and triggered.events[0].effect_intents.size() == 4 and triggered.events[0].effects_pending == ["commander_casualties", "victory"], "trigger emits typed intents and only post-G8 pending boundaries")
	_ok(not chain.cancel(triggered.state).ok and not chain.stage(triggered.state, ready, 4).ok, "triggered operation is immutable")
	var replay: Dictionary = chain.resolve_staged(triggered.state, ready, 4); _ok(replay.ok and replay.events.is_empty() and replay.state == triggered.state, "post-trigger resolve cannot duplicate event")
	var encoded := JSON.stringify(triggered); _ok(not encoded.contains('"winner"') and not encoded.contains('"damage":'), "state creates no concrete damage or winner")

func _test_ai_interference_and_hidden_independence() -> void:
	var battle = Battle.new(); _ok(battle.initialize(_fixture()).ok, "battle initializes for AI fixture")
	var planner = Planner.new(); _ok(planner.initialize().ok, "planner initializes with chain response rules")
	var viewer: Dictionary = battle.viewer_snapshot("cao_cao"); var resources: Dictionary = battle.scheduled_resource_preview("cao_cao")
	viewer.contacts = [{"contact_id": "CONTACT-RISK", "state": "confirmed", "disposition": "hostile", "display_position": [600, 100], "confidence_basis_points": 10000, "staleness_turns": 0}]
	for turn_number in range(1, 6):
		viewer.turn = turn_number; var result: Dictionary = planner.plan(viewer, resources, turn_number); _ok(result.ok, "Cao risk plan turn %d succeeds" % turn_number)
		_ok(String(result.intents[0].category).begins_with("chain_counter_") or result.intents[0].category == "confirmed_engage", "Cao risk response is typed")
	var hidden := viewer.duplicate(true); hidden["hidden_staged_operation"] = {"true": true}; var a: Dictionary = planner.plan(hidden, resources, 3); hidden.hidden_staged_operation = {"true": false}
	_eq(a, planner.plan(hidden, resources, 3), "Cao response is independent of hidden staged truth")

func _test_battle_public_api_redaction_and_phase_contract() -> void:
	var battle_source := FileAccess.get_file_as_string("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
	var resource_gate := battle_source.find("var resource_result: Dictionary = _combat_resources.resolve_shots")
	var chain_recheck := battle_source.find("var final_readiness: Dictionary = _chain_explosion.readiness", resource_gate)
	var effect_commit := battle_source.find("var effect_result: Dictionary = _combat_effects.resolve", chain_recheck)
	var supply_commit := battle_source.find("var supply_result: Dictionary = _fast_craft_supply.resolve", effect_commit)
	_ok(resource_gate >= 0 and chain_recheck > resource_gate and effect_commit > chain_recheck and supply_commit > effect_commit, "resource-authorized chain recheck and effects precede outbound supply")
	var battle = Battle.new(); _ok(battle.initialize(_fixture()).ok, "battle initializes for public API")
	_ok(not battle.chain_explosion_readiness().ready, "turn1 has no preexisting exact detection")
	_ok(not battle.stage_chain_explosion("CHAIN-DET-01", "missing").ok, "cannot stage without eligible confirmed contact")
	_eq(battle.viewer_chain_explosion_state("cao_cao").status, "unknown", "Cao cannot see pre-trigger operation state")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("no").ok, "turn1 command bundle submits")
	var first: Dictionary = battle.resolve_turn(); _ok(first.ok, "turn1 resolves full stack"); _ok(battle.continue_turn().ok, "turn2 opens")
	var contacts: Array = battle.visible_contacts("liu_bei").contacts; var hostile := {}
	for contact in contacts:
		if String(contact.get("state", "")) == "confirmed" and String(contact.get("disposition", "")) == "hostile": hostile = contact; break
	if hostile.is_empty(): print("  info turn2 Liu contacts: %s" % str(contacts))
	_ok(not hostile.is_empty(), "turn2 Liu has confirmed hostile contact")
	var readiness: Dictionary = battle.chain_explosion_readiness(String(hostile.get("contact_id", ""))); _ok(readiness.ok, "public readiness receipt remains viewer-safe")
	_ok(readiness.ready, "turn2 normal-demo fixture satisfies public readiness")
	_ok(not JSON.stringify(readiness).contains("composition") and not readiness.has("target_squadron_id"), "readiness leaks no enemy identity or composition")
	var staged: Dictionary = battle.stage_chain_explosion("CHAIN-DET-01", String(hostile.contact_id)); _ok(staged.ok, "public stage succeeds when all conditions met")
	_ok(not JSON.stringify(staged).contains("RC-CAO-SQ-01"), "staged viewer state keeps target identity opaque")
	_eq(battle.viewer_chain_explosion_state("cao_cao").status, "unknown", "Cao still cannot see staged operation")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("no").ok, "turn2 bundle submits")
	var receipt: Dictionary = battle.resolve_turn(); _ok(receipt.ok, "staged operation resolves atomically")
	_eq(receipt.chain_explosion_events.size(), 1, "exactly one operation event resolves")
	_eq(receipt.chain_explosion_events[0].event_type, "chain_explosion_triggered", "turn2 standard pressure permits trigger")
	_eq(receipt.phase_ledger.phases[1].phase_id, "barrage", "operation is in barrage phase")
	_ok(receipt.phase_ledger.phases[1].events.any(func(row): return String(row.source) == "chain_explosion_events"), "operation event is mapped into barrage ledger")
	_ok(not receipt.has("winner") and not receipt.has("damage"), "battle receipt invents no damage or winner")
	var liu_events: Dictionary = battle.visible_tactical_events("liu_bei", 2); var encoded_events := JSON.stringify(liu_events)
	_ok(encoded_events.contains("chain_explosion_triggered") and not encoded_events.contains("RC-CAO-SQ-01"), "Liu viewer event uses opaque contact without enemy stable id")
	var chain_visible: Array = liu_events.events.filter(func(row): return String(row.get("event_type", "")).begins_with("chain_explosion_"))
	var chain_encoded := JSON.stringify(chain_visible)
	_ok(not chain_encoded.contains("formation_id") and not chain_encoded.contains("blocking_event_ids"), "Liu operation event redacts enemy formation and blocking IDs recursively")
	var cao_events: Dictionary = battle.visible_tactical_events("cao_cao", 2); _ok(JSON.stringify(cao_events).contains("own_target_squadron_id"), "Cao learns only its own target identity after trigger")
	var state_copy: Dictionary = battle.viewer_chain_explosion_state("liu_bei"); state_copy.effect_intents.clear(); _ok(not battle.viewer_chain_explosion_state("liu_bei").effect_intents.is_empty(), "viewer operation state is a deep copy")
	var digest := battle.digest(); _ok(not battle.resolve_turn().ok and battle.digest() == digest, "duplicate resolve is rejected without duplicate trigger")
	var cao_view := battle.viewer_chain_explosion_state("cao_cao"); _ok(not JSON.stringify(cao_view).contains("staged_order"), "Cao view never leaks staged target")
