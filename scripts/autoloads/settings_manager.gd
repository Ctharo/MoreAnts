extends Node
## SettingsManager - Handles persistent game settings that survive between sessions

signal settings_changed

## Settings file path
const SETTINGS_PATH: String = "user://settings.cfg"

## Default settings values
var defaults: Dictionary = {
	"initial_ant_count": 20,
	"max_ants": 100,
	"ant_spawn_cost": 10.0,
	"spawn_rate": 0.5,
	"initial_food_stored": 100.0,
	"food_cluster_count": 6,
	"food_per_cluster": 200.0,
	"food_sources_per_cluster": 8,
	"cluster_radius": 100.0,
	"world_width": 2000.0,
	"world_height": 2000.0,
	"time_scale": 1.0,
}

## Current settings
var settings: Dictionary = {}

## ConfigFile for persistence
var _config: ConfigFile = ConfigFile.new()


func _ready() -> void:
	load_settings()


## Load settings from file or use defaults
func load_settings() -> void:
	var err: Error = _config.load(SETTINGS_PATH)
	
	if err != OK:
		# File doesn't exist or is corrupted, use defaults
		settings = defaults.duplicate()
		save_settings()
		return
	
	# Load each setting, falling back to default if not present
	settings.clear()
	for key: String in defaults:
		settings[key] = _config.get_value("settings", key, defaults[key])
	
	settings_changed.emit()


## Save current settings to file
func save_settings() -> void:
	for key: String in settings:
		_config.set_value("settings", key, settings[key])
	
	var err: Error = _config.save(SETTINGS_PATH)
	if err != OK:
		push_error("Failed to save settings: %s" % error_string(err))
	
	settings_changed.emit()


## Get a setting value
func get_setting(key: String) -> Variant:
	return settings.get(key, defaults.get(key, null))


## Set a setting value
func set_setting(key: String, value: Variant) -> void:
	settings[key] = value


## Reset all settings to defaults
func reset_to_defaults() -> void:
	settings = defaults.duplicate()
	save_settings()


## Get all settings as a dictionary
func get_all_settings() -> Dictionary:
	return settings.duplicate()
