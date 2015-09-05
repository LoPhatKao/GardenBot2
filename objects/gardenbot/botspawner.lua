function init(virtual)
  if not virtual then
    entity.setInteractive(true)
--    world.logInfo("\n-world-\n %s\n-entity-\n %s\n-mcontroller-\n %s",world,entity,mcontroller)
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
    parameters.level = 1
    parameters.spawnPoint = {p[1], p[2] + 1}
    world.spawnMonster(type, {p[1], p[2] + 1}, parameters)
    entity.smash()
  end
end