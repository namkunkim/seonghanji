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

## 캠페인 세이브 형식 판 (schema/save-campaign.json). World 세이브의 판과 별개다.
const SAVE_CAMPAIGN_VERSION: int = 1

## SCN-03 시나리오 사건 ID. 기능 이벤트(F-01~F-40)가 아니라 208 서사 사건이다.
const SCN03_EVENT03: String = "SCN-03-E03"
const SCN03_EVENT04: String = "SCN-03-E04"
const SCN03_EVENT06: String = "SCN-03-E06"
const SCN03_EVENT07: String = "SCN-03-E07"
const SCN03_EVENT09: String = "SCN-03-E09"
## G-10 slice 3 canonical pending identity. It is derived only from SCN-03 Event 09
## and its fixed ordinal; display names, fleets, region ownership, and UI order never enter it.
const SCN03_RED_CLIFF_PENDING_BATTLE_ID: String = "SCN-03-E09-RED-CLIFF-01"
## 외생 시나리오 결과 입력. World 명령 로그에만 남고, 진행 원장은 재생 파생값이다.
const CMD_SCN03_EVENT_OUTCOME: String = "scenario_event_outcome"
## Event 07's approved Red-Cliffs participant ledger is an external player command.
## It is replayed like the event outcomes; no campaign snapshot owns it.
const CMD_SCN03_RED_CLIFF_MANIFEST: String = "scn03_red_cliff_manifest"
## The active-battle result is an explicit player fact.  It is accepted only
## after the deterministic Contact → Barrage transition, then replayed from the
## normal player command log.
const CMD_SCN03_RED_CLIFF_RESULT: String = "scn03_red_cliff_result"
## DEMO-RC-02/03: the sole public battle-control command.  Its payload never
## contains losses, morale, schemes, or a winner.
const CMD_RED_CLIFF_PLAYER_COMMAND: String = "red_cliff_player_command"
const CMD_BATTLE_FORMATION_CHANGE: String = "battle_formation_change"
## Transition-news IDs are derived from this canonical battle ID plus one fixed
## transition token; they never use UI order, text, or an incrementing counter.
const SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1: String = "active_phase_1"
const SCN03_RED_CLIFF_TRANSITION_PHASE_2: String = "phase_2"
const SCN03_RED_CLIFF_TRANSITION_RESOLVED: String = "resolved"
const SCN03_CAO_OWNER: String = "조조"
const SCN03_SUN_OWNER: String = "손권"
const SCN03_LIU_CONTINGENT_ID: String = "SCN-03-LIU-BEI-CONTINGENT"
## 홈의 3D 항행 관측용 제3함대는 대형 편대가 아니라 독립 전열함 해무급 한 척이다.
## 이 값은 뷰 연출용 대체가 아니라 시나리오 초기 Fleet 정본에 반영한다.
const SCN03_HAEMU_SOLO_FLEET_ID: int = 3
## Negative command is the canonical unusable-command sentinel.  Scenario fleets
## may legitimately use zero while their officer roster provides the capability.
const RED_CLIFF_MIN_COMMAND_FOR_PLAYER_ORDER: int = 0

## Event 09 (scenario-200-208.md §ACT 7)의 순서는 지문에도 고정한다.
const SCN03_RED_CLIFF_CONDITIONS: Array[String] = [
	"cao_southward_complete",
	"sun_quan_independent",
	"liu_bei_hostile_to_cao",
	"sun_liu_military_pact",
	"yangtze_defense_line",
]


var world: World

## 세력별 인물 로스터. 세력 → Array[Dictionary] (통솔 내림차순)
var roster: Dictionary = {}
var data: GameData
var factions: Dictionary = {}
var faction_ids: Array[String] = []
var fleets: Array[Fleet] = []
var _next_fleet_id: int = 0

## 뷰어 → 적 함대 ID → 마지막 판독 값. `screens.md` §12.3의 세션 파생 관측 이력이다.
## 저장·지문에는 넣지 않는다. 관측은 명령·전투의 결과를 바꾸지 않는 정보 상태다 (V-66).
var _fleet_readings: Dictionary = {}

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

## 208 서사 사건 결과의 결정론적 원장. 값이 없으면 unknown 이며 false가 아니다.
## 외부 사건/명령 계층은 `issue_scn03_event_outcome`으로 player 입력을 로그화하고,
## 이 원장은 도달한 명령을 `record_scn03_event_outcome` reducer로 적용한 파생값이다.
var scn03_progress: Dictionary = {}
var _scn03_event09_evaluated: bool = false
## 기능 이벤트 계측(`events_fired`)과 분리된, 208 서사 사건의 one-shot 기록.
var scenario_event_records: Dictionary = {}
## Replay-derived Event 07 participant ledger.  Actual fleet IDs are explicit player
## input; this state never selects by owner, distance, region, or strength.
var scn03_red_cliff_manifest: Dictionary = {}
## Event 09에서만 파생하는 적벽 지속형 전투 상태. 세이브 스냅숏 정본이 아니며,
## player scenario-outcome 명령 재생으로 같은 순서에 다시 만든다.
var active_battles: Array[ActiveBattle] = []
var _battle_formation_commands: Dictionary = {}
var battle_formation_results: Array[Dictionary] = []
## Immutable, replay-derived transition facts for the canonical Red-Cliffs
## battle.  This is deliberately not C-02 policy or a UI feed: consumers can
## later project these facts without being allowed to create or alter them.
var scn03_red_cliff_transition_news: Array[Dictionary] = []
## 재생 입력은 발행 틱에만 World 대기열로 옮긴다. 저장 상태가 아니며 digest에도
## 직접 넣지 않는다 — World의 applied/pending player 명령이 같은 사실을 이미 접는다.
var _replay_player_commands: Array[Dictionary] = []
var _replay_player_cursor: int = 0
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
	# SCN-03 progress-command reducer is a RS-0.2 generation addition. Keeping RS-0.1
	# replays on their old digest path preserves saves made before G-10 slice 2.
	c.world.ruleset = Save.CURRENT_RULESET
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
	if fl.id == SCN03_HAEMU_SOLO_FLEET_ID and owner == SCN03_SUN_OWNER:
		fl.ships = 1
		fl.plan = Economy.PLAN_DEFAULT
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
	_stage_replay_player_commands()
	world.clock.step_ticks(1)
	Sim._advance_one_tick(world)
	_apply_arrived()          # ①-b 도달한 명령에 효과를 붙인다 (S2.9)
	_settle_month()           # ②-b 월 정산 — 자금·행정비·유지비 (S2.9)
	_arrive_fleets()
	_advance_scn03_red_cliff_pending_battle()
	if world.clock.tick % Strategy.GRAND_PERIOD_TICKS == 0:
		_ai_grand()
	if world.clock.tick % Strategy.OPERATIONAL_PERIOD_TICKS == 0:
		_ai_operational()
	_check_events()           # ⑥ 이벤트 판정 (function-events.md)
	_check_end()
	_advance_scn03_red_cliff_pending_battle()


## 재생 로그를 한꺼번에 pending에 싣지 않는다. 실제 플레이에서는 tick N의 step이 끝난
## 뒤 발행된 zero-delay 명령이 다음 step에만 전달된다. 재생도 tick N 시작에 N까지 발행된
## 입력만 주입해야 같은 전달 순서를 유지한다.
func _stage_replay_player_commands() -> void:
	while _replay_player_cursor < _replay_player_commands.size():
		var command: Dictionary = _replay_player_commands[_replay_player_cursor]
		if int(command["issued_tick"]) > world.clock.tick:
			return
		world.pending_commands.append(command.duplicate(true))
		_replay_player_cursor += 1


## SCN-03 Event 03/04/06/07의 **확정 결과만** 적벽 원장에 기록한다.
##
## 매핑은 `scenario-200-208.md` ACT 2~5의 직접 문장에 한정한다:
## E03 조조의 남하 → 조조 남하 완료, E04 항복인가 항전인가 → 손권 독립 유지,
## E06 땅 없는 자의 외교 → 유비 대조조 적대, E07 손유 회담의 군사협정/공동 방어
## → 손유 군사협정/장강 방어선. Event 05는 이 다섯 조건의 직접 원인이 아니다.
##
## `outcome`은 아래 정확한 키와 bool 값만 받는다. 같은 결과의 재기록은 idempotent;
## 다른 결과, 알 수 없는 사건, 불완전한 사전은 거부한다. 지역·전력·외교 tier·함대
## 위치는 여기서 읽거나 추론하지 않는다.
func record_scn03_event_outcome(event_id: String, outcome: Dictionary) -> bool:
	if world == null or world.scenario != "SCN-03" or not _uses_scn03_progress_rules():
		return false
	var expected := _scn03_expected_outcome_keys(event_id)
	if expected.is_empty() or not _is_valid_scn03_event_outcome(event_id, outcome):
		return false

	var same := true
	for key in expected:
		if scn03_progress.has(key) and bool(scn03_progress[key]) != bool(outcome[key]):
			return false
		if not scn03_progress.has(key) or bool(scn03_progress[key]) != bool(outcome[key]):
			same = false
	if same:
		return true
	for key in expected:
		scn03_progress[key] = bool(outcome[key])
	_evaluate_scn03_event09_if_ready()
	return true


