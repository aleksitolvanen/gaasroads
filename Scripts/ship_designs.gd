class_name ShipDesigns

# Swappable procedural ship hulls, for A/B testing in game: E cycles styles,
# the status overlay names the active one. Every design builds from primitive
# meshes via add_part(mesh, pos, rot_deg, scl) -> MeshInstance3D and returns
# {"engine_mat": StandardMaterial3D, "nozzles": Array[Vector3]} - the engine
# material is throttle-tinted by ship.gd, the nozzle positions anchor the
# exhaust cones. Nose points -Z, rear +Z; keep the visual roughly inside the
# collision box (0.7 wide, 0.3 tall, 1.0 long, centered at the origin).

enum { STYLE_CLASSIC, STYLE_RAPTOR, STYLE_MANTA, STYLE_HAMMER, STYLE_COMET, STYLE_COUNT }
const STYLE_NAMES := ["Classic", "Raptor", "Manta", "Hammer", "Comet"]

static func build(style: int, p: Callable) -> Dictionary:
	match style:
		STYLE_RAPTOR:
			return _build_raptor(p)
		STYLE_MANTA:
			return _build_manta(p)
		STYLE_HAMMER:
			return _build_hammer(p)
		STYLE_COMET:
			return _build_comet(p)
		_:
			return _build_classic(p)

static func _mat(albedo: Color, metallic: float, roughness: float, emission := Color(0, 0, 0), energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m

# The nozzle material ship.gd animates with throttle (dark at rest,
# glowing hot at speed) - every design routes its nozzles through one
static func _engine_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.05)
	m.emission_enabled = true
	m.emission = Color(0, 0, 0)
	m.emission_energy_multiplier = 0.0
	return m

static func _build_classic(p: Callable) -> Dictionary:
	var body_mat := _mat(Color(0.72, 0.12, 0.12), 0.35, 0.45)
	var accent_mat := _mat(Color(0.85, 0.85, 0.9), 0.5, 0.35)
	var dark_mat := _mat(Color(0.16, 0.16, 0.2), 0.6, 0.5)
	var canopy_mat := _mat(Color(0.2, 0.45, 0.6), 0.8, 0.15, Color(0.1, 0.3, 0.45), 0.6)
	var engine := _engine_mat()

	# Fuselage: flattened capsule, wide and low
	var hull := CapsuleMesh.new()
	hull.radius = 0.16
	hull.height = 1.05
	hull.material = body_mat
	p.call(hull, Vector3(0, 0, 0.02), Vector3(90, 0, 0), Vector3(1.5, 1.0, 0.75))

	# Nose cone
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.13
	nose.height = 0.38
	nose.radial_segments = 12
	nose.material = accent_mat
	p.call(nose, Vector3(0, -0.01, -0.62), Vector3(-90, 0, 0), Vector3(1.5, 1.0, 0.7))

	# Cockpit canopy
	var canopy := SphereMesh.new()
	canopy.radius = 0.11
	canopy.height = 0.22
	canopy.material = canopy_mat
	p.call(canopy, Vector3(0, 0.12, -0.16), Vector3.ZERO, Vector3(1.1, 0.7, 1.7))

	# Swept wings with tip fins
	var wing := BoxMesh.new()
	wing.size = Vector3(0.5, 0.045, 0.34)
	wing.material = body_mat
	p.call(wing, Vector3(-0.42, -0.03, 0.16), Vector3(0, -18, -4), Vector3.ONE)
	p.call(wing, Vector3(0.42, -0.03, 0.16), Vector3(0, 18, 4), Vector3.ONE)
	var fin := BoxMesh.new()
	fin.size = Vector3(0.045, 0.15, 0.22)
	fin.material = accent_mat
	p.call(fin, Vector3(-0.62, 0.03, 0.24), Vector3(0, -18, 0), Vector3.ONE)
	p.call(fin, Vector3(0.62, 0.03, 0.24), Vector3(0, 18, 0), Vector3.ONE)

	# Twin engine pods with glow nozzles
	var pod := CylinderMesh.new()
	pod.top_radius = 0.085
	pod.bottom_radius = 0.07
	pod.height = 0.45
	pod.radial_segments = 10
	pod.material = dark_mat
	p.call(pod, Vector3(-0.24, -0.02, 0.36), Vector3(90, 0, 0), Vector3.ONE)
	p.call(pod, Vector3(0.24, -0.02, 0.36), Vector3(90, 0, 0), Vector3.ONE)
	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.062
	nozzle.bottom_radius = 0.062
	nozzle.height = 0.05
	nozzle.radial_segments = 10
	nozzle.material = engine
	p.call(nozzle, Vector3(-0.24, -0.02, 0.6), Vector3(90, 0, 0), Vector3.ONE)
	p.call(nozzle, Vector3(0.24, -0.02, 0.6), Vector3(90, 0, 0), Vector3.ONE)

	# Dorsal fin, apex leaning back
	var dfin := PrismMesh.new()
	dfin.size = Vector3(0.34, 0.2, 0.04)
	dfin.left_to_right = 0.8
	dfin.material = body_mat
	p.call(dfin, Vector3(0, 0.17, 0.3), Vector3(0, -90, 0), Vector3.ONE)

	return {"engine_mat": engine, "nozzles": [Vector3(-0.24, -0.02, 0.6), Vector3(0.24, -0.02, 0.6)]}

