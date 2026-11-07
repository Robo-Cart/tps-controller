# Ragdoll Physics: Soft Limits, Muscle Tone, Impacts and Blending

Implementation guide for the soft-limit / muscle-tension ragdoll used by
`Assets/character_model/ragdoll.gd`. Everything described here is **in the project and
running against `PlayerRagdoll`** — this file explains why it is built the way it is and
how to tune it.

---

## 1. The engine constraint that shapes the whole design

Two facts about GodotPhysics 4.7 drive every decision below:

1. **Joints do not enforce angular limits.** `Generic6DOFJoint3D` accepts
   `set_angular_limit_*` calls and ignores them at simulation time. There is no
   `PinJoint3D`/`ConeTwistJoint3D` configuration that produces a joint that actually stops.
2. **Pose writes fight the solver.** Writing `PhysicalBone3D` transforms every frame
   produces perpetual micro-corrections: the bodies jitter and the pose glitches.

So a joint range is enforced in **two passes**, and both are needed:

```
bodies (PhysicsServer)           skeleton (what you see)
─────────────────────            ──────────────────────
free to swing past the stop  →   _write_poses() clips the drawn turn
soft-stop TORQUE pulls back  →   neutral bias + stiffness shape the drawn turn
```

The bodies get **torque impulses** to make them *want* to come back, and the skeleton gets a
**clipped pose** so the mesh never shows the overshoot. The two are deliberately not the
same number: the visual can be correct while the physical body is momentarily past its stop,
which is exactly what a strained joint looks like.

The torque is the pass that can go wrong in silence: a stop that fires *every* frame of a fall
is a motor returning the limb to the middle of its range, and it is strong enough to beat both
gravity and tone (see §3, "A stop the fall sits on"). The clip can only ever hide a motion, so
an unnatural *force* is always the torque pass.

> **Rule:** never resolve a limit by writing a transform. Add a torque, and clip the pose.

---

## 2. Module map and call order

| File | Purpose |
| --- | --- |
| `ragdoll.gd` | Rig build, momentum handover, damping, per-frame pose authoring |
| `ragdoll_soft_limits.gd` | Feature 1 — soft-zone clip maths + restoring acceleration |
| `ragdoll_muscles.gd` | Feature 2 — neutral posture, tone spring, physical soft stops |
| `ragdoll_impact.gd` | Feature 3 — primary momentum, limb lag, yaw twist, radial blast |
| `ragdoll_blend.gd` | Feature 4 — animation ↔ simulation weight |

Per physics step, in `PlayerRagdoll._physics_process`:

```
_advance_tension(delta)      # tone recovery, impact damping release, settle ramp
_apply_muscle_drives(delta)  # TORQUES for the next solver step (muscle tone + soft stops)
_write_poses()               # clip / stiffen / bias / settle / blend the DRAWN pose
```

Torques are applied **before** the pose is read, so a torque issued this frame is felt by the
solver on the next one and never contradicts what is drawn.

---

## 3. Feature 1 — Soft joint limits

### The curve

A hard clamp is a flat top: `min(angle, stop)`. Its slope goes from 1 to 0 discontinuously, so
the limb hits an invisible wall. Replace the top of the range with a soft zone of width
`soft` and this transfer function:

```
              ⎧ a                                  (free middle)
  clip(a) =   ⎨ aₑ + s · (a - aₑ) / (s + |a - aₑ|)  (soft zone, asymptotic at the stop)
              ⎩ stop                               (exact stop, unreachable)
```

where `aₑ` is the zone edge. It is continuous with **slope 1** at the edge (no kink where the
zone starts) and asymptotic at the stop (the joint never arrives). This is the key property:
the derivative falls from 1 toward 0 as the joint closes on its limit, so the *rate* of turn
decays instead of the turn being cut.

```gdscript
static func clip_angle(angle: float, lower: float, upper: float, soft: float) -> float:
	if upper <= lower or soft <= 0.0:
		return clampf(angle, lower, upper)

	var high_edge: float = upper - soft
	if angle > high_edge:
		var over: float = angle - high_edge
		return high_edge + soft * over / (soft + over)

	var low_edge: float = lower + soft
	if angle < low_edge:
		var over: float = low_edge - angle
		return low_edge - soft * over / (soft + over)

	return angle
```

Which reads, per axis of the joint's Euler range:

| input | output |
| --- | --- |
| `-90°` (past stop `-30`, zone `12`) | `-28.286°` |
| `-60°` | `-27.333°` |
| `-30°` (at the stop) | `-24.000°` (zone edge) |
| `0°` | `0.000°` |

### The restoring force

The correction is written as a **change of angular speed**, not as an acceleration. This is
the single most important decision in the whole stop:

> An acceleration has to be picked for one mass. 1200 rad/s² is a firm nudge to a thigh and a
> violent kick to a clavicle, so one constant cannot be right for both. Speed is
> mass-independent: "take 3 rad/s out of this joint" means the same thing on every bone,
> because the impulse that produces it is scaled by that bone's own inertia.

The overshoot is normalised into *soft-zone widths*, so one gain works for large and small
ranges:

