import bpy
from glob import glob
from pathlib import Path
from pprint import pprint
import re

bone_prefix = "mixamorig:"


def main():
	for action in bpy.data.actions:
		bpy.data.actions.remove(action)

	# bpy.ops.wm.read_homefile(app_template="")
	bpy.ops.outliner.orphans_purge(do_recursive=True)
	# bpy.ops.object.material_slot_remove_unused()
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete()

	filepaths = glob("/Users/Freya/Downloads/mixamo_workspace/nils/*.fbx")
	filepaths.sort()
	# pprint(filepaths)

	for (i, filepath) in enumerate(filepaths):
		import_armature(filepath)
		bpy.data.actions[0].name = "wtf_" + Path(filepath).stem

		add_root_bone()
		fix_bones()
		scale_all()
		copy_hips()

		if i < len(filepaths) - 1:
			delete_armature()

	# bpy.data.actions[-1].name = "RESET"
	# bpy.data.objects[1].name = "Body"

	bpy.context.area.ui_type = "TEXT_EDITOR"

	push_actions()
	sort_nla_tracks()

	bpy.ops.outliner.orphans_purge(do_recursive=True)


def push_actions():
	previous_context_area_type = bpy.context.area.type

	for action in bpy.data.actions:
		# print(action)
		if action.name.startswith("wtf_"):
			action.name = action.name[4:]
		bpy.ops.object.mode_set(mode="OBJECT")
		bpy.context.area.type = "DOPESHEET_EDITOR"

		bpy.context.space_data.ui_mode = "ACTION"
		# print(bpy.context.selected_objects)
		# bpy.context.selected_objects[0].animation_data.action = action
		bpy.data.objects["Armature"].animation_data.action = action
		bpy.ops.object.mode_set(mode="OBJECT")
		bpy.context.area.type = "DOPESHEET_EDITOR"

		bpy.context.space_data.ui_mode = "ACTION"
		bpy.ops.action.push_down()

	bpy.context.area.type = previous_context_area_type


def fix_bones():
	bpy.ops.object.mode_set(mode="OBJECT")

	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	bpy.context.object.show_in_front = True

	for rig in bpy.context.selected_objects:
		if rig.type == "ARMATURE":
			for mesh in rig.children:
				for vg in mesh.vertex_groups:
					new_name = vg.name
					new_name = new_name.replace(bone_prefix, "")
					rig.pose.bones[vg.name].name = new_name
					vg.name = new_name
			for bone in rig.pose.bones:
				bone.name = bone.name.replace(bone_prefix, "")

	for action in bpy.data.actions:
		fc = action.fcurves
		for f in fc:
			f.data_path = f.data_path.replace(bone_prefix, "")


def scale_all():
	bpy.ops.object.mode_set(mode="OBJECT")

	bpy.ops.object.mode_set(mode="POSE")
	bpy.ops.pose.select_all(action="SELECT")
	bpy.context.area.type = "GRAPH_EDITOR"
	bpy.context.space_data.dopesheet.filter_text = "Location"
	bpy.context.space_data.pivot_point = "CURSOR"
	bpy.context.space_data.dopesheet.use_filter_invert = False

	# print(bpy.context.selected_objects)
	bpy.ops.anim.channels_select_all(action="SELECT")

	bpy.ops.transform.resize(
		value=(1, 0.01, 1),
		orient_type="GLOBAL",
		orient_matrix=((1, 0, 0), (0, 1, 0), (0, 0, 1)),
		orient_matrix_type="GLOBAL",
		constraint_axis=(False, True, False),
		mirror=True,
		use_proportional_edit=False,
		proportional_edit_falloff="SMOOTH",
		proportional_size=1,
		use_proportional_connected=False,
		use_proportional_projected=False,
	)


