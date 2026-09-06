"""Finalize the approved Hae-mu V3 review mesh as a game-ready asset set.

Preserves the editable review source and writes a separate final Blend, four
GLBs, and shared 4K PBR textures. Static geometry is batched by material before
LOD generation to replace hundreds of object-level draw calls.
"""
from pathlib import Path
import gc
import math
import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "assets" / "models" / "ships"
TEXTURE_DIR = ROOT / "assets" / "textures" / "ships" / "haemu_v3"
SOURCE = MODEL_DIR / "wei_haemu_concept_rebuild_v3.blend"
FINAL_BLEND = MODEL_DIR / "haemu_line_ship_v3_final.blend"
SIZE = 4096


def save_rgba(name, rgb, alpha=1.0, non_color=False):
    image = bpy.data.images.new(name, width=SIZE, height=SIZE, alpha=True, float_buffer=False)
    rgba = np.empty((SIZE, SIZE, 4), dtype=np.float32)
    rgba[:, :, :3] = rgb
    rgba[:, :, 3] = alpha
    image.pixels.foreach_set(rgba.ravel())
    path = TEXTURE_DIR / f"{name}.png"
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    if non_color:
        image.colorspace_settings.name = "Non-Color"
    image.save()
    del rgba
    gc.collect()
    return image


def build_textures():
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(750)
    y = np.arange(SIZE, dtype=np.int32)[:, None]
    x = np.arange(SIZE, dtype=np.int32)[None, :]
    seams = ((x % 512) < 7) | ((y % 384) < 6)
    secondary = (((x + 173) % 1024) < 4) | (((y + 91) % 768) < 4)
    scratches = (((x * 7 + y * 3) % 1301) < 2)
    noise = rng.random((SIZE, SIZE), dtype=np.float32)
    value = np.clip(.78 + (noise - .5) * .12, .58, .94)
    value[secondary] *= .82
    value[seams] *= .32
    value[scratches] = np.minimum(value[scratches] * 1.16, 1.0)
    base_rgb = np.repeat(value[:, :, None], 3, axis=2)
    base = save_rgba("haemu_v3_BaseColor", base_rgb)
    del base_rgb, value

    # Tangent-space OpenGL normal: restrained surface waviness and sharper seams.
    nx = (rng.random((SIZE, SIZE), dtype=np.float32) - .5) * .055
    ny = (rng.random((SIZE, SIZE), dtype=np.float32) - .5) * .055
    nx[seams] *= 2.8
    ny[seams] *= 2.8
    nz = np.sqrt(np.clip(1.0 - nx * nx - ny * ny, .0, 1.0))
    normal_rgb = np.stack((nx * .5 + .5, ny * .5 + .5, nz), axis=2)
    normal = save_rgba("haemu_v3_Normal", normal_rgb, non_color=True)
    del nx, ny, nz, normal_rgb

    # ORM: R ambient occlusion, G roughness, B metallic.
    orm = np.empty((SIZE, SIZE, 3), dtype=np.float32)
    orm[:, :, 0] = np.where(seams, .54, .91)
    orm[:, :, 1] = np.clip(.33 + noise * .18, .28, .58)
    orm[:, :, 1][seams] = .70
    orm[:, :, 2] = np.where(scratches, .96, .88)
    orm_image = save_rgba("haemu_v3_ORM", orm, non_color=True)
    del orm, noise, seams, secondary, scratches

    # A restrained mask is supplied for engine/navigation material authoring.
    emission_rgb = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    band = ((x % 1024) > 930) & ((y % 768) > 716)
    emission_rgb[:, :, 0][band] = .08
    emission_rgb[:, :, 1][band] = .72
    emission_rgb[:, :, 2][band] = 1.0
    emission = save_rgba("haemu_v3_Emissive", emission_rgb)
    del emission_rgb, band
    gc.collect()
    return base, normal, orm_image, emission


def attach_pbr(material, images):
    base, normal, orm, _emission = images
    material.use_nodes = True
    nt = material.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    for node in list(nt.nodes):
        if node != bsdf and node.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(node)
    base_node = nt.nodes.new("ShaderNodeTexImage")
    base_node.name = "Shared 4K BaseColor"
    base_node.image = base
    nt.links.new(base_node.outputs["Color"], bsdf.inputs["Base Color"])
    normal_node = nt.nodes.new("ShaderNodeTexImage")
    normal_node.name = "Shared 4K Normal"
    normal_node.image = normal
    normal_node.image.colorspace_settings.name = "Non-Color"
    normal_map = nt.nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = .72
    nt.links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
    nt.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    orm_node = nt.nodes.new("ShaderNodeTexImage")
    orm_node.name = "Shared 4K ORM"
    orm_node.image = orm
    orm_node.image.colorspace_settings.name = "Non-Color"
    split = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(orm_node.outputs["Color"], split.inputs["Color"])
    nt.links.new(split.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(split.outputs["Blue"], bsdf.inputs["Metallic"])


def join_by_material():
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    groups = {}
    for obj in meshes:
        material = obj.data.materials[0] if obj.data.materials else None
        groups.setdefault(material, []).append(obj)
    joined = []
    for index, (material, objects) in enumerate(groups.items()):
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.join()
        result = bpy.context.object
        result.name = f"LOD0_batch_{index:02d}_{material.name if material else 'unassigned'}"
        result.parent = None
        joined.append(result)
    return joined


def unwrap(objects):
    for obj in objects:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(58), island_margin=.003, area_weight=.25)
        bpy.ops.object.mode_set(mode="OBJECT")


def export_selected(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_render = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True,
        export_materials="EXPORT", export_cameras=False, export_lights=False,
        export_yup=True,
    )


def make_lod(source, level, ratio):
    copies = []
    for obj in source:
        copy = obj.copy()
        copy.data = obj.data.copy()
        bpy.context.collection.objects.link(copy)
        copy.name = obj.name.replace("LOD0_", f"LOD{level}_")
        modifier = copy.modifiers.new(f"LOD{level} collapse", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = ratio
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = copy
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        copies.append(copy)
    return copies


def main():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    images = build_textures()
    static_batches = join_by_material()
    unwrap(static_batches)
    for material in bpy.data.materials:
        if "engine ion" not in material.name and "amber marker" not in material.name:
            attach_pbr(material, images)
    bpy.ops.wm.save_as_mainfile(filepath=str(FINAL_BLEND))
    export_selected(MODEL_DIR / "haemu_line_ship_lod0_v3_final.glb", static_batches)
    for level, ratio in ((1, .37), (2, .075), (3, .012)):
        lod = make_lod(static_batches, level, ratio)
        export_selected(MODEL_DIR / f"haemu_line_ship_lod{level}_v3_final.glb", lod)
        for obj in lod:
            bpy.data.objects.remove(obj, do_unlink=True)
    print(f"HAEMU_V3_FINAL batches={len(static_batches)} textures=4 lods=4")


if __name__ == "__main__":
    main()
