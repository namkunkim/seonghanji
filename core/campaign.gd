class_name Campaign
extends RefCounted

## 시나리오 진행 (scenario-setup.md §4 · endings.md §5.2 · world-state.md §4)
##
## **헤드리스로 끝까지 도는 것이 M0 의 산출물이다** (dev-requirements.md §9).
##
## > 화면 하나 없이 시나리오가 AI 대 AI로 100회 자동 진행되어
## > 세력 승률 분포가 출력되는 것

## 시나리오 3 종료 — ACT 10 완료. 208~211, 3년
const SCN03_END_TICK: int = GameClock.TICKS_PER_YEAR * 3

## 조기 종료 (world-state.md §3.1) — 견제 세력 **전부** 합쳐도 최강자의 1/3 미만
const EARLY_END_DEN: int = 3

## 일극형 임계 (world-state.md §4) — 최강자 ≥ **유효 세력** 나머지 합 × 2.0
const HEGEMON_RATIO: int = 2

## 유효 세력 하한 — 실동원이 전체 합의 10% 이상
const EFFECTIVE_FLOOR_PCT: int = 10


var world: World

## 세력별 인물 로스터. 세력 → Array[Dictionary] (통솔 내림차순)
var roster: Dictionary = {}
var data: GameData
var factions: Dictionary = {}
var faction_ids: Array[String] = []
var fleets: Array[Fleet] = []
var _next_fleet_id: int = 0

## 역사 편향 계수 (ai-design.md §6.2). 기본은 표준 0.25
var hb_milli: int = Strategy.HB_STANDARD_MILLI

## 외교 상태 (diplomacy.md §4.5 · §5)
var diplo: Diplomacy = Diplomacy.new()

## 진단 — 동맹이 실제로 맺어지는가
var alliances_formed: int = 0
var hegemony_peak: int = 0
var stagnation_hits: int = 0

## ---------------------------------------------------------------- 기능 이벤트
## 이벤트 ID → 발동 횟수. **「미발동 0종」 지표의 분모다**
var events_fired: Dictionary = {}
var alliances_broken: int = 0
var backstabs: int = 0
var revolts: int = 0
var refusals: int = 0
var _event_cooldown: Dictionary = {}
var _alliance_since: Dictionary = {}
var hegemony_coalition_ticks: int = 0
var joint_defenses: int = 0

## 진단용 계수. AI 가 왜 안 움직이는지 짚기 위한 것이다.
var skip_no_idle: int = 0
var skip_defense: int = 0
var skip_no_target: int = 0
var skip_threshold: int = 0
var dispatched: int = 0

## 내정 계수 (S2.9)
var months_settled: int = 0
var austerity_events: int = 0        # 재정 파탄 — 복구 중단 · 훈련 해제
## AI 내정 판단 스위치.
##
## ⚠ **켜면 세력 편차가 3.4 → 6.3배로 나빠진다** (2026-08-25 실측).
## 원인은 튜닝이 아니라 구조다 — 상세는 `m0-report.md` §2.4.
## **A/B 를 할 수 있어야 그 구조를 고칠 수 있으므로 스위치로 남긴다.**
var ai_domestic_enabled: bool = true

var cmds_issued: int = 0
var cmds_applied: int = 0
var fleets_built: int = 0
var cmds_rejected: int = 0

var ended: bool = false
var end_reason: String = ""
var battles: int = 0
var captures: int = 0

## ---------------------------------------------------------------- 계략 진단 (§5)
## **계략이 실제로 굴려지는가**를 재는 계수. 성공률만 맞고 시전이 0회면 배선이 아니다.
var schemes_tried: int = 0
var schemes_detected: int = 0
var schemes_failed: int = 0
var schemes_fired: int = 0
var fires_landed: int = 0
## 계략 종류별 성공 횟수. 인덱스는 `Scheme.Kind`
var schemes_by_kind: Array[int] = [0, 0, 0, 0, 0, 0, 0]
## 회랑에서 벌어진 전투 · 그중 매복이 성공한 횟수.
## **「회랑 출구 보정이 매복을 최다로 만든다」가 참인지 재는 자리다** (§5.3).
## +30 → +15 로 낮췄다 (2026-08-28, 검토 14) — `Scheme.TERRAIN_CORRIDOR_EXIT_AMBUSH_MILLI`
var corridor_battles: int = 0
var ambush_in_corridor: int = 0

## **매복이 공격측 쪽으로 기우는가 방어측 쪽으로 기우는가** (combat.md §10 검토 14).
## §5.3 은 지형 보정을 공수 대칭으로 준다 — 코드가 그런데도 결과가 한쪽으로
## 쏠린다면, 원인은 계수가 아니라 「누가 회랑에서 더 자주 싸우는가」일 수 있다.
var ambush_by_attacker: int = 0
var ambush_by_defender: int = 0
## 세력 → 그 세력이 계략을 **당한** 횟수 / **성공시킨** 횟수 (역할 무관)
var schemes_landed_on: Dictionary = {}
var schemes_cast_by: Dictionary = {}
## 세력 → 그 세력이 **공격측으로** 회랑 전투를 치른 횟수
var corridor_battles_as_attacker: Dictionary = {}

## ⚠ **위 순피해는 부호를 거꾸로 읽기 쉽다.** 음수 = 성공시킴이 더 많음 = **그 세력이 이긴다.**
## 지력·참모 품질이 높은 세력(조조·손권)이 음수로 나오는 것이 정상이다 — 처음에 이걸
## 반대로 읽고 「거대 세력이 소세력에게 진다」는 틀린 결론을 냈었다(2026-08-28).
##
## **기각한 가설 둘** — 재현하지 않는다.
##   ① 함대 선택 편향(그 전투에 나간 함대가 세력 평균보다 약한가) — 반박.
##      조조 실측 +1.88(오히려 평균보다 강한 함대가 싸운다)
##   ② 전투 진입 사기(자주 싸우는 세력이 사기가 낮아 계략에 더 잘 맞는가) — 반박.
##      조조 78.7·손권 77.4로 오히려 소세력보다 높다(마등한수 59.1 등)
## 진짜 원인은 **총량이 아니라 공세 국면**이었다 — 아래 `instrument_focus` 참조.

## ---------------------------------------------------------------- 진단 — 공세 국면 매복 피격
##
## §10 검토 14의 원래 가설을 정밀 재측정하기 위한 임시 계측. **총량이 아니라
## 「공격측으로 회랑에 들어갈 때 방어측 매복에 맞는 비율」만 본다.**
## 특정 세력(`instrument_focus`)이 비었으면 아무 것도 세지 않는다 — 기본 100회
## 캠페인 성능에 영향을 주지 않기 위해서다.
var instrument_focus: String = ""
var focus_corridor_attacks: int = 0
var focus_corridor_attacks_ambushed: int = 0
var focus_noncorridor_attacks: int = 0
var focus_noncorridor_attacks_ambushed: int = 0


