class_name Orders
extends RefCounted

## 명령 판정 코어 — A-03 (`DECISIONS.md` V-60 §8.1 갈라짐 ④·⑤)
##
## ## 무엇을 옮겼나
##
## 화면 페이로드가 하던 두 가지 판정을 여기로 올린다.
##   ⑤ **이동 경로·소요·진형 조건** — `FleetScreens` 가 `Routing.travel_ticks`·
##      `_terrain`·`FormationSpec` 로 직접 산정하고 `travel_ticks` 를 payload 에
##      실어 보냈다. 이제 UI·AI·재생이 **모두 `Orders.resolve_move` 를 부른다.**
##   ④ **관측 단계** — `FleetRow`·`DetailView` 가 적 함대의 진형·제독·척수를
##      게이팅 없이 그대로 그렸다 (`screens.md` §12 · 검토 20). `observe_fleet` 이
##      「무엇을 보일지」를 판정한다 — 「모르는 것을 아는 척하지 않는다」.
##
## ## 역할 계약 (V-60 ①)
##
##   docs = 근거 / data = 값 / core = 판정 / UI = 표시
##
## 이 클래스는 **순수 static · 상태 없음**이다. campaign.gd/world.gd 구조를
## 건드리지 않아 A-01(캠페인 저장 모델)과 편집 구간이 겹치지 않는다.
##
## ## 완료 정의 (V-60 ④)
##
## 「동일 입력에서 UI·AI·재생 결과가 일치」. `resolve_move` 는 (graph, data,
## 출발 성계, 목적 권역)만의 함수다 — 누가 부르든 같은 값이 나온다.
## `tests/run_tests.gd` §35 가 이 일치를 건다.


const UNREACHABLE_REASON: String = "닿지 않는다 — 회랑이 끊겼을 수 있다"


## ---------------------------------------------------------------- 이동 판정 (⑤)
##
## 함대 이동 요청 하나를 판정한다. **UI 는 이 결과를 표시만 하고, 발행
## payload 에는 목적 권역만 싣는다** — 소요·경로·진형 조건은 도달 시
## `Domestic._apply_fleet_move` 가 이 함수로 다시 낸다 (payload 를 믿지 않는다).
##
## 반환:
##   {
##     ok: bool, reason: String,
##     dest_system: String,
##     path: Array[String],           # 성계 경로 (출발 포함) · 닿지 않으면 []
##     travel_ticks: int,             # 45 × 배율 합 · 닿지 않으면 -1
##     corridor_ids: Array[String],   # 경로가 지나는 회랑 (COR-xx)
##     terrain: String,               # "개활" | "기저" | "중회랑" | "대회랑"
##     worst_scale: String,           # "" | "중회랑" | "대회랑"
##     allowed_formations: Array[String],   # 이 경로에서 펼 수 있는 진형
##     forced_formation: String,      # "" 아니면 그 진형으로 고정 (대회랑)
##   }
static func resolve_move(graph: Dictionary, data: GameData,
		from_system: String, dest_region: String) -> Dictionary:
	var out := {
		"ok": false, "reason": "",
		"dest_system": "",
		"path": ([] as Array[String]),
		"travel_ticks": Routing.UNREACHABLE,
		"corridor_ids": ([] as Array[String]),
		"terrain": "개활",
		"worst_scale": "",
		"allowed_formations": Formations.allowed_list("개활"),
		"forced_formation": "",
	}
	if data == null or not data.regions.has(dest_region):
		out["reason"] = "권역 없음: " + dest_region
		return out
	var dest_sys := data.system_of(dest_region)
	if dest_sys == "":
		out["reason"] = "권역의 성계를 알 수 없다: " + dest_region
		return out
	out["dest_system"] = dest_sys

	var t := Routing.travel_ticks(graph, from_system, dest_sys)
	if t == Routing.UNREACHABLE:
		out["reason"] = UNREACHABLE_REASON
		return out

	var p := Routing.path(graph, from_system, dest_sys)
	var cids: Array[String] = []
	if p.size() <= 1:
		# 같은 성계 안 — 목적 권역이 쥔 회랑을 본다
		for h in data.regions[dest_region].get("routes_hosted", []):
			for cid in data.corridor_ids:
				if String(data.corridors[cid]["name"]) == String(h) and not cids.has(cid):
					cids.append(cid)
	else:
		cids = Routing.corridors_on_path(graph, p)

	var terrain := _terrain_from_edges(graph, data, p, cids)
	out["ok"] = true
	out["path"] = p
	out["travel_ticks"] = t
	out["corridor_ids"] = cids
	out["terrain"] = terrain
	out["worst_scale"] = terrain if terrain in ["중회랑", "대회랑"] else ""
	out["allowed_formations"] = Formations.allowed_list(terrain)
	out["forced_formation"] = Formations.forced_formation(terrain)
	return out


