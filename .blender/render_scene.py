import bpy
from os import getenv

# SAMPLES = 1
# SAMPLES = 128
# SAMPLES = 1024
SAMPLES = 4096
# SAMPLES = 8192

name = bpy.path.display_name_from_filepath(bpy.data.filepath)

if "puzzles/" in bpy.data.filepath:
	name = "puzzles/" + name

scene = bpy.context.scene
scene.name = name
scene.use_nodes = True

if scene.view_layers[0].name == "ViewLayer":
	scene.view_layers[0].name = "main"

scene.frame_current = 0
scene.frame_start = 0
# scene.frame_end = 16

scene.render.use_multiview = True
scene.render.views_format = "MULTIVIEW"
scene.render.resolution_x = 640
scene.render.resolution_y = 400
#scene.render.resolution_x = 320
#scene.render.resolution_y = 200

scene.cycles.use_adaptive_sampling = False
scene.cycles.use_denoising = True
#scene.cycles.use_denoising = False

# TODO: make these not show up??
scene.render.filepath = "/tmp/" + name + "_"
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"

world = bpy.data.worlds["World"]
# world.mist_settings.start = 0.1  # 0.1?
# world.mist_settings.depth = 100  # 20?
# world.mist_settings.falloff = "LINEAR"
world.mist_settings.falloff = "LINEAR"

default_frame_end = scene.frame_end


def find_layer_collection(layer_collection, collection):
	if layer_collection.collection == collection:
		return layer_collection

	for child_collection in layer_collection.children:
		result = find_layer_collection(child_collection, collection)
		if result:
			return result

	return None


# bpy.ops.object.select_pattern(pattern="Camera_*", extend=False)
cameras = [obj for obj in bpy.data.objects if obj.type == "CAMERA"]
# for camera in bpy.context.selected_objects:
for camera in cameras:
	if camera.type != "CAMERA" or "-noimp" in camera.name or camera.hide_render:
		continue

	camera_name = camera.name.removeprefix("Camera_")

	if getenv("CAMERAS") and getenv("CAMERAS") not in camera_name:
		# print("Skipping camera " + camera_name, flush=True)
		continue

	if camera_name == "0":
		scene.cycles.samples = 4
	else:
		scene.cycles.samples = SAMPLES

	for view in reversed(scene.render.views):
		if view.name in ("left", "right"):
			scene.render.views[view.name].use = False
		else:
			scene.render.views.remove(view)

	scene.render.views.new(camera_name)
	# scene.render.views[camera_name].camera_suffix = "_" + camera_name
	# print("rendering " + camera.name)
	scene.camera = camera
	scene.frame_end = camera.get("frame_end", default_frame_end)

	if "Composite" in scene.node_tree.nodes:
		# TODO: don’t clear all nodes, use the input of this as a base
		# print("scene compositing nodetree has a Composite node")
		pass

	scene.node_tree.nodes.clear()

	for layer in scene.view_layers:
		# print(camera, layer, camera.users_collection, layer_collection.exclude)
		layer_collection = find_layer_collection(layer.layer_collection, camera.users_collection[0])
		layer.use = not layer.name.startswith("_") and not layer_collection.exclude

		if not layer.use:
			# print("Skipping layer " + layer.name, flush=True)
			continue

		# print("setting up rendering for layer " + layer.name)
		layer.use_pass_combined = True
		layer.use_pass_z = False
		layer.use_pass_mist = True

		r_layers = scene.node_tree.nodes.new("CompositorNodeRLayers")
		image_output = scene.node_tree.nodes.new("CompositorNodeOutputFile")
		mist_output = scene.node_tree.nodes.new("CompositorNodeOutputFile")
		# mist_output2 = scene.node_tree.nodes.new("CompositorNodeOutputFile")

		# depth_output = scene.node_tree.nodes.new("CompositorNodeOutputFile")
		# normalize = scene.node_tree.nodes.new("CompositorNodeNormalize")

		# alpha_convert = scene.node_tree.nodes.new("CompositorNodePremulKey")
		scene.node_tree.links.new(r_layers.outputs["Image"], image_output.inputs[0])
		scene.node_tree.links.new(r_layers.outputs["Mist"], mist_output.inputs[0])
		# scene.node_tree.links.new(r_layers.outputs["Mist"], alpha_convert.inputs[0])
		# scene.node_tree.links.new(alpha_convert.outputs[0], mist_output2.inputs[0])

		# scene.node_tree.links.new(r_layers.outputs["Depth"], normalize.inputs[0])
		# scene.node_tree.links.new(normalize.outputs[0], depth_output.inputs[0])

		r_layers.layer = layer.name

		prefix = layer.name + "/" if layer != scene.view_layers[0] else ""

		image_output.file_slots[0].path = bpy.path.relpath("renders/" + name + "/" + prefix + "#_" + camera_name)
		image_output.base_path = "//"

		mist_output.file_slots[0].path = bpy.path.relpath("renders/" + name + "/" + prefix + "m_#_" + camera_name)
		mist_output.base_path = "//"
		# mist_output2.file_slots[0].path = bpy.path.relpath("renders/" + name + "/" + prefix + "mm_#_" + camera_name)
		# mist_output2.base_path = "//"

		# depth_output.file_slots[0].path = bpy.path.relpath("renders/" + name + "/" + prefix + "d_#_" + camera_name)
		# depth_output.base_path = "//"

	if scene.frame_end > 1 and scene.frame_end < 250:
		bpy.ops.render.render(animation=True)
	else:
		bpy.ops.render.render(write_still=False)