## 외부 플레이어가 확정한 208 사건 결과의 유일한 입력 경로.
##
## 진행 원장과 Event 09 기록은 이 명령이 도달했을 때만 파생한다. 따라서 세이브는
## 원장을 직렬화하지 않고 이 명령(origin="player")만 기록하며, 재생도 같은 틱에 같은
## reducer를 지난다. `record_scn03_event_outcome`은 도달한 명령의 reducer 및 기존 단위
## 시험 호환용이다. UI/시나리오 호출자는 반드시 이 함수를 사용한다.
func issue_scn03_event_outcome(event_id: String, outcome: Dictionary,
		delay_ticks: int = 0) -> Dictionary:
	if world == null or world.scenario != "SCN-03" or not _uses_scn03_progress_rules():
		return {}
	if delay_ticks < 0 or not _is_valid_scn03_event_outcome(event_id, outcome):
		return {}
	return world.issue(CMD_SCN03_EVENT_OUTCOME, {
		"event_id": event_id,
		"outcome": outcome.duplicate(true),
	}, delay_ticks, "player")


## The Event 07 participant manifest's only player-facing entry point.  Fleet IDs
## are canonical Campaign IDs, while the Liu contingent is deliberately a scenario
## identifier rather than a Fleet or a new faction.
func issue_scn03_red_cliff_manifest(cao_fleet_ids: Array, sun_liu_fleet_ids: Array,
		fleet_roles: Dictionary, liu_contingent_id: String = SCN03_LIU_CONTINGENT_ID,
		delay_ticks: int = 0) -> Dictionary:
	var payload := {
		"cao_fleet_ids": cao_fleet_ids.duplicate(),
		"sun_liu_fleet_ids": sun_liu_fleet_ids.duplicate(),
		"fleet_roles": fleet_roles.duplicate(true),
		"liu_contingent_id": liu_contingent_id,
	}
	if world == null or world.scenario != "SCN-03" or not _uses_scn03_progress_rules():
		return {}
	if delay_ticks < 0 or not _is_valid_scn03_red_cliff_manifest_payload(payload):
		return {}
	if not bool(scn03_progress.get("sun_liu_military_pact", false)) \
			or not bool(scn03_progress.get("yangtze_defense_line", false)) \
			or not _manifest_fleets_valid_now(_canonical_scn03_red_cliff_manifest(payload)):
		return {}
	return world.issue(CMD_SCN03_RED_CLIFF_MANIFEST, payload, delay_ticks, "player")


func issue_scn03_red_cliff_result(winner_faction_id: String, delay_ticks: int = 0) -> Dictionary:
	# Deprecated DEMO-RC-01 boundary: a player may not provide a winner.
	return {}


## Public, log-backed controls for the playable Red-Cliffs battle.  The result
## dictionary returned by World.issue is only an accepted command receipt; use
## red_cliff_command_state() for renderable state and rejection reason.
func issue_red_cliff_player_command(battle_id: String, kind: String,
		payload: Dictionary = {}, delay_ticks: int = 0) -> Dictionary:
	if world == null or world.scenario != "SCN-03" or not _uses_scn03_red_cliff_phase_rules() \
			or delay_ticks < 0 or not _is_valid_red_cliff_player_command_payload(battle_id, kind, payload):
		return {}
	var battle := _scn03_red_cliff_battle()
	var reason := _red_cliff_player_command_reason(battle, battle_id, kind, payload)
	if reason != "":
		return {}
	var receipt := world.issue(CMD_RED_CLIFF_PLAYER_COMMAND, {"battle_id": battle_id,
		"kind": kind, "payload": payload.duplicate(true)}, delay_ticks, "player")
	if not receipt.is_empty():
		receipt["accepted"] = true
		receipt["reason_code"] = "queued"
		receipt["command_kind"] = kind
	return receipt


func red_cliff_command_state(battle_id: String, requested_kind: String = "",
		requested_payload: Dictionary = {}) -> Dictionary:
	var battle := _scn03_red_cliff_battle()
	if battle == null or battle.battle_id != battle_id:
		return {"accepted": false, "reason": "unknown_battle", "reason_code": "unknown_battle"}
	var state := {"accepted": battle.status == ActiveBattle.STATUS_ACTIVE,
		"reason": "resolved" if battle.status == ActiveBattle.STATUS_RESOLVED else "",
		"reason_code": "resolved" if battle.status == ActiveBattle.STATUS_RESOLVED else "",
		"phase": battle.combat_phase, "status": battle.status,
		"can_advance": battle.status == ActiveBattle.STATUS_ACTIVE and battle.combat_phase >= 2 and not battle.ai_delegated,
		"can_change_formation": battle.status == ActiveBattle.STATUS_ACTIVE and not battle.ai_delegated,
		"ai_delegated": battle.ai_delegated, "player_commands": battle.player_commands.duplicate(true),
		"last_command_feedback": battle.last_command_feedback.duplicate(true)}
	if requested_kind != "":
		state["requested_command"] = {
			"accepted": _red_cliff_player_command_reason(battle, battle_id, requested_kind, requested_payload) == "",
			"reason_code": _red_cliff_player_command_reason(battle, battle_id, requested_kind, requested_payload),
			"kind": requested_kind,
		}
	return state


func _red_cliff_player_command_reason(battle: ActiveBattle, battle_id: String,
		kind: String, payload: Dictionary) -> String:
	if battle == null or battle.battle_id != battle_id:
		return "unknown_battle"
	if battle.status == ActiveBattle.STATUS_RESOLVED:
		return "resolved"
	if battle.status != ActiveBattle.STATUS_ACTIVE:
		return "battle_not_active"
	if not _is_valid_red_cliff_player_command_payload(battle_id, kind, payload):
		return "invalid_payload"
	if battle.ai_delegated:
		return "ai_delegated"
	if kind == "advance_phase" and battle.combat_phase < 2:
		return "phase_not_ready"
	if battle.has_player_command_for_phase(kind, battle.combat_phase):
		return "duplicate_command"
	if kind == "change_formation" and String(payload.get("target_formation_id", "")) == battle.attacker_formation_id:
		return "duplicate_command"
	if kind != "delegate_ai":
		var attacker := _fleet_by_id(int(battle.attacker_fleet_ids[0])) if not battle.attacker_fleet_ids.is_empty() else null
		if attacker == null or attacker.command < RED_CLIFF_MIN_COMMAND_FOR_PLAYER_ORDER:
			return "insufficient_command"
	return ""


static func _is_valid_red_cliff_player_command_payload(battle_id: String, kind: String,
		payload: Dictionary) -> bool:
	if battle_id != SCN03_RED_CLIFF_PENDING_BATTLE_ID or not ["hold_formation", "change_formation", "advance_phase", "delegate_ai"].has(kind):
		return false
	if kind == "change_formation":
		return payload.size() == 1 and payload.get("target_formation_id", null) is String \
			and Formations.exists_id(String(payload["target_formation_id"]))
	return payload.is_empty()


func issue_battle_formation_change(battle_id: String, next_phase: int, fleet_id: int,
		target_formation_id: String, delay_ticks: int = 0) -> Dictionary:
	if battle_id == SCN03_RED_CLIFF_PENDING_BATTLE_ID or delay_ticks < 0 \
			or next_phase < 2 or next_phase > 5 or not Formations.exists_id(target_formation_id):
		return {}
	return world.issue(CMD_BATTLE_FORMATION_CHANGE, {"battle_id": battle_id,
		"next_phase": next_phase, "fleet_id": fleet_id,
		"target_formation_id": target_formation_id}, delay_ticks, "player")


## Save.inspect uses this same structural contract before replay.  It intentionally
## cannot validate live fleet liveness/ownership; the reducer below does that at the
## command's arrival tick, where those facts are authoritative.
static func _is_valid_scn03_red_cliff_manifest_payload(payload: Dictionary) -> bool:
	var required: Array[String] = ["cao_fleet_ids", "sun_liu_fleet_ids", "fleet_roles",
		"liu_contingent_id"]
	if payload.size() != required.size():
		return false
	for key in required:
		if not payload.has(key):
			return false
	if not payload["cao_fleet_ids"] is Array or not payload["sun_liu_fleet_ids"] is Array \
			or not payload["fleet_roles"] is Dictionary \
			or not payload["liu_contingent_id"] is String \
			or String(payload["liu_contingent_id"]) != SCN03_LIU_CONTINGENT_ID:
		return false
	var unique: Dictionary = {}
	for side_ids in [payload["cao_fleet_ids"], payload["sun_liu_fleet_ids"]]:
		if side_ids.is_empty():
			return false
		for raw_id in side_ids:
			if not Save._is_json_integer(raw_id) or int(raw_id) < 0 or unique.has(int(raw_id)):
				return false
			unique[int(raw_id)] = true
	var roles: Dictionary = payload["fleet_roles"]
	if roles.size() != unique.size():
		return false
	for raw_id in unique.keys():
		var role_key := str(raw_id)
		if not roles.has(role_key) or not roles[role_key] is String \
			or String(roles[role_key]).strip_edges() == "":
			return false
	for role_key in roles:
		if not role_key is String:
			return false
		var role_key_text := String(role_key)
		if not role_key_text.is_valid_int() or not unique.has(int(role_key_text)):
			return false
	return true


