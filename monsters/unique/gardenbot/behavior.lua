function init(args)
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

  entity.setAggressive(false)
  entity.setDeathParticleBurst("deathPoof")
  entity.setAnimationState("movement", "idle")
  
  self.inv = inventoryManager.create()

  self.ignore = {beakseed = true, talonseed = true}  
  local harvest = entity.configParameter("gardenSettings.gatherables")
  if harvest ~= nil then
    self.harvest = {}
    for _,v in ipairs(harvest) do
      self.harvest[v] = true
    end
  end
  local compact = entity.configParameter("compactPlot")
  if compact ~= nil then
    self.compact = {}
    for _,v in ipairs(compact) do
      self.compact[v] = true
    end
  end
  self.searchDistance = entity.configParameter("gardenSettings.searchDistance")
end

function main()
  self.state.update(entity.dt())
  self.sensors.clear()
end

function damage(args)
  if entity.health() < 1 then
    self.inv.drop({all = true, position = entity.position()})
  end
  self.state.pickState(args.sourceId)
end

function move(direction)
  entity.setAnimationState("movement", "move")

  entity.setFacingDirection(direction)
  if direction < 0 then
    entity.moveLeft()
  else
    entity.moveRight()
  end
end

function canReachTarget(target, ignoreLOS, reachOffset)
  local position = nil
  local collision = false
  local offset = 1
  if reachOffset ~= nil then offset = reachOffset end
  if type(target) == "number" then
    position = world.entityPosition(target)
    collision = not entity.entityInSight(target)
  elseif type(target) == "table" then
    position = target
    collision = world.lineCollision(entity.position(), position)
  end
  if position == nil then return nil end
  local ep = entity.position()
  local fovHeight = entity.configParameter("gardenSettings.fovHeight")
  local min = nil
  local max = nil
  --Target to the left
  if ep[1] > position[1] then
    min = {position[1]+0.5, ep[2] - fovHeight/2}
    max = {ep[1]-1, ep[2] + fovHeight / 2}
  --Target to the right
  else
    min = {ep[1]+0.5, ep[2] - fovHeight/2}
    max = {position[1]-offset, ep[2] + fovHeight / 2}
  end

  local oIds = world.objectQuery(min, max, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "gardenfence" })
  if oIds[1] ~= nil then
    if ignoreLOS == true or entity.entityInSight(oIds[1]) then return false,world.entityPosition(oIds[1]) end
    return false
  end
  return ignoreLOS == true or not collision
end

function distanceSort(a, b)
  local position = entity.position()
  local da = world.magnitude(position, world.entityPosition(a))
  local db = world.magnitude(position, world.entityPosition(b))
  return da < db
end
--------------------------------------------------------------------------------
moveState = {}

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
depositState = {}
--------------------------------------------------------------------------------
function depositState.enter()
  local count = self.inv.inventoryCount()
  if count ~= nil and count > 0 then
    local position = entity.position()
    local target = depositState.findTargetPosition(position)
    if target ~= nil then
      return {
        targetId = target.targetId,
        targetPosition = target.targetPosition,
        timer = entity.randomizeParameterRange("gardenSettings.depositTime")
      }
    end
  end
  return nil,entity.configParameter("gardenSettings.cooldown")
end
--------------------------------------------------------------------------------
function depositState.update(dt, stateData)
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil then
    return true
  end
  
  local position = entity.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
  if distance < entity.configParameter("gardenSettings.interactRange") then
    entity.setAnimationState("movement", "mod")
    if stateData.timer < 0 then
      --TODO storage not working between game sessions for monsters?
      --local seeds = self.inv.remove({group = "seeds", all = true})
      --local items = self.inv.remove({all = true})
      --local result = world.callScriptedEntity(stateData.targetId, "add", items)
      --self.inv.add(seeds)
      self.inv.putInContainer(stateData.targetId)
      return true, entity.configParameter("gardenSettings.cooldown")
    end
  else
    move(util.toDirection(toTarget[1]))
  end

  return stateData.timer < 0
