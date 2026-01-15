extends Node2D
## Main scene controller - connects UI and manages the simulation

@onready var world = $World  # SimulationWorld
@onready var colony = $World/Colony  # Colony

# UI References
@onready var ant_count_label: Label = $UI/StatsPanel/VBox/AntCount
@onready var food_stored_label: Label = $UI/StatsPanel/VBox/FoodStored
@onready var food_collected_label: Label = $UI/StatsPanel/VBox/FoodCollected
@onready var efficiency_label: Label = $UI/StatsPanel/VBox/Efficiency
@onready var sim_time_label: Label = $UI/StatsPanel/VBox/SimTime
@onready var play_pause_btn: Button = $UI/StatsPanel/VBox/Controls/PlayPause
@onready var speed_slider: HSlider = $UI/StatsPanel/VBox/Controls/SpeedSlider
@onready var spawn_food_btn: Button = $UI/StatsPanel/VBox/SpawnFood
@onready var toggle_efficiency_btn: Button = $UI/StatsPanel/VBox/ToggleEfficiency

# Cost panel references
@onready var cost_panel: PanelContainer = $UI/CostPanel
@onready var cost_efficiency_label: Label = $UI/CostPanel/VBox/EfficiencyHeader/Value
@onready var cost_food_energy_label: Label = $UI/CostPanel/VBox/FoodPerEnergy/Value
@onready var category_list: VBoxContainer = $UI/CostPanel/VBox/ScrollContainer/CategoryList
@onready var top_costs_list: VBoxContainer = $UI/CostPanel/VBox/TopCosts/List
@onready var behavior_list: VBoxContainer = $UI/CostPanel/VBox/BehaviorBreakdown/List

var camera: Camera2D

# Category colors for visualization
var category_colors: Dictionary = {
	"movement": Color.CORNFLOWER_BLUE,
	"sensing": Color.MEDIUM_PURPLE,
	"pheromone": Color.MEDIUM_SEA_GREEN,
	"interaction": Color.CORAL,
	"metabolism": Color.SANDY_BROWN,
}


func _ready() -> void:
	camera = $Camera2D

	# Connect UI signals
	play_pause_btn.pressed.connect(_on_play_pause_pressed)
	speed_slider.value_changed.connect(_on_speed_changed)
	spawn_food_btn.pressed.connect(_on_spawn_food_pressed)
	toggle_efficiency_btn.pressed.connect(_on_toggle_efficiency_pressed)

	# Set up colony with default forager behavior
	var forager_behavior = _create_default_forager()
	colony.behavior_program = forager_behavior

	# Register colony with world
	world.register_colony(colony)

	# Spawn some initial food
	_spawn_initial_food()

	# Connect colony signals
	colony.colony_stats_updated.connect(_update_ui)

	# Start simulation
	GameManager.start_simulation()
	_update_play_button()


func _process(_delta: float) -> void:
	# Camera controls
	_handle_camera_input()

	# Update UI periodically
	if Engine.get_process_frames() % 10 == 0:
		_update_ui()

	# Update cost panel if visible
	if cost_panel.visible and Engine.get_process_frames() % 30 == 0:
		_update_cost_panel()


func _handle_camera_input() -> void:
	var move_speed = 500.0 / camera.zoom.x
	var move = Vector2.ZERO

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


func _spawn_initial_food() -> void:
	# Spawn several food clusters around the map
	var cluster_positions = [
		Vector2(400, 400),
		Vector2(1600, 400),
		Vector2(400, 1600),
		Vector2(1600, 1600),
		Vector2(1000, 200),
		Vector2(1000, 1800),
	]

	for pos in cluster_positions:
		world.spawn_food_cluster(pos, 8, 100.0, 200.0)


func _update_ui() -> void:
	var stats = colony.get_stats()

	ant_count_label.text = "Ants: %d / %d" % [stats.ant_count, stats.max_ants]
	food_stored_label.text = "Food Stored: %.0f" % stats.food_stored
	food_collected_label.text = "Total Collected: %.0f" % stats.total_food_collected
	efficiency_label.text = "Efficiency: %.2f food/s" % stats.colony_efficiency
	sim_time_label.text = "Time: %.1fs" % GameManager.simulation_time

	# Update global efficiency
	var global_eff = GameManager.get_efficiency_ratio()
	if global_eff > 0:
		efficiency_label.text += " (%.3f f/e)" % global_eff


