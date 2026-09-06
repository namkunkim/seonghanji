"""Clean-room concept rebuild for the Wei Hae-mu.

Does not import or share geometry with the retired v1 generator.  The hull is
ring-modelled from a rounded polyhedral bow; every other mass is attached to
that silhouette instead of being a stack of rectangular v1 deck boxes.
"""
from pathlib import Path
import math
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models" / "ships"
REVIEW = ROOT / "out" / "fleet-reference-scene"
BLEND = OUT / "wei_haemu_concept_rebuild_v3.blend"
GLB = OUT / "wei_haemu_concept_rebuild_v3_review.glb"

def clear():
    bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.delete(use_global=False)
    for group in (bpy.data.materials, bpy.data.meshes, bpy.data.cameras, bpy.data.lights):
        for item in list(group):
            if item.users == 0: group.remove(item)

def mat(name, color, metallic=.8, rough=.34, emission=None):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    nt=m.node_tree; p=nt.nodes.get("Principled BSDF"); p.inputs["Base Color"].default_value=(*color,1)
    p.inputs["Metallic"].default_value=metallic; p.inputs["Roughness"].default_value=rough
    # Close-range breakup without a tiled stock texture: broad oxidation in color,
    # fine machining noise in the normal. This is intentionally restrained.
    tex=nt.nodes.new("ShaderNodeTexNoise"); tex.inputs["Scale"].default_value=3.5; tex.inputs["Detail"].default_value=5.0; tex.inputs["Roughness"].default_value=.72
    ramp=nt.nodes.new("ShaderNodeValToRGB"); ramp.color_ramp.elements[0].position=.24; ramp.color_ramp.elements[1].position=.78
    ramp.color_ramp.elements[0].color=(*(v*.48 for v in color),1); ramp.color_ramp.elements[1].color=(*(min(1,v*1.18) for v in color),1)
    fine=nt.nodes.new("ShaderNodeTexNoise"); fine.inputs["Scale"].default_value=115; fine.inputs["Detail"].default_value=3.0
    bump=nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value=.16; bump.inputs["Distance"].default_value=.025
    nt.links.new(tex.outputs["Fac"],ramp.inputs["Fac"]); nt.links.new(ramp.outputs["Color"],p.inputs["Base Color"])
    nt.links.new(fine.outputs["Fac"],bump.inputs["Height"]); nt.links.new(bump.outputs["Normal"],p.inputs["Normal"])
    if emission:
        p.inputs["Emission Color"].default_value=(*emission,1); p.inputs["Emission Strength"].default_value=5
    return m

def cube(name, loc, dims, material, bevel=.0):
    bpy.ops.mesh.primitive_cube_add(location=loc); o=bpy.context.object; o.name=name; o.dimensions=dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod=o.modifiers.new("edge break","BEVEL"); mod.width=bevel; mod.segments=2
        bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(material); return o

def cyl(name, loc, radius, depth, material, rot=(math.pi/2,0,0), verts=20):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    o=bpy.context.object; o.name=name; o.data.materials.append(material)
    mod=o.modifiers.new("machined edge","BEVEL"); mod.width=min(.07,radius*.12); mod.segments=2
    bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=mod.name); return o

def ring_hull(name, sections, material, sides=12):
    """Faceted fuselage from elliptical rings. y is ship length, z is height."""
    vertices=[]
    for y, halfwidth, halfheight, zc in sections:
        for i in range(sides):
            a=math.tau*i/sides
            # Flatten the belly and add a raised dorsal plane without boxes.
            z=zc + math.sin(a)*halfheight
            vertices.append((math.cos(a)*halfwidth,y,z))
    faces=[]
    for r in range(len(sections)-1):
        for i in range(sides): faces.append((r*sides+i,r*sides+(i+1)%sides,(r+1)*sides+(i+1)%sides,(r+1)*sides+i))
    faces.append(tuple(range(sides-1,-1,-1))); end=(len(sections)-1)*sides; faces.append(tuple(end+i for i in range(sides)))
    mesh=bpy.data.meshes.new(name+"Mesh"); mesh.from_pydata(vertices,[],faces); mesh.materials.append(material)
    obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj)
    bevel=obj.modifiers.new("armour edge radius","BEVEL"); bevel.width=.055; bevel.segments=2
    bpy.context.view_layer.objects.active=obj; obj.select_set(True); bpy.ops.object.modifier_apply(modifier=bevel.name); return obj

