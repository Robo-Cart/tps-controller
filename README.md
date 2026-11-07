Godot Third Person controller extending Chaff Games tutorials
https://www.youtube.com/@Chaff_Games
https://www.youtube.com/watch?v=VuYspK3MaqY&list=PLhnGgh9GDmn6Cf4_ut7I0VJNHh9Vbfkjv

Movement
Action	Keyboard / Mouse	Gamepad	Deadzone
up	W	Left stick ↑ (axis 1 −)
down	S	Left stick ↓ (axis 1 +)
left	A	Left stick ← (axis 0 −)
right	D	Left stick → (axis 0 +)
jump	Space	A (button 0)
sprint	Shift	L3 (button 7)
roll	C	B (button 1)
climb	E	Back/Select (button 4)

Combat
Action	Keyboard / Mouse	Gamepad	Deadzone
aim	Right mouse button	LT (axis 4 +)
shoot	Left mouse button	RT (axis 5 +)
reload	R	X (button 2)
holster_weapon	F	
weapon_up	Mouse wheel up (button 4)	Y (button 3)
drop	G	D-pad Down (button 12)
swap_camera_alignment	Tab	R3 (button 8)

Camera
Action	Binding	Deadzone
aim_left / aim_right	Right stick X (axis 2 − / +)
aim_up / aim_down	Right stick Y (axis 3 − / +)
model_view	Shift + ` (~)	D-pad Up (button 11)

Menu / misc
Action	Keyboard / Mouse	Gamepad	Deadzone
menu_button	—	Back/Select (button 4)
start_button	—	Start (button 6)
items	—	LB (button 9)
emote	T	D-pad Left (button 13)
death	X

Notes:
There is no crouch or slide action — both are derived at runtime from taps of roll (C / B), handled in player_state_machine.gd and the crouch/slide states.
climb and menu_button share the gamepad Back/Select button (button 4), so that physical button is bound to two actions.
sprint uses Shift (physical_keycode 4194325), and swap_camera_alignment uses Tab (4194306); both are bound as physical keycodes, so they follow key position rather than layout.
