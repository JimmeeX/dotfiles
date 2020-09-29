local awful         = require("awful")
local wibox         = require("wibox")

local clock_widget = wibox.widget.textclock(" %a %b %d %l:%M%P ")
local month_calendar = awful.widget.calendar_popup.month()
month_calendar:attach( clock_widget, 'tr' )

return clock_widget