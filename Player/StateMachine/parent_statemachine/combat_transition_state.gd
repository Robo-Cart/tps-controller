extends State
class_name CombatTransitionState

signal combat_status_changed(_status: String)

@export var state_machine: StateMachine
@export var status: String


func _enter() -> void:
	# Motion._enter() clears the crouch flag on the state we are about to enter,
	# so remember the posture before the child machine restarts.
	var keep_crouched: bool = Motion.crouched

	state_machine._initialize(state_machine.start_state)
	combat_status_changed.emit(status)

	if keep_crouched:
		state_machine._change_state("CrouchIdle")


func _exit() -> void:
	state_machine._set_active(false)