def make_ship():
    clear(); steel=mat("cold grey armour",(.16,.20,.23),.9,.30); dark=mat("black hangar interior",(.006,.009,.013),.55,.58)
    edge=mat("machined pale edge",(.34,.39,.42),.95,.22); copper=mat("copper thermal manifold",(.30,.095,.025),.85,.28)
    cyan=mat("blue engine ion",(.01,.11,.17),.1,.18,(.08,.7,1)); amber=mat("amber marker",(.18,.035,.004),.2,.23,(1,.18,.015))
    root=bpy.data.objects.new("Wei Hae-mu clean-room rebuild",None); bpy.context.collection.objects.link(root)
    def add(o): o.parent=root; return o
    # The independent, rounded faceted bow is the identity mass. No wedge primitive.
    add(ring_hull("rounded polyhedral armoured hull",[
        (-14.6,.45,.62,.0),(-14.0,1.55,1.20,.0),(-12.7,3.35,1.88,.0),(-10.4,4.75,2.15,.0),
        (-6.5,5.05,2.02,.0),(-2.0,4.95,1.82,.0),(3.1,4.55,1.62,.0),(6.7,3.55,1.48,.0),(8.3,2.7,1.25,.0)],steel))
    # Sloped dorsal citadel: two low plate layers, set into the fuselage.
    add(ring_hull("low dorsal citadel",[(-7.6,2.35,.34,2.0),(-4.8,2.7,.54,2.0),(-.3,2.48,.56,2.0),(4.6,1.95,.36,1.86)],edge,8))
    # Flowing cheek armour follows the bow rather than forming a triangle or flat deck.
    for s in (-1,1):
        for y,x,z,ang in [(-11.8,3.05,.82,-.20),(-9.5,4.12,1.02,-.12),(-7.0,4.48,1.10,0),(-4.4,4.34,1.12,.06)]:
            plate=add(cube("splayed bow armour plate",(s*x,y,z),(.52,1.58,.44),steel,.05)); plate.rotation_euler[1]=s*ang
        rail=add(cube("shoulder armour rail",(s*4.7,-3.6,1.45),(.12,7.1,.15),edge,.02))
    # Two large recessed primary wells (not a repetitive turret line).
    for y,scale in [(-5.0,1.30),(1.35,1.42)]:
        # Raised and deliberately oversized: these must read in a top view as
        # two exposed circular/octagonal wells, never as citadel furniture.
        add(cyl("exposed octagonal gun well",(0,y,2.42),1.22*scale,.34,edge,rot=(0,0,0),verts=8))
        add(cyl("black deep gun well",(0,y,2.61),.98*scale,.22,dark,rot=(0,0,0),verts=16))
        housing=add(cube("exposed heavy twin turret",(0,y-.12,2.92),(1.92*scale,1.42*scale,.58),steel,.12))
        for x in (-.43*scale,.43*scale):
            add(cyl("heavy gun barrel",(x,y-1.30*scale,3.00),.17,2.08*scale,dark,verts=24))
            add(cyl("recoil sleeve",(x,y-.72*scale,3.00),.27,.72*scale,edge,verts=24))
    # Port has compact missile cells and PD; starboard has the deliberately deep recovery throat.
    for y in (-6.6,-4.8,-3.0,-1.2,3.8):
        add(cube("port missile cassette",(-4.72,y,.72),(.55,1.25,.88),dark,.04))
        for z in (.48,.78,1.08): add(cyl("port missile mouth",(-5.01,y,z),.10,.08,edge,rot=(0,math.pi/2,0),verts=12))
    for y in (-10.8,-9.4,-7.9,-6.3,-4.2,-2.2): add(cyl("bow PD sensor",(-4.92,y,.82),.23,.28,edge,rot=(0,math.pi/2,0)))
    # No decorative side panel: a black, deep roof opening with gantry, ribs and aft service route.
    # Actual visible cavity: lowered deck, inner wall and exterior gantry.
    # It is intentionally much deeper than the former decorative black strip.
    add(cube("starboard recovery cavity floor",(4.13,.48,.28),(2.18,5.42,.22),dark,.02))
    add(cube("recovery cavity inner sidewall",(3.10,.48,.87),(.16,5.42,1.34),dark,.02))
    add(cube("recovery cavity outer sidewall",(5.20,.48,.87),(.16,5.42,1.34),edge,.02))
    for y in (-2.0,-.72,.56,1.84,3.05):
        add(cube("hangar transverse rib",(4.15,y,1.07),(2.15,.12,1.46),edge,.02))
        add(cube("hangar worklight",(5.28,y,1.74),(.07,.10,.06),cyan,.008))
    add(cube("hangar outer gantry rail",(5.28,.50,2.00),(.12,5.70,.16),edge,.02))
    # Stern thermal neck plus four large, individually supported engine pods in two vertical layers.
    for x,z in [(-3.65,.88),(-1.22,-.28),(1.22,-.28),(3.65,.88)]:
        add(cube("heavy engine support truss",(x,8.65,z),(.72,3.25,.64),edge,.08))
        add(cyl("thick copper annular manifold",(x,10.15,z),.82,.58,copper,verts=32))
        pod=add(cube("oversized independent engine nacelle",(x,12.12,z),(1.72,4.00,1.76),steel,.16))
        add(cube("engine black heat trench",(x,12.05,z+.90),(1.40,2.86,.16),dark,.02))
        add(cyl("large cyan engine exhaust",(x,14.18,z),.57,.20,cyan,verts=32))
        add(cube("engine coolant run",(x+.56,11.58,z+.62),(.10,3.12,.10),copper,.01))
    for x in (-4.55,4.55): add(cube("stern amber marker",(x,7.0,.62),(.08,.18,.08),amber,.01))
    return root

