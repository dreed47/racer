<img src="assets/icon.svg" width="64" height="64" alt="">

# Racer

Semi-realistic driving sim built with Godot 4 and GDScript.

## Run

```sh
godot --path . -e   # open the editor
godot --path .      # run the game
```

## Layout

- `car/`: car physics and setup. `car_look.gd` puts the 3D model from `car/roadster/` on the car. `sound/` makes the engine, tire and wind sound. Only the tire skid is a recording.
- `track/`: places to drive. `track.gd` is what every track offers. `circuit.gd` builds a loop from straights and arcs in code. `blender_track.gd` loads a track made in Blender.
- `tools/blender/`: Python scripts that build and export Blender tracks and the car model.
- `modes/`: game modes. `time_trial/` has the lap timer, best-lap file, lap display and ghost car. `save_paths.gd` keeps tests away from your saved files.
- `drivers/`: what controls a car: the player and the AI driver. `racing_line.gd` works out the AI's line and speeds.
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

Checks loop_1, the lap timer and the best-lap file. Saves only to the system temp folder.

```sh
godot --headless --path . -s tests/track_check.gd
```

Checks the Ridge track: gates, centreline, hills, surfaces, a timed lap and the car at the start. Touches no files.

```sh
godot --headless --path . -s tests/look_check.gd
```

Checks the car model: four wheels with calipers, the steering wheel turns, the brake lights glow. Touches no files.

```sh
godot --headless --path . -s tests/sound_check.gd
```

Checks car sound: engine pitch follows rpm, squeal only when sliding on hard ground, wind grows with speed, mute works. Touches no files.

```sh
godot --headless --path . -s tests/ghost_check.gd
```

Checks the ghost car: recording and replay, saving and loading, keeping only the fastest lap, the see-through car following the lap, and the on/off key. Writes only to a temp folder.

```sh
godot --headless --path . --fixed-fps 120 -s tests/ai_check.gd
```

Checks the AI driver: its racing line, a clean lap of Ridge at 90 % skill, the on/off key, the grid start and the skill slider. Takes about a minute. Touches no files.

## Time trial

The game starts on Ridge (`track/ridge/ridge.tscn`), a 2.6 km track with hills, a blind crest and a downhill hairpin.

To drive loop_1 instead, open `main.tscn` in a text editor and change `res://track/ridge/ridge.tscn` to `res://track/loop_1.tscn`. A track picker comes later.

On Ridge:

- Red and white kerbs mark the corners. They grip a little less than the road.
- Gravel traps sit on the outside of the big corners. Gravel grips less than grass and slows you much more.
- Low walls guard the fastest corners.

- You start 30 m before the line. The clock starts when you cross it.
- Hidden checkpoints stop shortcuts. Miss one and the lap doesn't count.
- Grass has less grip and slows the car.
- Each track keeps its own best lap.
- Y puts you back at the start and cancels the lap.
- After each checkpoint and lap, the gap to your best shows in green (faster) or red (slower).
- Best laps are kept in `user://lap_records.cfg`. On Linux that's `~/.local/share/godot/app_userdata/Racer/`. Delete the file to clear them.

## Ghost car

A see-through, pale blue copy of the roadster replays your fastest lap on the track while you drive. Race it to see where you gain or lose time. It has no collision, so you drive through it.

- It starts when you cross the line, in step with your lap, and stops at the end of its lap.
- The ghost is your fastest recorded lap. Laps from before the ghost was added weren't recorded, so your first full lap now sets it.
- G or D-pad up turns it on and off. A note on screen says which.
- Ghosts are kept in `user://ghosts/`, one file per track, next to the best-lap file. Delete a file to clear that track's ghost.

## AI driver

A yellow roadster with the same physics as yours drives Ridge for you to race.

- I or D-pad right turns it on and off. Turning it on puts both cars back on the grid, the AI car on your right. It waits until you move off.
- It works out its own racing line from the track and slows for each corner. It changes gear itself.
- It ignores you. The cars can bump.
- It makes no sound, so it doesn't clash with your engine.
- Its laps never count towards your times or ghost.
- **AI skill** in the tuning panel sets how close to the grip limit it drives, from 30 % to 100 %. At 90 % it laps Ridge in about 94 s. Above 90 % it sometimes slides off. If it gets stuck or leaves the track, it's put back on its line.

