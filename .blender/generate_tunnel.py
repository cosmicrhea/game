import bpy
import math

# fmt: off
# ===================== USER SETTINGS =====================
# Geometry
inner_radius      = 2.45        # inner radius of tunnel (m)
thickness         = 0.30        # lining thickness (m)
ring_length       = 1.5         # length of one ring along tunnel (m)
full_circle_res   = 128         # smoothness of curvature (full circle)

# Segmentation
regular_count     = 5           # number of big (regular) segments
key_angle_factor  = 0.6         # key segment angle = factor * regular

# Bolt pocket layout (round dimples)
bolt_angle_frac   = 0.30        # fraction of half-angle from segment center (0..1)
bolt_radius       = 0.10        # radius of bolt pocket (m)
bolt_depth_frac   = 0.35        # fraction of thickness for how deep the recess is

# Handle hole layout (wedge / rectangular recess)
handle_angle_frac = 0.45        # fraction of half-angle from segment center
handle_width_tan  = 0.45        # tan width as fraction of chord length
handle_height_tan = 0.18        # tan height as fraction of chord length
handle_depth_frac = 0.30        # fraction of thickness for recess depth
handle_diagonal_deg = 15.0      # rotation of wedge around normal (slight diagonal)

# Geometry Nodes – tunnel repetition
gn_ring_count     = 10          # how many rings along tunnel
gn_ring_spacing   = 1.5         # spacing between ring origins (m)
gn_rot_jitter_deg = 40          # per-ring random twist around tunnel axis (deg)
gn_pos_jitter     = 0.01        # per-ring random shift along axis (m)
gn_seed           = 27          # random seed
# ========================================================
# fmt: on

# Derived angles
regular_angle_deg = 360.0 / (regular_count + key_angle_factor)
key_angle_deg = regular_angle_deg * key_angle_factor

print(f"regular angle: {regular_angle_deg:.3f}°")
print(f"key angle:     {key_angle_deg:.3f}°")

# --------------------------------------------------------
# Cleanup
# --------------------------------------------------------


def clean_old():
    """Aggressively clean all previously generated objects."""
    kill_names = (
        "Segment (Regular)",
        "Segment (Key)",
        "Bolt Pocket (Top)",
        "Bolt Pocket (Bottom)",
        "Handle Hole (Top)",
        "Handle Hole (Bottom)",
        "Bolt Pocket",
        "Handle Hole",
        "Tunnel Controller",
        "TunnelRing",
        "SegReg",
        "SegKey",
        "RingGuide",
        "TBM_Ring",
        "RingBase",
        "TBM_Tunnel",
    )

    for coll in list(bpy.data.collections):
        if coll.name in ("TBM_Ring", "Tunnel"):
            for obj in list(coll.objects):
                bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.collections.remove(coll)

    for obj in list(bpy.data.objects):
        name = obj.name
        if any(
            name == n or name.startswith(n + ".") or name.startswith(n + "_")
            for n in kill_names
        ):
            bpy.data.objects.remove(obj, do_unlink=True)

    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)

    for ng in list(bpy.data.node_groups):
        if ng.name in ("TBM_TunnelAlongZ", "TBM_TunnelProcedural"):
            bpy.data.node_groups.remove(ng, do_unlink=True)


clean_old()

# Create collection
coll_name = "Tunnel"
coll = bpy.data.collections.new(coll_name)
bpy.context.scene.collection.children.link(coll)


def link_to_tunnel_only(obj):
    """Link object to Tunnel collection and unlink from Scene Collection."""
    if obj.name not in coll.objects:
        coll.objects.link(obj)
    if obj.name in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.unlink(obj)


# --------------------------------------------------------
# Create segment template (centered at angle 0)
# --------------------------------------------------------