def add_hero_detail(root):
    """Three readable detail scales over the user's revised primary hull."""
    steel=bpy.data.materials["cold grey armour"]; dark=bpy.data.materials["black hangar interior"]
    edge=bpy.data.materials["machined pale edge"]; copper=bpy.data.materials["copper thermal manifold"]
    cyan=bpy.data.materials["blue engine ion"]; amber=bpy.data.materials["amber marker"]
    def add(o): o.parent=root; return o
    sections=[(-14.6,.45,0.62),(-14.0,1.55,1.20),(-12.7,3.35,1.88),(-10.4,4.75,2.15),(-6.5,5.05,2.02),(-2.0,4.95,1.82),(3.1,4.55,1.62),(6.7,3.55,1.48),(8.3,2.70,1.25)]
    def profile(y):
        for a,b in zip(sections,sections[1:]):
            if a[0] <= y <= b[0]:
                t=(y-a[0])/(b[0]-a[0]); return (a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t)
        return sections[-1][1],sections[-1][2]
    # Fine armour quilting follows the curved dorsal profile instead of hiding it.
    for row in range(27):
        y=-12.7+row*.73; width,height=profile(y)
        lanes=max(1,int(width/.72))
        for lane in range(-lanes,lanes+1):
            x=lane*.68 + (.17 if row%2 else 0)
            if abs(x) > width*.78 or abs(x)<1.30: continue
            z=height+.055-abs(x/width)**2*.17
            panel=cube("dorsal ceramic armour tile",(x,y,z),(.52,.55,.055),steel,.018); panel.rotation_euler[1]=-.035*(x/width); add(panel)
            if (row+lane)%3==0:
                add(cube("armour inspection latch",(x+.19,y+.18,z+.038),(.055,.10,.025),copper,.004))
    # Long dark channels and cross seams establish manufacturing scale.
    for x in (-2.70,-1.95,1.95,2.70):
        add(cube("longitudinal service trench",(x,-1.6,1.88),(.075,13.6,.055),dark,.012))
        for y in (-7.0,-4.7,-2.4,-.1,2.2,4.5):
            add(cube("trench access bridge",(x,y,1.94),(.28,.12,.05),edge,.008))
    # Heat-exchanger farms sit in the aft shoulder, with pipes and dozens of fins.
    for side in (-1,1):
        for bank_y in (4.45,5.45,6.45):
            add(cube("radiator recessed bed",(side*2.86,bank_y,1.45),(.68,.78,.12),dark,.018))
            for fin in range(11):
                add(cube("radiator cooling fin",(side*2.86,bank_y-.32+fin*.064,1.56),(.58,.025,.18),edge,.003))
            add(cube("radiator copper feed",(side*3.22,bank_y,1.57),(.045,.68,.05),copper,.005))
    # Mechanical rings, fasteners and recoil rails make the two gun wells believable.
    for y,rad in ((-5.0,1.30),(1.35,1.42)):
        for n in range(20):
            a=math.tau*n/20; add(cyl("barbette perimeter bolt",(rad*math.cos(a),y+rad*math.sin(a),2.80),.045,.06,edge,rot=(0,0,0),verts=12))
        for x in (-.67,-.22,.22,.67):
            add(cube("turret recoil guide",(x,y-.62,2.77),(.075,1.32,.09),edge,.012))
    # Port combat face receives visible magazine plumbing; starboard bay receives tools.
    for y in (-6.5,-4.7,-2.9,-1.1,3.7):
        add(cube("port armoured cable trunk",(-4.35,y+.58,.44),(.12,1.02,.10),copper,.018))
        for z in (.23,.50,.77): add(cube("port cassette vent",(-5.04,y,z),(.035,.56,.055),edge,.003))
    for y in (-1.85,-.57,.71,1.99,3.0):
        for x in (3.45,3.86,4.27,4.68):
            add(cube("hangar deck guide",(x,y,.43),(.24,.045,.035),edge,.004))
        add(cube("hangar amber hazard lamp",(5.27,y,1.24),(.055,.10,.055),amber,.006))
    # Engine pods need a second detail scale visible in the rear and 3/4 views.
    for x,z in [(-3.65,.88),(-1.22,-.28),(1.22,-.28),(3.65,.88)]:
        for offset in (-.58,-.29,0,.29,.58):
            add(cube("engine radiator rib",(x+offset,12.15,z+.93),(.075,2.75,.16),dark,.008))
        for y in (10.85,11.55,12.25,12.95):
            add(cube("engine armour collar",(x,y,z),(1.84,.10,1.88),edge,.025))
        add(cyl("engine inner luminous throat",(x,14.31,z),.39,.10,cyan,verts=40))
    # Navigation and formation lights are sparse and recessed.
    for side in (-1,1):
        for y in (-10.4,-7.1,-3.8,-.5,2.8,6.0):
            width,_=profile(y); add(cube("recessed navigation pocket",(side*(width+.05),y,.32),(.07,.16,.10),dark,.008)); add(cube("navigation point",(side*(width+.095),y,.32),(.018,.055,.038),amber,.003))