```gdscript
# +1 pressed against the upper stop, -1 against the lower, |x| > 1 physically past it.
static func signed_overshoot(angle, lower, upper, soft) -> float:
	if upper <= lower:
		# Pinned axis: no travel at all, so the stop sits at zero.
		return signf(angle - lower) * maxf(absf(angle - lower) - soft, 0.0) / soft
	if soft <= 0.0:
		return 0.0
	...
	return (angle - high_edge) / soft

# Squared response: the first degrees into the zone barely pull, the last few are decisive.
static func stop_step(overshoot: float, outward_speed: float) -> float:
	var pull: float = minf(LIMIT_PULL_STEP * pow(overshoot, RESISTANCE_EXPONENT), MAX_LIMIT_PULL_STEP)
	var brake: float = clampf(outward_speed, 0.0, MAX_LIMIT_STEP - pull)
	return pull + brake
```

Two parts, and the split matters:

- **The pull** grows with the square of the overshoot. `ABS(overshoot)²` is what makes it feel
  like tissue rather than a spring: barely anything at the edge (the "spongy" part),
  unmistakable near the stop (the "ligament" part).
- **The brake** is sized to remove exactly the outward speed the joint still has, so it stops
  the joint instead of bouncing it, and a joint already on its way back gets no brake at all.
  Because it is bounded by the speed it is cancelling it can never over-cancel — which is why
  it is allowed to be large while the pull is capped separately at `MAX_LIMIT_PULL_STEP`.

### Applying it per bone

`RagdollMuscles.apply_limit` measures the joint's deviation from rest **in the joint's own
rest frame**, and drives the body about the matching **world** axis:

```gdscript
var joint_basis: Basis = Basis(parent_rotation * rest)
var deviation: Quaternion = rest.inverse() * (parent_rotation.inverse() * _rotation_of(body))

# A fold about one axis, read as one turn and split over the joint's axes by how much of
# that turn lies along each. get_angle() is NOT the shortest arc: it returns 0..TAU.
var fold: float = deviation.get_angle()
var fold_axis: Vector3 = deviation.get_axis().normalized()
if fold > PI:
	fold = TAU - fold
	fold_axis = -fold_axis

# Half a turn is its own mirror image, so the axis is undefined there; hold the joint to
# its parent's motion instead of driving it about a rounding error.
if fold > PI - 0.05:
	_damp_to_parent(body, parent_body, limit_weight)
	return

var overshoot: float = 0.0                            # worst axis ...
overshoot = maxf(overshoot, (fold - reach) / widest_soft)   # ... or the whole turn
var world_axis: Vector3 = (joint_basis * fold_axis).normalized()
var step: float = RagdollSoftLimits.stop_step(overshoot, outward_speed)
apply_angular_step(body, world_axis, -step * limit_weight)
```

Four bugs worth knowing, all of which produced the same symptom (a joint with no resistance):

1. **Measuring in one frame and driving in another.** Driving about `parent_basis[axis]`
   while the deviation was measured in the joint's frame put a hip's fold on an axis 180°
   from the one it turns about (measured `frame_dot = -1.00`), and the correction came out
   nearly perpendicular to the actual fold (`applied · v̂ = -0.12`). Measure and drive about
   `parent_rotation * rest * fold_axis`, nothing else.
2. **The fold is one turn, not three Euler angles.** `Basis(deviation).get_euler()` splits a
   170° knee fold onto the swing and twist axes, where the per-axis overshoot is nonsense.
3. **A fold spread over three axes can be out of range with no axis violated.** A shoulder can
   turn 100° with every axis inside its own stop. Hence the `reach` check against the furthest
   corner of the range box.
4. **Pinned axes are axes too.** Most joints only have a range on one axis; the other two are
   held at zero. If those get a soft zone of 0 the stop never fires and the joint is a free
   hinge — a foot can spin right round on the shin. They get `PIN_SOFT_ZONE` instead.

Two safety notes learned from testing:

- **Torque impulses accumulate; velocity writes overwrite.** `body_apply_torque_impulse`
  adds to the body's spin, so a weak per-frame tone still adds up over many frames. Use
  `BODY_STATE_ANGULAR_VELOCITY` only when you deliberately want to replace a spin.
- **`MAX_SANE_OVERSHOOT` guards were a mistake and are gone.** A guard that skips a joint
  which has folded a long way silences exactly the joint that needs help most. Past a half
  turn the joint is damped to its parent instead — see the `_damp_to_parent` branch.

### Tuning

| Constant | Meaning | Effect of raising it |
| --- | --- | --- |
| `SOFT_SHARE` / `DEFAULT_SOFT_SHARE` | Zone width as a share of each side of the range | Earlier, softer approach; limb never visibly reaches its stop |
| `RESISTANCE_EXPONENT` | Shape of the resistance curve | `1` = linear spring (rubbery); `2` = muscle; `3` = sudden wall |
| `LIMIT_PULL_STEP` | rad/s removed per unit of squared overshoot | Firmer stop; too high and the joint is held against contact it should yield to |
| `MAX_LIMIT_PULL_STEP` | Cap on the pull, rad/s | Same, but bounded |
| `MAX_LIMIT_STEP` | Cap on pull + brake, rad/s | How hard a joint can be stopped after a violent fold |
| `PIN_SOFT_ZONE` | Give on a zero-span axis, rad | How much a "locked" axis can wiggle before it is pushed back |

