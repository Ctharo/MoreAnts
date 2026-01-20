extends Node2D
## Main scene controller - connects UI and manages the simulation

@onready var world: SimulationWorld = $World
@onready var colony: Colony = $World/Colony

#region UI References
@onready var ant_count_label: Label = $UI/StatsPanel/VBox/AntCount
@onready var food_stored_label: Label = $UI/StatsPanel/VBox/FoodStored
@onready var food_collected_label: Label = $UI/StatsPanel/VBox/FoodCollected
@onready var efficiency_label: Label = $UI/StatsPanel/VBox/Efficiency
@onready var sim_time_label: Label = $UI/StatsPanel/VBox/SimTime
@onready var state_counts_label: Label = $UI/StatsPanel/VBox/StateCounts
@onready var play_pause_btn: Button = $UI/StatsPanel/VBox/Controls/PlayPause
@onready var speed_slider: HSlider = $UI/StatsPanel/VBox/Controls/SpeedSlider
@onready var spawn_food_btn: Button = $UI/StatsPanel/VBox/SpawnFood
@onready var toggle_efficiency_btn: Button = $UI/StatsPanel/VBox/ToggleEfficiency
@onready var toggle_debug_btn: Button = $UI/StatsPanel/VBox/ToggleDebug
@onready var back_to_settings_btn: Button = $UI/StatsPanel/VBox/BackToSettings

@onready var cost_panel: PanelContainer = $UI/CostPanel
@onready var cost_efficiency_label: Label = $UI/CostPanel/VBox/EfficiencyHeader/Value
@onready var cost_food_energy_label: Label = $UI/CostPanel/VBox/FoodPerEnergy/Value
@onready var category_list: VBoxContainer = $UI/CostPanel/VBox/ScrollContainer/CategoryList
@onready var top_costs_list: VBoxContainer = $UI/CostPanel/VBox/TopCosts/List
@onready var behavior_list: VBoxContainer = $UI/CostPanel/VBox/BehaviorBreakdown/List
#endregion

var camera: Camera2D

## Category colors for visualization
var category_colors: Dictionary = {
	"movement": Color.CORNFLOWER_BLUE,
	"sensing": Color.MEDIUM_PURPLE,
	"pheromone": Color.MEDIUM_SEA_GREEN,
	"interaction": Color.CORAL,
	"metabolism": Color.SANDY_BROWN,
}

## Debug mode state
var _debug_mode: bool = false

#region Ant Selection System
## Currently selected ant (persists until clicked elsewhere)
var _selected_ant: Node = null
## Currently hovered ant (temporary, follows mouse)
var _hovered_ant: Node = null
## Radius within which to snap selection to nearest ant
var _selection_snap_radius: float = 30.0
#endregion


func _ready() -> void:
	camera = $Camera2D

	# Connect UI signals
	play_pause_btn.pressed.connect(_on_play_pause_pressed)
	speed_slider.value_changed.connect(_on_speed_changed)
	spawn_food_btn.pressed.connect(_on_spawn_food_pressed)
	toggle_efficiency_btn.pressed.connect(_on_toggle_efficiency_pressed)
	toggle_debug_btn.pressed.connect(_on_toggle_debug_pressed)
	back_to_settings_btn.pressed.connect(_on_back_to_settings_pressed)

	# Apply settings from SettingsManager
	_apply_settings()

	# Set up colony with default forager behavior
	var forager_behavior: BehaviorProgram = _create_default_forager()
	colony.behavior_program = forager_behavior

	# Register colony with world
	world.register_colony(colony)

	# Spawn initial food based on settings
	_spawn_initial_food()
	
	# Spawn some initial obstacles
	_spawn_initial_obstacles()

	# Connect colony signals
	colony.colony_stats_updated.connect(_update_stats_ui)

	# Set initial time scale from settings
	GameManager.set_time_scale(SettingsManager.get_setting("time_scale"))
	speed_slider.value = SettingsManager.get_setting("time_scale")

	# Start simulation
	GameManager.start_simulation()
	_update_play_button()


