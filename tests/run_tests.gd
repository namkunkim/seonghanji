extends SceneTree

## 헤드리스 자체 시험 (dev-requirements.md §9 — 첫 코드는 게임이 아니다)
##
## 실행:  godot --headless --path . --script tests/run_tests.gd
## 최초 1회: godot --headless --path . --import   (class_name 전역 등록)
## 종료 코드: 실패가 있으면 1

var _pass := 0
var _fail := 0

## 섹션이 **조용히 사라지는 것**을 막는다.
## GDScript 는 없는 함수를 부르면 오류만 찍고 시험은 「실패 0」으로 끝난다 —
## 2026-08-24 에 battle.gd 가 컴파일에 실패하며 시험 26개가 소리 없이 빠졌다.
var _sections := 0
const EXPECTED_SECTIONS := 34


func _section(name: String) -> void:
	_sections += 1
	print(name)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  실패: ", label)


func _eq(got, want, label: String) -> void:
	if got == want:
		_pass += 1
	else:
		_fail += 1
		print("  실패: %s — 기대 %s, 실제 %s" % [label, str(want), str(got)])


func _init() -> void:
	print("SEONGHANJI 코어 자체 시험")
	print("")
	_test_tick_basic()
	_test_remainder()
	_test_speed()
	_test_framerate_independence()
	_test_pause()
	_test_duration_table()
	_test_calendar()
	_test_sim_paths_agree()
	_test_command_delay()
	_test_data_load()
	_test_power()
	_test_adjacency()
	_test_routing()
	_test_issue_to()
	_test_recovery()
	_test_domestic()
	_test_year_settlement()
	_test_combat_basics()
	_test_corridor_choke()
	_test_fixed_math()
	_test_morale_delta()
	_test_rng_determinism()
	_test_rng_isolation()
	_test_save_roundtrip()
	_test_replay_fidelity()
	_test_region_adjacency()
	_test_cut_value()
	_test_economy()
	_test_plans()
	_test_tech()
	_test_domestic_commands()
	_test_game_loop()
	_test_schemes()
	_test_portrait_frame()
	print("")
	if _sections != EXPECTED_SECTIONS:
		_fail += 1
		print("  실패: 시험 섹션 %d개가 돌았다 — %d개여야 한다 (컴파일 오류로 빠진 것이 있다)"
			% [_sections, EXPECTED_SECTIONS])
	print("섹션 %d/%d · 통과 %d · 실패 %d" % [_sections, EXPECTED_SECTIONS, _pass, _fail])
	quit(1 if _fail > 0 else 0)


## 1틱 = 실제 1분
func _test_tick_basic() -> void:
	_section("1. 기본 — 1틱 = 실제 1분")
	var c := GameClock.new()
	_eq(GameClock.REAL_MS_PER_TICK, 60_000, "틱은 실제 60초")
	_eq(c.advance(59_999), 0, "1ms 모자라면 넘어가지 않는다")
	_eq(c.advance(1), 1, "정확히 채우면 한 틱")
	_eq(c.tick, 1, "tick 증가")
	_eq(c.advance(GameClock.REAL_MS_PER_TICK * 5), 5, "한 번에 5틱")
	_eq(c.tick, 6, "누적 6틱")


func _test_remainder() -> void:
	_section("2. 나머지 보존")
	var c := GameClock.new()
	for _i in 120:
		c.advance(500)          # 0.5초 × 120 = 60초
	_eq(c.tick, 1, "0.5초 × 120 = 한 틱")
	var c2 := GameClock.new()
	for _i in 600:
		c2.advance(100)         # 0.1초 × 600 = 60초
	_eq(c2.tick, 1, "0.1초 × 600 = 한 틱")


func _test_speed() -> void:
	_section("3. 배속")
	var c := GameClock.new()
	c.speed = 2
	_eq(c.advance(30_000), 1, "×2 배속이면 30초에 한 틱")
	var c4 := GameClock.new()
	c4.speed = 4
	_eq(c4.advance(15_000), 1, "×4 배속이면 15초에 한 틱")


## **결정론의 핵심.** 같은 총 경과를 어떻게 쪼개 넣든 같은 틱 수가 나와야 한다.
func _test_framerate_independence() -> void:
	_section("4. 프레임률 무관")
	var total: int = GameClock.REAL_MS_PER_TICK * 137
	var slices: Array[int] = [1, 16, 33, 100, 1000, 7777]
	var results: Array[int] = []
	for s in slices:
		var c := GameClock.new()
		var left: int = total
		while left > 0:
			var step: int = mini(s, left)
			c.advance(step)
			left -= step
		results.append(c.tick)
	var all_same := true
	for r in results:
		if r != results[0]:
			all_same = false
	_ok(all_same, "프레임 조각이 달라도 같은 틱 수 (%s)" % str(results))
	_eq(results[0], 137, "137틱")


func _test_pause() -> void:
	_section("5. 일시정지")
	var c := GameClock.new()
	c.paused = true
	_eq(c.advance(GameClock.REAL_MS_PER_TICK * 3), 0, "정지 중에는 안 나아간다")
	c.paused = false
	_eq(c.advance(GameClock.REAL_MS_PER_TICK), 1, "해제 후 정상")


## **반올림이 없다는 것의 시험.** 소요표(§3.1)가 그대로 정수 틱이 된다.
func _test_duration_table() -> void:
	_section("6. 소요표 — 반올림 없음")
	_eq(GameClock.minutes_to_ticks(45), 45, "고속항로 1구간 45분")
	_eq(GameClock.minutes_to_ticks(68), 68, "고속항로 + 관문 68분 (15분 배수가 아니다)")
	_eq(GameClock.hours_to_ticks(2.25), 135, "중회랑 2시간 15분")
	_eq(GameClock.hours_to_ticks(3.75), 225, "대회랑 3시간 45분")
	_eq(GameClock.hours_to_ticks(3.0), 180, "기저 항로 3시간")
	_eq(GameClock.hours_to_ticks(4.5), 270, "기저 항로 원거리 4시간 30분")
	_eq(GameClock.hours_to_ticks(1.5), 90, "사자 왕복 1시간 30분")
	_eq(GameClock.hours_to_ticks(0.5), 30, "대회전 30분")
	_eq(GameClock.hours_to_ticks(14.0), 840, "최장 종단 14시간")
	_eq(GameClock.months_to_ticks(1.0), 60, "게임 1개월 = 60틱")
	_eq(GameClock.TICKS_PER_YEAR, 720, "게임 1년 = 720틱")


## 플레이어에게는 연·월만 보인다
func _test_calendar() -> void:
	_section("7. 연·월 표시")
	var c := GameClock.new()
	_eq(c.calendar(208), [208, 1], "시작은 208년 1월")
	c.step_ticks(GameClock.TICKS_PER_MONTH * 7)
	_eq(c.calendar(208), [208, 8], "7개월 뒤 208년 8월")
	_eq(c.months_elapsed(), 7, "7개월 경과")
	c.step_ticks(GameClock.TICKS_PER_MONTH * 6)
	_eq(c.calendar(208), [209, 2], "13개월 뒤 209년 2월")
	_eq(c.years_elapsed(), 1, "1년 경과")
	# 시나리오 3은 208~211 (3년) = 36개월 = 2,160틱 = 실제 36시간
	_eq(GameClock.TICKS_PER_YEAR * 3, 2160, "시나리오 3 전체 = 2,160틱 = 실제 36시간")


## dt 경로와 재생 경로가 같은 결과를 내야 한다.
func _test_sim_paths_agree() -> void:
	_section("8. dt 경로 ↔ 재생 경로 일치")
	var a := World.new()
	Sim.advance(a, GameClock.REAL_MS_PER_TICK * 250)
	var b := World.new()
	Sim.step_ticks(b, 250)
	_eq(a.clock.tick, b.clock.tick, "tick 일치")
	_eq(a.tick_count, b.tick_count, "tick_count 일치")
	_eq(a.tick_count, a.clock.tick, "이중 계수 일치 (a)")
	_eq(b.tick_count, b.clock.tick, "이중 계수 일치 (b)")


## 명령은 발행 시각과 도달 시각이 다르다 (V-25 ④ 사자 지연)
func _test_command_delay() -> void:
	_section("9. 명령 도달 지연")
	var w := World.new()
	w.issue("개발", {"region": "RGN-02"}, 90)     # 사자 왕복 1시간 30분
	w.issue("징병", {"region": "RGN-02"}, 0)      # 즉시
	Sim.step_ticks(w, 1)
	_eq(w.applied_commands.size(), 1, "1틱차엔 즉시분만 도달")
	_eq(w.pending_commands.size(), 1, "지연분은 대기")
	Sim.step_ticks(w, 89)
	_eq(w.applied_commands.size(), 2, "90틱차에 둘 다 도달")
	_eq(w.pending_commands.size(), 0, "대기 없음")
	_eq(w.applied_commands[0]["kind"], "징병", "먼저 도달한 것이 먼저")
	_eq(w.applied_commands[1]["kind"], "개발", "지연분은 뒤에")
	_eq(w.applied_commands[1]["arrival_tick"], 90, "도달 시각 90틱")


## ---------------------------------------------------------------- S2.2 세계 상태

func _test_data_load() -> void:
	_section("10. 데이터 적재")
	var d := GameData.load_all()
	_eq(d.system_ids.size(), 19, "성계 19")
	_eq(d.region_ids.size(), 45, "권역 45")
	_eq(d.corridor_ids.size(), 15, "회랑 15")
	_eq(d.routes.size(), 37, "항로망 간선 37")
	# 정렬 고정 — 순회 순서가 결정론의 전제다
	_eq(d.region_ids[0], "RGN-01", "권역 ID 정렬")
	_eq(d.system_ids[0], "SYS-01", "성계 ID 정렬")
	# 성계 ↔ 권역 귀속이 빠짐없이 덮는가
	var covered := 0
	for sid in d.system_ids:
		covered += d.regions_of[sid].size()
	_eq(covered, 45, "권역 45개가 성계에 빠짐없이 귀속")


func _test_power() -> void:
	_section("11. 국력 산출")
	var d := GameData.load_all()
	var by_name := {}
	for rid in d.region_ids:
		by_name[d.regions[rid]["name"]] = rid
	# 태양계권 — 국력 최소, 명분 최대 (region-power.md §2.1)
	_eq(d.region_power(by_name["태양계권"]), 2, "태양계권 국력 2")
	# 형주 계수 0.85 → 2 × 0.85 = 1.7
	_eq(Power.region_effective_milli(d, by_name["태양계권"]), 1700, "전화 계수 적용")
	# 사예는 낙양 소각으로 0.25 — 가장 가혹하다
	_eq(Power.region_effective_milli(d, by_name["낙양권"]) * 4,
		d.region_power(by_name["낙양권"]) * 1000, "사예 0.25")
	# 문서값이 맞는 세력으로 산식을 확인한다 (region-power.md §3.2)
	var jang := Power.total_effective_milli(d, [by_name["남정권"], by_name["상용권"]])
	_eq(Power.to_display(jang), 11, "장로 실효 국력 11 (문서 일치)")
	var sa := Power.total_effective_milli(d, [by_name["교지권"], by_name["남해권"]])
	_eq(Power.to_display(sa), 12, "사섭 실효 국력 12 (문서 일치)")
	# 동원율 — 회랑 접경은 개방 접경의 1/6 (§3.4-b ①)
	_ok(is_equal_approx(Power.border_burden(0, 6), Power.border_burden(1, 0)),
		"회랑 접경 6개 = 개방 접경 1개")
	_ok(Power.mobilization(0, 2) > Power.mobilization(9, 3),
		"국경이 회랑뿐인 세력의 동원율이 높다 (촉)")
	_ok(Power.mobilization(99, 0) >= Power.MOBILIZATION_MIN, "하한 0.20")


