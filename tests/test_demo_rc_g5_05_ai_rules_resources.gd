extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G5-05 — 조조·손권 AI 동일 규칙·제한 자원 운용
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const Planner := preload("res://core/demo_red_cliffs/red_cliffs_ai_planner.gd")
var _pass := 0; var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G5-05 viewer-safe AI and resources")
	_test_pure_planner_postures_thresholds_and_hidden_independence()
	_test_integration_same_resolvers_manual_parity_and_redaction()
	_test_determinism_deep_copy_and_resource_conservation()
	print("PASS %d / FAIL %d" % [_pass, _fail]); quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _fixture() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [110, 110], "RC-SUN-SQ-01": [120, 100], "RC-CAO-SQ-01": [300, 100]}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	return setup

func _battle(setup: Dictionary):
	var battle = Battle.new(); var initialized: Dictionary = battle.initialize(setup); _ok(initialized.ok, "battle initializes: %s" % str(initialized.get("errors", []))); return battle

func _planner():
	var planner = Planner.new(); var initialized: Dictionary = planner.initialize(); _ok(initialized.ok, "AI planner initializes"); return planner

func _test_pure_planner_postures_thresholds_and_hidden_independence() -> void:
	var battle = _battle(_fixture()); var planner = _planner()
	var planner_source := FileAccess.get_file_as_string("res://core/demo_red_cliffs/red_cliffs_ai_planner.gd")
	_ok(not planner_source.contains('faction_id == "sun_quan"') and not planner_source.contains('faction_id == "cao_cao"'), "Sun/Cao behavior has no faction-specific planner branch")
	var sun: Dictionary = battle.viewer_snapshot("sun_quan"); var sun_resources: Dictionary = battle.scheduled_resource_preview("sun_quan")
	var no_contact: Dictionary = planner.plan(sun, sun_resources, 1)
	_ok(no_contact.ok, "Sun no-contact plan succeeds"); _eq(no_contact.posture, "allied_defensive", "Sun posture is defensive")
	_eq(no_contact.orders[0].action, "hold", "Sun no-contact conserves resources with HOLD")
	_eq(no_contact.formation_orders[0].formation_id, sun.own_formation_state["RC-SUN-SQ-01"].formation_id, "Sun no-contact preserves current formation")
	_eq(no_contact.weapon_preset_orders[0].preset_id, "", "Sun no-contact preserves current weapon allocation")
	var estimated := {"contact_id": "CONTACT-SUN-X", "state": "estimated", "disposition": "hostile", "display_position": [260, 100], "last_known_position": [260, 100], "last_seen_turn": 0, "staleness_turns": 1, "confidence_basis_points": 6500, "error_radius": 30}
	sun.contacts = [estimated]
	var accepted: Dictionary = planner.plan(sun, sun_resources, 1); _eq(accepted.estimated_fire_intents.size(), 1, "Sun estimate accepted exactly at strict threshold")
	var aged := sun.duplicate(true); aged.contacts[0].staleness_turns = 2
	_eq(planner.plan(aged, sun_resources, 1).estimated_fire_intents.size(), 0, "Sun rejects age two estimate")
	var low_resource := sun_resources.duplicate(true); low_resource.resource_state["RC-SUN-SQ-01"].reserve_basis_points = 4999
	_eq(planner.plan(sun, low_resource, 1).estimated_fire_intents.size(), 0, "Sun rejects reserve below 50 percent")
	var allied := sun.duplicate(true); allied.contacts[0].disposition = "allied"
	_eq(planner.plan(allied, sun_resources, 1).orders[0].action, "hold", "Sun never targets allied contact")

	var cao: Dictionary = battle.viewer_snapshot("cao_cao"); var cao_resources: Dictionary = battle.scheduled_resource_preview("cao_cao")
	var patrol: Dictionary = planner.plan(cao, cao_resources, 1); _eq(patrol.posture, "aggressive_pressure", "Cao posture is pressure")
	_eq(patrol.orders[0].action, "move", "Cao no-contact uses public patrol waypoint")
	var cao_est := estimated.duplicate(true); cao_est.contact_id = "CONTACT-CAO-X"; cao_est.confidence_basis_points = 4500; cao_est.staleness_turns = 2
	cao.contacts = [cao_est]
	_eq(planner.plan(cao, cao_resources, 1).estimated_fire_intents.size(), 1, "Cao accepts age two estimate at 45 percent")
	var low_cao := cao_resources.duplicate(true); low_cao.resource_state["RC-CAO-SQ-01"].reserve_basis_points = 2499
	_eq(planner.plan(cao, low_cao, 1).estimated_fire_intents.size(), 0, "Cao rejects reserve below 25 percent")

	var confirmed := cao.duplicate(true); confirmed.contacts = [{"contact_id": "CONTACT-C", "state": "confirmed", "disposition": "hostile", "display_position": [100, 100], "confidence_basis_points": 10000, "staleness_turns": 0}]
	confirmed["hidden_true_position"] = [1, 1]
	var first: Dictionary = planner.plan(confirmed, cao_resources, 1); confirmed.hidden_true_position = [1500, 899]
	var second: Dictionary = planner.plan(confirmed, cao_resources, 1)
	_eq(first, second, "confirmed AI plan is independent of hidden truth fields")
	_eq(first.orders[0].action, "move", "confirmed contact produces pursuit movement")
	_ok(first.intents[0].category == "confirmed_engage", "confirmed contact records engage intent")
	var tie := confirmed.duplicate(true); tie.contacts.append({"contact_id": "CONTACT-A", "state": "confirmed", "disposition": "hostile", "display_position": [120, 100], "confidence_basis_points": 10000, "staleness_turns": 0})
	_eq(planner.plan(tie, cao_resources, 1).intents[0].contact_id, "CONTACT-A", "equal-priority target tie uses stable contact ID")
	var invalid := confirmed.duplicate(true); invalid.erase("own_navigation"); var before_invalid := JSON.stringify(invalid)
	_ok(not planner.plan(invalid, cao_resources, 1).ok, "malformed viewer snapshot rejected"); _eq(JSON.stringify(invalid), before_invalid, "invalid planner input remains atomic")

