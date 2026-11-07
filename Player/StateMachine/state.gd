extends Node
class_name State

@warning_ignore("unused_signal")
signal finished(next_state: String)


func _enter() -> void:
	return


func _exit() -> void:
	return


func _state_input(_event: InputEvent) -> void:
	return


func _update(_delta: float) -> void:
	return


func _crouch_toggle_requested() -> void:
	return


## Asked to start a slide by the shared roll input, which fires whenever the
## player taps it while moving fast. Only the states that can carry a slide
## report back that they took it, so the input can fall back to the crouch.
func _slide_requested() -> bool:
	return false
