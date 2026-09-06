class_name HomeMapSnapshot
extends RefCounted

## 홈 지도가 읽는 시나리오 상태의 읽기 전용 투영이다.
##
## 지형과 좌표는 `data/maps/galaxy-map.json`, 208년 소유 상태와 함대는
## `Campaign.scenario_03`에서 온다. UI는 반환값을 바꿔도 이 객체의 원본 상태를
## 바꿀 수 없다. 다른 시나리오도 같은 키를 쓰되, 코어에 없는 전투·뉴스는 빈 배열로
## 남긴다. 문서에서 상태를 발명해 채우지 않는다.

const MAP_PATH := "res://data/maps/galaxy-map.json"
const SCHEMA_VERSION := 1
const SCENARIO_03_ID := "SCN-03"
const SCENARIO_03_YEAR := 208
const SOLAR_DETAIL_MIN_ZOOM := 2
const SOLAR_DETAIL_BODY_IDS: Array[String] = [
	"BODY-RGN-04-01",
	"BODY-RGN-04-02",
	"BODY-RGN-04-03",
]
const EXTERNAL_POWER_SOURCE := "home_map_snapshot_fallback"
const EXTERNAL_POWER_SOURCE_STATUS := "pending_data_migration"

const RED_CLIFF_CONDITIONS: Array[String] = [
	"cao_southward_complete",
	"sun_quan_independent",
	"liu_bei_hostile_to_cao",
	"sun_liu_military_pact",
	"yangtze_defense_line",
]

var _state: Dictionary = {}


## `runtime`은 코어가 아직 보관하지 않는 일시 UI 상태만 받는다.
## 허용 키: viewer_faction, active_battles(비정본 fallback), news.
static func from_campaign(campaign, year: int = -1,
		runtime: Dictionary = {}) -> HomeMapSnapshot:
	var out := HomeMapSnapshot.new()
	var map_data := _read_map(MAP_PATH)
	var sid := ""
	var valid := true
	var validation_error := ""
	if campaign == null:
		valid = false
		validation_error = "missing_campaign"
	elif campaign.world == null:
		valid = false
		validation_error = "missing_world"
	else:
		sid = String(campaign.world.scenario)
		if sid == "":
			valid = false
			validation_error = "missing_scenario"
		elif sid != SCENARIO_03_ID:
			valid = false
			validation_error = "unsupported_scenario: " + sid
	var resolved_year := year
	if resolved_year < 0 and sid == SCENARIO_03_ID:
		resolved_year = SCENARIO_03_YEAR
	if valid and sid == SCENARIO_03_ID and resolved_year != SCENARIO_03_YEAR:
		# SCN-03은 208년 단일 시나리오다. 모순된 호출에서 캠페인 상태가
		# 다른 연도의 사실처럼 노출되지 않도록 시나리오 파생값을 무효화한다.
		valid = false
		validation_error = "SCN-03 only supports year 208"
		resolved_year = -1
	if not valid:
		resolved_year = -1
	var viewer_faction := ""
	if valid:
		viewer_faction = String(runtime.get("viewer_faction",
			campaign.world.player_faction))
	var player_faction := String(campaign.world.player_faction) if valid else ""

	var systems: Array = map_data.get("systems", []).duplicate(true)
	var regions: Array = map_data.get("regions", []).duplicate(true)
	var bodies: Array = map_data.get("bodies", []).duplicate(true)
	var routes: Array = map_data.get("routes", []).duplicate(true)
	var terrain := {
		"authored_ridges": map_data.get("authored_ridges", []).duplicate(true),
		"field": map_data.get("field", {}).duplicate(true),
		"hazard_channels": map_data.get("hazard_channels", []).duplicate(true),
		"plains": map_data.get("plains", []).duplicate(true),
		"terrain": map_data.get("terrain", {}).duplicate(true),
		"waterways": map_data.get("waterways", []).duplicate(true),
	}

	out._state = {
		"schema_version": SCHEMA_VERSION,
		"scenario_id": sid,
		"year": resolved_year,
		"valid": valid,
		"validation_error": validation_error,
		"scenario": _scenario(campaign, sid, resolved_year) if valid else _empty_scenario(),
		"viewer": {
			"faction_id": viewer_faction,
			"valid": valid and viewer_faction != "" and campaign.factions.has(viewer_faction),
		},
		"player_state": _player_state(campaign, player_faction) if valid else _empty_player_state(),
		"factions": _factions(campaign) if valid else [],
		"canonical_systems": systems,
		"canonical_regions": regions,
		"canonical_bodies": bodies,
		"canonical_routes": routes,
		"terrain": terrain,
		"region_owner": _region_owners(campaign, regions) if valid else {},
		"region_states": _region_states(campaign, regions, player_faction) if valid else {},
		"alliances": _alliances(campaign) if valid else [],
		"observed_fleets": _observed_fleets(campaign, viewer_faction) if valid else [],
		"pending_commands": _pending_commands(campaign, player_faction) if valid else [],
		"event_counts": _event_counts(campaign) if valid else {},
		"active_battles": _active_battles(campaign, map_data, sid, runtime) if valid else [],
		"red_cliff_conditions": _red_cliff_conditions(campaign, sid, runtime) if valid else {},
		"news": _news(runtime.get("news", [])) if valid else [],
		"external_powers": _external_powers(resolved_year) if valid else [],
		"capabilities": _capabilities(sid),
		"provenance": _provenance(sid, runtime),
		"presentation": {
			"valid": valid,
			"invalid_reason": validation_error,
			"solar_detail_min_zoom": SOLAR_DETAIL_MIN_ZOOM,
			"solar_detail_body_ids": SOLAR_DETAIL_BODY_IDS.duplicate(),
		},
	}
	return out