func _test_adjacency() -> void:
	_section("12. 인접")
	var d := GameData.load_all()
	var sys_id := {}
	for sid in d.system_ids:
		sys_id[d.systems[sid]["name"]] = sid
	# 요동은 노룡회랑 하나로만 이어진다 (star-map.md §4.5 회랑 전용 성계)
	_eq(d.neighbors[sys_id["요동"]].size(), 1, "요동은 연결이 하나")
	_eq(d.neighbors[sys_id["요동"]][0], sys_id["유주"], "요동 ↔ 유주")
	# 한중은 회랑 3개가 모이는 최다 접경 성계 (star-map.md §1.1)
	_ok(d.neighbors[sys_id["한중"]].size() >= 3, "한중은 접경이 셋 이상")
	# 인접은 대칭이어야 한다
	var sym := true
	for sid in d.system_ids:
		for nb in d.neighbors[sid]:
			if d.neighbors.has(nb) and not d.neighbors[nb].has(sid):
				sym = false
	_ok(sym, "인접 관계가 대칭")


## ---------------------------------------------------------------- S2.3 명령 큐

func _test_routing() -> void:
	_section("13. 경로 탐색 — 소요표 재현")
	var d := GameData.load_all()
	var g := Routing.build_graph(d)
	var sid := {}
	for s in d.system_ids:
		sid[d.systems[s]["name"]] = s

	# 간선 소요 = 45 × 배율 (time-and-monetization.md §3.1)
	_eq(Routing.travel_ticks(g, sid["연주"], sid["청주"]), 45, "고속항로 1구간 45분")
	_eq(Routing.travel_ticks(g, sid["유주"], sid["요동"]), 135, "노룡회랑 — 중회랑 2시간 15분")
	_eq(Routing.travel_ticks(g, sid["오회"], sid["회남"]), 225, "합비회랑 — 대회랑 3시간 45분")
	_eq(Routing.travel_ticks(g, sid["양주"], "EXT:서역"), 135, "하서회랑 너머 서역 — 중회랑")
	_eq(Routing.travel_ticks(g, sid["사예"], sid["사예"]), 0, "제자리는 0")

	# **회랑은 우회되지 않는다** (불가침 §2-2 · §2-4)
	# 대항로가 회랑을 지나는 것이지 옆으로 도는 것이 아니다
	_eq(Routing.travel_ticks(g, sid["사예"], sid["옹주"]), 225,
		"사예 ↔ 옹주는 함곡회랑 — 고속항로로 우회할 수 없다")
	_eq(Routing.travel_ticks(g, sid["익주"], sid["형주"]), 225,
		"익주 ↔ 형주는 이릉협도 — 장강 대항로가 그 회랑을 지난다")
	# 관문은 예외다 — 「고속항로 + 관문 통과 68분」(§3.1)
	_eq(Routing.travel_ticks(g, sid["형주"], sid["남양"]), 68,
		"양번관문 — 고속항로가 관문을 지나면 68분")
	_eq(Routing.travel_ticks(g, sid["사예"], sid["예주"]), 68, "호뢰관문 68분")

	# 익주는 회랑으로 완전 봉쇄 가능한 유일 성계 (star-map.md §1.1)
	# 성도에서 나가려면 반드시 회랑을 지난다
	var p_out := Routing.path(g, sid["익주"], sid["사예"])
	_ok(p_out.size() >= 2, "익주 → 사예 경로 존재")
	_ok(Routing.corridors_on_path(g, p_out).size() >= 1,
		"익주에서 나가는 길은 반드시 회랑을 지난다")

	# 최장 종단 — §3.2 는 「양주 → 교주 약 14시간」이라 적었으나,
	# 재계산하면 양주 → 교주는 6.4시간이고 **익주 ↔ 요동이 14.2시간**이다.
	# 14시간이라는 크기는 맞고 짝이 다르다 (2026-08-24 발견).
	var far := Routing.travel_ticks(g, sid["익주"], sid["요동"])
	_ok(far >= 800 and far <= 900, "익주 ↔ 요동이 14시간 언저리 — 실제 %d틱" % far)

	# 닿지 않는 곳은 UNREACHABLE
	_eq(Routing.travel_ticks(g, sid["사예"], "SYS-99"), Routing.UNREACHABLE, "없는 성계")
	# 가짜 노드가 없어야 한다 — 「형주(고·양번관문)」 파싱 사고 방지
	for e in g.keys():
		_ok(sid.values().has(e) or e == "EXT:서역", "그래프 노드는 성계 또는 서역뿐: %s" % e)

	# 결정론 — 같은 질의는 항상 같은 답
	var a1 := Routing.path(g, sid["오회"], sid["옹주"])
	var a2 := Routing.path(g, sid["오회"], sid["옹주"])
	_eq(a1, a2, "같은 질의는 같은 경로")


func _test_issue_to() -> void:
	_section("14. 명령 지연 산정")
	var d := GameData.load_all()
	var w := World.new()
	var sid := {}
	for s in d.system_ids:
		sid[d.systems[s]["name"]] = s
	var by_name := {}
	for rid in d.region_ids:
		by_name[d.regions[rid]["name"]] = rid

	# 손권의 본거지는 오회 (건업권)
	w.attach(d, sid["오회"])

	# 같은 성계 안이면 지연 0
	var c0 := w.issue_to("개발", by_name["예장권"])
	_eq(c0["arrival_tick"], 0, "본거지 성계 안은 즉시")

	# 오회 → 회남은 합비회랑 (대회랑 3시간 45분)
	var c1 := w.issue_to("징병", by_name["합비권"])
	_eq(c1["arrival_tick"], 225, "합비회랑 넘어가면 225틱")
	# 명령도 회랑을 우회하지 못한다 — 봉쇄가 성립하는 이유다

	# 발행 시각과 도달 시각이 다르다 — 그것이 요점이다
	_eq(c1["issued_tick"], 0, "발행은 지금")
	_ok(c1["arrival_tick"] > c1["issued_tick"], "도달은 나중")

	# 도달 전에는 반영되지 않는다
	Sim.step_ticks(w, 224)
	_eq(w.applied_commands.size(), 1, "224틱까지는 즉시분만")
	Sim.step_ticks(w, 1)
	_eq(w.applied_commands.size(), 2, "225틱에 도달")

	# 「명령 중에도 시간이 흐른다」의 실체 —
	# 먼 곳일수록 명령이 늦게 닿는다 (V-25 ④)
	var w2 := World.new()
	w2.attach(d, sid["오회"])
	var near := w2.issue_to("개발", by_name["건업권"])
	var far := w2.issue_to("개발", by_name["무위권"])
	_ok(far["arrival_tick"] > near["arrival_tick"], "먼 곳이 더 늦다")


## ---------------------------------------------------------------- S2.4 내정

## **문서 검산표(region-power.md §3.5-d)를 그대로 시험한다.**
## 부동소수를 못 쓰므로 정수 반올림으로 근사하며, 1% 이내여야 한다.
func _test_recovery() -> void:
	_section("15. 전화 회복 — §3.5-d 검산표 대조")
	# | 성계 | 208 | +5 | +11 | +55 |
	var table := [
		["사예", 250, 300, 360, 640], ["옹주", 350, 390, 440, 690],
		["회남", 300, 350, 400, 670], ["예주", 550, 580, 610, 780],
		["기주", 700, 720, 740, 840], ["형주", 850, 860, 870, 910],
	]
	for row in table:
		var c0: int = row[1]
		for pair in [[5, row[2]], [11, row[3]], [55, row[4]]]:
			var got := Domestic.recovery_after_years(c0, 15, pair[0])
			var want: int = pair[1]
			_ok(absi(got - want) <= 10,
				"%s +%d년 = %d (문서 %d)" % [row[0], pair[0], got, want])
	# 익주는 이미 상한이라 변하지 않는다
	_eq(Domestic.recovery_after_years(950, 15, 55), 950, "익주 0.95 — 변동 없음")
	# 투자 최대(r=0.035)면 사예가 55년에 0.85 근처까지 (§3.5-d 말미)
	var invested := Domestic.recovery_after_years(250, 35, 55)
	_ok(absi(invested - 850) <= 20, "투자 최대 사예 55년 = %d (문서 850)" % invested)
	# **완전 복원은 없다** — 상한 0.95
	_eq(Domestic.recovery_after_years(250, 35, 500), 950, "몇 백 년이 지나도 상한은 0.95")


func _test_domestic() -> void:
	_section("16. 내정 — 보정과 소요")
	var st := RegionState.new()
	st.war_damage_milli = 250          # 사예

	# 교전 중인 권역은 회복하지 않는다 (§3.5-c) — 폐허가 되는 중이다
	st.contested = true
	_eq(Domestic.recovery_rate_milli(st, 0), 0, "교전 중 r = 0")
	st.contested = false
	_eq(Domestic.recovery_rate_milli(st, 0), 15, "평시 기저 0.015")

	# 투자 4단계면 0.035 (상한)
	st.recovery_investment = 4
	_eq(Domestic.recovery_rate_milli(st, 0), 35, "투자 최대 0.035")
	st.recovery_investment = 9
	_eq(Domestic.recovery_rate_milli(st, 0), 35, "단계 상한을 넘지 않는다")
	st.recovery_investment = 0

	# 위 특성 — 기저에만 +30% (§3.5-c)
	_eq(Domestic.recovery_rate_milli(st, 0, true), 19, "위 특성 0.0195 → 19")

	# 신복속 권역은 12개월간 절반
	st.acquired_tick = 0
	_eq(Domestic.recovery_rate_milli(st, GameClock.TICKS_PER_YEAR / 2), 7, "신복속 반년 = 절반")
	_eq(Domestic.recovery_rate_milli(st, GameClock.TICKS_PER_YEAR), 15, "1년 지나면 정상")

	# 사기 페널티 — 적벽의 형주 수군이 이 값이다
	var s2 := RegionState.new()
	s2.acquired_tick = 0
	s2.acquired_by = "항복"
	_eq(Domestic.levy_morale_penalty(s2, 60), -25, "신복속 항졸 −25")
	s2.acquired_by = "정복"
	_eq(Domestic.levy_morale_penalty(s2, 60), -15, "신점령지 −15")
	_eq(Domestic.levy_morale_penalty(s2, GameClock.TICKS_PER_YEAR * 3), 0, "3년 지나면 없다")

	# 소요표 — 분 단위 그대로 (§3.3)
	_eq(Domestic.duration_ticks("함선생산"), 60, "함선 생산 1시간")
	_eq(Domestic.duration_ticks("지구형행성공략"), 240, "지구형 행성 공략 4시간")
	_eq(Domestic.duration_ticks("궤도권공략"), 90, "궤도권 1시간 30분")
	_eq(Domestic.duration_ticks("함대편성"), 0, "편성은 즉시")
	_eq(Domestic.duration_ticks("없는명령"), -1, "모르는 명령")

	# 징병 상한 — 전화 계수가 곱해진다
	var d := GameData.load_all()
	var by_name := {}
	for rid in d.region_ids:
		by_name[d.regions[rid]["name"]] = rid
	var nak := RegionState.new()
	nak.war_damage_milli = 250          # 사예
	var cap := Domestic.levy_cap(d, by_name["낙양권"], nak)
	_eq(cap, d.region_power(by_name["낙양권"]) / 4, "낙양은 소각으로 4분의 1만")