## ---------------------------------------------------------------- 셋업
## scenario-setup.md §4.1 의 배치를 그대로 싣는다.
static func scenario_03(data_ref: GameData, master_seed: int) -> Campaign:
	var c := Campaign.new()
	c.data = data_ref
	c.world = World.new()
	c.world.rng_seed = master_seed
	c.world.scenario = "SCN-03"
	c.world.attach(data_ref, "")
	c.world.load_war_damage(Power.WAR_DAMAGE_208_MILLI)

	var by_name := {}
	for rid in data_ref.region_ids:
		by_name[data_ref.regions[rid]["name"]] = rid
	var sys_by_name := {}
	for sid in data_ref.system_ids:
		sys_by_name[data_ref.systems[sid]["name"]] = sid

	# 통치 체제 (§3.4-b ④) — 동원율에 직접 걸린다
	var governance := {
		"조조": "중앙집권",        # 위 — 중앙집권 관료제 +0.05
		"손권": "호족연합",        # 오 −0.05
		"유종": "호족연합",        # 유표 −0.05
		"유장": "암약",            # **−0.25. 확장 의사 자체가 없다**
		"마등한수": "군벌연합",    # −0.10
		"장로": "표준",
		"사섭": "표준",
		"공손강": "표준",
	}
	var setup := {
		"조조": ["사예", "패도형",
			["사예", "예주", "연주", "청주", "서주", "기주", "유주", "병주", "남양", "회남"],
			["북부권"]],
		"유종": ["형주", "인덕형", [], ["중부권", "남부권", "태양계권"]],
		"손권": ["오회", "실리형", ["오회"], []],
		"유장": ["익주", "명문형", ["익주"], []],
		"장로": ["한중", "명사형", ["한중"], []],
		"마등한수": ["옹주", "무단형", ["옹주", "양주"], []],
		"사섭": ["교주", "실리형", ["교주"], []],
		"공손강": ["요동", "실리형", ["요동"], []],
	}
	var names: Array = setup.keys()
	names.sort()
	for nm in names:
		var spec: Array = setup[nm]
		var f := Faction.new()
		f.id = nm
		f.name = nm
		f.capital_system = sys_by_name[spec[0]]
		f.lord_type = spec[1]
		f.governance = String(governance.get(nm, "표준"))
		for sname in spec[2]:
			for rid in data_ref.regions_of[sys_by_name[sname]]:
				f.add_region(rid)
		for rname in spec[3]:
			f.add_region(by_name[rname])
		c.factions[nm] = f
		c.faction_ids.append(nm)
		for rid in f.regions:
			c.world.region_states[rid].owner = nm
	c.faction_ids.sort()

	# **신복속 초기 상태** (region-power.md §3.4-c)
	# 조조의 유주2·병주2 는 207년 무력 정복, 북부권은 208년 항복이다.
	# 이것이 없으면 조조의 동원율이 문서(0.34)보다 크게 높게 나온다.
	var recent := {
		"유주": ["정복", -GameClock.TICKS_PER_YEAR],      # 207 — 1년 전
		"병주": ["정복", -GameClock.TICKS_PER_YEAR],
	}
	for sname in recent.keys():
		for rid in data_ref.regions_of[sys_by_name[sname]]:
			var st: RegionState = c.world.region_states[rid]
			st.acquired_by = String(recent[sname][0])
			st.acquired_tick = int(recent[sname][1])
	var buk: RegionState = c.world.region_states[by_name["북부권"]]
	buk.acquired_by = "항복"                              # 208 — 유종의 항복
	buk.acquired_tick = 0

	# **천명** (function-events.md §0.3-① · Mandate.SCN03)
	for fid in c.faction_ids:
		c.factions[fid].mandate = Mandate.scenario_03(fid)
	# **권역 안정도** (function-events.md §0.3-④).
	# 획득 방식이 그 땅의 출발점을 정한다 — 동원율의 신복속 부담과 같은 사고다.
	for rid in data_ref.region_ids:
		var rst: RegionState = c.world.region_states[rid]
		rst.stability_initial = Stability.initial_for(rst.acquired_by)
		rst.stability = rst.stability_initial

	# **인물 로스터** (character-assignments.md · Roster).
	# 2026-08-25 신설 — 그때까지 모든 함대가 통솔 50 으로 싸웠다.
	c.roster = Roster.build(data_ref, "SCN-03")

	# **황제는 조조가 쥐고 있다** — 건안 원년 허 천도 이래. 패권 압력 +10
	c.factions["조조"].has_emperor = true

	# **개전 준비금 — 월 수입 1개월분.**
	# 0 에서 시작하면 첫 달에는 아무것도 할 수 없다. 시나리오가 「적벽 전야」이므로
	# 이미 움직이고 있던 나라들이라고 보는 편이 옳다.
	for fid in c.faction_ids:
		var ff: Faction = c.factions[fid]
		ff.treasury = Economy.faction_income(data_ref, c.world.region_states,
			ff.regions)

	# 실동원에 비례해 함대를 준다 (유지점 = 함선, combat.md §4.3.1)
	for fid in c.faction_ids:
		var f: Faction = c.factions[fid]
		var mob := f.mobilized(data_ref, c.world.region_states, c.world.graph, 0)
		var n := maxi(1, mob / 10)
		for _i in n:
			c._spawn_fleet(fid, f.capital_system)
	return c


func _spawn_fleet(owner: String, at: String) -> Fleet:
	var fl := Fleet.new()
	fl.id = _next_fleet_id
	_next_fleet_id += 1
	fl.owner = owner
	fl.at_system = at
	# **천명이 초기 사기에 들어간다** (combat.md §1.2 · function-events.md §0.3-①).
	# 2026-08-25 배선 — 그 전까지 모든 함대가 명목 100 으로 시작했고,
	# **조조의 황제 보유가 전투에서 아무 값도 하지 않았다.**
	var f: Faction = factions.get(owner)
	if f != null:
		fl.morale = Mandate.initial_morale(f.mandate)
	_assign_commander(fl)
	_assign_staff(fl)
	fleets.append(fl)
	return fl


## 함대에 제독을 앉힌다. **통솔 상위부터, 한 사람은 한 함대만** (§6.4).
##
## 자리가 모자라면 **무명 장교**가 맡고 보정은 0 이다 —
## 임명은 의무가 아니라 자원 배분이다.
func _assign_commander(fl: Fleet) -> void:
	var list: Array = roster.get(fl.owner, [])
	if list.is_empty():
		return
	# **다른 함대의 참모진도 본다.** 부제독·임무대장 3 자리를 빼먹으면
	# 이미 참모로 앉은 사람이 다음 함대의 제독으로 다시 뽑힌다 —
	# `_assign_staff` 가 붙기 전까지는 제독만 있어 드러나지 않던 구멍이다.
	var used := _used_roster_ids(fl.owner)
	for c in list:                               # **통솔 내림차순 · 순서 고정**
		var cid := String(c.get("id", ""))
		if used.has(cid):
			continue
		fl.commander_id = cid
		fl.commander_name = String(c.get("name", ""))
		fl.command = Roster.stat_of(c, "통솔")
		fl.might = Roster.stat_of(c, "무력")
		fl.wits = Roster.stat_of(c, "지력")
		# **매력이 초기 사기에 들어간다** (combat.md §1.2) —
		# 통솔 8 : 매력 7. 유비는 함대를 잘 몰지 못해도 먼저 무너지지 않는다
		var charm := Roster.stat_of(c, "매력")
		fl.morale = clampi(fl.morale
			+ (fl.command - 50) * 8 / 50 + (charm - 50) * 7 / 50,
			0, Battle.MORALE_MAX)
		return


## 이미 어딘가에 앉은 사람 전부 — 제독 + 부제독 + 임무대장 3, 모든 함대를 통틀어.
## **한 사람은 한 자리만 맡는다** (§6.4) — 제독과 참모진이 서로의 자리를 넘보지 않도록
## `_assign_commander` · `_assign_staff` 가 이 하나를 함께 쓴다.
func _used_roster_ids(owner: String) -> Dictionary:
	var used := {}
	for other in fleets:
		if other.owner != owner:
			continue
		for cid in [other.commander_id, other.vice_id, other.assault_id,
				other.siege_id, other.supply_id]:
			if cid != "":
				used[cid] = true
	return used


## 함대 참모진 — 부제독 · 강습대장 · 공성대장 · 보급대장 (ship-specs.md §6.5).
##
## 2026-08-28 신설. **제독 한 사람만 지력을 쥐고 있었다.** `combat.md` §5.3 의
## 「시전측 최고 지력은 함대에 편성된 인물 중 최고값」과 §5.2 의 「참모형 인물이
## 간파 판정을 갖는다」가 지금까지 코드에서 전부 제독으로 대신되고 있었다
## (combat.md §10 검토 16).
##
## **순서가 결정이다.** §6.5 표의 등재 순서(부제독 → 강습 → 공성 → 보급)를
## 그대로 우선순위로 쓴다 — 문서가 그 이상을 정하지 않았고, 표 순서가
## 유일하게 문서에 있는 근거다. 한 사람은 한 자리만 맡는다(§6.4).
func _assign_staff(fl: Fleet) -> void:
	var list: Array = roster.get(fl.owner, [])
	if list.is_empty():
		return
	var used := _used_roster_ids(fl.owner)
	if fl.commander_id != "":                    # fl 자신은 아직 `fleets` 에 없다
		used[fl.commander_id] = true

	var vice := _best_staff(list, used, "통솔")
	if not vice.is_empty():
		used[String(vice["id"])] = true
		fl.vice_id = String(vice["id"])
		fl.vice_command = Roster.stat_of(vice, "통솔")

	var assault := _best_staff(list, used, "무력")
	if not assault.is_empty():
		used[String(assault["id"])] = true
		fl.assault_id = String(assault["id"])
		fl.assault_might = Roster.stat_of(assault, "무력")

	var siege := _best_staff(list, used, "지력")
	if not siege.is_empty():
		used[String(siege["id"])] = true
		fl.siege_id = String(siege["id"])
		fl.siege_wits = Roster.stat_of(siege, "지력")

	var supply := _best_staff(list, used, "정치")
	if not supply.is_empty():
		used[String(supply["id"])] = true
		fl.supply_id = String(supply["id"])
		fl.supply_politics = Roster.stat_of(supply, "정치")

	_refresh_scheme_staff(fl)


## 아직 미배정인 인물 중 그 스탯이 가장 높은 사람. `roster` 는 통솔로만
## 정렬되어 있으므로(§2.3 순회 순서 고정) 다른 스탯은 여기서 훑는다.
## **동률이면 먼저 나온 쪽** — roster 자체가 통솔·ID 순으로 고정되어 있어
## 순회 순서가 결정론을 해치지 않는다.
func _best_staff(list: Array, used: Dictionary, stat: String) -> Dictionary:
	var best := {}
	var best_val := -1
	for c in list:
		var cid := String(c.get("id", ""))
		if used.has(cid):
			continue
		var v := Roster.stat_of(c, stat)
		if v > best_val:
			best_val = v
			best = c
	return best


