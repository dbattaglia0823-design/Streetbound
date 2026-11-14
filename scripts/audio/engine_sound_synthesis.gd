class_name EngineSoundSynthesis
extends RefCounted
## Offline-per-vehicle original waveforms. No real-world recordings are copied.
## Generated only when a car is selected; active playback uses ordinary
## AudioStreamPlayer nodes, not a per-sample GDScript audio callback.
const RATE := 22050
const LOOP_FRAMES := 13230 # 0.6 seconds; exact integer combustion cycles.
const REFERENCE_RPM := [1200.0, 2600.0, 4200.0, 6400.0]
const FAMILIES := {
	"i3": 1.5, "i4": 2.0, "i6": 3.0, "v6": 3.0,
	"v8_cross": 4.0, "v8_flat": 4.0, "v10": 5.0,
	"v12": 6.0, "w12": 6.0, "w16": 8.0,
	# Future roster: odd-fire five, opposed layouts, rotary, V16 hybrid and EV.
	"i5": 2.5, "boxer4": 2.0, "boxer6": 3.0,
	"rotary2": 2.0, "v16": 8.0, "electric": 0.0
}
static var _loops: Dictionary = {}
static var _effects: Dictionary = {}


static func family_supported(family: String) -> bool:
	return FAMILIES.has(family)


static func firing_frequency(family: String, rpm: float) -> float:
	return rpm / 60.0 * float(FAMILIES.get(family,4.0))