func _apply_settings() -> void:
	# Apply colony settings
	colony.initial_ant_count = int(SettingsManager.get_setting("initial_ant_count"))
	colony.max_ants = int(SettingsManager.get_setting("max_ants"))
	colony.ant_spawn_cost = SettingsManager.get_setting("ant_spawn_cost")
	colony.spawn_rate = SettingsManager.get_setting("spawn_rate")
	colony.food_stored = SettingsManager.get_setting("initial_food_stored")

	# Apply world settings
	world.world_width = SettingsManager.get_setting("world_width")
	world.world_height = SettingsManager.get_setting("world_height")

	# Center camera on world
	var world_center: Vector2 = Vector2(world.world_width / 2.0, world.world_height / 2.0)
	camera.position = world_center

	# Update nest position to center of world
	colony.nest_position = world_center


func _process(_delta: float) -> void:
	# Camera controls
	_handle_camera_input()
	
	# Update mouse hover for ant selection
	_update_ant_hover()

	# Update time label EVERY frame for smooth counting
	_update_time_label()

	# Update other UI periodically (less frequently)
	if Engine.get_process_frames() % 10 == 0:
		_update_stats_ui()

	# Update cost panel if visible
	if cost_panel.visible and Engine.get_process_frames() % 30 == 0:
		_update_cost_panel()


func _handle_camera_input() -> void:
	var move_speed: float = 500.0 / camera.zoom.x
	var move: Vector2 = Vector2.ZERO

	if Input.is_action_pressed("ui_left"):
		move.x -= 1
	if Input.is_action_pressed("ui_right"):
		move.x += 1
	if Input.is_action_pressed("ui_up"):
		move.y -= 1
	if Input.is_action_pressed("ui_down"):
		move.y += 1

	camera.position += move * move_speed * get_process_delta_time()

	# Zoom with scroll
	if Input.is_action_just_pressed("ui_page_up"):
		camera.zoom *= 1.2
	if Input.is_action_just_pressed("ui_page_down"):
		camera.zoom /= 1.2

	camera.zoom = camera.zoom.clamp(Vector2(0.1, 0.1), Vector2(2.0, 2.0))


#region Ant Selection System
func _update_ant_hover() -> void:
	## Update which ant is being hovered based on mouse position
	var mouse_world_pos: Vector2 = _get_mouse_world_position()
	
	# Find nearest ant within snap radius (adjusted for zoom)
	var snap_radius: float = _selection_snap_radius / camera.zoom.x
	var nearest_ant: Node = colony.find_nearest_ant(mouse_world_pos, snap_radius)
	
	# Update hover state
	if nearest_ant != _hovered_ant:
		# Clear previous hover
		if _hovered_ant != null and is_instance_valid(_hovered_ant):
			_hovered_ant.debug_hovered = false
		
		# Set new hover (but not if it's already selected)
		_hovered_ant = nearest_ant
		if _hovered_ant != null and _hovered_ant != _selected_ant:
			_hovered_ant.debug_hovered = true


func _get_mouse_world_position() -> Vector2:
	## Convert mouse screen position to world position
	var mouse_screen: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var viewport_center: Vector2 = viewport_size / 2.0
	
	# Offset from center, scaled by zoom
	var offset: Vector2 = (mouse_screen - viewport_center) / camera.zoom
	return camera.position + offset


func _select_ant(ant: Node) -> void:
	## Select an ant for persistent debug display
	# Clear previous selection
	if _selected_ant != null and is_instance_valid(_selected_ant):
		_selected_ant.debug_selected = false
	
	# Set new selection
	_selected_ant = ant
	if _selected_ant != null:
		_selected_ant.debug_selected = true
		# Also clear hover on this ant since it's now selected
		_selected_ant.debug_hovered = false


