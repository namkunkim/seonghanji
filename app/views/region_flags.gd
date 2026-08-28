class_name RegionFlags
extends RefCounted

## SC-L2 **주목 권역 표면화**의 판정 (`screens.md` §2.4)
##
## > 45권역 전부를 신경 쓰지 않게 하는 것이 `ui-design.md` §6.3 의 약속이다.
##
## | 상태 | 카드 |
## |---|---|
## | 분쟁 중 · 비지 위험 · 공략 중 · 명령 완료 | 펼침 |
## | 위임 · 평시 · 변화 없음 | 한 줄로 접힘 |
##
## 넷 중 **셋만 코어에서 나온다.** 「공략 중」은 코어에 없다 —
## `Campaign._capture()` 는 전투 결과로 소유를 **한 번에** 바꾸며,
## `partial-occupation.md` 의 4층(외곽→궤도권→식민지→지구형 행성)은
## 진행 상태로 존재하지 않는다. 그래서 진행도 바를 그릴 값이 없다.

## **명령 완료로 볼 기간.** 도달 후 게임 내 1개월(60틱) 동안 카드를 펼친다.
const RECENT_COMMAND_TICKS: int = GameClock.TICKS_PER_MONTH


## 분쟁 중인가.
##
## `screens.md` §2.2 는 분쟁을 **「두 세력 이상이 나눠 가진 성역」**으로 적었다.
## 그러나 §2.1 도해는 형주 셋 중 **중부권에만** ⚔ 를 붙인다 — 남부권도 같은 성역인데 없다.
## 그러므로 표식은 성역이 아니라 **그 성역 안에서 다른 소유와 맞닿은 권역**에 붙는다.
## 성역 밖 접경(남부권 ↔ 교주)은 세지 않는다. 도해가 그렇게 되어 있다.
static func contested(data: GameData, c: Campaign, rid: String) -> bool:
	var st: RegionState = c.world.region_states.get(rid)
	if st == null:
		return false
	if st.contested:
		return true
	var sid := data.system_of(rid)
	for nb in data.region_adjacency.get(rid, []):
		if data.system_of(nb) != sid:
			continue
		var ns: RegionState = c.world.region_states.get(nb)
		if ns != null and ns.owner != st.owner:
			return true
	return false


## 같은 세력이 쥔 인접 권역의 수. 비지 판정의 재료다.
static func friendly_neighbors(data: GameData, c: Campaign, rid: String) -> int:
	var st: RegionState = c.world.region_states.get(rid)
	if st == null or st.owner == "":
		return 0
	var n := 0
	for nb in data.region_adjacency.get(rid, []):
		var ns: RegionState = c.world.region_states.get(nb)
		if ns != null and ns.owner == st.owner:
			n += 1
	return n


## 비지인가. **코어와 같은 규칙이다** —
## `Campaign._settle_month()` 이 같은 조건으로 안정도 −8 을 매월 먹인다.
static func enclave(data: GameData, c: Campaign, rid: String) -> bool:
	var st: RegionState = c.world.region_states.get(rid)
	if st == null or st.owner == "":
		return false
	return friendly_neighbors(data, c, rid) == 0


## 비지 **위험**. 아직 비지는 아니나 이어진 곳이 하나뿐이다 —
## 그 하나를 잃으면 다음 달부터 안정도가 깎인다.
static func enclave_risk(data: GameData, c: Campaign, rid: String) -> bool:
	var st: RegionState = c.world.region_states.get(rid)
	if st == null or st.owner == "":
		return false
	return friendly_neighbors(data, c, rid) == 1


## 최근 이 권역에 명령이 **도달**했는가 (V-25 ④ — 발행과 도달은 다르다).
static func command_done(c: Campaign, rid: String) -> Dictionary:
	var now := c.world.clock.tick
	var best := {}
	for cmd in c.world.applied_commands:
		var p: Dictionary = cmd.get("payload", {})
		if String(p.get("region", "")) != rid:
			continue
		var at := int(cmd.get("arrival_tick", 0))
		if now - at > RECENT_COMMAND_TICKS:
			continue
		if best.is_empty() or at >= int(best.get("arrival_tick", 0)):
			best = cmd
	return best


## 이 권역으로 **발행되어 아직 도달하지 않은** 명령 수.
static func commands_pending(c: Campaign, rid: String) -> int:
	var n := 0
	for cmd in c.world.pending_commands:
		var p: Dictionary = cmd.get("payload", {})
		if String(p.get("region", "")) == rid:
			n += 1
	return n


## 카드를 펼칠 것인가 (§2.4).
static func notable(data: GameData, c: Campaign, rid: String) -> bool:
	var st: RegionState = c.world.region_states.get(rid)
	if st == null:
		return false
	if st.delegated:
		return false                      # 위임 권역은 시야에서 접힌다 (§6.3)
	if contested(data, c, rid):
		return true
	if enclave(data, c, rid) or enclave_risk(data, c, rid):
		return true
	if not command_done(c, rid).is_empty():
		return true
	return false


## 위험도. **필터 「위험순」의 눈금이다** — 정본이 아니라 이 화면의 정렬 기준이다.
static func danger(data: GameData, c: Campaign, rid: String) -> int:
	var st: RegionState = c.world.region_states.get(rid)
	if st == null:
		return 0
	var v := Stability.MAX - st.stability
	if enclave(data, c, rid):
		v += 40
	elif enclave_risk(data, c, rid):
		v += 12
	if contested(data, c, rid):
		v += 25
	return v
