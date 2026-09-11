extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G5-02 — 센서·전자전·진형·장수 탐지 보정
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Draft := preload("res://core/demo_red_cliffs/red_cliffs_formation_draft.gd")
const Detection := preload("res://core/demo_red_cliffs/red_cliffs_detection_resolver.gd")
const Interception := preload("res://core/demo_red_cliffs/red_cliffs_interception_resolver.gd")
const Movement := preload("res://core/demo_red_cliffs/red_cliffs_movement_resolver.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")

var _pass := 0; var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G5-02 sensor EW formation intelligence detection")
	_test_rules_score_ties_and_formation()
	_test_character_authority_and_invalid_crosscheck()
	_test_all_editable_reserve_commanders_apply_into_detection()
	_test_multi_observer_merge_viewer_redaction_atomicity()
	_test_battle_estimated_fire_phase_resource_regression()
	print("PASS %d / FAIL %d" % [_pass, _fail]); quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _setup() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads"); return loaded.setup.duplicate(true)

func _resolver(setup: Dictionary):
	var resolver = Detection.new(); var initialized: Dictionary = resolver.initialize(setup)
	_ok(initialized.ok, "sensor/EW resolver initializes: %s" % str(initialized.get("errors", []))); return resolver

func _test_rules_score_ties_and_formation() -> void:
	var setup := _setup(); var resolver = _resolver(setup); var rules: Dictionary = resolver.rules_snapshot()
	_eq(rules.profile_id, "normal-demo-sensor-ew-v1", "single normal demo sensor/EW profile")
	_eq(rules.thresholds, {"confirmed": 37.0, "estimated": 15.0}, "thresholds data-owned")
	_eq(resolver.call("_percent_round_half_up", 10, 5), 11, "positive half-point rounds up deterministically")
	_eq(rules.fast_equipment_sensor_points["FAST-EQ-RECON"], 6.0, "structured recon equipment sensor value is data-owned")
	_eq(rules.terrain.status, "active_normal_demo", "G5-03 terrain integration is explicit")
	var formation := resolver.initial_formation_state()
	var tie: Dictionary = resolver.evaluate("RC-LIU-SQ-01", "RC-CAO-SQ-01", 199.0, formation)
	_ok(tie.ok, "score evaluation succeeds"); _eq(tie.authoritative.score, 37, "exact confirmed threshold fixture")
	_eq(tie.state, "confirmed", "exact score tie is in-range")
	var outside: Dictionary = resolver.evaluate("RC-LIU-SQ-01", "RC-CAO-SQ-01", 200.0, formation)
	_eq(outside.state, "estimated", "one distance-penalty step changes to estimated")
	var farther: Dictionary = resolver.evaluate("RC-LIU-SQ-01", "RC-CAO-SQ-01", 225.0, formation)
	_ok(int(farther.authoritative.score) < int(outside.authoritative.score), "greater distance monotonically lowers score")
	_eq(outside.authoritative.target_ew_points, 14, "target EW derived from structured composition")
	_eq(outside.authoritative.own_sensor_breakdown.intelligence_sensor_points, 12, "Liu intelligence 76 uses configured band")
	var boosted := formation.duplicate(true); boosted["RC-LIU-SQ-01"].formation_id = "FRM-07"
	var formation_result: Dictionary = resolver.evaluate("RC-LIU-SQ-01", "RC-CAO-SQ-01", 200.0, boosted)
	_eq(formation_result.authoritative.formation_detection_percent, 10, "formation resolver detection modifier reused")
	_eq(formation_result.state, "confirmed", "positive formation modifier affects score")
	_ok(int(formation_result.authoritative.score) > int(outside.authoritative.score), "positive own formation modifier monotonically raises score")
	_ok(not resolver.evaluate("RC-LIU-SQ-01", "RC-CAO-SQ-01", -1.0, formation).ok, "negative distance rejected")

