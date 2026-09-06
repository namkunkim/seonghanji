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
	var live_state = Snapshot.from_campaign(campaign, 208, {"viewer_faction": "손권"})
	_eq(live_state.alliances().size(), 1, "코어의 성립 동맹만 투영")
	_ok(live_state.observed_fleets().size() > 0, "관측 주체가 있으면 코어 판정 함대를 투영")
	var allowed_observation_keys := [
		"stage", "visible", "system", "moving", "dest_region",
		"ships_exact", "ships_low", "ships_high", "formation",
		"commander_name", "plan", "morale_exact", "morale_band", "note",
	]
	for observed in live_state.observed_fleets():
		for key in observed.keys():
			_ok(allowed_observation_keys.has(key), "관측 계약 밖 함대 필드 비노출: " + String(key))
		_ok(not observed.has("arrival_tick"), "정확 도착 틱 비노출")
		_ok(not observed.has("target_region"), "원시 목표 권역 비노출")

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

	print("HomeMapSnapshot: %d 통과 / %d 실패" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
