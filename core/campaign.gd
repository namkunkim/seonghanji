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
var cmds_applied: int = 0
var cmds_rejected: int = 0

var ended: bool = false
var end_reason: String = ""
var battles: int = 0
var captures: int = 0


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
	fleets.append(fl)
	return fl


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
	_check_end()


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
		f.treasury += inc - adm - flt - drl - rec
		if f.treasury < 0:
			_austerity(f)
		Domestic.tech_tick(f, world.clock.tick)


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

	for phase in 5:
		var pa := Battle.combat_power_milli(att.ships, 1000, att.command, phase,
			att.morale, 1000, 1000, corridor)
		var pb := Battle.combat_power_milli(def_ships, 1000, def_command, phase,
			def_morale, 1000, 1000, corridor)
		var la := Battle.loss_rate_milli(phase, pa, pb)
		var lb := Battle.loss_rate_milli(phase, pb, pa)
		att.ships = maxi(0, att.ships - att.ships * la / 100000)
		def_ships = maxi(0, def_ships - def_ships * lb / 100000)
		att.morale = maxi(0, att.morale + Battle.morale_delta(phase, pa, pb))
		def_morale = maxi(0, def_morale + Battle.morale_delta(phase, pb, pa))
		# 붕괴 — **패주가 정상적인 지는 방식이다** (§1)
		if rng.chance(Battle.collapse_chance_pct(att.morale, att.command)):
			_retreat(att)
			_apply_losses(defs, def_ships, def_morale)
			return
		if rng.chance(Battle.collapse_chance_pct(def_morale, def_command)):
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
	if st.owner != "" and factions.has(st.owner):
		factions[st.owner].remove_region(rid)
	st.owner = owner
	st.acquired_tick = world.clock.tick
	st.acquired_by = "정복"
	if factions.has(owner):
		factions[owner].add_region(rid)


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
			# **서로 인접해야 한다.** 군사동맹의 알맹이는 참전 의무(§5.1)이고,
			# 참전하려면 함대가 닿아야 한다. 요동과 교주가 맺는 동맹은 종이다.
			# **손유 동맹이 정확히 이 조건을 만족한다** — 오회와 형주는
			# 장강 대항로로 이어져 있다.
			if not _factions_adjacent(a, b):
				continue
			if diplo.accepts(a, b, int(pa[1]), int(pb[1])):
				var before := diplo.tier_of(a, b)
				var after := diplo.escalate(a, b)
				if after > before and after == Diplomacy.Tier.군사동맹:
					alliances_formed += 1


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
		# **확률적 선정 + 역사 편향** (§6.2 · §11.1)
		# 최고점을 그냥 고르면 시드가 달라도 같은 판이 나온다.
		var pick := Strategy.choose_weighted(ranked, world.rng(Rng.DOMAIN_AI),
			data, world.scenario, fid, hb_milli)
		if pick.is_empty():
			continue
		var fl: Fleet = idle[idle.size() - 1]
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