func _test_character_authority_and_invalid_crosscheck() -> void:
	var setup := _setup(); var baseline = _resolver(setup)
	var baseline_eval: Dictionary = baseline.evaluate("RC-LIU-SQ-01", "RC-CAO-SQ-01", 200.0, baseline.initial_formation_state())
	var changed := setup.duplicate(true)
	for faction in changed.factions:
		if String(faction.id) == "liu_bei":
			for commander in faction.demo_roster:
				if String(commander.id) == "CHR-0128": commander.command = 0; commander.level = 0
	var changed_resolver = _resolver(changed)
	var changed_eval: Dictionary = changed_resolver.evaluate("RC-LIU-SQ-01", "RC-CAO-SQ-01", 200.0, changed_resolver.initial_formation_state())
	_eq(changed_eval.authoritative.score, baseline_eval.authoritative.score, "roster command/level do not affect detection")
	var mismatch := setup.duplicate(true)
	for squad in mismatch.squadrons:
		if String(squad.id) == "RC-LIU-SQ-01": squad.commander.name = "가짜 유비"
	for faction in mismatch.factions:
		if String(faction.id) == "liu_bei":
			for commander in faction.demo_roster:
				if String(commander.id) == "CHR-0128": commander.name = "가짜 유비"
	_ok(Setup.validate_document(mismatch).ok, "fixture remains valid at G2 boundary")
	var rejected = Detection.new(); _ok(not rejected.initialize(mismatch).ok, "assigned commander ID+name mismatch with characters.json rejected")

func _test_all_editable_reserve_commanders_apply_into_detection() -> void:
	var setup := _setup()
	var zhao_detector = Detection.new(); _ok(zhao_detector.initialize(setup).ok, "조운 assigned fast-craft commander initializes detection")
	var cases := [["RC-LIU-SQ-01", "CHR-0107", "관우", false],
		["RC-SUN-SQ-01", "CHR-0186", "노숙", true]]
	for row in cases:
		var editable_setup: Dictionary = setup.duplicate(true)
		if bool(row[3]): editable_setup.formation_options.sun_manual = true
		var editor = Draft.new(editable_setup)
		_ok(editor.set_commander(String(row[0]), String(row[1])).ok, "%s reserve commander stages" % row[2])
		var applied: Dictionary = editor.apply()
		_ok(applied.ok, "%s reserve commander applies through G3" % row[2])
		var detector = Detection.new()
		_ok(detector.initialize(applied.setup).ok, "%s canonical ID/name initializes G5 detection" % row[2])
	# Cao remains AI-only in G3, so its reserve roster is checked without opening
	# a forbidden editor permission path.
	for row in [["CHR-0033", "조인"], ["CHR-0043", "하후돈"]]:
		var cao_setup: Dictionary = setup.duplicate(true)
		for squad in cao_setup.squadrons:
			if String(squad.id) == "RC-CAO-SQ-01": squad.commander = {"id": String(row[0]), "name": String(row[1])}
		_ok(Setup.validate_document(cao_setup).ok, "%s AI roster remains a valid G3 setup" % row[1])
		var detector = Detection.new()
		_ok(detector.initialize(cao_setup).ok, "%s canonical ID/name initializes G5 detection" % row[1])

