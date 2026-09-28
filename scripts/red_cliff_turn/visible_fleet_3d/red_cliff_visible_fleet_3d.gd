class_name RedCliffVisibleFleet3D
extends SubViewportContainer

## S5-02 read-only 3D evidence renderer. It accepts only a viewer projection.
## It never owns a battle controller and never mutates authoritative state.

const MANIFEST_PATH := "res://assets/red_cliffs/visible_fleet_3d/v1/visible_fleet_3d_manifest.json"
const ASSET_ROOT := "res://assets/red_cliffs/visible_fleet_3d/v1/"
const MAX_VISIBLE_SHIPS := 204
const FACTION_COLORS := {"liu_bei": Color("55d49a"), "sun_quan": Color("ed8e80")}

var _projection: Dictionary = {}
var _selected_squadron_id := ""
var _manifest: Dictionary = {}
var _model_scenes: Dictionary = {}
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _visual_root: Node3D
var _entity_roots: Dictionary = {}
var _visual_summary: Dictionary = {}
var _compatibility_mode := false


func _ready() -> void:
	custom_minimum_size = Vector2(280, 390)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_viewport()
	_load_manifest_and_models()
	_rebuild()


func configure(viewer_projection: Dictionary, selected_squadron_id: String = "") -> Dictionary:
	if not viewer_projection is Dictionary:
		return {"ok": false, "errors": ["viewer projection은 Dictionary여야 합니다."]}
	_projection = viewer_projection.duplicate(true)
	_selected_squadron_id = selected_squadron_id
	if is_node_ready(): _rebuild()
	return {"ok": true, "errors": []}


func projection_for_test() -> Dictionary:
	return _projection.duplicate(true)


func visual_summary_for_test() -> Dictionary:
	return _visual_summary.duplicate(true)


func request_render_once() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func model_paths_for_test() -> Array:
	var result: Array = []
	for key in _model_scenes.keys(): result.append(String(key))
	result.sort()
	return result


func orientation_for_test(facing_deg: float) -> Dictionary:
	var yaw := -(facing_deg + 90.0)
	var forward := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw))
	var aft := Vector3.BACK.rotated(Vector3.UP, deg_to_rad(yaw))
	return {"yaw_degrees": yaw, "forward": forward, "aft": aft}


func imported_material_override_count_for_test() -> int:
	var count := 0
	for key in _model_scenes:
		var instance := (_model_scenes[key] as PackedScene).instantiate()
		if instance != null:
			count += _material_override_count(instance)
			instance.free()
	return count


func _build_viewport() -> void:
	_compatibility_mode = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_viewport = SubViewport.new()
	_viewport.name = "VisibleFleet3DViewport"
	# Compatibility is the low-spec fallback. Keep the same 204 public ships and
	# evidence, but reduce only raster cost; the container still scales to its pane.
	_viewport.size = Vector2i(560, 436) if _compatibility_mode else Vector2i(720, 560)
	# Evidence is rebuilt only when the public turn projection changes. Rendering
	# the unchanged scene every UI frame wastes the Compatibility/GLES budget.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if _compatibility_mode else Viewport.MSAA_2X
	_viewport.transparent_bg = false
	add_child(_viewport)
	_world = Node3D.new(); _world.name = "VisibleFleet3DWorld"; _viewport.add_child(_world)
	var environment_node := WorldEnvironment.new(); var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("02060f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("42658b"); environment.ambient_light_energy = 0.34
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC; environment_node.environment = environment; _world.add_child(environment_node)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-56, -24, 0); key.light_color = Color("bddcff"); key.light_energy = 1.1; key.shadow_enabled = not _compatibility_mode; _world.add_child(key)
	var rim := DirectionalLight3D.new(); rim.rotation_degrees = Vector3(42, 150, 0); rim.light_color = Color("4ba8ff"); rim.light_energy = 0.52; _world.add_child(rim)
	_camera = Camera3D.new(); _camera.name = "VisibleFleet3DCamera"; _camera.fov = 47.0; _world.add_child(_camera)
	_camera.look_at_from_position(Vector3(0, 48, 27), Vector3.ZERO, Vector3.UP); _camera.current = true
	_build_backdrop()
	_visual_root = Node3D.new(); _visual_root.name = "ProjectionVisuals"; _world.add_child(_visual_root)