end
--------------------------------------------------------------------------------
function depositState.findTargetPosition(position)
  local objectIds = {}
  if entity.configParameter("gardenSettings.searchType") == "line" then
    local p1 = vec2.add({-self.searchDistance, 0}, position)
    local p2 = vec2.add({self.searchDistance, 0}, position)
    objectIds = world.objectLineQuery(p1, p2, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "storage"})
  else
    objectIds = world.objectQuery(position, self.searchDistance, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "storage" })
  end
  if entity.configParameter("gardenSettings.efficiency") then
    table.sort(objectIds, distanceSort)
  end
  for _,oId in pairs(objectIds) do
    local oPosition = world.entityPosition(oId)
    if canReachTarget(oId) and self.inv.canAddToContainer(oId) then 
      return { targetId = oId, targetPosition = oPosition }
    end
  end
  
  return nil
end
--------------------------------------------------------------------------------
harvestState = {}
--------------------------------------------------------------------------------
function harvestState.enter()
  local position = entity.position()
  local target = harvestState.findTargetPosition(position)
  if target ~= nil then
    return {
      targetId = target.targetId,
      targetPosition = target.targetPosition,
      timer = entity.randomizeParameterRange("gardenSettings.harvestTime")
    }
  end
  return nil
end
--------------------------------------------------------------------------------
function harvestState.update(dt, stateData)
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil then
    return true
  end
  
  local position = entity.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
  if distance < entity.configParameter("gardenSettings.interactRange") then
    entity.setAnimationState("movement", "mod")
    if stateData.timer < 0 then
      local result = world.callScriptedEntity(stateData.targetId, "doHarvest")
    end
  else
    move(util.toDirection(toTarget[1]))
  end

  return stateData.timer < 0
end
--------------------------------------------------------------------------------
function harvestState.findTargetPosition(position)
  local objectIds = {}
  if entity.configParameter("gardenSettings.searchType") == "line" then
    local p1 = vec2.add({-self.searchDistance, 0}, position)
    local p2 = vec2.add({self.searchDistance, 0}, position)
    --objectIds = world.objectLineQuery(p1, p2, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "farmable" })
    --TODO use vanilla props for this
    objectIds = world.objectLineQuery(p1, p2, { callScript = "canHarvest" })
  else
    --objectIds = world.objectQuery(position, self.searchDistance, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "farmable" })
    objectIds = world.objectQuery(position, self.searchDistance, { callScript = "canHarvest" })
  end
  if entity.configParameter("gardenSettings.efficiency") then
    table.sort(objectIds, distanceSort)
  end
  for _,oId in pairs(objectIds) do
    local oPosition = world.entityPosition(oId)
    if canReachTarget(oId) then 
      return { targetId = oId, targetPosition = oPosition }
    end
  end
  
  return nil
end
--------------------------------------------------------------------------------
gatherState = {}
--------------------------------------------------------------------------------
function gatherState.enter()
  local position = entity.position()
  local target = gatherState.findTargetPosition(position)
  if target ~= nil then
    return {
      targetId = target.targetId,
      targetPosition = target.targetPosition,
      timer = entity.randomizeParameterRange("gardenSettings.harvestTime")
    }
  end
  return nil
end
--------------------------------------------------------------------------------
function gatherState.update(dt, stateData)
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil or stateData.timer < 0 then
    return true
  end
  
  local position = entity.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
  if distance < entity.configParameter("gardenSettings.interactRange") then
    entity.setAnimationState("movement", "mod")
    local r = world.takeItemDrop(stateData.targetId, entity.id())
    if r ~= nil then
      self.inv.add({name = r.name, count = r.count, data = r.data})
    end
    return true
  else
    move(util.toDirection(toTarget[1]))
  end

  return false
