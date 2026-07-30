--------------------------------------------------
-- FPS Counter Plugin
--------------------------------------------------

local function clamp(value, min, max)

    if value < min then
        return min
    end

    if value > max then
        return max
    end

    return value
end



--------------------------------------------------
-- Color helpers
--------------------------------------------------

local function make_color(r, g, b, a)

    return
        ((a & 0xFF) << 24)
        |
        ((r & 0xFF) << 16)
        |
        ((g & 0xFF) << 8)
        |
        (b & 0xFF)

end



--------------------------------------------------
-- Config
--------------------------------------------------

local config = {

    visible =
        samp.storage.get(
            "visible",
            true
        ),


    -- screen percentage

    x =
        clamp(
            samp.storage.get(
                "x",
                0.02
            ),
            0.0,
            1.0
        ),


    y =
        clamp(
            samp.storage.get(
                "y",
                0.03
            ),
            0.0,
            1.0
        ),



    size =
        clamp(
            samp.storage.get(
                "size",
                34
            ),
            20,
            80
        ),



    r =
        clamp(
            samp.storage.get(
                "r",
                255
            ),
            0,
            255
        ),


    g =
        clamp(
            samp.storage.get(
                "g",
                255
            ),
            0,
            255
        ),


    b =
        clamp(
            samp.storage.get(
                "b",
                255
            ),
            0,
            255
        ),


    a =
        clamp(
            samp.storage.get(
                "a",
                255
            ),
            0,
            255
        )
}



local smoothed_fps = 0.0



--------------------------------------------------
-- UI
--------------------------------------------------

samp.ui.menu.register({

    id = "settings",

    title = "FPS Counter",


    controls = {


        {
            type = "switch",

            id = "visible",

            title = "Show FPS",

            value = config.visible
        },


        {
            type = "slider",

            id = "x",

            title = "Horizontal position",

            min = 0.0,

            max = 1.0,

            step = 0.01,

            value = config.x
        },


        {
            type = "slider",

            id = "y",

            title = "Vertical position",

            min = 0.0,

            max = 1.0,

            step = 0.01,

            value = config.y
        },



        {
            type = "slider",

            id = "size",

            title = "Font size",

            min = 20,

            max = 80,

            step = 1,

            value = config.size
        },



        {
            type = "slider",

            id = "red",

            title = "Red",

            min = 0,

            max = 255,

            step = 1,

            value = config.r
        },


        {
            type = "slider",

            id = "green",

            title = "Green",

            min = 0,

            max = 255,

            step = 1,

            value = config.g
        },


        {
            type = "slider",

            id = "blue",

            title = "Blue",

            min = 0,

            max = 255,

            step = 1,

            value = config.b
        },


        {
            type = "slider",

            id = "alpha",

            title = "Alpha",

            min = 0,

            max = 255,

            step = 1,

            value = config.a
        }

    }

})



--------------------------------------------------
-- UI events
--------------------------------------------------

samp.events.on(
"ui.control_changed",
function(event)


    if event.pageId ~= "settings" then
        return
    end



    local id = event.controlId

    local value = event.value



    if id == "visible" then


        if type(value) ~= "boolean" then
            return
        end


        config.visible = value


        samp.storage.set(
            "visible",
            value
        )



    elseif id == "x" then


        if type(value) ~= "number" then
            return
        end


        config.x =
            clamp(value,0,1)


        samp.storage.set(
            "x",
            config.x
        )



    elseif id == "y" then


        if type(value) ~= "number" then
            return
        end


        config.y =
            clamp(value,0,1)


        samp.storage.set(
            "y",
            config.y
        )



    elseif id == "size" then


        if type(value) ~= "number" then
            return
        end


        config.size =
            clamp(value,20,80)


        samp.storage.set(
            "size",
            config.size
        )



    elseif id == "red" then


        config.r =
            clamp(value,0,255)


        samp.storage.set(
            "r",
            config.r
        )



    elseif id == "green" then


        config.g =
            clamp(value,0,255)


        samp.storage.set(
            "g",
            config.g
        )



    elseif id == "blue" then


        config.b =
            clamp(value,0,255)


        samp.storage.set(
            "b",
            config.b
        )



    elseif id == "alpha" then


        config.a =
            clamp(value,0,255)


        samp.storage.set(
            "a",
            config.a
        )

    end


end)



--------------------------------------------------
-- Draw HUD
--------------------------------------------------

samp.events.on(
"draw.hud",
function(event)


    local delta =
        event.deltaSeconds



    if delta ~= nil
    and delta > 0 then


        local current_fps =
            math.min(
                1000,
                1 / delta
            )



        if smoothed_fps <= 0 then


            smoothed_fps =
                current_fps



        elseif current_fps < smoothed_fps then


            -- 快速响应下降


            smoothed_fps =
                smoothed_fps * 0.5
                +
                current_fps * 0.5



        else


            -- 缓慢平滑恢复


            smoothed_fps =
                smoothed_fps * 0.9
                +
                current_fps * 0.1


        end

    end




    if not config.visible then
        return
    end



    if smoothed_fps <= 0 then
        return
    end



    local x =
        event.screenWidth
        *
        config.x



    local y =
        event.screenHeight
        *
        config.y




    local color =
        make_color(
            config.r,
            config.g,
            config.b,
            config.a
        )



    samp.draw.text({

        x = x,

        y = y,


        text =
            "FPS: "
            ..
            samp.format.number(
                smoothed_fps,
                0
            ),


        color = color,


        size =
            config.size

    })

end)