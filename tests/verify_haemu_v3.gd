extends SceneTree

const FILES := [
	"res://assets/models/ships/haemu_line_ship_lod0_v3_final.glb",
	"res://assets/models/ships/haemu_line_ship_lod1_v3_final.glb",
	"res://assets/models/ships/haemu_line_ship_lod2_v3_final.glb",
	"res://assets/models/ships/haemu_line_ship_lod3_v3_final.glb",
]


func _initialize() -> void:
	var failed := 0
	for path in FILES:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var result := document.append_from_file(path, state)
		if result != OK:
			failed += 1
			push_error("해무급 V3 GLB 파싱 실패: %s (%s)" % [path, error_string(result)])
			continue
		var scene := document.generate_scene(state)
		if scene == null:
			failed += 1
			push_error("해무급 V3 씬 생성 실패: %s" % path)
			continue
		print("HAEMU_V3_OK path=%s children=%d" % [path, scene.get_child_count()])
		scene.free()
	quit(1 if failed > 0 else 0)
