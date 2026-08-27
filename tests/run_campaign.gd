extends SceneTree

## M0 헤드리스 시뮬레이터 (dev-requirements.md §9 · ai-design.md §11.1)
##
## > **화면 하나 없이 시나리오가 AI 대 AI로 100회 자동 진행되어
## > 세력 승률 분포가 출력되는 것** — 이것이 M0 의 산출물이다.
##
## 실행: godot --headless --path . --script tests/run_campaign.gd
##
## 합격 기준 (§11.1)
## | 지표 | 목표 |
## |---|---|
## | 역사 재현율 | 40~60% |
## | 세력별 승률 편차 | 최대·최소 3배 이내 |
## | 조기 종료율 | 20% 이하 |

const RUNS := 100


## **주역 세력** — 승률 편차를 재는 집합 (ai-design.md §11.1-b · V-40).
##
## `scenario-setup.md` §4.2 실효 국력표에 오른 세력 중 통치 체제가 「암약」이 아닌 쪽.
## 유장은 암약(「확장 의사 자체가 없다」)이라 빠지고, 유비는 유랑 세력이라 미구현이다.
##
## **변경 소국의 「존속 100%」는 역사적으로 옳다** — 공손씨는 요동에서 삼대를 이었다.
## 그것을 밸런스 실패로 세면 고증을 깎게 된다.
const PROTAGONISTS: Array[String] = ["조조", "손권", "유종"]


