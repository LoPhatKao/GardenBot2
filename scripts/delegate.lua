--------------------------------------------------------------------------------
delegate = {
    v = 4,
    delegates = {},
    callbacks = {}
}
--------------------------------------------------------------------------------
-- overload hooks
--------------------------------------------------------------------------------
delegate.init = init
function init(args)
    local result = delegate.triggerAll("preInit", args)
    if not result then result = delegate.triggerAll("init", args) end
    if not result and delegate.init ~= nil then result = delegate.init(args) end
    if not result then delegate.triggerAll("postInit", args) end
end
--------------------------------------------------------------------------------
delegate.main = main
function main()
    local result = delegate.triggerAll("preMain")
    if not result then result = delegate.triggerAll("main") end
    if not result and delegate.main ~= nil then result = delegate.main() end
    if delegate.tick ~= nil then delegate.tick() end
    if not result then result = delegate.triggerAll("postMain") end
end
--------------------------------------------------------------------------------
delegate.die = die
function die()
    local result = delegate.triggerAll("preDie")
    if not result then result = delegate.triggerAll("die") end
    if not result and delegate.die ~= nil then result = delegate.die() end
    if not result then result = delegate.triggerAll("postDie") end
end
--------------------------------------------------------------------------------
delegate.damage = damage
function damage(args)
    local result = delegate.triggerAll("preDamage", args)
    if not result then result = delegate.triggerAll("damage", args) end
    if not result and delegate.damage ~= nil then result = delegate.damage(args) end
    if not result then result = delegate.triggerAll("postDamage", args) end
end
--------------------------------------------------------------------------------
delegate.interact = interact
function interact(args)
    local result = delegate.triggerAll("preInteract", args)
    if not result then result = delegate.triggerAll("interact", args) end
    if not result and delegate.interact ~= nil then result = delegate.interact(args) end
    if not result then result = delegate.triggerAll("postInteract", args) end
    return result
end
--------------------------------------------------------------------------------
-- delegate functions
--------------------------------------------------------------------------------
function delegate.create(targetName)
   table.insert(delegate.delegates, targetName)
end
--------------------------------------------------------------------------------
function delegate.remove(targetName)
    for i,d in ipairs(delegate.delegates) do
        if d == targetName then
            table.remove(delegate.delegates, i)
            return
        end
    end
end
--------------------------------------------------------------------------------
function delegate.triggerAll(functionName, args)
    for _,d in pairs(delegate.delegates) do
        local result = delegate.callback(d, functionName, args)
        if result ~= nil then return result end
    end
end
--------------------------------------------------------------------------------
function delegate.callback(targetName, functionName, args)
    if _ENV[targetName] ~= nil and _ENV[targetName][functionName] ~= nil then
        return _ENV[targetName][functionName](args)
    end
end
--------------------------------------------------------------------------------
function delegate.delayCallback(targetName, functionName, args, delay)
    if type(delay) ~= "number" then delay = 0 end
    table.insert(delegate.callbacks, {t = targetName, f = functionName, a = args, d = delay})
    if delegate.tick == nil then
        delegate.tick = delegate.delayTick
    end
end
--------------------------------------------------------------------------------
function delegate.delayTick()
    if delegate.ticking then return end
    delegate.ticking = true
    local i = 1
    while i <= #delegate.callbacks do
        if delegate.callbacks[i].d < 0 then
            delegate.callback(delegate.callbacks[i].t, delegate.callbacks[i].f, delegate.callbacks[i].a)
            table.remove(delegate.callbacks, i)
        else
            delegate.callbacks[i].d = delegate.callbacks[i].d - entity.dt()
            i = i + 1
        end
    end
    if next(delegate.callbacks) == nil then delegate.tick = nil end
    delegate.ticking = false
end
--------------------------------------------------------------------------------