## Tire grip display

Four boxes in the bottom-left corner show the tires, laid out like the car seen from above.

- Grey: gripping.
- Yellow: near the limit. This is where the tire grips hardest.
- Red: sliding or spinning. Red rear boxes mean wheelspin; red front boxes mean the car is running wide.
- `TC` turns yellow while traction control is cutting power.

## Sound

The engine and wind are made in code while you drive. The tire skid is a recording, `car/sound/tire_skid.wav`.

- Engine: a four-cylinder note that follows the rpm. More throttle sounds louder and rougher.
- Tires: a soft road rumble that grows with speed. The skid fades in when a grip box turns yellow and is loudest at red, a little higher in pitch the harder you slide. It stays below the engine. No skid on grass or gravel.
- Wind: grows with speed.

To change the volume, select `CarSound` in `main.tscn` in the editor and set `Volume Db`. Each sound has its own level there too. `Tire Db` sets the skid and road rumble.

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
| Mute sound | D-pad down      | M             |
| Ghost car on/off | D-pad up  | G             |
| AI car on/off | D-pad right    | I             |

Units are metric: metres, kilograms, newtons. Physics runs at 120 Hz with Jolt.

## Making tracks in Blender

Ridge is built by a script, so you can rebuild it from scratch or edit it by hand.

Rebuild from the script (about 10 s):

```sh
blender -b -P tools/blender/build_ridge.py
```

This writes `track/ridge/source/ridge.blend` and `track/ridge/ridge.glb`. It overwrites hand edits in the `.blend`.

Edit by hand:

1. Open `track/ridge/source/ridge.blend` in Blender and make your changes. Save.
2. Export to the game:

   ```sh
   blender -b track/ridge/source/ridge.blend -P tools/blender/export_track.py -- track/ridge/ridge.glb
   ```

3. Run `godot --headless --path . -s tests/track_check.gd` to check nothing broke.

Name objects so the game knows what they are. The start of each name sets the surface:

| Name starts with | Grip | Slows the car |
|---|---|---|
| `road` | 1.0 | no |
| `kerb` | 0.9 | a little |
| `grass` | 0.6 | yes |
| `gravel` | 0.45 | a lot |
| `wall`, `stand`, `tree` | 0.6 | no |
| `deco` | no collision, looks only | |

Markers (Blender empties, arrow pointing the way you drive):

- `Gate0`: start/finish line. `Gate1`, `Gate2` and so on: checkpoints, in driving order.
- `Spawn`: where the car starts, a little above the road.
- `Centreline`: an edge loop along the middle of the road. Hidden in the game.

Blender prints `ERROR MeshOptimizer is not available` during export. It's harmless.

## Car model in Blender

The roadster model is built by a script too:

```sh
blender -b -P tools/blender/build_roadster.py
```

This writes `car/roadster/source/roadster.blend` and `car/roadster/roadster.glb`. It overwrites hand edits in the `.blend`.

To edit by hand, open the `.blend`, save, then export:

```sh
blender -b car/roadster/source/roadster.blend -P tools/blender/export_track.py -- car/roadster/roadster.glb
```

The model only changes looks. The car still collides as a box. Keep these object names:

- `wheel`: the front left wheel, outer face to the left. The game copies it to all four corners.
- `caliper`: the brake caliper beside it. Steers but doesn't spin.
- `steering_wheel`: origin at the hub.
- `brake_lights`: glow when you brake.

The `preview_wheel` objects in the `.blend` only show the other three wheels there. They are not exported.

## Credits

- Tire skid: "Car tire squeal skid loop" by Tom Haigh (audible-edge), from [OpenGameArt](https://opengameart.org/content/car-tire-squeal-skid-loop), licensed [CC-BY 3.0](https://creativecommons.org/licenses/by/3.0/). Changed: pitched 25% lower, high end softened, and converted to 22 kHz mono.
