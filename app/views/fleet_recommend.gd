class_name FleetRecommend
extends RefCounted

## 함대 추천 편성 — `screens.md` §4.5 알고리즘 (요구 B7 · 구현 순서 ⑥)
##
## **순수 함수다.** 난수도 부동소수도 쓰지 않는다 (`DECISIONS.md` V-31).
## `SC-F2` 편성 시트의 [추천] 버튼이 이것을 부르고, 결과를 그대로 시트에 싣는다.
##
## 입력 — 목적 권역 · 경로(`Routing`) · 제독 통솔 · 여유 유지점 · 관측된 적 편성.
## **관측은 코어에 없다** (§12 — 은폐·정찰 시스템 부재). 그래서 §4.5 보정 중
## 「관측된 적 강습모함 비율」 항은 **언제나 미달**로 친다 —
## 「모르는 것을 아는 척하지 않는다」(§4.5).
##
## 진형 이름·요구 통솔·지형 허용은 `FormationSpec`(= `data/formations.json`)이 정본이다.

## 진형 하향 사슬 (§4.5) — 요구 통솔 미달이면 충족하는 가장 가까운 진형으로 내린다.
##   학익 75 → 봉시 70 → 안행 65 → 어린 60 → 방원 55 → 장사 40
const DOWNGRADE_CHAIN: Array[String] = [
	"학익진", "봉시진", "안행진", "어린진", "방원진", "장사진",
]

## 5전대 = 1함대. 규모 추천은 이 단위로 내림한다 (§4.5).
const FLEET_SQUADRONS_MILLI: int = 5000
const MIN_SQUADRONS_MILLI: int = 1000


## 추천 한 벌. 반환:
##   { plan, formation, axis, step, rule_no, rec_squadrons_milli, note }
## axis 는 "화력"/"돌파"/"지속"/"" · step 은 0~2.
static func recommend(data: GameData, campaign: Campaign, fl: Fleet,
		dest_rid: String, spare_points: int) -> Dictionary:
	var owner := fl.owner
	var corridors := corridors_on_route(data, campaign, fl.at_system, dest_rid)
	var scale := worst_corridor_scale(data, corridors)   # "대회랑"/"중회랑"/""

	var dest_owner := ""
	if dest_rid != "" and campaign.world.region_states.has(dest_rid):
		dest_owner = String(campaign.world.region_states[dest_rid].owner)
	var dest_hosts_corridor := _region_hosts_corridor(data, dest_rid)

	# ---------------------------------------------------------------- 규칙 (첫 일치)
	var plan := "균형"
	var formation := "어린진"
	var rule_no := 6
	if scale == "대회랑":
		plan = "회랑 돌파"; formation = "장사진"; rule_no = 1
	elif scale == "중회랑" or _route_has_gate(data, campaign, fl.at_system, dest_rid):
		plan = "회랑 돌파"; formation = "방원진"; rule_no = 2
	elif dest_owner != "" and dest_owner != owner:
		plan = "성계 공략"; formation = "안행진"; rule_no = 3
	elif dest_owner == owner and dest_hosts_corridor:
		plan = "봉쇄 유지"; formation = "방원진"; rule_no = 4
	elif _route_all_fast(data, campaign, fl.at_system, dest_rid) and dest_owner != owner:
		plan = "개활 결전"; formation = "어린진"; rule_no = 5

	# ---------------------------------------------------------------- 보정 (한 번만)
	var axis := ""
	var step := 0
	# ① 관측된 적 강습모함 비율 > 25% → 돌파 +1 : 관측 부재 → 적용 안 함 (§12.4)
	# ② 목적지 비지·보급 단절 위험 → 지속 +1
	if dest_owner == owner and _is_enclave(data, campaign, dest_rid):
		axis = "지속"; step = 1
	# ③ 규칙 1·2 채택 → 화력 +1 (관측 불요)
	if rule_no <= 2:
		axis = "화력"; step = 1

	# ---------------------------------------------------------------- 진형 하향
	var req := FormationSpec.required_command(formation)
	var forced := (rule_no == 1)                      # 대회랑은 장사진 강제 — 내리지 않는다
	if not forced and fl.command < req:
		formation = _downgrade(fl.command, formation)

	# ---------------------------------------------------------------- 규모
	var per := Economy.plan_point_milli(plan)         # 전대당 유지점 (milli)
	var cl := Roster.command_limit(fl.command)        # 지휘 한도 (유지점)
	var rec_milli := 0
	if per > 0:
		var by_command := cl * 1_000_000 / per
		var by_budget := maxi(spare_points, 0) * 1_000_000 / per
		rec_milli = mini(by_command, by_budget)
		rec_milli = rec_milli / FLEET_SQUADRONS_MILLI * FLEET_SQUADRONS_MILLI
		rec_milli = maxi(rec_milli, MIN_SQUADRONS_MILLI)

	return {
		"plan": plan,
		"formation": formation,
		"axis": axis,
		"step": step,
		"rule_no": rule_no,
		"rec_squadrons_milli": rec_milli,
		"note": _rule_note(rule_no, axis, step, corridors, data),
	}


