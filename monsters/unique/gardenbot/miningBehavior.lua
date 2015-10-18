-- shaftState and branchState - LoPhatKao Sept 2015
-- have both in one file as are heavily interconnected
-- yes, shaft is a potential pen!s reference, get over it ;p

-- main shaft on nearest X % 100 to spawn ( floor of spawnX+50/100 x 100)
-- dig -2 .. 2 from shaftX (4wide), dig down to world.underground from spawnY before branching
-- leave plats every 5 blocks ( branch floors)
-- max depth 200 above core or 100 branches
-- branches are 50 long ( ends are -50 and +49 from shaftX , allows multi mine overlap)
-- bridge across gaps
--------------------------------------------------------------------------------
--local dy = entity.configParameter("gardenSettings.fovHeight") / 2
    
shaftState = {}
branchState = {}
mineParams = {
  sLightName = "futurelight", -- light in shaft
  platName = "platform", -- platform bot will place
  wallName = "hazard", -- block ditto
  minDepth = 200, -- minimum above core bot mines to
  width = 100, -- width of mine (midshaft is half this)
  debugshaft = false
}
--------------------------------------------------------------------------------
function isOnPlatform()
local pos = mcontroller.position()
pos[2] = pos[2] + mcontroller.boundBox()[2] - 0.5
local onplats = world.collisionBlocksAlongLine({pos[1]-2,pos[2]},{pos[1]+1,pos[2]}, {"Null","Platform"})
return #onplats > 0
end    
--------------------------------------------------------------------------------
function ptInRect(pt,rect)
  return (pt[1]>=rect[1] and pt[1]<=rect[3] and pt[2]>=rect[2] and pt[2]<=rect[4])