## 전체 계약의 깊은 복사본. 호출자가 중첩 배열을 수정해도 원본은 유지된다.
func snapshot() -> Dictionary:
	return _state.duplicate(true)


func schema_version() -> int:
	return int(_state.get("schema_version", 0))


func scenario() -> Dictionary:
	return (_state.get("scenario", {}) as Dictionary).duplicate(true)


func viewer() -> Dictionary:
	return (_state.get("viewer", {}) as Dictionary).duplicate(true)


func player_state() -> Dictionary:
	return (_state.get("player_state", {}) as Dictionary).duplicate(true)


func factions() -> Array:
	return (_state.get("factions", []) as Array).duplicate(true)


func scenario_id() -> String:
	return String(_state.get("scenario_id", ""))


func year() -> int:
	return int(_state.get("year", -1))


func is_valid() -> bool:
	return bool(_state.get("valid", false))


func validation_error() -> String:
	return String(_state.get("validation_error", ""))


func canonical_systems() -> Array:
	return (_state.get("canonical_systems", []) as Array).duplicate(true)


func canonical_regions() -> Array:
	return (_state.get("canonical_regions", []) as Array).duplicate(true)


func canonical_bodies() -> Array:
	return (_state.get("canonical_bodies", []) as Array).duplicate(true)


## 지도 단계별 표시용 천체. 정본 천체 배열은 손대지 않되, 태양계 세부 천체는
## Z2 이상 또는 그 권역에서 실제 사건이 활성화된 때에만 노출한다.
func visible_bodies(zoom_level: int = 0) -> Array:
	var show_solar_detail := zoom_level >= SOLAR_DETAIL_MIN_ZOOM \
		or _has_active_solar_event()
	var out: Array = []
	for body in _state.get("canonical_bodies", []):
		if not show_solar_detail and SOLAR_DETAIL_BODY_IDS.has(String(body.get("id", ""))):
			continue
		out.append(body.duplicate(true))
	return out


func presentation() -> Dictionary:
	return (_state.get("presentation", {}) as Dictionary).duplicate(true)


