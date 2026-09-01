class_name World
extends RefCounted

## 세계 상태 (S2.2 에서 본격 확장)
##
## 지금은 **시간 모델 검증에 필요한 최소 골격**만 담는다.
## 권역·세력·함대는 S2.2 에서 붙인다.
##
## 세이브는 이 객체 전체가 아니라 **「시드 + 명령 로그」**다
## (data-model.md §5.4 · schema/save.json). 상태를 통째로 저장하지 않는 이유는
## 용량이 작고, 재생 가능하고, 조작 탐지가 쉽기 때문이다.

var clock: GameClock = GameClock.new()

## 정본 데이터. 없으면 명령 지연을 산정할 수 없다 (issue_to)
var data: GameData = null

## 항로망 그래프. data 를 붙일 때 함께 만든다
var graph: Dictionary = {}

## 본거지 성계. 명령은 여기서 출발한다 (사자 지연의 기점)
var capital: String = ""

## 권역별 가변 상태. RGN-xx → RegionState
## **순회는 data.region_ids(정렬됨)로만 한다** — Dictionary 순회는 결정론을 깬다
var region_states: Dictionary = {}

## 규칙 집합 버전. 시나리오 경계에서만 승격한다 (data-model.md §5.3)
## Sim.RULESET_VERSION 을 참조하지 않는다 — 클래스 상호 참조를 만들지 않기 위함
var ruleset: String = "RS-0.1.0"

## 시나리오. 단기판은 SCN-03(적벽 전야) 하나만 쓴다
var scenario: String = "SCN-03"

## 난수 시드. 소비 순서 고정이 전제다 (dev-requirements.md §2.3)
## 이름을 rng_seed 로 둔다 — `seed` 는 GDScript 전역 함수라 가린다
var rng_seed: int = 0

## 플레이어 세력. 단기판 기본값은 손권 (roadmap-solo.md §1.2)
var player_faction: String = ""

## 아직 도달하지 않은 명령. 발행 시각과 도달 시각이 다르다 (V-25 ④)
var pending_commands: Array[Dictionary] = []

## 도달해 반영된 명령. 재생의 입력이 된다
var applied_commands: Array[Dictionary] = []

## **이번 틱에 도달한 명령.** 매 틱 새로 채워진다.
##
## `Sim` 은 세력을 모른다 — 시간 모델만 안다. 그래서 효과를 붙이지 못하고
## **도달했다는 사실만 여기 남긴다.** 세력을 쥔 `Campaign` 이 이것을 읽어 적용한다.
## 계층을 섞지 않으려는 분리이며, 덕분에 `Sim` 단독 시험이 그대로 산다.
var last_arrived: Array[Dictionary] = []

## 진행한 틱 수. clock.tick 과 일치해야 한다 — 검증용 이중 계수
var tick_count: int = 0

## AI 계층별 판단 횟수. 주기가 옳게 도는지 확인하는 계수다 (ai-design.md §2)
var ai_grand_runs: int = 0
var ai_operational_runs: int = 0

## 발행 순번. 재생이 이어 붙일 수 있어야 하므로 Save 가 직접 쓴다.
var _seq: int = 0


## 명령을 발행한다. 도달까지 걸리는 날 수를 함께 준다.
##
## 「사자 왕복 1.5시간」이 연출이 아니라 실제 지연이 되는 지점이다
## (roadmap-solo.md §1.4).
##
## `origin` — 이 명령이 어디서 왔는가. **재생과 저장이 갈린다** (save-contract 전제 2 ·
## A-01 조율). `"player"` = 외생 입력 → 저장 로그에 기록하고 재생 시 주입한다.
## `"ai"` = `Strategy`/AI 판단이 낸 것 → 재생 중 `step()` 이 결정론적으로 재발행하므로
## 저장하지 않는다 (저장하면 이중 발행). 기본값 `"player"` — 기존 UI 호출부는 그대로.
func issue(kind: String, payload: Dictionary = {}, delay_ticks: int = 0,
		origin: String = "player") -> Dictionary:
	var c := {
		"seq": _seq,
		"issued_tick": clock.tick,
		"arrival_tick": clock.tick + delay_ticks,
		"kind": kind,
		"payload": payload,
		"origin": origin,
	}
	_seq += 1
	pending_commands.append(c)
	return c


## 정본 데이터를 붙인다. 항로망 그래프를 함께 만든다.
func attach(d: GameData, capital_system: String = "") -> void:
	data = d
	graph = Routing.build_graph(d)
	capital = capital_system
	region_states.clear()
	for rid in d.region_ids:
		region_states[rid] = RegionState.new()


## 시나리오의 전화 계수를 권역에 싣는다. 성계 이름 → 계수(1/1000).
func load_war_damage(damage_by_system: Dictionary) -> void:
	for rid in data.region_ids:
		var sname := data.system_name(data.system_of(rid))
		if damage_by_system.has(sname):
			region_states[rid].war_damage_milli = int(damage_by_system[sname])


## 목적 권역으로 명령을 보낸다. **지연을 코어가 산정한다.**
##
## 사자는 본거지에서 목적 권역의 성계까지 항로망을 지난다.
## 소요는 `time-and-monetization.md` §3.1 그대로다 — 고속항로 45분 · 대회랑 3시간 45분.
##
## 편도다. 「명령이 도달한다」이지 「보고를 받는다」가 아니다.
## 왕복(§3.4.2 결정형 ACT 의 「사자 왕복 1.5시간」)이 필요하면 두 번 잡는다.
##
## 닿지 않는 곳이면 -1 을 돌려주고 명령을 만들지 않는다 —
## 회랑이 끊기면 명령 자체가 가지 못한다 (「봉쇄는 성립한다」).
func issue_to(kind: String, region_id: String, payload: Dictionary = {},
		origin: String = "player") -> Dictionary:
	assert(data != null, "attach() 로 데이터를 먼저 붙인다")
	assert(capital != "", "본거지 성계가 필요하다")
	var dest := data.system_of(region_id)
	var t := Routing.travel_ticks(graph, capital, dest)
	if t == Routing.UNREACHABLE:
		return {}
	var p := payload.duplicate()
	p["region"] = region_id
	return issue(kind, p, t, origin)


## ---------------------------------------------------------------- 난수
##
## **직접 난수기를 만들지 않는다.** 반드시 이 둘을 지난다 —
## 그래야 (마스터 시드, 영역, 틱) 유도가 한 곳에 모인다 (core/rng.gd).

## 그 영역·이 틱 전용 난수 흐름. 소비 순서는 이 안에서만 문제가 된다.
func rng(domain: int) -> RngStream:
	return Rng.stream(rng_seed, domain, clock.tick)


## 대상이 정해진 판정. **호출 순서와 무관하다.**
## 등용 3중 판정처럼 인물마다 굴리는 것에 쓴다.
func roll_pct(domain: int, key: String, salt: int = 0) -> int:
	return Rng.roll_pct_for(rng_seed, domain, clock.tick, key, salt)

# 세이브 직렬화는 `Save.to_dict(world)` 하나가 정본이다 (save-contract 검토 8).
# 이전의 `World.to_save()` 는 호출부가 없고 형식이 `Save.to_dict` 와 미묘하게
# 달랐다(capital 누락 · 정렬·origin 필터 없음) — 이원화를 없애려 삭제했다.
