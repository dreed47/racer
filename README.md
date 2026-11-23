<img src="assets/icon.svg" width="64" height="64" alt="">

# Racer

Semi-realistic driving sim built with Godot 4 and GDScript.

## Run

```sh
godot --path . -e   # open the editor
godot --path .      # run the game
```

## Layout

- `car/`: car physics and setup.
- `track/`: places to drive.
- `modes/`: game modes (time trial first).
- `drivers/`: what controls a car (player now, AI later).
- `camera/`: chase camera.
- `debug/`: on-screen readouts, such as wheel loads.
- `tests/`: headless checks.

## Check the physics

```sh
godot --headless --path . -s tests/sim_check.gd
```

Prints suspension sag, weight transfer and speeds. Touches no files.

## Controls

| Action     | Xbox controller | Keyboard      |
|------------|-----------------|---------------|
| Steer      | Left stick      | A/D or arrows |
| Throttle   | Right trigger   | W or Up       |
| Brake      | Left trigger    | S or Down     |
| Reverse    | Hold LT when stopped | Hold S when stopped |
| Handbrake  | A               | Space         |
| Shift up   | RB              | E             |
| Shift down | LB              | Q             |
| Reset car  | Y               | R             |
| Pause      | Menu            | Esc           |

Units are metric: metres, kilograms, newtons. Physics runs at 120 Hz with Jolt.
