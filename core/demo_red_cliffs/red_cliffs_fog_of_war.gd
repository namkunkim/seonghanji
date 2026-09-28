class_name RedCliffsFogOfWar
extends RefCounted

## DEMO-RC-G5-01 — contact 수명과 실제 위치를 쓰지 않는 추정 사격 권위.
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Terrain := preload("res://core/demo_red_cliffs/red_cliffs_terrain_resolver.gd")
const RULES_PATH := "res://data/red-cliffs-fog-of-war-rules.json"

var _setup: Dictionary = {}
var _rules: Dictionary = {}
var _terrain


func initialize(applied_setup: Dictionary) -> Dictionary:
	var checked := Setup.validate_document(applied_setup)
	if not checked.ok: return _error("유효한 G3 적용 편성이 필요합니다.")
	var loaded := _load_rules()
	if not loaded.ok: return loaded
	var terrain = Terrain.new(); var terrain_result: Dictionary = terrain.initialize(checked.setup)
	if not terrain_result.ok: return terrain_result
	_setup = checked.setup.duplicate(true); _rules = loaded.rules.duplicate(true); _terrain = terrain
	return _ok()


func rules_snapshot() -> Dictionary: return _rules.duplicate(true)


func contact_id(viewer_faction_id: String, target_squadron_id: String) -> String:
	return "CONTACT-%s" % ("%s|%s|%s" % [_rules.deterministic_seed, viewer_faction_id, target_squadron_id]).sha256_text().substr(0, 12)


func initial_contact_fields() -> Dictionary:
	return {"staleness_turns": 0, "confidence_basis_points": 0, "error_radius": 0, "expires_after_turn": 0}


func transition(previous: Dictionary, sensor_state: String, observed_position, turn_number: int) -> Dictionary:
	var next := previous.duplicate(true)
	if sensor_state == "confirmed":
		next.state = "confirmed"; next.last_known_position = observed_position.duplicate(); next.last_seen_turn = turn_number
		next.staleness_turns = 0; next.confidence_basis_points = 10000; next.error_radius = 0
		next.expires_after_turn = turn_number + int(_rules.contact_lifecycle.estimated_memory_turns)
	elif sensor_state == "estimated":
		next.state = "estimated"; next.last_known_position = observed_position.duplicate(); next.last_seen_turn = turn_number
		next.staleness_turns = 0; next.confidence_basis_points = int(_rules.contact_lifecycle.estimated_confidence_basis_points)
		next.error_radius = int(_rules.contact_lifecycle.base_error_radius)
		next.expires_after_turn = turn_number + int(_rules.contact_lifecycle.estimated_memory_turns)
	elif int(next.get("last_seen_turn", 0)) > 0:
		var stale := turn_number - int(next.last_seen_turn)
		if stale <= 2:
			next.state = "estimated"; next.staleness_turns = stale
			next.confidence_basis_points = maxi(int(_rules.contact_lifecycle.minimum_confidence_basis_points),
				int(_rules.contact_lifecycle.estimated_confidence_basis_points) - stale * int(_rules.contact_lifecycle.stale_confidence_loss_per_turn))
			next.error_radius = int(_rules.contact_lifecycle.base_error_radius) + stale * int(_rules.contact_lifecycle.error_radius_per_stale_turn)
		elif stale == int(_rules.contact_lifecycle.estimated_memory_turns):
			next.state = "lost"; next.staleness_turns = stale
			next.confidence_basis_points = int(_rules.contact_lifecycle.minimum_confidence_basis_points)
			next.error_radius = int(_rules.contact_lifecycle.base_error_radius) + stale * int(_rules.contact_lifecycle.error_radius_per_stale_turn)
		else:
			next.state = "undetected"; next.last_known_position = null; next.staleness_turns = stale
			next.confidence_basis_points = 0; next.error_radius = 0
	else:
		next.state = "undetected"
	return next