static func _build_raptor(p: Callable) -> Dictionary:
	var hull_mat := _mat(Color(0.25, 0.27, 0.3), 0.85, 0.35)
	var accent_mat := _mat(Color(0.88, 0.87, 0.84), 0.55, 0.4)
	var glow_mat := _mat(Color(0.04, 0.1, 0.12), 0.3, 0.5, Color(0.25, 0.85, 1.0), 2.6)
	var glass_mat := _mat(Color(0.05, 0.07, 0.1), 0.7, 0.12)
	var engine := _engine_mat()

	var blade := PrismMesh.new()
	blade.size = Vector3(1.3, 1.23, 0.05)
	blade.left_to_right = 0.5
	blade.material = hull_mat
	p.call(blade, Vector3(0, 0, -0.065), Vector3(-90, 0, 0), Vector3.ONE)

	var spine := PrismMesh.new()
	spine.size = Vector3(0.4, 1.15, 0.16)
	spine.left_to_right = 0.5
	spine.material = hull_mat
	p.call(spine, Vector3(0, 0.09, -0.02), Vector3(-90, 0, 0), Vector3.ONE)

	var keel := PrismMesh.new()
	keel.size = Vector3(0.26, 0.8, 0.12)
	keel.left_to_right = 0.5
	keel.material = hull_mat
	p.call(keel, Vector3(0, -0.075, 0.08), Vector3(-90, 0, 0), Vector3.ONE)

	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.05
	spike.height = 0.28
	spike.radial_segments = 8
	spike.material = accent_mat
	p.call(spike, Vector3(0, 0.03, -0.58), Vector3(-90, 0, 0), Vector3.ONE)

	var canopy := BoxMesh.new()
	canopy.size = Vector3(0.17, 0.05, 0.36)
	canopy.material = glass_mat
	p.call(canopy, Vector3(0, 0.175, -0.1), Vector3(-6, 0, 0), Vector3.ONE)

	var edge := BoxMesh.new()
	edge.size = Vector3(0.05, 0.03, 1.28)
	edge.material = accent_mat
	p.call(edge, Vector3(0.3, 0.02, -0.05), Vector3(0, 28, 0), Vector3.ONE)
	p.call(edge, Vector3(-0.3, 0.02, -0.05), Vector3(0, -28, 0), Vector3.ONE)

	var strip := BoxMesh.new()
	strip.size = Vector3(0.035, 0.028, 1.1)
	strip.material = glow_mat
	p.call(strip, Vector3(0.25, 0.028, -0.025), Vector3(0, 28, 0), Vector3.ONE)
	p.call(strip, Vector3(-0.25, 0.028, -0.025), Vector3(0, -28, 0), Vector3.ONE)

	var tail_strip := BoxMesh.new()
	tail_strip.size = Vector3(0.42, 0.024, 0.035)
	tail_strip.material = glow_mat
	p.call(tail_strip, Vector3(0.4, 0.028, 0.505), Vector3.ZERO, Vector3.ONE)
	p.call(tail_strip, Vector3(-0.4, 0.028, 0.505), Vector3.ZERO, Vector3.ONE)

	var fin := PrismMesh.new()
	fin.size = Vector3(0.34, 0.22, 0.03)
	fin.left_to_right = 0.12
	fin.material = hull_mat
	p.call(fin, Vector3(0.155, 0.24, 0.38), Vector3(22, 90, 0), Vector3.ONE)
	p.call(fin, Vector3(-0.155, 0.24, 0.38), Vector3(-22, 90, 0), Vector3.ONE)

	var pod := BoxMesh.new()
	pod.size = Vector3(0.15, 0.11, 0.32)
	pod.material = hull_mat
	p.call(pod, Vector3(0.16, -0.04, 0.41), Vector3.ZERO, Vector3.ONE)
	p.call(pod, Vector3(-0.16, -0.04, 0.41), Vector3.ZERO, Vector3.ONE)

	var collar := TorusMesh.new()
	collar.inner_radius = 0.04
	collar.outer_radius = 0.08
	collar.material = accent_mat
	p.call(collar, Vector3(0.16, -0.04, 0.575), Vector3(90, 0, 0), Vector3.ONE)
	p.call(collar, Vector3(-0.16, -0.04, 0.575), Vector3(90, 0, 0), Vector3.ONE)

	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.06
	nozzle.bottom_radius = 0.05
	nozzle.height = 0.07
	nozzle.radial_segments = 10
	nozzle.material = engine
	p.call(nozzle, Vector3(0.16, -0.04, 0.605), Vector3(90, 0, 0), Vector3.ONE)
	p.call(nozzle, Vector3(-0.16, -0.04, 0.605), Vector3(90, 0, 0), Vector3.ONE)

	return {"engine_mat": engine, "nozzles": [Vector3(-0.16, -0.04, 0.605), Vector3(0.16, -0.04, 0.605)]}