### A stop the fall sits on

`apply_limit` is a torque, not a wall, and it is applied **every step a joint is out of the
comfortable middle of its range**. Its size is `min(3 × overshoot², 10)` rad/s of turn removed
per step plus the outward speed, which at a full stop is around 7 rad/s per step — more turn
than gravity gives the trunk in a whole fall. A joint whose range an ordinary death exceeds is
therefore not a limit, it is a **motor driving the limb back**.

The three spine joints were at `15°/8°/8°`. A run killed mid-stride folds the waist 30–45° and
rolls it towards 30° to the side inside a quarter of a second, so all three stops fired from
the first frame: the frame trace shows `Spine2` already at −0.95 of overshoot at frame 1,
before the body has moved at all, and the trunk's lateral overshoot growing to −1.5 by frame
21. The stops then won the argument with the hips, which is exactly the "torso thrown forward
then hauled back" symptom.

The trunk is the one chain given room to live in, `45°/30°/20°` — 135° of fold and 90° of
lateral travel across the chain, a cadaver's spine rather than a mannequin's. Limbs keep
their living range: a limb is expected to sit at its stops, a trunk is not. This started at
`25°/20°/12°`, which fixed the torque half of the symptom and left the drawn half, below.

### The drawn pose cannot fold past the limit

The second pass has the same failure mode and a stricter one. `clip_soft` asymptotes at the
joint's **hard limit**, and `stiffen` only ever scales a turn down, so a joint is drawn at most
at its limit and in practice at `limit × stiffness × (1 − 0.25 × tension)`. Whatever the bodies
do, the visible chest cannot fold further. With the trunk at `25°` the bodies went past 80° at
the waist while the visible chest froze at 35° for the whole fall: the player sees a torso being
hauled back upright even though the simulation is going over cleanly. Measured as drawn tilt
against the `Spine2` body's tilt, over one seeded death:

| Trunk range | Drawn | Bodies |
| --- | --- | --- |
| `25°/20°/12°`, stiffness 0.5 | `26 35 34 34 36 37 38 35 32 46 72` | `26 46 47 51 49 50 50 56 80 98 125` |
| `45°/30°/20°`, stiffness 0.9 | `38 48 51 52 53 55 59 70 82 100 117` | `26 46 47 51 52 53 56 66 82 101 120` |

