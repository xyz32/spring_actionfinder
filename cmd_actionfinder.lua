include("colors.h.lua")
include("keysym.h.lua")
include("utils.lua")

function widget:GetInfo()
	return {
		name      = "Action Finder",
		desc      = "Focuses the camera to the places of the map with a lot of action.",
		author    = "xyz",
		date      = "May 26, 2009",
		license   = "GNU GPL, v2 or later",
		version   = "1.7",
		layer     = 0,
		enabled   = true,  --  loaded by default?
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local TRANSITION_DURATION     			= 10
local FAR_TRANSITION_DURATION			= 5
local SWITCH_LIMIT						= 2500

local CAMERA_IDLE_RESPONSE     			= 10
local CAMERA_FIGHT_RESPONSE 			= 5
local FORCE_ECONOMY_VIEW				= 10      -- show some economy stuff after this many events
local USER_IDLE_RESUME         			= 10
local CAMERA_ELEVATION					= 10

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local lastMove = 0
local lastUserMove = 0
local eventsCount = 0

local fracScale = 50
local healthScale = 0 -- 0.001

local paraFracScale = fracScale * 0.25
local paraHealthScale = healthScale * 0

-- Automatically generated local definitions
local spEcho				 = Spring.Echo

local spGetFrameTimeOffset   = Spring.GetFrameTimeOffset
local spGetGameSeconds       = Spring.GetGameSeconds
local spGetUnitPosition      = Spring.GetUnitPosition
local spGetUnitViewPosition  = Spring.GetUnitViewPosition
local spGetCameraState       = Spring.GetCameraState
local spGetUnitIsDead		 = Spring.GetUnitIsDead
local spGetUnitVelocity		 = Spring.GetUnitVelocity
local spGetGroundHeight		 = Spring.GetGroundHeight
local spGetSpectatingState	 = Spring.GetSpectatingState
local spGetMouseState		 = Spring.GetMouseState
local spGetUnitTeam			 = Spring.GetUnitTeam

local spSetCameraState		 = Spring.SetCameraState
local spSetCameraTarget		 = Spring.SetCameraTarget

local spIsUnitAllied         = Spring.IsUnitAllied
local spValidUnitID			 = Spring.ValidUnitID
local spSelectUnitArray		 = Spring.SelectUnitArray
local spSendCommands		 = Spring.SendCommands
local spWorldToScreenCoords	 = Spring.WorldToScreenCoords
local spTraceScreenRay		 = Spring.TraceScreenRay

local mathAbs		     	 = math.abs
local mathRandom			 = math.random
local mathMax				 = math.max
local mathMin				 = math.min

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local inSpecMode = false
local inAttractMode = false
local wasSpecMode = false

local eventScale = 0.02

local lastMouseX = 0
local lastMouseY = 0

local WantedX,WantedZ,WantedID

local DEATH_EVENT            = 0
local TAKE_EVENT             = 1
local CREATE_EVENT           = 2
local CREATE_START_EVENT     = 3
local STOCKPILE_EVENTS       = 4
local DAMAGE_EVENTS          = 5
local PARALYZE_EVENT         = 6

local limit = 0.1

--------------------------------------------------------------------------------

local gameSecs = 0

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local eventMap  = {}

local damageMap = {}

local SavedInitialCameraState = nil

local ChangeModCounter = 1

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function getTransitionTime(x,z)
	cameraState = spGetCameraState()
	dst = mathAbs(cameraState.px - x) + mathAbs(cameraState.pz - z)

	if dst > SWITCH_LIMIT then
		return FAR_TRANSITION_DURATION
	else
		return TRANSITION_DURATION
	end
end

--------------------------------------------------------------------------------

local function clearTrackingMode()
	if WantedID and spValidUnitID(WantedID) then
		spSelectUnitArray({WantedID})
		spSendCommands("trackoff")
		spSelectUnitArray({})
		WantedID = nil
	end

	spSendCommands("trackoff")
end

--------------------------------------------------------------------------------

local function enableTrackingMode(id)
	clearTrackingMode()

	WantedID = id

	spSelectUnitArray({id})
	spSendCommands("track")
	spSelectUnitArray({})
end

--------------------------------------------------------------------------------

local function PickCameraMode(x,z,id)
	lastMove = gameSecs
	WantedX=x
	WantedZ=z

	clearTrackingMode()

	ChangeModCounter=mathRandom(0,4)
	spSelectUnitArray({})
	local RandomMode=mathRandom(1,3)
	-- Total war, close to ground
	if RandomMode==1 then
		spSetCameraState({name=tw,mode=2,rz=0,rx=mathRandom(-100,0)/100,ry=mathRandom(-50,50)/10,px=x,py=0,pz=z},getTransitionTime(x, z))
		-- FPS, tracking
	elseif RandomMode==2 and id and spValidUnitID(id) and not spGetUnitIsDead(id) then
		local vx,vy,vz=spGetUnitVelocity(id)
		if vx and vy and vz and vx^2+vy^2+vz^2>0.1^2 then
			spSetCameraState({name=fps,mode=0,px=x,py=spGetGroundHeight(x,z)+20,pz=z,rz=0,dx=0,dy=-1,ry=9,rx=-1,dz=-0.5,oldHeight=999},0)

			enableTrackingMode(id)

			WantedX=nil
			WantedZ=nil
			WantedID=id
		end
		-- TA Overview
	else
		spSetCameraState({name=ta,mode=1,px=x,py=0,pz=z,flipped=-1,dy=-0.9,zscale=0.5,height=999,dx=0,dz=-0.45},getTransitionTime(x, z))
	end
end

--------------------------------------------------------------------------------

function EnterSpecMode()
	spEcho("Start spec mode / action finder")

	spSetCameraTarget(Game.mapSizeX/2, CAMERA_ELEVATION,Game.mapSizeZ/2, 0)
	inSpecMode = true
end

--------------------------------------------------------------------------------

function EnterAttractMode()
	if not inSpecMode then
		EnterSpecMode()
	else
		wasSpecMode = true
	end

	spEcho("Attract mode camera style ON")

	inAttractMode = true
	spSendCommands("MapMarks 0") --disable markers

	SavedInitialCameraState = spGetCameraState()
	PickCameraMode(Game.mapSizeX/2,Game.mapSizeZ/2)
end

--------------------------------------------------------------------------------

function LeaveSpecMode()
	spEcho("End spec mode / action finder")
	inSpecMode = false

	spSetCameraState(spGetCameraState(), 0)

	if inAttractMode then
		LeaveAttractMode()
	end
end

--------------------------------------------------------------------------------

function LeaveAttractMode()
	spEcho("Attract mode camera style OFF")

	inAttractMode = false
	spSendCommands("MapMarks 1")

	if SavedInitialCameraState then
		spSetCameraState(SavedInitialCameraState, 0)
		SavedInitialCameraState=nil
	end

	if not wasSpecMode then
		LeaveSpecMode()
		wasSpecMode = false
	end
end

--------------------------------------------------------------------------------

local function UserAction()
	lastUserMove = gameSecs

	WantedX=nil
	WantedZ=nil

	clearTrackingMode()
end

--------------------------------------------------------------------------------

local function GetGameSecs()
	return spGetGameSeconds() + spGetFrameTimeOffset()
end

--------------------------------------------------------------------------------

local function UpdateCamera(pozX, pozZ, Uid)
	lastMove = gameSecs
	
	if Uid then 
		spSendCommands{"specteam "..spGetUnitTeam(Uid)}
	end

	if inAttractMode then
		if (ChangeModCounter > 0) then
			ChangeModCounter=ChangeModCounter-1
			if WantedID and spValidUnitID(WantedID) then
				local x,_,z=spGetUnitPosition(WantedID)
				if WantedX and WantedZ and x==WantedX and z==WantedZ then
					PickCameraMode(pozX,pozZ, Uid)
				end
			else
				WantedX=pozX
				WantedZ=pozZ

				clearTrackingMode()

				spSetCameraTarget(pozX, CAMERA_ELEVATION, pozZ, getTransitionTime(pozX, pozZ))
			end
		else
			PickCameraMode(pozX,pozZ,Uid)
		end
	else
		clearTrackingMode()
		spSetCameraTarget(pozX, CAMERA_ELEVATION, pozZ, getTransitionTime(pozX, pozZ))
	end
end

--------------------------------------------------------------------------------

function widget:TextCommand(command)
	--Specmode
	if (command == 'specmode' or command == 'specmode 1' or command == 'autocamera'  or command == 'autocamera 1' or command == 'actionfinder' or command == 'actionfinder 1')
	and not inSpecMode then
		EnterSpecMode()
		return false
	elseif (command == 'specmode' or command == 'specmode 0' or command == 'autocamera'  or command == 'autocamera 0' or command == 'actionfinder' or command == 'actionfinder 0')
	and inSpecMode then
		LeaveSpecMode()
	end

	--AttractMode
	if (command == 'actionfinder' or command == 'actionfinder 1' or command == 'attractmode' or command == 'attractmode 1')
	and not inAttractMode then
		EnterAttractMode()
		return false
	elseif (command == 'actionfinder' or command == 'actionfinder 0' or command == 'attractmode' or command == 'attractmode 0')
	and inSpecMode then
		LeaveAttractMode()
	end

	local cmd = string.sub(command, 10)
	return true
end

--------------------------------------------------------------------------------

function widget:KeyPress(key, mods, isRepeat)

	if key == KEYSYMS.S and mods.alt and mods.ctrl and not (mods.meta or mods.shift) then
		if inSpecMode then
			LeaveSpecMode()
			return true
		else
			EnterSpecMode()
			return true
		end
	end

	if key == KEYSYMS.C and mods.alt and mods.ctrl and not (mods.meta or mods.shift) then
		if inAttractMode then
			LeaveAttractMode()
			return true
		else
			EnterAttractMode()
			return true
		end
	end

	UserAction()
	return false
end

--------------------------------------------------------------------------------

function widget:Initialize()
	gameSecs = GetGameSecs()

	if spGetSpectatingState() then
		EnterSpecMode()
	else
		LeaveSpecMode()
	end
end

--------------------------------------------------------------------------------

function widget:PlayerChanged(playerID)
--[[  if spGetSpectatingState() then
EnterSpecMode()
else
LeaveSpecMode()
end
]]--
end

--------------------------------------------------------------------------------

function widget:Shutdown()
	if SavedInitialCameraState and inSpecMode then
		spSetCameraState(SavedInitialCameraState,TRANSITION_DURATION)
	end
end

--------------------------------------------------------------------------------

function widget:MousePress(x, y, button)
	lastUserMove = gameSecs
end

--------------------------------------------------------------------------------

function widget:MouseMove(x, y, dx, dy, button)
	UserAction()
end

--------------------------------------------------------------------------------

function widget:MouseRelease(x, y, button)
	UserAction()
end

--------------------------------------------------------------------------------

function widget:MouseWheel(up, value)
	UserAction()
end

--------------------------------------------------------------------------------

local function DrawEvent(event)
	if gameSecs > lastMove + CAMERA_IDLE_RESPONSE then
		eventsCount = 0
		UpdateCamera(event.x, event.z)
	end
end

--------------------------------------------------------------------------------

local function DrawDamage(damage)
	local u=nil
	if spValidUnitID(damage.u) then
		u=damage.u
	elseif spValidUnitID(damage.a) then
		u=damage.a
	end
	if spValidUnitID(damage.u) and not spGetUnitIsDead(damage.u) then
		local vx,vy,vz=spGetUnitVelocity(damage.u)
		if vx and vy and vz and vx^2+vy^2+vz^2>0.1^2 then
			u=damage.u
		end
	end
	if spValidUnitID(damage.a) and not spGetUnitIsDead(damage.a) then
		local vx,vy,vz=spGetUnitVelocity(damage.a)
		if vx and vy and vz and vx^2+vy^2+vz^2>0.1^2 then
			u=damage.a
		end
	end
	if u==nil then
		return
	end

	local px, py, pz = spGetUnitViewPosition(u)
	if px == nil then
		px, py, pz = spGetUnitViewPosition(u)
		if px == nil then
			return
		end
	end

	if (gameSecs > lastMove + CAMERA_FIGHT_RESPONSE) and (eventsCount < FORCE_ECONOMY_VIEW) then
		eventsCount = eventsCount + 1;
		UpdateCamera(px, pz, u)
	end
end

--------------------------------------------------------------------------------

function MouseMoved()
	local x, y, lmb, mmb, rmb = spGetMouseState()

	if x ~= lastMouseX then
		lastMouseX = x
		return true
	end

	if y ~= lastMouseY then
		lastMouseY = y
		return true
	end

	return false
end

--------------------------------------------------------------------------------

function widget:Update(dt)
	-- if specmode is not activated no need to update.
	if not inSpecMode then
		return
	end

	-- don't update evey frame
	local gs = GetGameSecs()
	if (gs == gameSecs) then
		return
	end

	gameSecs = gs

	-- if user wants to take manual controll pause the scipt for   USER_IDLE_RESUME seconds
	if MouseMoved() then
		UserAction()
		return
	end

	if gameSecs < lastUserMove + USER_IDLE_RESUME then
		return
	end

	local scale = (1 - (4 * dt))

	for unitID, d in pairs(eventMap) do
		local v = d.v
		v = v * scale
		if (v < limit) then
			eventMap[unitID] = nil
		else
			d.v = v
		end
	end

	for unitID, d in pairs(damageMap) do
		local v = d.v * scale
		local p = d.p * scale

		if (v > limit) then
			d.v = v
		else
			if (p > limit) then
				d.v = 0
			else
				damageMap[unitID] = nil
			end
		end

		if (p > 1) then
			d.p = p
		else
			if (v > 1) then
				d.p = 0
			else
				damageMap[unitID] = nil
			end
		end
	end

	if ((next(eventMap)  == nil) and
	(next(damageMap) == nil)) then
		return
	end

	-- draw damages before events
	for _,damage in pairs(damageMap) do
		DrawDamage(damage)
	end

	for _,event in pairs(eventMap) do
		DrawEvent(event)
	end
end

--------------------------------------------------------------------------------

local function AddEvent(unitID, unitDefID, color, cost)
	if (not spIsUnitAllied(unitID)) then
		return
	end
	local ud = UnitDefs[unitDefID]
	if ((ud == nil) or ud.isFeature) then
		return
	end
	local px, py, pz = spGetUnitPosition(unitID)
	if (px and pz) then
		eventMap[unitID] = {
			x = px,
			z = pz,
			v = cost or (ud.cost * eventScale),
			u = unitID,
			c = color,
		--      t = GetGameSeconds()
		}
	end
end

--------------------------------------------------------------------------------

function IsTerrainViewable(x1,z1)
	local y1=spGetGroundHeight(x1,z1)
	local xs,ys=spWorldToScreenCoords(x1,y1,z1)
	local _,pos=spTraceScreenRay(xs,ys,true,false)
	if pos then
		local x2,y2,z2=unpack(pos)
		--spEcho("e="..((x2-x1)^2+(y2-y1)^2+(z2-z1)^2))
		if ((x2-x1)^2+(y2-y1)^2+(z2-z1)^2)<22500 then
			return true
		else
			return false
		end
	else
		return nil
	end
end

--------------------------------------------------------------------------------

function widget:DrawWorldPreUnit()
	if not inAttractMode then
		return
	end

	local gs = GetGameSecs()
	if (gs == gameSecs) then
		return
	end

	if WantedX and WantedZ and not WantedID then
		if (lastMove+TRANSITION_DURATION+0.2>gameSecs) then
			return
		elseif not IsTerrainViewable(WantedX,WantedZ) then
			spEcho("View blocked, redoing it.")
			PickCameraMode(WantedX,WantedZ)
		end
	end
end

--------------------------------------------------------------------------------

function widget:UnitCreated(unitID, unitDefID, unitTeam)
	AddEvent(unitID, unitDefID, CREATE_START_EVENT)
end

--------------------------------------------------------------------------------

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	AddEvent(unitID, unitDefID, CREATE_EVENT)
end

--------------------------------------------------------------------------------

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	damageMap[unitID] = nil
	AddEvent(unitID, unitDefID, DEATH_EVENT)
	if WantedID and unitID==WantedID then
		clearTrackingMode()
		local x,_,z=spGetUnitPosition(unitID)
		PickCameraMode(x,z)
	end
end

--------------------------------------------------------------------------------

function widget:UnitTaken(unitID, unitDefID)
	damageMap[unitID] = nil
	AddEvent(unitID, unitDefID, TAKE_EVENT)
end

--------------------------------------------------------------------------------

function widget:StockpileChanged(unitID, unitDefID, unitTeam,
weaponNum, oldCount, newCount)
	if (newCount > oldCount) then
		AddEvent(unitID, unitDefID, STOCKPILE_EVENTS, 100)
	end
end

--------------------------------------------------------------------------------

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponID, attackerID, attackerDefID)

	if (not spIsUnitAllied(unitID)) then
		return
	end
	if (damage <= 0) then
		return
	end

	local ud = UnitDefs[unitDefID]
	if (ud == nil) then
		return
	end

	-- clamp the damage
	damage = mathMin(ud.health, damage)

	-- scale the damage value
	if (paralyzer) then
		damage = (paraHealthScale * damage) +
		(paraFracScale   * (damage / ud.health))
	else
		damage = (healthScale * damage) +
		(fracScale   * (damage / ud.health))
	end


	local d = damageMap[unitID]
	if (d ~= nil) then
		d.a = attackerID
		if (paralyzer) then
			d.p = d.p + damage
		else
			d.v = d.v + damage
		end
	else
		d = {}
		d.u = unitID
		d.a = attackerID
		--    d.t = GetGameSeconds()
		if (paralyzer) then
			d.v = 0
			d.p = mathMax(1, damage)
		else
			d.v = mathMax(1, damage)
			d.p = 0
		end
		damageMap[unitID] = d
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