## 계략이 실제로 참고하는 값을 갱신한다 (combat.md §5.3 · §5.4).
## 임명이 하나 바뀔 때마다(제독·참모진 모두) 다시 부른다.
func _refresh_scheme_staff(fl: Fleet) -> void:
	var wits_max := fl.wits
	var trait_union: Array = []
	var det_wits := 0
	var det_name := ""
	var det_traits: Array = []
	var wits80 := 0
	for cid in [fl.commander_id, fl.vice_id, fl.assault_id, fl.siege_id, fl.supply_id]:
		if cid == "":
			continue
		var c := _roster_char(fl.owner, cid)
		if c.is_empty():
			continue
		var w := Roster.stat_of(c, "지력")
		wits_max = maxi(wits_max, w)
		var t = c.get("traits")
		if t is Array:
			for tr in t:
				if not trait_union.has(tr):
					trait_union.append(tr)
		var classes = c.get("class")
		var is_staff: bool = classes is Array and classes.has("참")
		# **참모형만 간파 판정을 갖는다** (§5.2). 동률이면 먼저 훑은 자리
		# (제독 → 부제독 → 강습 → 공성 → 보급) 가 이긴다 — 순서 고정
		if is_staff and w > det_wits:
			det_wits = w
			det_name = String(c.get("name", ""))
			det_traits = (t if t is Array else [])
		if is_staff and w >= 80:                    # §5.3 「지력 80 이상 참모형 동승」
			wits80 += 1
	fl.staff_wits_max = wits_max
	fl.staff_traits = trait_union
	fl.detector_wits = det_wits
	fl.detector_name = det_name
	fl.detector_traits = det_traits
	fl.staff_wits80_count = wits80


## ---------------------------------------------------------------- 진행
## 한 틱. **호출 순서가 규칙이다.**
func step() -> void:
	if ended:
		return
	world.clock.step_ticks(1)
	Sim._advance_one_tick(world)
	_apply_arrived()          # ①-b 도달한 명령에 효과를 붙인다 (S2.9)
	_settle_month()           # ②-b 월 정산 — 자금·행정비·유지비 (S2.9)
	_arrive_fleets()
	if world.clock.tick % Strategy.GRAND_PERIOD_TICKS == 0:
		_ai_grand()
	if world.clock.tick % Strategy.OPERATIONAL_PERIOD_TICKS == 0:
		_ai_operational()
	_check_events()           # ⑥ 이벤트 판정 (function-events.md)
	_check_end()


## 실시간 진행 — **클라이언트가 부르는 입구다** (S3.2).
##
## 코어는 시계의 출처를 모른다 (`core/README.md`) —
## 단기는 게임 루프 델타로, 장기는 서버 벽시계로 **같은 함수를 부른다.**
## 그것이 C1~C3 에서 코어를 다시 짜지 않는 유일한 조건이다.
##
## 진행한 틱 수를 돌려준다.
func advance(elapsed_ms: int) -> int:
	if ended:
		return 0
	var n := world.clock.take_ticks(elapsed_ms)
	for _i in n:
		step()
		if ended:
			break
	return n


func run_to_end(max_ticks: int = SCN03_END_TICK) -> void:
	while not ended and world.clock.tick < max_ticks:
		step()
	if not ended:
		ended = true
		end_reason = "정규 종료"


## ---------------------------------------------------------------- 내정 (S2.9)
##
## `Sim._deliver_commands` 는 명령을 옮기기만 한다 — 세력을 모르기 때문이다.
## 여기서 **효과가 붙는다.**
func _apply_arrived() -> void:
	for c in world.last_arrived:
		var fid := String(c.get("payload", {}).get("faction", ""))
		var f: Faction = factions.get(fid)
		if f == null or not f.alive:
			cmds_rejected += 1
			continue
		# **건조만 여기서 처리한다** — 함대 생성은 Campaign 의 몫이다
		if String(c.get("kind", "")) == Domestic.CMD_BUILD:
			if _build_fleet(f):
				cmds_applied += 1
			else:
				cmds_rejected += 1
			continue
		var why := Domestic.apply(data, world.region_states, f, fleets, c,
			world.clock.tick)
		if why == "":
			cmds_applied += 1
		else:
			cmds_rejected += 1


## 월 정산. **연 정산(전화 회복) 옆에 선다** (domestic.md §7 ①).
##
## 「기간」이 게임 내 1개월이라는 확정(§4.0)이 여기서 코드가 된다 —
## 전열함 한 전대를 한 달에 짓고 그 비용이 국력 1 의 한 달 수입과 같다.
func _settle_month() -> void:
	if world.clock.tick == 0:
		return
	if world.clock.tick % Economy.SETTLE_PERIOD_TICKS != 0:
		return
	months_settled += 1
	for fid in faction_ids:                      # **정렬된 배열로만 순회한다**
		var f: Faction = factions[fid]
		if not f.alive:
			continue
		var inc := Economy.faction_income(data, world.region_states, f.regions)
		var adm := Economy.faction_admin(data, world.region_states, f.regions,
			f.governance)
		var flt := 0
		var drl := 0
		for fl in fleets:
			if fl.owner != fid or not fl.is_alive():
				continue
			flt += Economy.fleet_upkeep(fl.squadrons_milli(), fl.plan, fl.station)
			drl += Domestic.drill_cost(fl)
			Domestic.drill_tick(fl)
		var rec := Domestic.recover_cost_total(data, world.region_states, f.regions)
		var spare := inc - adm - flt - drl - rec
		f.treasury += spare
		if f.treasury < 0:
			_austerity(f)
		Domestic.tech_tick(f, world.clock.tick)

		# **권역 안정도** — 평시 회복 또는 감쇠 (§0.3-④)
		#
		# **[F-13] 비지는 사건이 아니라 상태다.** 2026-08-25 정정 —
		# 처음에 이벤트 발동 시 한 번만 −8 을 주었더니 안정도가 30 아래로
		# 내려가는 권역이 하나도 없었고, **[F-39] 후방 반란이 영영 안 터졌다.**
		# 고립되어 있는 동안 매월 깎여야 한다.
		for rid in f.regions:
			var rst: RegionState = world.region_states.get(rid)
			if rst == null:
				continue
			var enclave := true
			for nb in data.region_adjacency.get(rid, []):
				if f.regions.has(nb):
					enclave = false
					break
			Stability.tick(rst, enclave)

		# **할거 페널티** (§0.3-⑤) — 12개월 무획득이면 천명이 깎인다.
		#
		# 「가만히 있으면 진다」가 여기서 처음 코드가 된다.
		# 그전까지 웅크린 소국은 **아무 대가 없이** 존속했다 —
		# 유장·장로·사섭의 달성률 98~100% 가 그 결과였다.
		f.months_idle += 1
		var md := Stability.stagnation_mandate_delta(f.months_idle,
			f.regions.size(), f.wandering)
		if md != 0:
			f.mandate = clampi(f.mandate + md, Mandate.MIN, Mandate.MAX)
			stagnation_hits += 1

		_ai_domestic(f, spare)


## AI 내정 판단 (domestic.md §7 ⑦ · ai-design.md).
##
## **명령은 사자를 태워 보낸다.** AI 도 지연을 문다 —
## 플레이어만 늦는 것이 아니어야 「직할이 느리다」가 대칭이 된다 (§3).
func _ai_domestic(f: Faction, spare: int) -> void:
	if not ai_domestic_enabled:
		return
	if f.id == world.player_faction:
		return                                   # 플레이어 세력은 스스로 정한다

	# 훈련은 지속형이라 한 번만 켜면 된다. **전대장이 없으면 40 에서 멈춘다**
	for fl in fleets:
		if fl.owner == f.id and fl.is_alive() and not fl.drilling:
			if fl.drill < fl.drill_cap() and spare > Domestic.DRILL_COST_PER_SQUADRON * 5:
				fl.drilling = true

	var mob := f.mobilized(data, world.region_states, world.graph, world.clock.tick)
	var cap := Economy.squadrons_milli(mob, f.plan)
	var plan := Strategy.domestic_plan(data, world.region_states, f, fleets,
		spare, cap, world.clock.tick)
	if plan.is_empty():
		return
	var payload: Dictionary = plan["payload"]
	payload["faction"] = f.id
	var kind := String(plan["kind"])
	# **세력 명령은 즉시, 권역 명령은 사자 지연.**
	# 기술은 나라의 것이고 위임은 권한을 넘기는 선언이라 도달을 기다리지 않는다.
	if kind == Domestic.CMD_TECH or kind == Domestic.CMD_BUILD:
		world.issue(kind, payload, 0)
	elif payload.has("region"):
		world.capital = f.capital_system
		if world.issue_to(kind, String(payload["region"]), payload).is_empty():
			cmds_rejected += 1                   # 회랑이 끊겨 명령이 가지 못했다
	else:
		world.issue(kind, payload, 0)
	cmds_issued += 1


