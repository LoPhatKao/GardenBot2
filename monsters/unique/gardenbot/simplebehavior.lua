delegate.create("simplegardenbot")
--------------------------------------------------------------------------------
simplegardenbot = {}
--------------------------------------------------------------------------------
function simplegardenbot.init(args)
  self.sensors = sensors.create()
  self.state = stateMachine.create({
    "gatherState",
    "plantState",
    "harvestState",
    "depositState",
    "moveState",
    "attackState"
  })
  self.state.leavingState = function(stateName)
    entity.setAnimationState("movement", "idle")
  end
end
--------------------------------------------------------------------------------
function simplegardenbot.main()
  self.state.update(entity.dt())
  self.sensors.clear()
end
--------------------------------------------------------------------------------
function move(direction)
  if type(direction) == "table" then direction = direction[1] end
  entity.setAnimationState("movement", "move")

  entity.setFacingDirection(direction)
  if direction < 0 then
    entity.moveLeft()
  else
    entity.moveRight()
  end
end
--------------------------------------------------------------------------------
moveState = {}
--------------------------------------------------------------------------------
function moveState.enter()
  local direction
  if math.random(100) > 50 then
    direction = 1
  else
    direction = -1
  end

  return {
    timer = entity.randomizeParameterRange("moveTimeRange"),
    direction = direction
  }
end
--------------------------------------------------------------------------------
function moveState.update(dt, stateData)
  if self.sensors.collisionSensors.collision.any(true) then
    stateData.direction = -stateData.direction
  end
  
  local b,t = canReachTarget(vec2.add(entity.position(), {stateData.direction, 0}))
  if not b and t ~= nil then
    local distance = world.distance(t, entity.position())
    stateData.direction = -util.toDirection(distance[1])
  end

  if entity.onGround() and
     not self.sensors.nearGroundSensor.collisionTrace.any(true) and
     self.sensors.midGroundSensor.collisionTrace.any(true) then
    entity.moveDown()
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
    local toTarget = world.distance(self.targetPosition, entity.position())

    if world.magnitude(toTarget) < entity.configParameter("attackDistance") then
      attackState.setAttackEnabled(true)
    else
      attackState.setAttackEnabled(false)
      move(util.toDirection(toTarget[1]))
    end
  end

  if self.targetId == nil then
    stateData.timer = stateData.timer - dt
  else
    stateData.timer = entity.configParameter("attackTargetHoldTime")
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