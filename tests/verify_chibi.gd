extends SceneTree

## 적벽 재현 검산 — 코드 재계산 대 문서값 (combat.md §5.7)
##
## 실행: godot --headless --path . --script tests/verify_chibi.gd
##
## **이것은 합격/불합격 시험이 아니라 대조표다.** 어긋남 자체가 산출물이다.
##
## §5.7 은 J6 이 **손으로** 굴린 검산이고, 그 뒤 전제가 세 번 움직였다 —
## V-29(74 대 48) · V-37(101 대 46) · V-38(전대 28척).
## **손 계산은 전제가 움직일 때마다 낡는다.** 여기서 코드가 다시 굴린다.
##
## 계략 확률(간파 17.6% · 위장 항복 37.0% · 화공 90%)은 **사기 구간**에서 나오고
## 전력비와 무관하므로 그대로다. 바뀌는 것은 **각 분기에서 손유가 얼마나 버티는가**다.

## 표준 편성 (§4.3.3 균형)
const RATIO: Array[int] = [40, 20, 15, 10, 5, 10]

## 함종 × 페이즈 계수 (§4.3 · 1/1000). 보급함 ⑤ 는 「사기 유지」라 0.4 로 둔다
const COEFF: Array = [
	[800, 1000, 1600, 900, 1100],      # 전열함
	[900, 1800, 700, 500, 800],        # 포격함
	[700, 600, 800, 2000, 1000],       # 강습모함
	[1900, 1100, 900, 700, 600],       # 전자전함
	[500, 1200, 600, 800, 500],        # 공성함
	[400, 400, 500, 400, 400],         # 보급함
]

## §5.7 전제
const CAO_SHIPS: int = 2367
const ALLY_SHIPS: int = 1078
const CAO_MORALE0: int = 109           # 108.8
const ALLY_MORALE0: int = 116          # 115.6
const CAO_CMD: int = 96
const ZHOU_CMD: int = 96
## 페이즈별 판정 스탯 (§4.3 PHASE_STAT: 지력·지력·통솔·무력·통솔)
const CAO_STAT: Array[int] = [91, 91, 96, 72, 96]
const ZHOU_STAT: Array[int] = [95, 95, 96, 72, 96]

## §5.7 계략 판정의 전제. 정욱은 **참모형**이라 간파를 맡는다 (§5.2)
const JEONGUK_WITS: int = 89
## 표준 편성의 전자전함 비율(%p) — §5.3 의 「전자전함 5」가 여기서 나온다
const EW_PCT: int = 10

## 문서값 (1.54배 시절 손 계산)
const DOC_B: Array[int] = [108, 104, 94, 89, 88]      # 조조 · 분기 B
const DOC_B_ALLY: Array[int] = [110, 84, 58, 39, 32]  # 손유 · 분기 B


## 표준 편성의 페이즈 계수 (1/1000)
static func plan_coeff(phase: int) -> int:
	var v := 0
	for i in RATIO.size():
		v += RATIO[i] * int(COEFF[i][phase])
	return v / 100


func _init() -> void:
	print("")
	print("적벽 재현 검산 — combat.md §5.7 재실행")
	print("전제: 조조 %d척 · 손유 %d척 = %.2f배 (V-37·V-38)" % [
		CAO_SHIPS, ALLY_SHIPS, float(CAO_SHIPS) / float(ALLY_SHIPS)])
	print("")

	print("표준 편성 페이즈 계수")
	var line := "  "
	for p in 5:
		line += "%s %.3f  " % [Battle.PHASE_NAMES[p], plan_coeff(p) / 1000.0]
	print(line)
	print("")

	_schemes()

	# **E 는 양수로 넣는다** — §1.3 이 Δ사기 = −[L×k + D + E] 이므로
	# 양수 E 가 사기를 깎는다. 2026-08-25: 처음에 음수로 넣어 사기가 올랐다.
	_branch("분기 B — 정욱이 간파 (계략 무효 · 손유 사기 −15)", 15000, 0, 0)
	_branch("분기 C — 위장 항복 실패 (계략 불발 · 보정 없음)", 0, 0, 0)
	# **화공은 사기만 깎지 않는다.** §5.7 이 「L 33.1%(화공 30 + 통상 3.1)」라 적었다 —
	# 손실률에 30%p 가 얹히고, 그 손실이 다시 사기를 깎는다 (§1.3 Δ = −[L×k + D + E]).
	_branch("분기 A — 화공 성공 (조조 ② 손실 +30%p · 사기 E 52.5)", 0, 52500, 30000)

	print("")
	print("문서값 (1.54배 시절 손 계산 · combat.md §5.7)")
	print("  분기 B  조조 108 → 88.1 · 손유 110 → 32.0 · 붕괴 판정 10.2%")
	print("  분기 C  조조 108 → 87.7 · 손유 110 → 44.0")
	print("")
	print("⚠ 대조표다. 어긋남이 곧 산출물이며 합격/불합격을 매기지 않는다.")
	quit(0)


