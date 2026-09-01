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
const CURRENT_RULESET := "RS-0.1.0"

const STATUS_OK := "ok"
const STATUS_OLD_MINOR := "old_minor"
const STATUS_PARTIAL_RECOVERY := "partial_recovery"
const STATUS_CORRUPT := "corrupt"
const STATUS_MAJOR_MISMATCH := "major_mismatch"
const STATUS_NEWER_MINOR := "newer_minor"
const STATUS_VERIFICATION_FAILED := "verification_failed"


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


## 손상·규칙 세대 판정과 재생을 분리한다 (save-contract §3.2·§3.5).
## 부분 손상이면 첫 손상 명령 직전으로 로그와 목표 틱을 함께 잘라 건너뛰기를 막는다.
static func inspect(d: Dictionary, current_ruleset: String = CURRENT_RULESET) -> Dictionary:
	var bad := _required_campaign_error(d)
	if bad != "":
		return _inspection(STATUS_CORRUPT, false, bad, d)
	var w: Dictionary = d["world"]
	var saved_version := _parse_ruleset(String(w["ruleset"]))
	var current_version := _parse_ruleset(current_ruleset)
	if saved_version.is_empty():
		return _inspection(STATUS_CORRUPT, false, "world.ruleset: RS-X.Y.Z 형식이 아니다", d)
	if current_version.is_empty():
		return _inspection(STATUS_CORRUPT, false, "현재 ruleset: RS-X.Y.Z 형식이 아니다", d)
	if saved_version[0] != current_version[0]:
		return _inspection(STATUS_MAJOR_MISMATCH, false,
			"major 불일치 — 세이브 마이그레이션이 필요하다", d)
	if saved_version[1] > current_version[1]:
		return _inspection(STATUS_NEWER_MINOR, false, "현재 빌드보다 새 minor 세이브다", d)
	var cmds: Array = w["commands"]
	for i in cmds.size():
		var cmd_error := _command_error(cmds[i], i)
		if cmd_error == "":
			continue
		var repaired: Dictionary = d.duplicate(true)
		var safe_commands: Array = []
		for j in i:
			safe_commands.append(cmds[j])
		var corrupt_tick := int(cmds[i].get("issued_tick", 0)) if cmds[i] is Dictionary else 0
		var safe_tick := mini(int(w["game_tick"]), maxi(0, corrupt_tick))
		repaired["world"]["commands"] = safe_commands
		repaired["world"]["game_tick"] = safe_tick
		var out := _inspection(STATUS_PARTIAL_RECOVERY, true,
			"%s — 이후 로그 폐기, %d개월 시점으로 복원됨"
			% [cmd_error, safe_tick / GameClock.TICKS_PER_MONTH], repaired)
		out["restored_tick"] = safe_tick
		out["restored_month"] = safe_tick / GameClock.TICKS_PER_MONTH
		return out
	if saved_version[1] < current_version[1]:
		var old := _inspection(STATUS_OLD_MINOR, true,
			"세이브 minor 규칙으로 재생 — 시나리오 경계 승격은 후속", d)
		old["ruleset"] = String(w["ruleset"])
		return old
	return _inspection(STATUS_OK, true, "정상", d)


static func _inspection(status: String, loadable: bool, detail: String,
		d: Dictionary) -> Dictionary:
	return {"status": status, "loadable": loadable, "detail": detail, "save": d}


static func _parse_ruleset(value: String) -> Array[int]:
	var re := RegEx.new()
	if re.compile("^RS-([0-9]+)\\.([0-9]+)\\.([0-9]+)$") != OK:
		return []
	var m := re.search(value)
	if m == null:
		return []
	return [int(m.get_string(1)), int(m.get_string(2)), int(m.get_string(3))]


## Godot JSON 파서는 정수 토큰도 float 로 돌려줄 수 있다. 스키마의 integer 는
## 런타임 타입이 아니라 소수부 없는 유한 수라는 뜻으로 검사한다.
static func _is_json_integer(value) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and value == floor(value)


