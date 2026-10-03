class_name RedCliffsCommanderResolver
extends RefCounted

## DEMO-RC-G8-04a — 장수·제독 부상·전사·포로와 함대 지휘 승계를 결정적으로 판정한다.
## 입력은 G8-00 전투 효과 상태, 같은 턴 연쇄 폭발 적중, 턴 종료 위치, 고속정 나포 상태뿐이다.
const RULES_PATH := "res://data/red-cliffs-commander-rules.json"
const ALLIANCE := ["liu_bei", "sun_quan"]
const SUPREME_FACTIONS := ["liu_bei", "cao_cao"]

var _rules: Dictionary = {}
var _setup: Dictionary = {}
var _rescue_squadrons := {}


func initialize(applied_setup: Dictionary) -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return _error("장수 판정 규칙을 열 수 없습니다.")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1 or String(parsed.get("profile_id", "")) != "normal-demo-commander-v1":
		return _error("지원하지 않는 장수 판정 프로필입니다.")
	var branch: Dictionary = parsed.get("destroyed_branch", {}); var confusion: Dictionary = parsed.get("command_confusion", {})
	if int(branch.get("capture_radius", 0)) <= 0 or String(branch.get("chain_explosion_outcome", "")) != "killed" \
			or int(confusion.get("duration_turns", 0)) != 1 or int(confusion.get("extra_penalty_tiers", 0)) <= 0:
		return _error("장수 판정 규칙 계약이 잘못되었습니다.")
	if not applied_setup.get("squadrons") is Array or not applied_setup.get("factions") is Array:
		return _error("장수 판정에는 적용 편성이 필요합니다.")
	_rules = parsed.duplicate(true); _setup = applied_setup.duplicate(true); _rescue_squadrons = {}
	for squad in _setup.squadrons:
		for component in squad.get("composition", []):
			if String(component.get("mission_equipment_id", "")) == String(branch.rescue_mission_equipment_id): _rescue_squadrons[String(squad.id)] = true
	var built := initial_state()
	if built.has("error"): return _error(String(built.error))
	return _ok()


func rules_snapshot() -> Dictionary: return _rules.duplicate(true)


func initial_state() -> Dictionary:
	var roster := {}
	for faction in _setup.factions:
		for person in faction.get("demo_roster", []): roster[String(person.id)] = {"faction_id": String(faction.id), "name": String(person.name), "level": int(person.get("level", 0)), "command": int(person.get("command", 0))}
	var officers := {}; var fleets := {}
	for squad in _setup.squadrons:
		var officer_id := String(squad.commander.id)
		officers[officer_id] = _officer(officer_id, roster.get(officer_id, {}), String(squad.commander.name), String(squad.faction_id), String(squad.id), "squadron_commander")
	for fleet in _setup.get("fleet_groups", []):
		var fleet_id := String(fleet.id); var flagship_id := String(fleet.flagship_squadron_id)
		var commander_id := ""
		for squad in _setup.squadrons:
			if String(squad.id) == flagship_id: commander_id = String(squad.commander.id)
		var vice_id := ""
		if fleet.get("vice_commander") is Dictionary:
			vice_id = String(fleet.vice_commander.id)
			# 전대 지휘관으로 배치된 인물의 부함장 지위는 무효다(겸직 불가).
			if officers.has(vice_id): vice_id = ""
			else: officers[vice_id] = _officer(vice_id, roster.get(vice_id, {}), String(fleet.vice_commander.get("name", "")), String(fleet.faction_id), flagship_id, "vice_commander")
		for squadron_id in fleet.squadron_ids:
			for officer_id in officers:
				if String(officers[officer_id].squadron_id) == String(squadron_id): officers[officer_id].fleet_id = fleet_id
		fleets[fleet_id] = {"fleet_id": fleet_id, "faction_id": String(fleet.faction_id), "squadron_ids": fleet.squadron_ids.duplicate(),
			"commander_id": commander_id, "vice_commander_id": vice_id, "flagship_squadron_id": flagship_id,
			"leaderless": false, "confusion_turns": [], "successions": 0}
	return {"officers": officers, "fleets": fleets, "events": [], "concluded": false}


