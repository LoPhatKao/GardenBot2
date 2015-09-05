--------------------------------------------------------------------------------
idleState = {}
--------------------------------------------------------------------------------
function idleState.enter()
  if self.state.hasState() then return nil,entity.configParameter("gardenSettings.cooldown", 15) end
  return {}
end
--------------------------------------------------------------------------------
function idleState.update(dt, stateData)
  setAnimationState("movement", "idle")
  --world.logInfo("Idling")
  if not self.state.pickState() then
    --world.logInfo("No state found")
    self.state.pickState({ ignoreDistance = true })
  end
  return true,entity.configParameter("gardenSettings.cooldown", 15)
end