## 건조 — 실동원 상한 안에서 함대를 하나 세운다.
func _build_fleet(f: Faction) -> bool:
	var mob := f.mobilized(data, world.region_states, world.graph, world.clock.tick)
	var cap := Economy.squadrons_milli(mob, f.plan)
	var have := 0
	for fl in fleets:
		if fl.owner == f.id and fl.is_alive():
			have += fl.squadrons_milli()
	var one := Battle.FLEET_SHIPS * 1000 / Battle.SQUADRON_SHIPS
	if have + one > cap:
		return false                             # **실동원이 상한이다**
	# 건조비 — 균형 편성 5전대분 (combat.md §4.3.2)
	var cost := Economy.plan_upkeep_milli(f.plan) * 5 * 10 / 1000
	if f.treasury < cost:
		return false
	f.treasury -= cost
	_spawn_fleet(f.id, f.capital_system)
	fleets_built += 1
	return true


## 재정 파탄. **적자는 그냥 넘어가지 않는다.**
##
## 복구 투자를 끊고 훈련을 해제한다 — 둘 다 월정액이므로 즉시 지출이 멎는다.
## 함대 유지비와 행정비는 끊을 수 없다. **가진 것에 붙는 비용은 안 낼 수가 없다.**
func _austerity(f: Faction) -> void:
	austerity_events += 1
	for rid in f.regions:
		var st: RegionState = world.region_states.get(rid)
		if st != null:
			st.recovery_investment = 0
	for fl in fleets:
		if fl.owner == f.id:
			fl.drilling = false
	f.treasury = 0


## 세력의 이번 달 수지. [수입, 행정비, 함대비, 훈련비, 복구비, 잔여]
func budget(fid: String) -> Array:
	var f: Faction = factions[fid]
	var inc := Economy.faction_income(data, world.region_states, f.regions)
	var adm := Economy.faction_admin(data, world.region_states, f.regions,
		f.governance)
	var flt := 0
	var drl := 0
	for fl in fleets:
		if fl.owner != fid or not fl.is_alive():
			continue
		flt += Economy.fleet_upkeep(fl.squadrons_milli(), fl.plan, fl.station)
		drl += Domestic.drill_cost(fl)
	var rec := Domestic.recover_cost_total(data, world.region_states, f.regions)
	return [inc, adm, flt, drl, rec, inc - adm - flt - drl - rec]


func _arrive_fleets() -> void:
	var now := world.clock.tick
	var arrived: Array[Fleet] = []
	for fl in fleets:
		if fl.is_moving() and fl.arrival_tick <= now and fl.is_alive():
			arrived.append(fl)
	arrived.sort_custom(func(a, b): return a.id < b.id)
	for fl in arrived:
		var rid := fl.target_region
		fl.arrival_tick = -1
		fl.at_system = data.system_of(rid)
		fl.target_region = ""
		var st: RegionState = world.region_states[rid]
		if st.owner == fl.owner or st.owner == "":
			_capture(fl.owner, rid)
		else:
			_resolve_battle(fl, rid)


## 5페이즈 전투 (combat.md §2). 방어측은 그 성계의 주둔 함대 합.
func _resolve_battle(att: Fleet, rid: String) -> void:
	battles += 1
	var st: RegionState = world.region_states[rid]
	var defender: String = st.owner
	var corridor := _corridor_scale(rid)
	var rng := world.rng(Rng.DOMAIN_COMBAT)

	# **참전 의무** (diplomacy.md §5.1) — 군사동맹국이 침공받으면 함께 싸운다.
	# **적벽에서 손유 동맹이 조조를 막는 것이 이 규칙이다.**
	var defs: Array[Fleet] = []
	var joined := false
	for fl in fleets:
		if not fl.is_alive() or fl.is_moving():
			continue
		if fl.at_system != data.system_of(rid):
			continue
		if fl.owner == defender:
			defs.append(fl)
		elif fl.owner != att.owner and diplo.has_duty(fl.owner, defender):
			defs.append(fl)
			joined = true
	defs.sort_custom(func(a, b): return a.id < b.id)
	if joined:
		joint_defenses += 1

	var def_ships := 0
	for fl in defs:
		def_ships += fl.ships
	if def_ships <= 0:
		_capture(att.owner, rid)
		return

	var def_morale: int = defs[0].morale
	var def_command: int = defs[0].command
	var def_drill: int = defs[0].drill

	# ---------------------------------------------------------------- 기술
	#
	# **화력과 방어는 서로를 뺀다** (combat.md §1.4-c · V-34).
	# 2026-08-25 배선. 그 전까지 `Tech.power_milli` 는 산식만 있고
	# **전투에서 한 번도 불리지 않았다** — AI 가 기술에 쓴 돈이 전부 낭비였다.
	var af: Faction = factions.get(att.owner)
	var df: Faction = factions.get(defs[0].owner)
	var a_tech := 1000
	var b_tech := 1000
	if af != null and df != null:
		a_tech = Tech.power_milli(int(af.tech.get("화력", 0)),
			int(df.tech.get("방어", 0)))
		b_tech = Tech.power_milli(int(df.tech.get("화력", 0)),
			int(af.tech.get("방어", 0)))

	# ---------------------------------------------------------------- 계략
	#
	# **문서에 있는데 코드가 안 읽는다** — 일곱 번째다 (`core/combat/scheme.gd`).
	# `combat.md` §5 는 2026-08-23 에 산식을 전부 확정했고,
	# 2026-08-28 까지 코어에 계략이 한 줄도 없었다.
	var sa := _scheme_side(att)
	var sb := _scheme_side(defs[0])
	var ew_pct: int = int(Economy.PLANS.get(att.plan,
		Economy.PLANS[Economy.PLAN_DEFAULT])[3])
	if corridor != "":
		corridor_battles += 1
		corridor_battles_as_attacker[att.owner] = \
			int(corridor_battles_as_attacker.get(att.owner, 0)) + 1
	if att.owner == instrument_focus and instrument_focus != "":
		if corridor != "":
			focus_corridor_attacks += 1
		else:
			focus_noncorridor_attacks += 1

	for phase in 5:
		# 매복이 연 것은 **다음 페이즈**의 손실이다 (§5.5 「적 ② 손실률 ×1.5」).
		# 걸어 둔 배수를 페이즈 머리에서 회수한다 — 같은 페이즈에 터지면 매복이 아니다.
		var a_mult: int = int(sa["next_loss_mult"])
		var b_mult: int = int(sb["next_loss_mult"])
		sa["next_loss_mult"] = 1000
		sb["next_loss_mult"] = 1000

		# **공격측 → 방어측 순서를 고정한다** (V-31). 각 호출이 정확히 3회 소비한다.
		var ra := _run_scheme(rng, phase, sa, sb, def_morale, ew_pct, corridor)
		var rb := _run_scheme(rng, phase, sb, sa, att.morale, ew_pct, corridor)

		# **역할별 · 세력별 진단** (§10 검토 14) — 매복 편중이 어느 쪽에서 오는지
		if int(ra["kind"]) == Scheme.Kind.AMBUSH:
			ambush_by_attacker += 1
		if int(rb["kind"]) == Scheme.Kind.AMBUSH:
			ambush_by_defender += 1
		if int(ra["kind"]) >= 0:
			schemes_cast_by[att.owner] = int(schemes_cast_by.get(att.owner, 0)) + 1
			schemes_landed_on[defender] = int(schemes_landed_on.get(defender, 0)) + 1
		if int(rb["kind"]) >= 0:
			schemes_cast_by[defender] = int(schemes_cast_by.get(defender, 0)) + 1
			schemes_landed_on[att.owner] = int(schemes_landed_on.get(att.owner, 0)) + 1
			if att.owner == instrument_focus and instrument_focus != "" \
					and int(rb["kind"]) == Scheme.Kind.AMBUSH:
				if corridor != "":
					focus_corridor_attacks_ambushed += 1
				else:
					focus_noncorridor_attacks_ambushed += 1

		# 이간 — **보정의 60% 가 사라지는 것이지 스탯이 사라지는 것이 아니다** (§5.5)
		var a_stat: int = (Scheme.discorded_stat(att.command)
			if int(sa["discord"]) > 0 else att.command)
		var b_stat: int = (Scheme.discorded_stat(def_command)
			if int(sb["discord"]) > 0 else def_command)
		# 유인 — 끌어낸 쪽이 회랑 전개 상한을 벗어난다 (§5.5)
		var a_corr: String = "" if bool(sa["free_terrain"]) else corridor
		var b_corr: String = "" if bool(sb["free_terrain"]) else corridor

		var pa := Battle.combat_power_milli(att.ships, 1000, a_stat, phase,
			att.morale, 1000, a_tech, a_corr)
		var pb := Battle.combat_power_milli(def_ships, 1000, b_stat, phase,
			def_morale, 1000, b_tech, b_corr)

		# 계략의 손실은 **그 페이즈 손실률에 얹힌다** — 그리고 그 손실이 다시
		# 사기를 깎는다 (§1.3 Δ = −[L×k + D + E]). `verify_chibi.gd` 와 같은 셈이다.
		var la := (Battle.loss_rate_milli(phase, pa, pb) * a_mult / 1000
			+ int(rb["loss_milli"]))
		var lb := (Battle.loss_rate_milli(phase, pb, pa) * b_mult / 1000
			+ int(ra["loss_milli"]))

		# E 사건 가산 — 피격분과 시전 실패분. **연계는 중첩하지 않는다** (§1.3)
		var ea := Scheme.linked_event_milli(int(rb["event"]), int(ra["self_event"]))
		var eb := Scheme.linked_event_milli(int(ra["event"]), int(rb["self_event"]))

		att.ships = maxi(0, att.ships - att.ships * la / 100000)
		def_ships = maxi(0, def_ships - def_ships * lb / 100000)
		att.morale = maxi(0, att.morale - (la * Battle.MORALE_K_MILLI[phase] / 1000
			+ Battle.pressure_milli(pa, pb) + ea) / 1000)
		def_morale = maxi(0, def_morale - (lb * Battle.MORALE_K_MILLI[phase] / 1000
			+ Battle.pressure_milli(pb, pa) + eb) / 1000)
		sa["discord"] = maxi(0, int(sa["discord"]) - 1)
		sb["discord"] = maxi(0, int(sb["discord"]) - 1)
		# 붕괴 — **패주가 정상적인 지는 방식이다** (§1)
		#
		# **훈련도가 여기 걸린다** (§1.4-b). 2026-08-25 배선 —
		# 그 전까지 기본값 50 이 들어가 훈련이 아무 효과도 없었다.
		if rng.chance(Battle.collapse_chance_pct(att.morale, att.command, att.drill)):
			_retreat(att)
			_apply_losses(defs, def_ships, def_morale)
			return
		if rng.chance(Battle.collapse_chance_pct(def_morale, def_command, def_drill)):
			_apply_losses(defs, 0, def_morale)
			_capture(att.owner, rid)
			return
		if att.ships <= 0 or def_ships <= 0:
			break

	_apply_losses(defs, def_ships, def_morale)
	if def_ships <= 0 and att.ships > 0:
		_capture(att.owner, rid)
	elif att.ships <= 0:
		fleets.erase(att)


