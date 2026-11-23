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
- `debug/`: test tools, such as the controller readout.

## Controls

| Action     | Xbox controller | Keyboard      |
|------------|-----------------|---------------|
| Steer      | Left stick      | A/D or arrows |
| Throttle   | Right trigger   | W or Up       |
| Brake      | Left trigger    | S or Down     |
| Handbrake  | A               | Space         |
| Shift up   | RB              | E             |
| Shift down | LB              | Q             |
| Reset car  | Y               | R             |
| Pause      | Menu            | Esc           |

Units are metric: metres, kilograms, newtons. Physics runs at 120 Hz with Jolt.