## 턴 종료 판정. effect_state는 이번 턴 G8-00 결과, effect_events는 이번 턴 효과 이벤트다.
func resolve(prior_state: Dictionary, effect_state: Dictionary, effect_events: Array, recovery_state: Dictionary,
		navigation: Dictionary, turn_number: int) -> Dictionary:
	if _rules.is_empty(): return _error("장수 판정기가 초기화되지 않았습니다.")
	if turn_number < 1 or not prior_state.get("officers") is Dictionary or not effect_state.get("squadrons") is Dictionary:
		return _error("장수 판정 입력이 잘못되었습니다.")
	var state := prior_state.duplicate(true); var events: Array = []
	var chain_hit := {}
	for event in effect_events:
		if event is Dictionary and String(event.get("event_type", "")) == "chain_effects_applied" and int(event.get("turn", 0)) == turn_number:
			chain_hit[String(event.target_squadron_id)] = true
	var recovery: Dictionary = recovery_state.get("squadrons", {}) if recovery_state.get("squadrons") is Dictionary else {}
	var officer_ids: Array = state.officers.keys(); officer_ids.sort()
	for officer_id in officer_ids:
		var officer: Dictionary = state.officers[officer_id]; var squadron_id := String(officer.squadron_id)
		if not effect_state.squadrons.has(squadron_id): continue
		var row: Dictionary = effect_state.squadrons[squadron_id]; var vice := String(officer.role) == "vice_commander"
		var outcome := ""; var cause := ""
		if String(row.morale_status) == "surrendered": outcome = "captured"; cause = "surrendered"
		elif String(recovery.get(squadron_id, {}).get("status", "")) == "captured": outcome = "captured"; cause = "fast_craft_captured"
		elif String(row.damage_state) == "destroyed":
			cause = "destroyed"
			outcome = _destroyed_outcome(squadron_id, String(row.faction_id), chain_hit.has(squadron_id), effect_state, recovery, navigation)
			if chain_hit.has(squadron_id): cause = "destroyed_chain_explosion"
			elif outcome == "captured": cause = "destroyed_enemy_nearby"
			else: cause = "destroyed_recovered"
		elif not vice and String(row.damage_state) == "heavy_damage": outcome = "severe_injury"; cause = "heavy_damage"
		elif not vice and String(row.damage_state) == "moderate_damage": outcome = "light_injury"; cause = "moderate_damage"
		if outcome.is_empty(): continue
		var changed := _apply(state, String(officer_id), outcome, cause, turn_number)
		if not changed.is_empty(): events.append(changed)
	events.append_array(_succession(state, turn_number))
	state.events.append_array(events)
	return {"ok": true, "errors": [], "state": state, "events": events, "supreme_commanders": supreme_commanders(state)}


## 승패 확정 직후 한 번 호출한다. 강제 퇴각 중 자기 측 탈출 지점 밖에서 패배 측으로 끝난 전대는 포로다.
func conclude(prior_state: Dictionary, effect_state: Dictionary, navigation: Dictionary, winner_side_id: String,
		escape_points: Dictionary, turn_number: int) -> Dictionary:
	if _rules.is_empty(): return _error("장수 판정기가 초기화되지 않았습니다.")
	if bool(prior_state.get("concluded", false)): return _error("장수 판정은 이미 종결되었습니다.")
	var state := prior_state.duplicate(true); var events: Array = []
	var officer_ids: Array = state.officers.keys(); officer_ids.sort()
	for officer_id in officer_ids:
		var officer: Dictionary = state.officers[officer_id]; var squadron_id := String(officer.squadron_id)
		if not effect_state.squadrons.has(squadron_id): continue
		var row: Dictionary = effect_state.squadrons[squadron_id]
		if not bool(row.capabilities.get("forced_retreat", false)): continue
		var side := _side(String(row.faction_id))
		if winner_side_id.is_empty() or winner_side_id == side: continue
		var point: Dictionary = escape_points.get(side, {})
		if _within(navigation.get(squadron_id, {}).get("position", []), point.get("position", []), float(point.get("arrival_radius", 0))): continue
		var changed := _apply(state, String(officer_id), "captured", "failed_retreat", turn_number)
		if not changed.is_empty(): events.append(changed)
	state.concluded = true; state.events.append_array(events)
	return {"ok": true, "errors": [], "state": state, "events": events}


