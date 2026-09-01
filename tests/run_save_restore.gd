extends SceneTree

## 저장 복원 정식 인수 시험 — A-02 (save-contract §3.2·§3.5·§4.2).
const Harness := preload("res://tests/harness.gd")
var _pass := 0
var _fail := 0
var _skip := 0

func _ok(cond: bool, msg: String) -> void:
	if cond: _pass += 1
	else:
		_fail += 1
		print("  ✗ %s" % msg)

func _eq(a, b, msg: String) -> void:
	_ok(a == b, "%s  (%s != %s)" % [msg, str(a), str(b)])

func _init() -> void:
	print("저장 복원 층 — A-02 정식 인수")
	var data := GameData.load_all()
	_test_normal_and_tamper(data)
	_test_file_mid_restore()
	_test_snapshot_boundary_skip()
	_test_ruleset_isolation(data)
	_test_determinism_guards(data)
	_test_monthly_round_trip(data)
	_test_corruption(data)
	_test_fleet_is_derived(data)
	print("\n통과 %d · 스킵 %d · 실패 %d" % [_pass, _skip, _fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _campaign_with_player_move(data: GameData, seed: int, target_tick: int = 240) -> Campaign:
	var c := Campaign.scenario_03(data, seed)
	var fl: Fleet
	for candidate in c.fleets:
		if candidate.owner == "손권":
			fl = candidate
			break
	var target := ""
	for rid in data.region_ids:
		if data.system_of(rid) != fl.at_system:
			var route := Orders.resolve_move(c.world.graph, data, fl.at_system, rid)
			if bool(route["ok"]):
				target = rid
				break
	c.world.issue(Domestic.CMD_FLEET_MOVE,
		{"faction": "손권", "fleet": fl.id, "region": target}, 0, "player")
	c.replay_to(target_tick)
	return c

func _test_normal_and_tamper(data: GameData) -> void:
	print("1. 정상 저장 · 변조 검출 (다중 시드)")
	for seed in [711, 733, 755]:
		var c := _campaign_with_player_move(data, seed)
		var save := c.to_save_dict()
		var normal := Campaign.from_save_result(save, data)
		_eq(normal["status"], Save.STATUS_OK, "시드 %d 정상 status" % seed)
		_eq(normal["actual_digest"], normal["expected_digest"], "시드 %d 정상 양방향 지문" % seed)
		var variants: Array[Dictionary] = []
		var changed: Dictionary = save.duplicate(true)
		changed["world"]["seed"] = int(changed["world"]["seed"]) + 1
		variants.append(changed)
		changed = save.duplicate(true)
		changed["world"]["commands"][0]["arrival_tick"] = int(changed["world"]["commands"][0]["arrival_tick"]) + 1
		variants.append(changed)
		changed = save.duplicate(true)
		changed["world"]["commands"][0]["payload"]["fleet"] = int(changed["world"]["commands"][0]["payload"]["fleet"]) + 1
		variants.append(changed)
		changed = save.duplicate(true)
		changed["campaign"]["hb_milli"] = int(changed["campaign"]["hb_milli"]) + 1
		variants.append(changed)
		changed = save.duplicate(true)
		changed["campaign"]["digest"] = int(changed["campaign"]["digest"]) + 1
		variants.append(changed)
		for variant in variants:
			_eq(Campaign.from_save_result(variant, data)["status"],
				Save.STATUS_VERIFICATION_FAILED, "시드 %d 변조 검출" % seed)
	print("")

func _test_file_mid_restore() -> void:
	print("2. 중간 파일 저장 · 새 데이터 로더 복원 · 최종 지문")
	for seed in [811, 833]:
		var straight := Campaign.scenario_03(GameData.load_all(), seed)
		straight.run_to_end()
		var c := Campaign.scenario_03(GameData.load_all(), seed)
		c.replay_to(480)
		var path := "user://a02_mid_%d.json" % seed
		_ok(c.write_save(path), "시드 %d 파일 저장" % seed)
		var loaded := Campaign.read_save_result(path, GameData.load_all())
		_eq(loaded["status"], Save.STATUS_OK, "시드 %d 파일 로드 검증" % seed)
		var resumed: Campaign = loaded["campaign"]
		resumed.run_to_end()
		_eq(resumed.digest(), straight.digest(), "시드 %d 최종 지문 불변" % seed)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("")

func _test_snapshot_boundary_skip() -> void:
	print("3. 경계 스냅숏 ↔ 로그 재생")
	_skip += 1
	print("  SKIP — 경계 스냅숏 미도입. 전장 순수 로그 재생 평균 1528ms;")
	print("         발주자 판정 전 구현 금지, 다중 시나리오 진입 때 재검토\n")

func _test_ruleset_isolation(data: GameData) -> void:
	print("4. 규칙 세대 격리")
	var c := Campaign.scenario_03(data, 901)
	c.replay_to(180)
	var old := c.to_save_dict()
	var result := Campaign.from_save_result(old, data, "RS-0.2.0")
	_eq(result["status"], Save.STATUS_OLD_MINOR, "낮은 minor 는 세이브 규칙으로 로드")
	_eq(result["campaign"].world.ruleset, "RS-0.1.0", "현재 minor 로 덮지 않는다")
	_ok(bool(result["verified"]), "낮은 minor 재생 지문 일치")
	_eq(Campaign.from_save_result(old, data, "RS-0.1.9")["status"], Save.STATUS_OK, "patch 차이는 무시")
	var major := old.duplicate(true)
	major["world"]["ruleset"] = "RS-1.1.0"
	_eq(Save.inspect(major)["status"], Save.STATUS_MAJOR_MISMATCH, "major 불일치 거부")
	var future := old.duplicate(true)
	future["world"]["ruleset"] = "RS-0.2.0"
	_eq(Save.inspect(future)["status"], Save.STATUS_NEWER_MINOR, "더 새 minor 거부")
	print("")

func _test_determinism_guards(data: GameData) -> void:
	print("5. 플랫폼 독립 결정론 가드")
	var a := Campaign.scenario_03(data, 977)
	var b := Campaign.scenario_03(data, 977)
	a.replay_to(720)
	b.replay_to(720)
	_eq(a.digest(), b.digest(), "동일 시드 · 동일 순서 재생 지문")
	_ok(Save._parse_ruleset("RS-0.1.0") == [0, 1, 0], "정수 규칙 버전 파싱")
	_skip += 1
	print("  SKIP — Android 실기 지문 대조는 C-05·C-06 스모크 훅\n")

func _test_monthly_round_trip(data: GameData) -> void:
	print("6. 월 정산 자동 저장 지점 왕복")
	var c := Campaign.scenario_03(data, 1001)
	c.replay_to(GameClock.TICKS_PER_MONTH)
	_eq(c.world.clock.tick % GameClock.TICKS_PER_MONTH, 0, "월 경계 틱")
	var path := "user://a02_month.json"
	_ok(c.write_save(path), "월 경계 저장")
	var result := Campaign.read_save_result(path, GameData.load_all())
	_eq(result["status"], Save.STATUS_OK, "월 경계 파일 복원 검증")
	_eq(result["actual_digest"], c.digest(), "월 경계 왕복 지문")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("")

func _test_corruption(data: GameData) -> void:
	print("7. 손상 저장 복구")
	var path := "user://a02_broken.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	var parsed := Campaign.read_save_result(path, data)
	_eq(parsed["status"], Save.STATUS_CORRUPT, "JSON 파싱 실패 거부")
	_ok(String(parsed["detail"]).contains("JSON"), "파싱 실패 상세")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var c := _campaign_with_player_move(data, 1101)
	var missing := c.to_save_dict()
	missing["world"].erase("seed")
	var missing_result := Save.inspect(missing)
	_eq(missing_result["status"], Save.STATUS_CORRUPT, "필수 키 결손 거부")
	_ok(String(missing_result["detail"]).contains("world.seed"), "문제 키 표시")
	var schema_bad := c.to_save_dict()
	schema_bad["campaign"]["snapshot"] = []
	var schema_result := Save.inspect(schema_bad)
	_eq(schema_result["status"], Save.STATUS_CORRUPT, "스키마 추가 키 거부")
	_ok(String(schema_result["detail"]).contains("campaign.snapshot"), "스키마 위반 키 표시")
	var bad_rules := c.to_save_dict()
	bad_rules["world"]["ruleset"] = "latest"
	_eq(Save.inspect(bad_rules)["status"], Save.STATUS_CORRUPT, "ruleset 파싱 실패 거부")
	var damaged := c.to_save_dict()
	damaged["world"]["commands"][0].erase("kind")
	var recovered := Campaign.from_save_result(damaged, data)
	_eq(recovered["status"], Save.STATUS_PARTIAL_RECOVERY, "손상 명령 직전 복구")
	_eq(recovered["restored_tick"], 0, "첫 손상 명령 발행 직전 틱")
	_ok(String(recovered["detail"]).contains("0개월 시점으로 복원됨"), "복원 시점 고지")
	_eq(recovered["campaign"].world.applied_commands.size(), 0, "손상 이후 로그 전부 폐기")
	print("")

func _test_fleet_is_derived(data: GameData) -> void:
	print("8. 함대 상태는 명령 로그에서 파생")
	var c := _campaign_with_player_move(data, 1201, 30)
	var r: Campaign = Campaign.from_save_result(c.to_save_dict(), data)["campaign"]
	_eq(r.digest(), c.digest(), "플레이어 함대 이동 포함 전체 지문")
	for i in c.fleets.size():
		var a: Fleet = c.fleets[i]
		var b: Fleet = r.fleets[i]
		_eq([b.at_system, b.ships, b.morale, b.target_region, b.arrival_tick],
			[a.at_system, a.ships, a.morale, a.target_region, a.arrival_tick],
			"함대 %d 위치·척수·사기·이동 목표" % a.id)
	print("")