## ---------------------------------------------------------------- 계략 (combat.md §5)
##
## 한 측의 전투 1건 동안의 계략 상태.
##
## **함대 참모진 전원이 반영된다** (`ship-specs.md` §6.5 · 2026-08-28 배선).
## §5.3 의 「시전측 최고 지력」은 제독·부제독·임무대장 3 중 최고값(`staff_wits_max`),
## §5.4 의 「간파측 최고 지력」은 그중 **참모형뿐**이다(`detector_wits` · §5.2) —
## 없으면 이 함대는 이번 전투에서 아무 계략도 간파하지 못한다.
##
## 적벽이 그 구분을 정확히 보여준다 — §5.7 은 간파를 조조(91)가 아니라
## **정욱(89, 참모형)** 으로 굴렸다. `tests/verify_chibi.gd` 는 §5.7 대로
## 정욱을 넣어 별도로 굴린다 — 그 시나리오는 참모 편성 이전의 손 계산이라
## 이 함수와는 독립이다.
func _scheme_side(fl: Fleet) -> Dictionary:
	var c := _roster_char(fl.owner, fl.commander_id)
	var d = c.get("disposition")
	return {
		"wits": fl.staff_wits_max,
		"name": fl.commander_name,          # 성향은 여전히 제독(입안자) 것 — §5.6
		"might": fl.might,
		"traits": fl.staff_traits,          # 누가 타고 있든 특성은 산다 — 실행자 ≠ 입안자
		"detect_wits": fl.detector_wits,
		"detect_name": fl.detector_name,
		"detect_traits": fl.detector_traits,
		"staff80": fl.staff_wits80_count,
		"disposition": (String(d) if d != null else ""),
		"attempts": Scheme.attempts_allowed(fl.staff_wits80_count),
		"detects": Scheme.DETECTS_PER_PERSON,
		"linked": 0,                 # 위장 항복이 열어 둔 다음 계략 보정 (§5.5)
		"discord": 0,                # 자기가 이간에 걸린 잔여 페이즈
		"free_terrain": false,       # 유인에 성공해 지형을 벗어났는가
		"next_loss_mult": 1000,      # 매복이 다음 페이즈에 얹는 배수
	}


func _roster_char(owner: String, cid: String) -> Dictionary:
	if cid == "":
		return {}
	for c in roster.get(owner, []):
		if String(c.get("id", "")) == cid:
			return c
	return {}


## 지형 보정 (§5.3). 캠페인이 아는 지형은 회랑뿐이다 —
## **기저 항로와 밀집 진형은 전장 모델이 아직 갖고 있지 않다.**
static func _scheme_terrain_milli(kind: int, corridor: String) -> int:
	if corridor == "":
		return 0
	if kind == Scheme.Kind.AMBUSH:
		return Scheme.TERRAIN_CORRIDOR_EXIT_AMBUSH_MILLI
	return 0


## 한 측의 한 페이즈 계략. **난수를 정확히 3회 소비한다** (V-31 · §2.3 ③).
##
## 시전하지 않든, 간파당하든, 실패하든 소비량이 같다.
## 그래야 계략을 한 줄 고쳤을 때 **그 뒤의 붕괴 판정이 어긋나지 않는다** —
## 셋을 먼저 뽑고 나서 가지를 친다.
func _run_scheme(rng: RngStream, phase: int, me: Dictionary, foe: Dictionary,
		foe_morale: int, ew_pct: int, corridor: String) -> Dictionary:
	var cands: Array[int] = []
	var weights: Array[int] = []
	var total := 0
	for k in Scheme.CAMPAIGN_ENABLED:
		if not Scheme.allows_phase(k, phase):
			continue
		# **위장 항복은 황개「고육계」 전용이다** (§5.1) — 전 게임 유일
		if k == Scheme.Kind.FALSE_SURRENDER \
				and not Scheme.has_trait(me["traits"], Scheme.TRAIT_GOYUK):
			continue
		var terr := _scheme_terrain_milli(k, corridor)
		var met := terr > 0 or Scheme.trait_bonus_milli(k, phase, me["traits"]) > 0
		# **가산 뒤 곱셈** (ai-design.md §7.4). 뒤집으면 조건 없는 계략에 성향이 걸린다
		var w := Scheme.selection_weight_milli(met, String(me["disposition"]))
		cands.append(k)
		weights.append(w)
		total += w

	var pick := rng.below(maxi(total, 1))          # 소비 ① 선택
	var detect_roll := rng.below(100000)           # 소비 ② 간파
	var success_roll := rng.below(100000)          # 소비 ③ 성공

	var out := {"kind": -1, "loss_milli": 0, "event": 0, "self_event": 0}
	if cands.is_empty() or int(me["attempts"]) <= 0:
		return out
	me["attempts"] = int(me["attempts"]) - 1
	schemes_tried += 1

	var kind: int = cands[cands.size() - 1]
	var acc := 0
	for i in cands.size():
		acc += weights[i]
		if pick < acc:
			kind = cands[i]
			break

	# **간파를 먼저 굴린다** (§5.4). 통과해야 성공률 판정으로 간다.
	# **참모형이 없으면 이 함대는 애초에 간파할 수 없다** (§5.2) — `detect_wits` 가 0 이면
	# 판정 자체를 걸지 않는다. 난수 소비는 이미 앞에서 고정 3회로 끝났다(V-31).
	if int(foe["detects"]) > 0 and int(foe["detect_wits"]) > 0:
		var dc := Scheme.detect_chance_milli(int(foe["detect_wits"]), int(me["wits"]),
			foe["detect_traits"], String(foe["detect_name"]))
		if detect_roll < dc:
			foe["detects"] = int(foe["detects"]) - 1
			out["self_event"] = Scheme.EVENT_DETECTED   # 계략 무효 + 시전 측 −15
			schemes_detected += 1
			return out

	var sc := Scheme.success_chance_milli(kind, phase, int(me["wits"]),
		int(foe["wits"]), foe_morale, ew_pct,
		_scheme_terrain_milli(kind, corridor), me["traits"], int(me["staff80"]), false,
		int(me["linked"]))
	me["linked"] = 0
	if success_roll >= sc:
		out["self_event"] = Scheme.EVENT_FAILED         # 단순 실패 −5
		schemes_failed += 1
		return out

	out["kind"] = kind
	out["event"] = Scheme.EFFECT_EVENT[kind]
	schemes_fired += 1
	schemes_by_kind[kind] += 1
	match kind:
		Scheme.Kind.FIRE:
			out["loss_milli"] = (Scheme.EFFECT_LOSS_MILLI[kind]
				* Scheme.fire_damage_milli(false, corridor != "") / 1000)
			fires_landed += 1
		Scheme.Kind.AMBUSH:
			if corridor != "":
				ambush_in_corridor += 1
			out["loss_milli"] = Scheme.EFFECT_LOSS_MILLI[kind]
			foe["next_loss_mult"] = Scheme.AMBUSH_NEXT_LOSS_MILLI
		Scheme.Kind.DISCORD:
			foe["discord"] = Scheme.DISCORD_PHASES
		Scheme.Kind.FALSE_SURRENDER:
			me["linked"] = Scheme.LINKED_MILLI          # 이어지는 계략 +20
		Scheme.Kind.LURE:
			me["free_terrain"] = true
	return out