func _clear_selection() -> void:
	## Clear the current ant selection
	if _selected_ant != null and is_instance_valid(_selected_ant):
		_selected_ant.debug_selected = false
	_selected_ant = null


func _handle_ant_click(mouse_world_pos: Vector2) -> void:
	## Handle a click for ant selection
	var snap_radius: float = _selection_snap_radius / camera.zoom.x
	var clicked_ant: Node = colony.find_nearest_ant(mouse_world_pos, snap_radius)
	
	if clicked_ant != null:
		# Clicked on an ant - select it
		_select_ant(clicked_ant)
	else:
		# Clicked on empty space - clear selection
		_clear_selection()
#endregion


func _spawn_initial_food() -> void:
	var cluster_count: int = int(SettingsManager.get_setting("food_cluster_count"))
	var food_per_cluster: float = SettingsManager.get_setting("food_per_cluster")
	var sources_per_cluster: int = int(SettingsManager.get_setting("food_sources_per_cluster"))
	var cluster_radius: float = SettingsManager.get_setting("cluster_radius")

	var world_w: float = world.world_width
	var world_h: float = world.world_height
	var margin: float = 200.0

	# Distribute clusters evenly around the world
	for i: int in range(cluster_count):
		var angle: float = (float(i) / float(cluster_count)) * TAU
		var dist: float = minf(world_w, world_h) * 0.35
		var center: Vector2 = Vector2(world_w / 2.0, world_h / 2.0)
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * dist

		# Clamp to world bounds
		pos.x = clampf(pos.x, margin, world_w - margin)
		pos.y = clampf(pos.y, margin, world_h - margin)

		world.spawn_food_cluster(pos, sources_per_cluster, cluster_radius, food_per_cluster)


func _update_time_label() -> void:
	## Update only the time label (called every frame for smooth counting)
	sim_time_label.text = "Time: %.1fs (x%.1f)" % [GameManager.simulation_time, GameManager.time_scale]


func _update_stats_ui() -> void:
	## Update stat labels (called less frequently)
	var stats: Dictionary = colony.get_stats()

	ant_count_label.text = "Ants: %d / %d" % [stats.ant_count, stats.max_ants]
	food_stored_label.text = "Food Stored: %.0f" % stats.food_stored
	food_collected_label.text = "Total Collected: %.0f" % stats.total_food_collected
	efficiency_label.text = "Efficiency: %.2f food/s" % stats.colony_efficiency

	# Show state counts
	var state_counts: Dictionary = stats.get("state_counts", {})
	var state_str: String = ""
	for state_name: String in state_counts:
		if state_str.length() > 0:
			state_str += ", "
		state_str += "%s:%d" % [state_name.left(3), state_counts[state_name]]
	state_counts_label.text = "States: " + state_str

	# Update global efficiency
	var global_eff: float = GameManager.get_efficiency_ratio()
	if global_eff > 0:
		efficiency_label.text += " (%.3f f/e)" % global_eff


func _update_cost_panel() -> void:
	if not is_instance_valid(CostTracker):
		return

	var report: Dictionary = CostTracker.get_efficiency_report()

	# Update main metrics
	var eff: float = report.get("global_efficiency", 0.0)
	cost_efficiency_label.text = "%.2f" % eff
	if eff > 50:
		cost_efficiency_label.add_theme_color_override("font_color", Color.GREEN)
	elif eff > 20:
		cost_efficiency_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		cost_efficiency_label.add_theme_color_override("font_color", Color.RED)

	var food: float = report.get("total_food", 0.0)
	var energy: float = maxf(report.get("total_energy", 0.001), 0.001)
	cost_food_energy_label.text = "%.4f" % (food / energy)

	# Update category breakdown
	_update_category_list(report)

	# Update top costs
	_update_top_costs_list()

	# Update behavior breakdown
	_update_behavior_list(report)