func _record_scn03_red_cliff_manifest(payload: Dictionary) -> bool:
	if world == null or world.scenario != "SCN-03" or not _uses_scn03_progress_rules() \
			or not _is_valid_scn03_red_cliff_manifest_payload(payload):
		return false
	# Event 07 success, not merely Event 07's arrival, is the prerequisite.
	if not bool(scn03_progress.get("sun_liu_military_pact", false)) \
			or not bool(scn03_progress.get("yangtze_defense_line", false)):
		return false
	var canonical := _canonical_scn03_red_cliff_manifest(payload)
	if not _manifest_fleets_valid_now(canonical):
		return false
	if not scn03_red_cliff_manifest.is_empty():
		return scn03_red_cliff_manifest == canonical
	scn03_red_cliff_manifest = canonical
	return true


func _canonical_scn03_red_cliff_manifest(payload: Dictionary) -> Dictionary:
	var cao_ids: Array = payload["cao_fleet_ids"].duplicate()
	var sun_ids: Array = payload["sun_liu_fleet_ids"].duplicate()
	cao_ids.sort()
	sun_ids.sort()
	var roles: Dictionary = payload["fleet_roles"].duplicate(true)
	return {
		"cao_fleet_ids": cao_ids,
		"sun_liu_fleet_ids": sun_ids,
		"fleet_roles": roles,
		"liu_contingent_id": String(payload["liu_contingent_id"]),
	}


func _manifest_fleets_valid_now(manifest: Dictionary) -> bool:
	for raw_id in manifest.get("cao_fleet_ids", []):
		var cao_fleet := _fleet_by_id(int(raw_id))
		if cao_fleet == null or not cao_fleet.is_alive() or cao_fleet.owner != SCN03_CAO_OWNER:
			return false
	for raw_id in manifest.get("sun_liu_fleet_ids", []):
		var sun_fleet := _fleet_by_id(int(raw_id))
		if sun_fleet == null or not sun_fleet.is_alive() or sun_fleet.owner != SCN03_SUN_OWNER:
			return false
	return true


static func _is_valid_scn03_red_cliff_result_payload(payload: Dictionary) -> bool:
	if payload.size() != 3 or String(payload.get("battle_id", "")) != SCN03_RED_CLIFF_PENDING_BATTLE_ID:
		return false
	if not (payload.get("phase", null) is int) or int(payload["phase"]) != 2:
		return false
	var winner := String(payload.get("winner_faction_id", ""))
	return winner == "cao_side" or winner == "sun_liu_side"


func _scn03_red_cliff_battle() -> ActiveBattle:
	for battle in active_battles:
		if battle.battle_id == SCN03_RED_CLIFF_PENDING_BATTLE_ID:
			return battle
	return null


func _has_pending_scn03_red_cliff_result() -> bool:
	for command in world.pending_commands:
		if String(command.get("kind", "")) == CMD_SCN03_RED_CLIFF_RESULT:
			return true
	return false


static func _scn03_red_cliff_transition_news_id(battle_id: String, transition: String) -> String:
	return "%s:%s" % [battle_id, transition]


func _record_scn03_red_cliff_transition_news(battle: ActiveBattle, transition: String,
		at_tick: int) -> bool:
	if not _uses_scn03_red_cliff_news_rules() or battle == null \
			or battle.battle_id != SCN03_RED_CLIFF_PENDING_BATTLE_ID:
		return false
	if not [SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1,
		SCN03_RED_CLIFF_TRANSITION_PHASE_2,
		SCN03_RED_CLIFF_TRANSITION_RESOLVED].has(transition):
		return false
	var news_id := _scn03_red_cliff_transition_news_id(battle.battle_id, transition)
	for record in scn03_red_cliff_transition_news:
		if String(record.get("news_id", "")) == news_id:
			return false
	scn03_red_cliff_transition_news.append({
		"news_id": news_id,
		"battle_id": battle.battle_id,
		"transition": transition,
		"tick": at_tick,
	})
	scn03_red_cliff_transition_news.sort_custom(
		func(a, b): return String(a["news_id"]) < String(b["news_id"]))
	return true


func _fleet_by_id(fleet_id: int) -> Fleet:
	for fleet in fleets:
		if fleet.id == fleet_id:
			return fleet
	return null


## Read-only shared formation projection for UI, AI, and replay diagnostics.
func formation_verdict_for_fleet(fleet: Fleet, opposing: Fleet, phase: int,
		terrain: String) -> Dictionary:
	if fleet == null or opposing == null:
		return {}
	return Formations.combat_verdict(Formations.id_for_name(fleet.formation),
		Formations.id_for_name(opposing.formation), phase, fleet.command,
		fleet.staff_traits, terrain)


func active_battle_formation_verdicts(battle: ActiveBattle) -> Dictionary:
	if battle == null or battle.status != ActiveBattle.STATUS_ACTIVE or battle.combat_phase < 1:
		return {}
	var attacker := _fleet_by_id(int(battle.attacker_fleet_ids[0])) if not battle.attacker_fleet_ids.is_empty() else null
	var defender := _fleet_by_id(int(battle.defender_fleet_ids[0])) if not battle.defender_fleet_ids.is_empty() else null
	if attacker == null or defender == null:
		return {}
	return {"attacker": formation_verdict_for_fleet(attacker, defender,
		battle.combat_phase - 1, "개활"), "defender": formation_verdict_for_fleet(defender,
		attacker, battle.combat_phase - 1, "개활")}


func _advance_scn03_red_cliff_pending_battle() -> void:
	if not _uses_scn03_progress_rules():
		return
	for battle in active_battles:
		if battle.battle_id != SCN03_RED_CLIFF_PENDING_BATTLE_ID:
			continue
		if battle.status == ActiveBattle.STATUS_ACTIVE:
			if _uses_scn03_red_cliff_phase_rules():
				if battle.combat_phase == 1 and world.clock.tick > battle.started_tick \
						and _apply_red_cliff_phase_calculation(battle, 1, world.clock.tick):
					_apply_red_cliff_result_once(battle)
					_record_scn03_red_cliff_transition_news(battle,
						SCN03_RED_CLIFF_TRANSITION_PHASE_2, world.clock.tick)
				elif battle.ai_delegated and battle.combat_phase >= 2:
					battle.record_ai_decision(battle.combat_phase, "advance_phase", world.clock.tick)
					_apply_red_cliff_phase_calculation(battle, battle.combat_phase, world.clock.tick)
					_apply_red_cliff_result_once(battle)
			return
		if battle.status != ActiveBattle.STATUS_PENDING:
			return
		if ended:
			battle.cancel_pending(world.clock.tick, "scenario_ended")
			return
		if scn03_red_cliff_manifest.is_empty():
			return
		var status := _scn03_red_cliff_manifest_arrival_status(scn03_red_cliff_manifest)
		if String(status["state"]) == "cancelled":
			battle.cancel_pending(world.clock.tick, String(status["reason"]))
			return
		if String(status["state"]) != "ready":
			return
		var attacker_ids: Array[String] = []
		var defender_ids: Array[String] = []
		for raw_id in scn03_red_cliff_manifest["cao_fleet_ids"]:
			attacker_ids.append(str(raw_id))
		for raw_id in scn03_red_cliff_manifest["sun_liu_fleet_ids"]:
			defender_ids.append(str(raw_id))
		battle.activate_red_cliff(attacker_ids, defender_ids,
			scn03_red_cliff_manifest["fleet_roles"],
			String(scn03_red_cliff_manifest["liu_contingent_id"]), world.clock.tick)
		var attacker := _fleet_by_id(int(attacker_ids[0]))
		var defender := _fleet_by_id(int(defender_ids[0]))
		var attacker_ships := 0
		var defender_ships := 0
		for fleet_id in attacker_ids:
			var fleet := _fleet_by_id(int(fleet_id))
			attacker_ships += fleet.ships if fleet != null else 0
		for fleet_id in defender_ids:
			var fleet := _fleet_by_id(int(fleet_id))
			defender_ships += fleet.ships if fleet != null else 0
		battle.initialize_red_cliff_state(attacker_ships, defender_ships,
			attacker.morale if attacker != null else 100, defender.morale if defender != null else 100,
			Formations.id_for_name(attacker.formation) if attacker != null else Formations.PALJIN_ID,
			Formations.id_for_name(defender.formation) if defender != null else Formations.PALJIN_ID)
		_record_scn03_red_cliff_transition_news(battle,
			SCN03_RED_CLIFF_TRANSITION_ACTIVE_PHASE_1, world.clock.tick)
		return


