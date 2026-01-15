extends Node2D
## Main scene controller - connects UI and manages the simulation

@onready var world: Node2D = $World  # SimulationWorld
@onready var colony: Node2D = $World/Colony  # Colony

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


func _spawn_initial_food() -> void:
	# Spawn several food clusters around the map
	var cluster_positions: Array[Vector2] = [
		Vector2(400, 400),
		Vector2(1600, 400),
		Vector2(400, 1600),
		Vector2(1600, 1600),
		Vector2(1000, 200),
		Vector2(1000, 1800),
	]

	for pos: Vector2 in cluster_positions:
		world.spawn_food_cluster(pos, 8, 100.0, 200.0)


func _update_ui() -> void:
	var stats: Dictionary = colony.get_stats()

	ant_count_label.text = "Ants: %d / %d" % [stats.ant_count, stats.max_ants]
	food_stored_label.text = "Food Stored: %.0f" % stats.food_stored
	food_collected_label.text = "Total Collected: %.0f" % stats.total_food_collected
	efficiency_label.text = "Efficiency: %.2f food/s" % stats.colony_efficiency
	sim_time_label.text = "Time: %.1fs" % GameManager.simulation_time

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
	# Spawn a food cluster at a random position
	var pos: Vector2 = Vector2(
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
			KEY_P:
				# Toggle pheromone display
				world.toggle_pheromone_display(not world._show_pheromones)


## Create the default forager behavior with proper pheromone usage and energy management
func _create_default_forager() -> BehaviorProgram:
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

	var program: BehaviorProgram = BehaviorProgramScript.new()
	program.program_name = "Basic Forager"
	program.description = "A foraging behavior with energy management"

	#region Search State - Looking for food
	var search_state: BehaviorState = BehaviorStateScript.new()
	search_state.state_name = "Search"
	search_state.display_color = Color.YELLOW

	var search_move: MoveAction = MoveActionScript.new()
	search_move.move_mode = MoveAction.MoveMode.WEIGHTED_BLEND
	search_move.pheromone_name = "food_trail"
	search_move.blend_weights = {"pheromone": 0.6, "random": 0.35, "nest": -0.05}
	search_move.speed_multiplier = 1.0
	search_state.tick_actions = [search_move] as Array[BehaviorAction]

	# Transition: Found food nearby -> Harvest
	var found_food_trans: BehaviorTransition = BehaviorTransitionScript.new()
	found_food_trans.target_state = "Harvest"
	var food_nearby: NearbyCondition = NearbyConditionScript.new()
	food_nearby.entity_type = NearbyCondition.EntityType.FOOD
	food_nearby.count_mode = NearbyCondition.CountMode.ANY
	food_nearby.search_radius = 30.0
	found_food_trans.condition = food_nearby
	found_food_trans.priority = 10

	# Transition: Low energy -> GoHome (to refill)
	var low_energy_search_trans: BehaviorTransition = BehaviorTransitionScript.new()
	low_energy_search_trans.target_state = "GoHome"
	var low_energy_search: EnergyCondition = EnergyConditionScript.new()
	low_energy_search.compare_mode = EnergyCondition.CompareMode.BELOW_PERCENT
	low_energy_search.threshold = 30.0
	low_energy_search_trans.condition = low_energy_search
	low_energy_search_trans.priority = 15  # Higher priority than food

	search_state.transitions = [low_energy_search_trans, found_food_trans] as Array[BehaviorTransition]
	#endregion

	#region Harvest State - Picking up food
	var harvest_state: BehaviorState = BehaviorStateScript.new()
	harvest_state.state_name = "Harvest"
	harvest_state.display_color = Color.ORANGE

	var harvest_move: MoveAction = MoveActionScript.new()
	harvest_move.move_mode = MoveAction.MoveMode.TOWARD_NEAREST_FOOD
	harvest_move.speed_multiplier = 0.7

	var pickup: PickupAction = PickupActionScript.new()
	pickup.pickup_target = PickupAction.PickupTarget.NEAREST_FOOD
	pickup.pickup_range = 20.0

	harvest_state.tick_actions = [harvest_move, pickup] as Array[BehaviorAction]

	# Transition: Got food -> Return
	var got_food_trans: BehaviorTransition = BehaviorTransitionScript.new()
	got_food_trans.target_state = "Return"
	var carrying: CarryingCondition = CarryingConditionScript.new()
	carrying.carry_mode = CarryingCondition.CarryMode.CARRYING_ANYTHING
	got_food_trans.condition = carrying
	got_food_trans.priority = 10

	# Transition: No food around -> Search
	var no_food_trans: BehaviorTransition = BehaviorTransitionScript.new()
	no_food_trans.target_state = "Search"
	var no_food: NearbyCondition = NearbyConditionScript.new()
	no_food.entity_type = NearbyCondition.EntityType.FOOD
	no_food.count_mode = NearbyCondition.CountMode.NONE
	no_food.search_radius = 60.0
	no_food_trans.condition = no_food
	no_food_trans.priority = 5
	no_food_trans.cooldown_ticks = 5

	# Transition: Very low energy -> drop food thoughts, go home
	var critical_energy_harvest: BehaviorTransition = BehaviorTransitionScript.new()
	critical_energy_harvest.target_state = "GoHome"
	var crit_energy_h: EnergyCondition = EnergyConditionScript.new()
	crit_energy_h.compare_mode = EnergyCondition.CompareMode.BELOW_PERCENT
	crit_energy_h.threshold = 20.0
	critical_energy_harvest.condition = crit_energy_h
	critical_energy_harvest.priority = 15

	harvest_state.transitions = [critical_energy_harvest, got_food_trans, no_food_trans] as Array[BehaviorTransition]
	#endregion

	#region Return State - Carrying food back to nest
	var return_state: BehaviorState = BehaviorStateScript.new()
	return_state.state_name = "Return"
	return_state.display_color = Color.GREEN

	var return_move: MoveAction = MoveActionScript.new()
	return_move.move_mode = MoveAction.MoveMode.TOWARD_NEST
	return_move.speed_multiplier = 0.9

	var deposit_pheromone: PheromoneAction = PheromoneActionScript.new()
	deposit_pheromone.pheromone_name = "food_trail"
	deposit_pheromone.deposit_mode = PheromoneAction.DepositMode.CONSTANT
	deposit_pheromone.base_amount = 3.0
	deposit_pheromone.max_amount = 5.0
	deposit_pheromone.use_spread = true
	deposit_pheromone.spread_radius = 1

	return_state.tick_actions = [return_move, deposit_pheromone] as Array[BehaviorAction]

	# Transition: At nest -> Deposit
	var at_nest_trans: BehaviorTransition = BehaviorTransitionScript.new()
	at_nest_trans.target_state = "Deposit"
	var at_nest: DistanceCondition = DistanceConditionScript.new()
	at_nest.target_type = DistanceCondition.TargetType.NEST
	at_nest.compare_mode = DistanceCondition.CompareMode.CLOSER_THAN
	at_nest.threshold = 50.0
	at_nest_trans.condition = at_nest
	at_nest_trans.priority = 10

	# Transition: Lost food somehow -> Search
	var lost_food_trans: BehaviorTransition = BehaviorTransitionScript.new()
	lost_food_trans.target_state = "Search"
	var not_carrying: CarryingCondition = CarryingConditionScript.new()
	not_carrying.carry_mode = CarryingCondition.CarryMode.CARRYING_NOTHING
	lost_food_trans.condition = not_carrying
	lost_food_trans.priority = 5

	return_state.transitions = [at_nest_trans, lost_food_trans] as Array[BehaviorTransition]
	#endregion

	#region Deposit State - At nest, dropping food
	var deposit_state: BehaviorState = BehaviorStateScript.new()
	deposit_state.state_name = "Deposit"
	deposit_state.display_color = Color.BLUE

	var drop: DropAction = DropActionScript.new()
	drop.drop_mode = DropAction.DropMode.DROP_AT_NEST
	drop.nest_threshold = 60.0

	deposit_state.tick_actions = [drop] as Array[BehaviorAction]

	# Transition: Deposited food, low energy -> Rest
	var need_rest_trans: BehaviorTransition = BehaviorTransitionScript.new()
	need_rest_trans.target_state = "Rest"
	var need_rest_cond: EnergyCondition = EnergyConditionScript.new()
	need_rest_cond.compare_mode = EnergyCondition.CompareMode.BELOW_PERCENT
	need_rest_cond.threshold = 70.0
	need_rest_trans.condition = need_rest_cond
	need_rest_trans.priority = 5

	# Transition: Deposited food, good energy -> Search
	var deposited_trans: BehaviorTransition = BehaviorTransitionScript.new()
	deposited_trans.target_state = "Search"
	var empty_hands: CarryingCondition = CarryingConditionScript.new()
	empty_hands.carry_mode = CarryingCondition.CarryMode.CARRYING_NOTHING
	deposited_trans.condition = empty_hands
	deposited_trans.priority = 3

	deposit_state.transitions = [need_rest_trans, deposited_trans] as Array[BehaviorTransition]
	#endregion

	#region GoHome State - Returning to nest for energy (not carrying food)
	var go_home_state: BehaviorState = BehaviorStateScript.new()
	go_home_state.state_name = "GoHome"
	go_home_state.display_color = Color.CYAN

	var go_home_move: MoveAction = MoveActionScript.new()
	go_home_move.move_mode = MoveAction.MoveMode.TOWARD_NEST
	go_home_move.speed_multiplier = 1.0  # Move fast when hungry

	go_home_state.tick_actions = [go_home_move] as Array[BehaviorAction]

	# Transition: At nest -> Rest
	var home_arrived_trans: BehaviorTransition = BehaviorTransitionScript.new()
	home_arrived_trans.target_state = "Rest"
	var home_arrived: DistanceCondition = DistanceConditionScript.new()
	home_arrived.target_type = DistanceCondition.TargetType.NEST
	home_arrived.compare_mode = DistanceCondition.CompareMode.CLOSER_THAN
	home_arrived.threshold = 50.0
	home_arrived_trans.condition = home_arrived
	home_arrived_trans.priority = 10

	go_home_state.transitions = [home_arrived_trans] as Array[BehaviorTransition]
	#endregion

	#region Rest State - Staying at nest to refill energy
	var rest_state: BehaviorState = BehaviorStateScript.new()
	rest_state.state_name = "Rest"
	rest_state.display_color = Color.MEDIUM_PURPLE

	# Stay still at nest
	var rest_move: MoveAction = MoveActionScript.new()
	rest_move.move_mode = MoveAction.MoveMode.RANDOM_WALK
	rest_move.speed_multiplier = 0.1  # Barely move
	rest_move.random_turn_rate = 0.1

	rest_state.tick_actions = [rest_move] as Array[BehaviorAction]

	# Transition: Energy restored -> Search
	var energy_restored_trans: BehaviorTransition = BehaviorTransitionScript.new()
	energy_restored_trans.target_state = "Search"
	var energy_restored: EnergyCondition = EnergyConditionScript.new()
	energy_restored.compare_mode = EnergyCondition.CompareMode.ABOVE_PERCENT
	energy_restored.threshold = 80.0
	energy_restored_trans.condition = energy_restored
	energy_restored_trans.priority = 10

	# Transition: Wandered away from nest -> GoHome
	var wandered_away_trans: BehaviorTransition = BehaviorTransitionScript.new()
	wandered_away_trans.target_state = "GoHome"
	var wandered_away: DistanceCondition = DistanceConditionScript.new()
	wandered_away.target_type = DistanceCondition.TargetType.NEST
	wandered_away.compare_mode = DistanceCondition.CompareMode.FARTHER_THAN
	wandered_away.threshold = 60.0
	wandered_away_trans.condition = wandered_away
	wandered_away_trans.priority = 5

	rest_state.transitions = [energy_restored_trans, wandered_away_trans] as Array[BehaviorTransition]
	#endregion

	program.states = [search_state, harvest_state, return_state, deposit_state, go_home_state, rest_state] as Array[BehaviorState]
	program.initial_state = "Search"

	return program