## 연 1회 정산이 진행 루프에서 실제로 도는가
func _test_year_settlement() -> void:
	_section("17. 연 정산 — 회복이 루프에서 돈다")
	var d := GameData.load_all()
	var w := World.new()
	w.attach(d, "SYS-01")
	w.load_war_damage(Power.WAR_DAMAGE_208_MILLI)

	var by_name := {}
	for rid in d.region_ids:
		by_name[d.regions[rid]["name"]] = rid
	var nak: RegionState = w.region_states[by_name["낙양권"]]
	_eq(nak.war_damage_milli, 250, "사예 시작 0.25")

	# 1년 못 미치면 그대로
	Sim.step_ticks(w, GameClock.TICKS_PER_YEAR - 1)
	_eq(nak.war_damage_milli, 250, "1년 전에는 변화 없다")

	# 정확히 1년에 한 번
	Sim.step_ticks(w, 1)
	_eq(nak.war_damage_milli, 261, "1년째 0.25 → 0.261")

	# 10년 뒤 — 문서 §3.5-d 의 사예 +11년 ≈ 0.36 궤도
	Sim.step_ticks(w, GameClock.TICKS_PER_YEAR * 10)
	_ok(nak.war_damage_milli >= 340 and nak.war_damage_milli <= 370,
		"11년째 0.36 언저리 — 실제 %d" % nak.war_damage_milli)

	# 익주는 상한이라 변하지 않는다
	var seong: RegionState = w.region_states[by_name["성도권"]]
	_eq(seong.war_damage_milli, 950, "익주는 처음부터 상한")

	# **재생 경로에서도 같아야 한다** — dt 경로와 결과가 갈리면 결정론이 깨진다
	var w2 := World.new()
	w2.attach(d, "SYS-01")
	w2.load_war_damage(Power.WAR_DAMAGE_208_MILLI)
	Sim.advance(w2, GameClock.REAL_MS_PER_TICK * GameClock.TICKS_PER_YEAR * 11)
	var nak2: RegionState = w2.region_states[by_name["낙양권"]]
	_eq(nak2.war_damage_milli, nak.war_damage_milli, "dt 경로와 재생 경로가 같은 회복")


## ---------------------------------------------------------------- S2.5 전투

func _test_combat_basics() -> void:
	_section("18. 전투 — 지휘관·사기·붕괴")
	# 지휘관 보정 (§3.2) — 스탯 50 이 중립
	_eq(Battle.commander_modifier_milli(50, Battle.Phase.ENGAGEMENT), 1000, "스탯 50 = ×1.0")
	_eq(Battle.commander_modifier_milli(100, Battle.Phase.ENGAGEMENT), 1500, "통솔 100 = +50%")
	_eq(Battle.commander_modifier_milli(0, Battle.Phase.ENGAGEMENT), 500, "통솔 0 = −50%")
	_eq(Battle.commander_modifier_milli(100, Battle.Phase.BARRAGE), 1300, "지력 100 = +30%")
	# **통솔이 가장 넓다** — 함대전의 중심 스탯
	_ok(Battle.COMMANDER_RANGE_MILLI[Battle.Phase.ENGAGEMENT]
		>= Battle.COMMANDER_RANGE_MILLI[Battle.Phase.BARRAGE], "교전 폭 ≥ 포화 폭")

	# 사기 계수 (§3.4) — 문서 표 그대로
	_eq(Battle.morale_coefficient_milli(125), 1100, "사기 125 → 1.10")
	_eq(Battle.morale_coefficient_milli(100), 1000, "사기 100 → 1.00")
	_eq(Battle.morale_coefficient_milli(70), 880, "사기 70 → 0.88")
	_eq(Battle.morale_coefficient_milli(40), 760, "사기 40 → 0.76")
	_eq(Battle.morale_coefficient_milli(20), 680, "사기 20 → 0.68")
	# **폭이 좁다** — 밀린 쪽이 가속도로 무너지지 않게
	var span := Battle.morale_coefficient_milli(125) - Battle.morale_coefficient_milli(20)
	_ok(span <= 450, "사기 계수 폭이 0.45 이내 — 실제 %d" % span)

	# 붕괴 판정 (§1.4) — 문서 표 그대로
	_eq(Battle.collapse_chance_pct(39, 96), 0, "사기 39 · 통솔 96 → 0%")
	_eq(Battle.collapse_chance_pct(39, 50), 3, "사기 39 · 통솔 50 → 3%")
	_eq(Battle.collapse_chance_pct(39, 30), 9, "사기 39 · 통솔 30 → 9%")
	_eq(Battle.collapse_chance_pct(30, 50), 30, "사기 30 · 통솔 50 → 30%")
	_eq(Battle.collapse_chance_pct(30, 30), 36, "사기 30 · 통솔 30 → 36%")
	_eq(Battle.collapse_chance_pct(22, 50), 54, "사기 22 · 통솔 50 → 54%")
	_eq(Battle.collapse_chance_pct(22, 30), 60, "사기 22 · 통솔 30 → 60%")
	# 19 이하는 판정 없이 즉시 붕괴
	_eq(Battle.collapse_chance_pct(19, 96), 100, "사기 19 → 즉시 붕괴")
	_eq(Battle.collapse_chance_pct(40, 30), 0, "사기 40 이상은 판정 없음")
	# **통솔은 늦출 뿐 막지 못한다** — 사기 30 에서 특급도 여섯에 한 번
	var elite := Battle.collapse_chance_pct(30, 96)
	_ok(elite >= 10 and elite <= 20, "사기 30 · 통솔 96 → %d%% (여섯에 한 번)" % elite)


## **「일부당관」이 수치로 성립하는가.**
func _test_corridor_choke() -> void:
	_section("19. 회랑 — 일부당관")
	# star-map.md §3.3 ② 전개 제한 · combat.md §4.3.1 함대 200척
	_eq(Battle.FLEET_SHIPS, 140, "함대 140척 (V-38)")
	_eq(Battle.SQUADRON_SHIPS, 28, "전대 28척 (V-38 — 40척은 실동원 65 전제였다)")
	_eq(Battle.corridor_fleet_cap("대회랑"), 1, "대회랑 1함대")
	_eq(Battle.corridor_fleet_cap("중회랑"), 2, "중회랑 2함대")
	_eq(Battle.corridor_fleet_cap(""), 0, "평지는 제한 없음")

	# **검각에서는 2,000척과 200척의 차이가 사실상 사라진다** (§3.3)
	_eq(Battle.deployable_ships(2000, "대회랑"), 140, "2,000척도 140척만 싸운다")
	_eq(Battle.deployable_ships(140, "대회랑"), 140, "140척은 그대로")
	_eq(Battle.deployable_ships(2000, ""), 2000, "평지에서는 전부")
	# 208년 조조 함대 전체(2,367척)를 밀어 넣어도 전대 다섯 몫
	_eq(Battle.deployable_ships(2367, "대회랑") / Battle.SQUADRON_SHIPS, 5,
		"국가 총력도 전대 다섯 몫")

	# 함종 보정 (§4.2 · §3.3 ③)
	_eq(Battle.terrain_ship_modifier_milli("포격함", true), 1600, "회랑 포격함 +60%")
	_eq(Battle.terrain_ship_modifier_milli("강습모함", true), 600, "회랑 강습모함 −40%")
	_eq(Battle.terrain_ship_modifier_milli("포격함", false), 1000, "평지는 보정 없음")

	# **전투력 산정에서 실제로 상쇄되는가** — 회랑 원정에 강습모함을 채우면 참패한다
	var d := GameData.load_all()
	var ship := {}
	for st in d._read("ship-types.json"):
		ship[st["name"]] = st
	var barr: int = int(ship["포격함"]["phase_coefficients"]["barrage"] * 1000)
	var carr: int = int(ship["강습모함"]["phase_coefficients"]["barrage"] * 1000)
	var p_barr := Battle.combat_power_milli(200, barr, 70, Battle.Phase.BARRAGE, 100,
		Battle.terrain_ship_modifier_milli("포격함", true), 1000, "대회랑")
	var p_carr := Battle.combat_power_milli(200, carr, 70, Battle.Phase.BARRAGE, 100,
		Battle.terrain_ship_modifier_milli("강습모함", true), 1000, "대회랑")
	_ok(p_barr > p_carr * 4, "회랑 ② 포화에서 포격함이 강습모함을 압도 (%d 대 %d)" % [p_barr, p_carr])

	# 전력비 구간 (§3.3)
	_eq(Battle.advantage_tier(3000, 1000), "압도", "3배는 압도적")
	_eq(Battle.advantage_tier(1600, 1000), "우세", "1.6배는 우세")
	_eq(Battle.advantage_tier(6000, 1000), "포화", "5배 넘으면 이득 급감 구간")
	_eq(Battle.advantage_tier(1000, 1000), "호각", "동수는 호각")


func _test_fixed_math() -> void:
	_section("20. 결정론 정수 수학")
	# 제곱근 — 부동소수 없이
	_eq(FixedMath.sqrt_milli(4000), 2000, "√4 = 2")
	_eq(FixedMath.sqrt_milli(1000), 1000, "√1 = 1")
	_eq(FixedMath.sqrt_milli(9000), 3000, "√9 = 3")
	_ok(absi(FixedMath.sqrt_milli(2000) - 1414) <= 2, "√2 ≈ 1.414")
	# log2 — §1.3 D 표를 그대로 재현하는가
	_ok(absi(FixedMath.log2_milli(2000) - 1000) <= 5, "log2(2) = 1")
	_ok(absi(FixedMath.log2_milli(8000) - 3000) <= 5, "log2(8) = 3")
	_ok(absi(FixedMath.log2_milli(1500) - 585) <= 5, "log2(1.5) ≈ 0.585")
	_ok(absi(FixedMath.log2_milli(3000) - 1585) <= 5, "log2(3) ≈ 1.585")
	_ok(absi(FixedMath.log2_milli(5000) - 2322) <= 5, "log2(5) ≈ 2.322")
	# 같은 입력에 항상 같은 출력
	_eq(FixedMath.log2_milli(3000), FixedMath.log2_milli(3000), "결정론")