func _update_category_list(report: Dictionary) -> void:
	# Clear existing
	for child: Node in category_list.get_children():
		child.queue_free()

	var categories: Dictionary = report.get("categories", {})
	var total_cost: float = maxf(report.get("total_energy", 0.001), 0.001)

	for category_name: String in categories:
		var cat_data: Dictionary = categories[category_name]
		var cat_cost: float = cat_data.get("total_cost", 0.0)
		var percent: float = (cat_cost / total_cost) * 100.0 if total_cost > 0 else 0.0

		var row: HBoxContainer = HBoxContainer.new()

		var color_rect: ColorRect = ColorRect.new()
		color_rect.custom_minimum_size = Vector2(10, 10)
		color_rect.color = category_colors.get(category_name, Color.GRAY)
		row.add_child(color_rect)

		var name_label: Label = Label.new()
		name_label.text = " %s: %.1f (%.0f%%)" % [category_name.capitalize(), cat_cost, percent]
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		category_list.add_child(row)


func _update_top_costs_list() -> void:
	# Clear existing
	for child: Node in top_costs_list.get_children():
		child.queue_free()

	var costs: Array[Dictionary] = CostTracker.get_action_cost_comparison()

	for i: int in range(mini(5, costs.size())):
		var item: Dictionary = costs[i]
		var label: Label = Label.new()
		label.text = "%s: %.1f (%.1f%%)" % [item.get("action", "?"), item.get("total", 0.0), item.get("percent", 0.0)]
		label.add_theme_font_size_override("font_size", 11)
		top_costs_list.add_child(label)


func _update_behavior_list(report: Dictionary) -> void:
	# Clear existing
	for child: Node in behavior_list.get_children():
		child.queue_free()

	var behaviors: Dictionary = report.get("behaviors", {})

	for program_name: String in behaviors:
		var data: Dictionary = behaviors[program_name]
		var label: Label = Label.new()
		var eff_val: float = data.get("efficiency", 0.0)
		label.text = "%s: Eff=%.2f, Cost=%.1f" % [program_name, eff_val, data.get("total_cost", 0.0)]
		label.add_theme_font_size_override("font_size", 11)
		if eff_val > 50:
			label.add_theme_color_override("font_color", Color.GREEN)
		elif eff_val > 20:
			label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			label.add_theme_color_override("font_color", Color.ORANGE_RED)
		behavior_list.add_child(label)


func _on_play_pause_pressed() -> void:
	GameManager.toggle_simulation()
	_update_play_button()


func _update_play_button() -> void:
	play_pause_btn.text = "Pause" if GameManager.is_running else "Play"


func _on_speed_changed(value: float) -> void:
	GameManager.set_time_scale(value)


func _on_spawn_food_pressed() -> void:
	var cluster_radius: float = SettingsManager.get_setting("cluster_radius")
	var food_per_cluster: float = SettingsManager.get_setting("food_per_cluster")
	var sources_per_cluster: int = int(SettingsManager.get_setting("food_sources_per_cluster"))

	# Spawn a food cluster at a random position
	var pos: Vector2 = Vector2(
		randf_range(200, world.world_width - 200),
		randf_range(200, world.world_height - 200)
	)
	world.spawn_food_cluster(pos, sources_per_cluster, cluster_radius, food_per_cluster)


func _on_toggle_efficiency_pressed() -> void:
	cost_panel.visible = not cost_panel.visible
	toggle_efficiency_btn.text = "Hide Efficiency Panel" if cost_panel.visible else "Show Efficiency Panel"


func _on_toggle_debug_pressed() -> void:
	_debug_mode = not _debug_mode
	Ant.set_all_debug(_debug_mode)
	toggle_debug_btn.text = "Hide Debug (D)" if _debug_mode else "Show Debug (D)"


func _on_back_to_settings_pressed() -> void:
	GameManager.reset_simulation()
	CostTracker.reset()
	get_tree().change_scene_to_file("res://scenes/game_entry.tscn")


