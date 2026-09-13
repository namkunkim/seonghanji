extends SceneTree

## S5-02 — viewer-safe 3D evidence projection contract.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")

const VIEWERS := ["liu_bei", "sun_quan", "cao_cao"]
const FORBIDDEN_KEYS := [
	"actual_position", "applied_setup", "authoritative", "command_draft",
	"live_navigation", "resolution_receipt", "snapshot", "target_squadron_id",
]

var _pass := 0
var _fail := 0


func _init() -> void:
	call_deferred("_run")


func _ok(value: bool, label: String) -> void:
	if value:
		_pass += 1
	else:
		_fail += 1
		print("  x %s" % label)


func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])


func _run() -> void:
	print("S5-02 viewer-safe 3D projection")
	var loaded: Dictionary = Setup.load_default()
	_ok(loaded.ok, "default setup loads")
	if not loaded.ok:
		_finish()
		return
	var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {
		"RC-LIU-SQ-01": [100, 100], "RC-LIU-SQ-02": [100, 800],
		"RC-LIU-FC-01": [1600, 900], "RC-SUN-SQ-01": [100, 700],
		"RC-CAO-SQ-01": [400, 100],
	}
	for squadron in setup.squadrons:
		squadron.initial_position = positions[String(squadron.id)].duplicate()
		if String(squadron.id) == "RC-CAO-SQ-01":
			squadron.initial_facing_deg = 180
	var battle = Battle.new()
	var initialized: Dictionary = battle.initialize(setup)
	_ok(initialized.ok, "battle initializes: %s" % str(initialized.get("errors", [])))
	if not initialized.ok:
		_finish()
		return

	_test_initial_projection(battle)
	_test_resolved_event_order(battle)
	_test_three_viewer_opaque_contacts(battle)
	_test_invalid_viewer_is_atomic(battle)
	_finish()


func _test_initial_projection(battle) -> void:
	var digest_before: String = battle.digest()
	var first: Dictionary = battle.viewer_3d_projection("liu_bei")
	var second: Dictionary = battle.viewer_3d_projection("liu_bei")
	_ok(first.ok, "Liu projection succeeds")
	_eq(first.get("profile_id", ""), "S5-02", "projection identifies S5-02 profile")
	_eq(first, second, "same state produces byte-stable projection ordering")
	_eq(battle.digest(), digest_before, "projection query does not mutate battle state")
	_ok(_is_json_primitive_tree(first), "projection contains JSON primitives only")
	_ok(not _contains_forbidden_key(first), "projection contains no authoritative/private field names")
	_ok(not JSON.stringify(first).contains("RC-CAO-SQ-"), "Liu projection does not disclose Cao squadron ids")
	_ok(first.has("battlefield_bounds") and first.has("terrain_zones"), "projection carries public battlefield evidence")
	_ok(first.get("own_squadrons", []).size() == 3, "Liu receives exact own squadron rows")
	_ok(first.get("event_ordering", "") == "turn_event_id_event_type_ascending", "stable event ordering contract is explicit")
	_ok(String(first.get("visual_seed", "")).length() == 64, "projection has deterministic SHA-256 visual seed")

	var mutated := first.duplicate(true)
	mutated["battlefield_bounds"].clear()
	mutated["own_squadrons"][0]["position"].clear()
	mutated["contacts"].clear()
	var fresh: Dictionary = battle.viewer_3d_projection("liu_bei")
	_eq(fresh, first, "caller mutation cannot alter subsequent projection")
	_eq(battle.digest(), digest_before, "deep-copy mutation cannot alter battle state")


