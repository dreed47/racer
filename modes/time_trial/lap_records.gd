class_name LapRecords
extends RefCounted
## Best laps, one per track, kept in a small file between sessions.

const DEFAULT_PATH := "user://lap_records.cfg"

var path := DEFAULT_PATH


## user:// paths go to a temp folder under tests (see SavePaths).
func _init(file_path := DEFAULT_PATH) -> void:
	path = SavePaths.safe(file_path)


## Best lap on a track: {"time": float, "splits": Array[float], "level": String}, or empty
## if none. level is the learning level it was driven at, or "" for laps from before levels.
func best(track_id: String) -> Dictionary:
	var file := ConfigFile.new()
	if file.load(path) != OK or not file.has_section_key(track_id, "time"):
		return {}
	var splits: Array[float] = []
	for t in file.get_value(track_id, "splits", []):
		splits.append(float(t))
	return {"time": float(file.get_value(track_id, "time")), "splits": splits,
			"level": str(file.get_value(track_id, "level", ""))}


## Stores a best lap, keeping other tracks' records. Returns the Godot error code.
func save_best(track_id: String, time: float, splits: Array[float], level := "") -> Error:
	var file := ConfigFile.new()
	file.load(path)  # A missing file just means no records yet.
	file.set_value(track_id, "time", time)
	file.set_value(track_id, "splits", Array(splits))
	file.set_value(track_id, "level", level)
	file.set_value(track_id, "date", Time.get_datetime_string_from_system())
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return file.save(path)
