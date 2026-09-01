extends SceneTree

## 캠페인 저장·복원 재생 — A-01 (save-contract.md §4.2 · V-62)
##
## **이 세션(A-01)의 범위는 인수 조건 1·2 다** — 캠페인 지문이 존재하고,
## 저장 전 지문 = 순수 로그 재생 후 지문. 조건 3~7 의 정식 시험은 A-02
## (`tests/run_save_restore.gd`). 여기서는 3·4 를 미리보기로만 확인한다.
##
## 추가로 **불러오기 시간 실측** — save-contract 검토 포인트 1(경계 스냅숏
## 도입 판정의 근거는 A-01 의 불러오기 시간 실측)에 답한다.
##
## 실행: godot --headless --path . --script tests/run_campaign_replay.gd
## 종료: 통과 0 / 실패 비0 (tests/harness.gd 규약)

const Harness := preload("res://tests/harness.gd")

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  ✗ %s" % msg)


func _eq(a, b, msg: String) -> void:
	_ok(a == b, "%s  (%s != %s)" % [msg, str(a), str(b)])


func _init() -> void:
	var data := GameData.load_all()
	print("캠페인 저장·복원 재생 — A-01 (save-contract §4.2 조건 1·2)")
	print("")

	_test_digest_exists(data)
	_test_save_before_equals_replay_after(data)
	_test_file_round_trip(data)
	_test_mid_save_does_not_change_final(data)
	_test_tamper_changes_digest(data)
	_measure_load_time(data)

	print("")
	print("통과 %d · 실패 %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)


## 조건 1 — 캠페인 지문이 존재하고 상태에 민감하다.
func _test_digest_exists(data: GameData) -> void:
	print("1. 캠페인 지문 존재 · 상태 민감도")
	var a := Campaign.scenario_03(data, 1000)
	var b := Campaign.scenario_03(data, 1001)
	_ok(a.digest() != 0, "지문이 0 이 아니다")
	_ok(a.digest() != b.digest(), "시드가 다르면 초기 지문이 다르다")
	var d0 := a.digest()
	a.replay_to(360)
	_ok(a.digest() != d0, "6개월 진행하면 지문이 바뀐다")
	print("")


## 조건 2 — 저장 전 지문 = 순수 로그 재생 후 지문 (캠페인 도중).
func _test_save_before_equals_replay_after(data: GameData) -> void:
	print("2. 저장 전 = 재생 후 (캠페인 도중)")
	for seed in [1000, 1042, 1077]:
		var c := Campaign.scenario_03(data, seed)
		var target := 720                     # 1년 — 조기 종료 전
		c.replay_to(target)
		if c.ended:
			print("  · 시드 %d 는 %d틱 전에 종료 — 종료 틱으로 대상 조정" % [seed, target])
			target = c.world.clock.tick
		var before := c.digest()
		var save := c.to_save_dict()
		_eq(save["world"]["commands"].size(), 0,
			"시드 %d — M0 는 플레이어 명령 0 (AI 명령은 직렬화 제외)" % seed)
		var r := Campaign.from_save(save, data)
		_eq(r.world.clock.tick, c.world.clock.tick, "시드 %d — 재생 틱 일치" % seed)
		_eq(r.digest(), before, "시드 %d — 저장 전 지문 = 재생 후 지문" % seed)
		_eq(int(save["campaign"]["digest"]), before,
			"시드 %d — 세이브에 박힌 지문 = 저장 시점 지문" % seed)
	print("")


## 조건 2 — 파일 왕복 (프로세스 경계 없이 디스크만).
func _test_file_round_trip(data: GameData) -> void:
	print("3. 파일 왕복")
	var c := Campaign.scenario_03(data, 2024)
	c.replay_to(540)
	if c.ended:
		c = Campaign.scenario_03(data, 2024)
		c.replay_to(180)
	var before := c.digest()
	var path := "user://test_campaign_save.json"
	_ok(c.write_save(path), "파일 저장")
	var r := Campaign.read_save(path, data)
	_eq(r.digest(), before, "파일에서 복원한 지문 일치")
	_eq(int(r.hb_milli), int(c.hb_milli), "hb_milli 복원")
	_eq(r.ai_domestic_enabled, c.ai_domestic_enabled, "ai_domestic_enabled 복원")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("")


## 조건 4 미리보기 — 도중 저장·복원이 최종 지문을 바꾸지 않는다.
func _test_mid_save_does_not_change_final(data: GameData) -> void:
	print("4. 도중 저장·복원이 최종 지문을 바꾸지 않는다 (조건 4 미리보기)")
	for seed in [1000, 1055]:
		var straight := Campaign.scenario_03(data, seed)
		straight.run_to_end()
		var final_a := straight.digest()

		var c := Campaign.scenario_03(data, seed)
		c.replay_to(480)
		var save := c.to_save_dict()
		var r := Campaign.from_save(save, data)
		r.run_to_end()
		_eq(r.digest(), final_a,
			"시드 %d — 도중 저장 후 이어 진행한 최종 지문 = 무저장 최종 지문" % seed)
	print("")


## 조건 3 미리보기 — 입력 1비트를 바꾸면 재생 지문이 갈린다.
## 정식 변조 검증은 A-02 (`run_save_restore.gd`).
func _test_tamper_changes_digest(data: GameData) -> void:
	print("5. 변조 시 지문 불일치 (조건 3 미리보기 — 정식은 A-02)")
	var c := Campaign.scenario_03(data, 777)
	c.replay_to(600)
	var save := c.to_save_dict()
	var origin := c.digest()

	var t_seed: Dictionary = save.duplicate(true)
	t_seed["world"]["seed"] = 778
	_ok(Campaign.from_save(t_seed, data).digest() != origin,
		"시드를 바꾸면 재생 지문이 갈린다")

	var t_tick: Dictionary = save.duplicate(true)
	t_tick["world"]["game_tick"] = int(t_tick["world"]["game_tick"]) + 60
	_ok(Campaign.from_save(t_tick, data).digest() != origin,
		"목표 틱을 바꾸면 재생 지문이 갈린다")

	var t_hb: Dictionary = save.duplicate(true)
	t_hb["campaign"]["hb_milli"] = int(t_hb["campaign"]["hb_milli"]) + 100
	_ok(Campaign.from_save(t_hb, data).digest() != origin,
		"hb_milli 를 바꾸면 재생 지문이 갈린다 (외생 입력이 재생에 걸린다)")
	print("")


## 불러오기 시간 실측 — save-contract 검토 포인트 1.
##
## **경계 스냅숏 도입 여부는 이 수치로 판정한다.** 순수 로그 재생만으로
## 전장(全長) 캠페인 복원이 허용 밖이면 그때 스냅숏을 넣는다 (§3.4).
func _measure_load_time(data: GameData) -> void:
	print("6. 불러오기 시간 실측 (검토 포인트 1)")
	print("  기계: 개발 머신 · headless · Godot 4.7.2 · 단일 스레드")
	var seeds := [1000, 1011, 1022, 1033, 1044]
	var total_ms := 0.0
	var total_ticks := 0
	for seed in seeds:
		# 전장 캠페인을 만들어 종료까지 돌리고 저장한다
		var c := Campaign.scenario_03(data, seed)
		c.run_to_end()
		var save := c.to_save_dict()
		var end_tick: int = int(save["world"]["game_tick"])
		# 저장 = 재생이므로, from_save 한 번이 전장 재생 한 번이다
		var t0 := Time.get_ticks_msec()
		var r := Campaign.from_save(save, data)
		var dt := Time.get_ticks_msec() - t0
		total_ms += dt
		total_ticks += end_tick
		var okd := r.digest() == c.digest()
		print("  시드 %d — %4d틱 재생 %6.0fms  지문 %s"
			% [seed, end_tick, dt, "일치" if okd else "✗불일치"])
		_ok(okd, "시드 %d — 전장 재생 지문 일치" % seed)
	var n := seeds.size()
	print("  평균 — %.0f틱 재생 %.0fms  (틱당 %.2fms)"
		% [float(total_ticks) / n, total_ms / n,
		   total_ms / maxf(1.0, float(total_ticks))])
	print("  판정 근거: 전장 재생 평균 %.0fms." % (total_ms / n))
	print("    · 1초 미만이면 순수 로그 재생 유지 — 경계 스냅숏 불요 (§3.4 미결 시 처리)")
	print("    · 수 초 이상이면 A-01 후속에서 경계 스냅숏 도입 검토")
	print("")
