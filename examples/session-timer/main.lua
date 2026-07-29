local elapsed_seconds = 0.0
local running = samp.storage.get("running", true)

local function two_digits(value)
    local text = samp.format.number(value, 0)
    if value < 10 then
        return "0" .. text
    end
    return text
end

samp.ui.menu.register({
    id = "settings",
    title = "Session Timer",
    controls = {
        {
            type = "switch",
            id = "running",
            title = "Run timer",
            value = running
        },
        {
            type = "button",
            id = "reset",
            title = "Reset timer"
        }
    }
})

samp.events.on("game.frame", function(event)
    if running and event.deltaSeconds ~= nil then
        elapsed_seconds = elapsed_seconds + event.deltaSeconds
    end
end)

samp.events.on("ui.control_changed", function(event)
    if event.pageId ~= "settings" then
        return
    end
    if event.controlId == "running" then
        running = event.value
        samp.storage.set("running", running)
    elseif event.controlId == "reset" then
        elapsed_seconds = 0.0
        samp.log.info("session timer reset")
    end
end)

samp.events.on("draw.hud", function()
    local total = elapsed_seconds // 1
    local minutes = total // 60
    local seconds = total % 60
    samp.draw.text({
        x = 24.0,
        y = 96.0,
        text = "Session: " .. two_digits(minutes) .. ":" .. two_digits(seconds),
        color = 0xFFFFFFFF,
        size = 18.0
    })
end)