func canonical_routes() -> Array:
	return (_state.get("canonical_routes", []) as Array).duplicate(true)


func terrain() -> Dictionary:
	return (_state.get("terrain", {}) as Dictionary).duplicate(true)


func region_owner() -> Dictionary:
	return (_state.get("region_owner", {}) as Dictionary).duplicate(true)


func region_states() -> Dictionary:
	return (_state.get("region_states", {}) as Dictionary).duplicate(true)


func alliances() -> Array:
	return (_state.get("alliances", []) as Array).duplicate(true)


func observed_fleets() -> Array:
	return (_state.get("observed_fleets", []) as Array).duplicate(true)


func pending_commands() -> Array:
	return (_state.get("pending_commands", []) as Array).duplicate(true)


func event_counts() -> Dictionary:
	return (_state.get("event_counts", {}) as Dictionary).duplicate(true)


func active_battles() -> Array:
	return (_state.get("active_battles", []) as Array).duplicate(true)


func red_cliff_conditions() -> Dictionary:
	return (_state.get("red_cliff_conditions", {}) as Dictionary).duplicate(true)


func news() -> Array:
	return (_state.get("news", []) as Array).duplicate(true)


func external_powers() -> Array:
	return (_state.get("external_powers", []) as Array).duplicate(true)


func capabilities() -> Dictionary:
	return (_state.get("capabilities", {}) as Dictionary).duplicate(true)


func provenance() -> Dictionary:
	return (_state.get("provenance", {}) as Dictionary).duplicate(true)


## 형주성역의 네 권역. 정본 ID/좌표를 그대로 반환한다.
func jingzhou_regions() -> Array:
	var out: Array = []
	for row in _state.get("canonical_regions", []):
		if String(row.get("system", "")) == "SYS-13":
			out.append(row.duplicate(true))
	return out


func solar_region() -> Dictionary:
	return _find_named(_state.get("canonical_regions", []), "태양계권")


func old_earth_body() -> Dictionary:
	return _find_named(_state.get("canonical_bodies", []), "구지")


func _has_active_solar_event() -> bool:
	for event in _state.get("active_battles", []):
		if String(event.get("status", "")) != "active":
			continue
		if String(event.get("system_id", "")) == "SYS-13" \
				or String(event.get("region_id", "")) == "RGN-04" \
				or SOLAR_DETAIL_BODY_IDS.has(String(event.get("anchor_body_id", ""))):
			return true
	return false


static func red_cliff_ready(conditions: Dictionary) -> bool:
	for key in RED_CLIFF_CONDITIONS:
		if not bool(conditions.get(key, false)):
			return false
	return true


static func _scenario(campaign, scenario_id: String, start_year: int) -> Dictionary:
	var calendar: Array = campaign.world.clock.calendar(start_year)
	return {
		"id": scenario_id,
		"start_year": start_year,
		"tick": campaign.world.clock.tick,
		"year": int(calendar[0]),
		"month": int(calendar[1]),
		"speed": campaign.world.clock.speed,
		"paused": campaign.world.clock.paused,
		"ended": campaign.ended,
		"end_reason": campaign.end_reason,
	}


static func _empty_scenario() -> Dictionary:
	return {
		"id": "", "start_year": -1, "tick": 0, "year": -1, "month": -1,
		"speed": 1, "paused": false, "ended": false, "end_reason": "",
	}