func supreme_commanders(state: Dictionary) -> Dictionary:
	var result := {}
	for faction in _setup.factions:
		var faction_id := String(faction.id)
		if not SUPREME_FACTIONS.has(faction_id): continue
		var officer_id := _officer_id_by_name(state, faction_id, String(faction.get("supreme_commander", "")))
		var status := String(state.officers.get(officer_id, {}).get("status", "unhurt"))
		result[faction_id] = {"officer_id": officer_id, "status": status, "lost": (_rules.supreme_commander_loss.statuses as Array).has(status)}
	return result


## 이번 턴 명령에 적용할 지휘 불이익 덧셈. {squadron_id: {"extra_tiers": int, "command": int(선택)}}
func command_overrides(state: Dictionary, turn_number: int) -> Dictionary:
	var result := {}
	for fleet_id in state.get("fleets", {}):
		var fleet: Dictionary = state.fleets[fleet_id]
		var confused: bool = bool(fleet.leaderless) or (fleet.confusion_turns as Array).has(turn_number)
		if confused:
			for squadron_id in fleet.squadron_ids:
				result[String(squadron_id)] = {"extra_tiers": int(_rules.command_confusion.extra_penalty_tiers), "source": "command_confusion", "fleet_id": String(fleet_id)}
		# 부함장이 승계하면 기함 전대의 지휘 한도는 부함장의 통솔로 다시 계산한다.
		var commander: Dictionary = state.officers.get(String(fleet.commander_id), {})
		if String(commander.get("role", "")) == "vice_commander" and not bool(fleet.leaderless):
			var row: Dictionary = result.get(String(fleet.flagship_squadron_id), {"extra_tiers": 0, "source": "succession", "fleet_id": String(fleet_id)})
			row["command"] = int(commander.command); result[String(fleet.flagship_squadron_id)] = row
	return result


## 결과 화면용: 세력별 생존·부상·전사·포로 분류.
func report(state: Dictionary) -> Dictionary:
	var factions := {}
	var officer_ids: Array = state.get("officers", {}).keys(); officer_ids.sort()
	for officer_id in officer_ids:
		var officer: Dictionary = state.officers[officer_id]; var faction_id := String(officer.faction_id)
		if not factions.has(faction_id): factions[faction_id] = {"survived": [], "injured": [], "killed": [], "captured": []}
		var category := String(_rules.result_categories[String(officer.status)])
		factions[faction_id][category].append({"officer_id": String(officer_id), "name": String(officer.name), "status": String(officer.status),
			"label": String(_rules.statuses[String(officer.status)].label), "cause": String(officer.cause), "turn": int(officer.status_turn), "role": String(officer.role)})
	return {"ok": true, "errors": [], "factions": factions}


