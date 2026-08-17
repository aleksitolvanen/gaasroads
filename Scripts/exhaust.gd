class_name ShipExhaust
extends Node3D

# Engine exhaust: nested translucent flame cones per nozzle whose length
# tracks throttle - the plume doubles as a speed gauge.

const NOZZLES := [Vector3(-0.24, -0.02, 0.6), Vector3(0.24, -0.02, 0.6)]

var _cone_holders: Array[Node3D] = []
var _cone_mats: Array[StandardMaterial3D] = []
var _cone_base_alphas: Array[float] = []

func _init(nozzles: Array = NOZZLES):
	for nozzle in nozzles:
		var holder := Node3D.new()
		holder.position = nozzle
		add_child(holder)
		_cone_holders.append(holder)
		_add_cone(holder, 0.055, 0.55, Color(1.0, 1.0, 1.0), Color(0.7, 0.9, 1.0), 4.0, 0.85)
		_add_cone(holder, 0.09, 0.75, Color(0.4, 0.75, 1.0), Color(0.25, 0.6, 1.0), 2.5, 0.4)
		_add_cone(holder, 0.13, 1.0, Color(0.15, 0.35, 0.95), Color(0.1, 0.25, 0.85), 1.5, 0.18)

# Called from ship._physics_process with throttle fraction 0..1
func update(speed_t: float):
	var flicker := randf_range(-0.07, 0.07)
	var length := lerpf(0.45, 2.6, speed_t) * (1.0 + flicker)
	var vis := speed_t > 0.03
	for h in _cone_holders:
		h.visible = vis
		h.scale = Vector3(1.0 + flicker * 0.3, 1.0 + flicker * 0.3, length)
	for i in _cone_mats.size():
		var a: float = _cone_base_alphas[i] * lerpf(0.55, 1.0, speed_t) * (1.0 + flicker * 2.0)
		_cone_mats[i].albedo_color.a = clampf(a, 0.0, 1.0)

# Explosion: kill all output immediately
func shut_down():
	for h in _cone_holders:
		h.visible = false

func _add_cone(holder: Node3D, radius: float, length: float, albedo: Color, emission: Color, energy: float, alpha: float):
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = albedo
	mat.albedo_color.a = alpha
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	var cone := MeshInstance3D.new()
	cone.mesh = mesh
	# +90deg about X maps the cone's +Y apex to +Z: base at the nozzle,
	# tip trailing behind the ship
	cone.rotation_degrees = Vector3(90, 0, 0)
	cone.position = Vector3(0, 0, length / 2.0)
	holder.add_child(cone)
	_cone_mats.append(mat)
	_cone_base_alphas.append(alpha)
