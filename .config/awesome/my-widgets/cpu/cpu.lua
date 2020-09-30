local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")


------------------------------------------
-- Private utility functions
------------------------------------------

local function show_warning(title, message)
    naughty.notify {
        preset = naughty.config.presets.critical,
        title = tostring(title),
        text = tostring(message)
    }
end

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k,v in pairs(o) do
            if type(k) ~= 'number' then k = '"'..k..'"' end
            s = s .. '['..k..'] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

local function readcommand(command)
    local file = io.popen(command)
    local text = file:read('*all')
    file:close()
    return text
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

local function starts_with(str, start)
    return str:sub(1, #start) == start
end

-- Splits the string by separator
-- @return table with separated substrings
local function split(string_to_split, separator)
    if separator == nil then separator = "%s" end
    local t = {}

    for str in string.gmatch(string_to_split, "([^".. separator .."]+)") do
        table.insert(t, str)
    end

    return t
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
-- Cpu widget
------------------------------------------

local cpu_widget = class()

function cpu_widget:init(args)

    self.cpu_info = {}
    self.cpu_usage = {}
    self.num_processes = 10 -- Top N processes by CPU

    self.update_rate = 1 -- every N seconds
    self.graph_max = 100
    self.graph_padding = 0.01

    -- Widget References
    self.widget_displays = {}       -- Reference to Progress Bars
    self.cpu_graph_widget = {}      -- Reference to popup graph
    self.cpu_processes_widget = {}  -- Reference to popup processes

    self:fetch_data(args)

    self:create_widget_popup(args)
    self:create_widget_display(args)

    awful.widget.watch([[bash -c "lscpu | sed -nr '/CPU MHz/ s/.*:\s*(.*)/\1/p'; cat /proc/stat | grep '^cpu.' ; ps -eo '%p|%c|%C' --sort=-%cpu | head -11 | tail -n +2"]], self.update_rate, function (widget, stdout, stderr) self:update_widget(widget, stdout, stderr) end, self.widget)
end

function cpu_widget:fetch_data(args)
    self.cpu_info['architecture'] = os.capture([[lscpu | sed -nr '/Architecture/ s/.*:\s*(.*)/\1/p']])
    self.cpu_info['model_name'] = os.capture([[lscpu | sed -nr '/Model name/ s/.*:\s*(.*) @ .*/\1/p']])
    self.cpu_info['byte_order'] = os.capture([[lscpu | sed -nr '/Byte Order/ s/.*:\s*(.*)/\1/p']])
    self.cpu_info['num_cpu'] = tonumber(os.capture('nproc'))
    self.cpu_info['max_mhz'] = os.capture([[lscpu | sed -nr '/CPU max MHz/ s/.*:\s*(.*)/\1/p']])
end

function cpu_widget:create_widget_popup(args)
    self.widget_popup = awful.popup {
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
                create_popupsection('CPU', self:create_widget_cpu_subsection()),
                create_popupsection('GRAPH', self:create_widget_graph_subsection()),
                create_popupsection('PROCESSES', self:create_widget_process_subsection()),
                layout = wibox.layout.fixed.vertical
            },
            bg = beautiful.bg_normal,
            widget = wibox.container.background,
        }
    }
end

function cpu_widget:create_widget_display(args)
    local function create_vertical_progress(value)
        local progress_widget = wibox.widget {
            max_value     = 100,
            value         = value,
            -- color         = beautiful.fg_normal,
            color         = beautiful.progress_vertbar,
            background_color = '#2C2F5D',
            widget        = wibox.widget.progressbar,
        }
        return wibox.widget {
            {
                progress_widget,
                forced_width  = 10,
                direction     = 'east',
                layout        = wibox.container.rotate
            },
            bg = beautiful.bg_normal,
            widget = wibox.container.background
        }, progress_widget
    end

    local widget_layout = wibox.widget {
        {
            {
                markup = 'CPU',
                font = beautiful.font_msmall,
                widget = wibox.widget.textbox
            },
            direction     = 'east',
            layout        = wibox.container.rotate
        },
        layout = wibox.layout.fixed.horizontal
    }

    for i = 1, self.cpu_info['num_cpu']+1 do
        local vertical_progress_widget, progress_widget = create_vertical_progress()
        table.insert(self.widget_displays, progress_widget)
        widget_layout:add(vertical_progress_widget)
    end
    -- N Vertical Progress bars
    -- Display Widget

    self.widget = wibox.widget {
        widget_layout,
        margins = 5,
        widget = wibox.container.margin
    }
    self.widget:connect_signal("mouse::enter", function(c)
        self.widget_popup:move_next_to(mouse.current_widget_geometry)
        self.widget_popup.visible = true
    end)
    self.widget:connect_signal("mouse::leave", function(c) self.widget_popup.visible = false end)
