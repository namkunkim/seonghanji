extends SceneTree

const Snapshot := preload("res://app/home_map_snapshot.gd")

var _pass := 0
var _fail := 0


func _ok(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  실패: ", label)


func _eq(got, wanted, label: String) -> void:
	_ok(got == wanted, "%s — 기대 %s, 실제 %s" % [label, str(wanted), str(got)])


func _by_name(rows: Array, wanted: String) -> Dictionary:
	for row in rows:
		if String(row.get("name", "")) == wanted:
			return row
	return {}


func _ids(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append(String(row.get("id", "")))
	return out


func _unique(values: Array) -> bool:
	var seen := {}
	for value in values:
		if seen.has(value):
			return false
		seen[value] = true
	return true


func _assert_invalid(state, reason: String, label: String) -> void:
	_ok(not state.is_valid(), label + " — 무효 상태")
	_eq(state.year(), -1, label + " — 연도 제거")
	_eq(state.validation_error(), reason, label + " — 사유")
	_eq(state.presentation()["valid"], false, label + " — 표시 계약 무효")
	_eq(state.presentation()["invalid_reason"], reason, label + " — 표시 사유")
	_eq(state.region_owner(), {}, label + " — 소유 상태 차단")
	_eq(state.alliances(), [], label + " — 동맹 상태 차단")
	_eq(state.observed_fleets(), [], label + " — 함대 상태 차단")
	_eq(state.active_battles(), [], label + " — 전투 상태 차단")
	_eq(state.news(), [], label + " — 뉴스 상태 차단")
	_eq(state.external_powers(), [], label + " — 외부 세력 차단")


func _init() -> void:
	var campaign := Campaign.scenario_03(GameData.load_all(), 208)
	var state = Snapshot.from_campaign(campaign)

	_eq(state.scenario_id(), "SCN-03", "208 POC 시나리오 ID")
	_eq(state.year(), 208, "208 POC 연도")
	_eq(state.schema_version(), 1, "홈 런타임 투영 스키마 버전")
	_eq(state.scenario(), {
		"id": "SCN-03", "start_year": 208, "tick": 0, "year": 208,
		"month": 1, "speed": 1, "paused": false, "ended": false,
		"end_reason": "",
	}, "초기 시나리오 시계는 코어 상태를 투영")
	_eq(state.viewer(), {"faction_id": "", "valid": false},
		"플레이어 미지정이면 viewer를 발명하지 않음")
	_eq(state.player_state()["faction_id"], "", "플레이어 미지정 상태")
	_eq(state.factions().size(), 8, "코어에 실제 존재하는 8세력만 투영")
	_ok(_by_name(state.factions(), "유비").is_empty(), "미구현 유비 세력을 발명하지 않음")
	var allowed_faction_keys := [
		"id", "name", "capital_system", "alive", "wandering", "region_count",
	]
	for faction in state.factions():
		for key in faction.keys():
			_ok(allowed_faction_keys.has(key), "공개 세력 계약 밖 전략 상태 비노출: " + String(key))
		_ok(not faction.has("treasury") and not faction.has("mandate") \
			and not faction.has("hegemony") and not faction.has("tech"),
			"타 세력 전략 상태는 player_state에만 둠")
	_eq(state.capabilities()["external_powers"], false, "외부 세력은 fallback capability")
	_eq(state.capabilities()["active_battles"], false, "활성 전투는 코어 미지원")
	_eq(state.provenance()["external_powers"], "home_map_snapshot_fallback",
		"외부 세력 fallback 출처")
	_ok(state.is_valid(), "208 POC 투영은 유효")
	_eq(state.presentation()["valid"], true, "정상 표시 계약은 유효")
	_eq(state.canonical_systems().size(), 19, "정본 성계 19개")
	_eq(state.canonical_regions().size(), 45, "정본 권역 45개")
	_eq(state.canonical_bodies().size(), 245, "정본 천체 245개")
	_eq(state.canonical_routes().size(), 37, "정본 항로 37개")
	_ok(_unique(_ids(state.canonical_systems())), "성계 ID는 유일하다")
	_ok(_unique(_ids(state.canonical_regions())), "권역 ID는 유일하다")
	_ok(_unique(_ids(state.canonical_bodies())), "천체 ID는 유일하다")
	var sys_13 := _by_name(state.canonical_systems(), "형주")
	_eq(sys_13.get("id"), "SYS-13", "형주 정본 성계 ID")
	_eq(sys_13.get("regions"), ["RGN-01", "RGN-02", "RGN-03", "RGN-04"],
		"SYS-13 정본 권역 ID")
	_eq(state.solar_region().get("id"), "RGN-04", "태양계권 정본 권역 ID")
	_eq(state.solar_region().get("system"), "SYS-13", "RGN-04는 SYS-13 소속")
	_ok(not _by_name(state.canonical_bodies(), "구지").is_empty(), "구지가 정본 천체에 있다")
	_ok(not _by_name(state.canonical_bodies(), "형혹").is_empty(), "형혹이 정본 천체에 있다")
	_ok(not _by_name(state.canonical_bodies(), "태음").is_empty(), "태음이 정본 천체에 있다")
	_ok(_by_name(state.visible_bodies(0), "구지").is_empty(), "Z0에서 구지는 비강조")
	_ok(_by_name(state.visible_bodies(1), "형혹").is_empty(), "Z1에서 형혹은 비강조")
	_ok(not _by_name(state.visible_bodies(2), "구지").is_empty(), "Z2에서 구지 표시")
	_ok(not _by_name(state.visible_bodies(3), "태음").is_empty(), "Z3에서 태음 표시")
	_eq(state.presentation()["solar_detail_min_zoom"], 2, "태양계 세부 표시 단계 계약")

	var jingzhou := state.jingzhou_regions()
	_eq(jingzhou.size(), 4, "형주는 네 권역")
	var owners := state.region_owner()
	_eq(owners["RGN-01"], "조조", "208 북부권은 조조")
	_eq(owners["RGN-02"], "유종", "208 중부권은 유종")
	_eq(owners["RGN-03"], "유종", "208 남부권은 유종")
	_eq(owners["RGN-04"], "유종", "208 태양계권은 유종")
	_eq(state.region_states()["RGN-04"]["owner"], "유종", "권역 가변 상태 소유자")
	_eq(state.region_states()["RGN-04"]["detail_visibility"], "public",
		"플레이어 미지정이면 권역 상태는 공개 수준")
	_ok(not state.region_states()["RGN-04"].has("stability") \
		and not state.region_states()["RGN-04"].has("garrison") \
		and not state.region_states()["RGN-04"].has("development"),
		"타 세력 권역의 exact 전략 상세 비노출")
	_ok(not jingzhou[0].has("owner"), "정본 지형과 소유 상태는 분리된다")

	_eq(state.active_battles(), [], "기본 시작에는 미래 적벽 표식이 없다")
	var four_conditions := {
		"cao_southward_complete": true,
		"sun_quan_independent": true,
		"liu_bei_hostile_to_cao": true,
		"sun_liu_military_pact": true,
		"yangtze_defense_line": false,
	}
	var not_ready = Snapshot.from_campaign(campaign, 208,
		{"red_cliff_conditions": four_conditions})
	_eq(not_ready.active_battles(), [], "다섯 조건 중 하나라도 거짓이면 적벽 없음")
	four_conditions["yangtze_defense_line"] = true
	var conditions_only = Snapshot.from_campaign(campaign, 208,
		{"red_cliff_conditions": four_conditions})
	_eq(conditions_only.active_battles(), [], "다섯 조건만으로 미래 전투를 확정하지 않음")
	var partial_conditions := {
		"cao_southward_complete": true,
		"sun_quan_independent": false,
		"unknown_condition": true,
	}
	var partial = Snapshot.from_campaign(campaign, 208,
		{"red_cliff_conditions": partial_conditions})
	_eq(partial.snapshot()["red_cliff_conditions"], {
		"cao_southward_complete": true,
		"sun_quan_independent": false,
	}, "적벽 조건은 true/false를 보존하고 missing/미지 키를 만들지 않음")
	partial_conditions["cao_southward_complete"] = false
	partial_conditions["sun_quan_independent"] = true
	var leaked_conditions: Dictionary = partial.snapshot()["red_cliff_conditions"]
	leaked_conditions["cao_southward_complete"] = false
	_eq(partial.snapshot()["red_cliff_conditions"], {
		"cao_southward_complete": true,
		"sun_quan_independent": false,
	}, "적벽 조건 입력과 snapshot 반환값은 깊은 복사")
	var ready = Snapshot.from_campaign(campaign, 208, {
		"active_battles": [{"id": "BATTLE-RED-CLIFF", "status": "active"}],
		"red_cliff_conditions": four_conditions,
	})
	_eq(ready.active_battles().size(), 1, "다섯 조건이 모두 참이면 적벽 활성")
	_eq(ready.active_battles()[0]["anchor_body_id"], "BODY-RGN-04-01",
		"적벽은 구지 궤도에 고정")
	_ok(not _by_name(ready.visible_bodies(0), "구지").is_empty(),
		"관련 사건 활성 중에는 Z0에서도 구지 표시")

	var powers := state.external_powers()
	var dongyi := _by_name(powers, "동이 연합")
	var yuezhi := _by_name(powers, "대월지")
	var rome := _by_name(powers, "로마")
	var sassanid := _by_name(powers, "사산조")
	_eq(dongyi["relation_kind"], "alliance_eligible", "동이 연합은 동맹 가능")
	_eq(yuezhi["external_node_id"], "EXT:서역", "대월지는 서역 접근축 사용")
	_eq(rome["relation_kind"], "trade_background", "로마는 교역·배경 세력")
	_ok(not bool(rome["alliance_allowed"]), "로마와 동맹 불가")
	_eq(sassanid["status"], "future", "208 사산조는 미래 상태")
	_ok(not bool(sassanid["visible_as_current"]), "208 사산조를 현재 세력으로 표시하지 않음")
	_eq([dongyi["status"], yuezhi["status"], rome["status"], sassanid["status"]],
		["present", "present", "background", "future"], "208 외부 4종 상태")
	_ok(_unique(_ids(powers)), "외부 세력 ID는 유일하다")
	for power in powers:
		_ok(String(power["id"]).begins_with("EXT-"), "외부 세력 ID 접두사")
		_eq(power["source"], "home_map_snapshot_fallback", "외부 세력 임시 소스 표시")
		_eq(power["source_status"], "pending_data_migration", "외부 세력 이관 대기 표시")

	var mismatch = Snapshot.from_campaign(campaign, 224)
	_assert_invalid(mismatch, "SCN-03 only supports year 208", "SCN-03 연도 모순")

	var invalid_runtime := {
		"viewer_faction": "손권",
		"active_battles": [{"id": "FAKE", "status": "active", "region_id": "RGN-04"}],
		"news": [{"title": "주입 뉴스"}],
	}
	var null_state = Snapshot.from_campaign(null, 208, invalid_runtime)
	_assert_invalid(null_state, "missing_campaign", "캠페인 없음")
	_ok(null_state.canonical_bodies().size() == 245, "무효 상태도 정본 지리는 읽을 수 있다")

	var worldless := Campaign.new()
	var worldless_state = Snapshot.from_campaign(worldless, 208, invalid_runtime)
	_assert_invalid(worldless_state, "missing_world", "월드 없음")

	var missing_scenario := Campaign.new()
	missing_scenario.world = World.new()
	missing_scenario.world.scenario = ""
	var missing_scenario_state = Snapshot.from_campaign(missing_scenario, 208,
		invalid_runtime)
	_assert_invalid(missing_scenario_state, "missing_scenario", "시나리오 ID 없음")

	var unknown_scenario := Campaign.new()
	unknown_scenario.world = World.new()
	unknown_scenario.world.scenario = "SCN-UNKNOWN"
	var unknown_state = Snapshot.from_campaign(unknown_scenario, 208, invalid_runtime)
	_assert_invalid(unknown_state, "unsupported_scenario: SCN-UNKNOWN", "알 수 없는 시나리오")

	campaign.diplo.set_tier("손권", "유종", Diplomacy.Tier.맹약)
	var enemy_fleet: Fleet
	for fleet in campaign.fleets:
		if fleet.owner != "손권":
			enemy_fleet = fleet
			break
	_ok(enemy_fleet != null, "적 함대 fixture 확보")
	if enemy_fleet != null:
		enemy_fleet.at_system = campaign.factions["손권"].capital_system
		enemy_fleet.arrival_tick = -1
	var live_state = Snapshot.from_campaign(campaign, 208, {"viewer_faction": "손권"})
	_eq(live_state.alliances().size(), 1, "코어의 성립 동맹만 투영")
	_ok(live_state.observed_fleets().size() > 0, "관측 주체가 있으면 코어 판정 함대를 투영")
	var allowed_observation_keys := [
		"stage", "visible", "system", "moving", "dest_region",
		"ships_exact", "ships_low", "ships_high", "formation",
		"commander_name", "plan", "morale_exact", "morale_band", "note",
		"fleet_id", "system_id", "status", "display_name", "faction",
		"ships", "ships_display",
	]
	var own_seen := false
	var enemy_seen := false
	var last_fleet_id := -1
	for observed in live_state.observed_fleets():
		for key in observed.keys():
			_ok(allowed_observation_keys.has(key), "관측 계약 밖 함대 필드 비노출: " + String(key))
		_ok(not observed.has("arrival_tick"), "정확 도착 틱 비노출")
		_ok(not observed.has("target_region"), "원시 목표 권역 비노출")
		_ok(int(observed["fleet_id"]) > last_fleet_id, "관측 함대 stable fleet_id 정렬")
		last_fleet_id = int(observed["fleet_id"])
		_eq(observed["system_id"], observed["system"], "UI 성역 ID는 관측 위치와 동일")
		_eq(observed["status"], "moving" if observed["moving"] else "stationed",
			"UI 함대 상태는 관측 이동 여부에서 파생")
		_ok(String(observed["display_name"]) != "", "UI 함대 표시명 제공")
		_ok(String(observed["ships_display"]) != "", "UI 척수 또는 안전 범위 제공")
		if String(observed["faction"]) == "손권":
			own_seen = true
			_ok(observed.has("ships"), "아군은 정확 척수를 숫자로 제공")
		elif enemy_fleet != null and int(observed["fleet_id"]) == enemy_fleet.id:
			enemy_seen = true
			_eq(observed["faction"], "", "적 함대 소유 세력 미노출")
			_ok(not observed.has("ships"), "포착 단계 적 함대 정확 척수 미노출")
			_eq(observed["ships_display"], "%d–%d" % [observed["ships_low"], observed["ships_high"]],
				"적 함대는 관측 허용 척수 범위만 표시")
	_ok(own_seen, "아군 함대는 실제 소유자와 안정 ID로 식별")
	_ok(enemy_seen, "적 함대는 소유자 없이 안정 ID로 식별")

	var leaked := state.snapshot()
	leaked["region_owner"]["RGN-04"] = "변조"
	leaked["canonical_bodies"][0]["name"] = "변조"
	_eq(state.region_owner()["RGN-04"], "유종", "반환 소유 맵 변경이 원본에 영향 없음")
	_ok(_by_name(state.canonical_bodies(), "구지").get("name") == "구지",
		"반환 중첩 배열 변경이 원본에 영향 없음")
	var body_copy := state.old_earth_body()
	body_copy["name"] = "변조"
	_eq(state.old_earth_body()["name"], "구지", "접근자도 깊은 복사 반환")

	var runtime_battles := [{"id": "BATTLE-RED-CLIFF", "status": "active"}]
	var runtime_news := [{"title": "원본 소식", "tags": ["정본"]}]
	var mutable_runtime := {
		"active_battles": runtime_battles,
		"red_cliff_conditions": four_conditions,
		"news": runtime_news,
	}
	var isolated = Snapshot.from_campaign(campaign, 208, mutable_runtime)
	runtime_battles[0]["status"] = "removed"
	runtime_news[0]["tags"][0] = "변조"
	four_conditions["yangtze_defense_line"] = false
	_eq(isolated.active_battles().size(), 1, "runtime 전투 입력 변경과 분리")
	_eq(isolated.news()[0]["tags"][0], "정본", "runtime 중첩 뉴스 입력 변경과 분리")
	_ok(bool(isolated.active_battles()[0]["conditions"]["yangtze_defense_line"]),
		"runtime 조건 입력 변경과 분리")
	_eq(isolated.provenance()["active_battles"], "runtime_fixture",
		"주입 활성 전투는 코어가 아닌 fixture로 표시")
	_eq(isolated.provenance()["news"], "runtime_fixture",
		"주입 뉴스는 코어가 아닌 fixture로 표시")

	var runtime_campaign := Campaign.scenario_03(GameData.load_all(), 209)
	runtime_campaign.world.player_faction = "손권"
	runtime_campaign.world.clock.step_ticks(GameClock.TICKS_PER_MONTH * 14)
	runtime_campaign.world.clock.speed = 2
	runtime_campaign.world.clock.paused = true
	runtime_campaign.events_fired = {"F-12": 2, "F-07": 1}
	runtime_campaign.world.issue("개발", {
		"faction": "손권", "region": "RGN-29", "secret": "노출 금지",
	}, 12)
	runtime_campaign.world.issue("개발", {
		"faction": "조조", "region": "RGN-01",
	}, 5)
	runtime_campaign.world.issue("함대이동", {
		"faction": "손권", "fleet": 1, "region": "RGN-04",
	}, 9, "ai")
	var runtime_state = Snapshot.from_campaign(runtime_campaign)
	_eq(runtime_state.viewer(), {"faction_id": "손권", "valid": true},
		"viewer 기본값은 world.player_faction")
	var own_region_id := String(runtime_campaign.factions["손권"].regions[0])
	var enemy_region_id := "RGN-04"
	var projected_regions := runtime_state.region_states()
	_eq(projected_regions[own_region_id]["detail_visibility"], "full",
		"플레이어 소유 권역은 상세 공개")
	_eq(projected_regions[own_region_id]["stability"],
		runtime_campaign.world.region_states[own_region_id].stability,
		"플레이어 권역 안정도 코어 값 일치")
	_eq(projected_regions[own_region_id]["garrison"],
		runtime_campaign.world.region_states[own_region_id].garrison,
		"플레이어 권역 주둔 코어 값 일치")
	_eq(projected_regions[own_region_id]["development"],
		runtime_campaign.world.region_states[own_region_id].development,
		"플레이어 권역 개발 코어 값 일치")
	_eq(projected_regions[enemy_region_id]["detail_visibility"], "public",
		"타 세력 권역은 공개 수준")
	_ok(not projected_regions[enemy_region_id].has("stability") \
		and not projected_regions[enemy_region_id].has("garrison") \
		and not projected_regions[enemy_region_id].has("war_damage_milli") \
		and not projected_regions[enemy_region_id].has("recovery_investment") \
		and not projected_regions[enemy_region_id].has("delegated"),
		"타 세력 권역 exact 전략 필드 차단")
	_eq(runtime_state.scenario()["tick"], GameClock.TICKS_PER_MONTH * 14,
		"현재 코어 tick 투영")
	_eq([runtime_state.scenario()["year"], runtime_state.scenario()["month"]],
		[209, 3], "현재 연월 계산")
	_eq([runtime_state.scenario()["speed"], runtime_state.scenario()["paused"]],
		[2, true], "코어 배속과 정지 상태 투영")
	var player := runtime_state.player_state()
	_eq(player["faction_id"], "손권", "플레이어 상태 세력")
	_eq(player["treasury"], runtime_campaign.factions["손권"].treasury,
		"플레이어 실제 자금")
	_eq(player["budget"]["net"], runtime_campaign.budget("손권")[5],
		"플레이어 실제 월 순수지")
	_ok(int(player["mobilized"]) > 0, "플레이어 실동원 투영")
	_ok(int(player["fleet_capacity_milli"]) > 0, "플레이어 함대 수용력 투영")
	_ok(int(player["fleet_used_milli"]) > 0, "플레이어 함대 사용량 투영")
	_eq(runtime_state.event_counts(), {"F-07": 1, "F-12": 2},
		"이벤트는 뉴스가 아닌 누적 집계로 투영")
	_eq(runtime_state.pending_commands().size(), 1,
		"플레이어 자신의 비AI 대기 명령만 노출")
	_eq(runtime_state.pending_commands()[0]["seq"], 0, "대기 명령 seq 정렬")
	_eq(runtime_state.pending_commands()[0]["remaining_ticks"], 12,
		"대기 명령 남은 tick")
	_ok(not runtime_state.pending_commands()[0]["payload"].has("secret"),
		"대기 명령 payload 허용 필드만 노출")
	var leaked_runtime := runtime_state.snapshot()
	leaked_runtime["player_state"]["budget"]["net"] = 999999
	leaked_runtime["pending_commands"][0]["payload"]["region"] = "변조"
	_eq(runtime_state.player_state()["budget"]["net"], runtime_campaign.budget("손권")[5],
		"플레이어 중첩 상태 깊은 복사")
	_eq(runtime_state.pending_commands()[0]["payload"]["region"], "RGN-29",
		"대기 명령 중첩 상태 깊은 복사")

	print("HomeMapSnapshot: %d 통과 / %d 실패" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