func _apply_red_cliff_phase_calculation(battle: ActiveBattle, phase: int, at_tick: int) -> bool:
	if battle == null or battle.status != ActiveBattle.STATUS_ACTIVE or battle.combat_phase != phase:
		return false
	var attacker := _fleet_by_id(int(battle.attacker_fleet_ids[0])) if not battle.attacker_fleet_ids.is_empty() else null
	var defender := _fleet_by_id(int(battle.defender_fleet_ids[0])) if not battle.defender_fleet_ids.is_empty() else null
	if attacker == null or defender == null:
		return false
	var index := phase - 1
	var attacker_stat := attacker.wits if index < 2 else attacker.command
	var defender_stat := defender.wits if index < 2 else defender.command
	var attacker_coeff := Battle.formation_adjusted_ship_coefficient_milli(1000,
		battle.attacker_formation_id, battle.defender_formation_id, index, attacker.command,
		attacker.staff_traits, "개활")
	var defender_coeff := Battle.formation_adjusted_ship_coefficient_milli(1000,
		battle.defender_formation_id, battle.attacker_formation_id, index, defender.command,
		defender.staff_traits, "개활")
	var attacker_power := Battle.combat_power_milli(battle.attacker_ships, attacker_coeff,
		attacker_stat, index, battle.attacker_morale)
	var defender_power := Battle.combat_power_milli(battle.defender_ships, defender_coeff,
		defender_stat, index, battle.defender_morale)
	var attacker_rate := Battle.loss_rate_milli(index, attacker_power, defender_power)
	var defender_rate := Battle.loss_rate_milli(index, defender_power, attacker_power)
	var schemes: Array[Dictionary] = []
	# One fixed candidate per phase keeps the result independent of UI ordering.
	var scheme_kinds: Array[int] = [Scheme.Kind.AMBUSH, Scheme.Kind.FIRE, Scheme.Kind.DISCORD,
		Scheme.Kind.DECAPITATE, Scheme.Kind.LURE]
	var scheme_kind: int = scheme_kinds[index]
	var caster_is_attacker := index != 1
	var chance := Scheme.success_chance_milli(scheme_kind, index,
		attacker.wits if caster_is_attacker else defender.wits,
		defender.wits if caster_is_attacker else attacker.wits,
		battle.defender_morale if caster_is_attacker else battle.attacker_morale)
	var roll := Rng.roll_for(world.rng_seed, Rng.DOMAIN_COMBAT, at_tick,
		"%s|phase|%d|scheme" % [battle.battle_id, phase]) % 100000
	if roll < chance:
		var target_loss := (battle.defender_ships if caster_is_attacker else battle.attacker_ships) \
			* Scheme.EFFECT_LOSS_MILLI[scheme_kind] / 100000
		if caster_is_attacker:
			defender_rate += Scheme.EFFECT_LOSS_MILLI[scheme_kind]
		else:
			attacker_rate += Scheme.EFFECT_LOSS_MILLI[scheme_kind]
		schemes.append({"phase": phase, "kind": scheme_kind, "name": Scheme.NAMES[scheme_kind],
			"caster": "cao_side" if caster_is_attacker else "sun_liu_side", "loss": target_loss})
	var attacker_loss := mini(battle.attacker_ships, battle.attacker_ships * attacker_rate / 100000)
	var defender_loss := mini(battle.defender_ships, battle.defender_ships * defender_rate / 100000)
	return battle.apply_red_cliff_phase_outcome(at_tick, {"attacker_loss": attacker_loss,
		"defender_loss": defender_loss,
		"attacker_morale_delta": Battle.morale_delta(index, attacker_power, defender_power),
		"defender_morale_delta": Battle.morale_delta(index, defender_power, attacker_power),
		"schemes": schemes})


## DEMO-RC-05 core-side result projection.  The phase engine is the only writer
## of totals; this projection distributes those totals to existing fleets once,
## without inventing territory effects.
func _apply_red_cliff_result_once(battle: ActiveBattle) -> bool:
	if battle == null or battle.status != ActiveBattle.STATUS_RESOLVED or battle.campaign_result_applied:
		return false
	_apply_red_cliff_side_result(battle.attacker_fleet_ids, battle.attacker_ships, battle.attacker_morale)
	_apply_red_cliff_side_result(battle.defender_fleet_ids, battle.defender_ships, battle.defender_morale)
	battle.campaign_result_applied = true
	_record_scn03_red_cliff_transition_news(battle, SCN03_RED_CLIFF_TRANSITION_RESOLVED, battle.resolved_tick)
	return true


func _apply_red_cliff_side_result(fleet_ids: Array[String], total_ships: int, morale: int) -> void:
	var eligible: Array[Fleet] = []
	var baseline := 0
	for raw_id in fleet_ids:
		var fleet := _fleet_by_id(int(raw_id))
		if fleet != null:
			eligible.append(fleet)
			baseline += maxi(0, fleet.ships)
	var remaining := maxi(0, total_ships)
	for i in eligible.size():
		var fleet := eligible[i]
		var assigned := remaining if i == eligible.size() - 1 else \
			(mini(remaining, fleet.ships * maxi(0, total_ships) / maxi(1, baseline)))
		fleet.ships = assigned
		fleet.morale = clampi(morale, 0, Battle.MORALE_MAX)
		remaining -= assigned


func _scn03_red_cliff_manifest_arrival_status(manifest: Dictionary) -> Dictionary:
	for entry in [["cao_fleet_ids", SCN03_CAO_OWNER], ["sun_liu_fleet_ids", SCN03_SUN_OWNER]]:
		for raw_id in manifest[String(entry[0])]:
			var fleet := _fleet_by_id(int(raw_id))
			if fleet == null or not fleet.is_alive():
				return {"state": "cancelled", "reason": "required_fleet_destroyed"}
			if fleet.owner != String(entry[1]):
				return {"state": "cancelled", "reason": "manifest_invalid"}
			# A move issued while already at the battle system is an explicit withdrawal.
			if fleet.is_moving() and fleet.at_system == ActiveBattle.RED_CLIFF_SYSTEM_ID:
				return {"state": "cancelled", "reason": "required_fleet_withdrawn"}
			if fleet.is_moving() or fleet.at_system != ActiveBattle.RED_CLIFF_SYSTEM_ID:
				return {"state": "waiting"}
	return {"state": "ready"}


static func _scn03_expected_outcome_keys(event_id: String) -> Array[String]:
	match event_id:
		SCN03_EVENT03:
			return ["cao_southward_complete"]
		SCN03_EVENT04:
			return ["sun_quan_independent"]
		SCN03_EVENT06:
			return ["liu_bei_hostile_to_cao"]
		SCN03_EVENT07:
			return ["sun_liu_military_pact", "yangtze_defense_line"]
	return []


## Save.inspect와 도달 reducer가 같은 payload 계약을 쓴다. 여기서는 World나 UI 상태를
## 읽지 않아 재생 중에도 순수하다.
static func _is_valid_scn03_event_outcome(event_id: String, outcome: Dictionary) -> bool:
	var expected := _scn03_expected_outcome_keys(event_id)
	if expected.is_empty() or outcome.size() != expected.size():
		return false
	for key in expected:
		if not outcome.has(key) or not (outcome[key] is bool):
			return false
	for key in outcome:
		if not expected.has(String(key)):
			return false
	# Event 07의 「공동 방어 = 장강 방어선 공동 운용」은 군사협정 없이 성립할 수 없다.
	return event_id != SCN03_EVENT07 or not bool(outcome["yangtze_defense_line"]) \
		or bool(outcome["sun_liu_military_pact"])


func _uses_scn03_progress_rules() -> bool:
	var version := Save._parse_ruleset(world.ruleset)
	return version.size() == 3 and version[0] == 0 and version[1] >= 2


func _uses_scn03_red_cliff_phase_rules() -> bool:
	var version := Save._parse_ruleset(world.ruleset)
	return version.size() == 3 and version[0] == 0 and version[1] >= 3


func _uses_scn03_red_cliff_news_rules() -> bool:
	var version := Save._parse_ruleset(world.ruleset)
	return version.size() == 3 and version[0] == 0 and version[1] >= 4


func _evaluate_scn03_event09_if_ready() -> void:
	if _scn03_event09_evaluated:
		return
	for key in SCN03_RED_CLIFF_CONDITIONS:
		if not scn03_progress.has(key):
			return                         # unknown은 false도, 종료 트리거도 아니다.
	_scn03_event09_evaluated = true
	for key in SCN03_RED_CLIFF_CONDITIONS:
		if not bool(scn03_progress[key]):
			# DEC-01은 마지막 선행 사건 결과가 확정되는 이 전이에만 우선한다.
			ended = true
			end_reason = "DEC-01: 적벽 미발생"
			return
	scenario_event_records[SCN03_EVENT09] = 1
	_ensure_scn03_red_cliff_pending_battle()


## Event 09 success is the sole creation cause for this slice. Participants and roles
## deliberately remain unassembled: no region owner, generic fleet, power ratio, or
## diplomacy heuristic may fill them before the later activation contract exists.
func _ensure_scn03_red_cliff_pending_battle() -> void:
	if int(scenario_event_records.get(SCN03_EVENT09, 0)) != 1:
		return
	for battle in active_battles:
		if battle.battle_id == SCN03_RED_CLIFF_PENDING_BATTLE_ID:
			return
	active_battles.append(ActiveBattle.red_cliff_pending(world.clock.tick,
		SCN03_RED_CLIFF_PENDING_BATTLE_ID, SCN03_EVENT09))
	active_battles.sort_custom(func(a, b): return a.battle_id < b.battle_id)