func _test_integration_same_resolvers_manual_parity_and_redaction() -> void:
	var setup := _fixture(); var ai = _battle(setup); var manual = _battle(setup)
	for battle in [ai, manual]:
		battle.submit_command_draft(); battle.submit_sun_control_choice("no"); _ok(battle.resolve_turn().ok, "turn1 AI resolves through full stack"); battle.continue_turn()
	ai.submit_command_draft(); _ok(ai.submit_sun_control_choice("no").ok, "turn2 Sun AI plan prepared")
	var sun_decision: Dictionary = ai.viewer_ai_decision("sun_quan", 2); var cao_decision: Dictionary = ai.viewer_ai_decision("cao_cao", 2)
	_ok(sun_decision.ok and sun_decision.available and cao_decision.ok and cao_decision.available, "each AI can query only its own decision")
	_eq(sun_decision.source, "normal-demo-ai-v1", "AI receipt names rules authority")
	_ok(not ai.viewer_ai_decision("liu_bei", 2).ok, "Liu cannot query another faction raw AI decision")
	var liu_log := JSON.stringify(ai.viewer_turn_log("liu_bei")); _ok(not liu_log.contains("sun_ai_decision") and not liu_log.contains("cao_ai_decision"), "Liu viewer log leaks no raw AI plan")

	manual.submit_command_draft(); manual.submit_sun_control_choice("yes")
	for order in sun_decision.orders:
		if String(order.action) == "move": manual.set_order_move(String(order.squadron_id), order.waypoints, order.facing_deg)
		else: manual.set_order_hold(String(order.squadron_id))
	for order in sun_decision.formation_orders: manual.set_formation_order(String(order.squadron_id), String(order.formation_id))
	for order in sun_decision.weapon_allocation_orders:
		manual.apply_weapon_preset(String(order.squadron_id), "screen")
		manual.set_hold_fire(String(order.squadron_id), bool(order.hold_fire))
	for order in sun_decision.estimated_fire_orders: manual.set_estimated_fire(String(order.squadron_id), String(order.contact_id))
	_ok(manual.submit_command_draft().ok, "manual Sun submits the same command bundle")
	var ai_receipt: Dictionary = ai.resolve_turn(); var manual_receipt: Dictionary = manual.resolve_turn()
	_ok(ai_receipt.ok and manual_receipt.ok, "AI and manual bundles use downstream resolvers")
	_eq(ai.live_navigation(), manual.live_navigation(), "manual and AI equivalent movement resolve identically")
	_eq(ai.formation_state(), manual.formation_state(), "manual and AI equivalent formation resolves identically")
	_eq(ai.weapon_allocation_state(), manual.weapon_allocation_state(), "manual and AI equivalent weapon allocation resolves identically")
	_eq(ai.combat_resource_state(), manual.combat_resource_state(), "manual and AI equivalent resource reservations resolve identically")
	_ok(not ai_receipt.has("hit") and not ai_receipt.has("damage") and not ai_receipt.has("winner"), "AI creates no hit damage or winner")

