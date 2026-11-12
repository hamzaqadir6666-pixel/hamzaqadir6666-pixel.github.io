extends Node
## Dev tool: (re)generates the saved resources from their code definitions.
##   godot --headless res://scenes/tests/bake_resources.tscn
## Run it again after changing DayNight.build_environment(), Terrain.build_*_material() or UITheme.

func _ready() -> void:
	_save(DayNight.build_environment(), "res://environments/jungle_environment.tres")
	_save(Terrain.build_terrain_material(), "res://materials/terrain_material.tres")
	_save(Terrain.build_water_material(), "res://materials/water_material.tres")
	_save(UITheme.build_theme(), "res://ui/wilderness_theme.tres")
	get_tree().quit()


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	print("saved " if err == OK else "FAILED ", path)
