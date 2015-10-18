-- LoPhatKao - July 2015
-- harvestpools.lua - compatibility addon for Gardenbot 2
-- a workaround til world.spawnTreasure() is implemented
-- uses same calling conventions
harvestPools = {}

function harvestPools.spawnTreasure (pos, poolname, level, seed) -- i'm ignoring level and seed
  if type(pos) ~= "table" then return false end -- no spawn pos
  if type(poolname) ~= "string" then return false end -- invalid name parameter

  local tp = harvestPools.getPool(poolname)
  if tp == nil then  -- not listed
--    world.logInfo("Pool not found: %s",poolname)
    return false
  else -- is listed in known pools, generate dat bling
    local didSpawn = false
    if tp.fill ~= nil then -- spawn 'always drop' items
      for i = 1,#tp.fill do
        harvestPools.doSpawnItem(pos,tp.fill[i].item)
        didSpawn = true
      end
    end
    if tp.pool ~= nil then -- spawn 'maybe drop' items
      local maxrnd = harvestPools.numRounds(tp.poolRounds)
      for i = 1, maxrnd do
        local ritem = tp.pool[math.random(1,#tp.pool)]
        if math.random() <= harvestPools.poolWeight(ritem) or (i==maxrnd and not didSpawn) then
          harvestPools.doSpawnItem(pos,ritem.item)
          didSpawn = true
        end
      end
    end
    return didSpawn
  end
  return false
end

---------------------------------------------------------------------------------------
--------------  helper funcs
---------------------------------------------------------------------------------------

function harvestPools.numRounds(poolRounds)--randomize # rounds of pool spawning, returning 0 is ok
  if type(poolRounds) == "table" then -- usually a table of tables
    for i = #poolRounds,1,-1 do
      if math.random() <= poolRounds[i][1] or i == 1 then return poolRounds[i][2] end
    end
  end
  return 0
end

function harvestPools.poolWeight(pool)
if pool.weight ~= nil then return pool.weight end
return 1
end 

function harvestPools.itemName(item)
  if type(item) == "string" then return item end
  if type(item) == "table" then return item[1] end
  return "perfectlygenericitem" -- shouldnt ever get here.. 
end

function harvestPools.itemCount(item)
if type(item) == "table" and item[2] ~= nil then return item[2] end
return 1
end

function harvestPools.itemParams(item) -- for stuff with params, generated weps etc.
if type(item) == "table" and item[3] ~= nil then return item[3] end
return {}
end


function harvestPools.doSpawnItem(pos,item)
--world.logInfo("Spawning: %s",item)
pos[2] = math.floor(pos[2])+0.5
iName = harvestPools.itemName(item)
iCnt = harvestPools.itemCount(item)
iParam = harvestPools.itemParams(item)
  if not world.spawnItem(iName,pos,iCnt,iParam) then 
    world.logInfo("Failed to spawn item: %s",item)
  end
end

function harvestPools.getPool(poolname)
---------------------------------------------------------------------------------------
--  pool data - here comes the hugeness -.- lol - somewhere near 250kb
--  poolcounts: vanilla = 39(7 used), MFM = 27, FU = 174, OPP = 737 
-- should add popular race crops - avali etc
-- gb2rc2.1 - move to local of spawnTreasure
-- gb2rc3.1 move to its own func in general cleanup of harvestpool lua
--gb2rc4 - removed all data, long unneeded - left legacy code for reference - also lazy to edit all the monstypes
---------------------------------------------------------------------------------------
local pools = {
-- kao's test seed
moneyHarvest = {fill={{item="moneyseed"}},pool={{weight=0.05,item={"moneyseed",1}},{weight=0.1,item={"voxel10k",1}},{weight=0.2,item={"voxel5k",1}},{weight=0.3,item={"voxel2k",1}},{weight=0.4,item={"voxel1k",1}},{item={"money",100}}},poolRounds={{0.7,1},{0.3,0}}},

} -- end of pool list
return pools[poolname]

end