func _init() -> void:
	var data := GameData.load_all()
	print("SEONGHANJI — 시나리오 3 「적벽 전야」 AI 대 AI %d회" % RUNS)
	print("")

	var states := {}
	var leaders := {}
	var early := 0
	var historical := 0
	var wins := {}                 # 세력 → 목표 달성 횟수
	var total_battles := 0
	var total_captures := 0
	var total_issued := 0
	var total_applied := 0
	var total_built := 0
	var total_austerity := 0
	var fired := {}
	var total_backstab := 0
	var total_revolt := 0
	var total_broken := 0
	var total_ticks := 0
	var t0 := Time.get_ticks_msec()

	for run in RUNS:
		var c := Campaign.scenario_03(data, 1000 + run)
		c.hb_milli = Strategy.HB_STANDARD_MILLI
		c.run_to_end()
		var ws := c.world_state()
		var ld := c.leader()
		if c.historical_outcome():
			historical += 1
		for fid in c.faction_ids:
			if not wins.has(fid):
				wins[fid] = 0
			if c.achieved(fid):
				wins[fid] += 1
		states[ws] = int(states.get(ws, 0)) + 1
		leaders[ld] = int(leaders.get(ld, 0)) + 1
		if c.end_reason == "조기 종료":
			early += 1
		total_battles += c.battles
		total_captures += c.captures
		total_issued += c.cmds_issued
		total_applied += c.cmds_applied
		total_built += c.fleets_built
		total_austerity += c.austerity_events
		for eid in c.events_fired:
			fired[eid] = int(fired.get(eid, 0)) + int(c.events_fired[eid])
		total_backstab += c.backstabs
		total_revolt += c.revolts
		total_broken += c.alliances_broken
		total_ticks += c.world.clock.tick

	var elapsed := Time.get_ticks_msec() - t0
	print("완주 %d회 · %.1f초 · 회당 %.0fms" % [RUNS, elapsed / 1000.0, float(elapsed) / RUNS])
	print("평균 전투 %.1f회 · 점령 %.1f회 · 진행 %.0f틱"
		% [float(total_battles) / RUNS, float(total_captures) / RUNS, float(total_ticks) / RUNS])
	print("")

	print("종료 시 세계 상태")
	var keys: Array = states.keys()
	keys.sort()
	for k in keys:
		print("  %-8s %3d회  %5.1f%%" % [k, states[k], states[k] * 100.0 / RUNS])
	print("")

	print("기능 이벤트 — 발동 (function-events.md)")
	var ek: Array = fired.keys()
	ek.sort()
	var line := "  "
	for eid in ek:
		line += "%s %d회  " % [eid, int(fired[eid])]
	print(line if not ek.is_empty() else "  발동 없음")
	var missing: Array[String] = []
	for eid in Events.IMPLEMENTED:
		if not fired.has(eid):
			missing.append(eid)
	print("  구현 %d종 중 발동 %d · **미발동 %d** %s" % [
		Events.IMPLEMENTED.size(), ek.size(), missing.size(),
		("— " + ", ".join(missing)) if not missing.is_empty() else ""])
	print("  미구현 %d종 (인물 %d · 기타 %d)" % [
		Events.NEEDS_CHARACTERS.size() + Events.NEEDS_OTHER.size(),
		Events.NEEDS_CHARACTERS.size(), Events.NEEDS_OTHER.size()])
	print("  회당 배후 기습 %.1f · 후방 반란 %.1f · 연합 해체 %.1f"
		% [float(total_backstab) / RUNS, float(total_revolt) / RUNS,
		   float(total_broken) / RUNS])
	print("")

	print("내정 (S2.9 · AI 판단)")
	print("  회당 명령 발행 %.1f · 적용 %.1f · 함대 건조 %.1f · 재정 파탄 %.1f"
		% [float(total_issued) / RUNS, float(total_applied) / RUNS,
		   float(total_built) / RUNS, float(total_austerity) / RUNS])
	print("")

	# **세력별 목표 달성률** — §11.1 의 「승률」은 이쪽이다.
	# 실동원 1위로 재면 웅크린 세력이 이긴다 (Campaign.achieved 주석 참조).
	print("세력별 목표 달성률")
	print("  %-10s %6s   %s" % ["세력", "달성", "목표"])
	var goal := {
		"조조": "남북 대치 돌파 (중부권/건업권 획득)",
		"손권": "존속 + 병립 유지 (분치)",
	}
	var wk: Array = wins.keys()
	wk.sort()
	var rates: Array[int] = []
	for k in wk:
		var g: String = goal.get(k, "본거지 존속")
		print("  %-10s %5.1f%%   %s" % [k, wins[k] * 100.0 / RUNS, g])
		if PROTAGONISTS.has(k):
			rates.append(int(wins[k]))
	print("")

	print("최강 실동원 분포 (참고 — 승률 아님)")
	var lk: Array = leaders.keys()
	lk.sort()
	for k in lk:
		print("  %-8s %3d회  %5.1f%%" % [k, leaders[k], leaders[k] * 100.0 / RUNS])
	print("")

	# ---- 합격 기준 (§11.1)
	print("합격 기준 — ai-design.md §11.1")
	var pass_count := 0
	var checks := 0

	# 역사 재현 — **손권 존속 · 조조가 건업권/중부권 미보유** (Campaign.historical_outcome)
	# 「종료 시 삼국형」으로 재던 것은 무뎠다. 아무 일도 없어도 삼국형이기 때문이다.
	var hist_pct := historical * 100.0 / RUNS
	checks += 1
	var ok_hist := hist_pct >= 40.0 and hist_pct <= 60.0
	if ok_hist:
		pass_count += 1
	print("  역사 재현율 %5.1f%%  목표 40~60%%   %s" % [hist_pct, "통과" if ok_hist else "미달"])

	# 조기 종료율
	var early_pct := early * 100.0 / RUNS
	checks += 1
	var ok_early := early_pct <= 20.0
	if ok_early:
		pass_count += 1
	print("  조기 종료율 %5.1f%%  목표 20%% 이하  %s" % [early_pct, "통과" if ok_early else "미달"])

	# 세력별 편차 — **주역 세력의 목표 달성률**로 잰다 (ai-design.md §11.1-b · V-40).
	# 최강 실동원이 아니고, 변경 소국도 아니다.
	var vals := rates.duplicate()
	vals.sort()
	checks += 1
	var ok_spread := false
	var spread := 0.0
	if vals.size() >= 2 and vals[0] > 0:
		spread = float(vals[vals.size() - 1]) / float(vals[0])
		ok_spread = spread <= 3.0
	if ok_spread:
		pass_count += 1
	print("  세력 승률 편차 %.1f배  목표 3배 이내  %s   [주역 %s]"
		% [spread, "통과" if ok_spread else ("미달" if vals.size() >= 2 else "판정 불가"),
		   ", ".join(PROTAGONISTS)])

	print("")
	print("합격 %d/%d" % [pass_count, checks])
	print("")

	# ---- HB 모드 비교 — **계수가 실제로 작동하는가**
	# §6.2 는 「역사가 자연스럽게 재현되되 강제되지 않아야 한다」고 했다.
	# HB 를 올리면 재현율이 올라야 그 장치가 작동하는 것이다.
	print("HB 모드 비교 — ai-design.md §6.2")
	print("%-12s %6s %8s %8s" % ["모드", "HB", "재현율", "일극형"])
	print("-".repeat(38))
	for mode in [["자유 역사", Strategy.HB_FREE_MILLI],
				 ["표준", Strategy.HB_STANDARD_MILLI],
				 ["역사 중시", Strategy.HB_HISTORICAL_MILLI]]:
		var h := 0
		var one := 0
		for run in RUNS:
			var c := Campaign.scenario_03(data, 1000 + run)
			c.hb_milli = int(mode[1])
			c.run_to_end()
			if c.historical_outcome():
				h += 1
			if c.world_state() == "일극형":
				one += 1
		print("%-12s %5.2f %7.1f%% %7.1f%%"
			% [mode[0], mode[1] / 1000.0, h * 100.0 / RUNS, one * 100.0 / RUNS])
	print("")
	print("⚠ 미구현이라 판정하지 않은 것: 기능 이벤트 40종(미발동 0 지표) ·")
	print("  천명 · 계략 · 외교/동맹 · 군주 인격 프로파일 · 참모 의견")
	quit(0)
