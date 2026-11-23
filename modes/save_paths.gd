class_name SavePaths
extends RefCounted
## Where the game keeps files between sessions (best laps, ghosts), in Godot's user:// folder.
## Under a test script (godot -s tests/...), user:// paths go to a temp folder instead, so
## tests can never touch the real saved files.


## The path to use for a user:// file. Unchanged unless a test script is running.
static func safe(path: String) -> String:
	if not path.begins_with("user://") or not running_test():
		return path
	return test_dir().path_join(path.trim_prefix("user://"))


## Temp folder for this test run.
static func test_dir() -> String:
	return OS.get_temp_dir().path_join("racer_test_%d" % OS.get_process_id())


## True when the game runs under a test script: the scene tree then has a script on it.
static func running_test() -> bool:
	var tree := Engine.get_main_loop()
	return tree != null and tree.get_script() != null
