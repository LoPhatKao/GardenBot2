--------------------------------------------------------------------------------
plantState = {}
--------------------------------------------------------------------------------
function plantState.enter()
  local position = mcontroller.position()
  local target = plantState.findPosition(position)
  if target ~= nil then
    return {
      targetPosition = target.position,
      targetSeed = target.seed,
      timer = travelTime(target.position),--entity.randomizeParameterRange("gardenSettings.locateTime"),
      located = false
    }
  end
  return nil,entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------
function plantState.update(dt, stateData)
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil then
    return true
  end
  
  local position = mcontroller.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
util.debugLine(mcontroller.position(),vec2.add(mcontroller.position(),toTarget),"red")
  --TODO put a delay time here
  if distance < entity.configParameter("gardenSettings.interactRange") then
 --   entity.setFacingDirection(util.toDirection(toTarget[1]))
    mcontroller.controlFace(util.toDirection(toTarget[1]))
    setAnimationState("movement", "work")
    if not stateData.located then
      stateData.located = true
      stateData.timer = entity.randomizeParameterRange("gardenSettings.plantTime")
    elseif stateData.timer < 0 then
      local seed,oId = plantState.getSeedName(stateData.targetSeed)
      if oId ~= nil then
        seed = self.inv.takeFromContainer(oId, {name = seed.name, count = 1})
      end
      if seed ~= nil then
        --TODO fail check to add to ignored seeds
        local fd = mcontroller.facingDirection()
        if world.placeObject(seed.name, stateData.targetPosition, fd, seed.parameters) then
          if oId == nil then self.inv.remove({name = seed.name, count = 1, parameters = seed.parameters}) end
          plantState.addToMemory(seed.name, stateData.targetPosition)
          self.lastSeed = nil
        return true--,entity.randomizeParameterRange("gardenSettings.plantTime")
        else
          local fp = stateData.targetPosition[1] .. "," .. stateData.targetPosition[2]
          if storage.failedMemory[fp] then
            storage.failedMemory[fp] = storage.failedMemory[fp] + 1
          else storage.failedMemory[fp] = 1 end
          if oId ~= nil then self.inv.add(seed) end
        end
      end
    end
  else
    local dy = entity.configParameter("gardenSettings.fovHeight") / 2
    move({toTarget[1], toTarget[2] + dy})
  end

  return stateData.timer < 0,entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------

function plantState.findPosition(position)
--if true then return nil end
  local seed = plantState.getSeedName()
  if seed == nil then return nil end -- lpk: dont try if no seeds available

  local sw,sh = plantState.plotSize(seed.name)
  local basePosition = {
    math.floor(position[1] + 0.5),
    math.floor(position[2] + 0.5) - 1
  }
  local d = mcontroller.facingDirection()
  local dy = math.ceil(mcontroller.boundBox()[2]) -- 
--  if string.find(self.searchType, 'lumber$') then dy = -2 end -- bleh :P
  
  for offset = 0, entity.configParameter("gardenSettings.plantDistance", 10), 1 do
--    for d = -1, 2, 2 do
      local targetPosition = vec2.add({ offset * d, dy }, basePosition)
      --local modName = world.mod(vec2.add({0, -1}, targetPosition), "foreground")
      --if modName == nil or not string.find(modName, "tilled") then return nil end
      --local p1 = vec2.add(targetPosition, {0, -1})
      --local p2 = vec2.add(targetPosition, {0, 1})
      --local objects = world.objectQuery(p1, p2)
      --local objects = world.objectQuery(targetPosition, 0.5)
      local ps = targetPosition[1] .. "," .. targetPosition[2]
      local failedMemory = storage.failedMemory[ps]
      if not world.tileIsOccupied(targetPosition) -- nothing there
        and (world.material(vec2.add({0, -1}, targetPosition), "foreground") and 1) -- has ground under
        and canReachTarget(targetPosition) -- bot can get there
        and (failedMemory == nil or failedMemory < 3) -- not ignoring that spot
        and plantState.waterDepthCheck(seed,sh,targetPosition) -- right amount of water
        and plantState.saplingHeightCheck(sw,sh,targetPosition)--lpk: if its a tree, check more stuff
        and world.placeObject("gardenbotplot" .. sw, targetPosition) then -- test plot plants ok
          return { position = targetPosition, seed = seed.name}
      end
 --   end
  end
  --TODO if seed is 2 plot, and fails, then try looking for a 1 plot seed and try again
  return nil
end
--------------------------------------------------------------------------------
function plantState.waterDepthCheck(seed,y,pos)
if not isPleasedGiraffe() then return true end -- only care if pleased gir +

local sConfig = root.itemConfig(seed.name).config
if sConfig == nil then return false end  --  world.logInfo("%s",sConfig)
  if sConfig.minImmersion then
    local minY = sConfig.minImmersion*y -- actual height on plant - cc = 3.6, rp = 2.7
    local topMin = minY - math.floor(minY) -- the .6 or .7 or w/e
    local topPos = vec2.add(pos,{0,math.floor(minY)})
    local topLiq = world.liquidAt(topPos)
    if (topLiq == nil or topMin > topLiq[2]) then 
    util.debugRect({pos[1],pos[2],topPos[1]+1,topPos[2]+1},"magenta")
    return false end
  end
  if sConfig.maxImmersion then
    local maxY = sConfig.maxImmersion*y 
    local maxPart = maxY - math.floor(maxY)
    local maxPos = vec2.add(pos,{0,math.floor(maxY)})
    local maxLiq = world.liquidAt(maxPos) 
    if (maxLiq ~= nil and maxLiq[2] > maxPart) then     
    util.debugRect({pos[1],pos[2],maxPos[1]+1,maxPos[2]+1},"magenta")
    return false end
  end
