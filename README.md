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
- `debug/`: on-screen readouts and the tuning panel.
- `tests/`: headless checks.

## Check the physics

```sh
godot --headless --path . -s tests/sim_check.gd
```

Prints suspension sag, acceleration, braking, cornering grip and reverse. Touches no files.

```sh
godot --headless --path . -s tests/panel_check.gd
```

Checks the tuning panel. Saves only to the system temp folder.

## Tune the car

1. Press Tab or View. The game pauses and the setup panel opens.
1. Move between rows with the D-pad or arrow keys. Left and right change a value by 1 % of its range. The mouse works too.
1. Changes apply at once. Close the panel and drive to feel them.
1. Save writes to `car/roadster.tres`. Revert goes back to the last save.

Useful knobs:

- **Steer assist**: at 1, full stick turns the wheels only as far as the tires can use, so the car stops pushing wide. Set 0 for full lock at any speed.
- **Steer assist slip**: higher lets full stick push the front past peak grip.
- **Anti-roll bars**: a stiffer rear bar cuts understeer. Above about 5000 N/m the inside rear wheel spins up in hard corners and the car spins, because the differential is open.

## Controls

| Action     | Xbox controller | Keyboard      |
|------------|-----------------|---------------|
| Steer      | Left stick      | A/D or arrows |
| Throttle   | Right trigger   | W or Up       |
| Brake      | Left trigger    | S or Down     |
| Reverse    | LB down past N to R | Q down past N to R |
| Handbrake  | A               | Space         |
| Shift up   | RB              | E             |
| Shift down | LB              | Q             |
| Back to start | Y            | R             |
| Tuning panel | View          | Tab           |
| Pause      | Menu            | Esc           |

Units are metric: metres, kilograms, newtons. Physics runs at 120 Hz with Jolt.
