--------------------------------------------------------------------------------
mineState = {}
--------------------------------------------------------------------------------
function mineState.enter()
  local position = mcontroller.position()
  local target = mineState.findPosition(position)
  if target ~= nil then
    return {
      targetPosition = target.position,
      mine = target.mine,
      layer = target.layer,
      timer = entity.randomizeParameterRange("gardenSettings.locateTime"),
      located = false
    }
  end
  return nil,entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------
function mineState.update(dt, stateData)
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil then
    return true
  end
  
  local position = mcontroller.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
util.debugLine(mcontroller.position(),vec2.add(mcontroller.position(),toTarget),"red")
  if distance < entity.configParameter("gardenSettings.interactRange") then
--    entity.setFacingDirection(util.toDirection(toTarget[1]))
    mcontroller.controlFace(util.toDirection(toTarget[1]))
    setAnimationState("movement", "work")
    if not stateData.located then
      stateData.located = true
      stateData.timer = entity.randomizeParameterRange("gardenSettings.plantTime")
    elseif stateData.timer < 0 then
      if stateData.mine == nil then
        storage.mineMemory = world.mod(vec2.add({0, -1}, stateData.targetPosition), stateData.layer)
      else
        local modPos = vec2.add({0, -1}, stateData.targetPosition)
        if stateData.layer == "background" then modPos = stateData.targetPosition end
        if storage.mineMemory == world.mod(modPos,stateData.layer) then
        world.damageTiles({modPos}, stateData.layer, position, "plantish", 1) -- under tree?
        -- placeMaterial wouldnt work, modswap workaround
          world.placeMod(modPos,stateData.layer,"roots")
          world.damageTiles({modPos}, stateData.layer, position, "plantish", 1)
          world.spawnItem(dropNameFromMod(storage.mineMemory),stateData.targetPosition,1)
        if entity.hasSound("mine") then entity.playSound("mine") end
        end
        storage.mineMemory = nil
      end
      return true, 1
    end
  else
    local dy = entity.configParameter("gardenSettings.fovHeight") / 2
    move({toTarget[1], toTarget[2] + dy})
  end

  return stateData.timer < 0,entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------
function mineState.findPosition(position)
  position[2] = position[2]+mcontroller.boundBox()[2]+1 -- lpk: fix so lumbers can do mine too
  local basePosition = {
    math.floor(position[1] + 0.5),
    math.floor(position[2] + 0.5) - 1
  }
  local layer = "foreground"
--  world.debugPoint({basePosition[1]+0.5,basePosition[2]},"#AFF000")
  if storage.mineMemory ~= nil then storage.mineMemory = nil end
  for offset = 1, entity.configParameter("gardenSettings.plantDistance", 10), 1 do
    for d = -1, 2, 2 do
      local targetPosition = vec2.add({ offset * d, 0 }, basePosition)
      local modName = world.mod(vec2.add({0, -1}, targetPosition), "foreground")
--  world.debugText("%s",modName,vec2.add({0, -4+offset%3}, targetPosition),"white")
--world.debugPoint(vec2.add(targetPosition,{0.5,-0.5}),"white")
      local success = false
      if (storage.mineMemory and storage.mineMemory == modName) then
        local m1 = world.material(targetPosition, "foreground")
        local m2 = world.material(vec2.add({0, -1}, targetPosition), "foreground")
        success = not m1 and m2 == storage.matMemory
      elseif (storage.mineMemory == nil and modName and isOre(modName)) then
        success = true
        storage.matMemory = world.material(vec2.add({0, -1}, targetPosition), "foreground")
        storage.mineMemory = modName  -- instamine
      end
      if not success then -- check bg too
        for yoff = 0, entity.configParameter("gardenSettings.fovHeight"),1 do
          targetPosition = vec2.add({ offset * d, yoff }, basePosition)
--world.debugPoint(vec2.add(targetPosition,{0.5,0.5}),"yellow")
          if world.material(targetPosition, "background") then
            modName = world.mod(targetPosition,"background")
            if modName and isOre(modName) then
              storage.mineMemory = modName
              layer = "background"
              success = true
              break
            end
          end
        end
      end
      if success and canReachTarget(targetPosition) then
        return { position = targetPosition, mine = storage.mineMemory, layer = layer}
      end
    end
  end
  return nil
end