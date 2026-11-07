class_name MovementStats
extends Resource

@export var time_to_jump_apex: float = 0.5
@export var time_to_land: float = 0.5
@export var jump_height: float = 1.0
@export_range(0.0, 1.0, 0.05) var jump_release_velocity_multiplier: float = 0.5
@export_range(0.0, 1.0, 0.05) var jump_momentum_multiplier: float = 0.75
@export var run_speed: float = 4.5
@export var sprint_speed: float = 5.8
@export var aim_speed: float = 1.5
@export var crouch_speed: float = 2.0
@export var acceleration: float = 100
@export var in_air_acceleration: float = 5.0
@export var roll_speed: float = 8.0
@export var roll_duration: float = 1.0
@export_range(0.0, 2.0, 0.05) var roll_exit_speed_fraction: float = 0.85
@export var roll_double_tap_window: float = 0.35
@export var roll_double_tap_max_hold: float = 0.25

## Horizontal speed (in m/s) the player has to be travelling at for a press of
## the roll input to start a slide instead of toggling the crouch.
@export var slide_min_speed: float = 4.5

## Speed (in m/s) the slide bleeds down to before the slide state ends. Keeping
## it above zero hands run/sprint a little momentum instead of a standstill.
@export var slide_end_speed: float = 1.9

## Deceleration (in m/s^2) applied while sliding on level ground. This is the
## slide's friction: normal movement brakes at `acceleration`, so a low value here
## is what lets the player carry their momentum. Raising it shortens every slide.
## A face takes less of it the steeper it gets, down to `slide_slope_friction` at
## `Player.slope_max_climb_angle`, so a descent is greased while the flat grabs.
@export var slide_friction: float = 6.0

## Deceleration (in m/s^2) the ground takes off a slide on a face as steep as
## `Player.slope_max_climb_angle`. Between level ground and that face the slide
## blends from `slide_friction` to this, so the steeper the descent the less the
## surface holds it back and the sooner the slope's own pull
## (`slide_slope_acceleration`) adds speed. Lower this to make a downhill slide
## reach its ceiling faster.
@export var slide_slope_friction: float = 2.0

## Acceleration (in m/s^2) a slope adds to the slide. This is the slide's own
## pull and is tuned for feel rather than read off real gravity. Measured against
## the friction the face still has (see `slide_slope_friction`) it sets the angle
## where a downhill slide gains speed rather than loses it: about 10 degrees with
## the defaults. That sits well below the `slide_min_slope_angle` a face has to be
## for a crouch to become a slide, so every face that can tip the player into a
## slide also feeds it, and the steeper the face the harder it shoves, up to
## `slide_slope_max_speed`.
@export var slide_slope_acceleration: float = 32.0

## Fastest (in m/s) a slide is allowed to run on level ground. A slide on the
## flat only ever loses speed, so this is a ceiling it never actually reaches:
## it is here so the slide and the descent share one clamp. It sits a little
## above `sprint_speed`, because a slide is meant to be a way to keep momentum,
## not a faster way to travel.
@export var slide_max_speed: float = 6.0

## Fastest (in m/s) a slide is allowed to run on a face as steep as
## `Player.slope_max_climb_angle`. The ceiling blends from `slide_max_speed` on
## level ground up to this, so a descent is allowed to outrun the flat while a
## long face still cannot run away with the player.
@export var slide_slope_max_speed: float = 9.0

## Slope angle (degrees above horizontal) steep enough for a crouch to be a
## slide. On a face this steep the crouch state hands over to the slide on its
## own, travelling downhill whichever way the player is facing; on gentler ground
## the crouch holds and the roll tap leaves the player standing up instead.
@export_range(0.0, 89.0, 0.5) var slide_min_slope_angle: float = 20.0

## Share of the movement input's travel the player has to hold to stay in a
## sprint. Sprinting is a commitment: easing the stick back below this ends the
## sprint and drops the player to a run, instead of letting a half-pushed stick
## walk along at a reduced pace while the sprint still drains stamina. A keyboard
## is always at 1.0, so this only affects analogue sticks.
@export_range(0.1, 1.0, 0.05) var sprint_min_input: float = 0.9

@export_group("Stamina")

## Size of the stamina pool. Every cost and drain below is in the same points,
## and the HUD shows the pool as a 0..1 fraction of this value.
@export var stamina_max: float = 100.0

## Points of stamina restored per second once the player stops exerting
## themselves.
@export var stamina_regeneration: float = 25.0

## Seconds after the last drain before regeneration starts, so a short breather
## does not instantly refill the bar between two sprints.
@export var stamina_regeneration_delay: float = 0.75

## Points per second spent while sprinting. With the default pool this is about
## three and a third seconds of sprint, after which the player drops back to a
## run.
@export var sprint_stamina_drain: float = 30.0

## Stamina needed before a sprint can start, or be resumed after a roll/slide.
@export var sprint_min_stamina: float = 10.0

## One-off cost of a roll.
@export var roll_stamina_cost: float = 25.0

@export_group("Slope speed")

## Slope angle (degrees above horizontal) where a climb starts to cost speed.
## Gentler slopes are crossed at the movement state's full speed.
@export_range(0.0, 89.0, 0.5) var slope_slow_angle: float = 12.0

## Share of the movement state's own speed the player is left with on a slope as
## steep as `Player.slope_max_climb_angle`, the steepest face that still counts
## as ground. Between the two angles the speed falls off with the slope, so a
## run, sprint, aim-walk or crouch-walk all slow down together on the same face.
@export_range(0.1, 1.0, 0.05) var slope_min_speed_fraction: float = 0.45

## Slope angle (degrees above horizontal) where standing still stops holding.
## With no movement input on a face steeper than this the player slips downhill,
## gently at first and at `slip_speed` on the steepest face they can stand on.
@export_range(0.0, 89.0, 0.5) var slip_angle: float = 25.0

## Speed (in m/s) a standing player is pulled down the face at when it is as
## steep as `Player.slope_max_climb_angle`. Any movement input cancels it, so
## this is the price of standing still, not of crossing the slope.
@export var slip_speed: float = 2.0


func get_jump_gravity() -> float:
	var jump_gravity: float = (2 * jump_height) / pow(time_to_jump_apex, 2)
	return jump_gravity


func get_fall_gravity() -> float:
	var fall_gravity: float = (2 * jump_height) / pow(time_to_land, 2)
	return fall_gravity


func get_jump_velocity(gravity: float) -> float:
	var jump_velocity: float = gravity * time_to_jump_apex
	return jump_velocity