end
--------------------------------------------------------------------------------
function gatherState.findTargetPosition(position)
  local objectIds = {}
  if entity.configParameter("gardenSettings.searchType") == "line" then
    local p1 = vec2.add({-self.searchDistance, 0}, position)
    local p2 = vec2.add({self.searchDistance, 0}, position)
    objectIds = world.itemDropQuery(p1, p2)
  else
    objectIds = world.itemDropQuery(position, self.searchDistance)
  end
  if entity.configParameter("gardenSettings.efficiency") then
    table.sort(objectIds, distanceSort)
  end
  for _,oId in pairs(objectIds) do
	local n = world.entityName(oId)
	local match = string.match(n, "%a+seed%a*")

    if match ~= nil or self.harvest[n] == true or world.itemType(n) == "consumable" then
	  if canReachTarget(oId, false, entity.configParameter("gardenSettings.interactRange")) then
        return { targetId = oId, targetPosition = world.entityPosition(oId) }
	  end
    end
  end

  return nil
end
--------------------------------------------------------------------------------
plantState = {}
--------------------------------------------------------------------------------
function plantState.enter()
  local position = entity.position()
  --if count ~= nil and count > 0 then
    local target = plantState.findTargetPosition(position)
    if target ~= nil then
      return {
        targetPosition = target.position,
        targetSeed = target.seed,
        timer = entity.randomizeParameterRange("gardenSettings.plantTime")
      }
    end
  --end
  return nil,entity.configParameter("gardenSettings.cooldown")
end
--------------------------------------------------------------------------------
function plantState.update(dt, stateData)
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil then
    return true
  end
  
  local position = entity.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
  --TODO put a delay time here
  if distance < entity.configParameter("gardenSettings.interactRange") then
    entity.setAnimationState("movement", "mod")
    if stateData.timer < 0 then
      local seed,oId = plantState.getSeedName(stateData.targetSeed)
      local item = {}
      if oId ~= nil then
        item = self.inv.takeFromContainer(oId, {name = seed, count = 1})
      end
      if item == nil then
        seed = nil
      elseif seed ~= nil then
        if world.placeObject(seed, stateData.targetPosition) then
          if oId == nil then self.inv.remove({name = seed, count = 1}) end
        else
          self.inv.add(item)
        end
      end
      if seed == nil then return true, entity.configParameter("gardenSettings.cooldown") end
    end
  else
    move(util.toDirection(toTarget[1]))
  end
  --TODO consider checking stateData.targetPosition == nil to prevent ending activity

  return stateData.timer < 0
end
--------------------------------------------------------------------------------
function plantState.findTargetPosition(position)

  local direction = entity.facingDirection()
  local basePosition = {
    math.floor(position[1] + 0.5),
    math.floor(position[2] + 0.5) - 1
  }
  
  for offset = 0, self.searchDistance, 1 do
    for d = -1, 2, 2 do
      local targetPosition = vec2.add({ offset * d, 0 }, basePosition)
      --local modName = world.mod(vec2.add({0, -1}, targetPosition), "foreground")
      --if modName == nil or not string.find(modName, "tilled") then return nil end
      --local p1 = vec2.add(targetPosition, {0, -1})
      --local p2 = vec2.add(targetPosition, {0, 1})
      --local objects = world.objectQuery(p1, p2)
      --local objects = world.objectQuery(targetPosition, 0.5)
      --if type(next(objects)) ~= "number" and canReachTarget(targetPosition) then
        local seed = plantState.getSeedName()
        if seed ~= nil then
          local d = 2
          if self.compact[seed] ~= nil then d = 1 end
          if world.placeObject("gardenbotplot" .. d, targetPosition) then
            return { position = targetPosition, seed = seed}
          end
        end
      --end
    end
  end
  return nil
end

function plantState.getSeedName(name)
  local position = entity.position()
  local search = "%a+seed%a*"
  if name ~= nil then search = name end
  local seed = self.inv.findMatch(search, self.ignore)
  if seed ~= nil then return seed,nil end
  
  local distance = 2 * self.searchDistance
  local fovHeight = entity.configParameter("gardenSettings.fovHeight")
  local min = vec2.add({-distance, -fovHeight/2}, position)
  local max = vec2.add({distance, fovHeight/2}, position)
  local objectIds = world.objectQuery(min, max, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "storage" })
  for _,oId in ipairs(objectIds) do
    seed = self.inv.matchInContainer(oId, {name = search, ignore = self.ignore})
    if seed ~= nil then return seed,oId end
  end
  return nil
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
