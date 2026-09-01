class_name Save
extends RefCounted

## 세이브 입출력 (data-model.md §5.4 · schema/save.json · V-25 ③)
##
## ## 세이브는 「상태」가 아니라 「시드 + 명령 로그」다
##
## 세계를 통째로 저장하지 않는다. **마스터 시드와 명령 로그만 남기고,
## 불러올 때는 처음부터 다시 돌린다.**
##
## | 얻는 것 | |
## |---|---|
## | 용량 | 명령 수백 개면 몇 KB 다 |
## | 재현 | 버그 보고에 세이브 하나면 그 상황이 그대로 재현된다 |
## | 조작 탐지 | 명령 로그를 다시 돌려 결과가 다르면 손댄 것이다 |
##
## **대가는 불러오기가 곧 재생이라는 것이다.** 5.8개월짜리 캠페인이면
## 재생에 시간이 걸린다 — 그래서 규칙 버전을 고정하고(§5.3) 스냅샷을
## 함께 두는 것이 다음 과제다 (아래 검토 포인트).
##
## ## 재생이 옳았는지 어떻게 아는가
##
## `digest()` 가 세계의 지문을 낸다. **저장 전과 재생 후의 지문이 같아야 한다.**
## 다르면 어딘가에서 결정론이 깨진 것이다 — 그것을 잡는 것이 이 함수의 목적이다.

const SAVE_VERSION := 1


## ---------------------------------------------------------------- 내보내기
##
## **AI 가 발행한 명령(`origin == "ai"`)은 담지 않는다.** 재생 중 `step()` 이
## 결정론적으로 다시 발행하므로, 저장하면 재생 시 이중 발행되어 지문이 갈린다
## (save-contract §2.3 전제 2 · A-03 origin 규약). `origin` 키가 없으면 플레이어
## 명령으로 본다 — 기존 UI 호출부는 수정 없이 이 기본값에 잡힌다.
static func to_dict(world: World) -> Dictionary:
	var cmds: Array = []
	for c in world.applied_commands:
		if _is_ai(c):
			continue
		cmds.append(_cmd(c))
	for c in world.pending_commands:
		if _is_ai(c):
			continue
		cmds.append(_cmd(c))
	# **발행 순번으로 정렬한다.** 적용분과 대기분을 이어 붙이면 순서가 섞인다.
	# AI 명령을 걸러낸 뒤라 순번은 불연속일 수 있다 — 재생 시 `_seq` 처리는 `replay`.
	cmds.sort_custom(func(a, b): return a["seq"] < b["seq"])
	return {
		"ruleset": world.ruleset,
		"scenario": world.scenario,
		"seed": world.rng_seed,
		"game_tick": world.clock.tick,
		"player_faction": world.player_faction,
		"capital": world.capital,
		"commands": cmds,
	}


static func _cmd(c: Dictionary) -> Dictionary:
	return {
		"seq": int(c["seq"]),
		"issued_tick": int(c["issued_tick"]),
		"arrival_tick": int(c.get("arrival_tick", c["issued_tick"])),
		"kind": String(c["kind"]),
		"payload": c.get("payload", {}),
	}


## AI 발행 명령인가. `to_dict` 가 이것으로 거른다 (위 주석).
static func _is_ai(c: Dictionary) -> bool:
	return String(c.get("origin", "player")) == "ai"


## ---------------------------------------------------------------- 불러오기 = 재생
##
## **처음부터 다시 돌린다.** 명령을 전부 대기열에 넣고 목표 틱까지 진행하면,
## 각 명령이 제 도달 시각에 반영된다.
static func replay(d: Dictionary, data: GameData,
		damage: Dictionary = Power.WAR_DAMAGE_208_MILLI) -> World:
	var w := World.new()
	w.ruleset = String(d.get("ruleset", "RS-0.1.0"))
	w.scenario = String(d.get("scenario", "SCN-03"))
	w.rng_seed = int(d.get("seed", 0))
	w.player_faction = String(d.get("player_faction", ""))
	w.attach(data, String(d.get("capital", "")))
	w.load_war_damage(damage)

	var cmds: Array = d.get("commands", [])
	var sorted_cmds := cmds.duplicate()
	sorted_cmds.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
	var max_seq := -1
	for c in sorted_cmds:
		w.pending_commands.append({
			"seq": int(c["seq"]),
			"issued_tick": int(c["issued_tick"]),
			"arrival_tick": int(c["arrival_tick"]),
			"kind": String(c["kind"]),
			"payload": c.get("payload", {}),
			"origin": String(c.get("origin", "player")),
		})
		max_seq = maxi(max_seq, int(c["seq"]))
	# **저장된 명령은 AI 명령이 걸러진 뒤라 순번이 불연속이다** (`to_dict` 주석).
	# `size()` 로 잡으면 재생 중 새로 발행되는 명령이 기존 순번과 충돌할 수 있다 —
	# 마지막 순번 다음부터 잇는다. World 단독 재생(순번이 0 부터 연속)에서는
	# `max_seq + 1 == size()` 이므로 기존 동작과 같다.
	w._seq = max_seq + 1

	Sim.step_ticks(w, int(d.get("game_tick", 0)))
	return w


## ---------------------------------------------------------------- 지문
##
## 세계 상태를 하나의 수로 접는다. **재생이 옳았는지 판정하는 근거다.**
##
## 순회는 **정렬된 ID 로만** 한다 — Dictionary 순회는 순서가 보장되지 않으므로
## 그대로 쓰면 지문 자체가 결정론을 깬다.
static func digest(world: World) -> int:
	var h := 0
	h = _fold(h, world.clock.tick)
	h = _fold(h, world.tick_count)
	h = _fold(h, world.rng_seed)
	h = _fold(h, world.applied_commands.size())
	h = _fold(h, world.pending_commands.size())
	h = _fold(h, Rng._hash_string(world.ruleset + "|" + world.scenario))
	if world.data != null:
		for rid in world.data.region_ids:
			var st: RegionState = world.region_states.get(rid)
			if st == null:
				continue
			h = _fold(h, st.war_damage_milli)
			h = _fold(h, st.development)
			h = _fold(h, st.garrison)
			h = _fold(h, st.recovery_investment)
			h = _fold(h, Rng._hash_string(st.owner))
	for c in world.applied_commands:
		h = _fold(h, int(c["seq"]))
		h = _fold(h, int(c["arrival_tick"]))
	return h


static func _fold(h: int, v: int) -> int:
	return Rng._mix(h ^ Rng._mix(v))


## ---------------------------------------------------------------- 파일
static func write_file(world: World, path: String) -> bool:
	var d := to_dict(world)
	d["save_version"] = SAVE_VERSION
	return write_dict(d, path)


## 임의 사전을 세이브 파일로 쓴다. 캠페인 세이브(`Campaign.write_save` ·
## schema/save-campaign.json)가 이것을 쓴다 — World 세이브와 파일 형식(들여쓴 JSON)을
## 공유한다.
static func write_dict(d: Dictionary, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "  "))
	return true


static func read_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