static func _pcm(samples: PackedFloat32Array, looping: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size()*2)
	for i in samples.size():
		bytes.encode_s16(i*2,roundi(clampf(float(samples[i]),-0.95,0.95)*32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


static func engine_loop(family: String, stage: int,
		aggression: float = 0.8, roughness: float = 0.5,
		loaded: bool = true, tone: float = 0.0) -> AudioStreamWAV:
	# Recording-inspired power-on and off-throttle exhaust beds; they keep
	# the same firing order and exact RPM cycle but have independent harmonic
	# energy. Cached samples never change inside the driving frame loop.
	var key := "%s:%d:%d:%d:%d:%d" % [family,clampi(stage,0,3),
		roundi(aggression*20.0),roundi(roughness*20.0),
		1 if loaded else 0,roundi(tone*20.0)]
	if _loops.has(key):
		return _loops[key]
	var rpm := float(REFERENCE_RPM[clampi(stage,0,3)])
	var fire_cycles := roundi(firing_frequency(family,rpm)*float(LOOP_FRAMES)/RATE)
	# EVs produce quiet motor harmonics, NOT combustion pulses, a limiter
	# crackle or camshaft lope. This path is kept in the eight-band engine
	# mixer so future electric models can use the same listener infrastructure.
	if family == "electric":
		var motor := PackedFloat32Array()
		motor.resize(LOOP_FRAMES)
		var band := clampi(stage,0,3)
		var fundamental: int = [67,107,169,269][band]
		var bright_motor := clampf((tone+1.0)*0.5,0.0,1.0)
		for i in LOOP_FRAMES:
			var x := float(i)/float(LOOP_FRAMES)
			var phase := TAU*float(fundamental)*x
			var hum := sin(phase+0.15)*0.32+sin(phase*2.0+0.2)* \
				(0.11+bright_motor*0.09)+sin(phase*3.0+0.4)*0.045
			var inverter := sin(TAU*float(fundamental*5+19)*x)*0.027
			motor[i] = (hum+inverter)*(0.30 if loaded else 0.20)
		var electric_stream := _pcm(motor,true)
		_loops[key] = electric_stream
		return electric_stream
	# Integer firing-cycle loop removes PCM click at the wrap point, even
	# for odd three-cylinder, V6 and W16 engines.
	var rasp := clampf(aggression,0.1,1.4)
	var rough := clampf(roughness,0.0,1.0)
	var bright := clampf((tone+1.0)*0.34,0.0,0.68)
	var output := PackedFloat32Array()
	output.resize(LOOP_FRAMES)
	var mean := 0.0
	for i in LOOP_FRAMES:
		var x := float(i)/float(LOOP_FRAMES)
		var phase := TAU*float(fire_cycles)*x
		var base := sin(phase)*(0.63-bright*0.25)+ \
			sin(phase*2.0+0.14)*(0.12+bright*0.16)+ \
			sin(phase*3.0+0.35)*(0.035+bright*0.075)+ \
			sin(phase*4.0+0.61)*(0.012+bright*0.035)
		var uneven := 0.0
		match family:
			"i3":
				uneven = sin(phase/3.0+0.31)*0.31
				base += sin(phase*2.0/3.0)*0.11
			"i4":
				uneven = sin(phase*0.5)*0.17
				base += sin(phase*2.5)*0.065
			"i5":
				# Distinct odd-cylinder pulse beat: 2.5 combustion events
				# per crank turn, a throaty low growl with a sharp fifth.
				uneven = sin(phase/5.0+0.43)*0.26
				base += sin(phase*1.6+0.2)*0.105
			"boxer4":
				# Opposed four-cylinder exhaust-bank asymmetry.
				uneven = sin(phase*0.5+0.62)*0.26
				base += sin(phase*1.5+0.55)*0.10
			"boxer6":
				# Opposed six is smoother, with dry rear-engine rasp.
				uneven = sin(phase/3.0+0.25)*0.11
				base += sin(phase*2.0+0.42)*0.095
			"rotary2":
				# Continuous high-frequency rotary buzzy harmonics,
				# unlike staccato reciprocating piston exhaust pulses.
				uneven = sin(phase*0.5+0.36)*0.05
				base += sin(phase*3.0+0.14)*0.18+ \
					sin(phase*4.0+0.32)*0.12
			"i6":
				uneven = sin(phase/3.0)*0.07
				base += sin(phase*2.0+0.2)*0.055
			"v6":
				uneven = sin(phase/3.0+0.62)*0.23
				base += sin(phase*4.0/3.0+0.33)*0.10
			"v8_cross":
				# Alternating exhaust-bank pulse yields the low burble and
				# irregular note that an even-fire sine loop cannot produce.
				uneven = sin(phase*0.25+0.41)*0.30+sin(phase*0.5)*0.20
				base += sin(phase*1.5+0.1)*0.11
			"v8_flat":
				uneven = sin(phase*0.5+0.31)*0.09
				base += sin(phase*3.0+0.21)*0.15
			"v10":
				uneven = sin(phase/5.0+0.37)*0.13
				base += sin(phase*2.0+0.2)*0.11
			"v12":
				uneven = sin(phase/3.0)*0.05
				base += sin(phase*2.0)*0.075
			"w12":
				uneven = sin(phase/3.0+0.22)*0.15
				base += sin(phase*0.5+0.17)*0.18
			"w16":
				uneven = sin(phase*0.25+0.45)*0.18
				base += sin(phase*0.5+0.15)*0.24
			"v16":
				# Naturally aspirated, smooth high-revving V16.
				# Deliberately different from the older turbo W16 beat.
				uneven = sin(phase*0.25+0.14)*0.065
				base += sin(phase*2.0+0.34)*0.16+ \
					sin(phase*3.0+0.19)*0.13
		var cycle_grit := sin(phase*2.0+sin(phase*0.5)*0.17)*0.065
		# Tiled, deterministic harmonic turbulence instead of unlooped white
		# noise that pops when samples return to their start position.
		var grains := sin(TAU*float(97+fire_cycles)*x+0.23)*0.045+ \
			sin(TAU*float(171+fire_cycles)*x+1.17)*0.025
		var valve := (0.65+0.35*maxf(0.0,sin(phase)))
		var texture := (base+uneven*0.65)*(1.0+rough*0.23*valve)+ \
			rasp*0.20*cycle_grit+grains*rasp*0.14
		if loaded:
			# Loud loaded firing pressure and straight-through exhaust rasp.
			texture += rasp*(0.035+bright*0.045)*sin(phase*5.0+0.57)
			texture += (0.025+rough*0.035)*sin(phase*6.0+0.84)
		else:
			# Engine braking: softer firing pulse, light driveline buzz and
			# less high-frequency exhaust roar. Distinct from simply making
			# the power-on sample quieter when the throttle closes.
			texture = texture*(0.65-bright*0.06)+ \
				(0.13+rough*0.10)*sin(phase*0.5+0.1)
		# Soft harmonic saturation adds growl without square-wave clipping.
		var sample := tanh(texture*(1.0+rasp*(0.22 if loaded else 0.10)))* \
			(0.56 if loaded else 0.45)
		output[i] = sample
		mean += sample
	mean /= float(LOOP_FRAMES)
	for i in LOOP_FRAMES:
		output[i] -= mean
	# Periodic FIR smoothing removes thin, buzzy upper harmonics without
	# introducing wrap clicks or changing the engine firing rate.
	var softened := PackedFloat32Array()
	softened.resize(LOOP_FRAMES)
	for i in LOOP_FRAMES:
		softened[i] = (output[(i + LOOP_FRAMES - 2) % LOOP_FRAMES] + \
			output[(i + LOOP_FRAMES - 1) % LOOP_FRAMES] * 2.0 + \
			output[i] * 3.0 + output[(i + 1) % LOOP_FRAMES] * 2.0 + \
			output[(i + 2) % LOOP_FRAMES]) / 9.0
	var stream := _pcm(softened,true)
	_loops[key] = stream
	return stream


static func texture_loop(kind: String) -> AudioStreamWAV:
	if _effects.has(kind):
		return _effects[kind]
	var output := PackedFloat32Array()
	output.resize(LOOP_FRAMES)
	for i in LOOP_FRAMES:
		var x := float(i)/float(LOOP_FRAMES)
		var value := 0.0
		match kind:
			"intake":
				for j in 16:
					value += sin(TAU*(89.0+float(j*j)*21.0)*x+float(j)*1.7) / \
						(6.0+float(j)*0.38)
				value *= 0.42
			"turbo":
				value = sin(TAU*108.0*x)*0.18+sin(TAU*216.0*x)*0.07
			"blower":
				value = sin(TAU*132.0*x)*0.21+sin(TAU*264.0*x)*0.09
			"gear":
				value = sin(TAU*82.0*x)*0.15+sin(TAU*164.0*x)*0.06
			"wind":
				for j in 14:
					var harmonic := float(31+j*j*19)
					value += sin(TAU*harmonic*x+float(j)*1.42)* \
						(0.19 / sqrt(float(j)+1.0))
			"road":
				for j in 18:
					var harmonic := float(64+j*j*13)
					value += sin(TAU*harmonic*x+float(j)*2.38)* \
						(0.29 / sqrt(float(j)+1.0))
			"drivetrain":
				value = sin(TAU*68.0*x)*0.15+sin(TAU*136.0*x)*0.06
			"electric_drive":
				# Subtle EV inverter and reduction gear, no exhaust
				# resonance or synthetic combustion pulses.
				value = sin(TAU*211.0*x)*0.19+ \
					sin(TAU*422.0*x+0.11)*0.08+ \
					sin(TAU*691.0*x+0.48)*0.045
		output[i] = value
	var stream := _pcm(output,true)
	_effects[kind] = stream
	return stream


static func transient(kind: String) -> AudioStreamWAV:
	if _effects.has(kind):
		return _effects[kind]
	var duration := 0.50
	match kind:
		"shift": duration = 0.09
		"impact": duration = 0.16
		"pop": duration = 0.11
		"flutter": duration = 0.46
		"bov": duration = 0.57
		"ignition": duration = 0.95
		"shutdown": duration = 0.45
		"blip": duration = 0.20
		"limiter": duration = 0.09
		"curb": duration = 0.12
	var count := roundi(duration*RATE)
	var output := PackedFloat32Array()
	output.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1021 + (int(kind.hash()) & 0x7fffffff)
	var filtered := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i)/float(RATE)
		var progress := t/duration
		var noise := rng.randf_range(-1.0,1.0)
		filtered = lerpf(filtered,noise,0.18)
		var sample := 0.0
		match kind:
			"bov":
				var pitch := 2400.0*exp(-2.3*progress)+390.0
				phase += TAU*pitch/float(RATE)
				var envelope := pow(1.0-progress,2.1)
				sample = (noise*0.16+filtered*0.72+sin(phase)*0.29)*envelope
			"flutter":
				# Compressor surge chatter after a high-boost lift: a
				# decelerating sequence of pulse-gated resonant air bursts.
				var chatter := (7.0+5.0*(1.0-progress))
				var burst := pow(maxf(0.0,sin(TAU*chatter*t*5.0)),3.0)
				phase += TAU*(850.0+260.0*(1.0-progress))/float(RATE)
				sample = (filtered*0.68+sin(phase)*0.34)*burst*pow(1.0-progress,1.1)
			"pop":
				var transient_envelope := exp(-24.0*progress)
				sample = (filtered*0.55+sin(TAU*120.0*t)*0.43)*transient_envelope
			"shift":
				sample = (filtered*0.42+sin(TAU*155.0*t)*0.35)*exp(-18.0*progress)
			"impact":
				sample = (filtered*0.67+sin(TAU*69.0*t)*0.35)*exp(-11.0*progress)
			"ignition":
				# Relay click and repeated cranking before ignition catches.
				var crank := sin(TAU*(61.0+110.0*progress)*t)*0.45+ \
					sin(TAU*43.0*t)*0.25
				sample = (filtered*0.42+crank)* \
					(0.6+0.4*sin(TAU*7.5*t))*(1.0-smoothstep(0.68,1.0,progress))
			"shutdown":
				var pitch_drop := 155.0*pow(1.0-progress,1.5)+18.0
				phase += TAU*pitch_drop/float(RATE)
				sample = (sin(phase)*0.61+filtered*0.22)*pow(1.0-progress,1.8)
			"blip":
				var rev_sweep := 170.0+330.0*sin(PI*progress)
				phase += TAU*rev_sweep/float(RATE)
				sample = (sin(phase)*0.56+sin(phase*2.0)*0.22+ \
					filtered*0.12)*sin(PI*progress)
			"limiter":
				sample = (filtered*0.51+sin(TAU*90.0*t)*0.41)* \
					exp(-15.0*progress)
			"curb":
				sample = (filtered*0.59+sin(TAU*71.0*t)*0.34)* \
					exp(-22.0*progress)
		output[i] = clampf(sample*0.62,-0.9,0.9)
	var stream := _pcm(output,false)
	_effects[kind] = stream
	return stream