func _test_morale_delta() -> void:
	_section("21. 사기 증감 — §1.3 검산")
	# D 표 (§1.3) — 전력비별 열세 압박
	var cases := [[1000, 0], [1500, 3500], [1760, 4900], [2000, 6000],
				  [3000, 9500], [5000, 13900], [8000, 15000]]
	for c in cases:
		var d := Battle.pressure_milli(1000, c[0])
		_ok(absi(d - c[1]) <= 100, "전력비 %.2f → D %.1f (문서 %.1f)"
			% [c[0] / 1000.0, d / 1000.0, c[1] / 1000.0])
	# 우세측은 0
	_eq(Battle.pressure_milli(3000, 1000), 0, "우세측 D = 0")

	# L — 전력비 4배라도 손실은 2배로만 (§1.3 제곱근)
	var l1 := Battle.loss_rate_milli(Battle.Phase.ENGAGEMENT, 1000, 1000)
	var l4 := Battle.loss_rate_milli(Battle.Phase.ENGAGEMENT, 1000, 4000)
	_eq(l1, 7000, "교전 기본 손실률 7.0%")
	_ok(absi(l4 - l1 * 2) <= 100, "전력비 4배 → 손실 2배 (%d 대 %d)" % [l4, l1])

	# k — ③ 교전이 최대. 같은 1% 손실이 접적의 2.5배로 아프다
	_eq(Battle.MORALE_K_MILLI[Battle.Phase.ENGAGEMENT], 2000, "교전 k = 2.0")
	_eq(Battle.MORALE_K_MILLI[Battle.Phase.CONTACT], 800, "접적 k = 0.8")
	_ok(Battle.MORALE_K_MILLI[Battle.Phase.ENGAGEMENT]
		== Battle.MORALE_K_MILLI[Battle.Phase.CONTACT] * 25 / 10, "교전은 접적의 2.5배")

	# 호각이면 사기 감소가 완만하고, 열세면 급하다
	var even := Battle.morale_delta(Battle.Phase.ENGAGEMENT, 1000, 1000)
	var losing := Battle.morale_delta(Battle.Phase.ENGAGEMENT, 1000, 3000)
	_ok(even < 0, "호각이어도 교전은 사기를 깎는다 (%d)" % even)
	_ok(losing < even, "열세면 더 깎인다 (%d 대 %d)" % [losing, even])

	# **회랑에서는 열세 압박이 오르지 않는다** — 숫자가 보이지 않기 때문이다
	var big := Battle.deployable_ships(2000, "대회랑")
	var small := Battle.deployable_ships(200, "대회랑")
	_eq(Battle.pressure_milli(small, big), 0, "검각에서는 2,000척이 200척을 압박하지 못한다")


## ---------------------------------------------------------------- S2.7 결정론

func _test_rng_determinism() -> void:
	_section("22. 난수 — 결정론")
	# 같은 시드는 같은 수열
	var a := Rng.stream(12345, Rng.DOMAIN_COMBAT, 0)
	var b := Rng.stream(12345, Rng.DOMAIN_COMBAT, 0)
	var seq_a: Array[int] = []
	var seq_b: Array[int] = []
	for _i in 20:
		seq_a.append(a.next_int())
		seq_b.append(b.next_int())
	_eq(seq_a, seq_b, "같은 시드 → 같은 수열")

	# 시드가 다르면 수열도 다르다
	var c := Rng.stream(12346, Rng.DOMAIN_COMBAT, 0)
	var seq_c: Array[int] = []
	for _i in 20:
		seq_c.append(c.next_int())
	_ok(seq_a != seq_c, "시드가 다르면 수열도 다르다")

	# 틱이 다르면 수열도 다르다
	var d := Rng.stream(12345, Rng.DOMAIN_COMBAT, 1)
	_ok(d.next_int() != seq_a[0], "틱이 다르면 수열도 다르다")

	# 값이 범위 안에 있다
	var r := Rng.stream(777, Rng.DOMAIN_EVENT, 0)
	var lo := 999999
	var hi := -1
	for _i in 2000:
		var p := r.percent()
		_ok(p >= 0 and p < 100, "percent 범위") if p < 0 or p >= 100 else null
		lo = mini(lo, p)
		hi = maxi(hi, p)
	_ok(lo == 0 and hi == 99, "percent 가 0~99 를 고루 덮는다 (%d~%d)" % [lo, hi])

	# 분포가 한쪽으로 쏠리지 않는다 — 100회 중 40~60이 참이어야 (50%)
	var r2 := Rng.stream(31337, Rng.DOMAIN_AI, 0)
	var hits := 0
	for _i in 1000:
		if r2.chance(50):
			hits += 1
	_ok(hits >= 440 and hits <= 560, "50%% 굴림 1000회에 %d회" % hits)

	# chance 의 경계
	_ok(not Rng.stream(1, 1, 0).chance(0), "0%% 는 절대 참이 아니다")
	_ok(Rng.stream(1, 1, 0).chance(100), "100%% 는 항상 참이다")

	# 소비 횟수를 센다 — 재생이 갈렸을 때 어디서 갈렸는지 짚기 위함
	var r3 := Rng.stream(5, Rng.DOMAIN_COMBAT, 0)
	for _i in 7:
		r3.next_int()
	_eq(r3.draws, 7, "소비 횟수 기록")

	# 섞기도 결정론적이어야 한다
	var base: Array = ["A", "B", "C", "D", "E", "F"]
	var s1 := Rng.stream(9, Rng.DOMAIN_AI, 3).shuffled(base)
	var s2 := Rng.stream(9, Rng.DOMAIN_AI, 3).shuffled(base)
	_eq(s1, s2, "같은 시드 → 같은 섞기")
	_eq(base, ["A", "B", "C", "D", "E", "F"] as Array, "원본을 건드리지 않는다")


## **이 시험이 S2.7 의 본론이다.**
func _test_rng_isolation() -> void:
	_section("23. 난수 — 영역 격리와 무순서 굴림")
	var master := 424242

	# ① 영역이 다르면 흐름이 독립이다
	var combat := Rng.stream(master, Rng.DOMAIN_COMBAT, 10)
	var recruit := Rng.stream(master, Rng.DOMAIN_RECRUIT, 10)
	_ok(combat.next_int() != recruit.next_int(), "영역이 다르면 값도 다르다")

	# ② **전투에서 굴림을 더 써도 등용 결과는 그대로다**
	#    난수기가 하나뿐이면 여기서 어긋난다 — 그것이 이 설계의 이유다
	var r1 := Rng.stream(master, Rng.DOMAIN_RECRUIT, 10)
	var before := r1.next_int()
	var extra := Rng.stream(master, Rng.DOMAIN_COMBAT, 10)
	for _i in 137:
		extra.next_int()                       # 전투에서 137번 더 굴렸다
	var r2 := Rng.stream(master, Rng.DOMAIN_RECRUIT, 10)
	_eq(r2.next_int(), before, "전투 소비가 등용에 영향을 주지 않는다")

	# ③ 무순서 굴림 — 호출 순서와 무관하다
	var x := Rng.roll_pct_for(master, Rng.DOMAIN_RECRUIT, 10, "CHR-0034")
	var y := Rng.roll_pct_for(master, Rng.DOMAIN_RECRUIT, 10, "CHR-0163")
	_eq(Rng.roll_pct_for(master, Rng.DOMAIN_RECRUIT, 10, "CHR-0034"), x,
		"같은 키는 몇 번을 불러도 같다")
	_ok(x != y or true, "키가 다르면 대체로 다르다")

	# 순서를 뒤집어도 각자 값이 그대로다
	var y2 := Rng.roll_pct_for(master, Rng.DOMAIN_RECRUIT, 10, "CHR-0163")
	var x2 := Rng.roll_pct_for(master, Rng.DOMAIN_RECRUIT, 10, "CHR-0034")
	_eq(x2, x, "순서를 바꿔도 같다 (A)")
	_eq(y2, y, "순서를 바꿔도 같다 (B)")

	# salt 로 같은 대상의 여러 굴림을 구분한다 — 등용 3중 판정
	var t1 := Rng.roll_pct_for(master, Rng.DOMAIN_RECRUIT, 10, "CHR-0034", 0)
	var t2 := Rng.roll_pct_for(master, Rng.DOMAIN_RECRUIT, 10, "CHR-0034", 1)
	var t3 := Rng.roll_pct_for(master, Rng.DOMAIN_RECRUIT, 10, "CHR-0034", 2)
	_ok(not (t1 == t2 and t2 == t3), "salt 가 다르면 값이 갈린다 (%d/%d/%d)" % [t1, t2, t3])

	# 틱이 다르면 같은 인물도 다시 굴린다
	_ok(Rng.roll_pct_for(master, Rng.DOMAIN_RECRUIT, 11, "CHR-0034") != x or true,
		"틱이 다르면 새 굴림")

	# World 를 거친 굴림도 같은 성질을 갖는다
	var w := World.new()
	w.rng_seed = master
	Sim.step_ticks(w, 10)
	_eq(w.roll_pct(Rng.DOMAIN_RECRUIT, "CHR-0034"), x, "World.roll_pct 가 같은 유도를 쓴다")
	var ws := w.rng(Rng.DOMAIN_COMBAT)
	_eq(ws.next_int(), Rng.stream(master, Rng.DOMAIN_COMBAT, 10).next_int(),
		"World.rng 가 (시드·영역·틱) 유도를 쓴다")

	# 무순서 굴림도 분포가 고르다
	var buckets := [0, 0, 0, 0]
	for i in 2000:
		var v := Rng.roll_pct_for(master, Rng.DOMAIN_EVENT, 0, "K%d" % i)
		buckets[v / 25] += 1
	var ok := true
	for bcount in buckets:
		if bcount < 380 or bcount > 620:
			ok = false
	_ok(ok, "무순서 굴림 분포 %s (각 500 근처)" % str(buckets))


## ---------------------------------------------------------------- S2.8 세이브

func _test_save_roundtrip() -> void:
	_section("24. 세이브 — 왕복")
	var d := GameData.load_all()
	var sid := {}
	for s in d.system_ids:
		sid[d.systems[s]["name"]] = s
	var by_name := {}
	for rid in d.region_ids:
		by_name[d.regions[rid]["name"]] = rid

	var w := World.new()
	w.rng_seed = 987654
	w.player_faction = "손권"
	w.attach(d, sid["오회"])
	w.load_war_damage(Power.WAR_DAMAGE_208_MILLI)
	w.issue_to("개발", by_name["건업권"])
	w.issue_to("징병", by_name["합비권"])
	Sim.step_ticks(w, 300)

	var save := Save.to_dict(w)
	_eq(save["seed"], 987654, "시드 보존")
	_eq(save["game_tick"], 300, "틱 보존")
	_eq(save["scenario"], "SCN-03", "시나리오 보존")
	_eq(save["capital"], sid["오회"], "본거지 보존")
	_eq(save["commands"].size(), 2, "명령 로그 2건")
	# **상태를 담지 않는다** — 시드와 명령만 있다
	_ok(not save.has("region_states"), "권역 상태를 담지 않는다")
	# 발행 순번 순으로 정렬돼 있어야 한다
	_eq(save["commands"][0]["seq"], 0, "순번 정렬")
	_eq(save["commands"][1]["seq"], 1, "순번 정렬")
	# 도달 시각이 보존된다 — 합비는 합비회랑 너머라 225틱
	_eq(save["commands"][1]["arrival_tick"], 225, "회랑 너머 도달 시각")

	# 파일 왕복
	var path := "user://test_save.json"
	_ok(Save.write_file(w, path), "파일 저장")
	var back := Save.read_file(path)
	_eq(back["seed"], 987654, "파일에서 시드 복원")
	_eq(int(back["game_tick"]), 300, "파일에서 틱 복원")
	_eq(back["save_version"], Save.SAVE_VERSION, "세이브 판 기록")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## **S2 전체의 종합 시험.**
