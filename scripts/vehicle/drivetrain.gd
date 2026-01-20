class_name Drivetrain
extends RefCounted
## Base drivetrain class - distributes torque to axles.
## Override in subclasses for RWD/FWD/AWD behavior.
## NEVER applies forces directly - returns distribution only.

enum DriveType {
	RWD,
	FWD,
	AWD
}

var drive_type: DriveType = DriveType.RWD

# AWD bias (0.0 = full rear, 1.0 = full front)
var front_bias: float = 0.4


## Distribute engine torque to front/rear axles
## Returns Dictionary with "front" and "rear" values
func distribute_torque(engine_torque: float) -> Dictionary:
	match drive_type:
		DriveType.RWD:
			return _distribute_rwd(engine_torque)
		DriveType.FWD:
			return _distribute_fwd(engine_torque)
		DriveType.AWD:
			return _distribute_awd(engine_torque)
	return {"front": 0.0, "rear": 0.0}


func _distribute_rwd(torque: float) -> Dictionary:
	return {
		"front": 0.0,
		"rear": torque
	}


func _distribute_fwd(torque: float) -> Dictionary:
	return {
		"front": torque,
		"rear": 0.0
	}


func _distribute_awd(torque: float) -> Dictionary:
	return {
		"front": torque * front_bias,
		"rear": torque * (1.0 - front_bias)
	}


## Distribute brake force (always all wheels)
func distribute_brake(brake_force: float) -> Dictionary:
	# Typical brake bias: 60% front, 40% rear
	return {
		"front": brake_force * 0.6,
		"rear": brake_force * 0.4
	}


## Set drive type
func set_rwd() -> void:
	drive_type = DriveType.RWD


func set_fwd() -> void:
	drive_type = DriveType.FWD


func set_awd(bias: float = 0.4) -> void:
	drive_type = DriveType.AWD
	front_bias = clampf(bias, 0.0, 1.0)
