# Ant Colony Simulator

A biologically-inspired ant colony simulation where users can program ant behaviors using a visual state machine system. Watch emergent colony intelligence arise from simple individual rules!

## Core Concepts

### No Pathfinding - Emergent Navigation
Real ants don't plan paths. They make local decisions based on immediate sensory input:
- **Pheromone gradients**: Turn toward stronger concentrations
- **Path integration**: Dead reckoning toward the nest
- **Social cues**: Following other ants

This approach is both biologically accurate and computationally efficient (O(1) per decision), allowing thousands of ants to run smoothly.

### The Decision Loop
Each ant makes decisions at 10Hz (staggered across cohorts to prevent frame spikes):

```
1. SENSE (local only, O(1))
   • Sample pheromone fields at antenna positions (L/C/R)
   • Check path integrator for nest direction
   • Query spatial hash for nearby entities

2. THINK (user-programmed)
   • Evaluate behavior state machine
   • Check transition conditions
   • Compute desired heading

3. ACT (O(1))
   • Steer toward desired heading
   • Deposit pheromones
   • Pick up / drop items
```

## Behavior Programming System

### Resources
Behaviors are built from Godot Resources, making them easy to create, save, and share:

- **BehaviorProgram**: Complete state machine
- **BehaviorState**: Individual state with actions and transitions
- **BehaviorTransition**: Condition-based state change
- **BehaviorCondition**: Evaluates ant/environment state
- **BehaviorAction**: Modifies ant state or environment

### Available Conditions

| Condition | Description | Energy Cost |
|-----------|-------------|-------------|
| `PheromoneCondition` | Check pheromone levels/gradients | 0.01 |
| `CarryingCondition` | Is ant carrying something? | 0 |
| `EnergyCondition` | Check ant's energy level | 0 |
| `DistanceCondition` | Distance to nest/food/ants | 0 |
| `NearbyCondition` | Count nearby entities | 0.05 |
| `RandomCondition` | Probability-based | 0 |
| `CompositeCondition` | AND/OR/NOT combinations | varies |

### Available Actions

| Action | Description | Energy Cost |
|--------|-------------|-------------|
| `MoveAction` | Steering and movement | 0.1-0.2/unit |
| `PheromoneAction` | Deposit pheromone | 0.5/unit |
| `PickupAction` | Pick up items | 1.0 |
| `DropAction` | Drop carried items | 0.2 |
| `MemoryAction` | Store/recall information | 0 |

### Movement Modes

The `MoveAction` supports multiple steering strategies:

- `FOLLOW_PHEROMONE`: Gradient ascent on pheromone field
- `AVOID_PHEROMONE`: Gradient descent (flee from scent)
- `TOWARD_NEST`: Follow path integrator home
- `RANDOM_WALK`: Correlated random walk (exploration)
- `TOWARD_NEAREST_FOOD`: Beeline to detected food
- `WEIGHTED_BLEND`: Combine multiple influences

### Example: Basic Forager

```gdscript
# Created programmatically or via editor
var program = BehaviorProgram.new()
program.program_name = "Forager"

# State: Search for food
var search = BehaviorState.new()
search.state_name = "Search"
search.tick_actions = [
    MoveAction.new()  # WEIGHTED_BLEND of trail + random walk
]
search.transitions = [
    # Found food -> Harvest
    BehaviorTransition.new() with NearbyCondition(FOOD)
]

# State: Return with food  
var return_state = BehaviorState.new()
return_state.state_name = "Return"
return_state.tick_actions = [
    MoveAction.new(),  # TOWARD_NEST
    PheromoneAction.new()  # Lay trail while returning
]
```

## Efficiency Tracking

Every action has an energy cost. The simulation tracks:

- **Per-ant**: Energy spent, distance traveled, food delivered
- **Per-state**: Time spent, energy consumed, transitions
- **Per-colony**: Food/second, average ant efficiency
- **Global**: Total food collected / total energy spent

### Efficiency Score
```
efficiency = food_delivered / energy_spent × 100
```

Higher is better! Optimize your behaviors by:
- Minimizing unnecessary movement
- Reducing pheromone deposition in unproductive areas
- Balancing exploration vs exploitation

## File Structure

```
ant_simulator/
├── scripts/
│   ├── autoloads/
│   │   └── game_manager.gd      # Global simulation control
│   ├── world/
│   │   ├── world.gd             # World container
│   │   ├── pheromone_field.gd   # Efficient pheromone grid
│   │   └── spatial_hash.gd      # O(1) neighbor queries
│   ├── colony/
│   │   ├── colony.gd            # Colony management
│   │   └── ant.gd               # Ant agent
│   ├── behavior/
│   │   ├── behavior_program.gd  # State machine
│   │   ├── behavior_state.gd    # Individual state
│   │   ├── behavior_transition.gd
│   │   ├── behavior_factory.gd  # Pre-built behaviors
│   │   ├── conditions/          # All condition types
│   │   └── actions/             # All action types
│   ├── entities/
│   │   └── food_source.gd       # Food entities
│   └── stats/
│       └── efficiency_tracker.gd
└── scenes/
    └── main.tscn
```

## Controls

- **Arrow keys**: Pan camera
- **Page Up/Down**: Zoom
- **Space**: Play/Pause
- **F**: Spawn food cluster
- **R**: Reset simulation

## Performance Targets

With the current architecture:
- **10,000 ants** at 60fps target
- **Staggered updates**: No frame spikes
- **Spatial hashing**: O(k) neighbor queries (k = nearby count)
- **GPU-ready pheromones**: Diffusion can be offloaded to compute shaders

## Extending the System

### Custom Conditions
```gdscript
class_name MyCondition
extends BehaviorCondition

@export var my_param: float = 1.0

func _evaluate_internal(ant: Node, context: Dictionary) -> bool:
    # Your logic here
    return context.get("my_value", 0) > my_param
```

### Custom Actions
```gdscript
class_name MyAction
extends BehaviorAction

func _execute_internal(ant: Node, context: Dictionary) -> Dictionary:
    # Your logic here
    return {
        "success": true,
        "energy_cost": 0.5,
        "my_custom_key": some_value
    }
```

## License

MIT License - Feel free to use, modify, and share!
