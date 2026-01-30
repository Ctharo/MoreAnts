extends Control
## SettingsScreen - Pre-game configuration screen with persistent settings
## Includes tabs for General Settings, Ant Senses, and Behavior Weights

signal play_requested

#region UI References - General Settings
@onready var tab_container: TabContainer = %TabContainer
@onready var initial_ants_spin: SpinBox = %InitialAntsSpinBox
@onready var max_ants_spin: SpinBox = %MaxAntsSpinBox
@onready var spawn_cost_spin: SpinBox = %SpawnCostSpinBox
@onready var spawn_rate_spin: SpinBox = %SpawnRateSpinBox
@onready var initial_food_spin: SpinBox = %InitialFoodSpinBox
@onready var cluster_count_spin: SpinBox = %ClusterCountSpinBox
@onready var food_per_cluster_spin: SpinBox = %FoodPerClusterSpinBox
@onready var sources_per_cluster_spin: SpinBox = %SourcesPerClusterSpinBox
@onready var cluster_radius_spin: SpinBox = %ClusterRadiusSpinBox
@onready var world_width_spin: SpinBox = %WorldWidthSpinBox
@onready var world_height_spin: SpinBox = %WorldHeightSpinBox
@onready var time_scale_spin: SpinBox = %TimeScaleSpinBox
@onready var play_button: Button = %PlayButton
@onready var reset_button: Button = %ResetButton
@onready var reset_weights_button: Button = %ResetWeightsButton
#endregion

#region UI References - Ant Senses
@onready var senses_vbox: VBoxContainer = %SensesVBox
#endregion

#region UI References - Behavior Weights
@onready var behavior_vbox: VBoxContainer = %BehaviorVBox
#endregion

#region Sense Setting Controls
## Stores references to sense spinboxes: setting_key -> SpinBox
var _sense_spinboxes: Dictionary = {}

## Sense settings configuration: key -> {label, min, max, step, tooltip}
var _sense_settings_config: Dictionary = {
	"sensor_distance": {
		"label": "Scent/Pheromone Range",
		"min": 20.0,
		"max": 200.0,
		"step": 5.0,
		"tooltip": "How far ants can detect pheromone trails (chemical sensing)",
	},
	"sight_sense_range": {
		"label": "Visual Range",
		"min": 10.0,
		"max": 150.0,
		"step": 5.0,
		"tooltip": "How far ants can see food and other ants",
	},
	"obstacle_sense_range": {
		"label": "Obstacle Detection Range",
		"min": 10.0,
		"max": 100.0,
		"step": 5.0,
		"tooltip": "How far ahead ants detect obstacles for avoidance",
	},
	"ant_direction_sense_range": {
		"label": "Social Sensing Range",
		"min": 20.0,
		"max": 200.0,
		"step": 5.0,
		"tooltip": "Range for observing other ants' movement directions",
	},
	"pickup_range": {
		"label": "Pickup Range",
		"min": 5.0,
		"max": 50.0,
		"step": 2.0,
		"tooltip": "How close an ant must be to pick up food",
	},
	"ant_base_speed": {
		"label": "Base Speed",
		"min": 20.0,
		"max": 200.0,
		"step": 5.0,
		"tooltip": "Default movement speed for ants",
	},
	"ant_max_turn_rate": {
		"label": "Max Turn Rate",
		"min": 1.0,
		"max": 15.0,
		"step": 0.5,
		"tooltip": "How quickly ants can change direction (radians/sec)",
	},
	"ant_direction_carrying_boost": {
		"label": "Carrying Direction Boost",
		"min": 0.5,
		"max": 5.0,
		"step": 0.25,
		"tooltip": "How much more weight carrying ants have in social navigation hints",
	},
	"ant_direction_decay": {
		"label": "Direction Hint Decay",
		"min": 0.1,
		"max": 1.0,
		"step": 0.05,
		"tooltip": "How quickly direction hints decay with distance (lower = faster decay)",
	},
}
#endregion

#region Behavior Weight Controls
## Stores references to all weight spinboxes: state_name -> weight_name -> SpinBox
var _weight_spinboxes: Dictionary = {}

## State display colors for visual organization
var _state_colors: Dictionary = {
	"Search": Color(0.9, 0.9, 0.3, 1),
	"Harvest": Color(1.0, 0.6, 0.2, 1),
	"Return": Color(0.3, 0.9, 0.3, 1),
	"GoHome": Color(1.0, 0.4, 0.3, 1),
	"Rest": Color(0.5, 0.7, 1.0, 1),
}

## Weight descriptions for tooltips
var _weight_descriptions: Dictionary = {
	"pheromone": "Follow pheromone trails",
	"random": "Random exploration movement",
	"nest": "Move toward/away from nest (negative = away)",
	"ant_direction": "Follow other ants' movement hints",
	"food": "Move toward detected food",
	"colony_proximity": "Trail evaluation based on nest direction",
}
#endregion


func _ready() -> void:
	_connect_signals()
	_load_settings_to_ui()
	_build_senses_ui()
	_build_behavior_weights_ui()


