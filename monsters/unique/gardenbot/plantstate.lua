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
    entity.setAnimationState("movement", "work")
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
      if not world.tileIsOccupied(targetPosition) and canReachTarget(targetPosition) and (failedMemory == nil or failedMemory < 3) then
        if seed ~= nil then
          local sw,sh = plantState.plotSize(seed.name)
		      local shCheck = plantState.saplingHeightCheck(sw,sh,targetPosition)--lpk: if its a tree, check more stuff
		      if shCheck and world.placeObject("gardenbotplot" .. sw, targetPosition) then
            return { position = targetPosition, seed = seed.name}
          end
        end
      end
 --   end
  end
  --TODO if seed is 2 plot, and fails, then try looking for a 1 plot seed and try again
  return nil
end
--------------------------------------------------------------------------------
function plantState.saplingHeightCheck(x,y,pos)
  if x == "S" then x = 3 end -- x is S, so is a tree
  if pos[1] % x ~= 0 then return false end -- is not aligned properly
  
  local targPos = {pos[1],pos[2]+y-1}
  local blocksInLos = world.collisionBlocksAlongLine(pos, targPos, "Any")
  
if self.debug and #blocksInLos > 0 then 
local bl,tr = blocksInLos[1], vec2.add(blocksInLos[#blocksInLos],{1,1})
util.debugRect({bl[1],bl[2],tr[1],tr[2]},"red")-- lbrt
elseif self.debug then
util.debugRect({pos[1],pos[2],targPos[1]+1,targPos[2]+1},"yellow")
end
  return #blocksInLos == 0
end
--------------------------------------------------------------------------------
function plantState.plotSize(name)
  if string.find(name, "sapling") then return "S",20 end
  if storage.seedMemory[name] ~= nil then 
    return storage.seedMemory[name][1], storage.seedMemory[name][2] 
  end
  return 2,4
end
--------------------------------------------------------------------------------
function plantState.addToMemory(name, pos)
  if storage.seedMemory[name] ~= nil then return nil end
  local seedIds = world.objectQuery(pos, 0, {name = name})
  if seedIds[1] then
    local bounds = world.callScriptedEntity(seedIds[1], "entity.boundBox")
    local plot = {(bounds[3] - bounds[1]) - 2,(bounds[4] - bounds[2]) - 2}
--    world.logInfo("%s%s",name,plot)
    storage.seedMemory[name] = plot
  end
end
--------------------------------------------------------------------------------
function plantState.getSeedName(name)
  local position = mcontroller.position()
  local search = entity.configParameter("gardenSettings.seed", "seed")
  if name ~= nil then search = name end
  local seed = nil
  seed = self.inv.findMatch(self.lastSeed, self.ignore)
  if seed == nil then seed = self.inv.findMatch(search, self.ignore) end
  if seed ~= nil then return seed,nil end
  
  if self.homeBin ~= nil and world.entityExists(self.homeBin) then --lpk: check homebin before randoms
      seed = self.inv.matchInContainer(self.homeBin, {name = search, ignore = self.ignore})
      if seed ~= nil then return seed,self.homeBin end  
  end
  
  local distance = 2 * self.searchDistance
  local fovHeight = entity.configParameter("gardenSettings.fovHeight")
  local min = vec2.add({-distance, -fovHeight/2}, position)
  local max = vec2.add({distance, fovHeight/2}, position)
  local objectIds = world.objectQuery(min, max, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "storage" })
  for _,oId in ipairs(objectIds) do
    if canReachTarget(oId) then
      seed = self.inv.matchInContainer(oId, {name = search, ignore = self.ignore})
      if seed ~= nil then return seed,oId end
    end
  end
  return nil
end
--------------------------------------------------------------------------------