-------------------------------------------------
-- Net Speed Widget for Awesome Window Manager
-- Shows current upload/download speed
-- More details could be found here:
-- https://github.com/streetturtle/awesome-wm-widgets/tree/master/net-speed-widget

-- @author Pavel Makhov
-- @copyright 2020 Pavel Makhov
-------------------------------------------------

local awful = require("awful")
local naughty = require("naughty")
local watch = require("awful.widget.watch")
local wibox = require("wibox")
local beautiful = require("beautiful")
local gears = require("gears")

local interface = 'enp0s31f6'

local prev_time = os.clock()
local prev_rx = 0
local prev_tx = 0

local function show_warning(message)
    naughty.notify {
        preset = naughty.config.presets.critical,
        title = 'Net Speed Widget',
        text = message
    }
end

local function convert_to_h(bytes)
    local speed
    local dim
    local bits = bytes * 8
    if bits < 1000 then
        speed = bits
        dim = 'b/s'
    elseif bits < 1000000 then
        speed = bits/1000
        dim = 'Kb/s'
    elseif bits < 1000000000 then
        speed = bits/1000000
        dim = 'Mb/s'
    elseif bits < 1000000000000 then
        speed = bits/1000000000
        dim = 'Gb/s'
    else
        speed = tonumber(bits)
        dim = 'b/s'
    end
    return math.floor(speed + 0.5) .. dim
end

local function split(string_to_split, separator)
    if separator == nil then separator = "%s" end
    local t = {}

    for str in string.gmatch(string_to_split, "([^".. separator .."]+)") do
        table.insert(t, str)
    end

    return t
end

local function network_details()
    -- Returns a widget containing
    -- ip address

    local network_details_widget = wibox.widget {
        id = 'ip_address',
        widget = wibox.widget.textbox,
        set_ip_text = function(self, new_ip_addr)
            self:get_children_by_id('ip_address')[1]:set_text(tostring(new_ip_addr))
        end
    }

    local update_widget = function(widget, stdout, stderr)
        -- Get IP Address
        local ip_addresses = split(stdout, '\r\n')
        widget:set_ip_text("IP \t" .. ip_addresses[1])
    end
    -- [[bash -c "cat /sys/class/net/%s/statistics/*_bytes"]]
    local cmd = [[bash -c "ifconfig enp0s31f6 | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'"]]
    watch(cmd, 5, update_widget, network_details_widget)

    return network_details_widget
end

local function network_speed()
    local network_speed_widget = wibox.widget {
        -- Up Speed Textbox
        {
            id = 'tx_speed',
            align = 'center',
            font = beautiful.font_net,
            widget = wibox.widget.textbox
        },
        -- Down Speed Textbox
        {
            id = 'rx_speed',
            align = 'center',
            widget = wibox.widget.textbox,
            font = beautiful.font_net,
        },
        id = 'net_speed',
        expand = true,
        homogeneous = true,
        layout = wibox.layout.grid.vertical,
        set_tx_text = function(self, new_tx_speed)
            self:get_children_by_id('tx_speed')[1]:set_text(tostring(new_tx_speed))
        end,
        set_rx_text = function(self, new_rx_speed)
            self:get_children_by_id('rx_speed')[1]:set_text(tostring(new_rx_speed))
        end
    }

    local update_widget = function(widget, stdout, stderr)

        local curr_time = os.clock()
        local cur_rx = 0
        local cur_tx = 0

        local cur_vals = split(stdout, '\r\n')

        for i, v in ipairs(cur_vals) do
            if i%2 == 1 then cur_rx = cur_rx + cur_vals[i] end
            if i%2 == 0 then cur_tx = cur_tx + cur_vals[i] end
        end

        local time_diff = (curr_time - prev_time) * 10 -- seconds
        local speed_rx = (cur_rx - prev_rx) / time_diff
        local speed_tx = (cur_tx - prev_tx) / time_diff

        widget:set_rx_text(convert_to_h(speed_rx))
        widget:set_tx_text(convert_to_h(speed_tx))

        prev_time = curr_time
        prev_rx = cur_rx
        prev_tx = cur_tx
    end

    watch(string.format([[bash -c "cat /sys/class/net/%s/statistics/*_bytes"]], interface), 1, update_widget, network_speed_widget)

    return network_speed_widget
end


local function create_popupsection(section_title, section_content)
    return wibox.widget {
        {
            {
                -- Section Title
                {
                    {
                        {
                            id = section_title .. '_title',
                            text = section_title,
                            align = 'center',
                            widget = wibox.widget.textbox
                        },
                        -- Underline
                        bottom = 2,
                        color = beautiful.border_focus,
                        widget = wibox.container.margin,
                    },
                    -- bg = '#FFFFFF',
                    -- fg = beautiful.border_focus,
                    widget = wibox.container.background
                },
                -- Section Content
                section_content,
                expand = true,
                homogeneous = true,
                layout = wibox.layout.grid.vertical
            },
            -- bg = '#FF00FF',
            widget = wibox.container.background
        },
        margins = 10,
        widget = wibox.container.margin,
    }
end

local popup = awful.popup{
    ontop = true,
    visible = false,
    shape = gears.shape.rounded_rect,
    -- border_width = 1,
    border_color = beautiful.bg_normal,
    minimum_width = 200,
    maximum_width = 300,
    offset = { y = 5 },
    widget = {
        {
            create_popupsection('NETWORK', network_details()),
            create_popupsection('GRAPH', nil),
            create_popupsection('PROCESSES', nil),
            expand = true,
            homogeneous = true,
            layout = wibox.layout.grid.vertical
        },
        bg = beautiful.bg_normal,
        widget = wibox.container.background,
    }
}


local net_speed_widget = wibox.widget {
    network_speed(),
    widget = wibox.container.background,
}

net_speed_widget:buttons(
    awful.util.table.join(
        awful.button({}, 1, function()
            if popup.visible then
                popup.visible = not popup.visible
            else
                popup:move_next_to(mouse.current_widget_geometry)
            end
        end)
    )
)

local function worker(args)

    local args = args or {}

    return net_speed_widget

end

return setmetatable(net_speed_widget, { __call = function(_, ...) return worker(...) end })
