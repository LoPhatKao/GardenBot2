--------------------------------------------------------------------------------
grassState = {}
--------------------------------------------------------------------------------
function grassState.enter()
  local position = mcontroller.position()
  local target = grassState.findPosition(position)
  if target ~= nil then
    return {
      targetPosition = target.position,
      grass = target.grass,
      timer = entity.randomizeParameterRange("gardenSettings.locateTime"),
      located = false
    }
  end
  return nil,entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------
function grassState.update(dt, stateData)
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
      if stateData.grass == nil then
        storage.grassMemory = world.mod(vec2.add({0, -1}, stateData.targetPosition), "foreground")
      else
        local modPos = vec2.add({0, -1}, stateData.targetPosition)
        local wmod = world.mod(modPos, "foreground")
        if wmod == nil -- nothing there
        or not world.damageTiles({modPos}, "foreground", position, "plantish", 1) then -- under tree?
          world.placeMod(modPos, "foreground", stateData.grass)
          storage.grassMemory = nil
        end
        if entity.hasSound("grass") then entity.playSound("grass") end
      end
      return true,1
    end
  else
    local dy = entity.configParameter("gardenSettings.fovHeight") / 2
    move({toTarget[1], toTarget[2] + dy})
  end

  return stateData.timer < 0,entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------
function grassState.findPosition(position)
  position[2] = position[2]+math.ceil(mcontroller.boundBox()[2]) -- lpk: fix so lumbers can do grass too
  local basePosition = {
    math.floor(position[1] + 0.5),
    math.floor(position[2] + 0.5) - 1
  }
  
  for offset = 1, entity.configParameter("gardenSettings.plantDistance", 10), 1 do
    for d = -1, 2, 2 do
      local targetPosition = vec2.add({ offset * d, 0 }, basePosition)
      local modName = world.mod(vec2.add({0, -1}, targetPosition), "foreground")
--  world.debugText("%s",modName,vec2.add({0, -4+offset%3}, targetPosition),"white")
      local success = false
      if (storage.grassMemory and (modName == nil or (modName ~= storage.grassMemory and not string.find(modName,"tilled") and not isOre(modName))) ) then
        local m1 = world.material(targetPosition, "foreground")
        local m2 = world.material(vec2.add({0, -1}, targetPosition), "foreground")
        success = not m1 and m2 == storage.matMemory
      elseif (storage.grassMemory == nil and modName and string.find(modName, "grass")) then
        success = true
        storage.matMemory = world.material(vec2.add({0, -1}, targetPosition), "foreground")
      end
      if canReachTarget(targetPosition) and success then
        return { position = targetPosition, grass = storage.grassMemory}
      end
    end
  end
  return nil
end