func make_order(viewer_faction_id: String, shooter_squadron_id: String, contact: Dictionary,
		turn_number: int) -> Dictionary:
	if _squadron_faction(shooter_squadron_id) != viewer_faction_id:
		return _error("관측 세력의 전대만 추정 사격을 명령할 수 있습니다.")
	if String(contact.get("state", "")) != "estimated" or not contact.get("last_known_position") is Array:
		return _error("추정 상태 contact만 추정 사격 대상으로 선택할 수 있습니다.")
	var contact_id_value := String(contact.get("contact_id", ""))
	if contact_id_value.is_empty(): return _error("opaque contact ID가 필요합니다.")
	var error_radius := int(contact.get("error_radius", 0)); var offset := _deterministic_error(contact_id_value, shooter_squadron_id, turn_number, error_radius)
	var last_known: Array = contact.last_known_position.duplicate()
	var aim := _clamped_aim(last_known, offset)
	return {"ok": true, "errors": [], "order": {"squadron_id": shooter_squadron_id,
		"contact_id": contact_id_value, "last_known_position": last_known,
		"aim_position": aim,
		"last_seen_turn": int(contact.get("last_seen_turn", 0)), "staleness_turns": int(contact.get("staleness_turns", 0)),
		"confidence_basis_points": int(contact.get("confidence_basis_points", 0)), "confidence_label": "low",
		"error_radius": error_radius, "error_offset": offset, "issued_turn": turn_number}}


func authorize_orders(orders: Array, shooter_faction_id: String, live_navigation: Dictionary,
		weapon_policy: Dictionary, turn_number: int, temporary_zones: Array = []) -> Dictionary:
	var events: Array = []; var suppressed: Array = []; var seen := {}
	var sorted := orders.duplicate(true); sorted.sort_custom(func(a, b): return String(a.get("squadron_id", "")) < String(b.get("squadron_id", "")))
	for value in sorted:
		if not value is Dictionary: return _error("추정 사격 명령은 객체여야 합니다.")
		var order: Dictionary = value; var shooter_id := String(order.get("squadron_id", ""))
		if seen.has(shooter_id) or _squadron_faction(shooter_id) != shooter_faction_id: return _error("미지·중복 또는 타 세력 추정 사격 명령입니다: %s" % shooter_id)
		seen[shooter_id] = true
		var valid := _validate_sealed_order(order, turn_number)
		if not valid.ok: return valid
		if not live_navigation.has(shooter_id) or not weapon_policy.has(shooter_id): return _error("추정 사격 shooter 상태가 누락되었습니다: %s" % shooter_id)
		if bool(weapon_policy[shooter_id].hold_fire):
			suppressed.append(_suppressed(order, turn_number, "hold_fire", "사격 보류")); continue
		var selected := _select_weapon(order.aim_position, live_navigation[shooter_id], weapon_policy[shooter_id], temporary_zones)
		if selected.is_empty(): suppressed.append(_suppressed(order, turn_number, "weapon_ineligible", "추정 좌표에 적격 무기 없음")); continue
		var event_id := _event_id(turn_number, shooter_id, String(order.contact_id))
		events.append({"event_id": event_id, "event_type": "estimated_fire_authorized", "outcome": "estimated_fire_authorized",
			"turn": turn_number, "shooter_squadron_id": shooter_id, "contact_id": String(order.contact_id),
			"last_known_position": order.last_known_position.duplicate(), "aim_position": order.aim_position.duplicate(),
			"last_seen_turn": int(order.last_seen_turn), "staleness_turns": int(order.staleness_turns),
			"confidence_basis_points": int(order.confidence_basis_points), "confidence_label": "low",
			"error_radius": int(order.error_radius), "error_offset": order.error_offset.duplicate(),
			"selected_weapon_id": String(selected.weapon_id), "selected_platform_id": String(selected.platform_id),
			"allocation_basis_points": int(selected.allocation_basis_points),
			"terrain_weapon_modifier": selected.terrain_weapon_modifier.duplicate(true),
			"fire_control_snapshot": {"hold_fire": false, "allocations": weapon_policy[shooter_id].allocations.duplicate(true),
				"selected_weapon_id": String(selected.weapon_id), "selected_platform_id": String(selected.platform_id),
				"selected_allocation_basis_points": int(selected.allocation_basis_points),
				"eligibility": {"range": int(selected.range), "arc_deg": float(selected.arc_deg)}},
			"actual_target_position_used": false, "resource_gate_pending": true,
			"result_pending": _rules.estimated_fire.result_pending.duplicate()})
	return {"ok": true, "errors": [], "estimated_fire_events": events, "suppressed_events": suppressed}


