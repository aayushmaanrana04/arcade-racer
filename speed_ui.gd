extends Label

@export var car_path: NodePath
var car: VehicleBody3D

func _ready():
	car = get_node(car_path) as VehicleBody3D

func _process(_delta):
	if car == null:
		return

	var speed_mps: float = car.linear_velocity.length()
	var speed_kph: int = int(speed_mps * 3.6)

	text = "Speed: %d km/h" % speed_kph