func _test_determinism_deep_copy_and_resource_conservation() -> void:
	var setup := _fixture(); var a = _battle(setup); var b = _battle(setup)
	for battle in [a, b]: battle.submit_command_draft(); battle.submit_sun_control_choice("no")
	_eq(a.viewer_ai_decision("sun_quan"), b.viewer_ai_decision("sun_quan"), "Sun AI decision is deterministic")
	_eq(a.viewer_ai_decision("cao_cao"), b.viewer_ai_decision("cao_cao"), "Cao AI decision is deterministic")
	var sun_no_contact: Dictionary = a.viewer_ai_decision("sun_quan")
	_eq(sun_no_contact.formation_orders[0].formation_id, a.formation_state()["RC-SUN-SQ-01"].formation_id, "integrated Sun no-contact keeps current formation")
	_eq(sun_no_contact.weapon_allocation_orders[0].allocations, a.weapon_allocation_state()["RC-SUN-SQ-01"].allocations, "integrated Sun no-contact keeps weapon allocation")
	var copy: Dictionary = a.viewer_ai_decision("cao_cao"); copy.orders.clear(); _ok(not a.viewer_ai_decision("cao_cao").orders.is_empty(), "AI decision query is deep copied")
	var before: Dictionary = a.combat_resource_state(); var first: Dictionary = a.resolve_turn(); _ok(first.ok, "first resolve succeeds")
	var after: Dictionary = a.combat_resource_state(); _ok(_resources_never_increase(before, after), "resolution cannot grant AI free finite resources on turn1")
	var digest := a.digest(); _ok(not a.resolve_turn().ok, "duplicate resolve rejected"); _eq(a.digest(), digest, "duplicate resolve cannot consume twice")
	b.resolve_turn(); _eq(a.combat_resource_state(), b.combat_resource_state(), "replay consumes resources deterministically")
	_ok(a.continue_turn().ok, "turn2 opens for scheduled recovery preview")
	var authoritative_before := a.combat_resource_state(); var preview: Dictionary = a.scheduled_resource_preview("cao_cao")
	_ok(preview.ok and preview.scheduled_recovery_events.size() == 1, "own preview applies turn2 scheduled recovery once on a copy")
	_eq(a.combat_resource_state(), authoritative_before, "scheduled preview never mutates authoritative resources")
	var preview_copy := preview.duplicate(true); preview_copy.resource_state.clear(); _ok(not a.scheduled_resource_preview("cao_cao").resource_state.is_empty(), "scheduled resource preview is deep copied")

func _resources_never_increase(before: Dictionary, after: Dictionary) -> bool:
	for squadron_id in before:
		if int(after[squadron_id].shared.energy) > int(before[squadron_id].shared.energy) or int(after[squadron_id].shared.heat) < int(before[squadron_id].shared.heat): return false
		for weapon_id in before[squadron_id].weapons:
			for key in ["ammo", "carrier_ready", "special"]:
				if int(after[squadron_id].weapons[weapon_id][key]) > int(before[squadron_id].weapons[weapon_id][key]): return false
	return true