func _build_backdrop() -> void:
	var backdrop := MeshInstance3D.new(); backdrop.name = "RedCliffsStarfield"
	var plane := PlaneMesh.new(); plane.size = Vector2(92, 62)
	var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = load(ASSET_ROOT + "backgrounds/red_cliffs_starfield_v1.png") as Texture2D
	material.albedo_color = Color(0.68, 0.76, 0.82, 1.0); plane.material = material; backdrop.mesh = plane; backdrop.position.y = -3.5; _world.add_child(backdrop)


func _load_manifest_and_models() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null: return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return
	_manifest = parsed
	for ship_type_id in _manifest.get("ship_type_mapping", {}):
		var row: Dictionary = _manifest.ship_type_mapping[ship_type_id]
		if String(row.get("kind", "")) != "model": continue
		var asset_path := ASSET_ROOT + String(row.get("asset", ""))
		var scene := load(asset_path) as PackedScene
		if scene != null: _model_scenes[String(ship_type_id)] = scene


func _rebuild() -> void:
	if _visual_root == null: return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for child in _visual_root.get_children(): child.free()
	_entity_roots.clear()
	_visual_summary = {"requested_own_ship_count": 0, "own_ship_count": 0, "small_craft_count": 0, "confirmed_proxy_count": 0,
		"estimated_proxy_count": 0, "terrain_count": 0, "trail_count": 0, "beam_count": 0,
		"impact_count": 0, "repair_count": 0, "ew_count": 0, "chain_count": 0,
		"sampling_cap": MAX_VISIBLE_SHIPS, "sampled": false}
	if not bool(_projection.get("ok", false)): return
	_add_grid()
	_add_terrain(_projection.get("terrain_zones", []))
	var remaining := MAX_VISIBLE_SHIPS
	for value in _projection.get("own_squadrons", []):
		if not value is Dictionary or remaining <= 0: break
		for component in value.get("composition_current", []):
			if component is Dictionary: _visual_summary.requested_own_ship_count += maxi(0, int(component.get("count", 0)))
		remaining -= _add_own_squadron(value, remaining)
	for value in _projection.get("contacts", []):
		if value is Dictionary: _add_contact_proxy(value)
	_add_event_visuals(_projection.get("events", []))
	_visual_summary.sampled = int(_visual_summary.requested_own_ship_count) > int(_visual_summary.own_ship_count)


func _add_grid() -> void:
	var material := _material(Color(0.10, 0.42, 0.54, 0.27), true)
	for coordinate in range(-30, 31, 5):
		_add_box(_visual_root, Vector3(float(coordinate), -2.8, 0), Vector3(0.025, 0.014, 38), material)
	for coordinate in range(-18, 19, 4):
		_add_box(_visual_root, Vector3(0, -2.8, float(coordinate)), Vector3(62, 0.014, 0.025), material)


func _add_terrain(values: Array) -> void:
	for value in values:
		if not value is Dictionary: continue
		var shape: Dictionary = value.get("shape", {})
		if String(shape.get("kind", "")) != "rect": continue
		var start := _battle_to_world([shape.get("x", 0), shape.get("y", 0)])
		var finish := _battle_to_world([float(shape.get("x", 0)) + float(shape.get("width", 0)), float(shape.get("y", 0)) + float(shape.get("height", 0))])
		var mesh := MeshInstance3D.new(); mesh.name = "Terrain_%s" % String(value.get("zone_id", "unknown"))
		var plane := PlaneMesh.new(); plane.size = Vector2(absf(finish.x - start.x), absf(finish.z - start.z))
		var terrain_type := String(value.get("terrain_type", "")); var color: Color = {"nebula":Color(0.48,0.30,0.63,0.24),"debris":Color(0.68,0.48,0.22,0.25),"planet_shadow":Color(0.20,0.34,0.50,0.26),"temporary_chain_hazard":Color(0.92,0.30,0.12,0.30)}.get(terrain_type, Color(0.7,0.45,0.2,0.22))
		plane.material = _material(color, true); mesh.mesh = plane; mesh.position = (start + finish) * 0.5 + Vector3(0, -2.62, 0); _visual_root.add_child(mesh)
		_visual_summary.terrain_count += 1


