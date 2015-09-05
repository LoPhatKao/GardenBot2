function init(virtual)
  if not virtual then
    entity.setInteractive(true)
  end
end

function onInteraction(args)
  if args ~= nil and args.sourceId ~= nil then
    local p = entity.position()
    local parameters = {}
    local type = "gardenbotv80g"
    if entity.configParameter("botspawner.type") ~= nil then
      type = entity.configParameter("botspawner.type")
    end
    parameters.persistent = true
	parameters.damageTeam = 1
    parameters.ownerUuid = args.sourceId
    parameters.level = getLevel()
    parameters.spawnPoint = {p[1], p[2] + 1}
    world.spawnMonster(type, {p[1], p[2] + 1}, parameters)
    entity.smash()
  end
end

function getLevel()
  if world.getProperty("ship.fuel") ~= nil then return 10 end
  if world.threatLevel then return world.threatLevel() end  -- pleased giraffe
  return 1
end