static func _player_state(campaign, player_faction: String) -> Dictionary:
	var out := _empty_player_state()
	out["faction_id"] = player_faction
	if player_faction == "" or not campaign.factions.has(player_faction):
		return out
	var faction = campaign.factions[player_faction]
	var budget: Array = campaign.budget(player_faction)
	var mobilized: int = faction.mobilized(campaign.data, campaign.world.region_states,
		campaign.world.graph, campaign.world.clock.tick)
	var capacity_milli: int = Economy.squadrons_milli(mobilized, faction.plan)
	var used_milli: int = 0
	for fleet in campaign.fleets:
		if fleet.owner == player_faction and fleet.is_alive():
			used_milli += fleet.squadrons_milli()
	return {
		"faction_id": player_faction,
		"treasury": faction.treasury,
		"budget": {
			"income": int(budget[0]), "admin": int(budget[1]),
			"fleet": int(budget[2]), "drill": int(budget[3]),
			"recovery": int(budget[4]), "net": int(budget[5]),
		},
		"mandate": faction.mandate,
		"hegemony": faction.hegemony,
		"mobilized": mobilized,
		"fleet_capacity_milli": capacity_milli,
		"fleet_used_milli": used_milli,
		"tech": faction.tech.duplicate(true),
		"tech_research": faction.tech_research.duplicate(true),
	}


static func _empty_player_state() -> Dictionary:
	return {
		"faction_id": "", "treasury": 0,
		"budget": {"income": 0, "admin": 0, "fleet": 0, "drill": 0,
			"recovery": 0, "net": 0},
		"mandate": 0, "hegemony": 0, "mobilized": 0,
		"fleet_capacity_milli": 0, "fleet_used_milli": 0,
		"tech": {}, "tech_research": {},
	}


static func _factions(campaign) -> Array:
	var out: Array = []
	for faction_id in campaign.faction_ids:
		var faction = campaign.factions[faction_id]
		out.append({
			"id": faction.id,
			"name": faction.name,
			"capital_system": faction.capital_system,
			"region_count": faction.regions.size(),
			"alive": faction.alive,
			"wandering": faction.wandering,
		})
	return out


static func _region_states(campaign, canonical_regions: Array,
		player_faction: String) -> Dictionary:
	var out := {}
	for region in canonical_regions:
		var region_id := String(region.get("id", ""))
		var state = campaign.world.region_states.get(region_id)
		if state == null:
			continue
		var row := {
			"owner": state.owner,
			"contested": state.contested,
			"detail_visibility": "full" if player_faction != "" \
				and String(state.owner) == player_faction else "public",
		}
		if row["detail_visibility"] == "full":
			row.merge({
				"war_damage_milli": state.war_damage_milli,
				"acquired_tick": state.acquired_tick,
				"acquired_by": state.acquired_by,
				"recovery_investment": state.recovery_investment,
				"development": state.development,
				"delegated": state.delegated,
				"garrison": state.garrison,
				"stability": state.stability,
				"stability_initial": state.stability_initial,
				"pacified": state.pacified,
			})
		out[region_id] = row
	return out


static func _pending_commands(campaign, player_faction: String) -> Array:
	var out: Array = []
	if player_faction == "":
		return out
	for command in campaign.world.pending_commands:
		if String(command.get("origin", "player")) == "ai":
			continue
		var payload: Dictionary = command.get("payload", {})
		if String(payload.get("faction", "")) != player_faction:
			continue
		var safe_payload := {}
		for key in ["region", "fleet", "into", "axis", "stage", "amount", "on",
				"plan", "formation", "step"]:
			if payload.has(key):
				safe_payload[key] = payload[key]
		out.append({
			"seq": int(command.get("seq", -1)),
			"kind": String(command.get("kind", "")),
			"issued_tick": int(command.get("issued_tick", 0)),
			"arrival_tick": int(command.get("arrival_tick", command.get("issued_tick", 0))),
			"remaining_ticks": maxi(0, int(command.get("arrival_tick", 0)) - campaign.world.clock.tick),
			"payload": safe_payload,
		})
	out.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
	return out


static func _event_counts(campaign) -> Dictionary:
	var out := {}
	var event_ids: Array = campaign.events_fired.keys()
	event_ids.sort()
	for event_id in event_ids:
		out[String(event_id)] = int(campaign.events_fired[event_id])
	return out