end

function cpu_widget:create_widget_cpu_subsection()
    -- Architecture
    -- Model Name
    -- Byte Order
    -- Num CPUs
    -- Max GHz

    return wibox.widget {
        markup = "Architecture:\t" .. self.cpu_info['architecture'] .. '\n' ..
                 "Model:\t\t" .. self.cpu_info['model_name'] .. '\n' ..
                 "Byte Order:\t" .. self.cpu_info['byte_order'] .. '\n' ..
                 "No. CPUs:\t" .. self.cpu_info['num_cpu'] .. '\n' ..
                 "Max MHz:\t" .. self.cpu_info['max_mhz'] .. '\n',
        font = beautiful.font_small,
        widget = wibox.widget.textbox
    }
end

function cpu_widget:create_widget_graph_subsection()
    -- Create Text | Progressbar combo
    local function create_cpu_bar(label, value)
        local cpu_bar_components = {}

        local progress_label = wibox.widget {
            markup = label,
            font = beautiful.font_small,
            widget = wibox.widget.textbox
        }

        local progress_widget = wibox.widget {
            max_value     = 100,
            value         = value,
            color         = {type="linear", from = {0, 0}, to = {120, 0}, stops = { {0, "#46BDFF"}, {1.0, '#FF407B'} } },
            forced_height = 5,
            background_color = '#2C2F5D',
            widget        = wibox.widget.progressbar,
        }

        local cpu_bar_layout = wibox.widget {
            progress_label,
            {
                progress_widget,
                bg = beautiful.bg_normal,
                widget = wibox.container.background
            },
            layout = wibox.layout.ratio.horizontal
        }
        cpu_bar_layout:set_ratio(1, 0.25)
        cpu_bar_layout:set_ratio(2, 0.75)

        cpu_bar_components['label'] = progress_label
        cpu_bar_components['bar'] = progress_widget
        cpu_bar_components['layout'] = cpu_bar_layout

        return cpu_bar_layout, cpu_bar_components
    end

    self.cpu_graph_widget['cpus'] = wibox.widget {
        homogeneous = true,
        expand = true,
        spacing = 5,
        min_cols_size = 10,
        min_rows_size = 10,
        layout = wibox.layout.grid
    }
    -- 1..13
    for i = 1, self.cpu_info['num_cpu'] do
        local row = (i+1) // 2
        local col = ((i+1) %  2) + 1

        local cpu_bar, cpu_bar_components = create_cpu_bar()
        self.cpu_graph_widget['cpu_bar' .. i] = cpu_bar_components
        self.cpu_graph_widget['cpus']:add_widget_at(cpu_bar, row, col, 1, 1)
    end

    -- Total Cpu
    self.cpu_graph_widget['graph'] = wibox.widget {
        max_value = self.graph_max + self.graph_max*self.graph_padding,
        background_color = beautiful.bg_focus,
        forced_height = 50,
        step_width = 2,
        step_spacing = 1.5,
        color = beautiful.graph,
        widget = wibox.widget.graph
    }

    self.cpu_graph_widget['subtext'] = wibox.widget {
        align = 'left',
        font = beautiful.font_small,
        widget = wibox.widget.textbox
    }

    return wibox.widget {
        {
            {
                -- Mirrored so graph starts on right
                self.cpu_graph_widget['graph'],
                reflection = { horizontal = true },
                widget = wibox.container.mirror
            },
            bg = beautiful.bg_focus,
            widget = wibox.container.background
        },
        {
            self.cpu_graph_widget['subtext'],
            top = 5,
            widget = wibox.container.margin
        },
        {
            self.cpu_graph_widget['cpus'],
            top = 5,
            widget = wibox.container.margin
        },
        layout = wibox.layout.fixed.vertical
    }
end