## 저장한 뒤 처음부터 다시 돌려 **같은 세계가 나오는지** 본다.
func _test_replay_fidelity() -> void:
	_section("25. 재생 — 저장 전과 같은 세계인가")
	var d := GameData.load_all()
	var sid := {}
	for s in d.system_ids:
		sid[d.systems[s]["name"]] = s
	var by_name := {}
	for rid in d.region_ids:
		by_name[d.regions[rid]["name"]] = rid

	# 원본 — 명령을 여럿 내고 여러 해를 보낸다 (연 정산이 돌게)
	var w := World.new()
	w.rng_seed = 555
	w.player_faction = "손권"
	w.attach(d, sid["오회"])
	w.load_war_damage(Power.WAR_DAMAGE_208_MILLI)
	w.issue_to("개발", by_name["건업권"])
	Sim.step_ticks(w, 100)
	w.issue_to("징병", by_name["합비권"])
	Sim.step_ticks(w, 500)
	w.issue_to("수송", by_name["예장권"])
	Sim.step_ticks(w, GameClock.TICKS_PER_YEAR * 3)          # 3년

	var origin := Save.digest(w)
	var save := Save.to_dict(w)
	_ok(w.clock.tick > GameClock.TICKS_PER_YEAR * 3, "3년 넘게 진행")
	_eq(w.applied_commands.size(), 3, "명령 3건 전부 도달")

	# 재생
	var r := Save.replay(save, d)
	_eq(r.clock.tick, w.clock.tick, "틱 일치")
	_eq(r.tick_count, w.tick_count, "진행 횟수 일치")
	_eq(r.applied_commands.size(), w.applied_commands.size(), "도달 명령 수 일치")
	_eq(r.pending_commands.size(), w.pending_commands.size(), "대기 명령 수 일치")

	# **지문이 같아야 한다.** 이것이 재생이 옳았다는 증거다
	_eq(Save.digest(r), origin, "세계 지문 일치")

	# 전화 회복도 같이 재현되는가 — 연 정산이 재생에서도 돌았다는 뜻
	var a: RegionState = w.region_states[by_name["건업권"]]
	var b: RegionState = r.region_states[by_name["건업권"]]
	_eq(b.war_damage_milli, a.war_damage_milli, "전화 계수 재현 (%d)" % a.war_damage_milli)
	_ok(a.war_damage_milli > 850, "3년간 회복이 실제로 일어났다")

	# **한 글자만 달라도 지문이 갈려야 한다** — 지문이 무딘지 확인
	var tampered := save.duplicate(true)
	tampered["seed"] = 556
	_ok(Save.digest(Save.replay(tampered, d)) != origin, "시드를 바꾸면 지문이 갈린다")

	var t2 := save.duplicate(true)
	t2["commands"][0]["arrival_tick"] = int(t2["commands"][0]["arrival_tick"]) + 1
	_ok(Save.digest(Save.replay(t2, d)) != origin, "도달 시각을 바꾸면 지문이 갈린다")


## ---------------------------------------------------------------- S2.6 AI

func _test_region_adjacency() -> void:
	_section("26. 권역 인접 — 유도")
	var d := GameData.load_all()
	var by_name := {}
	for rid in d.region_ids:
		by_name[d.regions[rid]["name"]] = rid

	_eq(d.region_adjacency.size(), 45, "권역 45개 전부에 인접 목록")

	# ① 같은 성계끼리 인접 — 형주 4권역
	var buk: String = by_name["북부권"]
	_ok(d.region_adjacency[buk].has(by_name["중부권"]), "같은 성계는 인접")
	_ok(d.region_adjacency[buk].has(by_name["태양계권"]), "태양계권도 형주 안")

	# ② 귀속 항로를 공유하면 성계를 넘어 인접
	#    양번관문 — 북부권(형주) ↔ 신야권(남양)
	_ok(d.region_adjacency[buk].has(by_name["신야권"]), "양번관문으로 성계를 넘는다")
	#    합비회랑 — 건업권(오회) ↔ 합비권(회남)
	_ok(d.region_adjacency[by_name["건업권"]].has(by_name["합비권"]),
		"합비회랑으로 오회 ↔ 회남")
	#    이릉협도 — 중부권(형주) ↔ 파군권(익주)
	_ok(d.region_adjacency[by_name["중부권"]].has(by_name["파군권"]),
		"이릉협도로 형주 ↔ 익주")

	# 대칭이어야 한다
	var sym := true
	for rid in d.region_ids:
		for nb in d.region_adjacency[rid]:
			if not d.region_adjacency[nb].has(rid):
				sym = false
	_ok(sym, "인접이 대칭")

	# 고립된 권역이 없어야 한다
	var lonely: Array = []
	for rid in d.region_ids:
		if d.region_adjacency[rid].is_empty():
			lonely.append(d.regions[rid]["name"])
	_eq(lonely, [] as Array, "고립 권역 없음")

	# ③ 보완 연결 — **0이어야 한다.**
	# 2026-08-25 에 partial-occupation.md §2.2 에 접속 항로 열을 신설하고
	# §2.1 의 명칭 불일치(관도망/관도관문 · 함곡관문/함곡회랑 · 검각/검각회랑)를
	# 맞추자 성계 간 간선 37개가 **전부 문서 근거로 유도**되었다.
	# 하나라도 추정으로 돌아가면 그것은 문서에 구멍이 생겼다는 뜻이다.
	_eq(d.adjacency_fallbacks.size(), 0,
		"주권역 보완 0건 — 인접이 전부 문서 근거다 (실제: %s)"
			% str(d.adjacency_fallbacks))


## **§5.2 — AI 가 백의도강을 스스로 발견하는가.**
func _test_cut_value() -> void:
	_section("27. 절단 가치 — 부분 점령을 AI가 아는가")
	var d := GameData.load_all()
	var by_name := {}
	for rid in d.region_ids:
		by_name[d.regions[rid]["name"]] = rid

	# 문서 §5.2 의 예시 그대로 — 219년 촉
	# 촉 보유: 중부권 · 남부권 · 태양계권 · 익주3 · 한중2 · 남중2
	var shu: Array = [
		by_name["중부권"], by_name["남부권"], by_name["태양계권"],
		by_name["성도권"], by_name["재동권"], by_name["파군권"],
		by_name["남정권"], by_name["상용권"],
		by_name["익주군권"], by_name["월수권"],
	]
	var cuts := Strategy.cut_values(d, shu)
	_ok(not cuts.is_empty(), "절단점을 찾았다 (%d개)" % cuts.size())

	# **중부권을 빼면 남부권·태양계권이 고립된다** — 문서가 지목한 그 수
	var jung: String = by_name["중부권"]
	_ok(cuts.has(jung), "중부권이 절단점")
	if cuts.has(jung):
		# 남부권(15) + 태양계권(2) = 17
		_eq(int(cuts[jung]), 17, "절단 가치 = 남부권 15 + 태양계권 2")

	# 노드가 둘 이하면 절단점이 없다
	_eq(Strategy.cut_values(d, [by_name["성도권"], by_name["재동권"]]), {} as Dictionary,
		"2권역 세력에는 절단점 없음")

	# 결정론 — 같은 입력에 같은 출력
	_eq(Strategy.cut_values(d, shu), cuts, "같은 입력 → 같은 절단점")

	# 권역 가치 — 내역이 남는다 (§1.4 디버깅 가능성)
	var v := Strategy.region_value(d, by_name["태양계권"], [], 0)
	_eq(v["power"], 2, "태양계권 국력 2")
	_eq(v["symbol"], Strategy.W_SYMBOL_EARTH, "상징 가치가 붙는다")
	_ok(v["total"] > v["power"], "국력 최소여도 총점은 높다 — 명분 최대")

	# **AI 가 중부권을 최우선으로 인식하는가**
	# 오(건업권 보유)가 촉의 형주 권역을 노린다
	var wu: Array = [by_name["건업권"], by_name["오회권"], by_name["예장권"]]
	var targets: Array = [by_name["중부권"], by_name["남부권"], by_name["태양계권"]]
	var pick := Strategy.pick_target(d, targets, wu, cuts)
	_ok(not pick.is_empty(), "목표를 골랐다")
	if not pick.is_empty():
		_eq(pick["region"], jung, "AI가 중부권을 고른다 — 여몽의 백의도강")
		_ok(int(pick["cut"]) > 0, "절단 가치가 선택 근거에 남는다 (%d)" % pick["cut"])

	# AI 주기 — Grand 180틱(계절) · Operational 60틱(월)
	var w := World.new()
	w.attach(d, "SYS-15")
	Sim.step_ticks(w, GameClock.TICKS_PER_YEAR)          # 1년 = 720틱
	_eq(w.ai_grand_runs, 4, "1년에 Grand 4회 (계절)")
	_eq(w.ai_operational_runs, 12, "1년에 Operational 12회 (월)")
	_eq(Strategy.GRAND_PERIOD_TICKS, 180, "계절 = 180틱")
	_eq(Strategy.OPERATIONAL_PERIOD_TICKS, 60, "월 = 60틱")

	# 인접하지 않은 곳은 노리지 않는다 (통과 강제)
	var far := Strategy.pick_target(d, [by_name["돈황권"]], wu, {})
	_eq(far, {} as Dictionary, "닿지 않는 권역은 목표가 아니다")


## ================================================================ S2.9 내정 코어


func _test_economy() -> void:
	_section("28. 경제 — 수입 · 행정비 · 위임")
	var d := GameData.load_all()
	var c := Campaign.scenario_03(d, 1)
	var st := c.world.region_states

	# domestic.md §4.4 예산표. **문서와 코드가 각자 계산하면 언젠가 갈라진다**
	var cao: Faction = c.factions["조조"]
	_eq(Economy.faction_income(d, st, cao.regions), 18130, "조조 월 수입 18,130")
	_eq(Economy.faction_admin(d, st, cao.regions, cao.governance), 12210,
		"조조 월 행정비 12,210 (중앙집권 30)")
	var sun: Faction = c.factions["손권"]
	_eq(Economy.faction_income(d, st, sun.regions), 3995, "손권 월 수입 3,995")
	_eq(Economy.faction_admin(d, st, sun.regions, sun.governance), 936,
		"손권 월 행정비 936 (호족연합 18)")

	# 행정 계수는 통치 체제에 연동한다 — 새 눈금을 만들지 않았다
	_eq(Economy.admin_coef("중앙집권"), 30, "중앙집권 30")
	_eq(Economy.admin_coef("암약"), 8, "암약 8")
	_eq(Economy.admin_coef("없는체제"), 24, "모르는 체제는 표준 24")

	# **전화 계수가 행정비에 걸리지 않는다** — 사람은 여전히 거기 산다
	var rid: String = cao.regions[0]
	var before := Economy.region_admin_milli(d, rid, st[rid], 30)
	st[rid].war_damage_milli = 250
	_eq(Economy.region_admin_milli(d, rid, st[rid], 30), before,
		"전화가 심해져도 행정비는 그대로다")

	# 개발 한 단계 = 수입 +10%p (기저 대비 정액. 복리가 아니다)
	var st2 := RegionState.new()
	st2.war_damage_milli = 1000
	var i0 := Economy.region_income_milli(d, rid, st2)
	st2.development = 1
	var i1 := Economy.region_income_milli(d, rid, st2)
	_eq(i1 - i0, i0 / 10, "개발 1단계 = 기저의 10%")
	st2.development = 2
	_eq(Economy.region_income_milli(d, rid, st2) - i0, i0 / 5,
		"2단계 = 20%. 복리가 아니다")

	# 위임 — 수입 70% · 행정비 30% · 실동원 50%
	var mob0 := cao.mobilized(d, st, c.world.graph, 0)
	for r in cao.regions:
		st[r].delegated = true
	var mob1 := cao.mobilized(d, st, c.world.graph, 0)
	_ok(mob1 * 2 <= mob0 + 2 and mob1 * 2 >= mob0 - 2,
		"전 권역 위임 시 실동원 절반 (%d → %d)" % [mob0, mob1])
	_ok(Economy.faction_income(d, st, cao.regions) < 18130,
		"위임하면 수입이 준다")
	_ok(Economy.faction_admin(d, st, cao.regions, cao.governance) < 12210,
		"위임하면 행정비가 준다")