func _apply_losses(defs: Array[Fleet], remaining: int, morale: int) -> void:
	var left := remaining
	for fl in defs:
		fl.morale = morale
		var take := mini(fl.ships, left)
		fl.ships = take
		left -= take
	for i in range(fleets.size() - 1, -1, -1):
		if not fleets[i].is_alive():
			fleets.remove_at(i)


func _retreat(fl: Fleet) -> void:
	var f: Faction = factions.get(fl.owner)
	if f != null:
		fl.at_system = f.capital_system
	fl.morale = maxi(fl.morale, 40)


func _capture(owner: String, rid: String) -> void:
	var st: RegionState = world.region_states[rid]
	if st.owner == owner:
		return
	captures += 1
	# **참전 거부** (diplomacy.md §5.1 · Diplomacy.TRUST_REFUSE_CALL).
	#
	# 동맹국이 권역을 잃었다는 것은 **도우러 가지 않았다**는 뜻이다.
	# 2026-08-25 신설 — 그때까지 **신뢰도가 내려가는 경로가 하나도 없었고**,
	# 그래서 [F-12] 배후 기습이 100회 캠페인에서 한 번도 안 터졌다.
	# 「등 뒤가 위험해진다」가 성립하려면 등을 돌릴 이유가 먼저 있어야 한다.
	if st.owner != "" and factions.has(st.owner):
		for k in faction_ids:
			if k == st.owner or not diplo.is_allied(st.owner, k):
				continue
			diplo.adjust_trust(st.owner, k, Diplomacy.TRUST_REFUSE_CALL)
			refusals += 1
	if st.owner != "" and factions.has(st.owner):
		factions[st.owner].remove_region(rid)
	st.owner = owner
	st.acquired_tick = world.clock.tick
	st.acquired_by = "정복"
	# **무력 정복은 안정도 40 에서 다시 시작한다** (§0.3-④)
	st.stability_initial = Stability.INIT_CONQUEST
	st.stability = Stability.INIT_CONQUEST
	if factions.has(owner):
		factions[owner].add_region(rid)
		# **할거 시계를 되돌린다** (§0.3-⑤).
		# §4.6 원문대로 **공세 개시에서 멈추지만**, 여기서는 획득으로 잡는다 —
		# 출격 시점에 멈추면 「보내 놓고 가만히 있기」가 최적해가 된다.
		factions[owner].months_idle = 0


func _corridor_scale(rid: String) -> String:
	for h in data.regions[rid].get("routes_hosted", []):
		for cid in data.corridor_ids:
			if data.corridors[cid]["name"] == h:
				return String(data.corridors[cid]["scale"])
	return ""


## ---------------------------------------------------------------- 외교 AI
##
## §8.1 — 각 AI 세력은 **매 Grand 주기마다** 전 세력의 패권 압력을 평가한다.
## 위협도 2.0 을 넘으면 **견제 연합 결성 시도**(F-07).
##
## **손유 동맹이 여기서 성립한다.** 조조 실동원 101 대 손권 35 = 2.9배 —
## 「동맹이 유일한 활로」가 수치로 성립하는 지점이다.
func _ai_grand() -> void:
	var mobs := mobilized_all()
	_update_hegemony(mobs)
	for i in faction_ids.size():
		for j in range(i + 1, faction_ids.size()):
			var a: String = faction_ids[i]
			var b: String = faction_ids[j]
			if not factions[a].alive or not factions[b].alive:
				continue
			if diplo.tier_of(a, b) >= Diplomacy.Tier.군사동맹:
				continue
			# **같은 상대**를 위협으로 보고, **그 상대와 실제로 접해 있어야** 한다.
			# 위협을 느끼기만 해서는 손잡을 이유가 없다 — 요동과 교주가
			# 조조를 두려워한다고 서로 동맹하지는 않는다 (2026-08-25 실측:
			# 조건이 느슨하면 7세력이 전원 동맹을 맺는다).
			var pa := _worst_threat_pair(a, mobs, b)
			var pb := _worst_threat_pair(b, mobs, a)
			if pa[0] == "" or pa[0] != pb[0]:
				continue
			if not _factions_adjacent(a, pa[0]) or not _factions_adjacent(b, pa[0]):
				continue
			# **[F-07] 견제 연합** — 공통 위협의 패권 압력이 50 을 넘으면
			# 위협 임계를 면제한다 (function-events.md §0.3-②).
			#
			# 「강해지면 곧바로 포위된다」가 여기서 성립한다 —
			# 그전까지는 **조조가 아무리 커져도 아무 반작용이 없었다.**
			var threat_f: Faction = factions.get(pa[0])
			var coalition := threat_f != null 				and Hegemony.opens_coalition(threat_f.hegemony)
			# **서로 인접해야 한다.** 군사동맹의 알맹이는 참전 의무(§5.1)이고,
			# 참전하려면 함대가 닿아야 한다. 요동과 교주가 맺는 동맹은 종이다.
			# **손유 동맹이 정확히 이 조건을 만족한다** — 오회와 형주는
			# 장강 대항로로 이어져 있다.
			if not _factions_adjacent(a, b):
				continue
			if coalition or diplo.accepts(a, b, int(pa[1]), int(pb[1])):
				var before := diplo.tier_of(a, b)
				var after := diplo.escalate(a, b)
				if after > before and after == Diplomacy.Tier.군사동맹:
					alliances_formed += 1
					_alliance_since[Diplomacy.key(a, b)] = world.clock.tick


## 패권 압력 갱신 (function-events.md §0.3-②).
## **매 Grand 주기마다 전 세력에 대해 산출한다** (ai-design.md §8.1).
##
## ⚠ 우위 가산 넷 중 **둘만 구현했다** — 황제 보유와 영토 점유율.
## 「인재 밀도 1위」는 인물 배치가 코어에 없고(character-assignments 미적재),
## 「외교 영향력」은 이역 세력이 미구현이다.
func _update_hegemony(mobs: Dictionary) -> void:
	var land := {}
	for fid in faction_ids:
		land[fid] = factions[fid].regions.size()
	for fid in faction_ids:                      # **정렬된 배열로만 순회한다**
		var f: Faction = factions[fid]
		if not f.alive:
			f.hegemony = 0
			continue
		var bonuses := {
			"황제": f.has_emperor,
			"영토": Hegemony.land_lead(land, mobs, fid),
		}
		f.hegemony = Hegemony.pressure(mobs, fid, bonuses, f.violations)
		if f.hegemony > hegemony_peak:
			hegemony_peak = f.hegemony
		if Hegemony.opens_coalition(f.hegemony):
			hegemony_coalition_ticks += 1


## 그 세력이 느끼는 **최대 위협의 상대와 그 값**. 동맹 후보(ally)는 세지 않는다.
## 「누가 가장 무서운가」를 알아야 **같은 상대를 두려워하는지** 판정할 수 있다.
func _worst_threat_pair(fid: String, mobs: Dictionary, ally: String) -> Array:
	var own: int = mobs[fid]
	var worst := 0
	var who := ""
	for other in faction_ids:
		if other == fid or other == ally:
			continue
		if not factions[other].alive or diplo.is_allied(fid, other):
			continue
		var t := Diplomacy.threat_milli(own, int(mobs[other]),
			_factions_adjacent(fid, other))
		if t > worst:
			worst = t
			who = other
	return [who, worst]


func _factions_adjacent(a: String, b: String) -> bool:
	var fb: Faction = factions[b]
	for rid in factions[a].regions:
		for nb in data.region_adjacency.get(rid, []):
			if fb.regions.has(nb):
				return true
	return false


