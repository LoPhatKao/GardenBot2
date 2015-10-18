--------------------------------------------------------------------------------
harvestState = {}
--------------------------------------------------------------------------------
function harvestState.enter()
  local position = mcontroller.position()
  local target = nil
  local type = nil
  if string.find(self.searchType, 'farm$') then 
    type = "farm"
    target = harvestState.findFarmPosition(position)
  elseif string.find(self.searchType, 'lumber$') then
    type = "lumber"
    target = harvestState.findLumberPosition(position)
  end
  if target ~= nil then
    return {
      targetId = target.targetId,
      targetPosition = target.targetPosition,
      timer = travelTime(target.targetPosition)+1, --entity.randomizeParameterRange("gardenSettings.locateTime"),
      located = false,
      count = 0,
      type = type
    }
  end
  return nil,entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------
function harvestState.update(dt, stateData)
  if mcontroller.liquidMovement() then dt = dt/2 end
  if stateData.type == "farm" then 
    return harvestState.farmUpdate(dt, stateData)
  elseif stateData.type == "lumber" then
    return harvestState.lumberUpdate(dt, stateData)
  end
end
--------------------------------------------------------------------------------
function harvestState.farmUpdate(dt, stateData)
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil or not world.entityExists(stateData.targetId) then
    return true
  end
  
  local position = mcontroller.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
  util.debugLine(mcontroller.position(),vec2.add(mcontroller.position(),toTarget),"red")
  if distance < entity.configParameter("gardenSettings.interactRange") then
    setAnimationState("movement", "work")
    mcontroller.controlFace(util.toDirection(toTarget[1]))
    if not stateData.located then
      stateData.located = true
      stateData.timer = entity.randomizeParameterRange("gardenSettings.harvestTime")
    elseif stateData.timer < 0 then
      if entity.hasSound("work") then entity.playSound("work") end
      harvestState.harvestFarmable(stateData.targetId)
      return true, entity.configParameter("gardenSettings.cooldown", 15)/2
      --entity.randomizeParameterRange("gardenSettings.harvestTime")
    end
  else
    move(toTarget)
  end

  return stateData.timer < 0,entity.configParameter("gardenSettings.cooldown", 15)
--  entity.randomizeParameterRange("gardenSettings.harvestTime")
end
--------------------------------------------------------------------------------
function harvestState.findFarmPosition(position)
  local objectIds = {}
  if string.find(self.searchType, '^linear') then
    local p1 = vec2.add({-self.searchDistance, 0}, position)
    local p2 = vec2.add({self.searchDistance, 1}, position)
    objectIds = world.objectQuery(p1, p2, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "farmable",order = "nearest" })
  elseif string.find(self.searchType, '^radial') then
    objectIds = world.objectQuery(position, self.searchDistance, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "farmable",order = "nearest" })
  end
--  if entity.configParameter("gardenSettings.efficiency") then
--    table.sort(objectIds, distanceSort)
--  end
  for _,oId in pairs(objectIds) do
    local oPosition = world.entityPosition(oId)
    if harvestState.canHarvest(oId) and canReachTarget(oId) then
      return { targetId = oId, targetPosition = oPosition }
    end
  end
  
  return nil
end
--------------------------------------------------------------------------------
function harvestState.lumberUpdate(dt, stateData)
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil or not world.entityExists(stateData.targetId) then
    return true,entity.configParameter("gardenSettings.cooldown", 15)
  end
  
  local position = mcontroller.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
util.debugLine(mcontroller.position(),vec2.add(mcontroller.position(),toTarget),"red")
  if distance < entity.configParameter("gardenSettings.interactRange") then
    if not stateData.located then
      stateData.located = true
      stateData.timer = 0
    end
    if stateData.timer <= 0 then
 --     entity.setFacingDirection(util.toDirection(toTarget[1]))
      mcontroller.controlFace(util.toDirection(toTarget[1]+1)) --lpk: +1 to face center of tree
      setAnimationState("attack", "melee")
      stateData.timer = entity.randomizeParameterRange("gardenSettings.harvestTime")
      local tileDmg = stateData.count/2 --lpk: sliding damage - 0,1,2,3 .. etc
      stateData.count = stateData.count + 1
      local dmgtiles = {vec2.add(stateData.targetPosition,{0,1}),stateData.targetPosition,vec2.add(stateData.targetPosition,{0,-1})}
