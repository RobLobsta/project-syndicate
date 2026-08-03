class_name GroundSource
extends RefCounted
## The authored baseline a [GroundChunk] is filled from, feeding
## [member GroundChunk.base_heights] and [member GroundChunk.surface_ids].
##
## [b]Every query is a pure function of sample position.[/b] That is not a
## stylistic preference — chunks are allocated lazily and in whatever order the
## match happens to touch them, so a baseline drawn from a sequential
## [RandomNumberGenerator] would give two peers different terrain purely because
## they drove in different directions. Architectural Invariant I-9 requires the
## field to be reproducible; indexing the noise by position rather than by draw
## order is what delivers it.
##
## The noise is integer-hashed rather than [FastNoiseLite] for the same reason
## the rest of this layer quantises: an integer hash has no platform-dependent
## floating-point history, so two peers agree bit for bit.

enum Kind {
	## A level plane at [member base_height_m]. The fixture shape, and what the
	## match scene used before this document was implemented.
	FLAT = 0,
	## Summed value-noise octaves — open ground with rises and hollows.
	ROLLING = 1,
	## [constant ROLLING] with a broad depression at the world centre, which is
	## what makes an arena read as a basin.
	BASIN = 2,
}

## Wavelength of the coarsest noise octave, in samples.
const BASE_WAVELENGTH_SAMPLES: float = 220.0
const OCTAVE_COUNT: int = 4
const OCTAVE_LACUNARITY: float = 2.0
const OCTAVE_GAIN: float = 0.5

## Basin shaping. The radius is a fraction of the world span, and the depth is
## subtracted with a smooth falloff so the rim is drivable rather than a wall.
const BASIN_RADIUS_FRACTION: float = 0.34
const BASIN_DEPTH_M: float = 9.0

## Slope above which ground is classified [constant SurfaceTable.Surface.LOOSE]:
## spoil collects on steep faces and not on flat ones. Expressed as metres of
## rise per metre of run.
const LOOSE_SLOPE_THRESHOLD: float = 0.34

var kind: Kind = Kind.FLAT
var seed: int = 0
## Height of [constant Kind.FLAT], and the datum the other kinds vary about.
var base_height_m: float = 0.0
## Peak-to-trough amplitude of the summed octaves, in metres.
var amplitude_m: float = 14.0
## Surface written everywhere the slope rule does not override it.
var default_surface: int = SurfaceTable.Surface.COMPACTED


static func flat(height_m: float = 0.0) -> GroundSource:
	var s := GroundSource.new()
	s.kind = Kind.FLAT
	s.base_height_m = height_m
	return s


static func rolling(noise_seed: int, amplitude: float = 14.0) -> GroundSource:
	var s := GroundSource.new()
	s.kind = Kind.ROLLING
	s.seed = noise_seed
	s.amplitude_m = amplitude
	return s


static func basin(noise_seed: int, amplitude: float = 11.0) -> GroundSource:
	var s := GroundSource.new()
	s.kind = Kind.BASIN
	s.seed = noise_seed
	s.amplitude_m = amplitude
	return s


## Baseline height in metres at sample [param s].
func height_at(s: Vector2i) -> float:
	if kind == Kind.FLAT:
		return base_height_m
	var h := base_height_m + _fbm(s) * amplitude_m
	if kind == Kind.BASIN:
		h -= _basin_falloff(s) * BASIN_DEPTH_M
	return h


## Baseline surface classification at sample [param s].
##
## Derived from the local gradient rather than authored per sample, so the
## classification cannot disagree with the geometry it describes. A flat source
## is uniformly [member default_surface].
func surface_at(s: Vector2i) -> int:
	if kind == Kind.FLAT:
		return default_surface
	var spacing := GroundConstants.SAMPLE_SPACING_M
	var dx := (height_at(s + Vector2i(1, 0)) - height_at(s - Vector2i(1, 0))) / (2.0 * spacing)
	var dz := (height_at(s + Vector2i(0, 1)) - height_at(s - Vector2i(0, 1))) / (2.0 * spacing)
	var slope := sqrt(dx * dx + dz * dz)
	if slope > LOOSE_SLOPE_THRESHOLD:
		return SurfaceTable.Surface.LOOSE
	return default_surface


## Normalised [0, 1] depression weight at sample [param s], 1 at the world
## centre and 0 outside the basin radius.
func _basin_falloff(s: Vector2i) -> float:
	var w := GroundMath.sample_to_world_xz(s)
	var r := GroundConstants.WORLD_SPAN_M * BASIN_RADIUS_FRACTION
	var d := w.length() / maxf(r, 1.0)
	if d >= 1.0:
		return 0.0
	# smoothstep gives zero gradient at both ends, so the basin lip has no
	# crease for a suspension probe to catch on.
	return 1.0 - smoothstep(0.0, 1.0, d)


## Summed value-noise octaves at sample [param s], in [-1, 1].
func _fbm(s: Vector2i) -> float:
	var total := 0.0
	var amp := 1.0
	var norm := 0.0
	var wavelength := BASE_WAVELENGTH_SAMPLES
	for octave: int in OCTAVE_COUNT:
		total += _value_noise(s, wavelength, octave) * amp
		norm += amp
		amp *= OCTAVE_GAIN
		wavelength /= OCTAVE_LACUNARITY
	return total / maxf(norm, 0.0001)


## Bilinearly interpolated integer-hash value noise in [-1, 1].
func _value_noise(s: Vector2i, wavelength: float, octave: int) -> float:
	var fx := float(s.x) / wavelength
	var fz := float(s.y) / wavelength
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx := smoothstep(0.0, 1.0, fx - float(x0))
	var tz := smoothstep(0.0, 1.0, fz - float(z0))
	var h00 := _hash_unit(x0, z0, octave)
	var h10 := _hash_unit(x0 + 1, z0, octave)
	var h01 := _hash_unit(x0, z0 + 1, octave)
	var h11 := _hash_unit(x0 + 1, z0 + 1, octave)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Deterministic hash of a lattice corner to [-1, 1].
##
## Integer arithmetic throughout, masked to 32 bits at every step so the result
## does not depend on how wide the host's integers happen to be.
func _hash_unit(x: int, z: int, octave: int) -> float:
	var h := (x * 374761393 + z * 668265263 + octave * 2147483647 + seed * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 13)) & 0xFFFFFFFF
	h = (h * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h) / 2147483647.5 - 1.0