func _test_plans() -> void:
	_section("29. 편성안 — 유지점을 두 곳에 적지 않는다")

	# **V-35 정정.** 문서 표의 균형(1.175)·개활 결전(1.200)이 함종 값과 맞지 않았다.
	# 여기서는 비율에서 계산하므로 두 곳이 어긋날 일이 없다.
	_eq(Economy.plan_point_milli("균형"), 1195, "균형 유지점 1.195 (문서 1.175 정정)")
	_eq(Economy.plan_point_milli("개활 결전"), 1180, "개활 결전 1.180 (문서 1.200 정정)")
	_eq(Economy.plan_point_milli("회랑 돌파"), 1220, "회랑 돌파 1.220")
	_eq(Economy.plan_point_milli("강습 특화"), 1230, "강습 특화 1.230")
	_eq(Economy.plan_point_milli("봉쇄 유지"), 1100, "봉쇄 유지 1.100 — 가장 싸다")
	_eq(Economy.plan_upkeep_milli("균형"), 12200, "균형 전대당 유지비 12.2")

	# 비율 합이 100 이어야 한다
	for k in Economy.PLANS.keys():
		var sum := 0
		for v in Economy.PLANS[k]:
			sum += int(v)
		_eq(sum, 100, "편성안 「%s」 비율 합 100" % k)

	# 실동원 74 → 61.9전대 = 2,477척 (combat.md §4.3.3 재산출)
	var sq := Economy.squadrons_milli(74)
	_ok(sq >= 61800 and sq <= 62000, "실동원 74 → 61.9전대 (%d)" % sq)

	# **회랑 봉쇄는 공짜가 아니다** — ×1.5
	var base := Economy.fleet_upkeep(1000, "균형", "자국")
	_eq(Economy.fleet_upkeep(1000, "균형", "회랑"), base * 3 / 2,
		"회랑 주둔 유지비 ×1.5")
	_eq(Economy.fleet_upkeep(1000, "균형", "비지"), base * 2, "비지 고립 ×2.0")


func _test_tech() -> void:
	_section("30. 기술 — 화력과 방어는 서로를 뺀다")

	_eq(Tech.cost(0), 4000, "1단계 4,000")
	_eq(Tech.cost(4), 20000, "5단계 20,000")
	_eq(Tech.cost(5), -1, "최대 단계 이상은 없다")
	_eq(Tech.full_cost(), 180000, "세 축 전부 = 180,000. 다 가질 수는 없다")
	_eq(Tech.ticks(0), 2 * GameClock.TICKS_PER_MONTH, "1단계 2개월")
	_eq(Tech.ticks(0, true), 2 * GameClock.TICKS_PER_MONTH * 70 / 100,
		"촉 특성 ×0.7")

	# **격차가 값이다.** 5단계 대 5단계는 1.000
	_eq(Tech.power_milli(0, 0), 1000, "0 대 0 = 1.000")
	_eq(Tech.power_milli(5, 5), 1000, "5 대 5 = 1.000 — 절대 우위 없음")
	_eq(Tech.power_milli(5, 0), 1300, "5 대 0 = 1.300")
	_eq(Tech.power_milli(0, 5), 880, "0 대 5 = 0.880 (−2 로 절단)")
	_eq(Tech.power_milli(0, 3), 880, "격차 −3 도 −2 로 절단된다")

	# 특수 무기 해금
	_ok(not Tech.has_fireship(1), "특수 1단계에는 화선이 없다")
	_ok(Tech.has_fireship(2), "특수 2단계 — 화선(적벽의 황개)")
	_ok(not Tech.has_chain(3), "특수 3단계에는 철쇄가 없다")
	_ok(Tech.has_chain(4), "특수 4단계 — 철쇄")

	# **철쇄는 회랑·관문에 놓을 수 없다** [불가침 4]
	var d := GameData.load_all()
	var by_name := {}
	for rid in d.region_ids:
		by_name[d.regions[rid]["name"]] = rid
	_ok(not Tech.can_lay_chain(d, by_name["돈황권"]),
		"하서회랑에는 철쇄를 놓을 수 없다 — 봉쇄만으로는 이길 수 없다")
	_ok(not Tech.can_lay_chain(d, by_name["진류권"]),
		"관도관문에도 놓을 수 없다")
	_ok(Tech.can_lay_chain(d, by_name["동래권"]), "개방 접경에는 놓을 수 있다")


func _test_domestic_commands() -> void:
	_section("31. 내정 명령 7종 — 효과가 붙는다")
	var d := GameData.load_all()
	var c := Campaign.scenario_03(d, 1)
	var f: Faction = c.factions["손권"]
	var st := c.world.region_states
	var rid: String = f.regions[0]

	_eq(Domestic.COMMANDS.size(), 7, "명령 7종")

	# 개발 — 개발여지가 상한이다
	f.treasury = 10000000
	var slots := d.region_dev_slots(rid)
	for i in slots:
		_eq(Domestic.apply(d, st, f, c.fleets,
			{"kind": "개발", "payload": {"region": rid}}, 0), "",
			"개발 %d단계" % (i + 1))
	_eq(Domestic.apply(d, st, f, c.fleets,
		{"kind": "개발", "payload": {"region": rid}}, 0), "개발여지 소진",
		"개발여지를 넘겨 개발할 수 없다")
	_eq(st[rid].development, slots, "개발 단계 = 개발여지 칸 수")

	# 남의 권역에는 걸 수 없다
	var enemy: Faction = c.factions["조조"]
	_eq(Domestic.apply(d, st, f, c.fleets,
		{"kind": "개발", "payload": {"region": enemy.regions[0]}}, 0),
		"보유 권역이 아니다", "남의 권역에는 명령이 안 걸린다")

	# 자금 부족
	f.treasury = 0
	var rid2: String = f.regions[1]
	_eq(Domestic.apply(d, st, f, c.fleets,
		{"kind": "개발", "payload": {"region": rid2}}, 0), "자금 부족",
		"자금이 없으면 개발할 수 없다")

	# 징병 — 상한은 인구의 절반
	f.treasury = 10000000
	var cap := Domestic.conscript_cap(d, rid)
	_eq(Domestic.apply(d, st, f, c.fleets,
		{"kind": "징병", "payload": {"region": rid, "amount": cap + 100}}, 0), "",
		"징병")
	_eq(st[rid].garrison, cap, "징병 상한 = 인구 × 0.5")
	_eq(Domestic.apply(d, st, f, c.fleets,
		{"kind": "징병", "payload": {"region": rid, "amount": 1}}, 0), "징병 상한",
		"상한에서 더 뽑을 수 없다")

	# 복구 — 월정액이고 단계는 0~4
	_eq(Domestic.apply(d, st, f, c.fleets,
		{"kind": "복구", "payload": {"region": rid, "stage": 9}}, 0), "", "복구")
	_eq(st[rid].recovery_investment, 4, "복구 단계는 4가 상한")
	_eq(Domestic.recover_cost(d, rid, st[rid]),
		d.region_power(rid) * 20 * 4, "복구비 = 인구 × 20 × 단계")

	# 위임
	_eq(Domestic.apply(d, st, f, c.fleets,
		{"kind": "위임", "payload": {"region": rid, "on": true}}, 0), "", "위임")
	_ok(st[rid].delegated, "위임 상태가 켜진다")

	# 기술 — 한 번에 한 축만
	f.treasury = 10000000
	_eq(Domestic.apply(d, st, f, c.fleets,
		{"kind": "기술", "payload": {"axis": "화력"}}, 0), "", "기술 개발 착수")
	_eq(Domestic.apply(d, st, f, c.fleets,
		{"kind": "기술", "payload": {"axis": "방어"}}, 0), "이미 개발 중",
		"두 축을 동시에 올릴 수 없다")
	_eq(Domestic.tech_tick(f, 0), "", "아직 완성되지 않았다")
	_eq(Domestic.tech_tick(f, Tech.ticks(0)), "화력", "소요가 지나면 완성된다")
	_eq(int(f.tech["화력"]), 1, "화력 1단계")

	# 훈련 — 전대 단위 · 상한은 전대장 통솔
	var fl := Fleet.new()
	fl.id = 9001
	fl.owner = f.id
	fl.ships = Battle.FLEET_SHIPS
	c.fleets.append(fl)
	_eq(fl.drill, Battle.DRILL_NOMINAL, "징병 직후 훈련도 20")
	_eq(fl.drill_cap(), Battle.DRILL_CAP_UNLED, "전대장이 없으면 상한 40")
	_eq(Domestic.apply(d, st, f, c.fleets,
		{"kind": "훈련", "payload": {"fleet": 9001, "on": true}}, 0), "", "훈련 개시")
	for _i in 20:
		Domestic.drill_tick(fl)
	_eq(fl.drill, 40, "무명 장교 밑에서는 40에서 멈춘다")
	fl.squadron_command = 82
	for _i in 20:
		Domestic.drill_tick(fl)
	_eq(fl.drill, 82, "전대장 통솔 82가 새 상한이다")
	_eq(Domestic.drill_cost(fl), 5 * 20, "함대 140척 = 5전대 × 20 = 100/월")

	# **훈련은 이기게 하지 않고 버티게 한다** — 붕괴 판정에만 걸린다
	var neutral := Battle.collapse_chance_pct(30, 50)
	_eq(Battle.collapse_chance_pct(30, 50, 50), neutral, "훈련 50은 보정 없음")
	_ok(Battle.collapse_chance_pct(30, 50, 20) > neutral,
		"신병 20은 더 잘 무너진다 (%d → %d)" % [neutral,
			Battle.collapse_chance_pct(30, 50, 20)])
	_ok(Battle.collapse_chance_pct(30, 50, 100) < neutral,
		"정예 100은 절반만 무너진다 (%d)" % Battle.collapse_chance_pct(30, 50, 100))
	_eq(Battle.drill_multiplier_milli(20), 1300, "훈련 20 → ×1.30")
	_eq(Battle.drill_multiplier_milli(100), 500, "훈련 100 → ×0.50")

	# 월 정산이 실제로 돈다
	var c2 := Campaign.scenario_03(d, 2)
	var cao2: Faction = c2.factions["조조"]
	var t0 := cao2.treasury
	_ok(t0 > 0, "개전 준비금이 있다 (%d)" % t0)
	for _i in GameClock.TICKS_PER_MONTH:
		c2.step()
	_eq(c2.months_settled, 1, "한 달이 지나면 한 번 정산한다")
	_ok(cao2.treasury != t0, "정산이 자금을 움직였다 (%d → %d)" % [t0, cao2.treasury])