def render_views():
    bpy.ops.object.camera_add(); camera=bpy.context.object; bpy.context.scene.camera=camera; camera.data.type="ORTHO"
    world=bpy.data.worlds.new("neutral studio"); bpy.context.scene.world=world; world.use_nodes=True
    world.node_tree.nodes["Background"].inputs["Color"].default_value=(.025,.032,.045,1); world.node_tree.nodes["Background"].inputs["Strength"].default_value=.55
    for loc,energy,size,color in [((-13,-16,20),2200,10,(.65,.76,1)),((15,-9,12),1700,8,(1,.48,.22)),((4,16,16),2000,9,(.4,.58,1))]:
        bpy.ops.object.light_add(type="AREA",location=loc); l=bpy.context.object; l.data.energy=energy; l.data.shape="DISK"; l.data.size=size; l.data.color=color; l.rotation_euler=(Vector((0,0,.2))-l.location).to_track_quat("-Z","Y").to_euler()
    scene=bpy.context.scene; scene.render.engine="BLENDER_EEVEE"; scene.render.resolution_x=720; scene.render.resolution_y=405; scene.render.resolution_percentage=100; scene.render.image_settings.file_format="PNG"; scene.view_settings.look="AgX - Medium High Contrast"; scene.view_settings.exposure=1.3
    views=[("top",(0,0,37),(0,.5,.1),34),("starboard",(29,.5,3),(0,.5,.1),34),("bow",(0,-35,3),(0,-2,.1),16),("three_quarter",(21,-27,17),(0,.5,.2),34)]
    result=[]
    for name,loc,target,scale in views:
        camera.location=loc; camera.rotation_euler=(Vector(target)-camera.location).to_track_quat("-Z","Y").to_euler(); camera.data.ortho_scale=scale
        p=REVIEW/f"wei-haemu-concept-rebuild-v3-{name}.png"; scene.render.filepath=str(p); bpy.ops.render.render(write_still=True); result.append(p)
    ims=[bpy.data.images.load(str(p),check_existing=False) for p in result]; sheet=bpy.data.images.new("concept rebuild contact",1440,810,alpha=False); px=[0.0]*(1440*810*4)
    for n,im in enumerate(ims):
        ox=(n%2)*720; oy=(1-n//2)*405; source=list(im.pixels[:])
        for row in range(405): px[((oy+row)*1440+ox)*4:((oy+row)*1440+ox+720)*4]=source[row*720*4:(row+1)*720*4]
    sheet.pixels=px; sheet.filepath_raw=str(REVIEW/"wei-haemu-concept-rebuild-v3-contact-sheet.png"); sheet.file_format="PNG"; sheet.save()

def main():
    OUT.mkdir(parents=True,exist_ok=True); REVIEW.mkdir(parents=True,exist_ok=True); root=make_ship(); add_hero_detail(root); render_views(); bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.context.scene.objects:
        if o.type=="MESH": o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(GLB),export_format="GLB",use_selection=True,export_materials="EXPORT",export_cameras=False,export_lights=False)
if __name__=="__main__": main()
