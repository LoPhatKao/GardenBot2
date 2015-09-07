delegate.create("simplegardenbot")
--------------------------------------------------------------------------------
simplegardenbot = {}
grassState = {}
tillState = {}
mineState = {}
waterState = {}
returnState = {}
idleState = {}
--------------------------------------------------------------------------------
function simplegardenbot.init(args)
  self.sensors = sensors.create()
  self.state = stateMachine.create({
    "attackState",
    "gatherState",
--    "plantState",
--    "harvestState",
    "depositState",
--    "grassState",
--    "tillState",
--    "mineState",
--    "waterState",
    "attackState",
    "moveState",
    "idleState",
    "returnState"
  })
  self.state.leavingState = function(stateName)
    setAnimationState("movement", "idle")
  end
  
--  self.state.stateCooldown("plantState",cooldown()/2)-- lpk: add some delay before cpu intensive states can trigger
--  self.state.stateCooldown("harvestState",cooldown())
  self.state.stateCooldown("depositState",cooldown()*2)
  
  self.inState = ""
  self.debug = true

  self.projectileParams = entity.configParameter("projectileParameters")
  
  self.stuckCount = 0
  self.stuckPosition = {}
  self.csmTimer = 1

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
    world.debugPoint(mcontroller.position(),"white")
    world.debugText("%s",self.inState,vec2.add(mcontroller.position(),{-3,1.5}),"white")
  end
end
--------------------------------------------------------------------------------
function move(direction)
  if type(direction) == "table" then direction = direction[1] end
  local mcPos = mcontroller.position()
  local run = self.inState ~= "moveState"--util.toDirection(direction) == mcontroller.facingDirection() and not self.inState == "moveState"
  if run and self.shielded then run = false end
  
 --lpk: all the states call move, check for forced direction here
 -- if willFall(direction) then direction = -direction end  -- try not to fall
  direction = touchingFenceDirection(mcPos,direction)-- fence last
 
  if not mcontroller.onGround() then
    setAnimationState("movement", "jump")
  elseif run then
    setAnimationState("movement", "run")    
  else
    setAnimationState("movement", "walk")
  end
  
  if self.csmTimer <= 0 then
	  local csm = calculateSeparationMovement()
	  if csm == -(util.toDirection(direction)) then direction = csm * math.abs(direction) end
	  self.csmTimer = self.dt * 3
  else
    self.csmTimer = self.csmTimer - self.dt  
  end
 
  mcontroller.controlMove(direction, run)
  if self.inState ~= "attackState" then mcontroller.controlFace(direction) end
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
  local findDist = entity.configParameter("attackSearchRadius",30)

--  if util.trackTarget(findDist,findDist/2,nil) then --  also targets player boo :"(
  if attackState.findValidTarget(mcontroller.position(),findDist) then
--world.logInfo("attacking: %s %s %s",world.monsterType(self.targetId),world.callScriptedEntity(self.targetId,"entity.damageTeam"),self.targetId)
    return { timer = entity.configParameter("attackTargetHoldTime",5), burstCount = 1 } 
  end
  
  return nil, 1.5 --entity.configParameter("gardenSettings.cooldown", 15)
end

--------------------------------------------------------------------------------
function attackState.clearLOS(startPos, endPos)
local blocksInLos 
if isPleasedGiraffe() then
  blocksInLos = world.collisionBlocksAlongLine(startPos, endPos, {"Null","Block","Dynamic"})
else
  blocksInLos = world.collisionBlocksAlongLine(startPos, endPos, "Dynamic")
end
util.debugLine(startPos,vec2.add(startPos,world.distance(endPos,startPos)),"white")
return #blocksInLos == 0
end

function attackState.targInLOS(targID)
  local targPos = world.entityPosition(targID)
  return attackState.clearLOS(mcontroller.position(),targPos)
end

function attackState.isPsychoTarget(mId)
if math.random() < 0.1 and world.monsterType(mId) ~= "fireflyspawner" and world.callScriptedEntity(mId,"isGardenbot") ~= true then 
  return true
end 
  return false
end --

function attackState.findValidTarget(pos,dist)
  local monsterIds = world.entityQuery(pos, dist, { withoutEntityId = entity.id(),includedTypes = {"monster"}, order = "nearest" })

  if #monsterIds > 0 then
    for i,mId in ipairs(monsterIds) do
      if (entity.isValidTarget(mId) or (attackState.isPsychoTarget(mId))) and attackState.targInLOS(mId) then
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

  return { timer = entity.configParameter("attackTargetHoldTime"), burstCount = 1 }
end
--------------------------------------------------------------------------------
function attackState.update(dt, stateData)
  util.trackExistingTarget()

 --   if status.resource("shieldHealth") < 0 then attackState.setShieldEnabled(false) end
 
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
    local distance = world.magnitude(toTarget)
util.debugLine(mcontroller.position(),vec2.add(mcontroller.position(),toTarget),"red")
    local targJitterX = ((-stateData.burstCount)+2)-(math.random()-0.5)*mcontroller.facingDirection()
    local targJitterY = ((-stateData.burstCount*0.5)+1)-(math.random()-0.5)
    local targOffset = vec2.add(self.targetPosition,{targJitterX,targJitterY})
