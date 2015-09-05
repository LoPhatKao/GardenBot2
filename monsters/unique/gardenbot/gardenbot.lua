delegate.create("gardenbot")
--------------------------------------------------------------------------------
gardenbot = {}
profilerApi = {}
--------------------------------------------------------------------------------
function isGardenbot() return true end
--------------------------------------------------------------------------------
function gardenbot.init(args)
  entity.setDeathParticleBurst("deathPoof")
  entity.setAnimationState("movement", "idle")
  entity.setAggressive(false)
  
  self.inv = inventoryManager.create()

  self.ignore = {beakseed = true, talonseed = true, seedpile = true}
  self.ignoreIds = {}
  storage.seedMemory = {}
  storage.failedMemory = {}
  local harvest = entity.configParameter("gardenSettings.gatherables")
  if harvest ~= nil then
    self.harvest = {}
    self.harvestMatch = {}
    self.harvestType = {}
    for _,v in ipairs(harvest) do
      if type(v) == "string" then self.harvest[string.lower(v)] = true end
      if type(v) == "table" then
        for h,t in pairs(v) do
          if t == "match" then table.insert(self.harvestMatch, h) end
          if t == "type" then self.harvestType[string.lower(h)] = true end
        end
      end
    end
  end
  self.searchType = entity.configParameter("gardenSettings.searchType")
  self.searchDistance = entity.configParameter("gardenSettings.searchDistance")
  
  self.lastMoveDirection = 1
  
  script.setUpdateDelta(10)
  self.isCodeProfiling = type(profilerApi.init) == "function" and false
  if self.isCodeProfiling then profilerApi.init() end
end
--------------------------------------------------------------------------------
function gardenbot.damage(args)
  if args.sourceId > 0 then -- not a player, hax hp
    status.setResource("health", status.stat("maxHealth"))
  end

  if entity.health() <= 0 and not self.dead then -- lpk: also check dead to fix dupe exploit ;(
--util.debugLog("status: %s\nscript: %s",status,script)
  if self.isCodeProfiling then profilerApi.logData() end
    local spawner = nil
    if entity.type() then spawner = entity.type() .. "spawner" end
    if spawner ~= nil then self.inv.add({name = spawner, count = 1}) end
    self.inv.drop({all = true, position = mcontroller.position()})
    self.dead = true
    if entity.hasSound("dead") then entity.playSound("dead") end
  else
  self.state.pickState(args.sourceId) -- not dead, attack back
  end
end
--------------------------------------------------------------------------------
function cooldown(base)
if base == nil then base = entity.configParameter("gardenSettings.cooldown", 15) end
if type(base) ~= "number" then return 1 end
return (base + math.random(base))/2
end

--------------------------------------------------------------------------------
function canReachTarget(target, ignoreLOS)
  local position = nil
  local pad = 1.2
  if type(target) == "number" then
    position = world.entityPosition(target)
    pad = pad + entity.configParameter("gardenSettings.interactRange") / 2
  elseif type(target) == "table" then
    position = target
  end
  if position == nil then return nil end
  local collision = false
  local ep = mcontroller.position()

  local blocks = world.collisionBlocksAlongLine(ep, position, "Any", 2)
  collision = blocks[1] ~= nil
  if string.find(self.searchType, 'lumber$') then collision = #blocks == 2 end
  local fovHeight = entity.configParameter("gardenSettings.fovHeight")
  local min = nil
  local max = nil
  ep[2] = math.ceil(mcontroller.boundBox()[2] + ep[2] + 0.5)-- lpk: fix for lumber foot pos
  --Target to the left
  if ep[1] > position[1] then
    min = {position[1]+pad, ep[2] - (fovHeight/2)}
    max = {ep[1]-pad, ep[2] + (fovHeight/2)}
  --Target to the right
  else
    min = {ep[1]+pad, ep[2] - (fovHeight/2)}
    max = {position[1]-pad, ep[2] + (fovHeight/2)}
  end

  local oIds = world.objectQuery(min, max, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "gardenfence" })
  if oIds[1] ~= nil then
     return false,world.entityPosition(oIds[1])
  end
  return ignoreLOS == true or not collision
end
--------------------------------------------------------------------------------
function distanceSort(a, b)
  local position = mcontroller.position()
  local da = world.magnitude(position, world.entityPosition(a))
  local db = world.magnitude(position, world.entityPosition(b))
  return da < db
end
--------------------------------------------------------------------------------
function isOre(modName)
oreList = {
"aegisalt","coal","copper","corefragment","crystal","diamond","fossil","gold","iron",
"lead","moonstone","platinum","plutonium","prisilite","rubium","silverore","solarium",
"sulphur","titanium","trianglium","uranium","violium"
}
  for i,v in ipairs(oreList) do
    if v == modName then return true end
  end
  return false
end

function dropNameFromMod(modName)
oreMap = {
"aegisaltore","coalore","copperore","corefragmentore","crystal","diamond","fossilore","goldore","ironore", 
"lead","moonstoneore","platinumore","plutoniumore","prisiliteore","rubiumore","silverore","solariumore",
"sulphur","titaniumore","triangliumore","uraniumore","violiumore"
}
  for i,v in ipairs(oreMap) do
    if string.find(v,modName) then return v end
  end
  return "perfectlygenericitem" -- should never get here, but if it happens...
end

