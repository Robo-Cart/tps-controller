Godot Third Person controller extending Chaff Games tutorials
https://www.youtube.com/@Chaff_Games
https://www.youtube.com/watch?v=VuYspK3MaqY&list=PLhnGgh9GDmn6Cf4_ut7I0VJNHh9Vbfkjv

# Input Mapping

Source of truth: `project.godot` → `[input]`.

> **Note:** There is no `crouch` or `slide` action. Both are derived at runtime from *taps* of the `roll` input (see `Player/StateMachine/PlayerStateMachine/player_state_machine.gd`).

---

## Movement

| Action | Keyboard / Mouse | Gamepad | Deadzone |
| :--- | :--- | :--- | :--- |
| `up` | `W` | Left stick ↑ <sub>(axis 1 −)</sub> | 0.5 |
| `down` | `S` | Left stick ↓ <sub>(axis 1 +)</sub> | 0.5 |
| `left` | `A` | Left stick ← <sub>(axis 0 −)</sub> | 0.5 |
| `right` | `D` | Left stick → <sub>(axis 0 +)</sub> | 0.5 |
| `jump` | `Space` | **A** <sub>(button 0)</sub> | 0.5 |
| `sprint` | `Shift` | **L3** <sub>(button 7)</sub> | 0.5 |
| `roll` | `C` | **B** <sub>(button 1)</sub> | 0.2 |
| `climb` | `E` | **Back / Select** <sub>(button 4)</sub> | 0.2 |

### `roll` gestures

| Gesture | Result |
| :--- | :--- |
| Single tap | Crouch / stand up, or slide if fast enough, or slide downhill if on a slope |
| Double tap | Roll |
| Single tap while sliding | Roll out of the slide |

---

## Combat

| Action | Keyboard / Mouse | Gamepad | Deadzone |
| :--- | :--- | :--- | :--- |
| `aim` | Right mouse button | LT <sub>(axis 4 +)</sub> | 0.5 |
| `shoot` | Left mouse button | RT <sub>(axis 5 +)</sub> | 0.5 |
| `reload` | `R` | **X** <sub>(button 2)</sub> | 0.5 |
| `holster_weapon` | `F` | — | 0.5 |
| `weapon_up` | Mouse wheel up <sub>(button 4)</sub> | **Y** <sub>(button 3)</sub> | 0.5 |
| `drop` | `G` | D-pad Down <sub>(button 12)</sub> | 0.2 |
| `swap_camera_alignment` | `Tab` | **R3** <sub>(button 8)</sub> | 0.5 |

---

## Camera

| Action | Binding | Deadzone |
| :--- | :--- | :--- |
| `aim_left` | Right stick X − | 0.2 |
| `aim_right` | Right stick X + | 0.2 |
| `aim_up` | Right stick Y − | 0.2 |
| `aim_down` | Right stick Y + | 0.2 |
| `model_view` | `Shift` + `` ` `` / `~` | 0.2 |
| `model_view` <sub>(gamepad)</sub> | D-pad Up <sub>(button 11)</sub> | 0.2 |

---

## Menu & Misc

| Action | Keyboard / Mouse | Gamepad | Deadzone |
| :--- | :--- | :--- | :--- |
| `menu_button` | — | Back / Select <sub>(button 4)</sub> | 0.2 |
| `start_button` | — | **Start** <sub>(button 6)</sub> | 0.2 |
| `items` | — | **LB** <sub>(button 9)</sub> | 0.2 |
| `emote` | `T` | D-pad Left <sub>(button 13)</sub> | 0.2 |
| `death` | `X` | — | 0.2 |

---

## Notes

- **Shared physical button:** `climb` and `menu_button` both bind gamepad **button 4** (Back / Select).
- **Physical keycodes:** `sprint` (`4194325` = Shift) and `swap_camera_alignment` (`4194306` = Tab) are bound by *physical* keycode, so they follow key position rather than keyboard layout.
- **Analogue deadzones:** movement and aim actions use a 0.5 deadzone by default; the newer gameplay actions (`roll`, `climb`, `drop`, `model_view`, sticks, `emote`, `death`, `items`) use 0.2.

---

## Quick reference (gamepad layout)

| Button | Index | Actions |
| :--- | :--- | :--- |
| A | 0 | `jump` |
| B | 1 | `roll` (crouch / slide / roll) |
| X | 2 | `reload` |
| Y | 3 | `weapon_up` |
| Back / Select | 4 | `climb`, `menu_button` |
| Start | 6 | `start_button` |
| L3 | 7 | `sprint` |
| R3 | 8 | `swap_camera_alignment` |
| LB | 9 | `items` |
| D-pad Up | 11 | `model_view` |
| D-pad Down | 12 | `drop` |
| D-pad Left | 13 | `emote` |
| LT | axis 4 + | `aim` |
| RT | axis 5 + | `shoot` |
| Left stick | axes 0, 1 | `left` / `right`, `up` / `down` |
| Right stick | axes 2, 3 | `aim_left` / `aim_right`, `aim_up` / `aim_down` |