func _input(event: InputEvent) -> void:
	# Handle mouse input for ant selection
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				var mouse_world_pos: Vector2 = _get_mouse_world_position()
				_handle_ant_click(mouse_world_pos)
	
	# Handle keyboard input
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				_on_play_pause_pressed()
			KEY_F:
				_on_spawn_food_pressed()
			KEY_O:
				_on_spawn_obstacle_pressed()
			KEY_R:
				# Reset simulation
				get_tree().reload_current_scene()
			KEY_E:
				_on_toggle_efficiency_pressed()
			KEY_D:
				_on_toggle_debug_pressed()
			KEY_1:
				# Toggle sensor visualization only
				Ant.toggle_sensor_debug()
			KEY_2:
				# Toggle pheromone sample visualization only
				Ant.toggle_pheromone_debug()
			KEY_3:
				# Toggle state color visualization only
				Ant.toggle_state_debug()
			KEY_ESCAPE:
				_on_back_to_settings_pressed()


func _on_spawn_obstacle_pressed() -> void:
	## Spawn a random obstacle at a random position
	var pos: Vector2 = Vector2(
		randf_range(300, world.world_width - 300),
		randf_range(300, world.world_height - 300)
	)
	
	# Avoid spawning too close to nest
	var nest_pos: Vector2 = colony.nest_position
	if pos.distance_to(nest_pos) < 150:
		pos = nest_pos + (pos - nest_pos).normalized() * 200
	
	# Random shape
	if randf() > 0.5:
		world.spawn_obstacle_circle(pos, randf_range(20, 50))
	else:
		var size: Vector2 = Vector2(randf_range(40, 100), randf_range(20, 40))
		world.spawn_obstacle_rect(pos, size, randf_range(0, 360))


func _spawn_initial_obstacles() -> void:
	## Spawn some initial obstacles to create interesting navigation challenges
	var world_w: float = world.world_width
	var world_h: float = world.world_height
	var center: Vector2 = Vector2(world_w / 2.0, world_h / 2.0)
	
	# Create a ring of obstacles around the nest (with gaps for ants to pass)
	var ring_radius: float = 200.0
	var num_obstacles: int = 6
	for i: int in range(num_obstacles):
		var angle: float = (float(i) / float(num_obstacles)) * TAU
		# Skip some positions to create gaps
		if i % 2 == 0:
			continue
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
		world.spawn_obstacle_circle(pos, randf_range(25, 40))
	
	# Add some random obstacles in the outer areas
	for i: int in range(8):
		var angle: float = randf() * TAU
		var dist: float = randf_range(400, minf(world_w, world_h) * 0.4)
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * dist
		
		if randf() > 0.5:
			world.spawn_obstacle_circle(pos, randf_range(20, 45))
		else:
			var size: Vector2 = Vector2(randf_range(50, 100), randf_range(15, 30))
			world.spawn_obstacle_rect(pos, size, randf_range(0, 180))