func _update_cost_panel() -> void:
	if not is_instance_valid(CostTracker):
		return

	var report = CostTracker.get_efficiency_report()

	# Update main metrics
	var eff = report.get("global_efficiency", 0.0)
	cost_efficiency_label.text = "%.2f" % eff
	if eff > 50:
		cost_efficiency_label.add_theme_color_override("font_color", Color.GREEN)
	elif eff > 20:
		cost_efficiency_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		cost_efficiency_label.add_theme_color_override("font_color", Color.RED)

	var food = report.get("total_food", 0.0)
	var energy = maxf(report.get("total_energy", 0.001), 0.001)
	cost_food_energy_label.text = "%.4f" % (food / energy)

	# Update category breakdown
	_update_category_list(report)

	# Update top costs
	_update_top_costs_list()

	# Update behavior breakdown
	_update_behavior_list(report)


func _update_category_list(report: Dictionary) -> void:
	# Clear existing
	for child in category_list.get_children():
		child.queue_free()

	var categories = report.get("categories", {})
	var total_cost = maxf(report.get("total_energy", 0.001), 0.001)

	for category_name in categories:
		var cat_data = categories[category_name]
		var cat_cost = cat_data.get("total_cost", 0.0)
		var percent = (cat_cost / total_cost) * 100.0 if total_cost > 0 else 0.0

		var row = HBoxContainer.new()

		var color_rect = ColorRect.new()
		color_rect.custom_minimum_size = Vector2(10, 10)
		color_rect.color = category_colors.get(category_name, Color.GRAY)
		row.add_child(color_rect)

		var name_label = Label.new()
		name_label.text = " %s: %.1f (%.0f%%)" % [category_name.capitalize(), cat_cost, percent]
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		category_list.add_child(row)


func _update_top_costs_list() -> void:
	# Clear existing
	for child in top_costs_list.get_children():
		child.queue_free()

	var costs = CostTracker.get_action_cost_comparison()

	for i in range(min(5, costs.size())):
		var item = costs[i]
		var label = Label.new()
		label.text = "%s: %.1f (%.1f%%)" % [item.get("action", "?"), item.get("total", 0.0), item.get("percent", 0.0)]
		label.add_theme_font_size_override("font_size", 11)
		top_costs_list.add_child(label)


func _update_behavior_list(report: Dictionary) -> void:
	# Clear existing
	for child in behavior_list.get_children():
		child.queue_free()

	var behaviors = report.get("behaviors", {})

	for program_name in behaviors:
		var data = behaviors[program_name]
		var label = Label.new()
		var eff_val = data.get("efficiency", 0.0)
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
	# Spawn a food cluster at a random position
	var pos = Vector2(
		randf_range(200, world.world_width - 200),
		randf_range(200, world.world_height - 200)
	)
	world.spawn_food_cluster(pos, 10, 80.0, 300.0)


func _on_toggle_efficiency_pressed() -> void:
	cost_panel.visible = not cost_panel.visible
	toggle_efficiency_btn.text = "Hide Efficiency Panel" if cost_panel.visible else "Show Efficiency Panel"


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				_on_play_pause_pressed()
			KEY_F:
				_on_spawn_food_pressed()
			KEY_R:
				# Reset simulation
				get_tree().reload_current_scene()
			KEY_E:
				_on_toggle_efficiency_pressed()