def make_segment_mesh(name, angle_deg):
    """Create a curved segment arc centered at angle 0.
    Ring is in XZ plane, tunnel grows along Y+."""
    steps = max(8, round(full_circle_res * angle_deg / 360.0))
    a_rad = math.radians(angle_deg)
    start = -a_rad / 2.0
    end = a_rad / 2.0

    verts = []
    faces = []

    r_in = inner_radius
    r_out = inner_radius + thickness
    y0 = -ring_length / 2.0  # back
    y1 = ring_length / 2.0  # front

    for i in range(steps + 1):
        t = start + (end - start) * (i / steps)
        c = math.cos(t)
        s = math.sin(t)

        # Ring in XZ plane: X = r*cos(t), Z = r*sin(t), Y = length
        verts.append((r_in * c, y0, r_in * s))  # inner back
        verts.append((r_out * c, y0, r_out * s))  # outer back
        verts.append((r_in * c, y1, r_in * s))  # inner front
        verts.append((r_out * c, y1, r_out * s))  # outer front

    for i in range(steps):
        b0 = i * 4
        b1 = (i + 1) * 4
        faces.append((b0, b1, b1 + 2, b0 + 2))  # inner
        faces.append((b0 + 1, b0 + 3, b1 + 3, b1 + 1))  # outer
        faces.append((b0, b0 + 1, b1 + 1, b1))  # front
        faces.append((b0 + 2, b1 + 2, b1 + 3, b0 + 3))  # back

    last = steps * 4
    faces.append((0, 2, 3, 1))
    faces.append((last, last + 1, last + 3, last + 2))

    me = bpy.data.meshes.new(name + "_Mesh")
    me.from_pydata(verts, [], faces)
    me.update()
    obj = bpy.data.objects.new(name, me)
    link_to_tunnel_only(obj)

    for p in me.polygons:
        p.use_smooth = False

    return obj


# --------------------------------------------------------
# Create cutter objects (kept for tweaking!)
# --------------------------------------------------------


def create_bolt_cutters(segment_name, angle_deg):
    """Create bolt pocket cutters - KEPT for tweaking.
    Ring in XZ plane, tunnel along Y."""
    cutters = []
    depth = thickness * 0.95
    base_radius = inner_radius - depth / 2.0

    # Center of segment is at angle 0 in XZ plane
    t = 0.0
    x = base_radius * math.cos(t)
    z = base_radius * math.sin(t)

    for y_sign, y_tag in ((-1.0, "Back"), (1.0, "Front")):
        bolt_y = y_sign * ring_length * 0.15

        bpy.ops.mesh.primitive_cylinder_add(
            vertices=20,
            radius=bolt_radius,
            depth=depth,
            location=(x, bolt_y, z),
        )
        cutter = bpy.context.active_object
        cutter.name = f"Bolt Pocket ({y_tag}) - {segment_name}"
        # Rotate cylinder axis to point radially (along X at t=0)
        cutter.rotation_euler = (0.0, math.radians(90.0) + t, 0.0)
        cutter.display_type = "WIRE"
        # Hide from renders (camera rays and shadows)
        cutter.visible_camera = False
        cutter.visible_shadow = False
        link_to_tunnel_only(cutter)
        cutters.append(cutter)

    return cutters


def create_handle_cutters(segment_name, angle_deg):
    """Create handle hole cutters - KEPT for tweaking.
    Ring in XZ plane, tunnel along Y."""
    cutters = []
    half = math.radians(angle_deg / 2.0)

    angle_frac_from_center = 0.75
    offset = -half * angle_frac_from_center

    chord = 2.0 * inner_radius * math.sin(half)
    width = chord * handle_width_tan
    height = chord * handle_height_tan
    depth = thickness * handle_depth_frac

    base_radius = inner_radius - depth * 0.6

    t = offset
    x = base_radius * math.cos(t)
    z = base_radius * math.sin(t)

    from_top_frac = 0.18
    for y_sign, y_tag in ((1.0, "Front"), (-1.0, "Back")):
        handle_y = y_sign * ring_length * (0.5 - from_top_frac)

        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, handle_y, z))
        cutter = bpy.context.active_object
        cutter.name = f"Handle Hole ({y_tag}) - {segment_name}"
        # Scale: depth radial (X), height tangent (Z), width along tunnel (Y)
        cutter.scale = (depth * 0.5, width * 0.5, height * 0.5)

        diag = math.radians(handle_diagonal_deg)
        # Rotate to orient in XZ plane
        cutter.rotation_euler = (0.0, t + diag, math.radians(90.0))
        cutter.display_type = "WIRE"
        # Hide from renders (camera rays and shadows)
        cutter.visible_camera = False
        cutter.visible_shadow = False
        link_to_tunnel_only(cutter)
        cutters.append(cutter)

    return cutters


