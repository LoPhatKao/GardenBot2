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
    local p2 = vec2.add({self.searchDistance, 0}, position)
    objectIds = world.objectLineQuery(p1, p2, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "farmable",order = "nearest" })
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
    local p2 = vec2.add({self.searchDistance, 0}, position)
    objectIds = world.entityLineQuery(p1, p2, {notAnObject = true,order = "nearest"})
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
  local forceSeed = true
  local pos = world.entityPosition(oId)
  local stage = nil
  if world.farmableStage then stage = world.farmableStage(oId) end
  local interactions = world.callScriptedEntity(oId, "entity.configParameter", "stages",nil)
  if stage ~= nil and interactions ~= nil and interactions[stage+1].harvestPool ~= nil then
if math.random() <0.8 and world.damageTiles({pos},"foreground",pos,"plantish",1,1) then return end

    local hpname = interactions[stage+1].harvestPool
    local stageReset = interactions[stage+1].resetToStage == nil
    -- try pleased giraffe method
    if isPleasedGiraffe() then world.spawnTreasure(pos,hpname,entity.level()) world.breakObject(oId, stageReset) return end
    -- try lpk's workaround
    if harvestPools.spawnTreasure and harvestPools.getPool(hpname) then 
    hpst=harvestPools.spawnTreasure(pos,hpname) 
    world.breakObject(oId, hpst and stageReset) return end

    -- recreate vanilla harvestpools - cant find way to access them (in spirited)
    -- only works cause vanilla is pretty standardized
    -- check item is valid before trying to spawn - total unknowns will only drop plantfibre then seed on break
    local pname = string.sub(hpname,0,string.find(hpname,"Harvest")-1)
    local numRnd = 1
    if percentile() <= 0.3 then numRnd = 3 else numRnd = 2 end
    for i = 1,numRnd do
      if percentile() < 0.6 then -- farmable 
        local oname = pname
        -- special cases coffee->coffeebeans + sugarcane->sugar
        if pname == "coffee" then oname = "coffeebeans" end
        if pname == "sugarcane" then oname = "sugar" end
        
        if string.len(world.itemType(oname)) > 0 then -- itemtype returns "" for invalid, len sees "" as 0 
          world.spawnItem(oname,{pos[1], pos[2] + 0.5},1)
          if self.harvest[string.lower(oname)] == nil then self.harvest[string.lower(oname)] = true end
        end
      end
      if percentile() < 0.2 then -- seed
        if string.len(world.itemType(pname.."seed")) > 0 then
          world.spawnItem(pname.."seed",{pos[1], pos[2] + 0.5},1)
          forceSeed = false
        end
      end
      if percentile() < 0.2 then -- plantfibre
        world.spawnItem("plantfibre",{pos[1], pos[2] + 0.5},1)
      end
    
    end
  end
	
  world.breakObject(oId,not forceSeed) -- break plant, false force drops 1 seed
end

--[[  --lpk: old func, drops used to be in the *seed.object itself
function harvestState.harvestFarmable(oId)
  local stage = "2"
  if world.farmableStage then stage = world.farmableStage(oId) end
  local drops = world.callScriptedEntity(oId, "entity.configParameter", "interactionTransition." .. tostring(stage) .. ".dropOptions", nil)
  --world.callScriptedEntity(oId, "entity.randomizeParameter", "interactionTransition." .. stage .. ".dropOptions")
    if drops then
      local pos = world.entityPosition(oId)
      local i = 2
      local odds = drops[1]
      while drops[i] do
        if drops[i+1] == nil or math.random() < odds then
          local j = 1
          while drops[i][j] do
            local name = drops[i][j].name
            if self.harvest[string.lower(name)] == nil and world.itemType(name) == "generic" then
              self.harvest[string.lower(name)] = true
            end
            world.spawnItem(name, {pos[1], pos[2] + 1}, drops[i][j].count)
            j = j + 1
          end
          break
        end
        i = i + 1
      end
    end
    world.callScriptedEntity(oId, "entity.break")
end
--]]