func visible_events(viewer_faction_id: String, receipt: Dictionary) -> Dictionary:
	var events: Array = []
	for source in ["estimated_fire_events", "estimated_fire_suppressed_events"]:
		for value in receipt.get(source, []):
			if value is Dictionary and _squadron_faction(String(value.get("shooter_squadron_id", value.get("squadron_id", "")))) == viewer_faction_id:
				events.append(value.duplicate(true))
	events.sort_custom(func(a, b): return String(a.get("event_id", "")) < String(b.get("event_id", "")))
	return {"ok": true, "errors": [], "viewer_faction_id": viewer_faction_id, "events": events}


func _select_weapon(aim_position: Array, navigation: Dictionary, policy: Dictionary, temporary_zones: Array = []) -> Dictionary:
	var vector := Vector2(float(aim_position[0]) - float(navigation.position[0]), float(aim_position[1]) - float(navigation.position[1]))
	var distance := vector.length(); var facing := float(navigation.facing_deg)
	var bearing := facing if distance <= 0.000001 else fposmod(rad_to_deg(atan2(vector.y, vector.x)), 360.0)
	var delta := absf(wrapf(bearing - facing, -180.0, 180.0)); var eligible: Array = []
	for value in policy.capabilities:
		var capability: Dictionary = value; var weapon_id := String(capability.weapon_id); var allocation := int(policy.allocations.get(weapon_id, 0))
		var terrain_effect: Dictionary = _terrain.weapon_effect(navigation.position, aim_position, "sealed_estimated_aim", temporary_zones)
		var effective_range := int(floor(float(int(capability.range) * int(terrain_effect.range_basis_points) + 5000) / 10000.0))
		var effective_arc := clampf(float(capability.arc_deg) + float(terrain_effect.arc_delta_deg), 0.0, 360.0)
		if allocation > 0 and distance <= float(effective_range) and delta <= effective_arc * 0.5 + 0.000001:
			var row: Dictionary = capability.duplicate(true); row.allocation_basis_points = allocation; row.range = effective_range; row.arc_deg = effective_arc; row.terrain_weapon_modifier = terrain_effect; eligible.append(row)
	eligible.sort_custom(func(a, b):
		if int(a.allocation_basis_points) != int(b.allocation_basis_points): return int(a.allocation_basis_points) > int(b.allocation_basis_points)
		return String(a.weapon_id) < String(b.weapon_id))
	return {} if eligible.is_empty() else eligible[0]


func _validate_sealed_order(order: Dictionary, turn_number: int) -> Dictionary:
	var required := ["squadron_id", "contact_id", "last_known_position", "aim_position", "last_seen_turn", "staleness_turns", "confidence_basis_points", "confidence_label", "error_radius", "error_offset", "issued_turn"]
	for key in required:
		if not order.has(key): return _error("추정 사격 봉인 필드 누락: %s" % key)
	if int(order.issued_turn) != turn_number or String(order.confidence_label) != "low": return _error("추정 사격 턴·신뢰도 경계가 잘못되었습니다.")
	if not _valid_point(order.last_known_position) or not _valid_point(order.aim_position) or not _valid_point(order.error_offset): return _error("추정 사격 좌표가 잘못되었습니다.")
	var expected_offset := _deterministic_error(String(order.contact_id), String(order.squadron_id), turn_number, int(order.error_radius))
	if order.error_offset != expected_offset: return _error("추정 사격 결정론적 오차가 변조되었습니다.")
	var expected_aim := _clamped_aim(order.last_known_position, expected_offset)
	if Vector2(float(order.aim_position[0]), float(order.aim_position[1])).distance_to(Vector2(float(expected_aim[0]), float(expected_aim[1]))) > 0.000001: return _error("추정 사격 aim이 last-known+오차와 다릅니다.")
	return _ok()