# --------------------------------------------------------
# Build segments with NON-APPLIED boolean modifiers
# --------------------------------------------------------

print("\n=== Creating segment templates ===")

# Regular segment template
seg_reg = make_segment_mesh("Segment (Regular)", regular_angle_deg)
bolt_cutters_reg = create_bolt_cutters("Regular", regular_angle_deg)
handle_cutters_reg = create_handle_cutters("Regular", regular_angle_deg)

# Add boolean modifiers (NOT applied - stay live!)
for i, cutter in enumerate(bolt_cutters_reg):
    mod = seg_reg.modifiers.new(name=f"Bolt_{i}", type="BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter

for i, cutter in enumerate(handle_cutters_reg):
    mod = seg_reg.modifiers.new(name=f"Handle_{i}", type="BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter

print(f"  Created: {seg_reg.name} with {len(seg_reg.modifiers)} boolean modifiers")

# Key segment template
seg_key = make_segment_mesh("Segment (Key)", key_angle_deg)
bolt_cutters_key = create_bolt_cutters("Key", key_angle_deg)
handle_cutters_key = create_handle_cutters("Key", key_angle_deg)

for i, cutter in enumerate(bolt_cutters_key):
    mod = seg_key.modifiers.new(name=f"Bolt_{i}", type="BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter

for i, cutter in enumerate(handle_cutters_key):
    mod = seg_key.modifiers.new(name=f"Handle_{i}", type="BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter

print(f"  Created: {seg_key.name} with {len(seg_key.modifiers)} boolean modifiers")

# --------------------------------------------------------
# Geometry Nodes: Build ring + tunnel
# --------------------------------------------------------

ng_name = "TBM_TunnelProcedural"
old_ng = bpy.data.node_groups.get(ng_name)
if old_ng:
    bpy.data.node_groups.remove(old_ng, do_unlink=True)

ng = bpy.data.node_groups.new(ng_name, "GeometryNodeTree")

iface = ng.interface
make_in = lambda name, stype: iface.new_socket(
    name=name, in_out="INPUT", socket_type=stype
)
make_out = lambda name, stype: iface.new_socket(
    name=name, in_out="OUTPUT", socket_type=stype
)

make_in("Segment (Regular)", "NodeSocketObject")
make_in("Segment (Key)", "NodeSocketObject")
make_in("Ring Count", "NodeSocketInt")
make_in("Ring Spacing", "NodeSocketFloat")
make_in("Rot Jitter Deg", "NodeSocketFloat")
make_in("Pos Jitter", "NodeSocketFloat")
make_in("Seed", "NodeSocketInt")
make_out("Geometry", "NodeSocketGeometry")

nodes = ng.nodes
links = ng.links
nodes.clear()

group_in = nodes.new("NodeGroupInput")
group_out = nodes.new("NodeGroupOutput")
group_in.location = (-1400, 0)
group_out.location = (1400, 0)

# === STEP 1: Get segment geometries ===
obj_info_reg = nodes.new("GeometryNodeObjectInfo")
obj_info_reg.location = (-1200, 200)
obj_info_reg.transform_space = "RELATIVE"
links.new(group_in.outputs[0], obj_info_reg.inputs["Object"])

obj_info_key = nodes.new("GeometryNodeObjectInfo")
obj_info_key.location = (-1200, -100)
obj_info_key.transform_space = "RELATIVE"
links.new(group_in.outputs[1], obj_info_key.inputs["Object"])

# === STEP 2: Instance regular segments around circle ===
# Create points for regular segments
mesh_line_reg = nodes.new("GeometryNodeMeshLine")
mesh_line_reg.location = (-1000, 400)
mesh_line_reg.inputs["Count"].default_value = regular_count

# *** CRITICAL: Move ALL points to origin (0,0,0) ***
# MeshLine creates points along X axis - we need them all at center
# so rotation fans segments into a circle
set_pos_reg = nodes.new("GeometryNodeSetPosition")
set_pos_reg.location = (-800, 400)
links.new(mesh_line_reg.outputs["Mesh"], set_pos_reg.inputs["Geometry"])
# Position input defaults to (0,0,0) - that's what we want!
# We set Position (not Offset) to move points TO origin

origin_vec_reg = nodes.new("ShaderNodeCombineXYZ")
origin_vec_reg.location = (-800, 350)
origin_vec_reg.inputs[0].default_value = 0.0
origin_vec_reg.inputs[1].default_value = 0.0
origin_vec_reg.inputs[2].default_value = 0.0
links.new(origin_vec_reg.outputs["Vector"], set_pos_reg.inputs["Position"])

# Index for rotation calculation
index_reg = nodes.new("GeometryNodeInputIndex")
index_reg.location = (-1000, 300)

# Rotation angle = (index + 0.5) * regular_angle
add_half = nodes.new("ShaderNodeMath")
add_half.operation = "ADD"
add_half.location = (-600, 300)
add_half.inputs[1].default_value = 0.5
links.new(index_reg.outputs["Index"], add_half.inputs[0])

angle_reg = nodes.new("ShaderNodeMath")
angle_reg.operation = "MULTIPLY"
angle_reg.location = (-400, 300)
angle_reg.inputs[1].default_value = math.radians(regular_angle_deg)
links.new(add_half.outputs["Value"], angle_reg.inputs[0])

# Combine rotation vector (rotate around Y axis for XZ plane ring)
rot_vec_reg = nodes.new("ShaderNodeCombineXYZ")
rot_vec_reg.location = (-200, 300)
links.new(angle_reg.outputs["Value"], rot_vec_reg.inputs[1])  # Y axis rotation

# Instance regular segments with rotation
inst_reg = nodes.new("GeometryNodeInstanceOnPoints")
inst_reg.location = (0, 400)
links.new(
    set_pos_reg.outputs["Geometry"], inst_reg.inputs["Points"]
)  # Use repositioned points!
links.new(obj_info_reg.outputs["Geometry"], inst_reg.inputs["Instance"])
links.new(rot_vec_reg.outputs["Vector"], inst_reg.inputs["Rotation"])

# === STEP 3: Instance key segment ===
mesh_line_key = nodes.new("GeometryNodeMeshLine")
mesh_line_key.location = (-1000, 0)
mesh_line_key.inputs["Count"].default_value = 1

# Move key point to origin too (though with count=1 it's already there, but let's be explicit)
set_pos_key = nodes.new("GeometryNodeSetPosition")
set_pos_key.location = (-800, 0)
links.new(mesh_line_key.outputs["Mesh"], set_pos_key.inputs["Geometry"])

origin_vec_key = nodes.new("ShaderNodeCombineXYZ")
origin_vec_key.location = (-800, -50)
origin_vec_key.inputs[0].default_value = 0.0
origin_vec_key.inputs[1].default_value = 0.0
origin_vec_key.inputs[2].default_value = 0.0
links.new(origin_vec_key.outputs["Vector"], set_pos_key.inputs["Position"])

# Key rotation = regular_count * regular_angle + key_angle/2 (around Y axis)
key_rot_angle = math.radians(regular_count * regular_angle_deg + key_angle_deg / 2.0)
rot_vec_key = nodes.new("ShaderNodeCombineXYZ")
rot_vec_key.location = (-200, 0)
rot_vec_key.inputs[1].default_value = key_rot_angle  # Y axis rotation

inst_key = nodes.new("GeometryNodeInstanceOnPoints")
inst_key.location = (0, 0)
links.new(
    set_pos_key.outputs["Geometry"], inst_key.inputs["Points"]
)  # Use repositioned points!
links.new(obj_info_key.outputs["Geometry"], inst_key.inputs["Instance"])
links.new(rot_vec_key.outputs["Vector"], inst_key.inputs["Rotation"])

# === STEP 4: Join segments into ring ===
join_ring = nodes.new("GeometryNodeJoinGeometry")
join_ring.location = (200, 200)
links.new(inst_reg.outputs["Instances"], join_ring.inputs["Geometry"])
links.new(inst_key.outputs["Instances"], join_ring.inputs["Geometry"])

realize_ring = nodes.new("GeometryNodeRealizeInstances")
realize_ring.location = (200, 200)
links.new(join_ring.outputs["Geometry"], realize_ring.inputs["Geometry"])

# === STEP 5: Instance rings along Y+ (forward) ===
mesh_line_y = nodes.new("GeometryNodeMeshLine")
mesh_line_y.location = (400, 400)
links.new(group_in.outputs[2], mesh_line_y.inputs["Count"])

index_y = nodes.new("GeometryNodeInputIndex")
index_y.location = (400, 300)

mul_spacing = nodes.new("ShaderNodeMath")
mul_spacing.operation = "MULTIPLY"
mul_spacing.location = (600, 300)
links.new(index_y.outputs["Index"], mul_spacing.inputs[0])
links.new(group_in.outputs[3], mul_spacing.inputs[1])

# Position at (0, Y, 0) - use Position not Offset to zero out X drift!
pos_y = nodes.new("ShaderNodeCombineXYZ")
pos_y.location = (800, 300)
pos_y.inputs[0].default_value = 0.0  # X = 0
pos_y.inputs[2].default_value = 0.0  # Z = 0
links.new(mul_spacing.outputs["Value"], pos_y.inputs[1])  # Y = spacing * index

set_pos_y = nodes.new("GeometryNodeSetPosition")
set_pos_y.location = (600, 400)
links.new(mesh_line_y.outputs["Mesh"], set_pos_y.inputs["Geometry"])
links.new(
    pos_y.outputs["Vector"], set_pos_y.inputs["Position"]
)  # Position, not Offset!

inst_rings = nodes.new("GeometryNodeInstanceOnPoints")
inst_rings.location = (800, 200)
links.new(set_pos_y.outputs["Geometry"], inst_rings.inputs["Points"])
links.new(realize_ring.outputs["Geometry"], inst_rings.inputs["Instance"])

# === STEP 6: Rotation jitter ===
rot_neg = nodes.new("ShaderNodeMath")
rot_neg.operation = "MULTIPLY"
rot_neg.location = (400, -100)
rot_neg.inputs[1].default_value = -1.0
links.new(group_in.outputs[4], rot_neg.inputs[0])

rand_rot = nodes.new("FunctionNodeRandomValue")
rand_rot.data_type = "FLOAT"
rand_rot.location = (600, -100)
links.new(rot_neg.outputs["Value"], rand_rot.inputs["Min"])
links.new(group_in.outputs[4], rand_rot.inputs["Max"])
links.new(group_in.outputs[6], rand_rot.inputs["Seed"])

deg2rad = nodes.new("ShaderNodeMath")
deg2rad.operation = "MULTIPLY"
deg2rad.location = (800, -100)
deg2rad.inputs[1].default_value = math.pi / 180.0
links.new(rand_rot.outputs["Value"], deg2rad.inputs[0])

rot_jitter_vec = nodes.new("ShaderNodeCombineXYZ")
rot_jitter_vec.location = (1000, -100)
links.new(deg2rad.outputs["Value"], rot_jitter_vec.inputs[1])  # Y axis rotation

rot_rings = nodes.new("GeometryNodeRotateInstances")
rot_rings.location = (1000, 200)
links.new(inst_rings.outputs["Instances"], rot_rings.inputs["Instances"])
links.new(rot_jitter_vec.outputs["Vector"], rot_rings.inputs["Rotation"])

# === STEP 7: Position jitter ===
pos_neg = nodes.new("ShaderNodeMath")
pos_neg.operation = "MULTIPLY"
pos_neg.location = (400, -200)
pos_neg.inputs[1].default_value = -1.0
links.new(group_in.outputs[5], pos_neg.inputs[0])

rand_pos = nodes.new("FunctionNodeRandomValue")
rand_pos.data_type = "FLOAT"
rand_pos.location = (600, -200)
links.new(pos_neg.outputs["Value"], rand_pos.inputs["Min"])
links.new(group_in.outputs[5], rand_pos.inputs["Max"])
links.new(group_in.outputs[6], rand_pos.inputs["Seed"])

pos_jitter_vec = nodes.new("ShaderNodeCombineXYZ")
pos_jitter_vec.location = (1000, -200)
links.new(rand_pos.outputs["Value"], pos_jitter_vec.inputs[1])  # Y axis

jitter_pos = nodes.new("GeometryNodeSetPosition")
jitter_pos.location = (1200, 200)
links.new(rot_rings.outputs["Instances"], jitter_pos.inputs["Geometry"])
links.new(pos_jitter_vec.outputs["Vector"], jitter_pos.inputs["Offset"])

# === Output ===
realize_final = nodes.new("GeometryNodeRealizeInstances")
realize_final.location = (1200, 100)
links.new(jitter_pos.outputs["Geometry"], realize_final.inputs["Geometry"])
links.new(realize_final.outputs["Geometry"], group_out.inputs["Geometry"])

# Set defaults
for socket in iface.items_tree:
    if socket.in_out == "INPUT":
        if socket.name == "Ring Count":
            socket.default_value = gn_ring_count
        elif socket.name == "Ring Spacing":
            socket.default_value = gn_ring_spacing
        elif socket.name == "Rot Jitter Deg":
            socket.default_value = gn_rot_jitter_deg
        elif socket.name == "Pos Jitter":
            socket.default_value = gn_pos_jitter
        elif socket.name == "Seed":
            socket.default_value = gn_seed

# --------------------------------------------------------
# Create controller
# --------------------------------------------------------

controller_mesh = bpy.data.meshes.new("TunnelController_Mesh")
bpy.ops.mesh.primitive_cube_add(size=0.1, location=(0, 0, 0))
temp = bpy.context.active_object
controller_mesh = temp.data.copy()
bpy.data.objects.remove(temp, do_unlink=True)

controller = bpy.data.objects.new("Tunnel Controller", controller_mesh)
link_to_tunnel_only(controller)

mod = controller.modifiers.new(name="TunnelProcedural", type="NODES")
mod.node_group = ng

# Set inputs
try:
    input_sockets = [s for s in ng.interface.items_tree if s.in_out == "INPUT"]
    mod[input_sockets[0].identifier] = seg_reg
    mod[input_sockets[1].identifier] = seg_key
    mod[input_sockets[2].identifier] = gn_ring_count
    mod[input_sockets[3].identifier] = gn_ring_spacing
    mod[input_sockets[4].identifier] = gn_rot_jitter_deg
    mod[input_sockets[5].identifier] = gn_pos_jitter
    mod[input_sockets[6].identifier] = gn_seed
    print("✓ Modifier inputs assigned!")
except Exception as e:
    print(f"⚠ Could not auto-assign: {e}")

# --------------------------------------------------------
# Done!
# --------------------------------------------------------

print(f"\n=== DONE ===")
print(f"\nTWEAKABLE OBJECTS:")
print(f"  {seg_reg.name} - Regular segment template")
print(f"  {seg_key.name} - Key segment template")
print(f"\nCUTTER OBJECTS (move/scale these to tweak booleans!):")
for c in bolt_cutters_reg + handle_cutters_reg:
    print(f"  {c.name}")
for c in bolt_cutters_key + handle_cutters_key:
    print(f"  {c.name}")
print(f"\nChanges to segments/cutters update the tunnel instantly!")
print(f"View result on: Tunnel Controller")