## 아군 측(손유 연합은 서로 공유)은 전부, 적은 전사·포로만 공개한다.
func visible(viewer_faction_id: String, state: Dictionary) -> Dictionary:
	var viewer_side := _side(viewer_faction_id); var officers: Array = []
	var officer_ids: Array = state.get("officers", {}).keys(); officer_ids.sort()
	for officer_id in officer_ids:
		var officer: Dictionary = state.officers[officer_id]
		var own := _side(String(officer.faction_id)) == viewer_side
		if not own and not bool(_rules.statuses[String(officer.status)].terminal): continue
		officers.append({"officer_id": String(officer_id), "name": String(officer.name), "faction_id": String(officer.faction_id),
			"status": String(officer.status), "label": String(_rules.statuses[String(officer.status)].label),
			"can_command": not bool(_rules.statuses[String(officer.status)].incapacitated), "viewer_state": "own" if own else "enemy_terminal"})
	var fleets: Array = []
	var fleet_ids: Array = state.get("fleets", {}).keys(); fleet_ids.sort()
	for fleet_id in fleet_ids:
		var fleet: Dictionary = state.fleets[fleet_id]
		if _side(String(fleet.faction_id)) != viewer_side: continue
		fleets.append({"fleet_id": String(fleet_id), "commander_id": String(fleet.commander_id), "flagship_squadron_id": String(fleet.flagship_squadron_id),
			"leaderless": bool(fleet.leaderless), "confusion_turns": fleet.confusion_turns.duplicate()})
	return {"ok": true, "errors": [], "officers": officers, "fleets": fleets}


func _destroyed_outcome(squadron_id: String, faction_id: String, chain_hit: bool, effect_state: Dictionary, recovery: Dictionary, navigation: Dictionary) -> String:
	var branch: Dictionary = _rules.destroyed_branch
	if chain_hit: return String(branch.chain_explosion_outcome)
	var origin = navigation.get(squadron_id, {}).get("position", [])
	if not origin is Array or origin.size() != 2: return String(branch.captured_outcome)
	var radius_sq := float(branch.capture_radius) * float(branch.capture_radius)
	var side := _side(faction_id); var nearest_friend := INF; var nearest_enemy := INF
	var ids: Array = effect_state.squadrons.keys(); ids.sort()
	for other_id in ids:
		if String(other_id) == squadron_id or not _available(String(other_id), effect_state, recovery): continue
		var position = navigation.get(other_id, {}).get("position", [])
		if not position is Array or position.size() != 2: continue
		var distance_sq := _distance_sq(origin, position)
		if distance_sq > radius_sq: continue
		if _side(String(effect_state.squadrons[other_id].faction_id)) == side:
			if _rescue_squadrons.has(String(other_id)): return String(branch.recovered_outcome)
			nearest_friend = minf(nearest_friend, distance_sq)
		else: nearest_enemy = minf(nearest_enemy, distance_sq)
	if nearest_enemy == INF or nearest_friend <= nearest_enemy: return String(branch.recovered_outcome)
	return String(branch.captured_outcome)


func _available(squadron_id: String, effect_state: Dictionary, recovery: Dictionary) -> bool:
	if not bool(effect_state.squadrons[squadron_id].capabilities.get("operational", false)): return false
	return ["", "active"].has(String(recovery.get(squadron_id, {}).get("status", "")))


func _apply(state: Dictionary, officer_id: String, outcome: String, cause: String, turn_number: int) -> Dictionary:
	var officer: Dictionary = state.officers[officer_id]; var current := String(officer.status)
	if bool(_rules.statuses[current].terminal) or int(_rules.statuses[outcome].rank) <= int(_rules.statuses[current].rank): return {}
	officer.status = outcome; officer.cause = cause; officer.status_turn = turn_number
	return {"event_id": "CMDR-%02d-%s" % [turn_number, officer_id], "event_type": "commander_status_changed", "turn": turn_number,
		"officer_id": officer_id, "name": String(officer.name), "faction_id": String(officer.faction_id), "squadron_id": String(officer.squadron_id),
		"from_status": current, "status": outcome, "label": String(_rules.statuses[outcome].label), "cause": cause}