## 「대회랑 통과 · 화력 +1」 식 한 줄 (§4.5 마지막 문단).
static func _rule_note(rule_no: int, axis: String, step: int,
		corridors: Array, data: GameData) -> String:
	var head := {
		1: "대회랑 통과", 2: "중회랑·관문 통과", 3: "적 권역 공략",
		4: "자국 회랑 주둔", 5: "고속항로 조우 예상", 6: "표준",
	}
	var s := String(head.get(rule_no, "표준"))
	if not corridors.is_empty():
		var names: Array[String] = []
		for cid in corridors:
			names.append(String(data.corridors[cid]["name"]))
		s += " (" + " · ".join(names) + ")"
	if axis != "" and step > 0:
		s += " · %s +%d" % [axis, step]
	return s


## ---------------------------------------------------------------- 경로 판정
##
## `Routing` 은 성계 그래프다. 목적 권역의 성계까지 최단 경로를 풀어
## 그 경로가 지나는 회랑을 본다 (`Routing.corridors_on_path`).
static func corridors_on_route(data: GameData, campaign: Campaign,
		from_sys: String, dest_rid: String) -> Array:
	if dest_rid == "" or from_sys == "":
		return []
	var to_sys := data.system_of(dest_rid)
	var p := Routing.path(campaign.world.graph, from_sys, to_sys)
	if p.size() <= 1:
		# 같은 성계 안이면 목적 권역이 쥔 회랑을 본다
		return _region_corridor_ids(data, dest_rid)
	return Routing.corridors_on_path(campaign.world.graph, p)


static func _region_corridor_ids(data: GameData, rid: String) -> Array:
	var out: Array = []
	if rid == "" or not data.regions.has(rid):
		return out
	for h in data.regions[rid].get("routes_hosted", []):
		for cid in data.corridor_ids:
			if String(data.corridors[cid]["name"]) == String(h) and not out.has(cid):
				out.append(cid)
	return out


static func _region_hosts_corridor(data: GameData, rid: String) -> bool:
	if rid == "" or not data.regions.has(rid):
		return false
	for h in data.regions[rid].get("routes_hosted", []):
		if data.is_corridor(String(h)):
			return true
	return false


## 경로의 최악 회랑 등급. 대회랑 > 중회랑 > (없음).
static func worst_corridor_scale(data: GameData, corridor_ids: Array) -> String:
	var worst := ""
	for cid in corridor_ids:
		if not data.corridors.has(cid):
			continue
		var sc := String(data.corridors[cid].get("scale", ""))
		if sc == "대회랑":
			return "대회랑"
		if sc == "중회랑":
			worst = "중회랑"
	return worst


## 경로에 관문(고속항로+관문)이 있는가 — 중회랑과 같은 취급 (규칙 2).
static func _route_has_gate(data: GameData, campaign: Campaign,
		from_sys: String, dest_rid: String) -> bool:
	if dest_rid == "" or from_sys == "":
		return false
	var to_sys := data.system_of(dest_rid)
	var p := Routing.path(campaign.world.graph, from_sys, to_sys)
	for i in range(p.size() - 1):
		for e in campaign.world.graph.get(p[i], []):
			if e["to"] == p[i + 1] and "관문" in String(e.get("kind", "")):
				return true
	return false


## 경로가 전부 고속항로인가 (규칙 5).
static func _route_all_fast(data: GameData, campaign: Campaign,
		from_sys: String, dest_rid: String) -> bool:
	if dest_rid == "" or from_sys == "":
		return false
	var to_sys := data.system_of(dest_rid)
	if from_sys == to_sys:
		return false
	var p := Routing.path(campaign.world.graph, from_sys, to_sys)
	if p.size() <= 1:
		return false
	for i in range(p.size() - 1):
		var ok := false
		for e in campaign.world.graph.get(p[i], []):
			if e["to"] == p[i + 1]:
				var k := String(e.get("kind", ""))
				ok = k.begins_with("고속항로") and not ("관문" in k)
				break
		if not ok:
			return false
	return true


static func _is_enclave(data: GameData, campaign: Campaign, rid: String) -> bool:
	var owner := ""
	if campaign.world.region_states.has(rid):
		owner = String(campaign.world.region_states[rid].owner)
	if owner == "":
		return false
	for nb in data.region_adjacency.get(rid, []):
		var ns = campaign.world.region_states.get(nb)
		if ns != null and String(ns.owner) == owner:
			return false
	return true


## 요구 통솔을 충족하는 가장 가까운 하위 진형 (§4.5 하향 사슬).
static func _downgrade(command: int, from_formation: String) -> String:
	var start := DOWNGRADE_CHAIN.find(from_formation)
	if start < 0:
		start = 0
	for i in range(start, DOWNGRADE_CHAIN.size()):
		var f := DOWNGRADE_CHAIN[i]
		if command >= FormationSpec.required_command(f):
			return f
	return "장사진"
