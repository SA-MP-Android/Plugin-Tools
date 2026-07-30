local FOOT_OFFSET = 1.0
local INITIAL_LIFT = 0.0
local EPSILON = 0.05
local UPWARD_SPEED = 0.02
local RELOCATION_DISTANCE = 0.5
local FOLLOW_DISTANCE = 4.0

local state = {
    -- Enable state is intentionally session-only.
    enabled = false,
    climb_by_jump = samp.storage.get("climb_by_jump", true),
    raise_step = samp.storage.get("raise_step", 1.0),
    anchor_z = nil, center_x = nil, center_y = nil, surface_z = nil,
    last_position = nil, surface = nil
}

local function player()
    local p = samp.player.local_player()
    if p == nil or not p:is_valid() then return nil end
    return p
end

local function clear()
    if state.surface ~= nil then state.surface:release() end
    state.surface = nil
    state.anchor_z, state.center_x, state.center_y, state.surface_z = nil, nil, nil, nil
    state.last_position = nil
end

local function create(p, lift)
    local pos = p:position()
    if lift > 0.0 then
        pos.z = pos.z + lift
        p:set_position(pos)
        p:set_velocity({ x = 0.0, y = 0.0, z = 0.0 })
    end
    state.anchor_z, state.center_x, state.center_y = pos.z, pos.x, pos.y
    state.surface_z = pos.z - FOOT_OFFSET
    state.last_position = { x = pos.x, y = pos.y, z = pos.z }
    state.surface = samp.physics.create_surface({
        position = { x = pos.x, y = pos.y, z = state.surface_z }
    })
end

local function enable()
    local p = player()
    if p == nil then samp.log.warn("Air Walk: player unavailable"); return end
    clear()
    local ok, err = pcall(create, p, INITIAL_LIFT)
    if not ok then clear(); samp.log.error("Air Walk start failed: " .. tostring(err)) end
end

local function update()
    if not state.enabled then return end
    local p = player()
    if p == nil then return end
    if p:vehicle() ~= nil then clear(); return end
    if state.surface == nil or not state.surface:is_valid() then create(p, 0.0); return end

    local pos, vel, old = p:position(), p:velocity(), state.last_position
    local relocated = false
    if old ~= nil then
        local dx, dy, dz = pos.x - old.x, pos.y - old.y, pos.z - old.z
        relocated = dx * dx + dy * dy + dz * dz > RELOCATION_DISTANCE * RELOCATION_DISTANCE
    end
    state.last_position = { x = pos.x, y = pos.y, z = pos.z }

    -- Only accept upward movement. A lower server-set position never lowers anchor_z.
    local jumped = state.climb_by_jump and vel.z > UPWARD_SPEED and pos.z > state.anchor_z + EPSILON
    -- A position update with little/no upward velocity is treated as a server
    -- relocation. It is accepted at any distance, but only when it is higher.
    local server_raised = pos.z > state.anchor_z + EPSILON and
        (relocated or vel.z <= UPWARD_SPEED)
    if jumped or server_raised then state.anchor_z = pos.z end

    local dx, dy = pos.x - state.center_x, pos.y - state.center_y
    local moved = dx * dx + dy * dy > FOLLOW_DISTANCE * FOLLOW_DISTANCE
    local desired_z = state.anchor_z - FOOT_OFFSET
    local raised = math.abs(desired_z - state.surface_z) > EPSILON
    if moved then state.center_x, state.center_y = pos.x, pos.y end
    if moved or raised then
        state.surface_z = desired_z
        state.surface:set_position({ x = state.center_x, y = state.center_y, z = state.surface_z })
    end
end

samp.ui.menu.register({
    id = "settings", title = "Air Walk",
    controls = {
        { type = "switch", id = "enabled", title = "Enable Air Walk", value = state.enabled },
        { type = "switch", id = "climb_by_jump", title = "Jump to increase height", value = state.climb_by_jump },
        { type = "slider", id = "raise_step", title = "Manual raise step", min = 0.25, max = 3.0, step = 0.25, value = state.raise_step },
        { type = "button", id = "raise_now", title = "Raise Air Walk now" }
    }
})

samp.events.on("ui.control_changed", function(e)
    if e.pageId ~= "settings" then return end
    if e.controlId == "enabled" then
        state.enabled = e.value
        if state.enabled then enable() else clear() end
    elseif e.controlId == "climb_by_jump" then
        state.climb_by_jump = e.value; samp.storage.set("climb_by_jump", e.value)
    elseif e.controlId == "raise_step" then
        state.raise_step = e.value; samp.storage.set("raise_step", e.value)
    elseif e.controlId == "raise_now" and state.anchor_z ~= nil then
        local p = player()
        if p == nil then
            return
        end
        local pos = p:position()
        local new_z = state.anchor_z + state.raise_step
        p:set_position({ x = pos.x, y = pos.y, z = new_z })
        p:set_velocity({ x = 0.0, y = 0.0, z = 0.0 })
        state.anchor_z = new_z
        state.center_x, state.center_y = pos.x, pos.y
        state.surface_z = new_z - FOOT_OFFSET
        if state.surface ~= nil and state.surface:is_valid() then
            state.surface:set_position({
                x = state.center_x,
                y = state.center_y,
                z = state.surface_z
            })
        end
    end
end)

samp.events.on("player.spawned", function() if state.enabled then enable() end end)
samp.events.on("player.died", clear)
samp.events.on("session.ended", clear)
samp.events.on("game.frame", function()
    local ok, err = pcall(update)
    if not ok then
        state.enabled = false; clear()
        samp.log.error("Air Walk stopped: " .. tostring(err))
    end
end)
