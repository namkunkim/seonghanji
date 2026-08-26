class_name Sim
extends RefCounted

## 시뮬레이션 코어 진입점 (roadmap-solo.md §5.1 · dev-requirements.md §2.3)
##
## **이 클래스는 시계의 출처를 모른다.**
##
##     [코어]  advance(world, dt) -> world'        ← 시계의 출처를 모른다
##     [단기]  게임 루프 델타 × 배속  → advance(dt)   앱이 켜져 있는 동안만
##     [장기]  서버 벽시계 경과분      → advance(dt)   앱이 꺼져 있어도
##
## 단기판의 「명령 중에도 시간이 흐른다」와 장기판의 「접속하지 않아도 세계가
## 나아간다」는 **같은 함수의 두 호출자**다. 이 하나를 지키면 S2 의 코어를
## L3 온라인 전환 때 그대로 쓴다. 어기면 규칙이 두 벌이 되고, §2.3 이
## 「반드시 어긋난다」고 경고한 바로 그 지점이 된다.
##
## 결정론 요건 (dev-requirements.md §2.3):
##   - 부동소수 금지. 정수 또는 고정소수만 쓴다
##   - 시드 기반 난수 · 시드 저장 · **소비 순서 고정**
##   - 컬렉션 순회 순서 고정 (Dictionary 순회 금지, 정렬된 키를 쓴다)

const RULESET_VERSION := "RS-0.1.0"


## 실제 경과(정수 밀리초)만큼 세계를 나아가게 한다.
## 넘어간 게임 내 날 수를 돌려준다.
##
## 호출자가 세션 루프든 서버든 **이 함수는 구분하지 않는다.**
## **틱을 하나씩 밟는다.** 시계를 한 번에 밀어 올린 뒤 루프를 돌면
## 루프 내내 `clock.tick` 이 최종값에 고정되어, 「지금 몇 틱인가」에 의존하는
## 처리가 전부 어긋난다 (2026-08-24: 연 정산이 11번 대신 7,920번 돌았다).
static func advance(world: World, elapsed_ms: int) -> int:
	var ticks := world.clock.take_ticks(elapsed_ms)
	for _i in ticks:
		world.clock.step_ticks(1)
		_advance_one_tick(world)
	return ticks


## 재생·검증 전용. dt 를 거치지 않고 틱 단위로 진행한다.
## 헤드리스 시뮬레이터(S2.6)와 세이브 재생이 이 경로를 쓴다.
static func step_ticks(world: World, n: int) -> void:
	for _i in n:
		world.clock.step_ticks(1)
		_advance_one_tick(world)


## 한 틱 진행. **모든 세계 변화가 여기를 지난다.**
##
## 호출 순서를 바꾸면 결정론이 깨진다. 순서 자체가 규칙이다.
static func _advance_one_tick(world: World) -> void:
	_deliver_commands(world)   # ① 도달한 명령을 반영 (사자 지연, V-25 ④)
	_settle_year(world)        # ② 내정 정산 — 연 1회 전화 회복 (S2.4)
	# ③ 함대 이동      — S3 에서
	# ④ 전투 해결      — 판정 요소는 S2.5, 진행 루프는 S3
	_think(world)              # ⑤ AI 판단 — 계층별 주기 (S2.6)
	# ⑥ 이벤트 판정    — 기능 이벤트 40 (미착수)
	world.tick_count += 1


## 연 1회 정산. 전화 회복이 여기서 돈다 (region-power.md §3.5).
##
## **회복은 매 틱이 아니라 매년이다.** 산식이 연 단위 체감형이고,
## 틱마다 돌리면 720분의 1을 반올림하다 값이 뭉개진다.
static func _settle_year(world: World) -> void:
	if world.clock.tick == 0 or world.clock.tick % Domestic.RECOVERY_PERIOD_TICKS != 0:
		return
	if world.data == null:
		return
	# **정렬된 ID 로만 순회한다** — Dictionary 순회는 순서가 보장되지 않는다
	for rid in world.data.region_ids:
		var st: RegionState = world.region_states.get(rid)
		if st != null:
			Domestic.apply_recovery(st, world.clock.tick)


## AI 판단. **계층마다 주기가 다르다** (ai-design.md §2).
##
##   Grand        게임 내 계절 = 180틱
##   Operational  게임 내 월   =  60틱
##
## 결정 빈도가 낮은 것이 성능상 큰 이점이다 —
## 항행에 45분~3시간 45분이 걸리므로 AI 는 매 틱 사고할 필요가 없다.
##
## 두 주기가 겹치는 틱(180의 배수)에서는 **Grand 를 먼저** 돌린다.
## 상위 계층의 목표가 하위 계층의 입력이기 때문이다 — 순서가 규칙이다.
static func _think(world: World) -> void:
	if world.data == null or world.clock.tick == 0:
		return
	if world.clock.tick % Strategy.GRAND_PERIOD_TICKS == 0:
		world.ai_grand_runs += 1
	if world.clock.tick % Strategy.OPERATIONAL_PERIOD_TICKS == 0:
		world.ai_operational_runs += 1


## 발행 시각과 도달 시각이 다르다 (V-25 ④ 「사자 왕복」).
## 오늘 도달한 명령만 반영한다.
static func _deliver_commands(world: World) -> void:
	var now := world.clock.tick
	world.last_arrived.clear()
	var arrived: Array = []
	for c in world.pending_commands:
		if int(c.get("arrival_tick", now)) <= now:
			arrived.append(c)
	# 순회 순서를 고정한다 — 발행 시각, 그 다음 발행 순번
	arrived.sort_custom(func(a, b):
		if a["issued_tick"] != b["issued_tick"]:
			return a["issued_tick"] < b["issued_tick"]
		return a["seq"] < b["seq"])
	for c in arrived:
		world.pending_commands.erase(c)
		world.applied_commands.append(c)
		world.last_arrived.append(c)