## 점시점 판정(Orders)에 마지막 단계 2 판독의 신선도를 결합한다 (§12.3).
func observe_fleet(viewer_fid: String, target: Fleet, contact: bool = false) -> Dictionary:
	var live := Orders.observe_fleet(world, data, viewer_fid, target, fleets, contact)
	if int(live.get("stage", 0)) >= 2:
		_record_fleet_reading(viewer_fid, target, live)
		live["freshness"] = "current"
		live["observed_tick"] = world.clock.tick
		live["months_ago"] = 0
		return live
	var readings: Dictionary = _fleet_readings.get(viewer_fid, {})
	var reading: Dictionary = readings.get(target.id, {})
	if reading.is_empty():
		live["freshness"] = "none"
		live["observed_tick"] = -1
		live["months_ago"] = -1
		return live
	var elapsed := maxi(0, world.clock.tick - int(reading["tick"]))
	var months_ago := (elapsed + GameClock.TICKS_PER_MONTH - 1) / GameClock.TICKS_PER_MONTH
	if elapsed <= GameClock.TICKS_PER_MONTH * 3:
		var ghost: Dictionary = reading["observation"].duplicate(true)
		ghost["freshness"] = "current" if elapsed <= GameClock.TICKS_PER_MONTH else "stale"
		ghost["observed_tick"] = int(reading["tick"])
		ghost["months_ago"] = months_ago
		ghost["note"] = "%d개월 전 판독" % months_ago if months_ago > 0 else "현재 판독"
		return ghost
	# 3개월을 넘긴 판독은 단계 1로 강등해 정확 척수·진형·제독을 숨긴다 (§12.3·§12.4).
	var expired: Dictionary = reading["observation"].duplicate(true)
	var band := Orders.ships_band(int(expired["ships_exact"]))
	expired["stage"] = 1
	expired["visible"] = true
	expired["ships_exact"] = 0
	expired["ships_low"] = band[0]
	expired["ships_high"] = band[1]
	expired["formation"] = ""
	expired["commander_name"] = ""
	expired["plan"] = ""
	expired["morale_exact"] = 0
	expired["morale_band"] = ""
	expired["freshness"] = "expired"
	expired["observed_tick"] = int(reading["tick"])
	expired["months_ago"] = months_ago
	expired["note"] = "%d개월 전 판독 — 편성 정보 만료" % months_ago
	return expired


func _record_fleet_reading(viewer_fid: String, target: Fleet, observation: Dictionary) -> void:
	if viewer_fid == "" or target == null or target.owner == viewer_fid:
		return
	if not _fleet_readings.has(viewer_fid):
		_fleet_readings[viewer_fid] = {}
	var snapshot := observation.duplicate(true)
	snapshot.erase("freshness")
	snapshot.erase("observed_tick")
	snapshot.erase("months_ago")
	_fleet_readings[viewer_fid][target.id] = {"tick": world.clock.tick, "observation": snapshot}


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
	_advance_scn03_red_cliff_pending_battle()


## ---------------------------------------------------------------- 내정 (S2.9)
##
## `Sim._deliver_commands` 는 명령을 옮기기만 한다 — 세력을 모르기 때문이다.
## 여기서 **효과가 붙는다.**
func _apply_arrived() -> void:
	for c in world.last_arrived:
		if String(c.get("kind", "")) == CMD_BATTLE_FORMATION_CHANGE:
			var p: Dictionary = c.get("payload", {})
			if String(c.get("origin", "player")) == "player" and p.size() == 4 \
					and Formations.exists_id(String(p.get("target_formation_id", ""))):
				var bid := String(p.get("battle_id", ""))
				if not _battle_formation_commands.has(bid):
					_battle_formation_commands[bid] = []
				var queued: Dictionary = p.duplicate(true)
				queued["seq"] = int(c.get("seq", -1))
				_battle_formation_commands[bid].append(queued)
			else:
				cmds_rejected += 1
			continue
		if String(c.get("kind", "")) == CMD_SCN03_EVENT_OUTCOME:
			var scenario_payload: Dictionary = c.get("payload", {})
			var scenario_outcome: Dictionary = {}
			var raw_scenario_outcome = scenario_payload.get("outcome", {})
			if raw_scenario_outcome is Dictionary:
				scenario_outcome = raw_scenario_outcome
			if String(c.get("origin", "player")) == "player" \
					and raw_scenario_outcome is Dictionary \
					and record_scn03_event_outcome(String(scenario_payload.get("event_id", "")),
							scenario_outcome):
				cmds_applied += 1
			else:
				cmds_rejected += 1
			continue
		if String(c.get("kind", "")) == CMD_SCN03_RED_CLIFF_MANIFEST:
			var manifest_payload: Dictionary = c.get("payload", {})
			if String(c.get("origin", "player")) == "player" \
					and _record_scn03_red_cliff_manifest(manifest_payload):
				cmds_applied += 1
			else:
				cmds_rejected += 1
			continue
		if String(c.get("kind", "")) == CMD_RED_CLIFF_PLAYER_COMMAND:
			var control: Dictionary = c.get("payload", {})
			var control_kind := String(control.get("kind", ""))
			var control_payload: Dictionary = control.get("payload", {})
			var control_battle := _scn03_red_cliff_battle()
			var control_reason := "invalid_origin" if String(c.get("origin", "player")) != "player" else _red_cliff_player_command_reason(control_battle,
				String(control.get("battle_id", "")), control_kind, control_payload)
			if control_reason == "" and control_battle.has_player_command_at_tick(control_kind, world.clock.tick):
				control_reason = "duplicate_command"
			if control_reason != "":
				if control_battle != null:
					control_battle.record_command_feedback(false, control_reason, control_kind,
						world.clock.tick, int(c.get("seq", -1)))
				cmds_rejected += 1
				continue
			var accepted := false
			var command_phase := control_battle.combat_phase
			if control_kind == "hold_formation":
				accepted = not control_battle.ai_delegated
			elif control_kind == "change_formation":
				var target := String(control_payload["target_formation_id"])
				if not control_battle.ai_delegated and Formations.exists_id(target):
					control_battle.attacker_formation_id = target
					accepted = true
			elif control_kind == "advance_phase":
				if not control_battle.ai_delegated and control_battle.combat_phase >= 2:
					accepted = _apply_red_cliff_phase_calculation(control_battle, control_battle.combat_phase, world.clock.tick)
			elif control_kind == "delegate_ai":
				if not control_battle.ai_delegated:
					control_battle.ai_delegated = true
					accepted = true
			if accepted:
				control_battle.record_player_command(control_kind, int(c.get("seq", -1)), world.clock.tick, command_phase)
				control_battle.record_command_feedback(true, "applied", control_kind,
					world.clock.tick, int(c.get("seq", -1)))
				cmds_applied += 1
				_apply_red_cliff_result_once(control_battle)
			else:
				control_battle.record_command_feedback(false, "rejected_by_reducer", control_kind,
					world.clock.tick, int(c.get("seq", -1)))
				cmds_rejected += 1
			continue
		if String(c.get("kind", "")) == CMD_SCN03_RED_CLIFF_RESULT:
			var result_payload: Dictionary = c.get("payload", {})
			var battle := _scn03_red_cliff_battle()
			if String(c.get("origin", "player")) == "player" \
					and _uses_scn03_red_cliff_phase_rules() \
					and _is_valid_scn03_red_cliff_result_payload(result_payload) \
					and battle != null \
					and battle.resolve_red_cliff(String(result_payload["winner_faction_id"]), world.clock.tick):
				cmds_applied += 1
				_record_scn03_red_cliff_transition_news(battle,
					SCN03_RED_CLIFF_TRANSITION_RESOLVED, world.clock.tick)
			else:
				cmds_rejected += 1
			continue
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
			world.clock.tick, world.graph)   # graph — 함대이동 판정 (Orders.resolve_move)
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
	# ── 자동 저장 — 로그 플러시 지점 (save-contract §3.4) ──────────────────
	# 월 정산마다 명령 로그를 디스크로 flush 하고, 시나리오 경계에서 스냅숏.
	# A-01 은 이 **지점만** 표식한다 — 실제 플러시 호출·주기·슬롯·경계 스냅숏은
	# C-03(S3.8). 클라이언트가 이 시점에 `write_save(slot_path)` 를 부른다.
	# ─────────────────────────────────────────────────────────────────────
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
	# origin="ai" — 재생 중 step() 이 결정론적으로 재발행하므로 저장 로그엔 안 남는다
	# (save-contract 전제 2 · A-01 조율).
	if kind == Domestic.CMD_TECH or kind == Domestic.CMD_BUILD:
		world.issue(kind, payload, 0, "ai")
	elif payload.has("region"):
		world.capital = f.capital_system
		if world.issue_to(kind, String(payload["region"]), payload, "ai").is_empty():
			cmds_rejected += 1                   # 회랑이 끊겨 명령이 가지 못했다
	else:
		world.issue(kind, payload, 0, "ai")
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
		fl.departure_tick = -1
		fl.at_system = data.system_of(rid)
		fl.target_region = ""
		# The approved manifest's required fleet is arriving for the one persistent
		# Red-Cliffs battle, not entering the generic immediate-resolution path.
		# No other battle or unlisted fleet changes behaviour here.
		if _is_red_cliff_pending_arrival_fleet(fl):
			continue
		var st: RegionState = world.region_states[rid]
		if st.owner == fl.owner or st.owner == "":
			_capture(fl.owner, rid)
		else:
			_resolve_battle(fl, rid)