func _deterministic_error(contact_id_value: String, shooter_id: String, turn_number: int, radius: int) -> Array:
	if radius <= 0: return [0.0, 0.0]
	var hash := ("%s|%s|%s|%d" % [_rules.deterministic_seed, contact_id_value, shooter_id, turn_number]).sha256_text()
	var angle_units := hash.substr(0, 8).hex_to_int() % 360000; var radial_units := hash.substr(8, 8).hex_to_int() % 10001
	var angle := deg_to_rad(float(angle_units) / 1000.0); var magnitude := float(radius) * float(radial_units) / 10000.0
	return [snappedf(cos(angle) * magnitude, 0.001), snappedf(sin(angle) * magnitude, 0.001)]


func _clamped_aim(last_known: Array, offset: Array) -> Array:
	var bounds: Array = _setup.get("battlefield_bounds", [0, 0, 1600, 900])
	return [clampf(float(last_known[0]) + float(offset[0]), float(bounds[0]), float(bounds[2])),
		clampf(float(last_known[1]) + float(offset[1]), float(bounds[1]), float(bounds[3]))]


func _suppressed(order: Dictionary, turn_number: int, reason: String, label: String) -> Dictionary:
	return {"event_id": "EST-SUP-%s" % _event_id(turn_number, String(order.squadron_id), String(order.contact_id)),
		"event_type": "estimated_fire_suppressed", "turn": turn_number, "squadron_id": String(order.squadron_id),
		"contact_id": String(order.contact_id), "reason": reason, "reason_label": label}


func _event_id(turn_number: int, shooter_id: String, contact_id_value: String) -> String:
	return "EST-FIRE-%02d-%s" % [turn_number, ("%s|%d|%s|%s" % [_rules.deterministic_seed, turn_number, shooter_id, contact_id_value]).sha256_text().substr(0, 16)]


func _squadron_faction(squadron_id: String) -> String:
	for squad in _setup.get("squadrons", []):
		if String(squad.id) == squadron_id: return String(squad.faction_id)
	return ""


func _valid_point(value) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))


func _load_rules() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("전쟁 안개 규칙 파일을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-fog-v1" or String(parsed.get("deterministic_seed", "")).is_empty(): return _error("지원하지 않는 전쟁 안개 프로필입니다.")
	var life = parsed.get("contact_lifecycle", {}); var fire = parsed.get("estimated_fire", {})
	if not life is Dictionary or int(life.get("estimated_memory_turns", 0)) != 3 or String(life.get("age_policy", "")) != "age_1_to_2_estimated; age_3_lost_stale; age_gt_3_expired_omit" or int(life.get("estimated_confidence_basis_points", 0)) != 5000 or String(life.get("contact_id_policy", "")) != "viewer_faction_and_target_stable_for_battle_including_expiry_and_reacquisition": return _error("contact 수명 계약이 잘못되었습니다.")
	if not fire is Dictionary or String(fire.get("aim_policy", "")) != "sealed_last_known_plus_deterministic_error_clamped_to_battlefield_bounds_never_current_position" or String(fire.get("weapon_selection", "")) != "positive_allocation_and_last_known_range_arc; allocation_desc_weapon_id_asc; no_fallback_after_resource_gate": return _error("추정 사격 계약이 잘못되었습니다.")
	return {"ok": true, "errors": [], "rules": parsed.duplicate(true)}


func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
