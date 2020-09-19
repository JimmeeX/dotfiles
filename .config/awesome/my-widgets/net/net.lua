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

local graph_tx_max = 40000000       -- Mb/s
local graph_rx_max = 100000000      -- Mb/s
local graph_padding = 0.01          -- %
local graph_bg = '#2C2F5D'

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
        id = 'network_details',
        widget = wibox.widget.textbox,
        set_details_text = function(self, new_details)
            self:get_children_by_id('network_details')[1]:set_text(tostring(new_details))
        end
    }

    local update_widget = function(widget, stdout, stderr)
        -- Get IP Address
        local ip_address = split(stdout, '\r\n')[1]
        local text =
            "IP Address\t" .. ip_address .. "\n" ..
            "Interface \t" .. interface
        widget:set_details_text(text)
    end

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

    local network_hist_tx_widget = wibox.widget {
        --     local network_history_up = wibox.widget {
        max_value = graph_tx_max + graph_tx_max*graph_padding, -- 40 Mb/s
        -- background_color = beautiful.bg_normal,
        background_color = graph_bg,
        -- forced_width = 100,
        forced_height = 50,
        step_width = 2,
        step_spacing = 1,
        color = '#FF16B0',
        widget = wibox.widget.graph
    }

    local network_hist_rx_widget = wibox.widget {
        --     local network_history_up = wibox.widget {
        max_value = graph_rx_max + graph_rx_max*graph_padding, -- 100 Mb/s
        -- background_color = beautiful.bg_normal,
        background_color = graph_bg,
        -- forced_width = 100,
        forced_height = 50,
        step_width = 2,
        step_spacing = 1,
        color = '#46BDFF',
        widget = wibox.widget.graph
    }

    local network_history_widget = wibox.widget {
        {
            {
                {
                    -- Mirrored so graph starts on right
                    network_hist_tx_widget,
                    reflection = { horizontal = true },
                    widget = wibox.container.mirror
                },
                -- top = 10,
                bottom = 1,
                widget = wibox.container.margin
            },
            {
                {
                    -- Mirrored so graph starts on right and is facing downwards
                    network_hist_rx_widget,
                    direction = 'south',
                    widget = wibox.container.rotate
                },
                top = 1,
                -- bottom = 10,
                widget = wibox.container.margin
            },
            layout = wibox.layout.fixed.vertical
        },
        bg = graph_bg,
        widget = wibox.container.background
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

        network_hist_rx_widget:add_value(speed_rx*8 + graph_rx_max*graph_padding)
        network_hist_tx_widget:add_value(speed_tx*8 + graph_tx_max*graph_padding)

        prev_time = curr_time
        prev_rx = cur_rx
        prev_tx = cur_tx
    end

    watch(string.format([[bash -c "cat /sys/class/net/%s/statistics/*_bytes"]], interface), 1, update_widget, network_speed_widget)

    return network_speed_widget, network_history_widget
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
                {
                    section_content,
                    top = 10,
                    widget = wibox.container.margin,
                },
                layout = wibox.layout.fixed.vertical
            },
            -- bg = '#FF00FF',
            widget = wibox.container.background
        },
        margins = 10,
        widget = wibox.container.margin,
    }
end

local network_speed_widget, network_history_widget = network_speed()

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
            create_popupsection('GRAPH', network_history_widget),
            create_popupsection('PROCESSES', nil),
            -- expand = true,
            -- homogeneous = true,
            layout = wibox.layout.fixed.vertical
        },
        bg = beautiful.bg_normal,
        widget = wibox.container.background,
    }
}


local net_speed_widget = wibox.widget {
    network_speed_widget,
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