static func _build_manta(p: Callable) -> Dictionary:
	var hull_mat := _mat(Color(0.28, 0.18, 0.42), 0.15, 0.3)
	var teal_mat := _mat(Color(0.09, 0.22, 0.26), 0.2, 0.35)
	var glow_mat := _mat(Color(0.2, 0.7, 0.65), 0.0, 0.4, Color(0.1, 0.9, 0.8), 3.0)
	var canopy_mat := _mat(Color(0.05, 0.1, 0.14), 0.1, 0.08, Color(0.1, 0.9, 0.8), 0.5)
	var engine := _engine_mat()

	# Central body: wide squashed sphere
	var body := SphereMesh.new()
	body.radius = 0.32
	body.height = 0.3
	body.material = hull_mat
	p.call(body, Vector3(0, 0.06, 0.02), Vector3.ZERO, Vector3(1.1, 1.0, 1.5))

	# Nose dome blending into the body front
	var nose := SphereMesh.new()
	nose.radius = 0.22
	nose.height = 0.15
	nose.material = hull_mat
	p.call(nose, Vector3(0, 0.03, -0.42), Vector3.ZERO, Vector3(1.25, 1.0, 1.35))

	# Teal underbelly mass
	var belly := SphereMesh.new()
	belly.radius = 0.26
	belly.height = 0.2
	belly.material = teal_mat
	p.call(belly, Vector3(0, 0.0, 0.04), Vector3.ZERO, Vector3(1.05, 1.0, 1.5))

	# Wing arc: flattened ellipsoids, swept back, tips drooped
	var wing := SphereMesh.new()
	wing.radius = 0.3
	wing.height = 0.11
	wing.material = hull_mat
	p.call(wing, Vector3(0.33, 0.045, 0.06), Vector3(0, -10, -7), Vector3(1.05, 1.0, 0.8))
	p.call(wing, Vector3(-0.33, 0.045, 0.06), Vector3(0, 10, 7), Vector3(1.05, 1.0, 0.8))

	# Drooped wingtip pods
	var tip_pod := SphereMesh.new()
	tip_pod.radius = 0.05
	tip_pod.height = 0.075
	tip_pod.material = teal_mat
	p.call(tip_pod, Vector3(0.59, 0.0, 0.08), Vector3.ZERO, Vector3(1.0, 1.0, 1.8))
	p.call(tip_pod, Vector3(-0.59, 0.0, 0.08), Vector3.ZERO, Vector3(1.0, 1.0, 1.8))

	# Raised smooth cockpit dome (dark glass, faint inner glow)
	var dome := SphereMesh.new()
	dome.radius = 0.13
	dome.height = 0.2
	dome.material = canopy_mat
	p.call(dome, Vector3(0, 0.16, -0.14), Vector3.ZERO, Vector3(1.0, 1.0, 1.35))

	# Bioluminescent gill ring half-sunk behind the cockpit
	var gill := TorusMesh.new()
	gill.inner_radius = 0.14
	gill.outer_radius = 0.18
	gill.material = glow_mat
	p.call(gill, Vector3(0, 0.08, 0.16), Vector3(90, 0, 0), Vector3(1.3, 1.0, 1.0))

	# Tapering tail spine reaching back between the nozzles
	var spine := CylinderMesh.new()
	spine.top_radius = 0.0
	spine.bottom_radius = 0.055
	spine.height = 0.55
	spine.radial_segments = 12
	spine.material = hull_mat
	p.call(spine, Vector3(0, 0.08, 0.4), Vector3(90, 0, 0), Vector3.ONE)

	# Lure bulb capping the tail spine
	var tail_bulb := SphereMesh.new()
	tail_bulb.radius = 0.03
	tail_bulb.height = 0.06
	tail_bulb.material = glow_mat
	p.call(tail_bulb, Vector3(0, 0.08, 0.64), Vector3.ZERO, Vector3.ONE)

	# Twin engine pods flowing out of the trailing edge
	var pod := SphereMesh.new()
	pod.radius = 0.12
	pod.height = 0.17
	pod.material = teal_mat
	p.call(pod, Vector3(0.22, 0.0, 0.33), Vector3.ZERO, Vector3(0.85, 1.0, 1.75))
	p.call(pod, Vector3(-0.22, 0.0, 0.33), Vector3.ZERO, Vector3(0.85, 1.0, 1.75))

	# Nozzles
	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.08
	nozzle.bottom_radius = 0.08
	nozzle.height = 0.06
	nozzle.radial_segments = 12
	nozzle.material = engine
	p.call(nozzle, Vector3(0.22, 0.0, 0.55), Vector3(90, 0, 0), Vector3.ONE)
	p.call(nozzle, Vector3(-0.22, 0.0, 0.55), Vector3(90, 0, 0), Vector3.ONE)

	# Anglerfish lure line: glow dots along the wing leading edges
	var lure := SphereMesh.new()
	lure.radius = 0.028
	lure.height = 0.056
	lure.material = glow_mat
	p.call(lure, Vector3(0.15, 0.11, -0.36), Vector3.ZERO, Vector3.ONE)
	p.call(lure, Vector3(-0.15, 0.11, -0.36), Vector3.ZERO, Vector3.ONE)
	p.call(lure, Vector3(0.33, 0.065, -0.15), Vector3.ZERO, Vector3.ONE)
	p.call(lure, Vector3(-0.33, 0.065, -0.15), Vector3.ZERO, Vector3.ONE)
	p.call(lure, Vector3(0.48, 0.05, -0.04), Vector3.ZERO, Vector3.ONE)
	p.call(lure, Vector3(-0.48, 0.05, -0.04), Vector3.ZERO, Vector3.ONE)

	return {"engine_mat": engine, "nozzles": [Vector3(-0.22, 0.0, 0.55), Vector3(0.22, 0.0, 0.55)]}