## Create the default forager behavior inline to avoid class loading issues
func _create_default_forager():
	var BehaviorProgramScript = load("res://scripts/behavior/behavior_program.gd")
	var BehaviorStateScript = load("res://scripts/behavior/behavior_state.gd")
	var BehaviorTransitionScript = load("res://scripts/behavior/behavior_transition.gd")
	var MoveActionScript = load("res://scripts/behavior/actions/move_action.gd")
	var PheromoneActionScript = load("res://scripts/behavior/actions/pheromone_action.gd")
	var PickupActionScript = load("res://scripts/behavior/actions/pickup_action.gd")
	var DropActionScript = load("res://scripts/behavior/actions/drop_action.gd")
	var NearbyConditionScript = load("res://scripts/behavior/conditions/nearby_condition.gd")
	var CarryingConditionScript = load("res://scripts/behavior/conditions/carrying_condition.gd")
	var DistanceConditionScript = load("res://scripts/behavior/conditions/distance_condition.gd")
	var EnergyConditionScript = load("res://scripts/behavior/conditions/energy_condition.gd")

	var program = BehaviorProgramScript.new()
	program.program_name = "Basic Forager"
	program.description = "A simple foraging behavior"

	# Search state
	var search_state = BehaviorStateScript.new()
	search_state.state_name = "Search"
	search_state.display_color = Color.YELLOW

	var search_move = MoveActionScript.new()
	search_move.move_mode = 9  # WEIGHTED_BLEND
	search_move.pheromone_name = "food_trail"
	search_move.blend_weights = {"pheromone": 0.5, "random": 0.4, "nest": 0.1}
	search_state.tick_actions = [search_move]

	var found_food_trans = BehaviorTransitionScript.new()
	found_food_trans.target_state = "Harvest"
	var food_nearby = NearbyConditionScript.new()
	food_nearby.entity_type = 0  # FOOD
	food_nearby.count_mode = 0   # ANY
	food_nearby.search_radius = 25.0
	found_food_trans.condition = food_nearby
	found_food_trans.priority = 10

	var low_energy_trans = BehaviorTransitionScript.new()
	low_energy_trans.target_state = "Return"
	var low_energy = EnergyConditionScript.new()
	low_energy.compare_mode = 1  # BELOW_PERCENT
	low_energy.threshold = 30.0
	low_energy_trans.condition = low_energy
	low_energy_trans.priority = 5

	search_state.transitions = [found_food_trans, low_energy_trans]

	# Harvest state
	var harvest_state = BehaviorStateScript.new()
	harvest_state.state_name = "Harvest"
	harvest_state.display_color = Color.ORANGE

	var harvest_move = MoveActionScript.new()
	harvest_move.move_mode = 5  # TOWARD_NEAREST_FOOD
	harvest_move.speed_multiplier = 0.8

	var pickup = PickupActionScript.new()
	pickup.pickup_target = 0  # NEAREST_FOOD
	pickup.pickup_range = 15.0

	harvest_state.tick_actions = [harvest_move, pickup]

	var got_food_trans = BehaviorTransitionScript.new()
	got_food_trans.target_state = "Return"
	var carrying = CarryingConditionScript.new()
	carrying.carry_mode = 0  # CARRYING_ANYTHING
	got_food_trans.condition = carrying
	got_food_trans.priority = 10

	var no_food_trans = BehaviorTransitionScript.new()
	no_food_trans.target_state = "Search"
	var no_food = NearbyConditionScript.new()
	no_food.entity_type = 0  # FOOD
	no_food.count_mode = 1   # NONE
	no_food.search_radius = 50.0
	no_food_trans.condition = no_food
	no_food_trans.priority = 5
	no_food_trans.cooldown_ticks = 10

	harvest_state.transitions = [got_food_trans, no_food_trans]

	# Return state
	var return_state = BehaviorStateScript.new()
	return_state.state_name = "Return"
	return_state.display_color = Color.GREEN

	var return_move = MoveActionScript.new()
	return_move.move_mode = 2  # TOWARD_NEST

	var deposit_pheromone = PheromoneActionScript.new()
	deposit_pheromone.pheromone_name = "food_trail"
	deposit_pheromone.deposit_mode = 3  # INVERSELY_TO_DISTANCE
	deposit_pheromone.base_amount = 2.0
	deposit_pheromone.max_amount = 5.0
	deposit_pheromone.reference_distance = 300.0

	return_state.tick_actions = [return_move, deposit_pheromone]

	var at_nest_trans = BehaviorTransitionScript.new()
	at_nest_trans.target_state = "Deposit"
	var at_nest = DistanceConditionScript.new()
	at_nest.target_type = 0  # NEST
	at_nest.compare_mode = 0  # CLOSER_THAN
	at_nest.threshold = 30.0
	at_nest_trans.condition = at_nest
	at_nest_trans.priority = 10

	var lost_food_trans = BehaviorTransitionScript.new()
	lost_food_trans.target_state = "Search"
	var not_carrying = CarryingConditionScript.new()
	not_carrying.carry_mode = 1  # CARRYING_NOTHING
	lost_food_trans.condition = not_carrying
	lost_food_trans.priority = 5

	return_state.transitions = [at_nest_trans, lost_food_trans]

	# Deposit state
	var deposit_state = BehaviorStateScript.new()
	deposit_state.state_name = "Deposit"
	deposit_state.display_color = Color.BLUE

	var drop = DropActionScript.new()
	drop.drop_mode = 1  # DROP_AT_NEST
	drop.nest_threshold = 40.0

	deposit_state.tick_actions = [drop]

	var deposited_trans = BehaviorTransitionScript.new()
	deposited_trans.target_state = "Search"
	var empty_hands = CarryingConditionScript.new()
	empty_hands.carry_mode = 1  # CARRYING_NOTHING
	deposited_trans.condition = empty_hands
	deposited_trans.priority = 10

	deposit_state.transitions = [deposited_trans]

	program.states = [search_state, harvest_state, return_state, deposit_state]
	program.initial_state = "Search"

	return program
