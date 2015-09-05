delegate.create("simplegardenbot")
--------------------------------------------------------------------------------
simplegardenbot = {}
grassState = {}
tillState = {}
mineState = {}
returnState = {}
idleState = {}
--------------------------------------------------------------------------------
function simplegardenbot.init(args)
  self.sensors = sensors.create()
  self.state = stateMachine.create({
    "gatherState",
    "plantState",
    "harvestState",
    "depositState",
    "grassState",
    "tillState",
    "mineState",
    "moveState",
    "attackState",
    "idleState",
    "returnState"
  })
  self.state.leavingState = function(stateName)
    entity.setAnimationState("movement", "idle")
  end
  
  self.state.stateCooldown("plantState",cooldown()/2)-- lpk: add some delay before cpu intensive states can trigger
  self.state.stateCooldown("harvestState",cooldown())
  self.state.stateCooldown("depositState",cooldown()*2)
  
  self.inState = ""
  self.debug = true
  
  self.stuckCount = 0
  self.stuckPosition = {}

end
--------------------------------------------------------------------------------
function update(dt)
world.loadRegion({mcontroller.position()[1]-5, mcontroller.position()[2]-5,mcontroller.position()[1]+5,mcontroller.position()[2]+5})
self.dt = dt
simplegardenbot.main()
end

function simplegardenbot.main()
  self.inState = self.state.stateDesc()
  self.state.update(self.dt)--entity.dt())
  self.sensors.clear()
  if self.debug then
    world.debugText("%s",self.inState,vec2.add(mcontroller.position(),{-3,1.5}),"white")
  end
end
--------------------------------------------------------------------------------
function move(direction)
  if type(direction) == "table" then direction = direction[1] end
  local mcPos = mcontroller.position()

 --lpk: all the states call move, check for forced direction here
 -- if willFall(direction) then direction = -direction end  -- try not to fall
  direction = touchingFenceDirection(mcPos,direction)-- fence last
 
  entity.setAnimationState("movement", "move")
  local run = self.inState ~= "moveState"--util.toDirection(direction) == mcontroller.facingDirection() and not self.inState == "moveState"
  mcontroller.controlMove(direction, run)
  mcontroller.controlFace(direction)
  checkStuck()
  self.lastMoveDirection = util.toDirection(direction)
  if self.stuckCount > entity.configParameter("stuckCountMax",15) and self.inState ~= "returnState" then
    self.state.pickState({ignoreDistance=true})
  end
end
--------------------------------------------------------------------------------
moveState = {}
--------------------------------------------------------------------------------
function moveState.enter()
  local direction = mcontroller.facingDirection()

  return {
    timer = entity.randomizeParameterRange("moveTimeRange"),
    direction = direction
  }
end
--------------------------------------------------------------------------------
function moveState.update(dt, stateData)
  stateData.direction = self.lastMoveDirection

  if self.sensors.collisionSensors.collision.any(true) then
    stateData.direction = -stateData.direction
  end

--[[  -- lpk: replaced in move()  
  local b,t = canReachTarget(vec2.add(mcontroller.position(), {stateData.direction, 0}))
  if not b and t ~= nil then
    local distance = world.distance(t, mcontroller.position())
    stateData.direction = -util.toDirection(distance[1])
  end
--]]
--  stateData.direction = touchingFenceDirection(mcontroller.position(),stateData.direction)
--[[
  if mcontroller.onGround() and
     not self.sensors.nearGroundSensor.collisionTrace.any(true) and
     self.sensors.midGroundSensor.collisionTrace.any(true) then
    mcontroller.controlDown()
  end
--]]
  move(stateData.direction)

  stateData.timer = stateData.timer - dt
  if stateData.timer <= 0 then
    return true, 1.0
  end

  return false
end
--------------------------------------------------------------------------------
attackState = {}
--------------------------------------------------------------------------------
function attackState.enter()
  local findDist = entity.configParameter("attackSearchRadius",10)

--  if util.trackTarget(findDist,findDist/2,nil) then --  also targets player boo :"(
  if attackState.findValidTarget(mcontroller.position(),findDist) then
--world.logInfo("attacking: %s",self.targetId)
    return { timer = entity.configParameter("attackTargetHoldTime",5) } 
  end
  
  return nil, 1.5 --entity.configParameter("gardenSettings.cooldown", 15)
end

--------------------------------------------------------------------------------
function targInLOS(targID)
  local targPos = world.entityPosition(targID)
  local blocksInLos = world.collisionBlocksAlongLine(mcontroller.position(), targPos, "Dynamic")
  return #blocksInLos == 0
end

function isPsychoTarget(mId)
if math.random() < 0.1 and world.callScriptedEntity(mId,"isGardenbot") ~= true then 
  return true
end 
  return false
end

function attackState.findValidTarget(pos,dist)
  local monsterIds = world.entityQuery(pos, dist, { withoutEntityId = entity.id(),includedTypes = {"monster"}, order = "nearest" })

  if #monsterIds > 0 then
    for i,mId in ipairs(monsterIds) do
      if (entity.isValidTarget(mId) or (isPsychoTarget(mId))) and targInLOS(mId) then
        attackState.setAggressive(mId)
--	    util.trackExistingTarget()
        return true
	    end
    end
  end
   
  return false
end
--------------------------------------------------------------------------------
function attackState.enterWith(targetId)
  if type(targetId) ~= "number" then return nil end -- lpk: fix trying to use returnState params
  if targetId == 0 then return nil end

  attackState.setAggressive(targetId)

  return { timer = entity.configParameter("attackTargetHoldTime") }
end
--------------------------------------------------------------------------------
function attackState.update(dt, stateData)
  util.trackExistingTarget()

  if self.attackHoldTimer ~= nil then
    self.attackHoldTimer = self.attackHoldTimer - dt
    if self.attackHoldTimer > 0 then
      return false
    else
      self.attackHoldTimer = nil
    end
  end

  if self.targetPosition ~= nil then
    local toTarget = world.distance(self.targetPosition, mcontroller.position())

    if world.magnitude(toTarget) < entity.configParameter("attackDistance") then
      attackState.setAttackEnabled(true)
      stateData.timer = entity.configParameter("attackTargetHoldTime",5)
      if entity.hasSound("attack") then entity.playSound("attack") end
      maybeKickPetball()
    else
      attackState.setAttackEnabled(false)
      move(util.toDirection(toTarget[1]))
    end
  end

  if self.targetId == nil then
    stateData.timer = 0--stateData.timer - dt
  else--if not canReachTarget(self.targetId) then -- bounce on fences like angry dog
    stateData.timer = stateData.timer - dt
--  else
--    stateData.timer = entity.configParameter("attackTargetHoldTime",5)
  end

  if stateData.timer <= 0 then
    attackState.setAttackEnabled(false)
    attackState.setAggressive(nil)
    return true
  else
    return false
  end
end
--------------------------------------------------------------------------------
function attackState.setAttackEnabled(enabled)
  if enabled then
    entity.setAnimationState("movement", "attack")
    self.attackHoldTimer = entity.configParameter("attackHoldTime")
  else
    entity.setAnimationState("movement", "aggro")
  end

  entity.setDamageOnTouch(enabled)
end
--------------------------------------------------------------------------------
function attackState.setAggressive(targetId)
  self.targetId = targetId

  if targetId ~= nil then
    entity.setAnimationState("movement", "aggro")
    entity.setAggressive(true)
  else
    entity.setAnimationState("movement", "idle")
    entity.setAggressive(false)
  end
end