local awful = require("awful")
local naughty = require("naughty")
local watch = require("awful.widget.watch")
local wibox = require("wibox")
local beautiful = require("beautiful")
local gears = require("gears")

local function show_warning(title, message)
    naughty.notify {
        preset = naughty.config.presets.critical,
        title = tostring(title),
        text = tostring(message)
    }
end

local function quote_arg(str)
    return "'" .. string.gsub(str, "'", "'\\''") .. "'"
end

local function table_map(func, tab)
    local result = {}
    for i, v in ipairs(tab) do
        result[i] = func(v)
    end
    return result
end

local function make_argv(args)
    return table.concat(table_map(quote_arg, args), " ")
end

local function substitute(template, context)
  if type(template) == "string" then
    return (template:gsub("%${([%w_]+)}", function(key)
      return tostring(context[key] or "default")
    end))
  else
    -- function / functor:
    return template(context)
  end
end

local function new(self, ...)
    local instance = setmetatable({}, {__index = self})
    return instance:init(...) or instance
end

local function class(base)
    return setmetatable({new = new}, {
        __call = new,
        __index = base,
    })
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

function os.capture(cmd, raw)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    if raw then return s end
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
    return s
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

------------------------------------------
-- NET widget
------------------------------------------

local net_widget = class()

function net_widget:init(args)
    self.interface  = 'enp0s31f6'
    self.ip_address = os.capture([[ifconfig enp0s31f6 | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n 1]])

    self.max_up_speed   = 40000000       -- Mb/s
    self.max_down_speed = 100000000      -- Mb/s

    self.prev_time  = os.clock()
    self.prev_up    = os.capture(string.format([[cat /sys/class/net/%s/statistics/tx_bytes]], self.interface))
    self.prev_down  = os.capture(string.format([[cat /sys/class/net/%s/statistics/rx_bytes]], self.interface))

    self.update_rate    = 1 -- every N seconds
    self.graph_max      = 1
    self.graph_padding  = 0.01

    -- Widget References
    self.widget_display_text = {}   -- Reference to Progress Bars
    self.net_graph_widget = {}      -- Reference to popup graph

    self:create_widget_popup(args)
    self:create_widget_display(args)
    awful.widget.watch(string.format([[bash -c "cat /sys/class/net/%s/statistics/*_bytes"]], self.interface), self.update_rate, function (widget, stdout, stderr) self:update_widget(widget, stdout, stderr) end, self.widget)
end

function net_widget:create_widget_popup(args)
    -- Net Info
    -- Net Graph (Up/Down)
    self.widget_popup = awful.popup{
        ontop = true,
        visible = false,
        shape = gears.shape.rounded_rect,
        border_width = 1,
        border_color = beautiful.bg_focus,
        minimum_width = 350,
        maximum_width = 350,
        offset = { y = 5 },
        widget = {
            {
                create_popupsection('NETWORK', self:create_widget_net_subsection()),
                create_popupsection('GRAPH', self:create_widget_graph_subsection()),
                layout = wibox.layout.fixed.vertical
            },
            bg = beautiful.bg_normal,
            widget = wibox.container.background,
        }
    }
end

function net_widget:create_widget_display(args)
    self.widget_display_text['up'] = wibox.widget {
        -- Up Speed Textbox
        align = 'center',
        font = beautiful.font_msmall,
        widget = wibox.widget.textbox
    }

    self.widget_display_text['down'] = wibox.widget {
        align = 'center',
        font = beautiful.font_msmall,
        widget = wibox.widget.textbox,
    }

    self.widget = wibox.widget {
        {
            self.widget_display_text['up'],
            self.widget_display_text['down'],
            expand = true,
            homogeneous = true,
            layout = wibox.layout.grid.vertical,
        },
        margins = 5,
        widget = wibox.container.margin
    }

    self.widget:connect_signal("mouse::enter", function(c)
        self.widget_popup:move_next_to(mouse.current_widget_geometry)
        self.widget_popup.visible = true
    end)
    self.widget:connect_signal("mouse::leave", function(c) self.widget_popup.visible = false end)
end

function net_widget:create_widget_net_subsection()
    -- Net Details
        -- IP Address
        -- Interface
    return wibox.widget {
        markup =
            "Interface:\t" .. self.interface .. "\n" ..
            "IP Address:\t" .. self.ip_address,
        font = beautiful.font_small,
        widget = wibox.widget.textbox,
    }
end

function net_widget:create_widget_graph_subsection()
    -- Top -> Up Speed (TX)
    -- Bottom -> Down Speed (RX)

    self.net_graph_widget['up'] = wibox.widget {
        max_value = self.graph_max + self.graph_max*self.graph_padding,
        background_color = beautiful.bg_focus,
        forced_height = 50,
        step_width = 2,
        step_spacing = 1.5,
        color = '#FF16B0',
        widget = wibox.widget.graph
    }

    self.net_graph_widget['down'] = wibox.widget {
        max_value = self.graph_max + self.graph_max*self.graph_padding,
        background_color = beautiful.bg_focus,
        forced_height = 50,
        step_width = 2,
        step_spacing = 1.5,
        color = '#46BDFF',
        widget = wibox.widget.graph
    }

    self.net_graph_widget['subtext'] = wibox.widget {
        align = 'left',
        font = beautiful.font_small,
        widget = wibox.widget.textbox
    }

    local net_graph_layout = wibox.widget {
        {
            {
                {
                    -- Mirrored so graph starts on right
                    self.net_graph_widget['up'],
                    reflection = { horizontal = true },
                    widget = wibox.container.mirror
                },
                bottom = 1,
                widget = wibox.container.margin
            },
            {
                {
                    -- Mirrored so graph starts on right and is facing downwards
                    self.net_graph_widget['down'],
                    direction = 'south',
                    widget = wibox.container.rotate
                },
                top = 1,
                widget = wibox.container.margin
            },
            layout = wibox.layout.fixed.vertical
        },
        bg = beautiful.bg_focus,
        widget = wibox.container.background
    }

    return wibox.widget {
        net_graph_layout,
        {
            self.net_graph_widget['subtext'],
            top = 5,
            widget = wibox.container.margin
        },
        layout = wibox.layout.fixed.vertical
    }
end

function net_widget:update_widget(widget, stdout, stderr)
    local cur_time  = os.clock()
    local cur_down  = 0
    local cur_up    = 0

    local cur_vals = split(stdout, '\r\n')

    for i, v in ipairs(cur_vals) do
        if i%2 == 1 then cur_down = cur_down + cur_vals[i] end
        if i%2 == 0 then cur_up = cur_up + cur_vals[i] end
    end

    local time_diff     = (cur_time - self.prev_time) * 10 -- seconds
    local speed_up      = (cur_up - self.prev_up) / self.update_rate
    local speed_down    = (cur_down - self.prev_down) / self.update_rate

    -- show_warning(time_diff)

    -- Update Display Widget
    self.widget_display_text['up'].markup = convert_to_h(speed_up)
    self.widget_display_text['down'].markup = convert_to_h(speed_down)

    -- Update Popup Graph
    self.net_graph_widget['up']:add_value(speed_up*8 / self.max_up_speed + self.graph_max*self.graph_padding)
    self.net_graph_widget['down']:add_value(speed_down*8 / self.max_down_speed+ self.graph_max*self.graph_padding)
    self.net_graph_widget['subtext'].markup =
        'Up:\t' .. convert_to_h(speed_up) .. '\n' ..
        'Down:\t' .. convert_to_h(speed_down)

    self.prev_time  = cur_time
    self.prev_up    = cur_up
    self.prev_down  = cur_down
end

return net_widget