func _add_own_squadron(row: Dictionary, available: int) -> int:
	var position = row.get("position", [])
	if not _valid_point(position): return 0
	var root := Node3D.new(); var squadron_id := String(row.get("squadron_id", "")); root.name = "Own_%s" % squadron_id
	root.position = _battle_to_world(position); root.rotation_degrees.y = -(float(row.get("facing_deg", 0.0)) + 90.0); _visual_root.add_child(root); _entity_roots[squadron_id] = root
	var components: Array = row.get("composition_current", []); var total := 0
	for component in components: total += maxi(0, int(component.get("count", 0))) if component is Dictionary else 0
	var rendered := 0; var slot := 0
	for component in components:
		if not component is Dictionary: continue
		var ship_type_id := String(component.get("ship_type_id", "")); var count := mini(int(component.get("count", 0)), available - rendered)
		for local_index in count:
			var wrapper := _ship_visual(ship_type_id)
			if wrapper == null: continue
			wrapper.name = "Ship_%s_%03d_%s" % [squadron_id, slot, ship_type_id]
			wrapper.position = _formation_offset(slot, maxi(1, mini(total, available)), String(row.get("formation_id", "")))
			root.add_child(wrapper); _add_engine_and_trail(wrapper, ship_type_id, String(row.get("faction_id", "")))
			rendered += 1; slot += 1
	if squadron_id == _selected_squadron_id: _add_selection(root)
	_add_label(root, String(row.get("name", squadron_id)), FACTION_COLORS.get(String(row.get("faction_id", "")), Color("8fd9ff")))
	_visual_summary.own_ship_count += rendered
	return rendered


func _ship_visual(ship_type_id: String) -> Node3D:
	var wrapper := Node3D.new()
	var mapping: Dictionary = _manifest.get("ship_type_mapping", {}).get(ship_type_id, {})
	if ship_type_id == "SHP-08" or String(mapping.get("kind", "")) == "procedural_small_craft_glyph":
		var glyph := MeshInstance3D.new(); var hull := BoxMesh.new(); hull.size = Vector3(0.18, 0.08, 0.55); hull.material = _material(Color("a9dff4"), false); glyph.mesh = hull; wrapper.add_child(glyph)
		var wing := MeshInstance3D.new(); var wings := BoxMesh.new(); wings.size = Vector3(0.52, 0.035, 0.16); wings.material = _material(Color("72bcd8"), false); wing.mesh = wings; wrapper.add_child(wing)
		wrapper.scale = Vector3.ONE * float(mapping.get("display_scale", 0.36)); _visual_summary.small_craft_count += 1
		return wrapper
	if not _model_scenes.has(ship_type_id): return null
	var model := (_model_scenes[ship_type_id] as PackedScene).instantiate() as Node3D
	if model == null: return null
	model.rotation_degrees.y = float(_manifest.get("orientation", {}).get("model_yaw_degrees", -90.0))
	model.scale = Vector3.ONE * float(mapping.get("display_scale", 1.0)); wrapper.scale = Vector3.ONE * float(_manifest.get("fleet_visual_scale", 1.0 / 3.0)); wrapper.add_child(model)
	return wrapper


func _formation_offset(index: int, count: int, formation_id: String) -> Vector3:
	if index == 0: return Vector3.ZERO
	var slot := index - 1
	match formation_id:
		"FRM-02", "FRM-06":
			var rank := int(slot / 4.0) + 1; var lane := slot % 4; return Vector3((float(lane) - 1.5) * 0.62 + signf(float(lane) - 1.5) * rank * 0.18, -0.025 * rank, rank * 0.72)
		"FRM-03", "FRM-04":
			var column := slot % 3; var row := int(slot / 3.0) + 1; return Vector3((column - 1) * 0.68, -0.025 * row, row * 0.66)
		"FRM-05", "FRM-07":
			var column := slot % 5; var row := int(slot / 5.0) + 1; return Vector3((column - 2) * 0.62, -0.025 * row, row * 0.66)
		_:
			var columns := mini(8, maxi(3, int(ceil(sqrt(float(count)))))); var column := slot % columns; var row := int(slot / float(columns)) + 1; return Vector3((float(column) - float(columns - 1) * 0.5) * 0.62, -0.025 * row, row * 0.68)


