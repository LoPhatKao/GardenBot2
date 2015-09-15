--------------------------------------------------------------------------------
returnState = {}
--------------------------------------------------------------------------------
--function returnState.enter()
-- return returnState.enterWith({ignoreDistance = false})
--end


function returnState.enterWith(args)
    if self.spawnPoint == nil then self.spawnPoint = entity.configParameter("spawnPoint") end
    if self.homeBin ~= nil or self.spawnPoint ~= nil then
      local position = mcontroller.position()
      local range = entity.configParameter("gardenSettings.wanderRange") or 60
      local hPos = nil
      if self.homeBin ~= nil and world.entityExists(self.homeBin) then
        hPos = world.entityPosition(self.homeBin)
      else
        hPos = self.spawnPoint
      end
      local toTarget = world.distance(hPos, position)
      local distance = world.magnitude(toTarget)
      --if (type(args) == "table" and args.ignoreDistance) then world.logInfo("FORCED RETURN TO HOME") end
      if (type(args) == "table" and args.ignoreDistance) or distance > range then
	    return {
          targetPosition = hPos,
          timer = travelTime(distance)--(entity.configParameter("gardenSettings.returnTime", 15)
        }
      end
    end
  return nil,entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------
function returnState.update(dt, stateData)
  if mcontroller.liquidMovement() then dt = dt/2 end
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil then
    return true,entity.configParameter("gardenSettings.cooldown", 15)
  end

  local position = mcontroller.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
util.debugLine(mcontroller.position(),vec2.add(mcontroller.position(),toTarget),"red")
  if distance < 3 * entity.configParameter("gardenSettings.interactRange") then
    stateData.timer = -1
    self.ignoreIds = {}
    setAnimationState("movement", "idle")
  else
    if stateData.timer < 0 and (self.stuckCount > 0 or not canReachTarget(stateData.targetPosition)) then
      local p = stateData.targetPosition
      mcontroller.setPosition({p[1], p[2] + 0.5 + math.abs(mcontroller.boundBox()[2])})
      status.addEphemeralEffect("beamin",0.25)
      mcontroller.setVelocity({0,-1 * world.gravity(mcontroller.position())})
      setAnimationState("movement", "idle")
    else
      move({toTarget[1], toTarget[2]})
    end
  end

  return stateData.timer <= -1,entity.configParameter("gardenSettings.cooldown", 15)
end