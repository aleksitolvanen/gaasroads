class_name ShipExhaust
extends Node3D

# Swappable engine-exhaust rigs, for A/B testing in game: E cycles styles,
# the status overlay names the active one. Styles:
#   Classic       - the original rig: two CPUParticles layers of billboard
#                   spheres, very short lifetimes (kept as the baseline)
#   Puffs         - same two-layer idea, but soft radial-gradient quads with
#                   real lifetimes and low damping: a tapering smoke trail
#   Streaks       - thin velocity-aligned slivers: arcade motion streaks
#   Cones         - no particles: nested translucent flame cones per nozzle
#                   whose length tracks throttle (plume doubles as a gauge)
#   Cones+Streaks - the cones with a sparse streak overlay

enum { STYLE_CLASSIC, STYLE_PUFFS, STYLE_STREAKS, STYLE_CONES, STYLE_CONES_STREAKS, STYLE_COUNT }
const STYLE_NAMES := ["Classic", "Puffs", "Streaks", "Cones", "Cones+Streaks"]

const NOZZLES := [Vector3(-0.24, -0.02, 0.6), Vector3(0.24, -0.02, 0.6)]

var style := STYLE_CLASSIC
var _emitters: Array[CPUParticles3D] = []
var _cone_holders: Array[Node3D] = []
var _cone_mats: Array[StandardMaterial3D] = []
var _cone_base_alphas: Array[float] = []

static func create(p_style: int) -> ShipExhaust:
	var e := ShipExhaust.new()
	e.style = p_style
	match p_style:
		STYLE_PUFFS:
			e._build_puffs()
		STYLE_STREAKS:
			e._build_streaks(false)
		STYLE_CONES:
			e._build_cones()
		STYLE_CONES_STREAKS:
			e._build_cones()
			e._build_streaks(true)
		_:
			e._build_classic()
	return e

# Called from ship._physics_process with throttle fraction 0..1
func update(speed_t: float):
	var has_thrust := speed_t > 0.05
	for em in _emitters:
		em.emitting = has_thrust
	match style:
		STYLE_CLASSIC:
			_emitters[0].initial_velocity_min = lerpf(1.0, 4.0, speed_t)
			_emitters[0].initial_velocity_max = lerpf(2.0, 6.0, speed_t)
			_emitters[1].initial_velocity_min = lerpf(0.8, 3.0, speed_t)
			_emitters[1].initial_velocity_max = lerpf(1.5, 4.5, speed_t)
			_emitters[1].spread = lerpf(25.0, 40.0, speed_t)
		STYLE_PUFFS:
			for em in _emitters:
				em.initial_velocity_min = lerpf(2.0, 7.0, speed_t)
				em.initial_velocity_max = lerpf(3.5, 11.0, speed_t)
		STYLE_STREAKS, STYLE_CONES, STYLE_CONES_STREAKS:
			for em in _emitters:
				em.initial_velocity_min = lerpf(4.0, 14.0, speed_t)
				em.initial_velocity_max = lerpf(7.0, 20.0, speed_t)
	if not _cone_holders.is_empty():
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
	for em in _emitters:
		em.emitting = false
	for h in _cone_holders:
		h.visible = false

# ---------------- style builders ----------------

