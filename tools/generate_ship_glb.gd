extends SceneTree

## 3D 항행 화면용 경량 함선 GLB 생성기.
## Godot primitive mesh만 사용하므로 외부 DCC가 없어도 같은 결과를 재생성할 수 있다.

const OUTPUT_DIR := "res://assets/models/ships"

const SHIPS := {
	"line_ship": {"length": 6.8, "width": 2.7, "height": 1.05, "engines": 3, "turrets": 2, "wings": true},
	"artillery_ship": {"length": 8.0, "width": 2.2, "height": 1.0, "engines": 2, "turrets": 1, "barrel": true},
	"assault_carrier": {"length": 9.8, "width": 4.2, "height": 1.45, "engines": 4, "turrets": 3, "carrier": true},
	"electronic_ship": {"length": 6.0, "width": 2.5, "height": .9, "engines": 3, "turrets": 0, "dish": true},
	"siege_ship": {"length": 7.4, "width": 2.9, "height": 1.2, "engines": 3, "turrets": 2, "spine": true},
	"supply_ship": {"length": 7.1, "width": 3.4, "height": 1.25, "engines": 4, "turrets": 0, "cargo": true},
	"interceptor_fighter": {"length": 3.3, "width": 2.8, "height": .55, "engines": 2, "turrets": 0, "fighter": true},
}


func _init() -> void:
	call_deferred("_generate")


func _generate() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var failed := 0
	for id in SHIPS:
		var ship := _make_ship(String(id), SHIPS[id])
		var destination := OUTPUT_DIR.path_join("%s.glb" % id)
		var result := _write_glb(ship, destination)
		if result != OK:
			failed += 1
			push_error("GLB export failed: %s (%s)" % [destination, error_string(result)])
		ship.free()
	print("GENERATED_SHIP_GLB count=%d failed=%d" % [SHIPS.size(), failed])
	quit(1 if failed > 0 else 0)


func _write_glb(ship: Node3D, destination: String) -> Error:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(ship, state)
	if append_error != OK:
		return append_error
	return document.write_to_filesystem(state, destination)


func _make_ship(id: String, spec: Dictionary) -> Node3D:
	var ship := Node3D.new()
	ship.name = id
	var length := float(spec["length"])
	var width := float(spec["width"])
	var height := float(spec["height"])
	var hull := _metal_material(Color("293744"), Color("68dff4"))
	var armor := _metal_material(Color("15212c"), Color("3ea0d0"))
	var glow := _engine_material()

	# 전방은 -Z. 세 개의 층으로 나누면 작은 거리에서도 군함 실루엣이 읽힌다.
	_add_box(ship, "MainHull", Vector3(width, height, length * .68), Vector3(0, 0, .28), hull)
	_add_box(ship, "ForeHull", Vector3(width * .74, height * .82, length * .34), Vector3(0, .02, -length * .29), armor)
	_add_box(ship, "Bridge", Vector3(width * .38, height * .56, length * .20), Vector3(0, height * .58, -length * .02), armor)
	_add_box(ship, "Keel", Vector3(width * .42, height * .28, length * .82), Vector3(0, -height * .50, .18), armor)

	if bool(spec.get("wings", false)) or bool(spec.get("fighter", false)):
		_add_box(ship, "PortWing", Vector3(width * .82, height * .16, length * .34), Vector3(-width * .66, 0, .18), armor)
		_add_box(ship, "StarboardWing", Vector3(width * .82, height * .16, length * .34), Vector3(width * .66, 0, .18), armor)
	if bool(spec.get("carrier", false)):
		_add_box(ship, "FlightDeck", Vector3(width * .72, height * .14, length * .62), Vector3(0, height * .62, .22), armor)
		_add_box(ship, "PortBay", Vector3(width * .22, height * .30, length * .32), Vector3(-width * .38, height * .30, .18), glow)
		_add_box(ship, "StarboardBay", Vector3(width * .22, height * .30, length * .32), Vector3(width * .38, height * .30, .18), glow)
	if bool(spec.get("barrel", false)):
		_add_cylinder(ship, "Railgun", width * .13, length * .76, Vector3(0, height * .43, -length * .22), Vector3(90, 0, 0), armor)
	if bool(spec.get("spine", false)):
		_add_cylinder(ship, "SiegeSpine", width * .18, length * .74, Vector3(0, height * .38, .10), Vector3(90, 0, 0), hull)
	if bool(spec.get("dish", false)):
		_add_cylinder(ship, "SensorDish", width * .26, height * .14, Vector3(0, height * .88, .12), Vector3(0, 0, 0), glow)
	if bool(spec.get("cargo", false)):
		for side in [-1.0, 1.0]:
			_add_box(ship, "CargoPod", Vector3(width * .28, height * .72, length * .34), Vector3(side * width * .52, 0, .10), armor)

	for index in range(int(spec["turrets"])):
		var offset := -length * .18 + index * length * .24
		_add_cylinder(ship, "Turret%d" % index, width * .14, height * .18,
			Vector3(0, height * .76, offset), Vector3.ZERO, armor)
		_add_cylinder(ship, "TurretBarrel%d" % index, width * .052, length * .22,
			Vector3(0, height * .86, offset - length * .10), Vector3(90, 0, 0), hull)

	var engine_count := int(spec["engines"])
	for index in range(engine_count):
		var offset := float(index) - (float(engine_count - 1) * .5)
		var engine_at := Vector3(offset * width * .34, -height * .08, length * .47)
		_add_cylinder(ship, "Engine%d" % index, minf(width * .12, .34), length * .16,
			engine_at, Vector3(90, 0, 0), hull)
		_add_cylinder(ship, "EngineGlow%d" % index, minf(width * .08, .22), length * .03,
			engine_at + Vector3(0, 0, length * .10), Vector3(90, 0, 0), glow)
	return ship


func _add_box(parent: Node3D, name: String, dimensions: Vector3, at: Vector3,
		material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.position = at
	parent.add_child(instance)


func _add_cylinder(parent: Node3D, name: String, radius: float, length: float,
		at: Vector3, rotation: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.position = at
	instance.rotation_degrees = rotation
	parent.add_child(instance)


func _metal_material(color: Color, emission_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = .78
	material.roughness = .34
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = .10
	return material


func _engine_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("6fe8ff")
	material.emission_enabled = true
	material.emission = Color("2ed9ff")
	material.emission_energy_multiplier = 4.0
	material.metallic = .12
	material.roughness = .18
	return material
