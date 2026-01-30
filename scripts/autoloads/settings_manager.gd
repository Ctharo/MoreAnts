extends Node
## SettingsManager - Handles persistent game settings that survive between sessions

signal settings_changed

## Settings file path
const SETTINGS_PATH: String = "user://settings.cfg"

## Default settings values
var defaults: Dictionary = {
	# Colony settings
	"initial_ant_count": 20,
	"max_ants": 100,
	"ant_spawn_cost": 10.0,
	"spawn_rate": 0.5,
	"initial_food_stored": 100.0,
	# Food settings
	"food_cluster_count": 6,
	"food_per_cluster": 200.0,
	"food_sources_per_cluster": 8,
	"cluster_radius": 100.0,
	# World settings
	"world_width": 2000.0,
	"world_height": 2000.0,
	"time_scale": 1.0,
	# Ant sensing ranges
	"sensor_distance": 90.0,          # Pheromone/scent sensing range
	"sight_sense_range": 60.0,        # Visual detection range for food/ants
	"obstacle_sense_range": 35.0,     # Obstacle detection range
	"ant_direction_sense_range": 80.0, # Social navigation range
	"pickup_range": 20.0,             # Item pickup range
	# Ant direction sensing (social navigation)
	"ant_direction_carrying_boost": 2.0,
	"ant_direction_decay": 0.5,
	# Ant movement
	"ant_base_speed": 80.0,
	"ant_max_turn_rate": 9.42,  # PI * 3.0
}

## Default behavior weights per state
var default_behavior_weights: Dictionary = {
	"Search": {
		"pheromone": 0.5,
		"random": 0.3,
		"nest": -0.1,
		"ant_direction": 0.2,
		"food": 0.0,
		"colony_proximity": -0.1,
	},
	"Harvest": {
		"pheromone": 0.2,
		"random": 0.1,
		"nest": 0.0,
		"ant_direction": 0.0,
		"food": 0.7,
		"colony_proximity": 0.0,
	},
	"Return": {
		"pheromone": 0.4,
		"random": 0.0,
		"nest": 0.5,
		"ant_direction": 0.0,
		"food": 0.0,
		"colony_proximity": 0.1,
	},
	"GoHome": {
		"pheromone": 0.3,
		"random": 0.0,
		"nest": 0.6,
		"ant_direction": 0.0,
		"food": 0.0,
		"colony_proximity": 0.1,
	},
	"Rest": {
		"pheromone": 0.0,
		"random": 0.0,
		"nest": 0.0,
		"ant_direction": 0.0,
		"food": 0.0,
		"colony_proximity": 0.0,
	},
}

## Custom behavior weights (persisted)
var behavior_weights: Dictionary = {}

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
		behavior_weights = default_behavior_weights.duplicate(true)
		save_settings()
		return

	# Load each setting, falling back to default if not present
	settings.clear()
	for key: String in defaults:
		settings[key] = _config.get_value("settings", key, defaults[key])

	# Load behavior weights
	behavior_weights.clear()
	for state_name: String in default_behavior_weights:
		if _config.has_section_key("behavior_weights", state_name):
			behavior_weights[state_name] = _config.get_value("behavior_weights", state_name, {})
		else:
			behavior_weights[state_name] = default_behavior_weights[state_name].duplicate()

	settings_changed.emit()


## Save current settings to file
func save_settings() -> void:
	for key: String in settings:
		_config.set_value("settings", key, settings[key])

	# Save behavior weights
	for state_name: String in behavior_weights:
		_config.set_value("behavior_weights", state_name, behavior_weights[state_name])

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
	behavior_weights = default_behavior_weights.duplicate(true)
	save_settings()


## Get all settings as a dictionary
func get_all_settings() -> Dictionary:
	return settings.duplicate()


## Get behavior weights for a specific state
## Returns empty dictionary if state not found (action will use its own defaults)
func get_behavior_weights(state_name: String) -> Dictionary:
	if behavior_weights.has(state_name):
		return behavior_weights[state_name].duplicate()
	if default_behavior_weights.has(state_name):
		return default_behavior_weights[state_name].duplicate()
	return {}


## Set behavior weights for a specific state
func set_behavior_weights(state_name: String, weights: Dictionary) -> void:
	behavior_weights[state_name] = weights.duplicate()


## Get all behavior weights
func get_all_behavior_weights() -> Dictionary:
	return behavior_weights.duplicate(true)


## Reset behavior weights to defaults
func reset_behavior_weights() -> void:
	behavior_weights = default_behavior_weights.duplicate(true)
	save_settings()
