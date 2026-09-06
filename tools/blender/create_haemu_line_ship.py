"""Create the Hae-mu line cruiser source scene and a first review GLB in Blender.

Run with Blender in background mode.  This intentionally produces a separate
asset; it never overwrites the existing prototype fleet models.
"""
import bpy
import math
from pathlib import Path
from mathutils import Vector

OUT = Path(__file__).resolve().parents[2] / "assets" / "models" / "ships"
OUT.mkdir(parents=True, exist_ok=True)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, metallic, roughness, emission=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    # Procedural micro-pitting is rendered in Blender now and baked to PBR maps
    # in the following asset pass; it prevents the hero material reading as flat paint.
    noise = m.node_tree.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 42.0
    noise.inputs["Detail"].default_value = 3.0
    noise.inputs["Roughness"].default_value = .7
    bump = m.node_tree.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .16
    bump.inputs["Distance"].default_value = .055
    m.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    m.node_tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = 5.0
    return m


def box(name, loc, dimensions, mat, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Panel edge radius", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(mat)
    return obj


def cylinder(name, loc, radius, depth, mat, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=radius, depth=depth,
        location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new("Machined edge", "BEVEL")
    bevel.width = min(radius * .18, .12)
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def wedge(name, front_y, back_y, front_width, back_width, front_height, back_height, mat, z=0.0):
    """A faceted hull section: a ship-like taper rather than a scaled cube."""
    verts = [
        (-front_width / 2, front_y, z - front_height / 2),
        ( front_width / 2, front_y, z - front_height / 2),
        ( back_width / 2,  back_y, z - back_height / 2),
        (-back_width / 2,  back_y, z - back_height / 2),
        (-front_width / 2, front_y, z + front_height / 2),
        ( front_width / 2, front_y, z + front_height / 2),
        ( back_width / 2,  back_y, z + back_height / 2),
        (-back_width / 2,  back_y, z + back_height / 2),
    ]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bevel = obj.modifiers.new("Hull edge radius", "BEVEL")
    bevel.width = .13
    bevel.segments = 3
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def add_panel_bank(parent, x, y, z, count, mat):
    for i in range(count):
        panel = box("ArmorPanel", (x, y + i * 1.12, z), (1.45, .84, .10), mat, .035)
        panel.parent = parent


def render_preview():
    bpy.ops.object.camera_add(location=(19, -24, 13))
    camera = bpy.context.object
    camera.data.lens = 52
    camera.rotation_euler = (Vector((0, 0, .3)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    for location, energy, size, color in [
        ((-11, -12, 16), 1600, 8, (0.45, 0.72, 1.0)),
        ((12, 5, 10), 1100, 6, (1.0, 0.46, 0.18)),
        ((0, 16, -2), 900, 5, (0.2, 0.55, 1.0)),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        lamp = bpy.context.object
        lamp.data.energy = energy
        lamp.data.shape = "DISK"
        lamp.data.size = size
        lamp.data.color = color
        lamp.rotation_euler = (Vector((0, 0, 0)) - lamp.location).to_track_quat("-Z", "Y").to_euler()
    world = bpy.context.scene.world or bpy.data.worlds.new("Preview World")
    bpy.context.scene.world = world
    world.color = (0.002, 0.004, 0.008)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(OUT.parents[2] / "out" / "fleet-reference-scene" / "haemu-line-ship-v1.png")
    Path(scene.render.filepath).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)


def build():
    clear()
    hull = material("Ceramic blue-gray hull", (0.14, 0.19, 0.23), .88, .48)
    armor = material("Armor panel", (0.20, 0.27, 0.31), .82, .38)
    dark = material("Radiator graphite", (0.025, 0.04, 0.055), .65, .72)
    titanium = material("Titanium edge", (0.36, 0.39, 0.40), .93, .28)
    amber = material("Navigation amber", (0.36, 0.10, 0.015), .15, .30, (1.0, .20, .02))
    engine = material("Ion engine core", (0.1, 0.32, 0.45), .20, .20, (0.25, .75, 1.0))
    root = bpy.data.objects.new("Hae-mu Line Cruiser", None)
    bpy.context.collection.objects.link(root)

    # Blender forward is -Y, matching Godot's imported -Z convention.
    main = wedge("Armored taper keel", -6.7, 7.85, 4.35, 5.75, 1.55, 2.35, hull, -.06)
    main.parent = root
    bow = wedge("Triple sensor blade prow", -11.1, -5.9, 1.05, 4.5, .38, 1.65, armor, .18)
    bow.parent = root
    bridge = wedge("Low command spine", -4.8, 3.05, 1.42, 2.18, .72, 1.12, armor, 1.46)
    bridge.parent = root
    belly = box("Structural belly keel", (0, 1.9, -1.42), (3.35, 15.4, .68), dark, .12)
    belly.parent = root

    # Layered armor makes the silhouette read at medium range.
    for side in (-1, 1):
        for i in range(7):
            y = -5.7 + i * 1.78
            slab = box("Stepped side armor", (side * 3.04, y, .25 + (i % 2) * .13),
                (1.06, 1.48, 1.22), armor, .10)
            slab.parent = root
        rail = box("Weapon spine", (side * 2.85, -.15, 1.15), (.54, 10.6, .34), titanium, .06)
        rail.parent = root
        add_panel_bank(root, side * 2.73, -5.35, -.68, 8, dark)

    # Offset drone-recovery bay: asymmetric recognizer, not a franchise bridge.
    bay = box("Starboard drone recovery recess", (3.34, .45, .42), (1.42, 6.0, 1.35), dark, .12)
    bay.parent = root
    for y in (-1.5, .0, 1.5):
        lamp = box("Bay work light", (4.05, y, .62), (.08, .25, .08), amber, .02)
        lamp.parent = root

    # Two heavy turrets and six point-defense mounts, each with a visible barbette.
    for y in (-3.8, 2.1):
        base = cylinder("Heavy turret barbette", (0, y, 1.58), .72, .32, titanium)
        base.parent = root
        turret = box("Twin heavy turret", (0, y - .18, 1.98), (1.15, .92, .45), armor, .08)
        turret.parent = root
        for x in (-.28, .28):
            barrel = cylinder("Main cannon", (x, y - .92, 2.02), .10, 1.45, dark,
                rotation=(math.radians(90), 0, 0))
            barrel.parent = root
    for side in (-1, 1):
        for y in (-4.4, -.4, 3.3):
            pod = cylinder("Point defense", (side * 3.55, y, .45), .24, .52, titanium,
                rotation=(0, math.radians(90), 0))
            pod.parent = root

    # Four separated engine booms with gaps that make the rear readable.
    for x in (-2.3, -.78, .78, 2.3):
        boom = box("Separated engine boom", (x, 8.7, .18), (.82, 4.55, .82), armor, .13)
        boom.parent = root
        shield = box("Engine heat shield", (x, 10.2, .25), (1.18, .44, 1.18), dark, .08)
        shield.parent = root
        nozzle = cylinder("Four-boom ion nozzle", (x, 11.05, .22), .43, .55, titanium,
            rotation=(math.radians(90), 0, 0))
        nozzle.parent = root
        core = cylinder("Ion core", (x, 11.35, .22), .25, .08, engine,
            rotation=(math.radians(90), 0, 0))
        core.parent = root

    # Sparse functional details, kept away from flat every-surface noise.
    for side in (-1, 1):
        antenna = box("Comms mast", (side * 1.28, -1.4, 2.62), (.10, .10, 1.75), titanium, .02)
        antenna.parent = root
    for x in (-1.75, 1.75):
        nav = box("Bow navigation light", (x, -8.1, .72), (.13, .12, .10), amber, .02)
        nav.parent = root

    # Hero-distance surface language: broad removable armor tiles, recessed service
    # trenches and sparse equipment blocks.  The pattern is functional and modular,
    # not uniform noise stamped over every surface.
    for lane in (-1.5, 0.0, 1.5):
        for index in range(7):
            y = -4.65 + index * 1.38
            width = 1.05 if lane == 0.0 else .86
            plate = box("Deck armor tile", (lane, y, 1.16 + (index % 2) * .035),
                (width, 1.05, .105), armor if index % 3 else hull, .035)
            plate.parent = root
            if index % 2 == 0 and lane != 0.0:
                service = box("Recessed service trench", (lane, y - .27, 1.245),
                    (.20, .40, .045), dark, .015)
                service.parent = root
    for side in (-1, 1):
        for y in (-3.1, -.9, 1.4, 4.0):
            cooler = box("Armored heat exchanger", (side * 2.34, y, 1.08),
                (.48, .78, .28), dark, .045)
            cooler.parent = root
            seam = box("Cooler edge strip", (side * 2.60, y, 1.23),
                (.035, .62, .055), titanium, .012)
            seam.parent = root

    render_preview()
    # Save Blender source then export GLB with material data.
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "haemu_line_ship_v1.blend"))
    bpy.ops.export_scene.gltf(filepath=str(OUT / "haemu_line_ship_lod0.glb"),
        export_format="GLB", use_selection=True, export_materials="EXPORT",
        export_cameras=False, export_lights=False)


if __name__ == "__main__":
    build()