func _test_multi_observer_merge_viewer_redaction_atomicity() -> void:
	var setup := _setup(); var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 100], "RC-LIU-FC-01": [1600, 900], "RC-SUN-SQ-01": [100, 700], "RC-CAO-SQ-01": [300, 100]}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	var movement = Movement.new(); movement.initialize(setup); var moved: Dictionary = movement.resolve_orders(_holds(setup), movement.initial_navigation())
	var interception = Interception.new(); _ok(interception.initialize(setup).ok, "interception initializes G5-02")
	var prior := interception.initial_detection_state(); var digest := JSON.stringify(prior)
	var resolved: Dictionary = interception.resolve(moved.events, moved.live_navigation, prior, 1)
	_ok(resolved.ok, "multi-observer detection resolves"); _eq(JSON.stringify(prior), digest, "detection input deep-copy preserved")
	_eq(JSON.stringify(resolved), JSON.stringify(interception.resolve(moved.events, moved.live_navigation, prior, 1)), "same input detection replay deterministic")
	var contacts: Dictionary = interception.visible_contacts("liu_bei", resolved.detection_state, moved.live_navigation)
	_eq(contacts.contacts.size(), 1, "multiple observers merge to one target contact")
	var contact: Dictionary = contacts.contacts[0]
	_eq(contact.source_observer_squadron_id, "RC-LIU-SQ-01", "stronger state/margin observer wins deterministically")
	_ok(contact.detection_rationale.own_sensor_breakdown.ship_sensor_points > 0, "viewer receives own sensor breakdown")
	var public_json := JSON.stringify(contacts)
	_ok(not public_json.contains("target_squadron_id"), "estimated merged contact hides exact target identity")
	for forbidden in ["target_ew_points", "distance_penalty", "\"score\":", "\"margin\":", "confirmed_range", "estimated_range"]:
		_ok(not public_json.contains(forbidden), "viewer omits enemy/threshold inference field %s" % forbidden)
	_ok(public_json.contains("active_normal_demo"), "viewer sees active terrain rationale")
	var invalid_formation := {}; var invalid := interception.resolve(moved.events, moved.live_navigation, prior, 1, {}, invalid_formation)
	# Empty means initial formation by compatibility; a malformed non-empty state must reject.
	invalid_formation = {"RC-LIU-SQ-01": {"formation_id": "BAD"}}
	invalid = interception.resolve(moved.events, moved.live_navigation, prior, 1, {}, invalid_formation)
	_ok(not invalid.ok, "malformed formation state rejected"); _eq(JSON.stringify(prior), digest, "invalid evaluation atomic")

func _test_battle_estimated_fire_phase_resource_regression() -> void:
	var setup := _setup(); var positions := {"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 100], "RC-LIU-FC-01": [1600, 900], "RC-SUN-SQ-01": [100, 100], "RC-CAO-SQ-01": [400, 100]}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	var battle = Battle.new(); _ok(battle.initialize(setup).ok, "battle initializes G5-02")
	battle.submit_command_draft(); battle.submit_sun_control_choice("ai"); var first: Dictionary = battle.resolve_turn(); _ok(first.ok, "AI/manual-neutral detection turn resolves")
	var manual_battle = Battle.new(); manual_battle.initialize(setup); manual_battle.submit_command_draft(); manual_battle.submit_sun_control_choice("manual"); manual_battle.submit_command_draft()
	var manual_first: Dictionary = manual_battle.resolve_turn(); _ok(manual_first.ok, "manual Sun detection turn resolves")
	_eq(JSON.stringify(first.detection_events), JSON.stringify(manual_first.detection_events), "AI and manual control use identical detection resolver")
	battle.continue_turn(); var contacts: Array = battle.visible_contacts("liu_bei").contacts
	var estimated := contacts.filter(func(row): return String(row.get("state", "")) == "estimated")
	_ok(not estimated.is_empty(), "estimated-fire contact remains available")
	_ok(battle.set_estimated_fire("RC-LIU-SQ-02", String(estimated[0].contact_id)).ok, "estimated fire stages after G5-02")
	battle.submit_command_draft(); battle.submit_sun_control_choice("ai"); var second: Dictionary = battle.resolve_turn(); _ok(second.ok, "estimated fire/resource/phase resolve")
	_ok(second.estimated_fire_events.size() + second.estimated_fire_suppressed_events.size() >= 1, "estimated fire receipt preserved")
	_ok(battle.viewer_phase("liu_bei", "barrage", 2).ok, "five-phase viewer ledger preserved")
	_ok(not second.has("hit") and not second.has("damage") and not second.has("winner"), "no hit damage winner fabricated")

func _holds(setup: Dictionary) -> Array:
	var result: Array = []
	for squad in setup.squadrons:
		if bool(squad.get("operational", true)): result.append({"squadron_id": String(squad.id), "action": "hold"})
	return result
