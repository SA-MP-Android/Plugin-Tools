local defaults = require("defaults")
local state = {
    enabled = samp.storage.get("enabled", defaults.enabled),
    text = samp.storage.get("label", defaults.text),
    size = samp.storage.get("size", defaults.size),
    color = samp.storage.get("color", "white"),
    invulnerable = false,
    air_walk = false,
    noclip = false,
    standing = false
}

local effect_leases = {
    collision_filter = nil,
    physics_flags = nil
}

local movement = {
    surface = nil,
    anchor_z = nil,
    center_x = nil,
    center_y = nil,
    surface_z = nil,
    last_position = nil,
    suspended = false
}

local AIR_WALK_START_OFFSET = 3.0
local PED_FOOT_OFFSET = 1.0
local PLATFORM_FOLLOW_DISTANCE = 4.0
local HEIGHT_EPSILON = 0.05
local MINIMUM_UPWARD_SPEED = 0.02
local RELOCATION_DISTANCE = 0.5

samp.log.info("loading " .. samp.plugin.id .. " with API " .. samp.api.version)

local function log_lifecycle(event)
    samp.log.info(
        event.name ..
        " in session " ..
        samp.format.number(event.sessionId, 0)
    )
end

samp.events.on("plugin.loaded", function(event)
    samp.log.info(
        "one-shot high-priority callback for " ..
        event.name
    )
    local vehicle_page = samp.entity.list("vehicle", 0, 16)
    samp.log.info(
        "first streamed vehicle page contains " ..
        samp.format.number(#vehicle_page.items, 0) ..
        " handles"
    )
end, {
    priority = 100,
    once = true
})

samp.events.on("session.started", log_lifecycle)
samp.events.on("session.ended", log_lifecycle)
samp.events.on("game.ready", log_lifecycle)
samp.events.on("server.connected", log_lifecycle)
samp.events.on("server.disconnected", log_lifecycle)
samp.events.on("player.spawned", log_lifecycle)
samp.events.on("player.died", log_lifecycle)

samp.events.on("player.health_changed", function(event)
    samp.log.info(
        "health changed from " ..
        samp.format.number(event.previousHealth, 1) ..
        " to " ..
        samp.format.number(event.health, 1)
    )
end)

samp.events.on("player.vehicle_entered", function(event)
    samp.log.info(
        "entered vehicle " ..
        samp.format.number(event.vehicleId, 0) ..
        " passenger=" ..
        tostring(event.passenger)
    )
end)

samp.events.on("player.vehicle_left", function(event)
    samp.log.info(
        "left vehicle " ..
        samp.format.number(event.vehicleId, 0) ..
        " passenger=" ..
        tostring(event.passenger)
    )
end)

samp.events.on("player.interior_changed", function(event)
    samp.log.info(
        "interior changed from " ..
        samp.format.number(event.previousInterior, 0) ..
        " to " ..
        samp.format.number(event.interior, 0)
    )
end)

samp.events.on("chat.message_received", function(event)
    samp.log.info(
        "chat from " .. event.playerName ..
        " (" .. samp.format.number(event.playerId, 0) .. "): " ..
        event.message
    )
end)

samp.events.on("chat.server_message_received", function(event)
    samp.log.info("server message: " .. event.message)
end)

samp.events.on("chat.bubble_received", function(event)
    samp.log.info(
        "bubble from player #" ..
        samp.format.number(event.playerId, 0) ..
        ": " .. event.message
    )
end)

local function log_checkpoint(event)
    samp.log.info(
        event.name .. " kind=" .. event.kind ..
        " at (" ..
        samp.format.number(event.position.x, 1) .. ", " ..
        samp.format.number(event.position.y, 1) .. ", " ..
        samp.format.number(event.position.z, 1) .. ")"
    )
end

samp.events.on("checkpoint.entered", log_checkpoint)
samp.events.on("checkpoint.left", log_checkpoint)
samp.events.on("ui.menu_opened", log_lifecycle)
samp.events.on("ui.menu_closed", log_lifecycle)

local function log_entity_stream(event)
    samp.log.info(
        event.name .. " " .. event.entityType ..
        "#" .. samp.format.number(event.entityId, 0) ..
        " generation=" ..
        samp.format.number(event.streamGeneration, 0)
    )
    if event.name == "entity.streamed_in" then
        local entity = samp.entity.get(
            event.entityType,
            event.entityId,
            event.streamGeneration
        )
        if entity ~= nil and entity:is_valid() then
            local position = entity:position()
            samp.log.info(
                "entity position=(" ..
                samp.format.number(position.x, 1) .. ", " ..
                samp.format.number(position.y, 1) .. ", " ..
                samp.format.number(position.z, 1) .. ")"
            )
            if entity.type == "text_label" then
                samp.log.info("3D text label: " .. entity:text())
            elseif entity.type == "pickup" then
                samp.log.info(
                    "pickup model=" ..
                    samp.format.number(entity:model(), 0)
                )
            elseif entity.type == "actor" then
                samp.log.info(
                    "actor health=" ..
                    samp.format.number(entity:health(), 1)
                )
            end
        end
    end
end

samp.events.on("entity.streamed_in", log_entity_stream)
samp.events.on("entity.streamed_out", log_entity_stream)

samp.events.on("chat.message_sending", function(event)
    if event.message == "!plugin-example-block" then
        event.cancelled = true
        samp.log.info("blocked the API showcase test message")
    end
end)

samp.events.on("command.executing", function(event)
    if event.command == "/plugin-example-block" then
        event.cancelled = true
        samp.log.info("blocked the API showcase test command")
    end
end)

samp.events.on("dialog.shown", function(event)
    samp.log.info(
        "dialog #" .. samp.format.number(event.dialogId, 0) ..
        " shown as " .. event.style .. ": " .. event.title
    )
end)

samp.events.on("dialog.responding", function(event)
    if event.input == "plugin-example-block" then
        event.cancelled = true
        samp.log.info("blocked the API showcase test dialog response")
    end
end)

local blocked_textdraws = {}

local function textdraw_key(event)
    return samp.format.number(event.textdrawId, 0) .. ":" ..
        samp.format.number(event.textdrawGeneration, 0)
end

samp.events.on("textdraw.shown", function(event)
    samp.log.info(
        "textdraw #" .. samp.format.number(event.textdrawId, 0) ..
        " generation=" ..
        samp.format.number(event.textdrawGeneration, 0) ..
        " shown: " .. event.text
    )
    if event.text == "plugin-example-block" then
        blocked_textdraws[textdraw_key(event)] = true
    end
end)

samp.events.on("textdraw.text_changed", function(event)
    blocked_textdraws[textdraw_key(event)] =
        event.text == "plugin-example-block"
end)

samp.events.on("textdraw.hidden", function(event)
    blocked_textdraws[textdraw_key(event)] = nil
end)

samp.events.on("textdraw.clicking", function(event)
    if blocked_textdraws[textdraw_key(event)] then
        event.cancelled = true
        samp.log.info("blocked the API showcase test TextDraw click")
    end
end)

local function log_local_player()
    if not samp.api.has("player.local_player") then
        return
    end
    local player = samp.player.local_player()
    if player == nil then
        samp.log.info("local player is not available")
        return
    end

    local position = player:position()
    samp.log.info(
        "local player health=" ..
        samp.format.number(player:health(), 0) ..
        " armor=" ..
        samp.format.number(player:armor(), 0) ..
        " position=(" ..
        samp.format.number(position.x, 1) .. ", " ..
        samp.format.number(position.y, 1) .. ", " ..
        samp.format.number(position.z, 1) .. ")"
    )

    local vehicle = player:vehicle()
    if vehicle ~= nil then
        samp.log.info(
            "current vehicle " ..
            samp.format.number(vehicle.poolId, 0) ..
            " health=" ..
            samp.format.number(vehicle:health(), 0)
        )
    end
end

samp.events.on("player.spawned", log_local_player)

local function log_game_and_server()
    local game = samp.game.state()
    samp.log.info(
        "game ready=" ..
        tostring(game.ready) ..
        " multiplayer=" ..
        tostring(game.multiplayer) ..
        " localPlayerAvailable=" ..
        tostring(game.localPlayerAvailable) ..
        " playerGeneration=" ..
        samp.format.number(game.playerGeneration, 0) ..
        " interior=" ..
        samp.format.number(game.interior, 0)
    )

    local server = samp.server.current()
    if server == nil then
        samp.log.info("server is not available")
        return
    end
    samp.log.info(
        "server " ..
        server.address ..
        ":" ..
        samp.format.number(server.port, 0) ..
        " state=" ..
        server.state ..
        " name=" ..
        server.name
    )
end

samp.events.on("game.ready", log_game_and_server)
samp.events.on("server.connected", log_game_and_server)
samp.events.on("server.disconnected", log_game_and_server)

local function get_local_player()
    local player = samp.player.local_player()
    if player == nil then
        samp.log.warn("action skipped: local player is unavailable")
    end
    return player
end

local function release_effect(name)
    local lease = effect_leases[name]
    if lease ~= nil then
        lease:release()
        effect_leases[name] = nil
    end
end

local function release_movement_resources()
    release_effect("collision_filter")
    if movement.surface ~= nil then
        movement.surface:release()
    end
    movement.surface = nil
    movement.anchor_z = nil
    movement.center_x = nil
    movement.center_y = nil
    movement.surface_z = nil
    movement.last_position = nil
end

local function movement_requested()
    return state.air_walk or state.noclip
end

local function acquire_collision_filter()
    release_effect("collision_filter")
    if not state.noclip or movement.surface == nil then
        return
    end
    effect_leases.collision_filter = samp.effects.acquire(
        "player.collision_filter",
        {
            mode = "only_surface",
            surface = movement.surface
        }
    )
end

local function create_movement_surface(start_offset)
    local player = get_local_player()
    if player == nil or player:vehicle() ~= nil then
        return false
    end

    local position = player:position()
    if start_offset > 0.0 then
        position.z = position.z + start_offset
        player:set_position(position)
        player:set_velocity({ x = 0.0, y = 0.0, z = 0.0 })
    end
    movement.anchor_z = position.z
    movement.center_x = position.x
    movement.center_y = position.y
    movement.surface_z = position.z - PED_FOOT_OFFSET
    movement.last_position = {
        x = position.x,
        y = position.y,
        z = position.z
    }
    movement.surface = samp.physics.create_surface({
        position = {
            x = position.x,
            y = position.y,
            z = movement.surface_z
        }
    })
    acquire_collision_filter()
    return true
end

local function refresh_movement(start_offset)
    if not movement_requested() then
        movement.suspended = false
        release_movement_resources()
        return
    end
    if movement.surface == nil then
        create_movement_surface(start_offset)
    else
        acquire_collision_filter()
    end
end

local function update_movement()
    if not movement_requested() then
        return
    end
    local player = samp.player.local_player()
    if player == nil then
        return
    end
    if player:vehicle() ~= nil then
        if movement.surface ~= nil then
            release_movement_resources()
            movement.suspended = true
        end
        return
    end
    if movement.surface == nil then
        local offset = movement.suspended and 0.0 or AIR_WALK_START_OFFSET
        movement.suspended = false
        if not create_movement_surface(offset) then
            return
        end
    end

    local position = player:position()
    local velocity = player:velocity()
    local previous = movement.last_position
    local relocated = false
    if previous ~= nil then
        local dx = position.x - previous.x
        local dy = position.y - previous.y
        local dz = position.z - previous.z
        relocated = dx * dx + dy * dy + dz * dz >
            RELOCATION_DISTANCE * RELOCATION_DISTANCE
    end
    movement.last_position = {
        x = position.x,
        y = position.y,
        z = position.z
    }

    if relocated or
        (velocity.z > MINIMUM_UPWARD_SPEED and
         position.z > movement.anchor_z + HEIGHT_EPSILON) then
        movement.anchor_z = position.z
    end

    local dx = position.x - movement.center_x
    local dy = position.y - movement.center_y
    local moved_horizontally = dx * dx + dy * dy >
        PLATFORM_FOLLOW_DISTANCE * PLATFORM_FOLLOW_DISTANCE
    local surface_z = movement.anchor_z - PED_FOOT_OFFSET
    local height_changed = math.abs(surface_z - movement.surface_z) >
        HEIGHT_EPSILON
    if relocated or moved_horizontally then
        movement.center_x = position.x
        movement.center_y = position.y
    end
    if relocated or moved_horizontally or height_changed then
        movement.surface_z = surface_z
        movement.surface:set_position({
            x = movement.center_x,
            y = movement.center_y,
            z = movement.surface_z
        })
    end
end

local function apply_standing(enabled)
    release_effect("physics_flags")
    if not enabled or get_local_player() == nil then
        return
    end

    local ok, result = pcall(function()
        return samp.effects.acquire(
            "player.physics_flags",
            {
                onSolidSurface = true,
                isStanding = true,
                wasStanding = true,
                priority = 50
            }
        )
    end)
    if ok then
        effect_leases.physics_flags = result
        samp.log.info("Lua standing policy enabled")
    else
        samp.log.error("unable to apply standing flags: " .. tostring(result))
    end
end

local function reapply_enabled_effects()
    -- The host has already invalidated old-generation leases at this point.
    effect_leases.collision_filter = nil
    effect_leases.physics_flags = nil
    movement.surface = nil
    movement.last_position = nil
    movement.suspended = false
    apply_standing(state.standing)
    refresh_movement(AIR_WALK_START_OFFSET)
end

samp.events.on("player.spawned", reapply_enabled_effects, {
    priority = -100
})

samp.events.on("player.died", function()
    effect_leases.collision_filter = nil
    effect_leases.physics_flags = nil
    movement.surface = nil
    movement.last_position = nil
end)

samp.events.on("player.damage_before", function(event)
    if state.invulnerable then
        event.damage = 0.0
    end
end, {
    priority = 100
})

samp.events.on("server.disconnected", function()
    effect_leases.collision_filter = nil
    effect_leases.physics_flags = nil
    movement.surface = nil
    movement.last_position = nil
end)

samp.events.on("game.frame", function()
    local ok, failure = pcall(update_movement)
    if not ok then
        samp.log.error("movement example stopped: " .. tostring(failure))
        state.air_walk = false
        state.noclip = false
        release_movement_resources()
    end
end)

samp.ui.menu.register({
    id = "main",
    title = "Plugin API Example",
    controls = {
        {
            type = "section",
            id = "hud_section",
            title = "HUD settings"
        },
        {
            type = "text",
            id = "description",
            title = "Status",
            text = "This page is registered by Lua."
        },
        {
            type = "switch",
            id = "enabled",
            title = "Show HUD text",
            value = state.enabled
        },
        {
            type = "slider",
            id = "size",
            title = "Text size",
            min = 12.0,
            max = 32.0,
            step = 1.0,
            value = state.size
        },
        {
            type = "choice",
            id = "color",
            title = "Text color",
            value = state.color,
            options = {
                { value = "white", label = "White" },
                { value = "green", label = "Green" },
                { value = "blue", label = "Blue" }
            }
        },
        {
            type = "text_input",
            id = "label",
            title = "HUD label",
            value = state.text,
            placeholder = "Enter HUD text",
            max_length = 64
        },
        {
            type = "section",
            id = "actions_section",
            title = "Actions"
        },
        {
            type = "button",
            id = "log",
            title = "Write a test log"
        },
        {
            type = "text",
            id = "phase_e_warning",
            title = "Session only",
            text = "Effects are intentionally not persisted. Test them in a safe location."
        },
        {
            type = "button",
            id = "restore_player",
            title = "Set health and armor to 100"
        },
        {
            type = "button",
            id = "lift_entity",
            title = "Lift player or current vehicle by 2m"
        },
        {
            type = "button",
            id = "stop_entity",
            title = "Clear player or vehicle velocity"
        },
        {
            type = "button",
            id = "repair_vehicle",
            title = "Set current vehicle health to 1000"
        },
        {
            type = "switch",
            id = "invulnerable",
            title = "Lua invulnerability policy",
            value = state.invulnerable
        },
        {
            type = "switch",
            id = "air_walk",
            title = "Air walk: start +3m, climb by jumping",
            value = state.air_walk
        },
        {
            type = "switch",
            id = "noclip",
            title = "Noclip: Air Walk with selective collision",
            value = state.noclip
        },
        {
            type = "switch",
            id = "standing",
            title = "Lua-composed standing flags",
            value = state.standing
        }
    }
})

samp.events.on("ui.control_changed", function(event)
    if event.pageId ~= "main" then
        return
    end
    if event.controlId == "enabled" then
        state.enabled = event.value
        samp.storage.set("enabled", state.enabled)
    elseif event.controlId == "size" then
        state.size = event.value
        samp.storage.set("size", state.size)
    elseif event.controlId == "color" then
        state.color = event.value
        samp.storage.set("color", state.color)
    elseif event.controlId == "label" then
        state.text = event.value
        samp.storage.set("label", state.text)
    elseif event.controlId == "log" then
        samp.log.info("test button clicked")
    elseif event.controlId == "restore_player" then
        local player = get_local_player()
        if player ~= nil then
            player:set_health(100.0)
            player:set_armor(100.0)
            samp.log.info("player health and armor restored")
        end
    elseif event.controlId == "lift_entity" then
        local player = get_local_player()
        if player ~= nil then
            local vehicle = player:vehicle()
            if vehicle ~= nil then
                local position = vehicle:position()
                position.z = position.z + 2.0
                vehicle:set_position(position)
                samp.log.info("current vehicle lifted by 2m")
            else
                local position = player:position()
                position.z = position.z + 2.0
                player:set_position(position)
                samp.log.info("player lifted by 2m")
            end
        end
    elseif event.controlId == "stop_entity" then
        local player = get_local_player()
        if player ~= nil then
            local zero = { x = 0.0, y = 0.0, z = 0.0 }
            local vehicle = player:vehicle()
            if vehicle ~= nil then
                vehicle:set_velocity(zero)
                samp.log.info("current vehicle velocity cleared")
            else
                player:set_velocity(zero)
                samp.log.info("player velocity cleared")
            end
        end
    elseif event.controlId == "repair_vehicle" then
        local player = get_local_player()
        if player ~= nil then
            local vehicle = player:vehicle()
            if vehicle == nil then
                samp.log.warn("vehicle repair skipped: player is not in a vehicle")
            else
                vehicle:set_health(1000.0)
                samp.log.info("current vehicle health set to 1000")
            end
        end
    elseif event.controlId == "invulnerable" then
        state.invulnerable = event.value
        samp.log.info("Lua invulnerability=" .. tostring(state.invulnerable))
    elseif event.controlId == "air_walk" then
        state.air_walk = event.value
        refresh_movement(AIR_WALK_START_OFFSET)
    elseif event.controlId == "noclip" then
        state.noclip = event.value
        refresh_movement(AIR_WALK_START_OFFSET)
    elseif event.controlId == "standing" then
        state.standing = event.value
        apply_standing(state.standing)
    end
end)

samp.events.on("draw.hud", function()
    if not state.enabled then
        return
    end
    local colors = {
        white = 0xFFFFFFFF,
        green = 0xFF66DD88,
        blue = 0xFF66AAFF
    }
    samp.draw.text({
        x = 24.0,
        y = 120.0,
        text = state.text,
        color = colors[state.color] or colors.white,
        size = state.size
    })
    samp.draw.progress_bar({
        x1 = 24.0,
        y1 = 154.0,
        x2 = 224.0,
        y2 = 164.0,
        value = 0.65,
        color = colors[state.color] or colors.white,
        background_color = 0x66000000
    })

    local player = samp.player.local_player()
    if player ~= nil then
        local position = player:position()
        position.z = position.z + 1.0
        local screen = samp.draw.world_to_screen(position)
        if screen ~= nil then
            samp.draw.circle({
                x = screen.x,
                y = screen.y,
                radius = 5.0,
                color = 0xFFFFFFFF,
                filled = false,
                thickness = 2.0
            })
        end
    end
end)

samp.timer.after(1000, function()
    samp.log.info("one-second timer completed")
end)
