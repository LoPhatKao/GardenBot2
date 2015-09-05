--------------------------------------------------------------------------------
tillState = {}
--------------------------------------------------------------------------------
function tillState.enter()
  local position = mcontroller.position()
  local target = tillState.findPosition(position)
  if target ~= nil then
    return {
      targetPosition = target.position,
      till = target.till,
      timer = entity.randomizeParameterRange("gardenSettings.locateTime"),
      located = false
    }
  end
  return nil,entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------
function tillState.update(dt, stateData)
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
    entity.setAnimationState("movement", "work")
    if not stateData.located then
      stateData.located = true
      stateData.timer = entity.randomizeParameterRange("gardenSettings.plantTime")
    elseif stateData.timer < 0 then
      local modPos = vec2.add({0, -1}, stateData.targetPosition)
      if stateData.till == nil then
        local modName = world.mod(modPos, "foreground")
        if isPleasedGiraffe() and modName == "tilled" then modName = "tilleddry" end
        storage.tillMemory = modName
      else        
        if world.mod(modPos, "foreground") == nil -- nothing there
        or not world.damageTiles({modPos}, "foreground", position, "plantish", 1) then -- under tree?
          world.placeMod(modPos, "foreground", stateData.till)
        end
        if entity.hasSound("till") then entity.playSound("till") end
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
function tillState.findPosition(position)
  position[2] = position[2]+math.ceil(mcontroller.boundBox()[2]) -- lpk: fix so lumbers can do till too
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
      if (storage.tillMemory and (modName == nil or (modName ~= storage.tillMemory and string.find(modName, "grass")))) then
        local m1 = world.material(targetPosition, "foreground")
        local m2 = world.material(vec2.add({0, -1}, targetPosition), "foreground")
        success = not m1 and m2 == storage.matMemory
      elseif (storage.tillMemory == nil and modName and string.find(modName, "tilled")) then
        success = true
        storage.matMemory = world.material(vec2.add({0, -1}, targetPosition), "foreground")
      end
      if canReachTarget(targetPosition) and success then
        return { position = targetPosition, till = storage.tillMemory}
      end
    end
  end
  return nil
end