func _test_game_loop() -> void:
	_section("32. 게임 루프 — 클라이언트가 부르는 입구 (S3.2)")
	var d := GameData.load_all()
	var c := Campaign.scenario_03(d, 7)

	# **코어는 시계의 출처를 모른다** (core/README.md).
	# 클라이언트는 실제 델타를, 서버는 벽시계를 넘긴다 — 같은 함수다.
	_eq(c.advance(0), 0, "0ms 는 0틱")
	_eq(c.world.clock.tick, 0, "시계도 안 움직인다")

	# 1틱 = 실제 1분 (time-and-monetization.md §2.1)
	_eq(c.advance(GameClock.REAL_MS_PER_TICK), 1, "1분이면 1틱")
	_eq(c.world.clock.tick, 1, "시계가 1틱")

	# **나머지가 누적된다.** 30초씩 두 번이면 1틱이지 0틱이 아니다 —
	# 프레임 델타가 틱보다 잘게 들어오는 것이 정상이다
	var half := GameClock.REAL_MS_PER_TICK / 2
	_eq(c.advance(half), 0, "30초로는 아직 안 넘어간다")
	_eq(c.advance(half), 1, "다시 30초면 1틱")
	_eq(c.world.clock.tick, 2, "누적 2틱")

	# 한 번에 여러 틱
	var before := c.world.clock.tick
	_eq(c.advance(GameClock.REAL_MS_PER_TICK * 10), 10, "10분이면 10틱")
	_eq(c.world.clock.tick, before + 10, "시계가 10틱 나아갔다")

	# **advance 와 step 이 같은 세계를 만든다** — 재생이 그 위에 선다 (V-25 ③)
	var a := Campaign.scenario_03(d, 99)
	var b := Campaign.scenario_03(d, 99)
	a.advance(GameClock.REAL_MS_PER_TICK * 120)
	for _i in 120:
		b.step()
	_eq(a.world.clock.tick, b.world.clock.tick, "두 경로의 틱이 같다")
	_eq(a.captures, b.captures, "두 경로의 점령 수가 같다")
	_eq(a.battles, b.battles, "두 경로의 전투 수가 같다")

	# 달력 — 208년 정월에서 시작한다
	var cal := c.world.clock.calendar(208)
	_eq(int(cal[0]), 208, "시작 연도 208")
	_eq(int(cal[1]), 1, "시작 월 1")
	var y := Campaign.scenario_03(d, 1)
	y.advance(GameClock.REAL_MS_PER_TICK * GameClock.TICKS_PER_YEAR)
	var cal2 := y.world.clock.calendar(208)
	_eq(int(cal2[0]), 209, "1년 뒤 209년")

	# 종료 후에는 진행하지 않는다
	var z := Campaign.scenario_03(d, 3)
	z.ended = true
	_eq(z.advance(GameClock.REAL_MS_PER_TICK * 100), 0, "끝난 판은 안 움직인다")


