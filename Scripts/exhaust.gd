class_name ShipExhaust
extends Node3D

# Engine exhaust: nested translucent flame cones per nozzle whose length
# tracks throttle - the plume doubles as a speed gauge - plus a sparse
# overlay of velocity-aligned streaks for motion sparkle.

const NOZZLES := [Vector3(-0.24, -0.02, 0.6), Vector3(0.24, -0.02, 0.6)]

var _streaks: CPUParticles3D
var _cone_holders: Array[Node3D] = []
var _cone_mats: Array[StandardMaterial3D] = []
var _cone_base_alphas: Array[float] = []

func _init():
	for nozzle in NOZZLES:
		var holder := Node3D.new()
		holder.position = nozzle
		add_child(holder)
		_cone_holders.append(holder)
		_add_cone(holder, 0.055, 0.55, Color(1.0, 1.0, 1.0), Color(0.7, 0.9, 1.0), 4.0, 0.85)
		_add_cone(holder, 0.09, 0.75, Color(0.4, 0.75, 1.0), Color(0.25, 0.6, 1.0), 2.5, 0.4)
		_add_cone(holder, 0.13, 1.0, Color(0.15, 0.35, 0.95), Color(0.1, 0.25, 0.85), 1.5, 0.18)
	_build_streaks()

# Called from ship._physics_process with throttle fraction 0..1
func update(speed_t: float):
	_streaks.emitting = speed_t > 0.05
	_streaks.initial_velocity_min = lerpf(4.0, 14.0, speed_t)
	_streaks.initial_velocity_max = lerpf(7.0, 20.0, speed_t)
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
	_streaks.emitting = false
	for h in _cone_holders:
		h.visible = false

func _add_cone(holder: Node3D, radius: float, length: float, albedo: Color, emission: Color, energy: float, alpha: float):
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	var mat := _glow_mat(albedo, emission, energy, false, false)
	mat.albedo_color.a = alpha
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

func _build_streaks():
	var em := CPUParticles3D.new()
	em.position = Vector3(0, 0, 0.62)
	em.amount = 10
	em.lifetime = 0.22
	em.direction = Vector3(0, 0, 1)
	em.spread = 9.0
	em.gravity = Vector3.ZERO
	em.particle_flag_align_y = true
	em.scale_amount_min = 0.6
	em.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(0.6, 0.7))
	curve.add_point(Vector2(1.0, 0.0))
	em.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.97, 1.0, 0.9))
	grad.add_point(0.4, Color(0.4, 0.75, 1.0, 0.5))
	grad.set_color(1, Color(0.1, 0.3, 0.9, 0.0))
	em.color_ramp = grad
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.4, 0.035)
	mesh.material = _glow_mat(Color(0.8, 0.95, 1.0), Color(0.5, 0.8, 1.0), 4.0, true, false)
	em.mesh = mesh
	add_child(em)
	_streaks = em

func _glow_mat(albedo: Color, emission: Color, energy: float, vertex_color: bool, billboard: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Particle color ramps tint via vertex COLOR
	mat.vertex_color_use_as_albedo = vertex_color
	return mat