end
--------------------------------------------------------------------------------
function moveTo(targpos,vertical) -- move to a pos, digging if needed - return true if dug
--  blocksInLos = world.collisionBlocksAlongLine(mcontroller.position(), targPos, {"Null","Block","Dynamic"})
  if vertical == nil then vertical = false end
  local pos = mcontroller.position()
  local toTarget = world.distance(targpos, pos)
  local facedir = util.toDirection(toTarget[1])
  local footPosition = {
    pos[1], math.floor(pos[2] + mcontroller.boundBox()[2] + 0.5)
  }
  local retVal = false
  local blocks = {}
  mcontroller.controlFace(facedir)
  
  if vertical then
  local vdir = util.toDirection(toTarget[2])
    local onplats = isOnPlatform()
    local yoff = 1 
    local vyoff = mcontroller.boundBox()[4]-mcontroller.boundBox()[2] -- height
    local p1,p2 = {self.shaftX-2,footPosition[2]-yoff},{self.shaftX+1,footPosition[2]-yoff}
    if vdir > 0 then -- going up
      p1[2] = math.ceil(p1[2]+vyoff+1) p2[2] = math.ceil(p2[2]+vyoff+0.5) 
    end
    util.debugRect({p1[1],p1[2],p2[1]+1,p2[2]+1},"blue")
    if facedir > 0 then -- rtl instead
      p1,p2 = p2,p1
    end
    blocks = world.collisionBlocksAlongLine(p1, p2, {"Null","Block","Dynamic"},1)
    if onplats then
      p1[2] = p1[2]-1
      p2[2] = p2[2]-1
    util.debugRect({p1[1],p1[2],p2[1]+1,p2[2]+1},"blue")
    blocks2 = world.collisionBlocksAlongLine(p1, p2, {"Null","Block","Dynamic"},1)
      if #blocks2 > 0 then -- insert into blocks for damaging
        for i = 1,#blocks2,1 do
          table.insert(blocks,blocks2[i])
        end
      end
      
    end
  else -- horizontal digging
  -- adjust foot[2] for up/down digging
    local dy = entity.configParameter("gardenSettings.fovHeight") - 1
    local yoff = 0
    local tb = branchState.posToBranch(targpos)
    if not branchState.isAtBranchY(tb) and (self.inState ~= "branchState" or branchState.posToBranch(footPosition)<0) then 
      local tbY = branchState.branchToPos(tb)[2]
      if tbY > footPosition[2]-1 then -- dig up
      yoff = 1 
      else 
      yoff = -1 
      end
      dy = dy + 1 -- hacky :(
    end
    for chkX = 0,2,1 do 
      local p1 ={footPosition[1]+((chkX+0.5)*facedir),footPosition[2]+yoff+(dy)} --  top
      local p2 ={footPosition[1]+((chkX+0.5)*facedir),footPosition[2]+yoff} -- bott
      util.debugLine({p1[1],p1[2]},{p2[1],p2[2]},"green")
      local blocks2 = world.collisionBlocksAlongLine(p1,p2, {"Null","Block","Dynamic"},1)
      if #blocks2 > 0 and #blocks < 1 then -- insert into blocks for damaging
        for i = 1,#blocks2,1 do
          table.insert(blocks,blocks2[i])
        end
      end
    end
  end  
  
  if #blocks > 0 then -- break blocks in way, drop ores
    for bl = 1,#blocks,1 do
      retVal = damageBlock(blocks[bl])
    end    
  end
  if retVal then 
    setAnimationState("movement","repair")
  else
    move(toTarget) 
  end
  return retVal
end
--------------------------------------------------------------------------------
function damageBlock(block,dmg,hrv)
if dmg == nil then dmg = 1 end
if hrv == nil then hrv = 0 end
  local dmgtiles = false
  local matname = world.material(block,"foreground")
  if matname == mineParams.platName 
    or (matname == mineParams.wallName and not shaftState.isNearShaft())
    then return false end
  if matname == "sand" then hrv = 1 end
  local modName = world.mod(block,"foreground")
  if modName then --and isOre(modName) then
    dmgtiles = world.damageTiles({block},"foreground",block,"blockish",(0.75*dmg)) 
  else
    dmgtiles = world.damageTiles({block},"foreground",block,"blockish",dmg,hrv)
  end
  if not dmgtiles then -- maybe vine under ?
    dmgtiles = world.damageTiles({vec2.add(block,{0,-1})},"foreground",block,"plantish",2*dmg)
  end
  if not dmgtiles then -- maybe tree over ?! 
    dmgtiles = world.damageTiles({vec2.add(block,{0,1})},"foreground",block,"plantish",2*dmg)
  end
  if dmgtiles then
--[[  -- visually affect block - works but meh
  local pos = vec2.add(mcontroller.position(),{0.5*mcontroller.facingDirection(),0})
  local tpos = vec2.add(block,{0.5,0.5})
  local dis = world.distance(tpos,pos)
  world.spawnProjectile("lightning", pos, entity.id(), dis, false, {power = 0})
--]]
    if entity.hasSound("mine") and self.mineSoundTimer < 0 then 
      entity.playSound("mine")
      self.mineSoundTimer = 0.3 -- no earraping sounds plx
    end
  end
  util.debugRect({block[1],block[2],block[1]+1,block[2]+1},"red")
  return dmgtiles
end
--------------------------------------------------------------------------------
function placeLantern(position,oname)
if oname == nil then oname = "futurelight" end-- "oillantern1" end
  local sample = world.lightLevel(position)
  local level = math.floor(sample * 1000) * 0.1
  
  if level >= 20 then return end -- half of what turns on light sensor
  
  world.placeObject(oname,position,1,{})

end
--------------------------------------------------------------------------------

function shaftState.enter()
  if not isPleasedGiraffe() or world.getProperty("ship.fuel") ~= nil then return nil,999 end
  local position = mcontroller.position()
  local target = shaftState.findPosition(position)
  if target ~= nil then
    return {
      targetPosition = target.position,
      timer = math.max(5,travelTime(target.position))
    }
  end
  return nil,1--entity.configParameter("gardenSettings.cooldown", 15)
end
--------------------------------------------------------------------------------
function shaftState.findPosition(position)
  local footPosition = {
    math.floor(position[1] + 0.5),
    math.floor(position[2] + 0.5+math.ceil(mcontroller.boundBox()[2])) - 1
  }
  if self.shaftX == nil then self.shaftX = shaftState.findShaftX() end
  self.shaftHead = shaftState.findHead()
  local ret = self.shaftHead
  if world.underground(footPosition) or shaftState.isNearShaft() then -- return shaft at current branch depth
    local branch = branchState.posToBranch(footPosition)
    ret = branchState.branchToPos(math.max(0,branch))
  end
--  world.logInfo("shaft ret: %s fp: %s",ret,footPosition)
  return {position = ret}
end
--------------------------------------------------------------------------------
function shaftState.leavingState(stateName)
  script.setUpdateDelta(10)
end
--------------------------------------------------------------------------------

function shaftState.update(dt, stateData)
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil then
    return true
  end
  
  if self.mineSoundTimer >= 0 then self.mineSoundTimer = self.mineSoundTimer - dt end
  
  local dy = entity.configParameter("gardenSettings.fovHeight") / 2
  local position = mcontroller.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
util.debugLine(mcontroller.position(),vec2.add(mcontroller.position(),toTarget),"white")
  local curbranch = branchState.posToBranch(vec2.add({0,mcontroller.boundBox()[2]},position))
  local targbranch = branchState.posToBranch(stateData.targetPosition)
  local curfloor = branchState.branchToPos(curbranch)

 --entity.configParameter("gardenSettings.interactRange") then
  if shaftState.isNearShaft() then
    script.setUpdateDelta(2)
    if vec2.eq(self.shaftHead, stateData.targetPosition) then
--     if distance <= 3 then 
--    world.logInfo("at shaft head: %s",stateData.targetPosition)
      local headbranch = branchState.posToBranch(self.shaftHead)
      local headRect = {self.shaftX-2,self.shaftHead[2]+1,self.shaftX+1,self.shaftHead[2]+5}
      util.debugRect(headRect,"yellow")
      if headbranch == curbranch and world.rectTileCollision(headRect, {"Null", "Block", "Dynamic"}) then
      -- damage tiles in way
        for dty = 1,5,1 do
        local p1,p2 = {self.shaftX-2,self.shaftHead[2]+dty},{self.shaftX+1,self.shaftHead[2]+dty}
          local blocks = world.collisionBlocksAlongLine(p1,p2, {"Null","Block","Dynamic"},1)
          util.debugLine(p1,p2,"green")
          if #blocks > 0 then -- break blocks in way, drop ores
            for bl = 1,#blocks,1 do
              local dmg = math.min(1,2*(1/dty))
              if damageBlock(blocks[bl],dmg) then 
                stateData.timer = stateData.timer + dt
              end
            end    
--            return false
          end
          shaftState.placePlatforms(true)
        end
      else 
        if ptInRect(position,headRect) then -- start digging down
          shaftState.placePlatforms(true)
          shaftState.placeHeadItems()
          stateData.targetPosition = branchState.branchToPos(headbranch-1)
          stateData.timer = 5
        else 
          if moveTo(stateData.targetPosition,true) then
            stateData.timer = stateData.timer + dt 
          end
        end
      end
    else -- not at head
      if branchState.isAtBranchY(curbranch) then 
        local oids = world.itemDropQuery({curfloor[1]-2,curfloor[2]},{curfloor[1]+1,curfloor[2]+2})
        if #oids > 0 then return true,1 end  -- pickup loot
      end
      shaftState.placePlatforms(not mcontroller.onGround())
      shaftState.placeLights()
      if world.underground(position) then -- find a branch
--    world.logInfo("the underground, woo!: %s [%s]",position,branchState.posToBranch(position))
        if not branchState.isAtBranchY(curbranch) then
          shaftState.placePlatforms(true)
          if moveTo(curfloor,true) then 
            stateData.timer = stateData.timer + dt 
          end
        else -- at branchY maybe enter branchState
          local fd = mcontroller.facingDirection()
          if mineParams.debugshaft or not self.state.pickState({branch=curbranch,dir=fd}) then -- branches are clear
            if targbranch >= curbranch then
              if curbranch > 0 then 
                stateData.targetPosition = branchState.branchToPos(math.max(curbranch -1,0))
                stateData.timer = 5 
              else
                stateData.targetPosition = self.shaftHead -- force up shaft
                stateData.timer = 5 + math.random(5)
              end
            end
            if curbranch % 4 == 0 then -- check every 4 branch for out of range
              if self.homeBin == nil or not world.entityExists(self.homeBin) then
                shaftState.placeHeadItems(curbranch)
              end
            end
            moveTo(stateData.targetPosition,true)
--          else
--          world.logInfo("Branch %s:%s: not clear -- goto branchState",curbranch,fd)
--          self.state.pickState({ignoreDistance=true}) -- temp return
           -- 
          end
        end
      else -- not 'underground' yet, dig down more
        if branchState.isAtBranchY(curbranch) then 
          if targbranch >= curbranch then
            stateData.targetPosition = branchState.branchToPos(math.max(curbranch - 1,0))
            stateData.timer = 5
          end
        end
        shaftState.placeWalls()
        if moveTo(stateData.targetPosition,true) then
          stateData.timer = stateData.timer + dt -- readd time used for digging
        end
      end
    end
  else -- not near shaft, horizontally move to it
    if moveTo({stateData.targetPosition[1], stateData.targetPosition[2] + dy}) then
      stateData.timer = stateData.timer + dt
    else -- didn't dig, can check drops
      branchState.placeBridges()
      if math.floor(position[1]) % 5 == 0 then 
        return true
      end

    end
  end
 
  return stateData.timer < 0,entity.configParameter("gardenSettings.cooldown", 10)
end
--------------------------------------------------------------------------------

function shaftState.findHead(shaftY)
  if shaftY == nil then shaftY = self.spawnPoint[2] end
  local tmp = {self.shaftX,shaftY}
  local downchk = vec2.add(tmp,{0,-50})
  
  local blocks = world.collisionBlocksAlongLine(tmp, downchk, {"Null","Block","Platform"})
  
  if #blocks == 0 then 
    return shaftState.findHead(downchk[2]) -- in a valley?
  else
    local br = branchState.posToBranch({self.shaftX,blocks[1][2]})
    return branchState.branchToPos(br)
  end
  
end
--------------------------------------------------------------------------------
function shaftState.placeLights()
  -- place torch, alternating between {shaftX - (branch % 2), branchY + 2}
  local pos = mcontroller.position()
  local upbranch = branchState.posToBranch(pos)+1
  local position = branchState.branchToPos(upbranch)
  if position[2] > self.shaftHead[2]+1 then return end
--  position = vec2.add({ 0 - (upbranch % 2), 1 },position)
  position = vec2.add({ -1, 1 },position)

  placeLantern(position,mineParams.sLightName)
  --world.placeObject("torch",position,1,{})
end
--------------------------------------------------------------------------------
function shaftState.placeWalls() -- changed rc14 to do bg also
local pos = mcontroller.position()
if pos[2] >= self.shaftHead[2] then return end
if world.underground(pos) then return end
local lw,rw = -3,2
  placeBlock({self.shaftX+lw,pos[2]})
  placeBlock({self.shaftX+rw,pos[2]})
  for bgX = -2,1,1 do
    placeBlock({self.shaftX+bgX,pos[2]},"background")
  end
end
--------------------------------------------------------------------------------
function shaftState.placeHeadItems(br)
if br == nil then br = branchState.posToBranch(self.shaftHead) end
local itemY = branchState.branchToPos(br)[2] + 1
local chestname = "miniskip" -- custom chest
local fd = mcontroller.facingDirection()

  world.placeObject(chestname,{self.shaftX,itemY},fd,{})
  world.placeObject(mineParams.sLightName,{self.shaftX-2,itemY},1,{})
  world.placeObject(mineParams.sLightName,{self.shaftX+1,itemY},1,{})

  if self.homeBin == nil or not world.entityExists(self.homeBin) then -- set skip to homebin
    oids = world.objectQuery({self.shaftX,itemY}, 1, { callScript = "entity.configParameter", callScriptArgs = {"category"}, callScriptResult = "storage",order = "nearest" })
    if #oids > 0 then self.homeBin = oids[1] end
  end
end
--------------------------------------------------------------------------------
function shaftState.placePlatforms(under)
if under == nil then under = false end
local pos = mcontroller.position()
pos[2] = pos[2]+mcontroller.boundBox()[2]
local upb = branchState.posToBranch(pos)
if not under then 
  upb = upb + 1 
else  
  if not mcontroller.onGround() and mcontroller.falling() then 
  local blocks = world.lineTileCollision(pos,branchState.branchToPos(upb-1),{"Null","Block","Dynamic"})
  if not blocks then upb = upb - 1 end
  end
end
local ub = branchState.branchToPos(upb)
  if ub[2] > self.shaftHead[2] then return end
local plats = world.collisionBlocksAlongLine({ub[1]-2,ub[2]},{ub[1]+1,ub[2]}, {"Null","Platform"})
if #plats == 4 then return end -- already plats there
for platX = -2,1,1 do
local platpos = vec2.add({platX,0},ub)
  
  if shaftState.canPlacePlat(platpos) then
    shaftState.placePlat(platpos)
  else
    shaftState.nukeTile(platpos)
  end
end
end
--------------------------------------------------------------------------------
function shaftState.nukeTile(pos)
  if world.material(pos,"foreground") == mineParams.platName then return end
  return damageBlock(pos,99,0)
end
--------------------------------------------------------------------------------
function shaftState.placePlat(pos)
--    world.logInfo("place platform : %s",pos)
  if world.material(pos,"foreground") == mineParams.platName then return end
  world.placeMaterial(pos,"foreground",mineParams.platName)
end
--------------------------------------------------------------------------------
function shaftState.canPlacePlat(pos)
local matname = world.material(pos,"foreground")
  if (matname and matname ~= mineParams.platName) or world.tileIsOccupied(pos) then return false end
  return true
--  return not(world.tileIsOccupied(pos) or world.material(pos,"foreground") ~= "platform")
end
--------------------------------------------------------------------------------
function shaftState.isNearShaft(pos)
  if pos == nil then pos = mcontroller.position() end
  return math.abs(self.shaftX - pos[1]) <= 0.5
end
--------------------------------------------------------------------------------

function shaftState.findShaftX()
  local posX = self.spawnPoint[1]
--  posX = 100 * (math.floor(posX/100)+0.5)  -- 50, 150, 250 etc
  posX = mineParams.width * (math.floor(posX/mineParams.width)+0.5)  -- 50, 150, 250 etc
  return posX
end
--------------------------------------------------------------------------------
-- branchState
-- will only dig branches underground (26ish% of planet width)
--------------------------------------------------------------------------------

function branchState.enterWith(args)
if type(args) ~= "table" or args.branch == nil then return nil end
local pos = mcontroller.position()
if not world.underground(pos) then return nil end
--world.logInfo("trying to enter branchState, woo")
  local target = branchState.findBranch(pos, args.dir)
  if target ~= nil then
    return {
      targetPosition = target.position,
      timer = math.max(5,travelTime(target.position))
    }
  end
  return nil
end
--------------------------------------------------------------------------------

function branchState.findBranch(position, dir)
  local br = branchState.posToBranch(position)
  if br < 0 then return nil end -- stop digging
  local fd = dir or mcontroller.facingDirection()
  local facingClear = branchState.isBranchClear(br,fd)
  if facingClear and branchState.isBranchClear(br,-fd) then return nil end
  if facingClear then fd = -fd end
  return {
    position = {self.shaftX+(mineParams.width/2*fd),math.floor(position[2]+0.5)}
  }
end
--------------------------------------------------------------------------------

function branchState.update(dt, stateData)
-- horizontal shafting - dig to X % 5, then maybe break out to gather etc
  if mcontroller.liquidMovement() then dt = dt/2 end
  stateData.timer = stateData.timer - dt
  if stateData.targetPosition == nil then return true end
  if self.mineSoundTimer >= 0 then self.mineSoundTimer = self.mineSoundTimer - dt end
  
  local dy = entity.configParameter("gardenSettings.fovHeight") / 2
  local position = mcontroller.position()
  local toTarget = world.distance(stateData.targetPosition, position)
  local distance = world.magnitude(toTarget)
util.debugLine(mcontroller.position(),vec2.add(mcontroller.position(),toTarget),"yellow")
  local curbranch = branchState.posToBranch(position)
  local targbranch = branchState.posToBranch(stateData.targetPosition)
  local curfloor = branchState.branchToPos(curbranch)

  if curbranch ~= targbranch and curbranch > 0 then
    stateData.targetPosition = {stateData.targetPosition[1],math.floor(position[2]+0.5)}
  end
  
  if distance < 1 then -- at end of branch
    return true
  else -- dig the branch
    if moveTo(stateData.targetPosition) then
      stateData.timer = stateData.timer + dt
    else   --world.logInfo("didn't dig, maybe check drops")
      if math.floor(position[1]) % 5 == 0 then 
        local oids = world.itemDropQuery({position[1]-3,curfloor[2]},{position[1]+2,curfloor[2]+2})
        if #oids > 0 then return true,1 end

      end
    end
  end
  if curbranch == targbranch or curbranch < 0 then
  branchState.placeBridges()
  branchState.placeLights()
  end
  return stateData.timer < 0
end
--------------------------------------------------------------------------------
function branchState.isBranchClear(branch, dir)
 local bottY = branchState.branchToPos(branch)
 local blen = mineParams.width/2
 local lef = self.shaftX
 local bot = bottY[2]+1
 local rig = self.shaftX+blen
 local top = bottY[2]+4.5
 if dir == -1 then lef = lef - blen rig = rig - blen end
 local chkRect = {lef,bot,rig,top}
 world.loadRegion(chkRect)
 util.debugRect(chkRect,"yellow")
 return not world.rectTileCollision(chkRect,{"Null","Block","Dynamic"})
end
--------------------------------------------------------------------------------

function branchState.isAtBranchY(branch)
  local position = mcontroller.position()
  position[2] = math.floor(position[2]+0.5+mcontroller.boundBox()[2])-1
  if branch == nil then branch = branchState.posToBranch(position) end
--world.logInfo(position[2])
  local br = ((position[2] - mineParams.minDepth)/5)
  return (br - branch) == 0
end
--------------------------------------------------------------------------------

function branchState.posToBranch(pos)
  return math.floor((pos[2] - mineParams.minDepth)/5)
end
--------------------------------------------------------------------------------

function branchState.branchToPos(br)
  return {self.shaftX,(5 * br)+mineParams.minDepth}
end
--------------------------------------------------------------------------------
function branchState.placeLights()
local pos = mcontroller.position()
if not world.underground(pos) then return false end -- shouldnt happen but meh
local itemY = branchState.branchToPos(branchState.posToBranch(pos))[2] +1
local itemX = math.floor((pos[1]/20)+0.5)*20
if math.abs(pos[1] - itemX)<1 then placeLantern({itemX,itemY}) end
end
--------------------------------------------------------------------------------
function branchState.placeBridges(br)
local pos = mcontroller.position()
if not world.underground(pos) then return false end -- shouldnt happen but meh
if shaftState.isNearShaft() then return false end
if br == nil then br = branchState.posToBranch(pos) end
local brY = branchState.branchToPos(br)[2]
local p1,p2 = {pos[1]-3,brY},{pos[1]+2,brY}
local blocks = world.collisionBlocksAlongLine(p1,p2, {"Null","Block","Platform"})

  if #blocks == 6 then return false end
  local fd = mcontroller.facingDirection()
  if fd < 0 then p1[1],p2[1] = p2[1],p1[1] end -- rtl
  for brX = p1[1],p2[1],fd do
    placeBlock({brX,brY})
  end
end
--------------------------------------------------------------------------------

function placeBlock(pos,layer) -- pos should be a spot with no foreground material
if layer == nil then layer = "foreground" end
local spotmat = world.material(pos,layer)
if spotmat == mineParams.platName or spotmat == mineParams.wallName then return end
  if layer == "foreground" and not spotmat and world.tileIsOccupied(pos) then  -- maybe a vine? moneypod? iunno
    damageBlock(pos,99) -- fg only
  end
-- find and place a material
   world.placeMaterial(pos,layer,mineParams.wallName)
end
