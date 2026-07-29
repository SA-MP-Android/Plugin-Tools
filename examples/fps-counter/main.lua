local visible = samp.storage.get("visible", true)
local text_size = math.max(28.0, samp.storage.get("text_size", 34.0))
local smoothed_fps = 0.0

samp.ui.menu.register({
    id = "settings",
    title = "FPS Counter",
    controls = {
        {
            type = "switch",
            id = "visible",
            title = "Show FPS",
            value = visible
        },
        {
            type = "slider",
            id = "text_size",
            title = "Text size",
            min = 28.0,
            max = 52.0,
            step = 1.0,
            value = text_size
        }
    }
})

samp.events.on("ui.control_changed", function(event)
    if event.pageId ~= "settings" then
        return
    end
    if event.controlId == "visible" then
        visible = event.value
        samp.storage.set("visible", visible)
    elseif event.controlId == "text_size" then
        text_size = math.max(28.0, math.min(52.0, event.value))
        samp.storage.set("text_size", text_size)
    end
end)

samp.events.on("draw.hud", function(event)
    local delta = event.deltaSeconds
    if delta ~= nil and delta > 0.0 then
        local current_fps = math.min(1000.0, 1.0 / delta)
        if smoothed_fps == 0.0 then
            smoothed_fps = current_fps
        else
            smoothed_fps = smoothed_fps * 0.9 + current_fps * 0.1
        end
    end

    if not visible or smoothed_fps <= 0.0 then
        return
    end
    local y = math.min(
        event.screenHeight - text_size - 24.0,
        event.screenHeight * 0.285
    )
    samp.draw.text({
        x = 24.0,
        y = y,
        text = "FPS: " .. samp.format.number(smoothed_fps, 0),
        color = 0xFFFFFFFF,
        size = text_size
    })
end)