return true
end
--------------------------------------------------------------------------------
function plantState.saplingHeightCheck(x,y,pos)
  if x == "S" then x = 3 end -- x is S, so is a tree
  if pos[1] % x ~= 0 then return false end -- is not aligned properly
  
  local collisionType
  if not isPleasedGiraffe() then collisionType = "Any"  
  else collisionType = {"Null","Block","Dynamic","Platform"} end
  
  local targRect = {pos[1],pos[2],pos[1]+math.ceil(0.66*x),pos[2]+y-1}
  local blocksInLos = world.rectTileCollision(targRect,collisionType)
  
  if blocksInLos then util.debugRect(targRect,"red")
  else util.debugRect(targRect,"yellow") end
  return not blocksInLos
--[[
  local targPos = {pos[1],pos[2]+y-1}
  local blocksInLos = world.collisionBlocksAlongLine({pos[1]+(x/2),pos[2]}, {targPos[1]+(x/2),targPos[2]}, collisionType)
if self.debug and #blocksInLos > 0 then 
local bl,tr = blocksInLos[1], vec2.add(blocksInLos[#blocksInLos],{1,1})
util.debugRect({bl[1],bl[2],tr[1],tr[2]},"red")-- lbrt
elseif self.debug then
util.debugRect({pos[1],pos[2],targPos[1]+x,targPos[2]+1},"yellow")
end
  return #blocksInLos == 0
--]]
end
--------------------------------------------------------------------------------
function plantState.plotSize(name)
  if string.find(name, "sapling") then return "S",30 end
  if storage.seedMemory[name] ~= nil then 
    return storage.seedMemory[name][1], storage.seedMemory[name][2] 
  end
  bounds = root.itemConfig(name).config.orientations[1].spaces -- same data as world.objectSpaces()
  if bounds == nil then return 2,4 end
  table.sort(bounds,plantState.objectSpaceSort)  --world.logInfo("%s",bounds)
  return math.floor(bounds[#bounds][1] - bounds[1][1])+1,(bounds[#bounds][2] - bounds[1][2])+1
end
--------------------------------------------------------------------------------
function plantState.objectSpaceSort(a,b)
 if a[2] == b[2] then return a[1] < b[1] end
 return a[2] < b[2]
end

function plantState.addToMemory(name, pos)
  if storage.seedMemory[name] ~= nil then return nil end
  local seedIds = world.objectQuery(pos, 0, {name = name})
  if seedIds[1] then
  local plot,bounds
  if isPleasedGiraffe() then
--  world.logInfo("%s - %s",world.entityName(seedIds[1]),world.objectSpaces(seedIds[1]))
    bounds = world.objectSpaces(seedIds[1]) table.sort(bounds,plantState.objectSpaceSort)
    plot = {math.floor(bounds[#bounds][1] - bounds[1][1])+1,(bounds[#bounds][2] - bounds[1][2])+1}
  else
    bounds = world.callScriptedEntity(seedIds[1], "entity.boundBox")
    plot = {(bounds[3] - bounds[1]) - 2,(bounds[4] - bounds[2]) - 2}
  end
--    world.logInfo("%s %s \n%s",name,plot,bounds)
    storage.seedMemory[name] = plot
  end
end
--------------------------------------------------------------------------------
function plantState.getSeedName(name)
  local position = mcontroller.position()
  local search = entity.configParameter("gardenSettings.seed", "seed")
  if name ~= nil then search = name end
  if self.lastSeed == nil then self.lastSeed = search end
  local seed = nil
  seed = self.inv.findMatch(self.lastSeed, self.ignore)
  if seed == nil then seed = self.inv.findMatch(search, self.ignore) end
  if seed ~= nil then return seed,nil end
  
  if self.homeBin ~= nil and world.entityExists(self.homeBin) then --lpk: check homebin before randoms
      seed = self.inv.matchInContainer(self.homeBin, {name = self.lastSeed, ignore = self.ignore})
      if seed == nil then seed = self.inv.matchInContainer(self.homeBin, {name = search, ignore = self.ignore}) end
      if seed ~= nil then return seed,self.homeBin end  
  end
  
  local distance = 2 * self.searchDistance
  local fovHeight = entity.configParameter("gardenSettings.fovHeight")
  local min = vec2.add({-distance, -fovHeight/2}, position)
  local max = vec2.add({distance, fovHeight/2}, position)
  local objectIds = world.objectQuery(min, max, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "storage" })
  for _,oId in ipairs(objectIds) do
    if canReachTarget(oId) then
      seed = self.inv.matchInContainer(oId, {name = self.lastSeed, ignore = self.ignore})
      if seed == nil then seed = self.inv.matchInContainer(oId, {name = search, ignore = self.ignore}) end
      if seed ~= nil then return seed,oId end
    end
  end
  return nil
end
--------------------------------------------------------------------------------