static func _build_hammer(p: Callable) -> Dictionary:
	var hull_mat := _mat(Color(0.85, 0.45, 0.1), 0.3, 0.6)
	var steel_mat := _mat(Color(0.55, 0.57, 0.6), 0.7, 0.4)
	var dark_mat := _mat(Color(0.07, 0.07, 0.08), 0.25, 0.8)
	var white_mat := _mat(Color(0.9, 0.9, 0.87), 0.2, 0.55)
	var visor_mat := _mat(Color(0.2, 0.12, 0.05), 0.1, 0.4, Color(1.0, 0.65, 0.2), 1.5)
	var engine := _engine_mat()

	var hull := BoxMesh.new()
	hull.size = Vector3(0.62, 0.26, 0.92)
	hull.material = hull_mat
	p.call(hull, Vector3(0, 0, 0.08), Vector3.ZERO, Vector3.ONE)

	var upper := BoxMesh.new()
	upper.size = Vector3(0.46, 0.15, 0.68)
	upper.material = hull_mat
	p.call(upper, Vector3(0, 0.155, 0.1), Vector3.ZERO, Vector3.ONE)

	var prow := BoxMesh.new()
	prow.size = Vector3(1.3, 0.22, 0.24)
	prow.material = hull_mat
	p.call(prow, Vector3(0, 0, -0.6), Vector3.ZERO, Vector3.ONE)

	var prow_face := BoxMesh.new()
	prow_face.size = Vector3(1.14, 0.15, 0.05)
	prow_face.material = dark_mat
	p.call(prow_face, Vector3(0, 0, -0.71), Vector3.ZERO, Vector3.ONE)

	var neck := BoxMesh.new()
	neck.size = Vector3(0.36, 0.2, 0.34)
	neck.material = steel_mat
	p.call(neck, Vector3(0, 0, -0.42), Vector3.ZERO, Vector3.ONE)

	var pod := BoxMesh.new()
	pod.size = Vector3(0.24, 0.2, 0.56)
	pod.material = steel_mat
	p.call(pod, Vector3(-0.43, -0.02, 0.14), Vector3.ZERO, Vector3.ONE)
	p.call(pod, Vector3(0.43, -0.02, 0.14), Vector3.ZERO, Vector3.ONE)

	var grille := BoxMesh.new()
	grille.size = Vector3(0.2, 0.14, 0.06)
	grille.material = dark_mat
	p.call(grille, Vector3(-0.43, -0.02, -0.13), Vector3.ZERO, Vector3.ONE)
	p.call(grille, Vector3(0.43, -0.02, -0.13), Vector3.ZERO, Vector3.ONE)

	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.024
	pipe.bottom_radius = 0.024
	pipe.height = 0.66
	pipe.radial_segments = 8
	pipe.material = steel_mat
	p.call(pipe, Vector3(-0.17, 0.245, 0.09), Vector3(90, 0, 0), Vector3.ONE)
	p.call(pipe, Vector3(0.17, 0.245, 0.09), Vector3(90, 0, 0), Vector3.ONE)

	var visor := BoxMesh.new()
	visor.size = Vector3(0.32, 0.05, 0.06)
	visor.material = visor_mat
	p.call(visor, Vector3(0, 0.16, -0.25), Vector3.ZERO, Vector3.ONE)

	var mast := CylinderMesh.new()
	mast.top_radius = 0.012
	mast.bottom_radius = 0.012
	mast.height = 0.11
	mast.radial_segments = 6
	mast.material = steel_mat
	p.call(mast, Vector3(-0.16, 0.285, 0.32), Vector3.ZERO, Vector3.ONE)

	var tip := SphereMesh.new()
	tip.radius = 0.016
	tip.height = 0.032
	tip.material = white_mat
	p.call(tip, Vector3(-0.16, 0.33, 0.32), Vector3.ZERO, Vector3.ONE)

	var tank := CapsuleMesh.new()
	tank.radius = 0.055
	tank.height = 0.4
	tank.material = steel_mat
	p.call(tank, Vector3(0.43, 0.11, 0.18), Vector3(90, 0, 0), Vector3.ONE)

	var prow_stripe := BoxMesh.new()
	prow_stripe.size = Vector3(0.12, 0.014, 0.2)
	prow_stripe.material = white_mat
	p.call(prow_stripe, Vector3(-0.3, 0.115, -0.6), Vector3.ZERO, Vector3.ONE)
	p.call(prow_stripe, Vector3(0.3, 0.115, -0.6), Vector3.ZERO, Vector3.ONE)

	var hull_stripe := BoxMesh.new()
	hull_stripe.size = Vector3(0.47, 0.014, 0.07)
	hull_stripe.material = dark_mat
	p.call(hull_stripe, Vector3(0, 0.235, 0.3), Vector3.ZERO, Vector3.ONE)

	var housing := BoxMesh.new()
	housing.size = Vector3(0.64, 0.18, 0.12)
	housing.material = dark_mat
	p.call(housing, Vector3(0, 0, 0.56), Vector3.ZERO, Vector3.ONE)

	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.07
	nozzle.bottom_radius = 0.05
	nozzle.height = 0.09
	nozzle.radial_segments = 12
	nozzle.material = engine
	p.call(nozzle, Vector3(-0.22, 0, 0.65), Vector3(90, 0, 0), Vector3.ONE)
	p.call(nozzle, Vector3(0, 0, 0.65), Vector3(90, 0, 0), Vector3.ONE)
	p.call(nozzle, Vector3(0.22, 0, 0.65), Vector3(90, 0, 0), Vector3.ONE)

	return {"engine_mat": engine, "nozzles": [Vector3(-0.22, 0, 0.65), Vector3(0, 0, 0.65), Vector3(0.22, 0, 0.65)]}