func _test_three_viewer_opaque_contacts(battle) -> void:
	for viewer in VIEWERS:
		var digest_before: String = battle.digest()
		var projection: Dictionary = battle.viewer_3d_projection(viewer)
		_ok(projection.ok, "%s projection succeeds" % viewer)
		_ok(not projection.get("contacts", []).is_empty(), "%s receives at least one visible contact proxy" % viewer)
		var contacts_are_opaque := true
		for contact in projection.get("contacts", []):
			contacts_are_opaque = contacts_are_opaque and contact is Dictionary
			contacts_are_opaque = contacts_are_opaque and not contact.has("target_squadron_id")
			contacts_are_opaque = contacts_are_opaque and not contact.has("actual_position")
			contacts_are_opaque = contacts_are_opaque and String(contact.get("contact_id", "")).begins_with("CONTACT-")
			contacts_are_opaque = contacts_are_opaque and ["confirmed", "estimated"].has(String(contact.get("state", "")))
		_ok(contacts_are_opaque, "%s contacts remain opaque display proxies" % viewer)
		_ok(_is_sorted_by_key(projection.get("own_squadrons", []), "squadron_id"), "%s own rows are deterministically sorted" % viewer)
		_ok(_is_sorted_by_key(projection.get("contacts", []), "contact_id"), "%s contacts are deterministically sorted" % viewer)
		_eq(battle.digest(), digest_before, "%s projection is state-immutable" % viewer)


func _test_resolved_event_order(battle) -> void:
	_ok(battle.set_order_move("RC-LIU-SQ-01", [[240, 100]], 0).ok, "turn-one visible interception move stages")
	_ok(battle.submit_command_draft().ok, "turn-one Liu draft submits")
	_ok(battle.submit_sun_control_choice("no", true).ok, "turn-one Sun AI policy submits")
	var resolved: Dictionary = battle.resolve_turn()
	_ok(resolved.ok, "turn one resolves: %s" % str(resolved.get("errors", [])))
	if not resolved.ok:
		return
	var digest_before: String = battle.digest()
	var projection: Dictionary = battle.viewer_3d_projection("liu_bei")
	var repeated: Dictionary = battle.viewer_3d_projection("liu_bei")
	_eq(projection, repeated, "resolved event projection remains deterministic")
	_eq(battle.digest(), digest_before, "resolved projection query does not mutate state")
	_ok(not projection.get("events", []).is_empty(), "resolved projection exposes viewer-visible evidence events")
	var ordered := true
	for index in range(projection.get("events", []).size()):
		var event: Dictionary = projection.events[index]
		ordered = ordered and int(event.get("visual_order", -1)) == index
		ordered = ordered and String(event.get("visual_seed", "")).length() == 64
		if index > 0:
			ordered = ordered and _event_key(projection.events[index - 1]) <= _event_key(event)
	_ok(ordered, "events carry contiguous visual order and stable sorted seeds")
	_ok(_is_json_primitive_tree(projection), "resolved projection remains JSON primitive")
	_ok(not _contains_forbidden_key(projection), "resolved projection contains no forbidden private keys")


func _test_invalid_viewer_is_atomic(battle) -> void:
	var digest_before: String = battle.digest()
	var rejected: Dictionary = battle.viewer_3d_projection("unknown_faction")
	_ok(not rejected.ok, "unknown viewer is rejected")
	_eq(battle.digest(), digest_before, "unknown viewer rejection is atomic")


func _contains_forbidden_key(value) -> bool:
	if value is Dictionary:
		for key in value.keys():
			if FORBIDDEN_KEYS.has(String(key)):
				return true
			if _contains_forbidden_key(value[key]):
				return true
	elif value is Array:
		for child in value:
			if _contains_forbidden_key(child):
				return true
	return false


func _is_json_primitive_tree(value) -> bool:
	if value == null or value is bool or value is int or value is float or value is String:
		return true
	if value is Array:
		for child in value:
			if not _is_json_primitive_tree(child):
				return false
		return true
	if value is Dictionary:
		for key in value.keys():
			if not key is String or not _is_json_primitive_tree(value[key]):
				return false
		return true
	return false


func _is_sorted_by_key(rows: Array, key: String) -> bool:
	for index in range(1, rows.size()):
		if String(rows[index - 1].get(key, "")) > String(rows[index].get(key, "")):
			return false
	return true


func _event_key(event: Dictionary) -> String:
	return "%08d|%s|%s" % [int(event.get("turn", 0)), String(event.get("event_id", "")), String(event.get("event_type", ""))]


func _finish() -> void:
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)