Two lessons. A range has to be chosen for what a **body** does, not for a standing man, because
it caps both passes. And a share-based neutral posture (`NEUTRAL_POSTURE` is a fraction of each
joint's range) silently grows when a range is widened — 0.4 of 25° was a 10° curl, and 0.4 of
45° is 18°, so the shares are rescaled to `0.22` to hold the curl still.

Practical guidance: the trunk wants a **wide** zone (0.4–0.45; three spine joints stack
their ranges and read as one spongy column), shoulders/arms a **medium** zone (0.32–0.35; a
loose shoulder is the classic ragdoll tell), elbows/knees a **tight** zone (0.28; a knee
still has to reach a convincing fold), hands and feet the tightest (0.25, or pinned so the
visible contact does not slide).


---

## 4. Feature 2 — Muscle tone and the neutral posture

### The posture

The target is a relaxed standing body, not a starfish: arms forward with bent elbows, hips
and knees slightly flexed, head level, trunk very slightly curled. It is authored as
**shares of each joint's own range**, so it survives limit changes:

```gdscript
const NEUTRAL_POSTURE: Dictionary = {
	&"mixamorig_Spine":      Vector3(0.4,  0.5,  0.5),
	&"mixamorig_Shoulder":   Vector3(0.78, 0.55, 0.5),  # driven forward
	&"mixamorig_Arm":        Vector3(0.85, 0.42, 0.5),  # ~42° forward
	&"mixamorig_ForeArm":    Vector3(0.28, 0.5,  0.5),  # permanent gentle elbow bend
	&"mixamorig_UpLeg":      Vector3(0.2,  0.45, 0.5),  # slight hip flex
	&"mixamorig_Leg":        Vector3(0.14, 0.5,  0.5),  # slight knee flex
}
```

The elbow value is the single highest-leverage number in the file: a hinge permanently bent
~34° reads as *alive*; a straight elbow reads as a mannequin regardless of everything else.

#### …but it holds the pose the body died in

`NEUTRAL_POSTURE` is the posture the **rig was built in**, which is the wrong target for the
first second: a body killed at a run has its legs 15° apart and its trunk curled forward, and
tone's first act was to spring them back to standing at the exact moment it should be falling.

`RagdollMuscles.anchor_posture` runs at the end of `_sync_bodies_to_pose`, reads each joint's
actual deviation off the pose the bodies were just moved onto, and stores it clipped into the
joint's range as `spec["hold"]`. `posture_target(spec, relax)` slerps `hold` towards the
authored neutral as `_settle` rises, so the corpse holds the shape it died in while it is
falling and takes the authored pose once it has landed. On one trace: `Spine` holds 6.5°
against a 6.0° neutral, `LeftUpLeg` **16.5° against 7.2°** — a 9° snap that no longer happens.

### Two independent pulls

1. **Drawn bias** — a blend of the clipped drawn turn toward neutral, in `_write_poses`:

```gdscript
var bias: float = float(spec["neutral_bias"]) * _muscle_tone
bias *= lerpf(1.0, RagdollMuscles.NEUTRAL_SETTLE_SHARE, _settle)
limited = RagdollSoftLimits.blend(limited, neutral, bias)
```

The blend is shortest-arc per Euler axis (`wrapf`), so it never takes the 350° route when a
decomposition flips. Because both ends are inside the range, the bias can never defeat a
limit. This is what makes the pose *look* muscular; it is cheap and cannot destabilise.

2. **Physical tone** — a spring-damper torque on every body toward its neutral **world**
rotation:

```gdscript
static func apply_tone(body, target, delta, tone) -> void:
	var error: Quaternion = target * _rotation_of(body).inverse()
	var angle: float = error.get_angle()
	if angle < 0.0005:
		return
	var axis: Vector3 = error.get_axis().normalized()
	var along_speed: float = body.angular_velocity.dot(axis)
	var acceleration: float = MUSCLE_SPRING * angle - MUSCLE_DAMPING * along_speed
	acceleration = clampf(acceleration, -MAX_MUSCLE_ACCELERATION, MAX_MUSCLE_ACCELERATION)
	apply_angular_acceleration(body, axis, acceleration * tone, delta)
```

The correction acts **about the error axis only**, so it cannot cancel angular momentum
around the other two axes — important, or tone would damp a fall into syrup.

Targets are accumulated **parent-first** (`parent_target * rest * neutral`) so a limb's
neutral follows a corrected spine; tone is a posture, not a set of independent twists.

### Tone timeline

`TONE_SHOCK 0.45` → `TONE_BASE 0.85` over `TONE_RECOVERY_TIME 0.35 s`. A real body goes
slack from a shock and then stiffens. The recovery is deliberately quick: the collapse
happens in the first half second, so tone that arrives after the fall arrives too late to
stop the knees buckling under the body. At rest the physical pass keeps
`PHYSICAL_TONE_REST_SHARE 0.85` and the soft stops keep `REST_LIMIT_SHARE 1.0` of their
correction — dropping either is what made the corpse pancake.

### When tone must let go of the trunk

Tone is a posture *spring*, and a spring does not know a fall from a stumble. Two things it
used to get wrong produced the same visible symptom — the torso being thrown forward, then
hauled back the other way while the hips kept going over:

1. **The damping was measured against the world.** The posture target is anchored to the
   parent bone (`apply_drives` builds it as `parent_rotation * rest * neutral`), so the
   error only changes when the joint itself turns. Damping the *absolute* spin instead also
   braked every bone that was falling as part of the whole body: the chest lost the rotation
   gravity had given it, stopped, and rocked back while the hips carried on. Measured over 12
   deaths while running: 4.7 rad/s of relative joint speed before the fix and 0.2–0.4 rad/s
   after, with per-frame travel dropping from 5–16° to 0.0–1.1°.
2. **The trunk has no flexion headroom.** The authored neutral for `Spine`/`Spine1`/`Spine2`
   sits at about 0.4 of a rest-to-limit range of roughly `[-0.05, +0.44]` rad, so the settled
   chest is already near the front of its range. A fall folds the waist past that in two or
   three frames; `MUSCLE_SPRING 400` times the error asks for far more than
   `MAX_MUSCLE_ACCELERATION 600`, so the spring saturates and pulls the trunk upright at full
   strength *while the hips are still descending*. That is the reverse force.
3. **The trunk was out of range, so the stop did the same thing louder.** The soft stop is a
   torque too, and it is applied for every frame the joint is past the front of its soft zone.
   At `15°/8°/8°` the three spine joints were past it from frame 1 of the death, and the stop
   removes up to 7 rad/s of turn per step — several times what tone can ask for. Isolating it
   (`nolimits`, see §8) removed the backswing completely, which is how it was finally caught
   after two rounds of blaming tone.

Fix 2 is `SLACK_JOINTS` and `SLACK_SPIN` in `ragdoll_muscles.gd`: the three trunk joints give
up their posture in proportion to their own spin, losing it entirely at 2 rad/s. A body being
thrown about has no posture to hold, and it gets one back as soon as it stops being thrown —
which is why a settled corpse still keeps its shape on the floor. Fix 3 is the trunk's range in
`JOINT_LIMITS` (see §3, "A stop the fall sits on"): a stop inside the fall's own fold is a
motor, whatever weight it is given.

> **The gate must not be angle-based.** Gating tone on the joint's *error* looks right and
> measures worse: 5.5° of backward trunk unwind over 12 deaths against 2.8° with no gate at
> all, because the same factor also scaled down the parent-relative damping at the exact
> moment the joint was spinning fastest. Spin gates the whole correction; error gates only
> the spring.

### Why it still loses when it should

The reason the body still falls is arithmetic, not tuning luck:

| | angular acceleration |
| --- | --- |
| gravity on a hanging arm (≈0.25 m lever) | **~160 rad/s²** |
| gravity on the trunk | **>100 rad/s²** |
| full tone, at the `MAX_MUSCLE_ACCELERATION 600` ceiling | **600 rad/s²** |
| full tone, at the `MAX_MUSCLE_STEP` ceiling of 2.5 rad/s per step | **150 rad/s²** |
| full soft stop, at `MAX_LIMIT_PULL_STEP` | `10` rad/s per step |

Tone at its ceiling can now hold a hanging arm and a trunk — that is the difference between a
body and a pile — but the ceiling that actually binds is `MAX_MUSCLE_STEP`, not
`MAX_MUSCLE_ACCELERATION`, and it binds *deliberately*: 150 rad/s² is enough to hold posture
and not enough to fight a planted foot or a real impact.

> **Do not raise `MUSCLE_SPRING` to "fix" a drooping arm.** Add `NEUTRAL_BIAS` instead. Tone
> is the physical layer and must stay weaker than the world; the bias is the visual layer and
> can be pushed much further for free.

> **`PhysicalBone3D` has no `inertia` property, but the server knows it.** Read it with
> `PhysicsServer3D.body_get_param(rid, BODY_PARAM_INERTIA)`; it returns a **`Vector3`**, the
> diagonal in the body's own frame. Every torque here is scaled by the real value
> (`_inertia_along`), because guessing it as `mass × INERTIA_PER_KG` was 2–14× wrong on this
> rig (Hips 0.67, Spine 0.34, Neck 0.10, LeftHand 0.07 of the guess) and turned every
> "gentle" constant into a violent one on exactly the light bones — which is what made the
> joints chatter and feel like they had no tension at all.

### Tuning

| Constant | Raise to | Lower to |
| --- | --- | --- |
| `NEUTRAL_BIAS` (0.06–0.5) | Limbs hold shape, less droop, more "heavy" | Limbs read limp and float |
| `NEUTRAL_SETTLE_SHARE` (0.7) | Corpse keeps its shape on the floor | Corpse pancakes |
| `MUSCLE_SPRING` (400) | Stiffer held posture; too far and the corpse reads as propped up | Limbs sag, knees buckle |
| `MUSCLE_DAMPING` (40) | Space-like, no overshoot | Overshoot/wobble (unrealistic for tone) |
| `MAX_MUSCLE_ACCELERATION` (600) | Rarely reachable; the step cap usually binds first | Tone does nothing |
| `MAX_MUSCLE_STEP` (2.5 rad/s) | Stiffer, faster posture recovery — and the first constant to cause a light bone to chatter if raised too far | A limp half-second after every impact |
| `JOINT_DAMPING_RATE` (12) / `JOINT_DAMPING_FLOOR` (0.35) | Joints track their parent and cannot buzz | Joints vibrate against each other
| `TONE_BASE` (0.85) | Stiffer, more athletic collapse | Floppier, deader |
| `TONE_SHOCK` (0.45) | Less momentary slack, limbs whip less | A limp first fifth of a second |
| `TONE_RECOVERY_TIME` (0.35 s) | Later flop right after the hit | Tone arrives too late to stop the knees |
| `PHYSICAL_TONE_REST_SHARE` (0.85) | Corpse holds more shape at rest | Corpse settles into a pile |
| `SLACK_SPIN` (2 rad/s) | Tone holds the trunk through faster throws — the reverse force comes back | The trunk goes limp almost immediately after the hit |

---

## 5. Feature 3 — Rotational impacts

A central impulse alone makes a "bag of mass" slide away: the limbs follow their joints with
no independent motion. Real limbs **lag** the trunk. After the primary impulse lands, the
same shove is applied again, off-pivot, to the shoulders and arms (with the shove) and to the
hips and knees (against it, so the feet trail):

```gdscript
static func apply_blow(bodies, skeleton, direction, hit_point, speed) -> void:
	var shove: Vector3 = direction.normalized()
	# Limbs lag: shoulders are thrown the same way the trunk was shoved.
	_throw(bodies, skeleton, &"mixamorig_LeftShoulder", shove, 1.0, speed, SHOULDER_MASS_SHARE)
	_throw(bodies, skeleton, &"mixamorig_LeftArm",      shove, 1.0, speed, ARM_MASS_SHARE)
	# Legs trail: hips are driven the other way so the feet stay behind the chest.
	_throw(bodies, skeleton, &"mixamorig_LeftUpLeg",    shove, -1.0, speed, LEG_MASS_SHARE)
	_throw(bodies, skeleton, &"mixamorig_LeftLeg",      shove, -1.0, speed, LEG_MASS_SHARE)
	_twist(bodies, shove, hit_point, speed)
```

`_throw` uses `bone.apply_impulse(impulse, lever * LEVER_SHARE)` with the lever taken from
the child bone's real world position, so the shove turns into a swing instead of a
translation. Mass shares are small (shoulder 0.10, arm 0.16, leg 0.08) because the joint
already drags the limb; these impulses add *only* the lag.

`_twist` adds yaw to the hips from the hit's lateral offset, with a 35% counter-twist in
`Spine2`, so a hit on the shoulder turns the body instead of only shoving it.

### Surviving the damping

`ANGULAR_DAMP 15–30` with `DAMP_MODE_REPLACE` eats a one-shot spin in about ten degrees. Two
consequences, both load-bearing:

- Deliberate rotation must be written with `BODY_STATE_ANGULAR_VELOCITY`, not left to an
  impulse (`add_spin` does exactly that, adding to the existing spin and capping it).
- `apply_blast` is a **per-frame** call for the duration of the explosion, not a one-shot:

```gdscript
static func apply_blast(bodies, origin, radius, speed) -> void:
	for key: Variant in bodies:
		var offset: Vector3 = bone.global_position - origin
		var falloff: float = 1.0 - distance / radius
		var push: Vector3 = offset / distance
		var tangent: Vector3 = push.cross(Vector3.UP)      # separates blast from a uniform push
		bone.apply_impulse((push + tangent.normalized() * BLAST_TANGENT)
			* speed * falloff * bone.mass * BLAST_MASS_SHARE, Vector3.ZERO)
		add_spin(bone, tangent * speed * falloff * BLAST_SPIN_SHARE)
```

### Public API on `PlayerRagdoll`

```gdscript
ragdoll.apply_blow(direction, hit_point_world, speed)   # bullet, punch, shove while simulating
ragdoll.apply_blast(origin, radius, speed)              # call every frame during an explosion
```

Both are ignored when the rig is not simulating, so callers need no guards.

### Tuning

| Constant | Raise to | Note |
| --- | --- | --- |
| `SHOULDER_MASS_SHARE` / `ARM_MASS_SHARE` | Arms whip harder | Above ~0.25 the arms overtake the trunk |
| `LEG_MASS_SHARE` | Legs kick out on impact | Too high makes a comedic scissor |
| `LEVER_SHARE` (0.6) | More swing, less shove | Below ~0.3 the limbs barely rotate |
| `MAX_SECONDARY_SPEED` (6) | Stronger lag | Cap exists so a light hit cannot blur the body |
| `MAX_SECONDARY_SPIN` (12 rad/s) | Faster tumbles | 12 ≈ 2 rev/s: already fast on screen |
| `YAW_SHARE` (0.3) / `MAX_YAW_SPEED` (5) | More twisting on off-axis hits | Watch the neck in a headshot |
| `BLAST_TANGENT` (0.35) | Bodies tumble apart rather than radiate | Too high looks like a windmill |

Empirical result with the shipped values: peak body spin ≈15 rad/s at the hit, decaying to
<1 rad/s once settled, hips resting at y ≈ 0.19 m, no NaN and no runaway bodies over 600
headless frames including a mid-fall blast.

---

## 6. Feature 4 — Blending with animation

The weight decides who owns the skeleton: `0` = animation, `1` = bodies. Everything between
is the hand-over, and the hand-over is what makes a stumble read as *catching himself*
instead of a corpse switch.

```gdscript
# ragdoll.gd, inside _write_poses
var simulated: Transform3D = Transform3D(Basis(rotation), body_pose.origin)
if _simulation_weight < 1.0:
	var animated: Transform3D = (
		skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
	)
	simulated = RagdollBlend.blend_pose(animated, simulated, _simulation_weight)
poses[bone_index] = simulated
```

`blend_pose` is a shortest-arc quaternion slerp plus a position lerp, so there is no gimbal
flip mid-handover.

`RagdollBlend` owns the timing and the triggers:

```gdscript
func update(delta: float, grounded: bool, speed: float) -> float:
	if not grounded and speed >= IMPACT_FALL_SPEED:      # 2.5 m/s airborne
		_target = 1.0
	elif speed >= STUMBLE_SPEED and weight < 1.0:        # 2.0 m/s
		_target = maxf(_target, 0.5)                     # lean on the simulation
	elif grounded and _target > 0.0:
		_grounded_time += delta
		if _grounded_time >= RECOVER_GROUNDED_TIME:      # 0.35 s on the ground
			_target = 0.0
	var duration: float = BLEND_IN_TIME if weight < _target else BLEND_OUT_TIME
	weight = move_toward(weight, _target, delta / maxf(duration, 0.001))
	return weight
```

Asymmetric by design: `BLEND_IN_TIME 0.2 s` (a trip is a snap) versus `BLEND_OUT_TIME 0.5 s`
(recovering must look deliberate). Automatic triggers can be overridden with
`request_fall()` / `request_recover()` for scripted moments.

### Wiring a stumble (not yet in `player.gd`)

```gdscript
var _ragdoll_blend := RagdollBlend.new()

func _physics_process(delta: float) -> void:
	# ... existing movement ...
	var weight: float = _ragdoll_blend.update(delta, is_on_floor(), velocity.length())
	if _ragdoll != null:
		if weight > 0.0 and not _ragdoll.is_simulating_physics():
			_ragdoll.start_simulation(velocity, Vector3.UP * _yaw_rate)
		elif weight <= 0.0 and _ragdoll.is_simulating_physics():
			velocity = Vector3.ZERO              # or hand the measured momentum back
			_ragdoll.stop_simulation()
		_ragdoll.set_simulation_weight(weight)
```

Requirements for this to look right:

1. **Keep the `AnimationTree` running while `weight < 1`.** It is what the partial weight is
   blending *from*. Only at `weight == 1` (death) should it be disabled.
2. **Update the tree in `_physics_process`, before the ragdoll.** `_write_poses` reads
   `get_bone_global_pose`, so if the tree writes in idle time the blend reads its own previous
   output instead of the animation.
3. **Do not disable the character body** during a stumble — the capsule keeps driving
   locomotion while the skeleton leans on the simulation. `_die()` deliberately does disable
   it, which is the difference between a stumble and a death.

### Tuning

| Constant | Raise to | Lower to |
| --- | --- | --- |
| `STUMBLE_SPEED` (2.0) | Only hard knocks become stumbles | Nearly every run trips |
| `IMPACT_FALL_SPEED` (2.5) | Falls hand over later | Airborne body goes limp immediately |
| `BLEND_IN_TIME` (0.2) | Softer catch | Snappier |
| `BLEND_OUT_TIME` (0.5) | More laboured recovery | Poppy return |
| `RECOVER_GROUNDED_TIME` (0.35) | Body lies longer before getting up | Pops upright |

---

## 7. Symptom → parameter cheat sheet

| Symptom on screen | Change |
| --- | --- |
| Limbs stop dead on an invisible wall | Raise the joint's `SOFT_SHARE`, lower `RESISTANCE_EXPONENT` |
| **The torso is thrown forward, then hauled back upright while the hips keep going over** | Check the joint is not out of range for the whole fall: widen its `JOINT_LIMITS` first, then gate tone (see §3, "A stop the fall sits on") |
| **The body keeps falling but the visible chest stops rotating** | The drawn cap: `clip_soft` asymptotes at `JOINT_LIMITS`, so the range is too small for the fall. Compare the drawn bone pose against the body's own transform (see §3, "The drawn pose cannot fold past the limit") |
| Limb is drawn in a pose the bodies are not in | Check `JOINT_STIFFNESS` for that bone: the drawn share is `stiffness × (1 − 0.25 × tension)`, so 0.5 draws a joint at 44% of where the bodies put it |
| Joints feel rubbery / bouncy | Raise `LIMIT_PULL_STEP`, raise `RESISTANCE_EXPONENT` |
| Body folds into a ball on impact | Lower `MAX_LIMIT_PULL_STEP`, widen the hip `SOFT_SHARE` |
| Corpse is a ball only once it stops moving | Raise `REST_LIMIT_SHARE`, raise `PHYSICAL_TONE_REST_SHARE` |
| A joint buzzes or shakes at rest | Raise `JOINT_DAMPING_RATE`, lower `MAX_MUSCLE_STEP` |
| A limb spins right round on a joint that should not turn | Check the axis has a span; a zero span needs `PIN_SOFT_ZONE` |
| Arms float out sideways | Raise `NEUTRAL_BIAS` on arms, raise the shoulder `NEUTRAL_POSTURE` share |
| Arms stick out like a superhero | Lower arm `NEUTRAL_POSTURE` x-share toward 0.7 |
| Elbows look rigid | Raise the elbow `NEUTRAL_POSTURE` x-share (0.28 → 0.35) |
| Body looks weightless mid-fall | Lower `MAX_MUSCLE_ACCELERATION`, lower `TONE_BASE` |
| Body looks like it is being held up | Lower `PHYSICAL_TONE_REST_SHARE`, lower `NEUTRAL_SETTLE_SHARE` |
| Knees buckle during the collapse | Raise `TONE_RECOVERY_RATE` (shorter `TONE_RECOVERY_TIME`), raise `MUSCLE_SPRING` |
| Corpus pancake on the floor | Raise `SETTLE_BIAS`, raise `NEUTRAL_SETTLE_SHARE` |
| Death is a single frame of blur | Lower `HIT_SPEED`, lower `MAX_SECONDARY_SPIN`, raise `IMPACT_ANGULAR_DAMP` |
| Limbs do not react to the hit | Raise `ARM_MASS_SHARE` / `LEG_MASS_SHARE`, raise `LEVER_SHARE` |
| Explosion looks like a uniform push | Raise `BLAST_TANGENT`, raise `BLAST_SPIN_SHARE` |
| Stumble snaps | Raise `BLEND_IN_TIME` |
| Recovery is sluggish | Lower `BLEND_OUT_TIME`, lower `RECOVER_GROUNDED_TIME` |

---

## 8. Verification notes

- `gdlint` clean on all five files (`ragdoll.gd` is at 1000 of the 1000-line cap; new
  behaviour belongs in the modules, not the rig).
- `godot --headless --import` registers all five `class_name`s.
- Headless death + blast probe (600 frames): no NaN, no runaway bodies, peak spin
  ≈15 rad/s decaying to 0.6, hips settling at y ≈ 0.19 m, `settle` reaching 1.0, tone
  recovering 0.15 → 0.55, and `clip_angle` verified numerically (table in §3).
- A joint range is enforced in **two** places, and they fail differently: `apply_limit` is a
  stop torque on the bodies (a joint that visibly fights the fall), and `clip_soft` in
  `_write_poses` clips what is drawn (a joint that is only ever wrong in the render). The old
  note here said the drawn pass was the only one — that was true of the code as first written
  and was the reason the stop torque went unexamined for two rounds.
- The drawn pass has to be judged **against the bodies**, not against the previous build. Print
  the drawn bone pose's tilt next to the same `PhysicalBone3D`'s tilt, every frame. The drawn
  trunk lagged the bodies by up to 55° for the whole of a fall and both builds looked plausible
  frame by frame; only the two columns side by side show a torso the player is not seeing.

### How to judge whether the joints resist

Not by reading constants, and **not** by `PhysicalBone3D.angular_velocity`: on this rig it
reports meaningless figures (a spine joint folded 3.5° reported 9.45 rad/s relative, and every
joint reported 27–45 rad/s in the same frame). Use transforms only:

- **fold** — `rad_to_deg(min(raw, TAU - raw))` of
  `rest.inverse() * (parent_rotation.inverse() * child_rotation)`. Raw `get_angle()` is not
  the shortest arc and inflates every fold past a half turn.
- **travel** — the frame-to-frame change of `fold`, in degrees per frame, averaged over the
  last 60 frames. This is the honest answer to "does the joint resist": a held joint sits at
  0.0–0.4°/frame, a free one at 5–16°/frame.
- **out-of-range frames** — count frames where `fold` exceeds the joint's widest span.

Deaths are chaotic, but a **seeded frame trace** is not: `seed(N)` in
`SceneTree._initialize()` plus `--fixed-fps 60` makes one death byte-identical across runs
(verified over three), which is what makes a one-run A/B legitimate. That seed only covers
the `randi()` settle pose and the blow; a real game runs unseeded, so anything that changes
solver behaviour still wants a mean of **12 runs** before it is believed.

Trace the frames, not the aggregate. Print tilt, fold, hips height and the per-axis soft
overshoot every frame (1, 5, 9 … 33, then 60, 90 … 240) for a single death. A 21° backswing
that is unmissable frame by frame averages out to 1.9° over twelve deaths — the metric was
not wrong, the instrument was too blunt, and two rounds were spent tuning the wrong subsystem
because of it.

Isolate a subsystem with a **run-time flag**, never by editing constants and hoping: the probe
accepts `nolimits` (zero every `spec["soft"]`), `notone` (`_muscle_tone = 0`), `nostiffen`,
`noanchor` and `wide`, so one seeded death can be compared against five counterfactuals.

Measured on this rig, before → after the fixes above:

| | before | after |
| --- | --- | --- |
| mean fold at rest | 90.1° | 27–36° |
| mean relative speed at rest | 4.68 rad/s | 0.22–0.43 rad/s |
| joint travel at rest | 5–16°/frame | 0.0–1.1°/frame |
| out-of-range frames (knees, hips, spine) | 370–410 of 410 | single digits to ~20 |

One honest known limitation: the clavicle (`mixamorig_*Shoulder`, range 10°/10°/8°) rests
86–106° out of range, because the whole weight of an arm on a 0.3 m lever needs far more
torque than a stop may apply. A real clavicle is braced by the ribcage and ligaments, which a
ragdoll has not got; the drawn pose clips it, so it reads as a stiff shoulder rather than a
dislocation.

### How to measure "my torso springs back"

The symptom is a *reversal*, so the metric is the backwards part of the trunk's tilt, split by
phase, because the phases have different causes:

| phase | frames after the kill (at 60 fps) | what is happening |
| --- | --- | --- |
| fall | until the chest passes 60° of tilt | the blow, the fold, and tone's chance to fight it |
| post | 60 → 170 | the body meeting the floor |
| settle | 170 onwards | `SETTLE_START 2.5 s`, the authored settle pose |

Count frames where the trunk's tilt rate is more negative than −20°/s and sum the negative
tilt, per phase. Twelve deaths, killed while running at 5 m/s:

| build | mean backwards tilt during the fall |
| --- | --- |
| angle-gated yield on the trunk | 5.5° |
| no gate at all | 2.8° |
| `SLACK_SPIN` gate | 1.9° |

Eliminated by measurement along the way, each isolated on its own: the `JOINT_DAMPING_FLOOR`
(identical output), the muscle spring, `TONE_BASE`, the drawn stiffness, `HIT_SPEED` (it
changes the shape of the fall, not the reversal), and `ANGULAR_DAMP`/`IMPACT_ANGULAR_DAMP`
(15→2 and 30→4 changed nothing). All of those were guesses that the numbers refused.

> **The soft stops were on that list, and they were the answer.** That verdict came from the
> 12-run aggregate. With every `spec["soft"]` zeroed, the trunk's tilt at frames
> 1/5/9/…/33 is `25 39 36 36 35 35 34 29 36` — monotone. With them in place it was
> `25 45 45 44 37 26 24 26 41`: a **21° backswing at 0.4 s**. Cause in §3, "A stop the fall
> sits on". After widening the trunk's range: `25 45 46 51 52 51 53 52 71` — the chest never
> goes back, and the fold climbs from 12° to 49° without a frame of regression.

The drawn pose follows the physical pose through every turn, but it is not a copy: the
stiffness (`JOINT_STIFFNESS`, 0.5 on the trunk) draws the chest at about half the physical
fold. Judge forces on the bodies and shapes on the render.