func _add_engine_and_trail(parent: Node3D, ship_type_id: String, faction_id: String) -> void:
	var color: Color = FACTION_COLORS.get(faction_id, Color("73cfff")); var small := ship_type_id == "SHP-08"
	var engine := MeshInstance3D.new(); engine.name = "EngineGlow"; var sphere := SphereMesh.new(); sphere.radius = 0.10 if small else 0.16; sphere.height = sphere.radius * 2.0
	var engine_material := _material(color, false); engine_material.emission_enabled = true; engine_material.emission = color; engine_material.emission_energy_multiplier = 4.0; sphere.material = engine_material; engine.mesh = sphere; engine.position = Vector3(0, 0, 1.05 if small else 2.2); parent.add_child(engine)
	var trail := MeshInstance3D.new(); trail.name = "AftTrail"; var trail_mesh := BoxMesh.new(); var length := 0.8 if small else 1.7; trail_mesh.size = Vector3(0.055, 0.035, length)
	var trail_material := _material(Color(color, 0.46), true); trail_material.emission_enabled = true; trail_material.emission = color; trail_material.emission_energy_multiplier = 2.6; trail_mesh.material = trail_material; trail.mesh = trail_mesh; trail.position = Vector3(0, 0, (1.05 if small else 2.2) + length * 0.5); parent.add_child(trail)


func _add_selection(parent: Node3D) -> void:
	var ring := MeshInstance3D.new(); ring.name = "SelectedSquadronRing"; var torus := TorusMesh.new(); torus.inner_radius = 2.4; torus.outer_radius = 2.52; torus.rings = 32; torus.ring_segments = 8; torus.material = _material(Color(0.94,0.77,0.25,0.92), true); ring.mesh = torus; ring.rotation_degrees.x = 90; ring.position.y = -0.7; parent.add_child(ring)


func _add_contact_proxy(row: Dictionary) -> void:
	var position = row.get("display_position", [])
	if not _valid_point(position): return
	var state := String(row.get("state", "estimated")); var root := Node3D.new(); var contact_id := String(row.get("contact_id", "")); root.name = "Contact_%s" % contact_id; root.position = _battle_to_world(position); _visual_root.add_child(root); _entity_roots[contact_id] = root
	var proxy := MeshInstance3D.new(); proxy.name = "ObservedContactProxy"; var mesh := SphereMesh.new(); mesh.radius = 0.82 if state == "confirmed" else 1.18; mesh.height = mesh.radius * 2.0; mesh.radial_segments = 12; mesh.rings = 6
	var color := Color(0.94,0.35,0.28,0.82) if state == "confirmed" else Color(0.92,0.70,0.28,0.42); mesh.material = _material(color, true); proxy.mesh = mesh; root.add_child(proxy)
	_add_label(root, ("확인 " if state == "confirmed" else "추정 ") + contact_id, color)
	if state == "confirmed": _visual_summary.confirmed_proxy_count += 1
	else: _visual_summary.estimated_proxy_count += 1


func _add_label(parent: Node3D, text: String, color: Color) -> void:
	var label := Label3D.new(); label.text = text; label.font_size = 22; label.modulate = color; label.outline_size = 5; label.position = Vector3(0, 2.6, 0); label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; parent.add_child(label)