## 5페이즈를 굴린다. ally_event 는 손유에게, cao_event 는 조조에게 걸리는 Δ사기(밀리).
func _branch(title: String, ally_event: int, cao_event: int,
		cao_loss_bonus: int) -> void:
	print(title)
	print("  %-6s %8s %8s %8s   %s" % ["페이즈", "조조", "손유", "전력비", "손유 붕괴"])
	var cao := CAO_MORALE0
	var ally := ALLY_MORALE0
	var cao_n := CAO_SHIPS
	var ally_n := ALLY_SHIPS
	var collapse_worst := 0
	for p in 5:
		var c := plan_coeff(p)
		var pc := Battle.combat_power_milli(cao_n, c, CAO_STAT[p], p, cao)
		var pa := Battle.combat_power_milli(ally_n, c, ZHOU_STAT[p], p, ally)
		var ratio := float(pc) / float(maxi(pa, 1))

		# 손실 반영 (§1.3 L)
		var lc := Battle.loss_rate_milli(p, pc, pa)
		var la := Battle.loss_rate_milli(p, pa, pc)

		# 화공의 손실 가산 — ② 포화 한정
		if p == 1 and cao_loss_bonus > 0:
			lc += cao_loss_bonus
		# Δ사기 = −[ L×k + D + E ] (§1.3). 가산 손실이 사기에도 반영되도록 직접 계산한다.
		var dc := -((lc * Battle.MORALE_K_MILLI[p] / 1000
			+ Battle.pressure_milli(pc, pa)
			+ (cao_event if p == 1 else 0)) / 1000)
		var da := Battle.morale_delta(p, pa, pc, ally_event if p == 1 else 0)
		cao = clampi(cao + dc, 0, Battle.MORALE_MAX)
		ally = clampi(ally + da, 0, Battle.MORALE_MAX)
		cao_n = cao_n - cao_n * lc / 100000
		ally_n = ally_n - ally_n * la / 100000

		var col := Battle.collapse_chance_pct(ally, ZHOU_CMD)
		collapse_worst = maxi(collapse_worst, col)
		var mark := ""
		if ally <= Battle.MORALE_COLLAPSE_FLOOR:
			mark = "  ★ 즉시 붕괴"
		elif col > 0:
			mark = "  %d%%" % col
		print("  %-6s %8d %8d %8.2f   %s" % [
			Battle.PHASE_NAMES[p], cao, ally, ratio, mark])
		if ally <= Battle.MORALE_COLLAPSE_FLOOR:
			break
	print("  잔존   조조 %d척 · 손유 %d척 · 손유 최대 붕괴 확률 %d%%" % [
		cao_n, ally_n, collapse_worst])
	print("")


## ---------------------------------------------------------------- 계략 (§5.3~§5.5)
##
## **§5.7 이 항별로 적어 둔 세 확률을 `core/combat/scheme.gd` 로 다시 굴린다.**
##
## 사기 곡선과 달리 **여기는 전력비에 둔감하다** — 계략 확률은 지력 대결과
## 사기 구간에서 나오므로 V-37(2.20배) 이 이 값들을 건드리지 않는다.
## 그래서 이 표는 대조가 아니라 **일치해야 하는 표**다.
func _schemes() -> void:
	# 조조 사기 108.2 = **고양 구간**. 그 사실 자체가 방어가 된다
	var band := CAO_MORALE0 - 1              # ② 진입 시점 108
	var jo: Array = ["「미주랑」 화공 계열 계략 +50%"]
	var hg: Array = ["「고육계」 위장 항복 실행 가능"]

	# 간파는 **참모형이 맡는다** (§5.2) — 조조(91)가 아니라 정욱(89)이다.
	# 캠페인은 참모 편성이 없어 제독으로 대신한다. 그 어긋남을 여기 남긴다.
	var detect := Scheme.detect_chance_milli(JEONGUK_WITS, ZHOU_STAT[1])
	var detect_cao := Scheme.detect_chance_milli(CAO_STAT[1], ZHOU_STAT[1])
	var fs := Scheme.success_chance_milli(Scheme.Kind.FALSE_SURRENDER, 1,
		ZHOU_STAT[1], CAO_STAT[1], band, EW_PCT, 0, hg)
	var fire := Scheme.success_chance_milli(Scheme.Kind.FIRE, 1,
		ZHOU_STAT[1], CAO_STAT[1], band, EW_PCT,
		Scheme.TERRAIN_DENSE_FIRE_MILLI, jo)

	print("② 포화 — 계략 판정 (§5.3 · §5.4)")
	print("  %-22s %10s %10s" % ["판정", "문서값", "코드"])
	_line("간파 (정욱 89)", 17600, detect)
	_line("위장 항복 (황개)", 37000, fs)
	_line("화공 (주유 · 밀집)", 90000, fire)
	print("")

	var passed := Scheme.trigger_chance_milli(detect, fs)
	print("네 갈래 (§5.7)")
	print("  %-22s %10s %10s" % ["경로", "문서값", "코드"])
	_line("A. 화공 성공", 27400, passed * fire / 100000)
	_line("B. 정욱이 간파", 17600, detect)
	_line("C. 위장 항복 실패", 51900, Scheme.trigger_chance_milli(detect, 100000 - fs))
	_line("D. 화공만 실패", 3000, passed * (100000 - fire) / 100000)
	print("")
	print("  ⚠ 고양이 아니었다면 위장 항복은 %.1f%% 였다 — **잘 이끌린 함대는 속지 않는다**"
		% [Scheme.success_chance_milli(Scheme.Kind.FALSE_SURRENDER, 1,
			ZHOU_STAT[1], CAO_STAT[1], 90, EW_PCT, 0, hg) / 1000.0])
	print("  ⚠ 간파를 제독(조조 91)으로 굴리면 %.1f%% 다 — 참모 편성이 붙기 전 캠페인의 값"
		% [detect_cao / 1000.0])
	print("")


## **문서는 0.1%까지 적는다** (27.4%). 그 눈금에서 대조한다 —
## 27.439% 를 「어긋남」으로 찍으면 표가 거짓말을 한다.
func _line(label: String, doc_milli: int, code_milli: int) -> void:
	var rounded := (code_milli + 50) / 100 * 100
	var mark := "" if doc_milli == rounded else "   ← 어긋남"
	print("  %-22s %9.1f%% %9.1f%%%s" % [
		label, doc_milli / 1000.0, code_milli / 1000.0, mark])