static func _required_campaign_error(d: Dictionary) -> String:
	var extra := _unexpected_key(d, ["save_version", "world", "campaign"])
	if extra != "":
		return "%s: 허용되지 않은 키" % extra
	for key in ["save_version", "world", "campaign"]:
		if not d.has(key):
			return "%s: 필수 키가 없다" % key
	if not _is_json_integer(d["save_version"]):
		return "save_version: 정수가 아니다"
	if not d["world"] is Dictionary:
		return "world: 객체가 아니다"
	if not d["campaign"] is Dictionary:
		return "campaign: 객체가 아니다"
	var w: Dictionary = d["world"]
	extra = _unexpected_key(w, ["ruleset", "scenario", "seed", "game_tick",
		"player_faction", "capital", "commands", "save_version"])
	if extra != "":
		return "world.%s: 허용되지 않은 키" % extra
	for key in ["ruleset", "scenario", "seed", "game_tick", "commands"]:
		if not w.has(key):
			return "world.%s: 필수 키가 없다" % key
	if not w["ruleset"] is String:
		return "world.ruleset: 문자열이 아니다"
	if not w["scenario"] is String or String(w["scenario"]) != "SCN-03":
		return "world.scenario: 단기판은 SCN-03 이어야 한다"
	if not _is_json_integer(w["seed"]):
		return "world.seed: 정수가 아니다"
	if not _is_json_integer(w["game_tick"]) or int(w["game_tick"]) < 0:
		return "world.game_tick: 0 이상의 정수가 아니다"
	if not w["commands"] is Array:
		return "world.commands: 배열이 아니다"
	var cd: Dictionary = d["campaign"]
	extra = _unexpected_key(cd, ["hb_milli", "ai_domestic_enabled", "digest",
		"ended", "end_reason"])
	if extra != "":
		return "campaign.%s: 허용되지 않은 키" % extra
	for key in ["hb_milli", "ai_domestic_enabled", "digest"]:
		if not cd.has(key):
			return "campaign.%s: 필수 키가 없다" % key
	if not _is_json_integer(cd["hb_milli"]):
		return "campaign.hb_milli: 정수가 아니다"
	if not cd["ai_domestic_enabled"] is bool:
		return "campaign.ai_domestic_enabled: 불리언이 아니다"
	if not _is_json_integer(cd["digest"]):
		return "campaign.digest: 정수가 아니다"
	return ""


static func _unexpected_key(d: Dictionary, allowed: Array) -> String:
	for key in d.keys():
		if not allowed.has(String(key)):
			return String(key)
	return ""


static func _command_error(value, index: int) -> String:
	if not value is Dictionary:
		return "world.commands[%d]: 객체가 아니다" % index
	var c: Dictionary = value
	var extra := _unexpected_key(c,
		["seq", "issued_tick", "arrival_tick", "kind", "payload"])
	if extra != "":
		return "world.commands[%d].%s: 허용되지 않은 키" % [index, extra]
	for key in ["seq", "issued_tick", "kind"]:
		if not c.has(key):
			return "world.commands[%d].%s: 필수 키가 없다" % [index, key]
	if not _is_json_integer(c["seq"]) or int(c["seq"]) < 0:
		return "world.commands[%d].seq: 0 이상의 정수가 아니다" % index
	if not _is_json_integer(c["issued_tick"]) or int(c["issued_tick"]) < 0:
		return "world.commands[%d].issued_tick: 0 이상의 정수가 아니다" % index
	if not c["kind"] is String or String(c["kind"]) == "":
		return "world.commands[%d].kind: 비어 있지 않은 문자열이어야 한다" % index
	if c.has("arrival_tick") and c["arrival_tick"] != null and not _is_json_integer(c["arrival_tick"]):
		return "world.commands[%d].arrival_tick: 정수 또는 null 이어야 한다" % index
	if c.has("payload") and not c["payload"] is Dictionary:
		return "world.commands[%d].payload: 객체가 아니다" % index
	return ""


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


## 파일 파싱 실패를 빈 정상 사전과 구분한다 (§3.5).
static func inspect_file(path: String, current_ruleset: String = CURRENT_RULESET) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _inspection(STATUS_CORRUPT, false, "파일을 열 수 없다: %s" % path, {})
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or not json.data is Dictionary:
		return _inspection(STATUS_CORRUPT, false,
			"JSON 파싱 실패: %s" % json.get_error_message(), {})
	return inspect(json.data, current_ruleset)