func _connect_signals() -> void:
	play_button.pressed.connect(_on_play_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	reset_weights_button.pressed.connect(_on_reset_weights_pressed)

	# Connect all spinboxes to save on change
	initial_ants_spin.value_changed.connect(_on_setting_changed.bind("initial_ant_count"))
	max_ants_spin.value_changed.connect(_on_setting_changed.bind("max_ants"))
	spawn_cost_spin.value_changed.connect(_on_setting_changed.bind("ant_spawn_cost"))
	spawn_rate_spin.value_changed.connect(_on_setting_changed.bind("spawn_rate"))
	initial_food_spin.value_changed.connect(_on_setting_changed.bind("initial_food_stored"))
	cluster_count_spin.value_changed.connect(_on_setting_changed.bind("food_cluster_count"))
	food_per_cluster_spin.value_changed.connect(_on_setting_changed.bind("food_per_cluster"))
	sources_per_cluster_spin.value_changed.connect(_on_setting_changed.bind("food_sources_per_cluster"))
	cluster_radius_spin.value_changed.connect(_on_setting_changed.bind("cluster_radius"))
	world_width_spin.value_changed.connect(_on_setting_changed.bind("world_width"))
	world_height_spin.value_changed.connect(_on_setting_changed.bind("world_height"))
	time_scale_spin.value_changed.connect(_on_setting_changed.bind("time_scale"))


func _load_settings_to_ui() -> void:
	initial_ants_spin.value = SettingsManager.get_setting("initial_ant_count")
	max_ants_spin.value = SettingsManager.get_setting("max_ants")
	spawn_cost_spin.value = SettingsManager.get_setting("ant_spawn_cost")
	spawn_rate_spin.value = SettingsManager.get_setting("spawn_rate")
	initial_food_spin.value = SettingsManager.get_setting("initial_food_stored")
	cluster_count_spin.value = SettingsManager.get_setting("food_cluster_count")
	food_per_cluster_spin.value = SettingsManager.get_setting("food_per_cluster")
	sources_per_cluster_spin.value = SettingsManager.get_setting("food_sources_per_cluster")
	cluster_radius_spin.value = SettingsManager.get_setting("cluster_radius")
	world_width_spin.value = SettingsManager.get_setting("world_width")
	world_height_spin.value = SettingsManager.get_setting("world_height")
	time_scale_spin.value = SettingsManager.get_setting("time_scale")


#region Ant Senses UI Building
func _build_senses_ui() -> void:
	## Dynamically builds the ant sensing controls
	_sense_spinboxes.clear()

	# Group settings by category
	var sensing_keys: Array[String] = [
		"sensor_distance", "sight_sense_range", "obstacle_sense_range",
		"ant_direction_sense_range", "pickup_range"
	]
	var movement_keys: Array[String] = ["ant_base_speed", "ant_max_turn_rate"]
	var social_keys: Array[String] = ["ant_direction_carrying_boost", "ant_direction_decay"]

	# Sensing Ranges section
	_add_section_header(senses_vbox, "Sensing Ranges", Color(0.3, 0.8, 0.3, 1))
	for key: String in sensing_keys:
		_create_sense_row(senses_vbox, key)

	# Separator
	var sep1: HSeparator = HSeparator.new()
	sep1.add_theme_constant_override("separation", 8)
	senses_vbox.add_child(sep1)

	# Movement section
	_add_section_header(senses_vbox, "Movement", Color(0.3, 0.6, 0.9, 1))
	for key: String in movement_keys:
		_create_sense_row(senses_vbox, key)

	# Separator
	var sep2: HSeparator = HSeparator.new()
	sep2.add_theme_constant_override("separation", 8)
	senses_vbox.add_child(sep2)

	# Social Navigation section
	_add_section_header(senses_vbox, "Social Navigation", Color(0.9, 0.6, 0.3, 1))
	for key: String in social_keys:
		_create_sense_row(senses_vbox, key)


func _add_section_header(container: VBoxContainer, title: String, color: Color) -> void:
	var header: Label = Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", color)
	container.add_child(header)


func _create_sense_row(container: VBoxContainer, setting_key: String) -> void:
	## Creates a single sense setting row with label and spinbox
	if not _sense_settings_config.has(setting_key):
		return

	var config: Dictionary = _sense_settings_config[setting_key]
	var current_value: float = SettingsManager.get_setting(setting_key)

	var row: HBoxContainer = HBoxContainer.new()

	# Label
	var label: Label = Label.new()
	label.text = config.get("label", setting_key)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.tooltip_text = config.get("tooltip", "")
	row.add_child(label)

	# Spinbox
	var spinbox: SpinBox = SpinBox.new()
	spinbox.min_value = config.get("min", 0.0)
	spinbox.max_value = config.get("max", 100.0)
	spinbox.step = config.get("step", 1.0)
	spinbox.value = current_value
	spinbox.custom_minimum_size = Vector2(90, 0)
	spinbox.tooltip_text = config.get("tooltip", "")
	spinbox.value_changed.connect(_on_sense_setting_changed.bind(setting_key))
	row.add_child(spinbox)

	# Store reference
	_sense_spinboxes[setting_key] = spinbox

	container.add_child(row)


func _on_sense_setting_changed(value: float, setting_key: String) -> void:
	SettingsManager.set_setting(setting_key, value)
	SettingsManager.save_settings()
#endregion


#region Behavior Weights UI Building
func _build_behavior_weights_ui() -> void:
	## Dynamically builds the behavior weights controls for each state
	_weight_spinboxes.clear()

	# Get current weights from settings
	var all_weights: Dictionary = SettingsManager.get_all_behavior_weights()

	# Define the order of states for display
	var state_order: Array[String] = ["Search", "Harvest", "Return", "GoHome", "Rest"]

	for state_name: String in state_order:
		if not all_weights.has(state_name):
			continue

		var weights: Dictionary = all_weights[state_name]
		_create_state_section(state_name, weights)


func _create_state_section(state_name: String, weights: Dictionary) -> void:
	## Creates a collapsible section for a behavior state's weights
	_weight_spinboxes[state_name] = {}

	# State header
	var header: Label = Label.new()
	header.text = state_name + " State"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", _state_colors.get(state_name, Color.WHITE))
	behavior_vbox.add_child(header)

	# Container for this state's weights
	var state_container: VBoxContainer = VBoxContainer.new()
	state_container.add_theme_constant_override("separation", 4)
	behavior_vbox.add_child(state_container)

	# Create weight controls
	var weight_order: Array[String] = ["pheromone", "random", "nest", "ant_direction", "food", "colony_proximity"]

	for weight_name: String in weight_order:
		if not weights.has(weight_name):
			continue

		var weight_value: float = weights[weight_name]
		_create_weight_row(state_container, state_name, weight_name, weight_value)

	# Add separator after each state (except last)
	var separator: HSeparator = HSeparator.new()
	separator.add_theme_constant_override("separation", 8)
	behavior_vbox.add_child(separator)


func _create_weight_row(container: VBoxContainer, state_name: String, weight_name: String, value: float) -> void:
	## Creates a single weight row with label and spinbox
	var row: HBoxContainer = HBoxContainer.new()

	# Label with description
	var label: Label = Label.new()
	label.text = _format_weight_name(weight_name)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.tooltip_text = _weight_descriptions.get(weight_name, "")
	row.add_child(label)

	# Spinbox for weight value
	var spinbox: SpinBox = SpinBox.new()
	spinbox.min_value = -2.0
	spinbox.max_value = 2.0
	spinbox.step = 0.05
	spinbox.value = value
	spinbox.custom_minimum_size = Vector2(80, 0)
	spinbox.tooltip_text = _weight_descriptions.get(weight_name, "")
	spinbox.value_changed.connect(_on_weight_changed.bind(state_name, weight_name))
	row.add_child(spinbox)

	# Store reference
	_weight_spinboxes[state_name][weight_name] = spinbox

	container.add_child(row)


func _format_weight_name(weight_name: String) -> String:
	## Converts weight_name to a more readable format
	match weight_name:
		"pheromone":
			return "Pheromone"
		"random":
			return "Random Walk"
		"nest":
			return "Nest Direction"
		"ant_direction":
			return "Ant Direction"
		"food":
			return "Food Direction"
		"colony_proximity":
			return "Colony Proximity"
		_:
			return weight_name.capitalize()
#endregion


#region Signal Handlers
func _on_setting_changed(value: float, key: String) -> void:
	SettingsManager.set_setting(key, value)
	SettingsManager.save_settings()


func _on_weight_changed(value: float, state_name: String, weight_name: String) -> void:
	## Called when a behavior weight spinbox value changes
	var weights: Dictionary = SettingsManager.get_behavior_weights(state_name)
	weights[weight_name] = value
	SettingsManager.set_behavior_weights(state_name, weights)
	SettingsManager.save_settings()


func _on_play_pressed() -> void:
	play_requested.emit()


func _on_reset_pressed() -> void:
	SettingsManager.reset_to_defaults()
	_load_settings_to_ui()
	_refresh_senses_ui()
	_refresh_behavior_weights_ui()


func _on_reset_weights_pressed() -> void:
	## Resets only the behavior weights to defaults
	SettingsManager.reset_behavior_weights()
	_refresh_behavior_weights_ui()
#endregion


func _refresh_senses_ui() -> void:
	## Refreshes all sense spinbox values from settings
	for setting_key: String in _sense_spinboxes:
		var spinbox: SpinBox = _sense_spinboxes[setting_key]
		spinbox.value = SettingsManager.get_setting(setting_key)


func _refresh_behavior_weights_ui() -> void:
	## Refreshes all behavior weight spinbox values from settings
	var all_weights: Dictionary = SettingsManager.get_all_behavior_weights()

	for state_name: String in _weight_spinboxes:
		if not all_weights.has(state_name):
			continue

		var weights: Dictionary = all_weights[state_name]
		var spinboxes: Dictionary = _weight_spinboxes[state_name]

		for weight_name: String in spinboxes:
			if weights.has(weight_name):
				var spinbox: SpinBox = spinboxes[weight_name]
				# Temporarily disconnect to avoid save loops
				spinbox.value = weights[weight_name]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
