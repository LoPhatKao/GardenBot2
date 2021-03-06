delegate.create("simpleminerbot")
--------------------------------------------------------------------------------
simpleminerbot = {}
grassState = {}
tillState = {}
mineState = {}  -- surface strip
branchState = {} -- branches  <-- --> 4 tall = leave y % 5 == 0
shaftState = {} -- main shaft - leave plats every 5 - dig 100 down from spawn y before branching
--------------------------------------------------------------------------------
function simpleminerbot.init(args)
  self.sensors = sensors.create()
  self.state = stateMachine.create({
--  	"grassState",
--  	"tillState", -- test till
--    "plantState",
--    "harvestState",
    "mineState",
    "gatherState",
    "depositState",
    "shaftState",
    "branchState",
    "attackState",
    "moveState",
  	"returnState",
    "idleState"
  })
  self.state.leavingState = function(stateName)
    setAnimationState("movement", "idle")
  end
  
--  self.state.stateCooldown("plantState",cooldown()/2)-- lpk: add some delay before cpu intensive states can trigger
--  self.state.stateCooldown("harvestState",cooldown())
  self.state.stateCooldown("depositState",cooldown()*2)
  
  self.inState = ""
  self.debug = true
  
  self.stuckCount = 0
  self.stuckPosition = {}
  self.jumpTimer = 5
  self.csmTimer = 1
  
  self.shaftX = nil
  self.mineSoundTimer = 0
end
--------------------------------------------------------------------------------
function simpleminerbot.update()
local p1,r1 = mcontroller.position(),mcontroller.boundBox()
world.loadRegion({p1[1]+r1[1], p1[2]+r1[2],p1[1]+r1[3],p1[2]+r1[4]})
	self.dt = script.updateDt()
  self.inState = self.state.stateDesc()
  self.state.update(self.dt)--entity.dt())
  self.sensors.clear()
  if self.debug then
    world.debugText("%s",self.inState,vec2.add(mcontroller.position(),{-3,1.5}),"white")
--    world.debugText("%s",mcontroller.yVelocity(),vec2.add(mcontroller.position(),{-3,0.5}),"white")
    world.debugPoint(mcontroller.position(),"white")
  end
end

-- function update(dt)--
 --world.logInfo("dt: %s : script/60: %s",dt,script.updateDt())
	-- simpleminerbot.main()
-- end
--------------------------------------------------------------------------------
function move(direction)
local moveDir, moveY = 0,0
local mcPos = mcontroller.position()
  if type(direction) == "table" then 
	moveDir = direction[1]
	moveY = direction[2]
  end
  if type(direction) == "number" then moveDir = direction end
    
  --lpk: all the states call move, check for fence here
  moveDir = touchingFenceDirection(mcPos,moveDir) -- in gardenbot.lua

  local run = not (self.inState == "moveState" or self.inState == "branchState")

  if self.jumpTimer <= 0 then
    if jumpThresholdX == nil then jumpThresholdX = 4 end

    -- We either need to be blocked by something, the target is above us and
    -- we are about to fall, or the target is significantly high above us
    local doJump = false
    if isBlocked() then
      doJump = true
--	  elseif self.stuckCount > 4 then
--      doJump = true
    elseif (moveY >= 0 and math.abs(moveDir) > 7) and willFall() then
      doJump = true
    elseif (math.abs(moveDir) < jumpThresholdX and moveY > entity.configParameter("jumpTargetDistance")) then
      doJump = true
    end
    if self.inState == "branchState" then doJump = false end

    if doJump then
      controlJump()
    end
  else
    if not mcontroller.onGround() or (mcontroller.liquidMovement() and moveY >0)then
	    mcontroller.controlHoldJump()
	  else
      self.jumpTimer = self.jumpTimer - self.dt
	  end
  end -- jump

  if moveY < 0 then --mcontroller.onGround() not mcontroller.falling()
    mcontroller.controlDown()
  end
  
  if self.csmTimer <= 0 and self.inState ~= "branchState" then
	  local csm = calculateSeparationMovement()
	  if csm == -(util.toDirection(moveDir)) then moveDir = csm * math.abs(moveDir) end
	  self.csmTimer = self.dt * 3
  else
    self.csmTimer = self.csmTimer - self.dt  
  end
  
  if not mcontroller.onGround() then
    setAnimationState("movement", "jump")
  elseif run then
    setAnimationState("movement", "run")
  else
    setAnimationState("movement", "walk")
  end