def copy_hips():
	bpy.context.area.ui_type = "FCURVES"
	# SELECT OUR ROOT MOTION BONE
	bpy.ops.pose.select_all(action="DESELECT")
	bpy.context.object.pose.bones["Root"].bone.select = True
	# SET FRAME TO ZERO
	bpy.ops.graph.cursor_set(frame=0.0, value=0.0)
	# ADD NEW KEYFRAME
	bpy.ops.anim.keyframe_insert_menu(type="Location")
	# SELECT ONLY HIPS AND LOCTAIUON GRAPH DATA
	bpy.ops.pose.select_all(action="DESELECT")
	print(bpy.context.object.pose.bones.keys)
	bpy.context.object.pose.bones["Hips"].bone.select = True
	bpy.context.area.ui_type = "DOPESHEET"
	bpy.context.space_data.dopesheet.filter_text = "Location"
	bpy.context.area.ui_type = "FCURVES"
	# COPY THE LOCATION VALUES OF THE HIPS AND DELETE THEM
	bpy.ops.graph.copy()
	bpy.ops.graph.select_all(action="DESELECT")

	myFcurves = bpy.context.object.animation_data.action.fcurves
	# print(myFcurves)

	for i in myFcurves:
		if str(i.data_path) == 'pose.bones["Hips"].location':
			if i.array_index != 1:
				myFcurves.remove(i)

	bpy.ops.pose.select_all(action="DESELECT")
	bpy.context.object.pose.bones["Root"].bone.select = True
	bpy.ops.graph.paste()

	# Get the animation data and action
	anim_data = bpy.context.object.animation_data
	action = anim_data.action if anim_data else None

	# Get the fcurves for the root bone's location
	fcurves = [
		fcurve
		for fcurve in action.fcurves
		if fcurve.data_path == 'pose.bones["Root"].location'  # and fcurve.array_index in range(3)
	]
	# for i in fcurves:
	# 	print(i.data_path)

	# Set the minimum Y value of the root bone to 0
	z_fcurve = fcurves[1]
	for keyframe in z_fcurve.keyframe_points:
		if keyframe.co.y < 0:
			keyframe.co.y = 0

	anim_data = bpy.context.object.animation_data
	action = anim_data.action if anim_data else None
	hips_fcurves = [
		hips_fcurve
		for hips_fcurve in action.fcurves
		if hips_fcurve.data_path == 'pose.bones["Hips"].location'  # and hips_fcurve.array_index in range(3)
	]
	for keyframe in hips_fcurves[0].keyframe_points:
		if keyframe.co.y > 0:
			keyframe.co.y = 0
			# keyframe.co.y = keyframe.co.y / 2

	bpy.context.area.ui_type = "VIEW_3D"


def delete_armature():
	bpy.ops.object.mode_set(mode="OBJECT")
	bpy.ops.object.select_all(action="SELECT")

	bpy.ops.object.delete(use_global=False, confirm=False)


def import_armature(path):
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

	bpy.ops.import_scene.fbx(filepath=path)


def add_root_bone():
	global bone_prefix

	# armature = bpy.data.objects[0]
	armature = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")

	print("armature =", armature)

	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.armature.bone_primitive_add()

	# root_bone = armature.data.edit_bones.new("Root")
	# root_bone.tail.y = 30

	bpy.ops.object.mode_set(mode="POSE")
	bpy.context.object.pose.bones["Bone"].name = "Root"

	bpy.ops.object.mode_set(mode="EDIT")
	# armature.data.edit_bones["mixamorig:Hips"].parent = root_bone

	# for bone in armature.data.edit_bones: print(bone)

	match = re.search(r"^mixamorig\d?\d?:", armature.data.edit_bones.keys()[0])
	if match:
		bone_prefix = match.group()
		print("Found bone prefix '" + bone_prefix + "'")

	armature.data.edit_bones[bone_prefix + "Hips"].parent = armature.data.edit_bones["Root"]

	bpy.ops.object.mode_set(mode="OBJECT")


def sort_nla_tracks():
	# Switch to the NLA Editor
	previous_context_area_type = bpy.context.area.type
	bpy.context.area.type = "NLA_EDITOR"

	# Get the active object
	obj = bpy.context.active_object

	# Check if the active object has an animation data
	if obj.animation_data:
		# Get the NLA tracks
		tracks = obj.animation_data.nla_tracks

		# Sort the tracks alphabetically by name
		sorted_tracks = sorted(tracks, key=lambda x: x.name)

		# Deselect all tracks first
		bpy.ops.nla.select_all(action="DESELECT")

		# Select and move tracks one by one
		for track in sorted_tracks:
			track.select = True
			bpy.ops.anim.channels_move(direction="BOTTOM")
			track.select = False

	bpy.context.area.type = previous_context_area_type


if __name__ == "__main__":
	main()