func _succession(state: Dictionary, turn_number: int) -> Array:
	var events: Array = []
	var fleet_ids: Array = state.fleets.keys(); fleet_ids.sort()
	for fleet_id in fleet_ids:
		var fleet: Dictionary = state.fleets[fleet_id]
		if bool(fleet.leaderless) or not _incapacitated(state, String(fleet.commander_id)): continue
		var previous := String(fleet.commander_id); var successor := ""
		var vice_id := String(fleet.vice_commander_id)
		if not vice_id.is_empty() and vice_id != previous and not _incapacitated(state, vice_id): successor = vice_id
		if successor.is_empty():
			var candidates: Array = []
			for officer_id in state.officers:
				var officer: Dictionary = state.officers[officer_id]
				if String(officer.role) == "squadron_commander" and (fleet.squadron_ids as Array).has(String(officer.squadron_id)) and not _incapacitated(state, String(officer_id)):
					candidates.append(officer)
			candidates.sort_custom(func(a, b):
				if int(a.level) != int(b.level): return int(a.level) > int(b.level)
				if int(a.command) != int(b.command): return int(a.command) > int(b.command)
				return String(a.squadron_id) < String(b.squadron_id))
			if not candidates.is_empty():
				successor = String(candidates[0].officer_id); fleet.flagship_squadron_id = String(candidates[0].squadron_id)
		var confusion_turn := turn_number + int(_rules.command_confusion.starts_turn_offset)
		if successor.is_empty():
			fleet.leaderless = true
			events.append({"event_id": "CMDS-%02d-%s" % [turn_number, fleet_id], "event_type": "fleet_leaderless", "turn": turn_number,
				"fleet_id": String(fleet_id), "faction_id": String(fleet.faction_id), "previous_commander_id": previous, "command_confusion": "until_battle_end"})
			continue
		fleet.commander_id = successor; fleet.successions = int(fleet.successions) + 1
		if not (fleet.confusion_turns as Array).has(confusion_turn): fleet.confusion_turns.append(confusion_turn)
		events.append({"event_id": "CMDS-%02d-%s" % [turn_number, fleet_id], "event_type": "fleet_command_succeeded", "turn": turn_number,
			"fleet_id": String(fleet_id), "faction_id": String(fleet.faction_id), "previous_commander_id": previous, "successor_id": successor,
			"successor_name": String(state.officers[successor].name), "successor_role": String(state.officers[successor].role),
			"flagship_squadron_id": String(fleet.flagship_squadron_id), "command_confusion_turn": confusion_turn})
	return events


func _incapacitated(state: Dictionary, officer_id: String) -> bool:
	if not state.officers.has(officer_id): return true
	return bool(_rules.statuses[String(state.officers[officer_id].status)].incapacitated)


func _officer(officer_id: String, roster_row: Dictionary, fallback_name: String, faction_id: String, squadron_id: String, role: String) -> Dictionary:
	return {"officer_id": officer_id, "name": String(roster_row.get("name", fallback_name)), "faction_id": faction_id,
		"level": int(roster_row.get("level", 0)), "command": int(roster_row.get("command", 0)), "squadron_id": squadron_id,
		"fleet_id": "", "role": role, "status": "unhurt", "cause": "", "status_turn": 0}


func _officer_id_by_name(state: Dictionary, faction_id: String, name: String) -> String:
	var ids: Array = state.officers.keys(); ids.sort()
	for officer_id in ids:
		if String(state.officers[officer_id].faction_id) == faction_id and String(state.officers[officer_id].name) == name: return String(officer_id)
	return ""


func _side(faction_id: String) -> String: return "liu_sun_alliance" if ALLIANCE.has(faction_id) else faction_id
func _distance_sq(a: Array, b: Array) -> float: return pow(float(a[0]) - float(b[0]), 2) + pow(float(a[1]) - float(b[1]), 2)
func _within(position, center, radius: float) -> bool:
	if not position is Array or not center is Array or position.size() != 2 or center.size() != 2: return false
	return _distance_sq(position, center) <= radius * radius
func _ok() -> Dictionary: return {"ok": true, "errors": []}
func _error(message: String) -> Dictionary: return {"ok": false, "errors": [message]}
