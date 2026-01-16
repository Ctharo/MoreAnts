extends Control
## SettingsScreen - Pre-game configuration screen with persistent settings

signal play_requested

#region UI References
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
#endregion


func _ready() -> void:
	_connect_signals()
	_load_settings_to_ui()


func _connect_signals() -> void:
	play_button.pressed.connect(_on_play_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	
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


func _on_setting_changed(value: float, key: String) -> void:
	SettingsManager.set_setting(key, value)
	SettingsManager.save_settings()


func _on_play_pressed() -> void:
	play_requested.emit()


func _on_reset_pressed() -> void:
	SettingsManager.reset_to_defaults()
	_load_settings_to_ui()
