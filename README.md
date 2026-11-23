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
- `track/`: places to drive. `circuit.gd` builds a loop from straights and arcs.
- `modes/`: game modes. `time_trial/` has the lap timer, best-lap file and lap display.
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

Checks the tuning panel, including the unsaved-changes question. Saves only to the system temp folder.

```sh
godot --headless --path . -s tests/aids_check.gd
```

Checks traction control: full throttle in 1st, straight and in a tight turn, with it on and off. Touches no files.

```sh
godot --headless --path . -s tests/lap_check.gd
```

Checks the track, the lap timer and the best-lap file. Saves only to the system temp folder.

## Time trial

The game starts on `track/loop_1.tscn`, a 1.6 km loop with a fast sweeper, a chicane and two hairpins.

- You start 30 m before the line. The clock starts when you cross it.
- Hidden checkpoints stop shortcuts. Miss one and the lap doesn't count.
- Grass has less grip and slows the car.
- Y puts you back at the start and cancels the lap.
- After each checkpoint and lap, the gap to your best shows in green (faster) or red (slower).
- Best laps are kept in `user://lap_records.cfg`. On Linux that's `~/.local/share/godot/app_userdata/Racer/`. Delete the file to clear them.

## Tire grip display

Four boxes in the bottom-left corner show the tires, laid out like the car seen from above.

- Grey: gripping.
- Yellow: near the limit. This is where the tire grips hardest.
- Red: sliding or spinning. Red rear boxes mean wheelspin; red front boxes mean the car is running wide.
- `TC` turns yellow while traction control is cutting power.

## Tune the car

1. Press Tab or View. The game pauses and the setup panel opens.
1. Move between rows with the D-pad or arrow keys. Left and right change a value by 1 % of its range. The mouse works too.
1. Changes apply at once. Close the panel and drive to feel them.
1. Save writes to `car/roadster.tres`. Revert goes back to the last save.
1. Tab or View again closes the panel. With unsaved changes it asks first: Save, Drive without saving, Undo changes, or Back (B or Tab).

Useful knobs:

- **Traction control**: cuts power when a rear wheel spins. The differential is open, so in tight corners the inside rear wheel spins up easily. On by default.
- **Traction slip**: how much wheelspin traction control allows. Higher lets the car slide more.
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
