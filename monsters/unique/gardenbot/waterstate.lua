--------------------------------------------------------------------------------
waterState = {}
--------------------------------------------------------------------------------
function waterState.enter()
  if not isPleasedGiraffe() then return nil, 9999 end -- get out, and dont come back!
  
  local position = mcontroller.position()
  local target = waterState.findPosition(position)
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
function waterState.update(dt, stateData)
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
      if stateData.till == nil then
          storage.waterMemory = world.mod(vec2.add({0, -1}, stateData.targetPosition), "foreground")
      else
--        local modPos = vec2.add({0.5, math.random(1,3)/2}, stateData.targetPosition)
        local yoff = waterState.sloped(stateData.targetPosition) and 1 or 0.75 
        local modPos = vec2.add({0.5, yoff}, stateData.targetPosition)
        world.spawnProjectile("watersprinkledroplet", modPos, entity.id(), {0, -1}, false, {power = 0})
        if entity.hasSound("water") then entity.playSound("water") end
        storage.waterMemory = nil
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
function waterState.sloped(pos)
return world.material({pos[1]+mcontroller.facingDirection(),pos[2]},"foreground") and 1
--local ml = world.material({pos[1]-1,pos[2]},"foreground") if ml then return true end
--local mr = world.material({pos[1]+1,pos[2]},"foreground") if mr then return true end
--return false
end
--------------------------------------------------------------------------------
function waterState.findPosition(position)
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
      if (storage.waterMemory and modName == storage.waterMemory ) then
        local m1 = world.material(targetPosition, "foreground")
        local m2 = world.material(vec2.add({0, -1}, targetPosition), "foreground")
        success = not m1 and m2 == storage.matMemory
      elseif (storage.waterMemory == nil and modName and string.find(modName, "tilleddry")) then
        success = true
        storage.matMemory = world.material(vec2.add({0, -1}, targetPosition), "foreground")
        storage.waterMemory = modName
      end
      if canReachTarget(targetPosition) and success then
        return { position = targetPosition, till = storage.waterMemory}
      end
    end
  end
  return nil
end