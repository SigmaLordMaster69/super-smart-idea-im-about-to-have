--[[
	INFINITE ROAD ASSETS
	====================
	Drag premade models (Toolbox / Creator Store asset packs) into the
	folders next to this script and they replace the built-in part props.
	Put several models in one folder to get random variants. Leave a folder
	empty to keep the built-in version.

	  Trees/Pine  SnowPine  Oak  OakAutumn  Birch  BirchAutumn  Cypress  Palm  Cactus
	  Plants/Bush  DryBush  Flowers
	  Rocks
	  Signs/CurveLeft  CurveRight  ChevronLeft  ChevronRight  Tunnel
	        SpeedLimit  FallingRocks  Deer  Guide  Marker
	  Road/GuardRail  Delineator  RoadEnd
	  Vehicles/Sedan  SportsCar  Pickup  Semi  Naked  Supermoto  Sportbike
	           Cruiser   (each has a Body folder: one model per vehicle)
	  Car/Body  Motorcycle/Body   (older slots: the Sedan and the Naked bike)

	What happens to each model:
	  * scripts, sounds, seats, humanoids, welds and constraints are removed
	    (free models often contain scripts; none of them will run),
	  * parts are anchored and do not block the car (except Rocks, RoadEnd),
	  * the pivot moves to the bottom centre,
	  * trees/plants/rocks are scaled to the game's sizes; signs only when
	    they are far off (for example tiny or giant models).

	Attributes you can add to a model, or to its folder (Properties panel,
	"+" next to Attributes):
	  KeepSize      (boolean) keep the model's own size
	  Scale         (number)  extra scale factor, e.g. 1.3
	  YawOffset     (number)  degrees to turn the model. Signs must show
	                          their front towards -Z (the blue "Front"
	                          arrow); cars must point their nose towards -Z.
	  HeightOffset  (number)  studs up (+) or down (-), e.g. -1 to bury roots
	  Collide       (boolean) whether it blocks the car

	Tips:
	  * Signs: the Tunnel, SpeedLimit, Guide and Marker slots get their text
	    written into the model's TextLabel if it has one.
	  * GuardRail: one straight segment model; it is repeated along every
	    rail. Its long side can point either way, it is turned for you. The
	    car still collides with an invisible rail, so the model's own
	    collision does not matter.
	  * Vehicles/<Id>/Body: a model for that vehicle, nose towards -Z. It
	    is scaled to the vehicle's length (sedan 17 studs, sports car 16,
	    pickup 21, tractor unit 27, bikes 7.3 to 8.6) and welded onto the
	    physics chassis. Parts named *wheel*, *tire*, *tyre* or *rim* are
	    found and attached to the suspension so they spin and steer. For
	    the Semi, put in the tractor unit only: the trailer stays built-in.
	    On bikes the rider stays and leans with your model.
	  * Car/Body and Motorcycle/Body still work: they are used for the
	    Sedan and the Naked bike when their Vehicles folder is empty.
	  * The Output window prints which folders were picked up when you press
	    Play.
]]
return nil