world.debugPoint(targOffset,"green")
    local weapOffset = entity.toAbsolutePosition(entity.configParameter("projectileSourcePosition"))
    if distance <= entity.configParameter("targetAcquisitionDistance",20) and 
      distance >= entity.configParameter("minimalTargetRadius",5) and
      attackState.clearLOS(weapOffset,targOffset) then      -- ranged attack
      local rangeTarget = world.distance(targOffset,weapOffset)
      stateData.timer = entity.configParameter("attackTargetHoldTime",5)
      attackState.setRangedAttackEnabled(true,self.projectileParams.skillName)
      attackState.setShieldEnabled(true)
      attackState.aimRanged(rangeTarget)
      
      if stateData.burstCount > self.projectileParams.shots then
        stateData.burstCount = 1
        entity.setActiveSkillName(nil)
        self.attackHoldTimer = entity.configParameter("attackHoldTime",1)
      else
        attackState.fireRanged(rangeTarget)
        stateData.burstCount = stateData.burstCount + 1
        self.attackHoldTimer = self.projectileParams.fireInterval
      end
      
--      if isPleasedGiraffe() then
--        status.addEphemeralEffect(self.projectileParams.castEffect, self.projectileParams.castTime)
--        else
          status.addEphemeralEffect("staticshield", 0.25)
--      end
      
    elseif distance < entity.configParameter("minimalTargetRadius",5) and
      distance > entity.configParameter("closeDistance",1.5)*2 and
      attackState.clearLOS(weapOffset,targOffset) then -- back off
      move(-toTarget[1])
    elseif distance <= entity.configParameter("closeDistance",1.5) then       --melee attack
      attackState.setAttackEnabled(true)
      attackState.setShieldEnabled(true)
      stateData.timer = entity.configParameter("attackTargetHoldTime",5)
      if entity.hasSound("attack") then entity.playSound("attack") end
      maybeKickPetball()
    else
      attackState.setRangedAttackEnabled(false)
      attackState.setAttackEnabled(false)
--      attackState.setShieldEnabled(false)
      move(toTarget)
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
    attackState.setRangedAttackEnabled(false)
    attackState.setAttackEnabled(false)
    attackState.setShieldEnabled(false)
    attackState.setAggressive(nil)
    return true
  else
    return false
  end
end
--------------------------------------------------------------------------------
function attackState.aimRanged(direction)
    entity.rotateGroup("projectileAim", 0)
    mcontroller.controlFace(util.toDirection(direction[1]))
    local maxRotate = math.pi / 180 * 60
    local rotateAmount 
    if isPleasedGiraffe() then rotateAmount = math.atan(-direction[2],math.abs(direction[1]))
    else rotateAmount = math.atan2(-direction[2],math.abs(direction[1])) end
    if rotateAmount > 0 then rotateAmount = math.min(rotateAmount, maxRotate/2) -- below
    else rotateAmount = math.max(rotateAmount, -maxRotate)    end
    entity.rotateGroup("projectileAim", rotateAmount);
end
--------------------------------------------------------------------------------
function attackState.fireRanged(direction)
    local pConfig = {
      power = self.projectileParams.power,
      speed = self.projectileParams.speed
    }
    local sourceOffset = entity.configParameter("projectileSourceOffset")
    local sourcePosition = entity.configParameter("projectileSourcePosition")
    if sourceOffset then
      local angle = math.atan(direction[2], math.abs(direction[1]))
      sourceOffset = vec2.rotate(sourceOffset, angle)
      sourcePosition = vec2.add(sourcePosition, sourceOffset)
    end
  if pConfig.power then
    local targetLevel = entity.level() 
    if self.targetId ~= nil and self.targetId > 0 then targetLevel = world.callScriptedEntity(self.targetId,"entity.level") or targetLevel end
    pConfig.power = pConfig.power * root.evalFunction("monsterLevelPowerMultiplier", targetLevel)
  end

    world.spawnProjectile(self.projectileParams.projectile, entity.toAbsolutePosition(sourcePosition), entity.id(), direction, false, pConfig)

    if entity.hasSound("rangedAttack") then entity.playSound("rangedAttack") end
end
--------------------------------------------------------------------------------
function attackState.setRangedAttackEnabled(enabled,name)
  if enabled then
    setAnimationState("attack", "shooting")
    entity.setActiveSkillName(name)
  else
    setAnimationState("movement", "idle")
    entity.setActiveSkillName(nil)
    entity.rotateGroup("projectileAim", 0)
  end
end
--------------------------------------------------------------------------------
function attackState.setShieldEnabled(enabled)
  if enabled then
    local maxShieldHealth = status.stat("maxHealth") --* entity.configParameter("shieldHealthMultiplier")
    local initialPercentage = 1--entity.configParameter("initialPercentage")
    status.modifyResource("shieldHealth", initialPercentage * maxShieldHealth)
    setAnimationState("movement", "shieldStart")
--  status.addEphemeralEffect("glow")
  else
    status.modifyResource("shieldHealth", 0) 
    setAnimationState("movement", "shieldEnd")
--  status.removeEphemeralEffect("glow")
  end
  self.shielded = enabled
end
--------------------------------------------------------------------------------
function attackState.setAttackEnabled(enabled)
  if enabled then
    setAnimationState("attack", "melee")
    self.attackHoldTimer = entity.configParameter("attackHoldTime",2)
  else
    setAnimationState("movement", "idle")
  end

  entity.setDamageOnTouch(enabled)
end
--------------------------------------------------------------------------------
function attackState.setAggressive(targetId)
  self.targetId = targetId

  if targetId ~= nil then
    setAnimationState("attack", "melee")
    entity.setAggressive(true)
  else
    setAnimationState("movement", "idle")
    entity.setAggressive(false)
  end
end