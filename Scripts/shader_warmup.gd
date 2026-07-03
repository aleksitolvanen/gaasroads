extends Node

# Holds one material per shader feature-combo used by the game, alive for the
# whole session. BaseMaterial3D shares compiled shaders per feature-combo, so
# keeping these referenced means the GL programs compiled for them survive
# scene changes - without this, every round recompiles them at first draw,
# which stalls the frame on WebGL. build_rig() returns sub-pixel geometry that
# draws every variant once, shown behind the GET READY gate.

var _materials: Array[StandardMaterial3D] = []
var _particle_mat: StandardMaterial3D

func _ready():
	var shaded := StandardMaterial3D.new()  # tiles, tunnel walls, engine glow
	shaded.emission_enabled = true
	shaded.emission = Color(0.1, 0.1, 0.2)
	_materials.append(shaded)

	var plain := StandardMaterial3D.new()  # ship body, wings, nose
	_materials.append(plain)

	var glow := StandardMaterial3D.new()  # lasers, trails, rings, suns, hulls
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = Color(0.2, 0.2, 0.4)
	_materials.append(glow)

	var glow_alpha := StandardMaterial3D.new()  # haze, coronas, auras, wisps
	glow_alpha.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_alpha.emission_enabled = true
	glow_alpha.emission = Color(0.2, 0.2, 0.4)
	glow_alpha.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials.append(glow_alpha)

	var glow_billboard := StandardMaterial3D.new()  # exhaust particles, ring dust
	glow_billboard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_billboard.emission_enabled = true
	glow_billboard.emission = Color(0.2, 0.2, 0.4)
	glow_billboard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_billboard.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_particle_mat = glow_billboard
	_materials.append(glow_billboard)

	var star := StandardMaterial3D.new()  # star field quads
	star.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_materials.append(star)

	var textured := StandardMaterial3D.new()  # background image quad
	textured.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	textured.albedo_texture = GameState.background_texture
	textured.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials.append(textured)

func build_rig() -> Node3D:
	var rig := Node3D.new()
	for i in _materials.size():
		var m := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.001, 0.001)
		quad.material = _materials[i]
		m.mesh = quad
		m.position = Vector3(0.01 * (i - 3), 0, -2)
		rig.add_child(m)

	# CPUParticles render through the instancing shader variant - draw that too
	var parts := CPUParticles3D.new()
	parts.amount = 4
	parts.lifetime = 0.5
	var pmesh := QuadMesh.new()
	pmesh.size = Vector2(0.001, 0.001)
	pmesh.material = _particle_mat
	parts.mesh = pmesh
	parts.position = Vector3(0, 0, -2)
	rig.add_child(parts)
	return rig
