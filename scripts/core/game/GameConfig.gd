extends Resource
class_name GameConfig

enum SlotType { CLOSED, LOCAL, REMOTE, AI }

@export var player_count: int = 2
@export var port: int = 8070
@export var server_ip: String = "localhost"
@export var slots: Array[SlotType] = [SlotType.LOCAL, SlotType.REMOTE, SlotType.AI, SlotType.CLOSED]