## ---------------------------------------------------------------- AI
## **AI 도 플레이어와 같은 규칙을 쓴다** (ai-design.md §1.3 치팅 금지).
func _ai_operational() -> void:
	for fid in faction_ids:
		var f: Faction = factions[fid]
		if not f.alive:
			continue
		var idle: Array[Fleet] = []
		for fl in fleets:
			if fl.owner == fid and fl.is_alive() and not fl.is_moving():
				idle.append(fl)
		if idle.is_empty():
			skip_no_idle += 1
			continue
		idle.sort_custom(func(a, b): return a.id < b.id)

		var targets: Array = []
		for rid in f.regions:
			for nb in data.region_adjacency.get(rid, []):
				var st: RegionState = world.region_states[nb]
				# **동맹국은 치지 않는다.** 배신 판정(§5.2)은 미구현이다
				if st.owner != "" and diplo.is_allied(fid, st.owner):
					continue
				if st.owner != fid and not targets.has(nb):
					targets.append(nb)
		if targets.is_empty():
			skip_no_target += 1
			continue
		targets.sort()

		# 적 세력마다 절단점을 구한다 — §5.2
		var cuts := {}
		for oid in faction_ids:
			if oid == fid:
				continue
			var of: Faction = factions[oid]
			if of.alive:
				cuts.merge(Strategy.cut_values(data, of.regions))

		# **자기 방어를 먼저 뗀다** (ai-design.md §5.4).
		# 자기 절단점을 지킬 함대를 남기지 않으면 본진이 빈다 —
		# 손권이 적벽 전에 소멸하던 원인이 이것이었다 (2026-08-25).
		# §5.4 는 「**소수** 배치」라 했다. 절단점마다 함대를 묶으면
		# 전부 방어에 붙어 아무도 공격하지 않는다 — 2026-08-25 실측: 전투 0회.
		# **절반을 넘지 않게 자른다.**
		var need := mini(Strategy.defense_need(data, f.regions), idle.size() / 2)
		if idle.size() <= need:
			skip_defense += 1
			continue

		var ranked := Strategy.rank_targets(data, targets, f.regions, cuts)
		if ranked.is_empty():
			continue
		# **결단 임계** (§4.1) — 선택지가 비슷하면 결정하지 못한다.
		# 명문형(원소·유장)은 임계가 높아 자주 보류한다.
		var second: int = int(ranked[1]["total"]) if ranked.size() > 1 else 0
		if not Strategy.decides(int(ranked[0]["total"]), second, f.lord_type):
			skip_threshold += 1
			continue

		# **공세 처리량은 여유 함대에 비례한다.**
		#
		# 2026-08-25 까지 여기서 `idle[idle.size() - 1]` 한 척만 보냈다.
		# 조조는 실동원 101(16.9함대)에 접경 12개인데
		# 손권(5.2함대·접경 4)과 **똑같이 월 1함대만 출격했다** —
		# **공세 처리량이 세력 크기와 무관했다.**
		#
		# `ai-design.md` §5.4 는 「방어를 먼저 떼고 나머지로 공세」라 했지
		# 「한 척씩」이라 한 적이 없다. 여유의 절반을 낸다 —
		# 전부 내보내면 다음 주기에 대응할 손이 없다.
		var spare_fleets := maxi(1, (idle.size() - need) / 2)
		for _n in spare_fleets:
			if idle.size() <= need:
				break
			# **확률적 선정 + 역사 편향** (§6.2 · §11.1)
			# 최고점을 그냥 고르면 시드가 달라도 같은 판이 나온다.
			var pick := Strategy.choose_weighted(ranked, world.rng(Rng.DOMAIN_AI),
				data, world.scenario, fid, hb_milli)
			if pick.is_empty():
				break
			var fl: Fleet = idle.pop_back()
			var t := Routing.travel_ticks(world.graph, fl.at_system,
				data.system_of(pick["region"]))
			if t == Routing.UNREACHABLE:
				continue
			fl.target_region = pick["region"]
			fl.arrival_tick = world.clock.tick + maxi(t, 1)
			dispatched += 1


## ---------------------------------------------------------------- 종료 판정
func _check_end() -> void:
	var alive_ids: Array[String] = []
	for fid in faction_ids:
		if factions[fid].alive:
			alive_ids.append(fid)
	if alive_ids.size() <= 1:
		ended = true
		end_reason = "단일 세력"
		return
	var mobs := mobilized_all()
	var total := 0
	var top := 0
	for fid in alive_ids:
		total += mobs[fid]
		top = maxi(top, mobs[fid])
	var rest := total - top
	if rest * EARLY_END_DEN < top:
		ended = true
		end_reason = "조기 종료"


func mobilized_all() -> Dictionary:
	var out := {}
	for fid in faction_ids:
		var f: Faction = factions[fid]
		out[fid] = f.mobilized(data, world.region_states, world.graph,
			world.clock.tick) if f.alive else 0
	return out


## 종료 시 세계 상태 판정 (V-27 · world-state.md §4)
## **일극형이면 통합, 그 외면 병립.**
func world_state() -> String:
	var mobs := mobilized_all()
	var total := 0
	for fid in faction_ids:
		total += mobs[fid]
	if total <= 0:
		return "삼국형"
	var effective: Array[String] = []
	for fid in faction_ids:
		if mobs[fid] * 100 >= total * EFFECTIVE_FLOOR_PCT:
			effective.append(fid)
	if effective.size() <= 1:
		return "일극형"
	var top := ""
	for fid in effective:
		if top == "" or mobs[fid] > mobs[top]:
			top = fid
	var rest := 0
	for fid in effective:
		if fid != top:
			rest += mobs[fid]
	if mobs[top] >= rest * HEGEMON_RATIO:
		return "일극형"
	if effective.size() == 2:
		return "양강형"
	return "삼국형"


## ---------------------------------------------------------------- 역사 재현
##
## §11.1 의 「역사 재현율 40~60%」를 재려면 **적벽의 역사적 결과**를
## 구체적으로 정의해야 한다. 「종료 시 삼국형」은 너무 무디다 —
## 아무 일도 일어나지 않아도 삼국형이기 때문이다 (m0-report.md 검토 포인트 1).
##
## 208~211 의 역사적 결과 셋을 판정한다.
##   ① 손권이 존속한다
##   ② 조조가 강동(건업권)을 얻지 못한다
##   ③ 조조가 형주 중부권(강릉)을 얻지 못한다
##
## 셋이 모두 참일 때 「역사 재현」이다. 하나라도 어긋나면 이탈이며,
## **이탈이 나쁜 것이 아니다** — §11.1 은 절반의 이탈을 요구한다.
func historical_outcome() -> bool:
	var sun: Faction = factions.get("손권")
	if sun == null or not sun.alive:
		return false
	var by_name := {}
	for rid in data.region_ids:
		by_name[data.regions[rid]["name"]] = rid
	for nm in ["건업권", "중부권"]:
		var st: RegionState = world.region_states[by_name[nm]]
		if st.owner == "조조":
			return false
	return true


## 최대 실동원 세력
func leader() -> String:
	var mobs := mobilized_all()
	var top := ""
	for fid in faction_ids:
		if top == "" or mobs[fid] > mobs[top]:
			top = fid
	return top


## ---------------------------------------------------------------- 세력별 목표
##
## §11.1 의 「세력별 승률」을 재려면 **무엇이 승리인지**가 필요하다.
##
## **실동원 1위로 재면 안 된다.** 웅크린 세력이 이긴다 —
## 익주는 회랑으로 봉쇄되고 전화 0.95 로 온전한데 확장하지 않으니
## 신복속도 원정 부담도 지지 않는다. 2026-08-25 실측에서 **유장이 67% 로 최강**이었다.
##
## `endings.md` §6 이 답을 갖고 있다.
##
## > **오의 분치 엔딩은 페널티가 없다.** 손권의 「할거」 특성이 원전 그대로
## > 「병립 지향」이므로, 오만은 분치를 정당한 목표로 삼을 수 있다.
##
## **승리 조건은 세력마다 다르다.** 그것이 두 주제축이 살아 있다는 뜻이다 —
## 「통일 vs 분권」은 모두가 같은 것을 노릴 때는 질문이 되지 않는다.
##
## 시나리오 3 의 고유 목표는 **「남북 대치」**(§5)다.
##   조조 — 그 대치를 **깬다**. 중부권 또는 건업권을 얻으면 남하 성공
##   손권 — 그 대치를 **유지한다**. 존속하고 일극형을 막으면 분치
##   그 외 — **존속한다**. 본거지를 지키는 것이 목표다
func achieved(fid: String) -> bool:
	var f: Faction = factions.get(fid)
	if f == null or not f.alive:
		return false                       # 소멸은 절사 (§3.4)

	var by_name := {}
	for rid in data.region_ids:
		by_name[data.regions[rid]["name"]] = rid

	match fid:
		"조조":
			# 남북 대치 돌파 — 강동이나 강릉에 닿았는가
			for nm in ["건업권", "중부권"]:
				if world.region_states[by_name[nm]].owner == "조조":
					return true
			return false
		"손권":
			# 존속 + 병립. **분치는 오의 정당한 목표다**
			if world.region_states[by_name["건업권"]].owner != "손권":
				return false
			return world_state() != "일극형"
		_:
			# 본거지 성계의 권역을 하나라도 지켰는가
			for rid in f.regions:
				if data.system_of(rid) == f.capital_system:
					return true
			return false


## 세력별 달성 여부 전부
func achievements() -> Dictionary:
	var out := {}
	for fid in faction_ids:
		out[fid] = achieved(fid)
	return out


## ================================================================ 기능 이벤트
##
## `Sim._advance_one_tick` 의 ⑥ 자리가 비어 있었다 —
## **「미발동 이벤트 0종」이 M0 의 마지막 「판정 불가」 지표였다.**
##
## **Grand(계절)마다 본다.** 매 틱 40종을 굴릴 이유가 없다.
func _check_events() -> void:
	if world.clock.tick % Events.CHECK_PERIOD_TICKS != 0:
		return
	var mobs := mobilized_all()
	var rng := world.rng(Rng.DOMAIN_EVENT)
	for fid in faction_ids:                      # **정렬된 배열로만 순회한다**
		var f: Faction = factions[fid]
		if not f.alive:
			continue
		_check_faction_events(f, mobs, rng)


func _fire(fid: String, eid: String) -> bool:
	var k := eid + "|" + fid
	var last := int(_event_cooldown.get(k, -Events.COOLDOWN_TICKS * 2))
	if world.clock.tick - last < Events.COOLDOWN_TICKS:
		return false
	_event_cooldown[k] = world.clock.tick
	events_fired[eid] = int(events_fired.get(eid, 0)) + 1
	return true