--  util.debugLine(mcontroller.position(), vec2.add(mcontroller.position(), vec2.mul({moveDir,moveY}, 3)), "green")
  util.debugLine({mcPos[1],mcPos[2]+math.ceil(mcontroller.boundBox()[2]) }, vec2.add(mcontroller.position(),{moveDir,moveY}), "green")
  
  mcontroller.controlMove(moveDir, run)
--  mcontroller.controlFace(moveDir)
  checkStuck()
  self.lastMoveDirection = util.toDirection(moveDir)
  if self.stuckCount > entity.configParameter("stuckCountMax",15) and self.inState ~= "returnState" then
    self.state.pickState({ignoreDistance=true})
  end
end

function controlJump()
  if mcontroller.onGround() then
    mcontroller.controlJump()
	self.jumpTimer = entity.randomizeParameterRange("jumpTime")
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
--[[  
  local b,t = canReachTarget(vec2.add(mcontroller.position(), {stateData.direction, 0}))
  if not b and t ~= nil then
    local distance = world.distance(t, mcontroller.position())
    stateData.direction = -util.toDirection(distance[1])
	stateData.timer = stateData.timer + 0.5
  end
--]]
--  stateData.direction = touchingFenceDirection(mcontroller.position(),stateData.direction)

  if mcontroller.onGround() and
     not self.sensors.nearGroundSensor.collisionTrace.any(true) and
     self.sensors.midGroundSensor.collisionTrace.any(true) then
    mcontroller.controlDown()
  end

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
function attackState.enterWith(targetId)
  if type(targetId) ~= "number" then return nil end -- lpk: fix trying to use returnState params
  if targetId == 0 then return nil end

  attackState.setAggressive(targetId)
--world.logInfo("attacked by: %s",targetId)
  return { timer = entity.configParameter("attackTargetHoldTime",5) }
end
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
  local blocksInLos 
  if isPleasedGiraffe() then
  blocksInLos = world.collisionBlocksAlongLine(mcontroller.position(), targPos, {"Null","Block","Dynamic"})
  else
  blocksInLos = world.collisionBlocksAlongLine(mcontroller.position(), targPos, "Dynamic")
  end
  return #blocksInLos == 0
end

function isPsychoTarget(mId)
if math.random() < 0.1 and world.monsterType(mId) ~= "fireflyspawner" and world.callScriptedEntity(mId,"isGardenbot") ~= true then 
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
    local armOffset = vec2.add(mcontroller.position(),entity.configParameter("projectileOffset"))
    local toTarget = world.distance(self.targetPosition, armOffset)
    util.debugLine(armOffset,vec2.add(mcontroller.position(),toTarget),"red")
    local targDist = world.magnitude(toTarget)
    
    if targDist < entity.configParameter("attackDistance",5) then
      attackState.setAttackEnabled(true)
      stateData.timer = entity.configParameter("attackTargetHoldTime",5)
      if entity.hasSound("attack") then entity.playSound("attack") end
      maybeKickPetball()
      world.spawnProjectile("lightning", armOffset, entity.id(), toTarget, false, {})
    else
      attackState.setAttackEnabled(false)
      move(toTarget)--util.toDirection(toTarget[1]))
    end
  end

  if self.targetId == nil then
    stateData.timer = 0--stateData.timer - dt
  else--if not canReachTarget(self.targetId) then
    stateData.timer = stateData.timer - dt
--  else
--    stateData.timer = entity.configParameter("attackTargetHoldTime",5)
  end

  if stateData.timer <= 0 then
    attackState.setAttackEnabled(false)
    attackState.setAggressive(nil)
    return true,entity.configParameter("attackTargetHoldTime",5)
  else
    return false
  end
end
--------------------------------------------------------------------------------
function attackState.setAttackEnabled(enabled)
  if enabled then
    setAnimationState("movement", "attackStart")
    self.attackHoldTimer = entity.configParameter("attackHoldTime",2)
--    if maybeKickPetball() then return end
  else
    setAnimationState("movement", "attackEnd")
  end
  entity.setDamageOnTouch(enabled)
end
--------------------------------------------------------------------------------
function attackState.setAggressive(targetId)
  self.targetId = targetId

  if targetId ~= nil then
    setAnimationState("movement", "work")
    entity.setAggressive(true)
  else
    setAnimationState("movement", "idle")
    entity.setAggressive(entity.configParameter("aggressive"),false)
  end
end