static func _capabilities(scenario_id: String) -> Dictionary:
	var has_scn03_red_cliff_core := scenario_id == SCENARIO_03_ID
	return {
		"scenario_clock": true,
		"player_faction": true,
		"treasury": true,
		"budget": true,
		"mandate": true,
		"hegemony": true,
		"mobilized": true,
		"fleet_capacity": true,
		"region_states": true,
		"observed_fleets": true,
		"alliances": true,
		"pending_commands": true,
		"event_counts": true,
		"date_day": false,
		"supply_resource": false,
		"influence_resource": false,
		"intel_resource": false,
		"active_battles": has_scn03_red_cliff_core,
		"red_cliff_conditions": has_scn03_red_cliff_core,
		"news": false,
		"external_powers": false,
		"liu_bei_wandering": false,
	}


static func _provenance(scenario_id: String, runtime: Dictionary) -> Dictionary:
	var has_scn03_red_cliff_core := scenario_id == SCENARIO_03_ID
	var has_runtime_noncanonical_battle := _has_runtime_noncanonical_battle(runtime)
	return {
		"scenario": "campaign_core",
		"viewer": "campaign_core_or_runtime_override",
		"player_state": "campaign_core",
		"factions": "campaign_core",
		"region_states": "campaign_core",
		"pending_commands": "campaign_core_filtered",
		"event_counts": "campaign_core_aggregate",
		"active_battles": "campaign_core_or_runtime_fixture" if has_scn03_red_cliff_core and has_runtime_noncanonical_battle else "campaign_core" if has_scn03_red_cliff_core else "runtime_fixture" if has_runtime_noncanonical_battle else "unsupported",
		"red_cliff_conditions": "campaign_core" if has_scn03_red_cliff_core else "runtime_fixture" if runtime.has("red_cliff_conditions") else "unsupported",
		"news": "runtime_fixture" if runtime.has("news") else "unsupported",
		"external_powers": EXTERNAL_POWER_SOURCE,
	}


static func _read_map(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "정본 지도를 열 수 없다: " + path)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "정본 지도가 객체가 아니다: " + path)
	return parsed


static func _region_owners(campaign, canonical_regions: Array) -> Dictionary:
	var out := {}
	if campaign == null or campaign.world == null:
		return out
	for region in canonical_regions:
		var rid := String(region.get("id", ""))
		var state = campaign.world.region_states.get(rid)
		if state != null:
			out[rid] = String(state.owner)
	return out


static func _alliances(campaign) -> Array:
	var out: Array = []
	if campaign == null or campaign.diplo == null:
		return out
	var keys: Array = campaign.diplo.tiers.keys()
	keys.sort()
	for pair_key in keys:
		var tier := int(campaign.diplo.tiers[pair_key])
		if tier < Diplomacy.Tier.맹약:
			continue
		var parties := String(pair_key).split("|")
		out.append({
			"parties": Array(parties),
			"tier": tier,
			"tier_name": Diplomacy.TIER_NAMES[tier],
			"trust_milli": campaign.diplo.trust_of(parties[0], parties[1]),
		})
	return out


## 관측 주체가 없으면 빈 배열이다. Campaign.observe_fleet은 판독 기록을 써서
## 스냅샷 생성만으로 캠페인이 변할 수 있으므로, 비변이 점시점 판정인
## Orders.observe_fleet의 결과만 그대로 노출한다.
static func _observed_fleets(campaign, viewer: String) -> Array:
	var out: Array = []
	if campaign == null or viewer == "":
		return out
	for fleet in campaign.fleets:
		var observed: Dictionary = Orders.observe_fleet(
			campaign.world, campaign.data, viewer, fleet, campaign.fleets)
		if not bool(observed.get("visible", false)):
			continue
		var safe: Dictionary = observed.duplicate(true)
		var own_fleet := String(fleet.owner) == viewer
		safe["fleet_id"] = fleet.id
		safe["system_id"] = String(observed.get("system", ""))
		safe["status"] = "moving" if bool(observed.get("moving", false)) else "stationed"
		safe["display_name"] = "제%d함대" % fleet.id if own_fleet else "미확인 함대 #%d" % fleet.id
		safe["faction"] = String(fleet.owner) if own_fleet else ""
		if int(observed.get("stage", 0)) >= 2:
			safe["ships"] = int(observed.get("ships_exact", 0))
			safe["ships_display"] = str(safe["ships"])
		else:
			safe["ships_display"] = "%d–%d" % [
				int(observed.get("ships_low", 0)), int(observed.get("ships_high", 0))]
		out.append(safe)
	out.sort_custom(func(a, b): return int(a["fleet_id"]) < int(b["fleet_id"]))
	return out


