class_name RedCliffsVictoryResolver
extends RefCounted

## DEMO-RC-G8-01~03·G8-04a — 전투 효과·기함·총사령관·탈출·20턴 비교로 매 턴 전체 승패를 결정한다.
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
			or String(parsed.get("simultaneous_winner_faction_id", "")) != "cao_cao" or int(parsed.get("turn_limit", 0)) != 20: return _error("승리 조건 규칙 계약이 잘못되었습니다.")
	var escape_points: Dictionary = parsed.get("escape_points", {})
	for side_id in ["cao_cao", "liu_sun_alliance"]:
		var point: Dictionary = escape_points.get(side_id, {})
		var position: Array = point.get("position", [])
		if position.size() != 2 or not _finite_number(position[0]) or not _finite_number(position[1]) or int(point.get("arrival_radius", 0)) <= 0:
			return _error("탈출 지점 규칙 계약이 잘못되었습니다: %s" % side_id)
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
	# DEMO-RC-G8-02: beyond Liu Bei's own terminal condition, the coalition also
	# falls when its *combined* cost (Liu Bei + Sun Quan) crosses the same loss
	# threshold, even if neither member alone has. Sun Quan's own defeat flag
	# (computed above for evidence) never ends the battle by itself.
	var member_ids: Array = _rules.alliance.member_faction_ids
	var alliance_original_cost := 0; var alliance_remaining_cost := 0
	for member_id in member_ids:
		var member_row: Dictionary = factions[String(member_id)]
		alliance_original_cost += int(member_row.original_cost); alliance_remaining_cost += int(member_row.remaining_cost)
	var alliance_loss_bp := int(floor(float((alliance_original_cost - alliance_remaining_cost) * 10000) / float(alliance_original_cost)))
	var alliance_loss_reached := alliance_loss_bp >= int(_rules.loss_threshold_basis_points)
	var alliance_evidence := {"member_faction_ids": member_ids.duplicate(), "original_cost": alliance_original_cost,
		"remaining_cost": alliance_remaining_cost, "loss_basis_points": alliance_loss_bp, "loss_threshold_reached": alliance_loss_reached}
	# DEMO-RC-G8-03: flagship destruction is a standalone terminal condition on
	# top of the cost/morale checks above. Cao Cao's flagship falling defeats
	# Cao Cao regardless of Cao Cao's own remaining cost/morale state.
	var flagships: Dictionary = victory_inputs.get("flagships", {})
	if not flagships.get("liu_bei") is Dictionary or not flagships.get("cao_cao") is Dictionary: return _error("기함 승리 입력이 없습니다.")
	var liu_flagship_destroyed: bool = bool(flagships.liu_bei.get("destroyed", false))
	var cao_flagship_destroyed: bool = bool(flagships.cao_cao.get("destroyed", false))
	# Escape points: Cao Cao's flagship reaching Cao Cao's own point is an
	# alliance victory; Liu Bei's flagship together with its whole fleet
	# reaching the alliance's point is a *limited* alliance victory. Both are
	# computed upstream (position + fleet membership are outside this pure
	# cost/morale resolver) and handed in as plain booleans.
	var escapes: Dictionary = victory_inputs.get("escapes", {})
	if not (escapes.get("cao_cao") is bool) or not (escapes.get("liu_sun_alliance") is bool): return _error("탈출 승리 입력이 없습니다.")
	var cao_escaped: bool = bool(escapes.cao_cao)
	var alliance_escaped: bool = bool(escapes.liu_sun_alliance)
	# DEMO-RC-G8-04a: 총사령관(유비·조조)의 전사·포로는 기함 격침과 동격의 즉시 종료 조건이다.
	# 중상은 승계만 일으키고 전투는 계속된다. 입력이 없으면(G8-01~03 단독 시험) 상실 없음으로 본다.
	var supremes: Dictionary = victory_inputs.get("supreme_commanders", {})
	if not supremes is Dictionary: return _error("총사령관 승리 입력이 잘못되었습니다.")
	var liu_supreme_lost: bool = bool(supremes.get("liu_bei", {}).get("lost", false))
	var cao_supreme_lost: bool = bool(supremes.get("cao_cao", {}).get("lost", false))
	var alliance_defeated: bool = bool(defeated.liu_bei) or alliance_loss_reached or liu_flagship_destroyed or liu_supreme_lost
	var cao_defeated: bool = bool(defeated.cao_cao) or cao_flagship_destroyed or cao_escaped or cao_supreme_lost
	var winner_faction_id := ""
	var winner_side_id := ""
	var reason_codes: Array = []
	var victory_type := "decisive"
	# The requirements give Cao Cao precedence whenever both sides meet a
	# terminal condition during the same resolved turn.
	if alliance_defeated and cao_defeated:
		winner_faction_id = String(_rules.simultaneous_winner_faction_id); winner_side_id = "cao_cao"; reason_codes = ["simultaneous_terminal_conditions_cao_priority"]
	elif alliance_defeated:
		winner_faction_id = "cao_cao"; winner_side_id = "cao_cao"
		if liu_flagship_destroyed: reason_codes = ["liu_bei_flagship_destroyed"]
		elif liu_supreme_lost: reason_codes = ["liu_bei_supreme_commander_lost"]
		elif bool(defeated.liu_bei): reason_codes = ["liu_bei_terminal_condition"]
		else: reason_codes = ["alliance_combined_loss_threshold"]
	elif cao_defeated:
		winner_faction_id = "liu_sun_alliance"; winner_side_id = "liu_sun_alliance"
		if cao_flagship_destroyed: reason_codes = ["cao_cao_flagship_destroyed"]
		elif cao_supreme_lost: reason_codes = ["cao_cao_supreme_commander_lost"]
		elif cao_escaped: reason_codes = ["cao_cao_flagship_escaped"]
		else: reason_codes = ["cao_cao_terminal_condition"]
	elif alliance_escaped:
		winner_faction_id = "liu_sun_alliance"; winner_side_id = "liu_sun_alliance"; reason_codes = ["alliance_escape_limited_victory"]; victory_type = "limited"
	elif int(victory_inputs.get("turn", 0)) >= int(_rules.turn_limit):
		# 20-turn fallback: compare surviving-cost ratio with cross-multiplication
		# so no floating point enters the decision. A tie favors Cao Cao.
		var cao_row: Dictionary = factions.cao_cao
		var alliance_side := alliance_remaining_cost * int(cao_row.original_cost)
		var cao_side := int(cao_row.remaining_cost) * alliance_original_cost
		if alliance_side > cao_side:
			winner_faction_id = "liu_sun_alliance"; winner_side_id = "liu_sun_alliance"; reason_codes = ["turn_limit_alliance_cost_ratio_higher"]
		else:
			winner_faction_id = "cao_cao"; winner_side_id = "cao_cao"
			reason_codes = ["turn_limit_tie_cao_priority"] if alliance_side == cao_side else ["turn_limit_cao_cost_ratio_higher"]
	return {"ok": true, "errors": [], "turn": int(victory_inputs.get("turn", 0)), "winner_present": not winner_faction_id.is_empty(),
		"winner_faction_id": winner_faction_id, "winner_side_id": winner_side_id, "reason_codes": reason_codes, "victory_type": victory_type,
		"faction_evidence": evidence, "alliance_evidence": alliance_evidence, "future_conditions_pending": _rules.result_contract.future_conditions.duplicate()}


func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
func _finite_number(value) -> bool: return (value is int or value is float) and is_finite(float(value))
