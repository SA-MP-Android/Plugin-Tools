local STAND_PRIORITY = 50

local state = {
    lease = nil
}

local function release()
    if state.lease ~= nil then
        state.lease:release()
        state.lease = nil
    end
end

local function apply()
    release()
    local p = samp.player.local_player()
    if p == nil or not p:is_valid() then
        samp.log.warn("Always Stand: player unavailable")
        return
    end
    local ok, lease = pcall(function()
        return samp.effects.acquire("player.physics_flags", {
            priority = STAND_PRIORITY,
            onSolidSurface = true,
            isStanding = true,
            wasStanding = true
        })
    end)
    if ok then
        state.lease = lease
        samp.log.info("Always Stand enabled")
    else
        samp.log.error("Always Stand start failed: " .. tostring(lease))
    end
end

samp.events.on("player.spawned", apply)
samp.events.on("player.died", release)
samp.events.on("session.ended", release)
samp.events.on("server.disconnected", release)