func _check_faction_events(f: Faction, mobs: Dictionary, rng: RngStream) -> void:
	var fid := f.id
	var own: int = int(mobs.get(fid, 0))

	# 최강자와 그 실동원
	var top := ""
	var top_mob := 0
	for k in faction_ids:
		if int(mobs.get(k, 0)) > top_mob:
			top_mob = int(mobs.get(k, 0))
			top = k

	# ---------------------------------------------------------- [F-02] 상징의 쟁탈
	# 황제를 쥔 세력이 유효 세력이기를 그치기 직전에 황제가 손을 떠난다.
	if f.has_emperor and Events.share_pct(mobs, fid) <= Events.F02_SYMBOL_SHARE_PCT:
		if _fire(fid, "F-02"):
			f.has_emperor = false                # 상징이 손을 떠난다
			f.mandate = clampi(f.mandate - 15, Mandate.MIN, Mandate.MAX)

	# ---------------------------------------------------------- [F-05] 격상 선언
	# 회랑 둘을 낀 요충을 쥐고 실동원 40 을 넘으면 칭왕을 선언할 수 있다.
	if own >= Events.F05_MOBILIZED:
		for rid in f.regions:
			if Events.is_hub(data, rid):
				if _fire(fid, "F-05"):
					f.mandate = clampi(f.mandate + 5, Mandate.MIN, Mandate.MAX)
				break

	# ---------------------------------------------------------- [F-07][F-09][F-14]
	if top != "" and top != fid:
		var tf: Faction = factions[top]
		if Hegemony.opens_coalition(tf.hegemony):
			_fire(fid, "F-07")                   # 결성 조건 개방 (실제 성립은 _ai_grand)
		if Hegemony.turns_hostile(tf.hegemony) \
				and Events.share_pct(mobs, fid) >= Events.F14_SHARE_PCT:
			_fire(fid, "F-14")                   # 극대 앞에서는 깨진 동맹도 복원된다
		# 최강자가 연합 전체의 0.9 를 넘으면 분열 외교를 건다
		var coalition_mob := 0
		for k in faction_ids:
			if k != top and diplo.is_allied(fid, k):
				coalition_mob += int(mobs.get(k, 0))
		coalition_mob += own
		if coalition_mob > 0 and top_mob * 100 >= coalition_mob * Events.F09_SPLIT_RATIO_PCT:
			_fire(top, "F-09")

	# ---------------------------------------------------------- [F-10] 연합의 해체
	for k in faction_ids:
		if k <= fid or not diplo.is_allied(fid, k):
			continue
		var since := int(_alliance_since.get(Diplomacy.key(fid, k), world.clock.tick))
		var months := (world.clock.tick - since) / GameClock.TICKS_PER_MONTH
		var pct := Events.coalition_decay_pct(months)
		if pct > 0 and rng.chance(pct):
			if _fire(fid, "F-10"):
				diplo.set_tier(fid, k, Diplomacy.Tier.화친)
				alliances_broken += 1

	# ---------------------------------------------------------- [F-12] 배후 기습
	# **동맹 신뢰도가 「저」로 떨어지고 동맹국 주력이 다른 전선에 있을 때.**
	for k in faction_ids:
		if k == fid or not diplo.is_allied(fid, k):
			continue
		if diplo.trust_of(fid, k) > Events.F12_TRUST_MAX:
			continue
		if _committed_pct(k) < Events.F12_COMMITTED_PCT:
			continue
		var prize := _adjacent_region_of(fid, k)
		if prize == "":
			continue
		if _fire(fid, "F-12"):
			diplo.set_tier(fid, k, Diplomacy.Tier.NONE)
			diplo.record_betrayal(fid, k)
			_capture(fid, prize)                 # **등 뒤에서 요충을 가져간다**
			f.mandate = clampi(f.mandate - 10, Mandate.MIN, Mandate.MAX)
			backstabs += 1

	# ---------------------------------------------------------- [F-13] 고립과 비지화
	for rid in f.regions:
		var isolated := true
		for nb in data.region_adjacency.get(rid, []):
			if f.regions.has(nb):
				isolated = false
				break
		if isolated:
			var rst: RegionState = world.region_states.get(rid)
			if rst != null and _fire(fid, "F-13"):
				Stability.tick(rst, true)        # 비지 −8
			break

	# ---------------------------------------------------------- [F-15] 요충 쟁탈
	for rid in f.regions:
		for nb in data.region_adjacency.get(rid, []):
			var nst: RegionState = world.region_states.get(nb)
			if nst == null or nst.owner == "" or nst.owner == fid:
				continue
			if not Events.is_hub(data, nb):
				continue
			if own * 100 >= int(mobs.get(nst.owner, 1)) * Events.F15_ATTACK_RATIO_PCT:
				_fire(fid, "F-15")
				break

	# ---------------------------------------------------------- [F-17] 약자의 반복 공세
	# **할거 페널티가 도는 동안 약자는 계속 나간다** — 제갈량의 북벌이다.
	if own >= Events.F17_MOBILIZED and f.months_idle >= Stability.STAGNATION_MONTHS:
		_fire(fid, "F-17")

	# ---------------------------------------------------------- [F-23] 관문 방어전
	for rid in f.regions:
		if not Events.is_hub(data, rid):
			continue
		for nb in data.region_adjacency.get(rid, []):
			var nst2: RegionState = world.region_states.get(nb)
			if nst2 != null and nst2.owner != "" and nst2.owner != fid \
					and not diplo.is_allied(fid, nst2.owner):
				_fire(fid, "F-23")
				break

	# ---------------------------------------------------------- [F-25] 최후의 항전
	if top != "" and top != fid and own > 0 \
			and own * Events.F25_LAST_STAND_DEN <= top_mob:
		if _fire(fid, "F-25"):
			for fl in fleets:                    # **막다른 곳에서 사기가 오른다**
				if fl.owner == fid and fl.is_alive():
					fl.morale = mini(fl.morale + 10, Battle.MORALE_MAX)

	# ---------------------------------------------------------- [F-27] 의사결정 지연
	if fid == top and f.lord_type == "명문형":
		_fire(fid, "F-27")

	# ---------------------------------------------------------- [F-36] 미래를 태우는 통치
	if f.lord_type == "무단형":
		var eff := f.effective_milli(data, world.region_states) / 1000
		var upkeep := 0
		for fl in fleets:
			if fl.owner == fid and fl.is_alive():
				upkeep += fl.squadrons_milli() / 1000
		if upkeep > 0 and eff * 100 <= upkeep * Events.F36_DEFICIT_PCT:
			if _fire(fid, "F-36"):
				for rid in f.regions:            # **수탈** — 안정도 −10
					var rst2: RegionState = world.region_states.get(rid)
					if rst2 != null:
						Stability.tick(rst2, false, true)

	# ---------------------------------------------------------- [F-37] 수도 파괴와 천도
	if top != "" and top != fid and f.regions.size() > 1 \
			and top_mob * 100 >= own * Events.F37_CAPITAL_RATIO_PCT:
		_fire(fid, "F-37")

	# ---------------------------------------------------------- [F-39] 후방 반란
	# **주력이 나가 있고 후방이 흔들리면 등 뒤에서 무너진다.**
	if _committed_pct(fid) >= Events.F39_COMMITTED_PCT:
		for rid in f.regions:
			var rst3: RegionState = world.region_states.get(rid)
			if rst3 == null or rst3.stability > Events.F39_REVOLT_STABILITY:
				continue
			if _fire(fid, "F-39"):
				f.remove_region(rid)             # 권역이 손을 떠난다
				rst3.owner = ""
				rst3.stability = Stability.INIT_FRONTIER
				revolts += 1
			break

	# ---------------------------------------------------------- [F-40] 땅 없는 자의 유랑
	if f.regions.is_empty() and f.mandate >= Events.F40_MANDATE:
		var ships := 0
		for fl in fleets:
			if fl.owner == fid and fl.is_alive():
				ships += fl.ships
		if ships >= Battle.SQUADRON_SHIPS:
			if _fire(fid, "F-40"):
				f.alive = true
				f.wandering = true               # **땅을 잃어도 끝나지 않는다**


## 그 세력 주력의 몇 %가 이동 중(타 전선)인가.
func _committed_pct(fid: String) -> int:
	var total := 0
	var moving := 0
	for fl in fleets:
		if fl.owner != fid or not fl.is_alive():
			continue
		total += fl.ships
		if fl.is_moving():
			moving += fl.ships
	if total <= 0:
		return 0
	return moving * 100 / total


## `fid` 에 인접한 `owner` 의 권역 하나. 없으면 빈 문자열.
func _adjacent_region_of(fid: String, owner: String) -> String:
	var f: Faction = factions[fid]
	for rid in f.regions:
		for nb in data.region_adjacency.get(rid, []):
			var st: RegionState = world.region_states.get(nb)
			if st != null and st.owner == owner:
				return nb
	return ""