function cpu_widget:create_widget_process_subsection()
    -- PID Name %CPU (Ordered from highest to lowest)
    local function create_process_row(pid, name, cpu)
        local pid_container = wibox.widget {
            markup = pid,
            align = 'right',
            font = beautiful.font_small,
            widget = wibox.widget.textbox
        }
        local name_container = wibox.widget {
            markup = name,
            align = 'left',
            font = beautiful.font_small,
            widget = wibox.widget.textbox
        }
        local cpu_container = wibox.widget {
            markup = cpu,
            align = 'right',
            font = beautiful.font_small,
            widget = wibox.widget.textbox
        }

        local process_row_container = wibox.widget {
            {
                pid_container,
                right = 10,
                widget = wibox.container.margin
            },
            name_container,
            cpu_container,
            layout  = wibox.layout.ratio.horizontal
        }
        process_row_container:ajust_ratio(2, 0.2, 0.47, 0.33)

        local process_row_widgets = {}
        process_row_widgets['pid'] = pid_container
        process_row_widgets['name'] = name_container
        process_row_widgets['cpu'] = cpu_container

        return process_row_container, process_row_widgets
    end

    local process_layout = wibox.widget {
        layout = wibox.layout.fixed.vertical
    }

    local header_container, header_row_widgets = create_process_row("<b>PID</b>", "<b>Name</b>", "<b>CPU%</b>")
    process_layout:add(header_container)

    for i = 1, self.num_processes do
        local process_row_container, process_row_widgets = create_process_row()
        table.insert(self.cpu_processes_widget, process_row_widgets)
        process_layout:add(process_row_container)
    end

    return process_layout

end

function cpu_widget:update_widget(widget, stdout, stderr)
    local parse_cpu_mhz = false
    local cpu_num = 1
    local process_num = 1

    local cpu_mhz = nil

    for line in stdout:gmatch("[^\r\n]+") do
        if parse_cpu_mhz == false then
            cpu_mhz = tonumber(line)
            parse_cpu_mhz = true
        elseif starts_with(line, 'cpu') then

            if self.cpu_usage[cpu_num] == nil then self.cpu_usage[cpu_num] = {} end

            local name, user, nice, system, idle, iowait, irq, softirq, steal, guest, guest_nice =
                line:match('(%w+)%s+(%d+)%s(%d+)%s(%d+)%s(%d+)%s(%d+)%s(%d+)%s(%d+)%s(%d+)%s(%d+)%s(%d+)')

            -- Calculate Usage
            local total = user + nice + system + idle + iowait + irq + softirq + steal

            local diff_idle = idle - tonumber(self.cpu_usage[cpu_num]['idle_prev'] == nil and 0 or self.cpu_usage[cpu_num]['idle_prev'])
            local diff_total = total - tonumber(self.cpu_usage[cpu_num]['total_prev'] == nil and 0 or self.cpu_usage[cpu_num]['total_prev'])
            local diff_usage = (1000 * (diff_total - diff_idle) / diff_total + 5) / 10

            self.cpu_usage[cpu_num]['total_prev'] = total
            self.cpu_usage[cpu_num]['idle_prev'] = idle

            -- Update Graph
            if cpu_num == 1 then
                -- show_warning(diff_usage)
                self.cpu_graph_widget['graph']:add_value(diff_usage + self.graph_max*self.graph_padding)
                self.cpu_graph_widget['subtext'].markup =
                    'Clock Speed:\t' .. cpu_mhz .. ' MHz\n' ..
                    'Usage:\t\t' .. math.floor(diff_usage*1000+0.5)/1000 .. '%'
            else
                self.cpu_graph_widget['cpu_bar' .. cpu_num-1]['label'].markup = 'CPU' .. cpu_num-1
                self.cpu_graph_widget['cpu_bar' .. cpu_num-1]['bar'].value = diff_usage
            end

            -- Update Display Widgets
            self.widget_displays[cpu_num].value = diff_usage

            cpu_num = cpu_num + 1
        else
            local columns = split(line, '|')

            local pid = columns[1]
            local name = columns[2]
            local cpu = columns[3]

            self.cpu_processes_widget[process_num]['pid'].markup = pid
            self.cpu_processes_widget[process_num]['name'].markup = name
            self.cpu_processes_widget[process_num]['cpu'].markup = cpu

            process_num = process_num + 1
        end
    end
end

return cpu_widget
