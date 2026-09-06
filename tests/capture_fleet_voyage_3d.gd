extends SceneTree

## 3D 항행 관측의 시각 회귀 캡처. 수동 검토용 산출물만 만들며 게임 정본은 바꾸지 않는다.

func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var fleet = null
	for candidate in main.campaign.fleets:
		if candidate != null and candidate.is_alive() and String(candidate.owner) == "손권":
			fleet = candidate
			break
	if fleet == null:
		push_error("캡처할 손권 함대를 찾지 못했습니다")
		quit(1)
		return
	main._on_tactical_route_detail_requested(fleet.id)
	for _frame in range(16):
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var output := "res://out/fleet-reference-scene/fleet-voyage-3d-fleet-v2.png"
	var result := image.save_png(output)
	if result != OK:
		push_error("3D 항행 캡처 저장 실패: %d" % result)
		quit(1)
		return
	print("FLEET_VOYAGE_CAPTURE=", output)
	quit(0)