## 경로가 부과하는 지형 — "개활" | "기저" | "중회랑" | "대회랑".
## 회랑 > 기저 항로 > 개활 순으로 최악을 취한다 (`screens.md` §3.3).
static func terrain_on_route(graph: Dictionary, data: GameData,
		from_system: String, to_system: String) -> String:
	if from_system == to_system or from_system == "" or to_system == "":
		return "개활"
	var p := Routing.path(graph, from_system, to_system)
	if p.size() <= 1:
		return "개활"
	var cids := Routing.corridors_on_path(graph, p)
	return _terrain_from_edges(graph, data, p, cids)


## 한 권역이 쥔 지형 — 그 권역에 주둔한 함대가 펴는 진형의 제약 (`screens.md` §3.3).
## 권역이 회랑을 끼고 있으면 그 등급, 아니면 "개활". `routes.json` 에 비회랑
## 항로의 권역 귀속이 없어 기저 항로는 가려내지 못한다 (검토 13).
static func terrain_of_region(data: GameData, region_id: String) -> String:
	if data == null or not data.regions.has(region_id):
		return "개활"
	var worst := "개활"
	for h in data.regions[region_id].get("routes_hosted", []):
		var nm := String(h)
		if not data.is_corridor(nm):
			continue
		for cid in data.corridor_ids:
			if String(data.corridors[cid]["name"]) != nm:
				continue
			var sc := String(data.corridors[cid].get("scale", ""))
			if sc == "대회랑":
				return "대회랑"
			if sc == "중회랑":
				worst = "중회랑"
	return worst


## 경로 간선의 회랑 등급·항로 종류로 지형을 정한다.
static func _terrain_from_edges(graph: Dictionary, data: GameData,
		p: Array, corridor_ids: Array) -> String:
	var worst := "개활"
	for cid in corridor_ids:
		if not data.corridors.has(cid):
			continue
		var sc := String(data.corridors[cid].get("scale", ""))
		if sc == "대회랑":
			return "대회랑"
		if sc == "중회랑":
			worst = "중회랑"
	if worst != "개활":
		return worst
	# 회랑이 없으면 기저 항로 여부를 본다 (광폭 전개 불가 · §3.3)
	for i in range(p.size() - 1):
		for e in graph.get(p[i], []):
			if e["to"] == p[i + 1]:
				if String(e.get("kind", "")).begins_with("기저"):
					worst = "기저"
				break
	return worst