func _is_red_cliff_pending_arrival_fleet(fleet: Fleet) -> bool:
	if scn03_red_cliff_manifest.is_empty() or fleet.at_system != ActiveBattle.RED_CLIFF_SYSTEM_ID:
		return false
	for battle in active_battles:
		if battle.battle_id != SCN03_RED_CLIFF_PENDING_BATTLE_ID \
				or battle.status != ActiveBattle.STATUS_PENDING:
			continue
		for key in ["cao_fleet_ids", "sun_liu_fleet_ids"]:
			if scn03_red_cliff_manifest.get(key, []).has(fleet.id):
				return true
	return false


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
	var battle_id := att.encounter_battle_id
	var terrain := att.encounter_terrain
	if terrain == "":
		terrain = "개활"
	var attacker_formation_id := Formations.effective_formation_id(
		Formations.id_for_name(att.formation), att.command, att.staff_traits, terrain)
	var defender_formation_id := Formations.effective_formation_id(
		Formations.id_for_name(defs[0].formation), def_command, defs[0].staff_traits, terrain)
	var formation_used: Dictionary = {}
	var formation_penalty: Dictionary = {}
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
		var next_phase := phase + 1
		var a_change := _apply_battle_formation_change(battle_id, next_phase, att,
			attacker_formation_id, terrain, formation_used)
		attacker_formation_id = String(a_change["formation_id"])
		formation_penalty["att"] = int(a_change["penalty_milli"])
		var b_change := _apply_battle_formation_change(battle_id, next_phase, defs[0],
			defender_formation_id, terrain, formation_used)
		defender_formation_id = String(b_change["formation_id"])
		formation_penalty["def"] = int(b_change["penalty_milli"])
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
		var a_ship_coeff := Battle.formation_adjusted_ship_coefficient_milli(1000,
			attacker_formation_id, defender_formation_id, phase, att.command,
			att.staff_traits, terrain)
		var b_ship_coeff := Battle.formation_adjusted_ship_coefficient_milli(1000,
			defender_formation_id, attacker_formation_id, phase, def_command,
			defs[0].staff_traits, terrain)
		a_ship_coeff = a_ship_coeff * int(formation_penalty.get("att", 1000)) / 1000
		b_ship_coeff = b_ship_coeff * int(formation_penalty.get("def", 1000)) / 1000

		var pa := Battle.combat_power_milli(att.ships, a_ship_coeff, a_stat, phase,
			att.morale, 1000, a_tech, a_corr)
		var pb := Battle.combat_power_milli(def_ships, b_ship_coeff, b_stat, phase,
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
	_battle_formation_commands.erase(battle_id)
	att.encounter_terrain = ""
	att.encounter_battle_id = ""


func _apply_battle_formation_change(battle_id: String, next_phase: int, fleet: Fleet,
		current_id: String, terrain: String, used: Dictionary) -> Dictionary:
	var out := {"formation_id": current_id, "penalty_milli": 1000}
	if battle_id == "" or not _battle_formation_commands.has(battle_id):
		return out
	for command in _battle_formation_commands[battle_id]:
		if int(command.get("next_phase", -1)) != next_phase or int(command.get("fleet_id", -1)) != fleet.id:
			continue
		var result := {"battle_id": battle_id, "next_phase": next_phase, "fleet_id": fleet.id,
			"target_formation_id": String(command.get("target_formation_id", "")), "seq": int(command.get("seq", -1))}
		if used.has(fleet.id):
			result["status"] = "rejected_duplicate"
			battle_formation_results.append(result)
			continue
		var target := String(command.get("target_formation_id", ""))
		if not Formations.exists_id(target) or Formations.forced_formation(terrain) != "" \
				or not Formations.allowed_in(Formations.name_for_id(target), terrain):
			result["status"] = "rejected_illegal"
			battle_formation_results.append(result)
			continue
		used[fleet.id] = true
		if target == Formations.PALJIN_ID and fleet.command >= 90 and Formations.has_paljin_trait(fleet.staff_traits):
			out["formation_id"] = target
			result["status"] = "applied"
		elif fleet.command >= Formations.required_command(Formations.name_for_id(target)):
			out["formation_id"] = target
			result["status"] = "applied"
		else:
			out["penalty_milli"] = 800
			result["status"] = "failed_command"
		battle_formation_results.append(result)
	return out


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
		# **플레이어 함대는 AI 가 움직이지 않는다** (`screens.md` 검토 25).
		# `_ai_domestic` 은 이미 거른다 — Operational 만 빠져 있었다. M0 은 AI 대 AI 라
		# `player_faction` 이 "" 이므로 이 가드는 무연산이고, 클라이언트에서만 문다.
		# 이게 없으면 `SC-F1` 의 [이동]·[분할] 발행이 다음 주기에 덮인다 (요구 B7·§1 비차단).
		if fid == world.player_faction:
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
			# **AI 이동도 명령 로그를 지난다** (A-03 · save-contract 전제 2).
			# 경로·소요 판정은 도달 시 `Orders.resolve_move` 가 낸다 — 여기서는
			# 목적 권역만 싣는다. 닿지 않으면 지금 걸러 발행하지 않는다(기존 동작 유지).
			# origin="ai" 라 저장 로그엔 안 남고 재생이 재발행한다.
			if not bool(Orders.resolve_move(world.graph, data, fl.at_system,
					String(pick["region"]))["ok"]):
				continue
			world.issue(Domestic.CMD_FLEET_MOVE, {
				"faction": fid, "fleet": fl.id, "region": String(pick["region"]),
			}, 0, "ai")
			dispatched += 1


## ---------------------------------------------------------------- 종료 판정
func _check_end() -> void:
	# 마지막 SCN-03 선행 결과가 DEC-01을 세운 같은 전이에서는 이를 덮어쓰지 않는다.
	if ended:
		return
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


## ================================================================ 캠페인 저장·복원
##
## **저장 = 「시드 + 플레이어 명령 로그」다** (save-contract.md §2 · V-62 · V-25 ③).
## 세력·함대·경제·외교·이벤트·전투 결과는 담지 않는다 — 셋업(`scenario_03`)의
## 확정 초기값에서 명령·AI·정산의 결정론적 함수로 **재생 때 다시 만들어진다** (§2.2).
##
## `Save.replay` 는 `World` 만 만든다 (시간 + 명령 로그 + 전화 계수). 경제·전투·외교·
## 이벤트는 이 `Campaign` 계층에 있으므로, 여기서 **셋업부터 목표 틱까지 다시 도는
## 경로**를 따로 세운다 (§1.3 결손 ①).


## 캠페인 지문. **저장 전과 재생 후가 같아야 한다** (§4.2 조건 1·2).
##
## 순회는 **정렬된 ID·쌍·키로만** 한다 (§4.3 · data-model.md §2.3 — Dictionary
## 순회 금지). 진단 계수(`schemes_tried` · `ambush_by_*` · `skip_*` 등)는 접지
## 않는다 (§4.3 제외) — 세계 상태가 아니라 계측이고, 밸런스 조정 때마다 바뀌어
## 인수 시험을 깨뜨린다. AI 명령의 순번·부기도 접지 않는다 — 파생이며, 그
## 효과는 아래 세력·함대·권역·외교·이벤트 상태로 이미 접힌다.
static func _scn03_red_cliff_manifest_digest_values(raw_payload) -> Array:
	if not raw_payload is Dictionary or not _is_valid_scn03_red_cliff_manifest_payload(raw_payload):
		return [Rng._hash_string("invalid_scn03_red_cliff_manifest")]
	var manifest := _canonical_manifest_for_digest(raw_payload)
	var values: Array = [Rng._hash_string(String(manifest["liu_contingent_id"]))]
	for key in ["cao_fleet_ids", "sun_liu_fleet_ids"]:
		var ids: Array = manifest[key]
		values.append(ids.size())
		for fleet_id in ids:
			values.append(int(fleet_id))
	var role_keys: Array = manifest["fleet_roles"].keys()
	role_keys.sort()
	for role_key in role_keys:
		values.append(Rng._hash_string(String(role_key)))
		values.append(Rng._hash_string(String(manifest["fleet_roles"][role_key])))
	return values


static func _canonical_manifest_for_digest(payload: Dictionary) -> Dictionary:
	var cao_ids: Array = payload["cao_fleet_ids"].duplicate()
	var sun_ids: Array = payload["sun_liu_fleet_ids"].duplicate()
	cao_ids.sort()
	sun_ids.sort()
	return {
		"cao_fleet_ids": cao_ids,
		"sun_liu_fleet_ids": sun_ids,
		"fleet_roles": payload["fleet_roles"].duplicate(true),
		"liu_contingent_id": String(payload["liu_contingent_id"]),
	}


func digest() -> int:
	var h := 0
	# ── 시간 · 규칙 · 외생 입력 ──────────────────────────────────────────
	h = Save._fold(h, world.clock.tick)
	h = Save._fold(h, world.tick_count)
	h = Save._fold(h, world.rng_seed)
	h = Save._fold(h, Rng._hash_string(world.ruleset + "|" + world.scenario))
	h = Save._fold(h, hb_milli)
	h = Save._fold(h, 1 if ai_domestic_enabled else 0)
	h = Save._fold(h, 1 if ended else 0)
	h = Save._fold(h, Rng._hash_string(end_reason))
	# ── 플레이어 명령 (origin != "ai" 만) ───────────────────────────────
	var pcmds: Array = []
	for c in world.applied_commands:
		if String(c.get("origin", "player")) != "ai":
			pcmds.append(c)
	for c in world.pending_commands:
		if String(c.get("origin", "player")) != "ai":
			pcmds.append(c)
	pcmds.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
	h = Save._fold(h, pcmds.size())
	for c in pcmds:
		h = Save._fold(h, int(c["seq"]))
		h = Save._fold(h, int(c["arrival_tick"]))
		h = Save._fold(h, Rng._hash_string(String(c["kind"])))
		# RS-0.2의 발행 tick은 replay staging의 입력이고, scenario outcome payload는
		# 아직 reducer가 만들지 않은 pending 상태에서도 플레이어 정본이다. 기존
		# RS-0.1 지문은 이 필드들을 접지 않아 과거 저장을 그대로 재생한다.
		if _uses_scn03_progress_rules():
			h = Save._fold(h, int(c["issued_tick"]))
			if String(c["kind"]) == CMD_SCN03_EVENT_OUTCOME:
				var command_payload: Dictionary = c.get("payload", {})
				var command_event_id := String(command_payload.get("event_id", ""))
				h = Save._fold(h, Rng._hash_string(command_event_id))
				var command_outcome: Dictionary = command_payload.get("outcome", {})
				for key in _scn03_expected_outcome_keys(command_event_id):
					h = Save._fold(h, 1 if bool(command_outcome.get(key, false)) else 0)
			elif String(c["kind"]) == CMD_SCN03_RED_CLIFF_MANIFEST:
				for value in _scn03_red_cliff_manifest_digest_values(c.get("payload", {})):
					h = Save._fold(h, value)
			elif String(c["kind"]) == CMD_SCN03_RED_CLIFF_RESULT:
				var result_payload: Dictionary = c.get("payload", {})
				h = Save._fold(h, Rng._hash_string(String(result_payload.get("battle_id", ""))))
				h = Save._fold(h, int(result_payload.get("phase", -1)))
				h = Save._fold(h, Rng._hash_string(String(result_payload.get("winner_faction_id", ""))))
			elif String(c["kind"]) == CMD_RED_CLIFF_PLAYER_COMMAND:
				var control_payload: Dictionary = c.get("payload", {})
				h = Save._fold(h, Rng._hash_string(String(control_payload.get("battle_id", ""))))
				h = Save._fold(h, Rng._hash_string(String(control_payload.get("kind", ""))))
				var nested: Dictionary = control_payload.get("payload", {})
				h = Save._fold(h, Rng._hash_string(String(nested.get("target_formation_id", ""))))
			elif String(c["kind"]) == CMD_BATTLE_FORMATION_CHANGE:
				var formation_payload: Dictionary = c.get("payload", {})
				h = Save._fold(h, Rng._hash_string(String(formation_payload.get("battle_id", ""))))
				h = Save._fold(h, int(formation_payload.get("next_phase", -1)))
				h = Save._fold(h, int(formation_payload.get("fleet_id", -1)))
				h = Save._fold(h, Rng._hash_string(String(formation_payload.get("target_formation_id", ""))))
	# ── 세력 (정렬된 faction_ids) ──────────────────────────────────────
	for fid in faction_ids:
		var f: Faction = factions[fid]
		h = Save._fold(h, Rng._hash_string(fid))
		h = Save._fold(h, 1 if f.alive else 0)
		h = Save._fold(h, f.treasury)
		h = Save._fold(h, f.mandate)
		h = Save._fold(h, f.hegemony)
		h = Save._fold(h, f.months_idle)
		h = Save._fold(h, 1 if f.has_emperor else 0)
		h = Save._fold(h, 1 if f.wandering else 0)
		for axis in Tech.AXES:
			h = Save._fold(h, int(f.tech.get(axis, 0)))
		h = Save._fold(h, Rng._hash_string(String(f.tech_research.get("axis", ""))))
		h = Save._fold(h, int(f.tech_research.get("done_tick", 0)))
		var vs: Array = f.violations.duplicate()
		vs.sort()
		h = Save._fold(h, Rng._hash_string("|".join(vs)))
		h = Save._fold(h, f.regions.size())            # Faction.regions 는 정렬 유지
		h = Save._fold(h, Rng._hash_string("|".join(f.regions)))
	# ── 권역 (정렬된 region_ids) ──────────────────────────────────────
	for rid in data.region_ids:
		var st: RegionState = world.region_states.get(rid)
		if st == null:
			continue
		h = Save._fold(h, st.war_damage_milli)
		h = Save._fold(h, st.development)
		h = Save._fold(h, st.garrison)
		h = Save._fold(h, st.recovery_investment)
		h = Save._fold(h, Rng._hash_string(st.owner))
		h = Save._fold(h, st.stability)
		h = Save._fold(h, st.stability_initial)
		h = Save._fold(h, st.acquired_tick)
		h = Save._fold(h, Rng._hash_string(st.acquired_by))
		h = Save._fold(h, 1 if st.delegated else 0)
		h = Save._fold(h, 1 if st.contested else 0)
		h = Save._fold(h, 1 if st.pacified else 0)
	# ── 함대 (id 오름차순) ────────────────────────────────────────────
	var fl_sorted: Array = fleets.duplicate()
	fl_sorted.sort_custom(func(a, b): return a.id < b.id)
	h = Save._fold(h, fl_sorted.size())
	for fl in fl_sorted:
		h = Save._fold(h, fl.id)
		h = Save._fold(h, Rng._hash_string(fl.owner))
		h = Save._fold(h, Rng._hash_string(fl.at_system))
		h = Save._fold(h, Rng._hash_string(fl.target_region))
		h = Save._fold(h, fl.departure_tick)
		h = Save._fold(h, fl.arrival_tick)
		h = Save._fold(h, Rng._hash_string(fl.encounter_terrain))
		h = Save._fold(h, Rng._hash_string(fl.encounter_battle_id))
		h = Save._fold(h, fl.ships)
		h = Save._fold(h, fl.morale)
		h = Save._fold(h, fl.drill)
		h = Save._fold(h, 1 if fl.drilling else 0)
		h = Save._fold(h, fl.squadron_command)
		h = Save._fold(h, Rng._hash_string(fl.formation))
		h = Save._fold(h, Rng._hash_string(fl.plan))
		h = Save._fold(h, Rng._hash_string(fl.station))
		h = Save._fold(h, Rng._hash_string(fl.commander_id))
		h = Save._fold(h, Rng._hash_string(fl.vice_id))
		h = Save._fold(h, Rng._hash_string(fl.assault_id))
		h = Save._fold(h, Rng._hash_string(fl.siege_id))
		h = Save._fold(h, Rng._hash_string(fl.supply_id))
	# ── 외교 (정렬된 세력 쌍) ─────────────────────────────────────────
	for i in faction_ids.size():
		for j in range(i + 1, faction_ids.size()):
			var a: String = faction_ids[i]
			var b: String = faction_ids[j]
			h = Save._fold(h, Rng._hash_string(Diplomacy.key(a, b)))
			h = Save._fold(h, diplo.tier_of(a, b))
			h = Save._fold(h, diplo.trust_of(a, b))
			h = Save._fold(h, diplo.betrayal_count(a, b))
	# ── 이벤트 (정렬된 ID) ───────────────────────────────────────────
	var eids: Array = events_fired.keys()
	eids.sort()
	for eid in eids:
		h = Save._fold(h, Rng._hash_string(String(eid)))
		h = Save._fold(h, int(events_fired[eid]))
	# RS-0.2부터 서사 진행은 전투·UI 파생값이 아닌 결정론적 게임 상태다. unknown도
	# 접는다. RS-0.1 저장은 이 필드가 존재하기 전 지문 알고리즘을 그대로 유지한다.
	if _uses_scn03_progress_rules():
		for key in SCN03_RED_CLIFF_CONDITIONS:
			h = Save._fold(h, Rng._hash_string(key))
			h = Save._fold(h, 0 if not scn03_progress.has(key) else 1)
			h = Save._fold(h, 1 if bool(scn03_progress.get(key, false)) else 0)
		h = Save._fold(h, 1 if _scn03_event09_evaluated else 0)
		var scenario_event_ids: Array = scenario_event_records.keys()
		scenario_event_ids.sort()
		for event_id in scenario_event_ids:
			h = Save._fold(h, Rng._hash_string(String(event_id)))
			h = Save._fold(h, int(scenario_event_records[event_id]))
		# Active battles are derived gameplay state in RS-0.2, not save snapshots.
		# Fold their normalized pending contract so replay omissions are observable.
		var sorted_active_battles: Array[ActiveBattle] = active_battles.duplicate()
		sorted_active_battles.sort_custom(func(a, b): return a.battle_id < b.battle_id)
		h = Save._fold(h, sorted_active_battles.size())
		for battle in sorted_active_battles:
			for value in battle.digest_values():
				h = Save._fold(h, value)
		if _uses_scn03_red_cliff_news_rules():
			var transition_news := scn03_red_cliff_transition_news.duplicate()
			transition_news.sort_custom(
				func(a, b): return String(a.get("news_id", "")) < String(b.get("news_id", "")))
			h = Save._fold(h, transition_news.size())
			for record in transition_news:
				h = Save._fold(h, Rng._hash_string(String(record.get("news_id", ""))))
				h = Save._fold(h, Rng._hash_string(String(record.get("battle_id", ""))))
				h = Save._fold(h, Rng._hash_string(String(record.get("transition", ""))))
				h = Save._fold(h, int(record.get("tick", -1)))
	var formation_results := battle_formation_results.duplicate()
	formation_results.sort_custom(func(a, b): return int(a.get("seq", -1)) < int(b.get("seq", -1)))
	h = Save._fold(h, formation_results.size())
	for record in formation_results:
		for key in ["battle_id", "next_phase", "fleet_id", "target_formation_id", "seq", "status"]:
			var value = record.get(key, "")
			h = Save._fold(h, value if value is int else Rng._hash_string(String(value)))
	var ck: Array = _event_cooldown.keys()      # 재발동 쿨다운 (§1.2)
	ck.sort()
	for k in ck:
		h = Save._fold(h, Rng._hash_string(String(k)))
		h = Save._fold(h, int(_event_cooldown[k]))
	var ak: Array = _alliance_since.keys()       # 동맹 성립 시각 (§4.3)
	ak.sort()
	for k in ak:
		h = Save._fold(h, Rng._hash_string(String(k)))
		h = Save._fold(h, int(_alliance_since[k]))
	# JSON 숫자는 IEEE-754 경로를 지날 수 있다. 64비트 해시를 그대로 저장하면
	# 파일 왕복 때 하위 비트가 유실되므로 플랫폼 독립적인 양의 31비트로 고정한다.
	return h & 0x7fffffff


## 캠페인 세이브 사전 (schema/save-campaign.json).
func to_save_dict() -> Dictionary:
	return {
		"save_version": SAVE_CAMPAIGN_VERSION,
		"world": Save.to_dict(world),        # origin != "ai" 명령만 · save_version 없음
		"campaign": {
			"hb_milli": hb_milli,             # 외생 입력 — 시드로 유도되지 않는다
			"ai_domestic_enabled": ai_domestic_enabled,
			"digest": digest(),              # 저장 시점 지문 — 재생 후와 대조 (§4.2)
			# 종료 상태 — `_check_end` 의 자연 종료는 재생이 다시 만들지만,
			# `run_to_end` 가 max_ticks 에서 강제한 「정규 종료」는 재생 루프
			# (`replay_to`)가 재현하지 않는다. 세이브가 「끝났는가」의 정본이다.
			"ended": ended,
			"end_reason": end_reason,
		},
	}


## 캠페인 세이브 사전에서 캠페인을 되살린다.
##
## **셋업부터 목표 틱까지 다시 돌린다** (§3.1 순수 로그 재생). `scenario_03(seed)` 로
## 결정론적 초기 상태를 세우고, 저장된 플레이어 명령(origin != "ai")을 발행 틱에 맞춰
## 명령 대기열에 주입한 뒤 목표 틱까지 `step()` 을 반복한다. AI 명령·전투·이벤트·경제는 재생 중
## 시드에서 다시 만들어진다 (§2.2 파생).
##
## ⚠ 단기판은 `SCN-03` 하나뿐이다 (CLAUDE.md 함정 · save-contract §3). 다른 시나리오
## 경계 스냅숏은 이 세션 범위 밖 (§3.4 · A-01 실측 후 판정).
static func _from_clean_save(d: Dictionary, data_ref: GameData) -> Campaign:
	var w: Dictionary = d.get("world", {})
	var scn := String(w.get("scenario", "SCN-03"))
	assert(scn == "SCN-03", "단기판은 SCN-03 하나뿐이다 (save-contract §3)")
	var cd: Dictionary = d.get("campaign", {})

	var c := Campaign.scenario_03(data_ref, int(w.get("seed", 0)))
	c.hb_milli = int(cd.get("hb_milli", Strategy.HB_STANDARD_MILLI))
	c.ai_domestic_enabled = bool(cd.get("ai_domestic_enabled", true))
	c.world.ruleset = String(w.get("ruleset", c.world.ruleset))
	c.world.player_faction = String(w.get("player_faction", ""))

	# 플레이어 명령은 발행 틱에 stage한다. 전부를 미리 pending에 넣으면 zero-delay
	# 입력이 라이브보다 한 tick 일찍 도달한다. AI 명령은 직렬화에서 제외됐으므로 여기 없다.
	var cmds: Array = w.get("commands", [])
	var sorted_cmds: Array = cmds.duplicate()
	sorted_cmds.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
	var max_seq := -1
	for cm in sorted_cmds:
		c._replay_player_commands.append({
			"seq": int(cm["seq"]),
			"issued_tick": int(cm["issued_tick"]),
			"arrival_tick": int(cm.get("arrival_tick", cm["issued_tick"])),
			"kind": String(cm["kind"]),
			"payload": cm.get("payload", {}),
			"origin": String(cm.get("origin", "player")),
		})
		max_seq = maxi(max_seq, int(cm["seq"]))
	# 재생 중 새로 발행되는 AI 명령이 주입분과 순번 충돌하지 않게 (save.gd `replay` 와 동일).
	c.world._seq = maxi(c.world._seq, max_seq + 1)

	c.replay_to(int(w.get("game_tick", 0)))

	# 종료 상태 복원 — `replay_to` 는 `run_to_end` 처럼 max_ticks 에서 종료를
	# 강제하지 않는다. 세이브가 「끝났다」고 하면 그대로 맞춘다. 자연 종료는
	# 재생이 이미 같은 틱에 같은 사유로 세워 두므로 이 대입이 무연산이다.
	if bool(cd.get("ended", false)) and not c.ended:
		c.ended = true
		c.end_reason = String(cd.get("end_reason", "정규 종료"))
	return c


## 검사와 재생을 합친 호출자용 결과. `Save.inspect` 가 로드 가부·복구 범위를,
## 이 함수가 재생 지문 검증을 맡는다 (§3.2·§3.5).
static func from_save_result(d: Dictionary, data_ref: GameData,
		current_ruleset: String = Save.CURRENT_RULESET) -> Dictionary:
	var result := Save.inspect(d, current_ruleset)
	if not bool(result["loadable"]):
		result["campaign"] = null
		return result
	var c := _from_clean_save(result["save"], data_ref)
	var expected := int(result["save"]["campaign"]["digest"])
	var actual := c.digest()
	result["campaign"] = c
	result["expected_digest"] = expected
	result["actual_digest"] = actual
	result["verified"] = actual == expected
	if actual != expected and String(result["status"]) != Save.STATUS_PARTIAL_RECOVERY:
		result["status"] = Save.STATUS_VERIFICATION_FAILED
		result["detail"] = "재생 지문이 저장 지문과 다르다 — 검증 실패 표식"
	return result


## 기존 정상 호출부 호환. 거부된 저장은 null을 돌려준다.
static func from_save(d: Dictionary, data_ref: GameData) -> Campaign:
	return from_save_result(d, data_ref).get("campaign")


## 목표 틱까지 재생한다. `run_to_end` 와 달리 **`ended` 를 강제하지 않는다** —
## 캠페인 도중에 저장한 세이브(§4.2 조건 4)는 목표 틱이 종료 틱이 아닐 수 있다.
func replay_to(target_tick: int) -> void:
	while not ended and world.clock.tick < target_tick:
		step()
	# 마지막 step 직후 발행되어 저장 시점에는 pending이던 입력도 같은 상태로 남긴다.
	_stage_replay_player_commands()


## 캠페인 세이브를 파일로 쓴다 (schema/save-campaign.json).
func write_save(path: String) -> bool:
	return Save.write_dict(to_save_dict(), path)


## 캠페인 세이브 파일에서 되살린다. 파일·스키마·규칙 판정은 `Save.inspect_file`,
## 재생 지문 판정은 `from_save_result` 가 맡는다 (§3.2·§3.5).
static func read_save_result(path: String, data_ref: GameData,
		current_ruleset: String = Save.CURRENT_RULESET) -> Dictionary:
	var inspected := Save.inspect_file(path, current_ruleset)
	if not bool(inspected["loadable"]):
		inspected["campaign"] = null
		return inspected
	return from_save_result(inspected["save"], data_ref, current_ruleset)


static func read_save(path: String, data_ref: GameData) -> Campaign:
	return read_save_result(path, data_ref).get("campaign")