func _add_event_visuals(values: Array) -> void:
	for value in values:
		if not value is Dictionary: continue
		var event: Dictionary = value; var kind := String(event.get("event_type", "")); var subject: Node3D = _event_subject(event)
		if kind in ["movement", "move", "movement_resolved"] and _valid_point(event.get("from", [])) and _valid_point(event.get("to", [])):
			_add_beam(_battle_to_world(event.get("from", [])), _battle_to_world(event.get("to", [])), Color(0.28,0.82,1.0,0.42), "MovementTrail"); _visual_summary.trail_count += 1
		elif "shot" in kind or "fire" in kind:
			var source: Node3D = _entity_roots.get(String(event.get("own_squadron_id", ""))); var target: Node3D = _entity_roots.get(String(event.get("contact_id", "")))
			if source is Node3D and target is Node3D: _add_beam(source.position + Vector3.UP, target.position + Vector3.UP, Color("73ddff"), "AuthorizedBeam"); _visual_summary.beam_count += 1
			elif subject is Node3D: _add_impact(subject.position, Color("ff7552")); _visual_summary.impact_count += 1
		elif "repair" in kind or "supply" in kind or "recovery" in kind:
			if subject is Node3D: _add_halo(subject, Color(0.35,0.95,0.62,0.7), "RepairEvidence"); _visual_summary.repair_count += 1
		elif "sensor" in kind or "detection" in kind or "electronic" in kind:
			if subject is Node3D: _add_halo(subject, Color(0.43,0.68,1.0,0.58), "EWEvidence"); _visual_summary.ew_count += 1
		elif "chain" in kind or "temporary_terrain" in kind:
			if subject is Node3D: _add_impact(subject.position, Color("ff9a42"))
			_visual_summary.chain_count += 1


func _event_subject(event: Dictionary) -> Node3D:
	for key in ["own_squadron_id", "squadron_id", "contact_id"]:
		var id := String(event.get(key, ""))
		if _entity_roots.has(id): return _entity_roots[id]
	return null


func _add_beam(start: Vector3, finish: Vector3, color: Color, node_name: String) -> void:
	var length := start.distance_to(finish)
	if length <= 0.001: return
	var beam := MeshInstance3D.new(); beam.name = node_name; var box := BoxMesh.new(); box.size = Vector3(0.07, 0.07, length); var material := _material(color, true); material.emission_enabled = true; material.emission = Color(color.r,color.g,color.b,1); material.emission_energy_multiplier = 4.0; box.material = material; beam.mesh = box; _visual_root.add_child(beam); beam.look_at_from_position((start + finish) * 0.5, finish, Vector3.UP)


func _add_impact(at: Vector3, color: Color) -> void:
	var impact := MeshInstance3D.new(); impact.name = "ViewerEventImpact"; var sphere := SphereMesh.new(); sphere.radius = 0.72; sphere.height = 1.44; var material := _material(color, true); material.emission_enabled = true; material.emission = color; material.emission_energy_multiplier = 3.4; sphere.material = material; impact.mesh = sphere; impact.position = at + Vector3.UP; _visual_root.add_child(impact)


func _add_halo(parent: Node3D, color: Color, node_name: String) -> void:
	var ring := MeshInstance3D.new(); ring.name = node_name; var torus := TorusMesh.new(); torus.inner_radius = 1.35; torus.outer_radius = 1.48; torus.rings = 24; torus.ring_segments = 8; torus.material = _material(color, true); ring.mesh = torus; ring.rotation_degrees.x = 90; ring.position.y = 0.55; parent.add_child(ring)


func _battle_to_world(point: Array) -> Vector3:
	var bounds: Array = _projection.get("battlefield_bounds", [0,0,1600,900])
	var width := maxf(1.0, float(bounds[2])); var height := maxf(1.0, float(bounds[3]))
	return Vector3(((float(point[0]) - float(bounds[0])) / width - 0.5) * 58.0, 0.0, ((float(point[1]) - float(bounds[1])) / height - 0.5) * 34.0)


func _valid_point(value) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float)


func _add_box(parent: Node3D, position: Vector3, box_size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = box_size; box.material = material; mesh.mesh = box; mesh.position = position; parent.add_child(mesh)


func _material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = color
	if transparent: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _material_override_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).material_override != null else 0
	for child in node.get_children(): count += _material_override_count(child)
	return count