## ---------------------------------------------------------------- 관측 판정 (④)
##
## `viewer_fid` 가 `target` 함대에 대해 지금 무엇을 아는가 (`screens.md` §12.2).
##
## | 단계 | 조건 | 아는 것 |
## |---|---|---|
## | 0 미접촉 | 같은 성계에 아군 자산 없음 | 아무것도 |
## | 1 포착 | 같은 성계에 아군 함대 · 주둔 권역 | 존재 · 위치 · 척수(±20%) · 이동 방향 |
## | 2 판독 | 접적 **또는** 전자전함 ≥10% + 1개월 체류 | 편성안 · 진형 · 제독 · 사기 구간 |
##
## `contact` = 전투 ① 페이즈 돌입을 아는 호출자(전투 레인)가 넘긴다. 전자전함
## 편성 판정은 함종별 척수(`A-04`)가 서야 가능하다 — 그 전까지 recon 경로는
## 언제나 미달로 친다 (「모르는 것을 아는 척하지 않는다」 · §12.4).
##
## `world` 만 받는다 (factions·diplo 는 Campaign 소관). 동맹 자산을 아군으로
## 세는 것은 후속(A-06 관측 통합)에서 diplo 를 넘겨 확장한다.
static func observe_fleet(world: World, data: GameData, viewer_fid: String,
		target: Fleet, all_fleets: Array, contact: bool = false) -> Dictionary:
	var sys := target.at_system
	var out := {
		"stage": 0,
		"visible": false,
		"system": sys,
		"moving": target.is_moving(),
		"dest_region": target.target_region if target.is_moving() else "",
		"ships_exact": 0,
		"ships_low": 0, "ships_high": 0,
		"formation": "",
		"commander_name": "",
		"plan": "",
		"morale_exact": 0,
		"morale_band": "",
		"note": "",
	}
	if viewer_fid == "" or target == null:
		out["note"] = "관측자 세력 미상"
		return out
	if target.owner == viewer_fid:
		# 아군 함대는 관측이 아니라 완전 정보다
		out["stage"] = 2
		out["visible"] = true
		out["ships_exact"] = target.ships
		out["ships_low"] = target.ships
		out["ships_high"] = target.ships
		out["formation"] = String(target.formation) if "formation" in target else ""
		out["commander_name"] = target.commander_name
		out["plan"] = target.plan
		out["morale_exact"] = target.morale
		out["morale_band"] = _morale_band(target.morale)
		return out

	var has_asset := _viewer_has_asset(world, data, viewer_fid, sys, target, all_fleets)
	if not has_asset:
		out["note"] = "미접촉 — 같은 성계에 아군 자산이 없다"
		return out

	# 단계 1 · 포착
	out["stage"] = 1
	out["visible"] = true
	var band := ships_band(target.ships)
	out["ships_low"] = band[0]
	out["ships_high"] = band[1]

	# 단계 2 · 판독 — 접적만 (전자전함 recon 경로는 A-04 후)
	if contact:
		out["stage"] = 2
		out["ships_exact"] = target.ships
		out["formation"] = String(target.formation) if "formation" in target else ""
		out["commander_name"] = target.commander_name
		out["plan"] = target.plan
		out["morale_exact"] = target.morale
		out["morale_band"] = _morale_band(target.morale)
	else:
		out["note"] = "포착 — 편성·진형·제독은 접적 시 판독 (전자전함 관측 = A-04 후)"
	return out


## 척수 ±20% 밴드 (§12.2 단계 1). [하한, 상한].
static func ships_band(ships: int) -> Array:
	return [ships * 80 / 100, (ships * 120 + 99) / 100]


## 사기 구간 — 정확값을 숨기고 구간만 (§12.2 단계 2 「사기 구간」).
static func _morale_band(morale: int) -> String:
	if morale <= Battle.MORALE_COLLAPSE_CEIL:
		return "붕괴 위험"
	if morale < 70:
		return "낮음"
	if morale <= 110:
		return "보통"
	return "높음"


## `viewer_fid` 가 `sys` 성계에 관측 자산을 두고 있는가 —
## 주둔·이동 아닌 아군 함대, 또는 그 성계에 보유 권역.
static func _viewer_has_asset(world: World, data: GameData, viewer_fid: String,
		sys: String, target: Fleet, all_fleets: Array) -> bool:
	for fl in all_fleets:
		if fl == target or fl.owner != viewer_fid or not fl.is_alive():
			continue
		if fl.at_system == sys and not fl.is_moving():
			return true
	if data != null and world != null:
		for rid in data.regions_of.get(sys, []):
			var st = world.region_states.get(rid)
			if st != null and String(st.owner) == viewer_fid:
				return true
	return false
