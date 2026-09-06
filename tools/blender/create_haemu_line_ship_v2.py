"""Build the Hae-mu V2 hero cruiser, separately from the prototype assets.

The design is original: an armoured maritime-inspired deep-space cruiser with a
faceted prow, serviceable plate armour and four isolated drive nacelles.  It is
intended for the close observation hero ship; far fleet members remain LODs.
"""
import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models" / "ships"
PREVIEW = ROOT / "out" / "fleet-reference-scene" / "haemu-line-ship-v2.png"


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.materials, bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def pbr_material(name, base, metallic=.0, rough=.5, accent=None, scale=7.0):
    """Principled, layered procedural material that reads like a PBR surface."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    output = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    tex = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (scale, scale, scale)
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 5.5
    noise.inputs["Detail"].default_value = 4.0
    noise.inputs["Roughness"].default_value = .68
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = .28
    ramp.color_ramp.elements[0].color = (*[v * .52 for v in base], 1)
    ramp.color_ramp.elements[1].position = .74
    ramp.color_ramp.elements[1].color = (*[min(1, v * 1.16) for v in base], 1)
    bump_noise = nt.nodes.new("ShaderNodeTexNoise")
    bump_noise.inputs["Scale"].default_value = 48.0
    bump_noise.inputs["Detail"].default_value = 2.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .22
    bump.inputs["Distance"].default_value = .045
    nt.links.new(tex.outputs["Generated"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(mapping.outputs["Vector"], bump_noise.inputs["Vector"])
    nt.links.new(bump_noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    if accent:
        bsdf.inputs["Emission Color"].default_value = (*accent, 1)
        bsdf.inputs["Emission Strength"].default_value = 7.0
    nt.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return m


def cube(name, loc, dim, mat, bevel=.0):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = dim
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = ob.modifiers.new("edge radius", "BEVEL")
        mod.width, mod.segments = bevel, 2
        mod.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=mod.name)
    ob.data.materials.append(mat)
    return ob


def cyl(name, loc, radius, depth, mat, rotation=(0, 0, 0), vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rotation)
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(mat)
    bevel = ob.modifiers.new("machined rim", "BEVEL")
    bevel.width, bevel.segments = min(radius * .12, .075), 2
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return ob


def wedge(name, yf, yb, wf, wb, hf, hb, mat, z=0):
    vs = [(-wf/2,yf,z-hf/2),(wf/2,yf,z-hf/2),(wb/2,yb,z-hb/2),(-wb/2,yb,z-hb/2),
          (-wf/2,yf,z+hf/2),(wf/2,yf,z+hf/2),(wb/2,yb,z+hb/2),(-wb/2,yb,z+hb/2)]
    faces = [(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
    me = bpy.data.meshes.new(name + "Mesh")
    me.from_pydata(vs, [], faces)
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bevel = ob.modifiers.new("hull soften", "BEVEL")
    bevel.width, bevel.segments = .075, 3
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return ob


def parent(ob, root):
    ob.parent = root
    return ob


def build_ship():
    clear_scene()
    OUT.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    hull = pbr_material("Hae-mu ceramic hull", (.105,.145,.17), .78, .38, scale=5.0)
    armor = pbr_material("Hae-mu layered armour", (.18,.235,.255), .86, .29, scale=8.0)
    edge = pbr_material("Titanium machined edge", (.34,.39,.41), .94, .21, scale=12.0)
    graphite = pbr_material("Thermal graphite", (.018,.027,.036), .58, .63, scale=18.0)
    copper = pbr_material("Heat-scarred copper", (.25,.065,.018), .83, .34, scale=10.0)
    cyan = pbr_material("Ion plasma", (.02,.16,.24), .15, .17, accent=(.10,.76,1.0), scale=4.0)
    amber = pbr_material("Navigation glass", (.26,.05,.006), .12, .20, accent=(1.0,.18,.015), scale=6.0)
    root = bpy.data.objects.new("Hae-mu V2 — Line Cruiser", None)
    bpy.context.collection.objects.link(root)

    # Primary original silhouette: a long low armoured blade, not a franchise triangle.
    parent(wedge("faceted deep keel", -8.5, 9.1, 2.0, 6.1, .62, 2.55, hull, -.22), root)
    parent(wedge("split sensor prow", -12.5, -7.4, .32, 2.25, .12, .72, edge, .12), root)
    parent(wedge("command armour spine", -5.0, 4.15, 1.22, 2.48, .58, 1.34, armor, 1.43), root)
    parent(cube("underside structural keel", (0, .65, -1.53), (3.15, 16.3, .55), graphite, .10), root)

    # Layered armour volumes and inset seam strips.
    for side in (-1, 1):
        for i in range(9):
            y = -6.35 + i * 1.46
            outward = 2.28 + .20 * abs(i-4)/4
            plate = parent(cube("removable armour cassette", (side*outward, y, .18 + .05*(i%2)),
                (1.15, 1.20, 1.02), armor, .075), root)
            parent(cube("armour shadow gap", (side*(outward-.60), y-.50, .06),
                (.08, .075, .66), graphite, .012), root)
            parent(cube("cassette edge", (side*(outward+.54), y, .55),
                (.035, .92, .12), edge, .012), root)
        parent(cube("longitudinal weapon rail", (side*2.67, -.1, 1.02), (.30, 11.5, .23), edge, .035), root)
        # heat exchanger fins, visible only in dedicated service bands
        for y in (-3.5, -.1, 3.3):
            for n in range(5):
                parent(cube("radiator fin", (side*2.18, y + n*.15, -.67), (.36,.055,.42), graphite, .008), root)

    # Asymmetrical recovery recess on starboard, with internal ribs and work lights.
    parent(cube("starboard recovery bay", (3.02, .95, .35), (1.30, 5.35, 1.10), graphite, .08), root)
    for y in (-.8,.35,1.5,2.65):
        parent(cube("recovery bay rib", (3.67,y,.42), (.10,.16,.82), edge, .015), root)
        parent(cube("recovery bay light", (3.73,y,.76), (.06,.12,.055), amber, .008), root)

    # Command sensors: off-axis small mass, with no familiar bridge silhouette.
    parent(wedge("sensor blister", (-3.8), -1.05, .55, 1.0, .24, .40, graphite, 2.16), root)
    for x in (-.43,.43):
        parent(cyl("sensor aperture", (x,-3.72,2.24), .12,.06,cyan,rotation=(math.radians(90),0,0)),root)

    # Heavy guns are sunk into barbettes, supported by realistic mechanisms.
    for y in (-4.0, 1.9):
        parent(cyl("heavy turret ring", (0,y,1.52), .78,.24,edge),root)
        parent(cube("twin cannon housing", (0,y-.08,1.83), (1.22,.86,.42),armor,.06),root)
        for x in (-.29,.29):
            parent(cyl("heavy cannon barrel", (x,y-.94,1.89), .095,1.5,graphite,rotation=(math.radians(90),0,0)),root)
            parent(cyl("recoil jacket", (x,y-.53,1.89), .15,.42,edge,rotation=(math.radians(90),0,0)),root)
    for side in (-1,1):
        for y in (-5.2,-2.25,.65,3.45):
            parent(cyl("point defense cupola", (side*3.02,y,.63),.22,.42,edge,rotation=(0,math.radians(90),0)),root)

    # Four physically separated engines with cable conduits, heat shields and luminous cores.
    for x in (-2.35,-.78,.78,2.35):
        parent(cube("isolated engine strut", (x,9.0,.12),(.76,4.95,.75),armor,.09),root)
        parent(cube("engine coolant conduit", (x+.23,8.72,.58),(.08,4.15,.08),copper,.015),root)
        parent(cube("engine heat shield", (x,10.52,.20),(1.08,.34,1.10),graphite,.06),root)
        parent(cyl("engine nozzle", (x,11.08,.20),.44,.54,edge,rotation=(math.radians(90),0,0)),root)
        parent(cyl("ion engine bloom", (x,11.38,.20),.265,.075,cyan,rotation=(math.radians(90),0,0)),root)
        for side in (-1,1):
            parent(cube("nacelle vane", (x+side*.36,10.78,.52),(.05,.68,.46),graphite,.01),root)

    # Dense but purposeful greebles: deck tiles, equipment housings, vents, conduits.
    for lane in (-1.42,0,1.42):
        for i in range(10):
            y=-5.65+i*1.07
            parent(cube("deck armour tile", (lane,y,1.12+(.025 if i%2 else 0)),
                (.87 if lane else 1.02,.77,.085), armor if i%3 else hull,.022),root)
            if i % 2 == 0:
                parent(cube("deck service channel", (lane,y-.24,1.19),(.16,.27,.032),graphite,.008),root)
    for side in (-1,1):
        for idx,y in enumerate((-4.7,-2.85,-.95,.95,2.85,4.72)):
            parent(cube("external systems cabinet",(side*2.33,y,1.03),(.42,.45,.29),graphite,.035),root)
            parent(cube("cabinet label light",(side*2.55,y,1.12),(.022,.10,.04),amber,.004),root)
            parent(cube("maintenance conduit",(side*2.64,y,.85),(.06,.68,.06),copper,.01),root)
    for x in (-1.78,1.78):
        parent(cube("bow marker",(x,-8.87,.44),(.12,.09,.09),amber,.012),root)
    for side in (-1,1):
        parent(cube("communications mast",(side*1.18,-.95,2.52),(.075,.075,1.45),edge,.012),root)

    return root


def render(root):
    bpy.ops.object.camera_add(location=(17.8,-24.6,12.6))
    camera=bpy.context.object
    camera.data.lens=57
    camera.rotation_euler=(Vector((0,0,.25))-camera.location).to_track_quat("-Z","Y").to_euler()
    bpy.context.scene.camera=camera
    for loc,energy,size,color in [((-13,-14,18),2300,9,(.38,.66,1)),((13,-1,11),1600,7,(1,.30,.09)),((1,14,6),1300,8,(.16,.47,1)),((0,-5,19),1050,10,(.30,.50,1.0))]:
        bpy.ops.object.light_add(type="AREA",location=loc)
        light=bpy.context.object
        light.data.energy,light.data.shape,light.data.size,light.data.color=energy,"DISK",size,color
        light.rotation_euler=(Vector((0,0,0))-light.location).to_track_quat("-Z","Y").to_euler()
    world=bpy.data.worlds.new("Deep space preview")
    world.use_nodes=True
    world.node_tree.nodes["Background"].inputs["Color"].default_value=(.001,.003,.009,1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value=.16
    bpy.context.scene.world=world
    scene=bpy.context.scene
    scene.render.engine="BLENDER_EEVEE"
    scene.render.resolution_x,scene.render.resolution_y=1440,810
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG"
    scene.render.filepath=str(PREVIEW)
    scene.render.film_transparent=False
    scene.view_settings.look="AgX - Medium High Contrast"
    scene.view_settings.exposure = .85
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    hero=build_ship()
    render(hero)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "haemu_line_ship_v2.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH": obj.select_set(True)
    bpy.context.view_layer.objects.active=next((o for o in bpy.context.selected_objects if o.type=="MESH"),None)
    bpy.ops.export_scene.gltf(filepath=str(OUT / "haemu_line_ship_lod0_v2.glb"), export_format="GLB", use_selection=True, export_materials="EXPORT", export_cameras=False, export_lights=False)