--------------------------------------------------------------------------------
function touchingFenceDirection(mcPos,moveDir)
  --lpk: called by move, check for fence here, returns a direction
  -- for some reason profiling makes this not work?!wtfh
  local outDir = util.toDirection(moveDir)   
  local b,t = canReachTarget(vec2.add(mcPos, {outDir*1.5, 0}))
  if not b and t ~= nil then -- hit garden fence
    local distance = world.distance(t, mcPos)
    outDir = -util.toDirection(distance[1]) -- bounce
	  local passDir = util.toDirection(distance[1]) -- passthru to homebin maybe?
    local binPos = entity.configParameter("spawnPoint")-- use spawn if no homebin
	  if self.homeBin ~= nil and world.entityExists(self.homeBin) then
	    binPos = world.entityPosition(self.homeBin)
	  end
	  local binDist = world.distance(binPos, mcPos)
	  local binDir = util.toDirection(binDist[1])
	  if binDir == passDir then 
		  outDir = passDir 
	  end  
--	if mcontroller.onGround() then
--    mcontroller.setVelocity({moveDir * world.gravity(mcontroller.position()),0})
--  end
  if self.debug then
    world.debugText("%s",outDir,vec2.add(t,{-0.5,3}),"yellow")
    util.debugRect({t[1],t[2],t[1]+1,t[2]+3},"yellow")
  end
  end
 return outDir * math.abs(moveDir)
end
--------------------------------------------------------------------------------

function maybeKickPetball() -- kick ball instead of damaging it, not that bot did dmg anyway >.>
  if self.targetId and world.entityExists(self.targetId) 
  and world.monsterType(self.targetId) == "petball" then
    world.callScriptedEntity(self.targetId, "punt", mcontroller.facingDirection())
    return true
  end
  return false
end
--------------------------------------------------------------------------------
function chatNearbyPlayerOrBot()
-- report current inventory to players
-- binary art for bots - icons built into hobo etc.

  --  entity.say("01000101") "ð«"
  --  entity.say("ԑ)҈ (Ӟ") "E{0}3" "∈)☼(∋"  "ԑ(þ)Ӟ"

  -- entity.say doesnt work, may have to spawn a temp item like gardenplot that only does say then breaks
end

--------------------------------------------------------------------------------
-- movement funcs, mostly cribbed from groundmovement.lua
--------------------------------------------------------------------------------
-- NOTE: this will be inaccurate if called more than once per tick
function checkStuck()
  local newPos = mcontroller.position()
  if newPos[1] == self.stuckPosition[1] and newPos[2] == self.stuckPosition[2] then
    self.stuckCount = self.stuckCount + 1
  else
    self.stuckCount = 0
    self.stuckPosition = newPos
  end

  return self.stuckCount
end

--------------------------------------------------------------------------------
function calculateSeparationMovement()
  local entityIds = world.entityQuery(mcontroller.position(), 0.5, { includedTypes = {"monster"}, withoutEntityId = entity.id(), order = "nearest" })
  if #entityIds > 0 then
    local separationMovement = world.distance(mcontroller.position(), world.entityPosition(entityIds[1]))
    return util.toDirection(separationMovement[1])
  end

  return 0
end

--------------------------------------------------------------------------------
function travelTime(distance) -- lpk: modded to accept a pos also
  if type(distance) == "table" then return travelTimeToPos(distance) end
  local runSpeed = mcontroller.baseParameters().walkSpeed
  return math.abs(distance / runSpeed)
end

function travelTimeToPos(pos)
  local toTarget = world.distance(pos, mcontroller.position())
  local distance = world.magnitude(toTarget)
  local runSpeed = mcontroller.baseParameters().walkSpeed
  return math.abs(distance / runSpeed)
end
--------------------------------------------------------------------------------
-- estimate the maximum jump duration
function jumpTime()
  return (2 * mcontroller.baseParameters().airJumpProfile.jumpSpeed) / (world.gravity(mcontroller.position()) * 1.5)
end

--------------------------------------------------------------------------------
-- estimate the maximum jump height
function jumpHeight()
  return (mcontroller.baseParameters().airJumpProfile.jumpSpeed * jumpTime()) / 4
end

--------------------------------------------------------------------------------
function faceTarget()
  if self.onGround then
    mcontroller.controlFace(self.toTarget[1])
  end
end

--------------------------------------------------------------------------------
function controlFace(direction)
  if self.onGround then
    mcontroller.controlFace(direction)
  end
end

--------------------------------------------------------------------------------
function isBlocked(direction)
  local direction = direction or mcontroller.facingDirection()
  local position = mcontroller.position()
  position[1] = position[1] + direction

  if not world.resolvePolyCollision(mcontroller.collisionPoly(), position, 0.8) then
    return true
  end
  return false
end

--------------------------------------------------------------------------------
function willFall(direction)
  local direction = direction or mcontroller.facingDirection()
  local position = mcontroller.position()
  position[1] = position[1] + direction
  --Snap the position forward
  position[1] = direction > 0 and math.ceil(position[1]) or math.floor(position[1])

  local bounds = mcontroller.boundBox()

  local groundRegion = {
    math.floor(position[1] + bounds[1]), math.ceil(position[2] + bounds[2] - 1),
    math.ceil(position[1] + bounds[3]), math.ceil(position[2] + bounds[2])
  }
  if world.rectTileCollision(groundRegion, "Any") then
    return false
  end
  return true
end
