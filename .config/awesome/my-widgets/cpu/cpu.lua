local awful = require("awful")
local watch = require("awful.widget.watch")
local wibox = require("wibox")
local beautiful = require("beautiful")
local gears = require("gears")

local function worker(args)
    local cpugraph_widget = wibox.widget {
        max_value = 100,
        background_color = "#00000000",
        forced_width = width,
        step_width = step_width,
        step_spacing = step_spacing,
        widget = wibox.widget.graph,
        color = "linear:0,0:0,20:0,#FF0000:0.3,#FFFF00:0.6," .. color
    }

    local cpu_widget = wibox.container.margin(wibox.container.mirror(cpugraph_widget, { horizontal = true }), 0, 0, 0, 2)
    return cpu_widget
end

-- return setmetatable(net_speed_widget, { __call = function(_, ...) return worker(...) end })