static func _build_comet(p: Callable) -> Dictionary:
	var body_mat := _mat(Color(0.85, 0.82, 0.78), 0.7, 0.25)
	var chrome_mat := _mat(Color(0.9, 0.92, 0.95), 1.0, 0.12)
	var red_mat := _mat(Color(0.8, 0.1, 0.12), 0.45, 0.35)
	var glass_mat := _mat(Color(0.16, 0.22, 0.3), 0.85, 0.1)
	var bell_mat := _mat(Color(0.35, 0.36, 0.4), 0.9, 0.3)
	var porthole_mat := _mat(Color(1.0, 0.92, 0.75), 0.1, 0.4, Color(1.0, 0.85, 0.55), 1.5)
	var engine := _engine_mat()

	var hull := CapsuleMesh.new()
	hull.radius = 0.21
	hull.height = 1.3
	hull.material = body_mat
	p.call(hull, Vector3(0, 0.03, -0.05), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.75))

	var nose := SphereMesh.new()
	nose.radius = 0.16
	nose.height = 0.32
	nose.material = chrome_mat
	p.call(nose, Vector3(0, 0.03, -0.62), Vector3.ZERO, Vector3(1.05, 0.78, 0.8))

	var nose_ring := TorusMesh.new()
	nose_ring.inner_radius = 0.18
	nose_ring.outer_radius = 0.235
	nose_ring.material = red_mat
	p.call(nose_ring, Vector3(0, 0.03, -0.4), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.75))

	var canopy := SphereMesh.new()
	canopy.radius = 0.12
	canopy.height = 0.24
	canopy.material = glass_mat
	p.call(canopy, Vector3(0, 0.14, -0.22), Vector3.ZERO, Vector3(0.9, 0.8, 1.25))

	var fin := PrismMesh.new()
	fin.size = Vector3(0.5, 0.3, 0.035)
	fin.left_to_right = 0.0
	fin.material = red_mat
	p.call(fin, Vector3(0, 0.19, 0.4), Vector3(0, 90, 0), Vector3.ONE)
	p.call(fin, Vector3(-0.139, -0.05, 0.4), Vector3(-60, -90, 180), Vector3.ONE)
	p.call(fin, Vector3(0.139, -0.05, 0.4), Vector3(60, -90, 180), Vector3.ONE)

	var collar := TorusMesh.new()
	collar.inner_radius = 0.145
	collar.outer_radius = 0.205
	collar.material = chrome_mat
	p.call(collar, Vector3(0, 0.02, 0.5), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.78))

	var bell := CylinderMesh.new()
	bell.top_radius = 0.14
	bell.bottom_radius = 0.08
	bell.height = 0.18
	bell.radial_segments = 14
	bell.material = bell_mat
	p.call(bell, Vector3(0, 0.02, 0.6), Vector3(90, 0, 0), Vector3.ONE)

	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.12
	nozzle.bottom_radius = 0.12
	nozzle.height = 0.06
	nozzle.radial_segments = 12
	nozzle.material = engine
	p.call(nozzle, Vector3(0, 0.02, 0.66), Vector3(90, 0, 0), Vector3.ONE)

	var porthole := SphereMesh.new()
	porthole.radius = 0.022
	porthole.height = 0.044
	porthole.material = porthole_mat
	p.call(porthole, Vector3(-0.202, 0.07, -0.18), Vector3.ZERO, Vector3.ONE)
	p.call(porthole, Vector3(-0.202, 0.07, 0.0), Vector3.ZERO, Vector3.ONE)
	p.call(porthole, Vector3(-0.202, 0.07, 0.18), Vector3.ZERO, Vector3.ONE)
	p.call(porthole, Vector3(0.202, 0.07, -0.18), Vector3.ZERO, Vector3.ONE)
	p.call(porthole, Vector3(0.202, 0.07, 0.0), Vector3.ZERO, Vector3.ONE)
	p.call(porthole, Vector3(0.202, 0.07, 0.18), Vector3.ZERO, Vector3.ONE)

	return {"engine_mat": engine, "nozzles": [Vector3(0, 0.02, 0.66)]}
