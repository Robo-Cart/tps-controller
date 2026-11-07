class_name Stamina
extends RefCounted

## Shared stamina pool for the movement states. Sprinting and rolling draw on it,
## and it refills once the player stops exerting themselves for
## `stamina_regeneration_delay`.
##
## The pool lives on the class rather than on a state node because the states are
## separate siblings but only ever one of them is active: a static pool keeps the
## value across every state change without threading a reference between them.

const STATS: MovementStats = preload("res://Player/player_movement_stats.tres")

## Negative until the first read, which is how a freshly spawned player starts
## with a full pool without every state having to reset it on entry.
static var _current: float = -1.0
static var _regeneration_delay: float = 0.0


## Current stamina in points, between 0 and `STATS.stamina_max`.
static func get_current() -> float:
	if _current < 0.0:
		_current = maxf(STATS.stamina_max, 0.01)
	return _current


## Current stamina as a 0..1 fraction, for the HUD.
static func get_fraction() -> float:
	return clampf(get_current() / maxf(STATS.stamina_max, 0.01), 0.0, 1.0)


static func is_empty() -> bool:
	return get_current() <= 0.0


## Whether the pool holds enough for a sprint to start, or to be handed back to
## after a roll, slide or climb.
static func can_sprint() -> bool:
	return get_current() >= STATS.sprint_min_stamina


## Whether the pool holds enough for a roll to start.
static func can_roll() -> bool:
	return get_current() >= STATS.roll_stamina_cost


## Takes stamina and restarts the regeneration delay. The pool never goes below
## zero: a drain that overdraws it empties it, and the calling state is what ends
## the action.
static func drain(amount: float) -> void:
	if amount <= 0.0:
		return

	_current = maxf(get_current() - amount, 0.0)
	_regeneration_delay = maxf(STATS.stamina_regeneration_delay, 0.0)


## Refills the pool at the configured rate once the delay since the last drain
## has run out.
static func regenerate(delta: float) -> void:
	if _regeneration_delay > 0.0:
		_regeneration_delay = maxf(_regeneration_delay - delta, 0.0)
		return

	_current = minf(get_current() + STATS.stamina_regeneration * delta, STATS.stamina_max)


## Puts the pool back to full. Called by the player on spawn so a new scene does
## not inherit the previous one's stamina.
static func reset() -> void:
	_current = maxf(STATS.stamina_max, 0.01)
	_regeneration_delay = 0.0
