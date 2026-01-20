extends Label

@export var car_path: NodePath
var car: Node  # CarV2 script on VehicleBody3D

# RPM range
const MIN_RPM: float = 1000.0
const MAX_RPM: float = 7000.0

func _ready():
	car = get_node(car_path)

func _process(_delta):
	if car == null:
		return

	# Speed
	var speed_kph: int = int(car.get_speed_kmh())

	# RPM
	var rpm: int = int(car.get_current_rpm())
	var gear: int = car.get_current_gear()

	# RPM bar (20 chars wide)
	var rpm_normalized: float = clampf((rpm - MIN_RPM) / (MAX_RPM - MIN_RPM), 0.0, 1.0)
	var bar_fill: int = int(rpm_normalized * 20)
	var rpm_bar: String = "[" + "=".repeat(bar_fill) + " ".repeat(20 - bar_fill) + "]"

	# Redline warning
	var redline: String = " REDLINE!" if rpm > 6300 else ""

	text = "SPD: %d km/h\nRPM: %d %s%s\n     %d        %d" % [
		speed_kph,
		rpm,
		rpm_bar,
		redline,
		int(MIN_RPM),
		int(MAX_RPM)
	]
