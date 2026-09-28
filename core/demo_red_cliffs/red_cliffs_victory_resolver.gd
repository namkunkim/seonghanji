class_name RedCliffsVictoryResolver
extends RefCounted

## DEMO-RC-G8-01 — 전투 효과가 확정한 입력으로 매 턴 기본 승패를 결정한다.
const RULES_PATH := "res://data/red-cliffs-victory-rules.json"

var _rules: Dictionary = {}


func initialize() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("승리 조건 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-victory-v1": return _error("지원하지 않는 승리 조건 프로필입니다.")
	var alliance: Dictionary = parsed.get("alliance", {})
	if int(parsed.get("loss_threshold_basis_points", 0)) != 7000 or String(parsed.get("morale_collapse_policy", "")) != "all_faction_squadrons_surrendered" \
			or alliance.get("member_faction_ids", []) != ["liu_bei", "sun_quan"] or String(alliance.get("player_anchor_faction_id", "")) != "liu_bei" \
			or String(parsed.get("simultaneous_winner_faction_id", "")) != "cao_cao": return _error("승리 조건 규칙 계약이 잘못되었습니다.")
	_rules = parsed.duplicate(true)
	return _ok()


func rules_snapshot() -> Dictionary: return _rules.duplicate(true)


func evaluate(victory_inputs: Dictionary) -> Dictionary:
	if _rules.is_empty(): return _error("승리 조건 판정기가 초기화되지 않았습니다.")
	if not victory_inputs is Dictionary or not victory_inputs.get("factions") is Dictionary: return _error("승리 조건 입력이 잘못되었습니다.")
	var factions: Dictionary = victory_inputs.factions
	for faction_id in ["liu_bei", "sun_quan", "cao_cao"]:
		if not factions.get(faction_id) is Dictionary: return _error("필수 세력 승리 입력이 없습니다: %s" % faction_id)
	var defeated := {}; var evidence: Array = []
	for faction_id in ["liu_bei", "sun_quan", "cao_cao"]:
		var row: Dictionary = factions[faction_id]
		var original_cost := int(row.get("original_cost", -1)); var remaining_cost := int(row.get("remaining_cost", -1))
		var squadron_count := int(row.get("squadron_count", -1)); var surrendered_count := int(row.get("surrendered_squadron_count", -1))
		if original_cost <= 0 or remaining_cost < 0 or remaining_cost > original_cost or squadron_count <= 0 or surrendered_count < 0 or surrendered_count > squadron_count:
			return _error("세력 승리 입력 범위가 잘못되었습니다: %s" % faction_id)
		var loss_bp := int(floor(float((original_cost - remaining_cost) * 10000) / float(original_cost)))
		var loss_reached := loss_bp >= int(_rules.loss_threshold_basis_points)
		var morale_collapsed := surrendered_count == squadron_count
		defeated[faction_id] = loss_reached or morale_collapsed
		evidence.append({"faction_id": faction_id, "loss_basis_points": loss_bp, "loss_threshold_reached": loss_reached,
			"morale_collapsed": morale_collapsed, "surrendered_squadron_count": surrendered_count, "squadron_count": squadron_count})
	var alliance_defeated: bool = bool(defeated.liu_bei)
	var cao_defeated: bool = bool(defeated.cao_cao)
	var winner_faction_id := ""
	var winner_side_id := ""
	var reason_codes: Array = []
	# The requirements give Cao Cao precedence whenever both sides meet a
	# terminal condition during the same resolved turn.
	if alliance_defeated and cao_defeated:
		winner_faction_id = String(_rules.simultaneous_winner_faction_id); winner_side_id = "cao_cao"; reason_codes = ["simultaneous_terminal_conditions_cao_priority"]
	elif alliance_defeated:
		winner_faction_id = "cao_cao"; winner_side_id = "cao_cao"; reason_codes = ["liu_bei_terminal_condition"]
	elif cao_defeated:
		winner_faction_id = "liu_sun_alliance"; winner_side_id = "liu_sun_alliance"; reason_codes = ["cao_cao_terminal_condition"]
	return {"ok": true, "errors": [], "turn": int(victory_inputs.get("turn", 0)), "winner_present": not winner_faction_id.is_empty(),
		"winner_faction_id": winner_faction_id, "winner_side_id": winner_side_id, "reason_codes": reason_codes,
		"faction_evidence": evidence, "future_conditions_pending": _rules.result_contract.future_conditions.duplicate()}


func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
