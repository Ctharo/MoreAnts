extends Node
## GameEntry - Entry point that manages the settings screen and game transitions

@onready var settings_screen: Control = $SettingsScreen


func _ready() -> void:
	settings_screen.play_requested.connect(_on_play_requested)


func _on_play_requested() -> void:
	# Change to the main simulation scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")