## SCN-03 적벽은 runtime fixture가 아니라 Campaign의 replay 파생 상태를 읽는다.
## runtime은 코어에 정본이 없는 비적벽 전투의 임시 표시만 보완할 수 있으며, 절대로
## 적벽 ID를 주입하거나 기존 적벽 상태를 덮어쓸 수 없다.
static func _active_battles(campaign, map_data: Dictionary, scenario_id: String,
		runtime: Dictionary) -> Array:
	var out: Array = []
	var conditions := _red_cliff_conditions(campaign, scenario_id, runtime)
	if scenario_id == SCENARIO_03_ID:
		for battle in campaign.active_battles:
			var projected := _project_scn03_red_cliff_battle(battle, map_data, conditions)
			if not projected.is_empty():
				out.append(projected)
	# Generic battles have no current Campaign record. Preserve explicit fixture rows,
	# but reserve the canonical Red-Cliffs identity for the core projection above.
	var provided = runtime.get("active_battles", [])
	if provided is Array:
		for value in provided:
			if value is Dictionary and String(value.get("id", "")) != Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID and String(value.get("id", "")) != "BATTLE-RED-CLIFF":
				var fallback: Dictionary = (value as Dictionary).duplicate(true)
				# Runtime has no Campaign battle record for generic battles. Keep its
				# display ID separate from the authoritative core battle identifier.
				fallback["battle_id"] = String(fallback.get("id", ""))
				fallback["provenance"] = "runtime_fixture"
				out.append(fallback)
	out.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	return out


static func _project_scn03_red_cliff_battle(battle, map_data: Dictionary,
		conditions: Dictionary) -> Dictionary:
	if battle == null or String(battle.battle_id) != Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID or String(battle.scenario_id) != SCENARIO_03_ID:
		return {}
	var guji := _find_named(map_data.get("bodies", []), "구지")
	if guji.is_empty() or String(battle.region_id) != String(guji.get("region", "")) or String(battle.system_id) != String(guji.get("system", "")) or String(battle.anchor_body_id) != String(guji.get("id", "")):
		return {}
	return {
		# `id` is the stable home-map route identity; `battle_id` remains the
		# authoritative replay identity for all state and selection decisions.
		"id": "BATTLE-RED-CLIFF", "battle_id": String(battle.battle_id),
		"canonical_battle_id": String(battle.battle_id), "provenance": "campaign_core",
		"name": "적벽 대회전",
		"scenario_id": String(battle.scenario_id), "cause_event_id": String(battle.cause_event_id),
		"status": String(battle.status), "system_id": String(battle.system_id),
		"region_id": String(battle.region_id), "anchor_body_id": String(battle.anchor_body_id),
		"anchor_position": (guji.get("position", []) as Array).duplicate(true),
		"anchor_kind": "구지 궤도", "created_tick": int(battle.created_tick),
		"started_tick": int(battle.started_tick), "campaign_stage": int(battle.campaign_stage),
		"combat_phase": int(battle.combat_phase), "entry_available": bool(battle.entry_available),
		"conditions": conditions.duplicate(true),
	}


