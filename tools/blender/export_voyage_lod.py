import bpy
import sys

args = sys.argv[sys.argv.index("--") + 1:]
if len(args) != 1:
    raise RuntimeError("Usage: blender -b source.blend --python export_voyage_lod.py -- output.glb")
output_path = args[0]

mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
if not mesh_objects:
    raise RuntimeError("No mesh objects found")

# A 28-ship squadron is viewed at formation distance.  Keep a compact, readable
# silhouette budget rather than loading each source model's multi-million faces.
for obj in mesh_objects:
    polygon_count = len(obj.data.polygons)
    if polygon_count > 60000:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        decimate = obj.modifiers.new("Voyage formation LOD", 'DECIMATE')
        decimate.ratio = 60000.0 / float(polygon_count)
        decimate.decimate_type = 'COLLAPSE'
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        obj.select_set(False)

bpy.ops.object.select_all(action='DESELECT')
for obj in mesh_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = mesh_objects[0]
bpy.ops.export_scene.gltf(
    filepath=output_path,
    export_format='GLB',
    use_selection=True,
    export_cameras=False,
    export_lights=False,
    export_materials='EXPORT',
)
