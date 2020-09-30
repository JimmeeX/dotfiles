local awful         = require("awful")
local beautiful     = require("beautiful")
local gears         = require("gears")
local wibox         = require("wibox")

local clock_widget = wibox.widget.textclock(" %a %b %d %l:%M%P ")
local month_calendar = awful.widget.calendar_popup.month({
    font = beautiful.font_small,
    style_month = {
        shape = gears.shape.rounded_rect,
        border_width = 1,
        border_color = beautiful.bg_focus
    },
    style_normal = {
        shape = gears.shape.rounded_rect,
    },
    style_focus = {
        shape = gears.shape.rounded_rect,
    }
})
month_calendar:attach( clock_widget, 'tr' )

return clock_widget