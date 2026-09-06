"""Build the V3 Hae-mu hero vessel: an original, game-ready hard-surface asset.

Run: blender --background --python tools/blender/build_haemu_line_battleship_v3.py
The V3 output is isolated from all prototype assets.
"""
from pathlib import Path
import math
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models" / "ships"
PREVIEW = ROOT / "out" / "fleet-reference-scene" / "haemu-line-battleship-v3-beauty.png"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import create_haemu_line_ship_v2 as kit


def build():
    kit.clear_scene()
    OUT.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    ceramic = kit.pbr_material("Ceramic blue-grey", (.075, .12, .15), .82, .31, scale=7)
    armour = kit.pbr_material("Layered blue-grey armour", (.16, .23, .28), .88, .25, scale=12)
    dark = kit.pbr_material("Graphite thermal tiles", (.008, .014, .021), .60, .66, scale=20)
    machined = kit.pbr_material("Machined titanium", (.35, .42, .46), .92, .18, scale=16)
    copper = kit.pbr_material("Heat scarred conduits", (.23, .05, .012), .80, .31, scale=18)
    cyan = kit.pbr_material("Pale cyan ion core", (.01, .13, .20), .20, .14, accent=(.12, .85, 1), scale=4)
    amber = kit.pbr_material("Amber navigation glass", (.28, .055, .005), .08, .18, accent=(1, .18, .02), scale=4)
    root = bpy.data.objects.new("Hae-mu line battleship V3", None)
    bpy.context.collection.objects.link(root)

    def add(obj):
        return kit.parent(obj, root)

    # The primary silhouette follows the approved V3 sheet: broad low wedge,
    # pinched central citadel and four detached stern booms.
    add(kit.wedge("main armoured wedge", -13.0, 7.7, 2.5, 8.8, .72, 2.45, armour, -.12))
    add(kit.wedge("deep structural keel", -11.5, 9.4, 1.8, 4.9, .55, 1.15, ceramic, -1.42))
    add(kit.wedge("split sensor blade", -15.0, -7.2, .34, 3.25, .16, .60, machined, .02))
    add(kit.wedge("dorsal stepped citadel", -6.0, 4.6, 1.7, 3.65, .42, .88, armour, 1.68))
    add(kit.wedge("dorsal thermal crown", -8.1, 2.2, .95, 2.3, .17, .33, dark, 2.32))

    # Tapered, overlapping bow armour plates make a deliberate maritime prow.
    for side in (-1, 1):
        for i in range(13):
            y = -11.7 + i * .78
            x = side * (1.55 + i * .17)
            add(kit.cube("bow armour lamella", (x, y, .55 + i * .026),
                         (1.12, .63, .34), armour if i % 3 else ceramic, .045))
            add(kit.cube("bow seam", (side * (abs(x) + .48), y, .72),
                         (.032, .43, .045), dark, .006))
    # Split shoulders: port is weapons-facing, starboard opens into a recovery bay.
    for side in (-1, 1):
        for i in range(14):
            y = -5.5 + i * .83
            if side > 0 and 6 <= i <= 10:
                continue
            x = side * (4.05 + .15 * abs(i - 7) / 7)
            add(kit.cube("removable flank armour", (x, y, .20), (1.06, .68, 1.12), armour, .055))
            add(kit.cube("flank shadow seam", (side * 4.54, y, .32), (.028, .48, .65), dark, .006))
    add(kit.cube("starboard maintenance bay void", (4.23, 1.45, .18), (1.48, 4.75, 1.58), dark, .11))
    for y in (-.35, .50, 1.35, 2.20, 3.05):
        add(kit.cube("bay structural arch", (4.88, y, .38), (.11, .10, 1.30), machined, .014))
        add(kit.cube("bay inspection lamp", (4.96, y, .93), (.045, .10, .052), amber, .005))
    # Sensor boom deliberately exists only on the service side.
    add(kit.cube("starboard sensor boom", (5.55, .15, .65), (2.15, .20, .16), machined, .028))
    add(kit.cyl("starboard sensor head", (6.55, .15, .65), .24, .35, cyan, rotation=(0, math.radians(90), 0), vertices=32))

    # Four heavy twin turrets = sixteen primary barrels, mounted low in the spine.
    for n, y in enumerate((-5.1, -2.05, 1.0, 4.05)):
        add(kit.cyl("turret armoured barbette", (0, y, 2.18), .92, .30, machined, vertices=40))
        add(kit.cube("twin turret housing", (0, y - .10, 2.50), (1.58, 1.02, .52), armour, .075))
        for x in (-.48, -.16, .16, .48):
            add(kit.cyl("primary cannon barrel", (x, y - 1.03, 2.56), .085, 1.70, dark,
                         rotation=(math.radians(90), 0, 0), vertices=24))
            add(kit.cyl("primary recoil jacket", (x, y - .54, 2.56), .125, .46, machined,
                         rotation=(math.radians(90), 0, 0), vertices=24))
    # Side weapon architecture: 24 secondary barrels, 12 PD mounts, 8 missile arrays.
    for side in (-1, 1):
        for i, y in enumerate((-5.3, -3.2, -1.1, 1.0, 3.1, 5.2)):
            add(kit.cube("secondary gun sponson", (side * 4.70, y, .82), (.64, .68, .46), ceramic, .04))
            for z in (.74, 1.03):
                add(kit.cyl("secondary cannon", (side * 5.06, y - .15, z), .065, .55, dark,
                             rotation=(0, math.radians(90), 0), vertices=20))
        for y in (-4.25, -1.45, 1.35, 4.15):
            add(kit.cube("missile cassette", (side * 3.45, y, 1.25), (.66, .86, .72), dark, .045))
            for row in (-.22, .22):
                add(kit.cyl("missile tube", (side * 3.77, y + row, 1.30), .075, .16, machined,
                             rotation=(0, math.radians(90), 0), vertices=16))
        for y in (-4.8, -2.9, -.8, 1.3, 3.4, 5.2):
            add(kit.cyl("point defence cupola", (side * 4.55, y, .92), .25, .34, machined,
                         rotation=(0, math.radians(90), 0), vertices=28))

    # Four distinct engine booms, each with fairing, heat shielding, plumbing and cyan core.
    for x in (-2.7, -.9, .9, 2.7):
        add(kit.cube("engine separation strut", (x, 9.25, .10), (1.05, 4.75, .86), armour, .10))
        add(kit.cube("engine nacelle fairing", (x, 10.80, .14), (1.32, 2.75, 1.44), ceramic, .11))
        add(kit.cube("engine dorsal radiator", (x, 10.42, 1.01), (1.15, 1.96, .17), dark, .025))
        add(kit.cube("engine copper manifold", (x + .44, 10.80, .56), (.07, 2.30, .09), copper, .012))
        add(kit.cyl("engine vector ring", (x, 12.24, .14), .55, .29, machined,
                     rotation=(math.radians(90), 0, 0), vertices=40))
        add(kit.cyl("engine ion core", (x, 12.46, .14), .36, .10, cyan,
                     rotation=(math.radians(90), 0, 0), vertices=40))
        for side in (-1, 1):
            add(kit.cube("engine control vane", (x + side * .61, 11.13, .57), (.055, 1.30, .62), dark, .012))

    # Hero-distance surface construction: functional panel seams, bolts, thermal fins and cable trays.
    for lane in (-2.10, -1.40, -.70, 0, .70, 1.40, 2.10):
        for i in range(24):
            y = -6.4 + i * .49
            add(kit.cube("deck panel seam", (lane, y, 1.31), (.36, .026, .022), dark, .003))
            if i % 2 == 0:
                for dx in (-.13, .13):
                    add(kit.cube("deck fastener", (lane + dx, y + .13, 1.33), (.038, .038, .024), machined, .003))
    for side in (-1, 1):
        for block in (4.8, 5.8, 6.8):
            add(kit.cube("thermal exchanger backing", (side * 2.96, block, -.52), (.36, .72, .74), dark, .02))
            for fin in range(13):
                add(kit.cube("thermal exchanger fin", (side * 3.18, block - .31 + fin * .052, -.49),
                             (.29, .020, .64), machined, .002))
        for i in range(18):
            y = -5.8 + i * .65
            add(kit.cube("flank cable tray", (side * 3.15, y, .92), (.052, .46, .075), dark, .008))
            if i % 2 == 1:
                add(kit.cube("service latch", (side * 3.29, y, .54), (.032, .09, .09), copper, .003))

    return root


def render_and_export(root):
    bpy.ops.object.camera_add(location=(22, -29, 16))
    camera = bpy.context.object
    camera.data.lens = 58
    camera.rotation_euler = (Vector((0, 0, .25)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    for loc, energy, size, color in [((-15,-17,20),3200,11,(.43,.72,1)),((15,-4,14),2500,9,(1,.30,.08)),((2,17,16),2600,10,(.35,.58,1))]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.data.energy, light.data.shape, light.data.size, light.data.color = energy, "DISK", size, color
        light.rotation_euler = (Vector((0,0,0)) - light.location).to_track_quat("-Z", "Y").to_euler()
    world = bpy.data.worlds.new("V3 deep space studio")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (.002, .005, .011, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .20
    bpy.context.scene.world = world
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW)
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 1.1
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "haemu_line_ship_v3.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH": obj.select_set(True)
    bpy.context.view_layer.objects.active = next(o for o in bpy.context.selected_objects if o.type == "MESH")
    bpy.ops.export_scene.gltf(filepath=str(OUT / "haemu_line_ship_lod0_v3.glb"), export_format="GLB", use_selection=True, export_materials="EXPORT", export_cameras=False, export_lights=False)


if __name__ == "__main__":
    render_and_export(build())
