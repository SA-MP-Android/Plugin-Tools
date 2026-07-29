local visible = samp.storage.get("visible", true)
local offset_x = samp.storage.get("offset_x", 0.0)
local offset_y = samp.storage.get("offset_y", 0.0)
local arm_length = samp.storage.get("arm_length", 12.0)

samp.ui.menu.register({
    id = "settings",
    title = "Crosshair Guide",
    controls = {
        {
            type = "text",
            id = "hint",
            title = "Position",
            text = "Offsets are relative to the center of the screen."
        },
        {
            type = "switch",
            id = "visible",
            title = "Show guide",
            value = visible
        },
        {
            type = "slider",
            id = "arm_length",
            title = "Arm length",
            min = 4.0,
            max = 40.0,
            step = 1.0,
            value = arm_length
        },
        {
            type = "slider",
            id = "offset_x",
            title = "Horizontal offset",
            min = -640.0,
            max = 640.0,
            step = 10.0,
            value = offset_x
        },
        {
            type = "slider",
            id = "offset_y",
            title = "Vertical offset",
            min = -360.0,
            max = 360.0,
            step = 10.0,
            value = offset_y
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
    elseif event.controlId == "arm_length" then
        arm_length = event.value
        samp.storage.set("arm_length", arm_length)
    elseif event.controlId == "offset_x" then
        offset_x = event.value
        samp.storage.set("offset_x", offset_x)
    elseif event.controlId == "offset_y" then
        offset_y = event.value
        samp.storage.set("offset_y", offset_y)
    end
end)

samp.events.on("draw.hud", function(event)
    if not visible then
        return
    end

    local center_x = event.screenWidth / 2.0 + offset_x
    local center_y = event.screenHeight / 2.0 + offset_y
    local gap = 4.0
    local color = 0xE6FFFFFF
    samp.draw.line({
        x1 = center_x - arm_length,
        y1 = center_y,
        x2 = center_x - gap,
        y2 = center_y,
        thickness = 2.0,
        color = color
    })
    samp.draw.line({
        x1 = center_x + gap,
        y1 = center_y,
        x2 = center_x + arm_length,
        y2 = center_y,
        thickness = 2.0,
        color = color
    })
    samp.draw.line({
        x1 = center_x,
        y1 = center_y - arm_length,
        x2 = center_x,
        y2 = center_y - gap,
        thickness = 2.0,
        color = color
    })
    samp.draw.line({
        x1 = center_x,
        y1 = center_y + gap,
        x2 = center_x,
        y2 = center_y + arm_length,
        thickness = 2.0,
        color = color
    })
    samp.draw.rect({
        x1 = center_x - 1.0,
        y1 = center_y - 1.0,
        x2 = center_x + 1.0,
        y2 = center_y + 1.0,
        thickness = 1.0,
        color = color,
        filled = true
    })
end)