func _build_classic():
	# The original rig, verbatim: dense short cone of billboard spheres
	var core := CPUParticles3D.new()
	core.position = Vector3(0, 0, 0.56)
	core.amount = 45
	core.lifetime = 0.06
	core.direction = Vector3(0, 0, 1)
	core.spread = 20.0
	core.initial_velocity_min = 2.0
	core.initial_velocity_max = 4.0
	core.gravity = Vector3.ZERO
	core.damping_min = 25.0
	core.damping_max = 40.0
	core.scale_amount_min = 0.8
	core.scale_amount_max = 1.2
	var core_curve := Curve.new()
	core_curve.add_point(Vector2(0, 1.0))
	core_curve.add_point(Vector2(0.15, 0.6))
	core_curve.add_point(Vector2(0.4, 0.2))
	core_curve.add_point(Vector2(1.0, 0.0))
	core.scale_amount_curve = core_curve
	var core_grad := Gradient.new()
	core_grad.set_color(0, Color(0.9, 0.97, 1.0, 0.9))
	core_grad.add_point(0.3, Color(0.5, 0.8, 1.0, 0.6))
	core_grad.set_color(1, Color(0.2, 0.5, 0.9, 0.0))
	core.color_ramp = core_grad
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.1
	core_mesh.height = 0.2
	core_mesh.material = _glow_mat(Color(0.8, 0.95, 1.0), Color(0.6, 0.85, 1.0), 5.0, false, true)
	core.mesh = core_mesh
	add_child(core)
	_emitters.append(core)

	var outer := CPUParticles3D.new()
	outer.position = Vector3(0, 0, 0.56)
	outer.amount = 35
	outer.lifetime = 0.08
	outer.direction = Vector3(0, 0, 1)
	outer.spread = 35.0
	outer.initial_velocity_min = 1.5
	outer.initial_velocity_max = 3.0
	outer.gravity = Vector3.ZERO
	outer.damping_min = 20.0
	outer.damping_max = 35.0
	outer.scale_amount_min = 1.0
	outer.scale_amount_max = 1.8
	var outer_curve := Curve.new()
	outer_curve.add_point(Vector2(0, 1.0))
	outer_curve.add_point(Vector2(0.1, 0.5))
	outer_curve.add_point(Vector2(0.3, 0.15))
	outer_curve.add_point(Vector2(1.0, 0.0))
	outer.scale_amount_curve = outer_curve
	var outer_grad := Gradient.new()
	outer_grad.set_color(0, Color(0.25, 0.55, 1.0, 0.5))
	outer_grad.add_point(0.4, Color(0.1, 0.3, 0.8, 0.15))
	outer_grad.set_color(1, Color(0.05, 0.15, 0.5, 0.0))
	outer.color_ramp = outer_grad
	var outer_mesh := SphereMesh.new()
	outer_mesh.radius = 0.12
	outer_mesh.height = 0.24
	outer_mesh.material = _glow_mat(Color(0.2, 0.5, 1.0), Color(0.15, 0.4, 0.9), 2.5, false, true)
	outer.mesh = outer_mesh
	add_child(outer)
	_emitters.append(outer)

func _build_puffs():
	# Soft radial-gradient quads with real lifetimes: a tapering trail
	var core := _puff_emitter(0.10, 30, 0.22, 14.0, 6.0)
	var core_grad := Gradient.new()
	core_grad.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	core_grad.add_point(0.25, Color(0.55, 0.85, 1.0, 0.55))
	core_grad.set_color(1, Color(0.15, 0.4, 0.9, 0.0))
	core.color_ramp = core_grad
	var outer := _puff_emitter(0.17, 22, 0.34, 26.0, 3.0)
	var outer_grad := Gradient.new()
	outer_grad.set_color(0, Color(0.35, 0.65, 1.0, 0.45))
	outer_grad.add_point(0.4, Color(0.15, 0.35, 0.85, 0.2))
	outer_grad.set_color(1, Color(0.05, 0.15, 0.5, 0.0))
	outer.color_ramp = outer_grad

func _puff_emitter(size: float, amount: int, lifetime: float, spread: float, damping: float) -> CPUParticles3D:
	var em := CPUParticles3D.new()
	em.position = Vector3(0, 0, 0.6)
	em.amount = amount
	em.lifetime = lifetime
	em.direction = Vector3(0, 0, 1)
	em.spread = spread
	em.gravity = Vector3.ZERO
	em.damping_min = damping
	em.damping_max = damping * 1.6
	em.scale_amount_min = 0.7
	em.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.9))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	em.scale_amount_curve = curve
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size * 2.0, size * 2.0)
	var mat := _glow_mat(Color.WHITE, Color(0.6, 0.85, 1.0), 3.0, true, true)
	mat.albedo_texture = _puff_texture()
	mesh.material = mat
	em.mesh = mesh
	add_child(em)
	_emitters.append(em)
	return em

func _build_streaks(sparse: bool):
	# Thin slivers aligned to their velocity: motion streaks
	var em := CPUParticles3D.new()
	em.position = Vector3(0, 0, 0.62)
	em.amount = 10 if sparse else 22
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
	_emitters.append(em)

func _build_cones():
	# Nested translucent flame cones per nozzle; update() stretches them
	# with throttle and flickers alpha - the plume reads as a speed gauge
	for nozzle in NOZZLES:
		var holder := Node3D.new()
		holder.position = nozzle
		add_child(holder)
		_cone_holders.append(holder)
		_add_cone(holder, 0.055, 0.55, Color(1.0, 1.0, 1.0), Color(0.7, 0.9, 1.0), 4.0, 0.85)
		_add_cone(holder, 0.09, 0.75, Color(0.4, 0.75, 1.0), Color(0.25, 0.6, 1.0), 2.5, 0.4)
		_add_cone(holder, 0.13, 1.0, Color(0.15, 0.35, 0.95), Color(0.1, 0.25, 0.85), 1.5, 0.18)

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

# ---------------- shared helpers ----------------

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
	# Particle color ramps tint via vertex COLOR - without this flag the
	# gradient is ignored (the Classic rig's ramps never actually applied)
	mat.vertex_color_use_as_albedo = vertex_color
	return mat

func _puff_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t
