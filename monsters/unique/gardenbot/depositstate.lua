--------------------------------------------------------------------------------
depositState = {}
--------------------------------------------------------------------------------
function depositState.enter()
  local count = self.inv.inventoryCount()
  if count ~= nil and count > 0 then
    local position = mcontroller.position()
    local target = depositState.findTargetPosition(position)
    if target ~= nil then
      if self.homeBin == nil or not world.entityExists(self.homeBin) then -- lpk: dont swap homebin unless needed
        self.homeBin = target.targetId
      end
      return {
        targetId = target.targetId,
        targetPosition = target.targetPosition,
        timer = travelTime(target.targetPosition),--entity.randomizeParameterRange("gardenSettings.locateTime"),
        located = false
      }
    end
  end
  return nil,entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------
function depositState.update(dt, stateData)
  if stateData.targetPosition == nil then
    return true,entity.configParameter("gardenSettings.cooldown", 15)
  end
  stateData.timer = stateData.timer - dt
  
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
      stateData.timer = entity.randomizeParameterRange("gardenSettings.depositTime")
      world.containerOpen(stateData.targetId)
    elseif stateData.timer < 0 then
      --TODO storage not working between game sessions for monsters
      --local seeds = self.inv.remove({group = "seeds", all = true})
      --local items = self.inv.remove({all = true})
      --local result = world.callScriptedEntity(stateData.targetId, "add", items)
      --self.inv.add(seeds)
      self.inv.putInContainer(stateData.targetId)
      world.containerClose(stateData.targetId)
      return true,entity.configParameter("gardenSettings.cooldown", 15)*2 -- lpk:ignore deposit for a while
    end
  else
    move({toTarget[1], toTarget[2]+1})
  end

  return stateData.timer < 0
end
--------------------------------------------------------------------------------
function depositState.findTargetPosition(position)
  if self.homeBin and world.entityExists(self.homeBin) and self.inv.canAddToContainer(self.homeBin) then
    local oPosition = world.entityPosition(self.homeBin)
    return { targetId = self.homeBin, targetPosition = oPosition }
  end
  local objectIds = {}
  if string.find(self.searchType, '^linear') then
    local p1 = vec2.add({-self.searchDistance, 0}, position)
    local p2 = vec2.add({self.searchDistance, 0}, position)
    objectIds = world.objectLineQuery(p1, p2, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "storage",order = "nearest"})
  elseif string.find(self.searchType, '^radial') then
    objectIds = world.objectQuery(position, self.searchDistance, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "storage",order = "nearest" })
  end
--  if entity.configParameter("gardenSettings.efficiency") then
--    table.sort(objectIds, distanceSort)
--  end
  for _,oId in pairs(objectIds) do
    local oPosition = world.entityPosition(oId)
    if canReachTarget(oId) and self.inv.canAddToContainer(oId) then 
      return { targetId = oId, targetPosition = oPosition }
    end
  end
  
  return nil
end