extends Unit

class_name Zoomba

var pathing_manager
#@onready var job_manager : JobManager = $"../../JobManager"

# Called when the node enters the scene tree for the first time.
func _ready():
	$Zapper.visible = false

func initialise(b : Building):
	super.initialise(b)
	type = UnitManager.Type.ZOOMBA
	_health_bar.position.y = 2.5
	add_to_group("zoomba")
	var updated_mat = load("res://materials/player/player" + str(building.player_owner) + "_material.tres")
	$Body/CSGBody/CSGMesh.material = updated_mat
	
#func pathing_callback():
	## First - check we didn't scram while moving.
	## If we did then we want to redirect to the idle callback
	#if scram_count > 0:
		#assert(state == State.IDLE)
		#return idle_callback()
	#assert(state == State.PATHING)
	## Second - check our job is stil valid
	#if not check_job_still_valid():
		#return job_finished(false)
	## Third check if at destination
	#if location.get_id() == job["place"].get_id():
		#return start_work()
	## Fourth, run pathing
	#if not check_pathing_valid():
		#return abandon_job(false) # No active call-backs
	## Fifth, move to next location
	#assert(progress < path.size())
	#location = pathing_manager.get_tile( path[progress] )
	#progress += 1
	#move("pathing_callback")



#
#func check_job_still_valid() -> bool:
	#match job["type"]:
		#JobManager.JobType.CONSTRUCT_MONORAIL:
			## Get the monorail segment which connects this tile to the target
			#var mr = job["place"].paths[ job["target"] ]
			#if mr.state != mr_class.State.INITIAL:
				#return false  # Job was already done/stared (both directions can get queued, or another team might make the claim)
		#JobManager.JobType.CONSTRUCT_BUILDING:
			#var building = job["target"].building
			#if building == null:
				## Expect rare
				#print("Building == null for CONSTRUCT_BUILDING job? ", job)
				#return false
			#if building.state != building.State.BLUEPRINT:
				#return false # Job was already done/stared (many directions can get queued)
			#if building.location.player != player and building.location.player != -1:
				#return false # Was taken (check also for -1 as barriers are built on un-claimed land)
		#JobManager.JobType.CLAIM_TILE:
			#var tile = job["place"]
			#if tile.player == player: 
				#return false # Already (re)/claimed
			#if tile.building != null:
				#return false # Should now be a claim building job
		#JobManager.JobType.CLAIM_BUILDING:
			#var building = job["target"].building
			#if building == null:
				#return false # Nothing left to claim
			#if job["place"].player != player:
				#return false # No longer own this adjacent tile
			#if building.location.player == player:
				#return false # Already captured
			#if building.capture_in_progress:
				#return false # Already being captured
		#_:
			#print("UNKNOWN JOB TYPE")
			#assert(false)
	#return true
	#
#func start_work():
	#assert(state == State.PATHING)
	#state = State.WORKING
	#quick_rotate()
	#$Zapper.visible = true
	#match job["type"]:
		#JobManager.JobType.CONSTRUCT_MONORAIL:
			## Get the monorail segment which connects this tile to the target
			#$Zapper.target_position.y = Cairo.UNIT
			#var mr = job["place"].paths[ job["target"] ]
			#assert(mr.state == mr_class.State.INITIAL)
			#mr.start_construction(self)
		#JobManager.JobType.CONSTRUCT_BUILDING:
			#$Zapper.target_position.y = Cairo.UNIT
			#var building = job["target"].building
			#assert(building != null)
			#building.start_construction(self)
		#JobManager.JobType.CLAIM_TILE:
			#$Zapper.target_position.y = Cairo.UNIT / 2.0
			#var tile = job["place"]
			#assert(tile.player != player)
			#tile.start_capture(self)
		#JobManager.JobType.CLAIM_BUILDING:
			#$Zapper.target_position.y = Cairo.UNIT
			#var building = job["target"].building
			#assert(building != null)
			#assert(job["place"].player == player)
			#building.start_capture(self)
		#_:
			#print("UNKNOWN JOB TYPE")
			#assert(false)
			#
#func quick_rotate():
	#if job["target"] == null:
		 #return
	#setup_rotation(job["target"], null)
	#create_tween().tween_method(quat_transform, 0.0, 1.0, QUICK_ROTATE_TIME)
#
#func job_finished(work_was_done : bool):
	#assert((work_was_done and state == State.WORKING) or (not work_was_done and state == State.PATHING))
	#assert(job != null)
	#state = State.IDLE
	#$Zapper.visible = false
	#var job_id = job["id"]
	#job = null
	#job_manager.remove_job(player, job_id)
	#job_manager.assign_jobs()
	#idle_callback()
	#

#


#