## SCN-03 진행 원장은 unknown을 false로 바꾸지 않는다. 현재 코어가 없는 이전
## 시나리오에서만 기존 runtime fixture를 사용한다.
static func _red_cliff_conditions(campaign, scenario_id: String, runtime: Dictionary) -> Dictionary:
	var provided = campaign.scn03_progress if scenario_id == SCENARIO_03_ID else runtime.get("red_cliff_conditions", {})
	if not provided is Dictionary:
		return {}
	var out := {}
	for key in RED_CLIFF_CONDITIONS:
		if provided.has(key) and typeof(provided[key]) == TYPE_BOOL:
			out[key] = provided[key]
	return out


static func _has_runtime_noncanonical_battle(runtime: Dictionary) -> bool:
	var provided = runtime.get("active_battles", [])
	if not provided is Array:
		return false
	for value in provided:
		if value is Dictionary and String(value.get("id", "")) != Campaign.SCN03_RED_CLIFF_PENDING_BATTLE_ID and String(value.get("id", "")) != "BATTLE-RED-CLIFF":
			return true
	return false


static func _news(value) -> Array:
	if not value is Array:
		return []
	return (value as Array).duplicate(true)


## 외부 세력은 영토 소유자와 섞지 않는다. 좌표가 정본 지도에 없는 세력에는
## 좌표를 만들지 않고, 문서에 확정된 접근축과 관계 종류만 제공한다.
static func _external_powers(at_year: int) -> Array:
	if at_year < 0:
		return []
	var sassanid_active := at_year >= 224
	var rows: Array = [
		{
			"id": "EXT-DONGYI",
			"name": "동이 연합",
			"source": EXTERNAL_POWER_SOURCE,
			"source_status": EXTERNAL_POWER_SOURCE_STATUS,
			"relation_kind": "alliance_eligible",
			"alliance_allowed": true,
			"status": "present",
			"access_axis": "노룡회랑",
		},
		{
			"id": "EXT-DAEYUEZHI",
			"name": "대월지",
			"source": EXTERNAL_POWER_SOURCE,
			"source_status": EXTERNAL_POWER_SOURCE_STATUS,
			"relation_kind": "investiture_alliance_eligible",
			"alliance_allowed": true,
			"status": "present",
			"access_axis": "하서회랑 → 서역",
			"external_node_id": "EXT:서역",
		},
		{
			"id": "EXT-ROME",
			"name": "로마",
			"source": EXTERNAL_POWER_SOURCE,
			"source_status": EXTERNAL_POWER_SOURCE_STATUS,
			"relation_kind": "trade_background",
			"alliance_allowed": false,
			"status": "background",
		},
		{
			"id": "EXT-SASSANID",
			"name": "사산조",
			"source": EXTERNAL_POWER_SOURCE,
			"source_status": EXTERNAL_POWER_SOURCE_STATUS,
			"relation_kind": "external_threat",
			"alliance_allowed": false,
			"status": "active" if sassanid_active else "future",
			"active": sassanid_active,
			"visible_as_current": sassanid_active,
			"starts_year": 224,
		},
	]
	_validate_external_power_rows(rows)
	return rows


## TODO(data migration): 외부 세력 정본 파일이 생기면 이 임시 목록을 로더로 교체한다.
static func _validate_external_power_rows(rows: Array) -> void:
	var seen := {}
	for row in rows:
		var external_id := String(row.get("id", ""))
		assert(external_id.begins_with("EXT-") and external_id.length() > 4,
			"외부 세력 ID는 EXT- 접두사를 써야 한다: " + external_id)
		assert(not seen.has(external_id), "중복 외부 세력 ID: " + external_id)
		assert(String(row.get("source", "")) != "", "외부 세력 source 누락: " + external_id)
		assert(String(row.get("source_status", "")) != "",
			"외부 세력 source_status 누락: " + external_id)
		seen[external_id] = true


static func _find_named(rows, wanted: String) -> Dictionary:
	for row in rows:
		if String(row.get("name", "")) == wanted:
			return row.duplicate(true)
	return {}