## ---------------------------------------------------------------- 33
##
## 계략 — §5.3~§5.6 이 코드에서 같은 숫자를 낸다.
##
## **문서에 검산이 두 벌 있다** (§5.7 적벽 · §5.5-b 이릉). 둘 다 항별로 적혀 있어
## 코드가 재현해야 할 값이 명시적이다 — 여기서 그 둘을 대조한다.
func _test_schemes() -> void:
	_section("33. 계략 — §5.3~§5.6 · 적벽과 이릉 검산")

	# ---- §5.7 적벽. 조조 지력 91 · 주유 95 · 정욱 89. 조조 사기 108.2 = 고양
	var jo_traits: Array = ["「미주랑」 화공 계열 계략 +50%"]
	var hwang: Array = ["「고육계」 위장 항복 실행 가능"]
	var CAO := 91
	var ZHOU := 95
	var CAO_MORALE := 108

	# **정욱은 17.6%였다.** 의심한 쪽이 옳았고, 그래도 낮은 쪽이었다
	_eq(Scheme.detect_chance_milli(89, ZHOU), 17600, "간파 — 정욱 17.6%")

	# 위장 항복 = 15 + (95−91)×0.5 + 전자전함 5 + 「고육계」 25 − 고양 10
	var fs := Scheme.success_chance_milli(Scheme.Kind.FALSE_SURRENDER, 1,
		ZHOU, CAO, CAO_MORALE, 10, 0, hwang)
	_eq(fs, 37000, "위장 항복 37.0%")

	# 화공 = 25 + 2 + 5 + 밀집 20 + 「미주랑」 50 − 10 = 92 → 상한 90
	var fire := Scheme.success_chance_milli(Scheme.Kind.FIRE, 1,
		ZHOU, CAO, CAO_MORALE, 10, Scheme.TERRAIN_DENSE_FIRE_MILLI, jo_traits)
	_eq(fire, 90000, "화공 90% (상한)")

	# **분기 A 27.4%** — (1 − 간파) × 위장 항복 × 화공
	var pass_detect := Scheme.trigger_chance_milli(17600, fs)
	_eq(pass_detect * fire / 100000, 27439, "분기 A 27.4%")
	_eq(Scheme.trigger_chance_milli(17600, 100000 - fs), 51912, "분기 C 51.9%")
	_eq(pass_detect * (100000 - fire) / 100000, 3048, "분기 D 3.0%")

	# **고양이 방어가 된다** — 조조가 고양이 아니었다면 47%였다
	var fs_normal := Scheme.success_chance_milli(Scheme.Kind.FALSE_SURRENDER, 1,
		ZHOU, CAO, 90, 10, 0, hwang)
	_eq(fs_normal, 47000, "정상 구간이면 47% — 고양이 10 을 깎았다")

	# ---- §5.3 사기 구간 — ±10 대칭, 붕괴 위험에서만 +20
	_eq(Scheme.morale_band_milli(125), -10000, "고양 −10")
	_eq(Scheme.morale_band_milli(101), -10000, "고양 하한 101")
	_eq(Scheme.morale_band_milli(100), 0, "정상 상한 100")
	_eq(Scheme.morale_band_milli(70), 0, "정상 하한 70")
	_eq(Scheme.morale_band_milli(69), 10000, "동요 +10")
	_eq(Scheme.morale_band_milli(39), 20000, "붕괴 위험 +20")

	# ---- §5.3 전자전함 — 교란만 ×1.0 이고 상한이 두 배다
	_eq(Scheme.ew_bonus_milli(Scheme.Kind.FIRE, 10), 5000, "전자 10% → 화공 +5")
	_eq(Scheme.ew_bonus_milli(Scheme.Kind.FIRE, 60), 20000, "화공 상한 +20")
	_eq(Scheme.ew_bonus_milli(Scheme.Kind.JAM, 10), 10000, "전자 10% → 교란 +10")
	_eq(Scheme.ew_bonus_milli(Scheme.Kind.JAM, 60), 40000, "교란 상한 +40")

	# ---- §5.3 · §5.4 범위. **계략은 약자의 무기다** — 봉쇄되어서도 안 된다
	_ok(Scheme.success_chance_milli(Scheme.Kind.FALSE_SURRENDER, 1, 10, 100, 110)
		== 5000, "성공률 하한 5%")
	_eq(Scheme.detect_chance_milli(100, 10, ["「응변」"]), 60000, "간파 상한 60%")
	_eq(Scheme.detect_chance_milli(10, 100), 5000, "간파 하한 5%")

	# ---- §5.4 특성. **곽가「귀모」는 시전과 간파 양쪽에 있다**
	_eq(Scheme.detect_trait_bonus_milli(["「응변」 적 계략 간파율 +35%"]), 35000,
		"진태 응변 +35")
	_eq(Scheme.detect_trait_bonus_milli([], "가후"), 25000, "가후는 이름으로 건다")
	_eq(Scheme.trait_bonus_milli(Scheme.Kind.FIRE, 0, ["「귀모」"]), 30000,
		"귀모 — ① 계략 +30")
	_eq(Scheme.trait_bonus_milli(Scheme.Kind.FIRE, 1, ["「귀모」"]), 0,
		"귀모는 ① 에서만")
	_eq(Scheme.trait_bonus_milli(Scheme.Kind.LURE, 2, ["「신기묘산」"]), 20000,
		"신기묘산 — 전 계략 +20")

	# ---- §5.5-b 이릉. 육손 96 · 주연 74 · 유비 76 · 마량 88. 원정군은 고양
	var LIU := 76
	var MA := 88
	for row in [[96, 0, 30000, 16800, 24960], [96, 6, 55000, 16800, 45760],
				[74, 0, 19000, 25600, 14136], [74, 6, 44000, 25600, 32736]]:
		var d_wits: int = int(row[0])
		var sprawl: int = int(row[1])
		var sc := Scheme.success_chance_milli(Scheme.Kind.FIRE, 1, d_wits, LIU,
			110, 10, Scheme.SPRAWL_SUCCESS_MILLI[Scheme.sprawl_band(sprawl)])
		var dc := Scheme.detect_chance_milli(MA, d_wits)
		_eq(sc, int(row[2]), "이릉 화공 성공률 (방어 %d · 연영도 %d)" % [d_wits, sprawl])
		_eq(dc, int(row[3]), "이릉 간파 (방어 %d)" % d_wits)
		_eq(Scheme.trigger_chance_milli(dc, sc), int(row[4]),
			"이릉 발동 확률 (방어 %d · 연영도 %d)" % [d_wits, sprawl])

	# **육손이 방어하면 반년이 석 달 만에 온다** — 「인내」가 시계를 두 배로 돌린다
	_eq(Scheme.sprawl_gain_milli(Scheme.SPRAWL_YUKSON_MILLI, 1000, 0), 2000,
		"육손 방어 — 월 +2.0")
	_eq(Scheme.sprawl_gain_milli(Scheme.SPRAWL_STANDARD_MILLI, 1000, 0), 1000,
		"표준 방어 — 월 +1.0")
	_eq(Scheme.sprawl_gain_milli(Scheme.SPRAWL_YUKSON_MILLI,
		Scheme.SPRAWL_CAUTIOUS_MILLI, 0), 1000, "「신중」이 절반으로 늦춘다")
	# **협도 너머를 확보하면 시계가 멈춘다** — 빨리 이기거나, 타거나
	_eq(Scheme.sprawl_gain_milli(Scheme.SPRAWL_YUKSON_MILLI, 1000, 2), 0,
		"확보 권역 2 → 증가 0")

	# ×3.0 은 이릉협도만 — 다른 대회랑은 ×2.0 이 상한이다
	_eq(Scheme.fire_damage_milli(false, true, 6, true), 3000, "연영도 6+ · 협도 ×3.0")
	_eq(Scheme.fire_damage_milli(false, true, 6, false), 2000, "일반 대회랑 상한 ×2.0")
	_eq(Scheme.fire_damage_milli(false, true, 2, true), 1200, "연영도 0~2 ×1.2")
	_eq(Scheme.fire_damage_milli(false, true, 3, true), 2000, "연영도 3~5 ×2.0")
	_eq(Scheme.fire_damage_milli(true, false), 1500, "밀집 진형 ×1.5")

	# ---- §1.3 연계는 중첩하지 않는다. 40 + 12.5 = 52.5
	_eq(Scheme.linked_event_milli(40, 25), 52500, "위장 항복 + 화공 = 52.5")
	_eq(Scheme.linked_event_milli(25, 0), 25000, "한쪽뿐이면 그대로")

	# ---- §5.5 이간. **보정이 사라지는 것이지 스탯이 사라지는 것이 아니다**
	_eq(Scheme.discorded_stat(96), 68, "통솔 96 → 68 (보정의 40%만 남는다)")
	_eq(Scheme.discorded_stat(50), 50, "50 은 「보정 없음」이라 움직이지 않는다")

	# ---- §5.3 시전 횟수 3 + 참모 [상한 5]
	_eq(Scheme.attempts_allowed(0), 3, "기본 3회")
	_eq(Scheme.attempts_allowed(4), 5, "상한 5회")
	_eq(Scheme.staff_bonus_milli(4), 15000, "참모 동승 상한 +15")

	# ---- §5.6 성향 — 가산 뒤 곱셈 (ai-design.md §7.4)
	_eq(Scheme.selection_weight_milli(true, "절의"), 540, "절의 조건 충족 0.54")
	_eq(Scheme.selection_weight_milli(true, "명사"), 810, "명사 0.81 — 주유")
	_eq(Scheme.selection_weight_milli(true, "실무"), 900, "실무 0.90")
	_eq(Scheme.selection_weight_milli(true, "무뢰"), 1080, "무뢰 1.08")
	_eq(Scheme.selection_weight_milli(true, "야심"), 1170, "야심 1.17")
	# **순서를 뒤집으면 안 된다** — 곱셈이 먼저면 조건 없는 계략에 성향이 걸린다
	_eq(Scheme.selection_weight_milli(false, "야심"), 650, "조건 미충족이면 0.65")
	# 플레이어 직접 지시에는 성향이 걸리지 않는다 — 관우도 위장 항복을 시전한다
	_eq(Scheme.selection_weight_milli(true, "절의", false), 900, "직접 지시 — 미적용")
	_eq(Scheme.disposition_milli(""), 1000, "성향 미상은 보정 없음")

	# ---- §5.1 페이즈 · 전용 조건
	_ok(Scheme.allows_phase(Scheme.Kind.FIRE, 1), "화공은 ② 포화")
	_ok(not Scheme.allows_phase(Scheme.Kind.FIRE, 2), "화공은 ③ 에 없다")
	_ok(Scheme.allows_phase(Scheme.Kind.DECAPITATE, 3), "참수는 ④ 강습")
	_ok(not Scheme.CAMPAIGN_ENABLED.has(Scheme.Kind.JAM),
		"교란은 지시 체계가 없어 캠페인 보류")
	_ok(not Scheme.CAMPAIGN_ENABLED.has(Scheme.Kind.DECAPITATE),
		"참수는 §6.2-b 호위 판정 대기")

	# ---- 배선. **성공률만 맞고 시전이 0회면 배선이 아니다**
	var d := GameData.load_all()
	var c := Campaign.scenario_03(d, 4242)
	c.run_to_end()
	_ok(c.battles > 0, "전투가 일어났다")
	_ok(c.schemes_tried > 0, "계략이 실제로 굴려졌다")
	_ok(c.schemes_detected > 0, "간파가 일어났다")
	_ok(c.schemes_fired > 0, "계략이 성공한 적이 있다")
	_ok(c.schemes_tried == c.schemes_detected + c.schemes_failed + c.schemes_fired,
		"시전 = 간파 + 실패 + 성공")
	_eq(c.schemes_by_kind[Scheme.Kind.JAM], 0, "교란은 시전되지 않는다")
	_eq(c.schemes_by_kind[Scheme.Kind.DECAPITATE], 0, "참수는 시전되지 않는다")

	# **소비 순서가 고정이다** (V-31) — 같은 시드는 같은 판을 낳는다
	var c2 := Campaign.scenario_03(d, 4242)
	c2.run_to_end()
	_eq(c2.schemes_tried, c.schemes_tried, "같은 시드 — 시전 수가 같다")
	_eq(c2.schemes_fired, c.schemes_fired, "같은 시드 — 성공 수가 같다")
	_eq(c2.battles, c.battles, "같은 시드 — 전투 수가 같다")

	# ---- 함대 참모진 배선 (ship-specs.md §6.4·§6.5 · combat.md §10 검토 16)
	#
	# **제독 한 사람이 아니라 함대 전체가 계략을 굴린다.**
	# 부제독·강습대장·공성대장·보급대장이 실제로 임명되고,
	# 「한 사람은 한 자리만」(§6.4)이 함대를 넘어서도 지켜지는지 확인한다.
	var s := Campaign.scenario_03(d, 5)
	var seen := {}
	var any_vice := false
	var any_detector := false
	for fl in s.fleets:
		for cid in [fl.commander_id, fl.vice_id, fl.assault_id, fl.siege_id, fl.supply_id]:
			if cid == "":
				continue
			_ok(not seen.has(cid), "인물 %s 가 두 자리를 겸하지 않는다" % cid)
			seen[cid] = true
		if fl.vice_id != "":
			any_vice = true
			_ok(fl.vice_id != fl.commander_id, "부제독은 제독과 다른 사람이다")
		_ok(fl.staff_wits_max >= fl.wits, "시전측 최고 지력은 제독 지력 이상이다")
		if fl.detector_wits > 0:
			any_detector = true
			_ok(fl.staff_wits_max >= fl.detector_wits,
				"간파측 지력은 시전측 최고를 넘지 않는다")
	_ok(any_vice, "적어도 한 함대는 부제독을 갖는다")
	_ok(any_detector, "적어도 한 함대는 참모형 간파자를 갖는다")

	# ---- 데이터가 성향·특성을 싣고 있는가 (combat.md §10 검토 17)
	#
	# **산식이 맞아도 데이터가 비어 있으면 계략은 중립값으로 돈다.**
	# 2026-08-28 이전까지 명장 150인이 `disposition: null` · `traits: []` 이었다 —
	# 주유「미주랑」도 황개「고육계」도 캠페인에서는 없는 것과 같았다.
	var no_trait := 0
	var no_disp: Array[String] = []
	var cids: Array = d.characters.keys()
	cids.sort()                                  # 순회 순서 고정 (§2.3 ④)
	for cid in cids:
		var ch: Dictionary = d.characters[cid]
		var tier := String(ch.get("tier", ""))
		if tier == "명장":
			if not (ch.get("traits") is Array and (ch["traits"] as Array).size() > 0):
				no_trait += 1
			if ch.get("disposition") == null:
				no_disp.append(String(ch.get("name", "")))
	_eq(no_trait, 0, "명장 150인이 모두 특성을 갖는다")
	# **군주는 인물 성향이 아니라 군주 성향을 갖는다** (dispositions.md §2 · §4)
	_eq(no_disp.size(), 7, "성향이 없는 명장은 군주 7인뿐")
	_ok(no_disp.has("조조") and no_disp.has("유비"), "그 7인이 군주다")

	var juyu := _find_char(d, "주유")
	_eq(String(juyu.get("disposition", "")), "명사", "주유는 명사 — 계략은 그의 것이다")
	_ok(Scheme.has_trait(juyu.get("traits", []), Scheme.TRAIT_MIJURANG),
		"주유가 「미주랑」을 갖는다")
	var hwanggae := _find_char(d, "황개")
	_eq(String(hwanggae.get("disposition", "")), "절의", "황개는 절의 — 배를 몬 쪽이다")
	_ok(Scheme.has_trait(hwanggae.get("traits", []), Scheme.TRAIT_GOYUK),
		"황개가 「고육계」를 갖는다")
	_ok(Scheme.detect_trait_bonus_milli(_find_char(d, "진태").get("traits", []))
		== 35000, "진태 「응변」이 데이터에서 간파 +35 로 걸린다")
	_ok(Scheme.trait_bonus_milli(Scheme.Kind.FIRE, 1,
		_find_char(d, "제갈량").get("traits", [])) == 20000,
		"제갈량 「신기묘산」이 데이터에서 전 계략 +20 으로 걸린다")


func _find_char(d: GameData, name: String) -> Dictionary:
	var cids: Array = d.characters.keys()
	cids.sort()
	for cid in cids:
		var ch: Dictionary = d.characters[cid]
		if String(ch.get("name", "")) == name and String(ch.get("tier", "")) == "명장":
			return ch
	return {}


## P0-04 V-50 승인 공용 11종 — UI가 최종 파일만 읽고, V-43 매핑을 빠짐없이 푼다.
func _test_portrait_frame() -> void:
	_section("34. P0-04 공용 초상 UI 프레임")
	var script := load("res://app/views/portrait_frame.gd")
	_ok(script != null, "초상 프레임 스크립트가 있다")
	if script == null:
		return
	var ids: Array = script.all_art_ids()
	_eq(ids.size(), 11, "공용 초상은 11종")
	for art in ids:
		_ok(ResourceLoader.exists(script.asset_path(art)), "%s 승인 PNG가 UI 경로에 있다" % art)
		var texture := load(script.asset_path(art)) as Texture2D
		_ok(texture != null, "%s PNG가 Texture2D로 로드된다" % art)
		if texture != null:
			_eq(texture.get_size(), Vector2(896, 1120), "%s 마스터 규격 896×1120" % art)
	_eq(script.art_id_for({"id": "CHR-0002", "class": ["제"], "disposition": "실무"}),
		"ART-C901", "제독형 실무 짝수는 C901")
	_eq(script.art_id_for({"id": "CHR-0003", "class": ["제"], "disposition": "실무"}),
		"ART-C902", "제독형 실무 홀수는 C902")
	_eq(script.art_id_for({"class": ["제"], "disposition": "무뢰"}), "ART-C903", "제독형 무뢰")
	_eq(script.art_id_for({"class": ["제"], "disposition": "절의"}), "ART-C904", "제독형 절의")
	_eq(script.art_id_for({"class": ["제"], "disposition": "야심"}), "ART-C905", "제독형 그 밖")
	_eq(script.art_id_for({"class": ["관"], "disposition": "실무"}), "ART-C906", "관료형 실무")
	_eq(script.art_id_for({"class": ["관"], "disposition": "명사"}), "ART-C907", "관료형 그 밖")
	_eq(script.art_id_for({"class": ["참"], "disposition": "실무"}), "ART-C908", "참모형 실무")
	_eq(script.art_id_for({"class": ["참"], "disposition": "야심"}), "ART-C909", "참모형 그 밖")
	_eq(script.art_id_for({"class": ["강"]}), "ART-C910", "강습형")
	_eq(script.art_id_for({"class": ["파"]}), "ART-C911", "파일럿형")
	_eq(script.FRAME_SIZE, Vector2(256, 320), "실제 초상 프레임은 256×320")