## Create the default forager behavior inline to avoid class loading issues
## Improved version with better state transitions and energy thresholds
func _create_default_forager() -> BehaviorProgram:
	var BehaviorProgramScript: Script = load("res://scripts/behavior/behavior_program.gd")
	var BehaviorStateScript: Script = load("res://scripts/behavior/behavior_state.gd")
	var BehaviorTransitionScript: Script = load("res://scripts/behavior/behavior_transition.gd")
	var MoveActionScript: Script = load("res://scripts/behavior/actions/move_action.gd")
	var PheromoneActionScript: Script = load("res://scripts/behavior/actions/pheromone_action.gd")
	var CarryingConditionScript: Script = load("res://scripts/behavior/conditions/carrying_condition.gd")
	var DistanceConditionScript: Script = load("res://scripts/behavior/conditions/distance_condition.gd")
	var EnergyConditionScript: Script = load("res://scripts/behavior/conditions/energy_condition.gd")

	var program: BehaviorProgram = BehaviorProgramScript.new()
	program.program_name = "Basic Forager"
	program.description = "Event-driven foraging with dual pheromone trails. Pickup/drop are automatic on contact/nest entry."

	#region Search State - Explore and deposit home_trail
	var search_state: BehaviorState = BehaviorStateScript.new()
	search_state.state_name = "Search"
	search_state.display_color = Color.YELLOW

	var search_move: MoveAction = MoveActionScript.new()
	search_move.move_mode = MoveAction.MoveMode.WEIGHTED_BLEND
	search_move.pheromone_name = "food_trail"
	search_move.blend_weights = {"pheromone": 0.6, "random": 0.3, "nest": -0.1}

	# Deposit home_trail while searching so ants can find their way back
	var search_home_pheromone: PheromoneAction = PheromoneActionScript.new()
	search_home_pheromone.pheromone_name = "home_trail"
	search_home_pheromone.deposit_mode = PheromoneAction.DepositMode.INVERSELY_TO_DISTANCE
	search_home_pheromone.base_amount = 3.0
	search_home_pheromone.max_amount = 8.0
	search_home_pheromone.reference_distance = 400.0

	search_state.tick_actions = [search_move, search_home_pheromone] as Array[BehaviorAction]

	# Transition to Return when carrying (triggered by pickup event)
	var carrying_trans: BehaviorTransition = BehaviorTransitionScript.new()
	carrying_trans.target_state = "Return"
	var carrying: CarryingCondition = CarryingConditionScript.new()
	carrying.carry_mode = CarryingCondition.CarryMode.CARRYING_ANYTHING
	carrying_trans.condition = carrying
	carrying_trans.priority = 10

	# Transition to GoHome when energy is low (30% threshold)
	var low_energy_trans: BehaviorTransition = BehaviorTransitionScript.new()
	low_energy_trans.target_state = "GoHome"
	var low_energy: EnergyCondition = EnergyConditionScript.new()
	low_energy.compare_mode = EnergyCondition.CompareMode.BELOW_PERCENT
	low_energy.threshold = 30.0
	low_energy_trans.condition = low_energy
	low_energy_trans.priority = 5

	search_state.transitions = [carrying_trans, low_energy_trans] as Array[BehaviorTransition]
	#endregion

	#region Harvest State - Move toward food (pickup is event-triggered on contact)
	var harvest_state: BehaviorState = BehaviorStateScript.new()
	harvest_state.state_name = "Harvest"
	harvest_state.display_color = Color.ORANGE

	var harvest_move: MoveAction = MoveActionScript.new()
	harvest_move.move_mode = MoveAction.MoveMode.TOWARD_NEAREST_FOOD
	harvest_move.speed_multiplier = 1.0

	# Still deposit home trail while harvesting
	var harvest_home_pheromone: PheromoneAction = PheromoneActionScript.new()
	harvest_home_pheromone.pheromone_name = "home_trail"
	harvest_home_pheromone.deposit_mode = PheromoneAction.DepositMode.CONSTANT
	harvest_home_pheromone.base_amount = 2.0

	harvest_state.tick_actions = [harvest_move, harvest_home_pheromone] as Array[BehaviorAction]

	# Pickup triggers Return automatically, but keep transition as fallback
	var got_food_trans: BehaviorTransition = BehaviorTransitionScript.new()
	got_food_trans.target_state = "Return"
	var has_food: CarryingCondition = CarryingConditionScript.new()
	has_food.carry_mode = CarryingCondition.CarryMode.CARRYING_ANYTHING
	got_food_trans.condition = has_food
	got_food_trans.priority = 10

	harvest_state.transitions = [got_food_trans] as Array[BehaviorTransition]
	#endregion

	#region Return State - Head home while depositing food_trail
	var return_state: BehaviorState = BehaviorStateScript.new()
	return_state.state_name = "Return"
	return_state.display_color = Color.GREEN

	var return_move: MoveAction = MoveActionScript.new()
	return_move.move_mode = MoveAction.MoveMode.WEIGHTED_BLEND
	return_move.pheromone_name = "home_trail"
	return_move.blend_weights = {"pheromone": 0.5, "nest": 0.5, "random": 0.0}

	# Deposit food_trail so other ants can find the food source
	var deposit_food_pheromone: PheromoneAction = PheromoneActionScript.new()
	deposit_food_pheromone.pheromone_name = "food_trail"
	deposit_food_pheromone.deposit_mode = PheromoneAction.DepositMode.CONSTANT
	deposit_food_pheromone.base_amount = 4.0  # Constant strong trail
	deposit_food_pheromone.max_amount = 6.0

	return_state.tick_actions = [return_move, deposit_food_pheromone] as Array[BehaviorAction]

	# Deposit happens automatically on nest entry; transition to Search when no longer carrying
	var deposited_trans: BehaviorTransition = BehaviorTransitionScript.new()
	deposited_trans.target_state = "Search"
	var empty_hands: CarryingCondition = CarryingConditionScript.new()
	empty_hands.carry_mode = CarryingCondition.CarryMode.CARRYING_NOTHING
	deposited_trans.condition = empty_hands
	deposited_trans.priority = 10

	return_state.transitions = [deposited_trans] as Array[BehaviorTransition]
	#endregion

	#region GoHome State - For low energy ants returning without food
	var go_home_state: BehaviorState = BehaviorStateScript.new()
	go_home_state.state_name = "GoHome"
	go_home_state.display_color = Color.ORANGE_RED

	var go_home_move: MoveAction = MoveActionScript.new()
	go_home_move.move_mode = MoveAction.MoveMode.WEIGHTED_BLEND
	go_home_move.pheromone_name = "home_trail"
	go_home_move.blend_weights = {"pheromone": 0.4, "nest": 0.6, "random": 0.0}

	go_home_state.tick_actions = [go_home_move] as Array[BehaviorAction]

	# Transition to Rest when at nest
	var at_nest_trans: BehaviorTransition = BehaviorTransitionScript.new()
	at_nest_trans.target_state = "Rest"
	var at_nest: DistanceCondition = DistanceConditionScript.new()
	at_nest.target_type = DistanceCondition.TargetType.NEST
	at_nest.compare_mode = DistanceCondition.CompareMode.CLOSER_THAN
	at_nest.threshold = 50.0
	at_nest_trans.condition = at_nest
	at_nest_trans.priority = 10

	go_home_state.transitions = [at_nest_trans] as Array[BehaviorTransition]
	#endregion

	#region Rest State - Wait at nest until energy restored (lowered threshold!)
	var rest_state: BehaviorState = BehaviorStateScript.new()
	rest_state.state_name = "Rest"
	rest_state.display_color = Color.LIGHT_BLUE

	# Slow movement while resting (milling around the nest)
	var rest_move: MoveAction = MoveActionScript.new()
	rest_move.move_mode = MoveAction.MoveMode.RANDOM_WALK
	rest_move.speed_multiplier = 0.1  # Very slow, not stopped
	rest_move.random_turn_rate = 0.5

	rest_state.tick_actions = [rest_move] as Array[BehaviorAction]

	# Transition back to Search when energy is above 60% (lowered from 80%)
	var rested_trans: BehaviorTransition = BehaviorTransitionScript.new()
	rested_trans.target_state = "Search"
	var high_energy: EnergyCondition = EnergyConditionScript.new()
	high_energy.compare_mode = EnergyCondition.CompareMode.ABOVE_PERCENT
	high_energy.threshold = 60.0  # Lowered from 80%
	rested_trans.condition = high_energy
	rested_trans.priority = 10

	rest_state.transitions = [rested_trans] as Array[BehaviorTransition]
	#endregion

	program.states = [search_state, harvest_state, return_state, go_home_state, rest_state] as Array[BehaviorState]
	program.initial_state = "Search"

	return program