--      world.damageTiles({stateData.targetPosition}, "foreground", position, "plantish", 2) -- original
      world.damageTiles(dmgtiles, "foreground", position, "plantish", tileDmg)
      if entity.hasSound("work") then entity.playSound("work") end
    end  
  else
    local dy = entity.configParameter("gardenSettings.fovHeight") / 2
    move({toTarget[1], toTarget[2] + dy})
  end

  if stateData.timer < 0 or stateData.count > 9 then
    self.ignoreIds[stateData.targetId] = true
    return true,entity.configParameter("gardenSettings.cooldown", 15)
  end
  return false
end
--------------------------------------------------------------------------------
function harvestState.findLumberPosition(position)
  local objectIds = {}
  if string.find(self.searchType, '^linear') then
    local p1 = vec2.add({-self.searchDistance, 0}, position)
    local p2 = vec2.add({self.searchDistance, 1}, position)
    objectIds = world.entityQuery(p1, p2, {notAnObject = true,order = "nearest"})
  elseif string.find(self.searchType, '^radial') then
    objectIds = world.entityQuery(position, self.searchDistance, {notAnObject = true,order = "nearest"})
  end
--  if entity.configParameter("gardenSettings.efficiency") then
--    table.sort(objectIds, distanceSort)
--  end
  for _,oId in pairs(objectIds) do
    local oPosition = world.entityPosition(oId)
    oPosition[2] = oPosition[2] + 1
    if not self.ignoreIds[oId] and world.entityType(oId) == "plant" and canReachTarget(oId) then 
      return { targetId = oId, targetPosition = oPosition }
    end
  end
  
  return nil
end
--------------------------------------------------------------------------------
function harvestState.canHarvest(oId)
  local stage = nil
  if world.farmableStage then stage = world.farmableStage(oId) end
--  local interactions = world.callScriptedEntity(oId, "entity.configParameter", "interactionTransition", nil)
  local interactions = world.callScriptedEntity(oId, "entity.configParameter", "stages",nil)--..tostring(stage+1)..".harvestPool", nil)
--  if interactions then world.logInfo("%d : %s",stage,interactions[stage+1].harvestPool) end
  if stage ~= nil and interactions ~= nil and interactions[stage+1].harvestPool ~= nil then
      return true
  end
  return false
end
--------------------------------------------------------------------------------
function percentile(pct)
  if pct == nil then pct = 1 end
  math.randomseed(os.time()*math.random())
  return (1-(math.random(100)/100))*pct
end

function harvestState.harvestFarmable(oId) -- rewritten by LoPhatKao june2015
--	world.logInfo("trying to harvest")
  if not world.entityExists(oId) then return end
  local forceSeed = true
  local pos = world.entityPosition(oId)
  local stage = nil
  if world.farmableStage then stage = world.farmableStage(oId) end
  local interactions = world.callScriptedEntity(oId, "entity.configParameter", "stages",nil)
  if stage ~= nil and interactions ~= nil and interactions[stage+1].harvestPool ~= nil then

    local hpname = interactions[stage+1].harvestPool
    local stageReset = interactions[stage+1].resetToStage ~= nil
    -- try to 'press E'
    if math.random() <= storage.efficiency and world.damageTiles({pos},"foreground",pos,"plantish",1,1) then
      storage.efficiency = math.min(1.0,storage.efficiency + 0.001)  --world.logInfo("%s",storage.efficiency)
      return
    else 
      if stageReset then storage.efficiency = math.max(0.25,storage.efficiency - 0.001) end 
      world.breakObject(oId,false)  -- snip ;D
      return
    end
  end
	--rc14 remove legacy code
end
