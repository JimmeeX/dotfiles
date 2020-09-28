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

local function spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys 
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
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

local function create_coloured_container(colour, text)
    local textbox_widget = wibox.widget {
        text = text,
        font = beautiful.font_vsmall,
        align = 'center',
        widget = wibox.widget.textbox
    }

    return wibox.widget {
        textbox_widget,
        bg = colour,
        fg = '#ffffff',
        -- forced_width = 10,
        widget = wibox.container.background
    }, textbox_widget
end

local function trim(s)
    -- from PiL2 20.4
    return (s:gsub("^%s*(.-)%s*$", "%1"))
  end

------------------------------------------
-- GPU widget
------------------------------------------

local gpu_widget = class()

function gpu_widget:init(args)
    self.num_processes = 10 -- Top N processes by Memory

    self.update_rate = 1 -- every N seconds
    self.graph_max = 1
    self.graph_padding = 0.01

    -- Widget References
    self.widget_display_bar = nil   -- Reference to Progress Bars
    self.gpu_info_widget = nil      -- Reference to popup memory info
    self.gpu_graph_widget = {}      -- Reference to popup graph
    self.gpu_processes_widget = {}  -- Reference to popup processes

    self:create_widget_popup(args)
    self:create_widget_display(args)
    -- nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu,utilization.memory,memory.total,memory.free,memory.used --format=csv,noheader
    awful.widget.watch([[bash -c "nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu,utilization.memory,memory.total,memory.free,memory.used --format=csv,noheader,nounits; nvidia-smi pmon -c 1 -s m | tail -n +3"]], self.update_rate, function (widget, stdout, stderr) self:update_widget(widget, stdout, stderr) end, self.widget)
end

function gpu_widget:create_widget_popup(args)
    -- GPU
    -- Utilisation + Memory Graph
    -- Processes (Top 10) sorted by GPU Memory Usage

    self.widget_popup = awful.popup{
        ontop = true,
        visible = false,
        shape = gears.shape.rounded_rect,
        border_color = beautiful.bg_normal,
        minimum_width = 350,
        maximum_width = 350,
        offset = { y = 5 },
        widget = {
            {
                create_popupsection('GPU', self:create_widget_gpu_subsection()),
                create_popupsection('GRAPH', self:create_widget_graph_subsection()),
                create_popupsection('PROCESSES', self:create_widget_process_subsection()),
                layout = wibox.layout.fixed.vertical
            },
            bg = beautiful.bg_normal,
            widget = wibox.container.background,
        }
    }
end

function gpu_widget:create_widget_display(args)
    -- GPU Utilisation (%)

    -- Display Widget
    self.widget_display_bar = wibox.widget {
        max_value     = 1,
        color         = beautiful.progress_vertbar,
        background_color = beautiful.bg_focus,
        widget        = wibox.widget.progressbar,
    }

    self.widget_bg = wibox.widget {
        {
            self.widget_display_bar,
            forced_width  = 10,
            direction     = 'east',
            layout        = wibox.container.rotate
        },
        bg = beautiful.bg_normal,
        widget = wibox.container.background
    }

    self.widget = wibox.widget {
        self.widget_bg,
        margins = 5,
        widget = wibox.container.margin
    }

    self.widget:connect_signal("mouse::enter", function(c)
        self.widget_popup:move_next_to(mouse.current_widget_geometry)
        self.widget_popup.visible = true
    end)
    self.widget:connect_signal("mouse::leave", function(c) self.widget_popup.visible = false end)
end

function gpu_widget:create_widget_gpu_subsection()
    -- GPU Details
        -- Name
        -- Driver Version
        -- CUDA Version?
        -- temperature.gpu

    self.gpu_info_widget = wibox.widget {
        font = beautiful.font_small,
        widget = wibox.widget.textbox
    }

    return self.gpu_info_widget
end

function gpu_widget:create_widget_graph_subsection()
    -- Top -> GPU Utilisation
    -- Bottom -> Memory

    self.gpu_graph_widget['util'] = wibox.widget {
        max_value = self.graph_max + self.graph_max*self.graph_padding,
        background_color = beautiful.bg_focus,
        forced_height = 50,
        step_width = 2,
        step_spacing = 1.5,
        color = '#FF16B0',
        widget = wibox.widget.graph
    }

    self.gpu_graph_widget['mem'] = wibox.widget {
        max_value = self.graph_max + self.graph_max*self.graph_padding,
        background_color = beautiful.bg_focus,
        -- forced_width = 100,
        forced_height = 50,
        step_width = 2,
        step_spacing = 1.5,
        color = '#46BDFF',
        widget = wibox.widget.graph
    }

    self.gpu_graph_widget['subtext'] = wibox.widget {
        align = 'left',
        font = beautiful.font_small,
        widget = wibox.widget.textbox
    }

    local gpu_graph_layout = wibox.widget {
        {
            {
                {
                    -- Mirrored so graph starts on right
                    self.gpu_graph_widget['util'],
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
                    self.gpu_graph_widget['mem'],
                    direction = 'south',
                    widget = wibox.container.rotate
                },
                top = 1,
                -- bottom = 10,
                widget = wibox.container.margin
            },
            layout = wibox.layout.fixed.vertical
        },
        bg = beautiful.bg_focus,
        widget = wibox.container.background
    }

    return wibox.widget {
        gpu_graph_layout,
        {
            self.gpu_graph_widget['subtext'],
            top = 5,
            widget = wibox.container.margin
        },
        layout = wibox.layout.fixed.vertical
    }

    -- return gpu_graph_layout
end

function gpu_widget:create_widget_process_subsection()
    -- PID Name %CPU (Ordered from highest to lowest)
    local function create_process_row(pid, name, gpu_mem)
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
        local gpu_mem_container = wibox.widget {
            markup = gpu_mem,
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
            gpu_mem_container,
            layout  = wibox.layout.ratio.horizontal
        }
        process_row_container:ajust_ratio(2, 0.2, 0.47, 0.33)

        local process_row_widgets = {}
        process_row_widgets['pid'] = pid_container
        process_row_widgets['name'] = name_container
        process_row_widgets['gpu_mem'] = gpu_mem_container

        return process_row_container, process_row_widgets
    end

    local process_layout = wibox.widget {
        layout = wibox.layout.fixed.vertical
    }

    local header_container, header_row_widgets = create_process_row("<b>PID</b>", "<b>Name</b>", "<b>GPU MEM%</b>")
    process_layout:add(header_container)

    for i = 1, self.num_processes do
        local process_row_container, process_row_widgets = create_process_row()
        table.insert(self.gpu_processes_widget, process_row_widgets)
        process_layout:add(process_row_container)
    end

    return process_layout

end

function gpu_widget:update_widget(widget, stdout, stderr)
    local i = 1

    local mem_total = nil
    local gpu_processes = {}
    local process_num = 1

    for line in stdout:gmatch("[^\r\n]+") do
        if i == 1 then
            -- Parse GPU Details
            -- nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu,utilization.memory,memory.total,memory.free,memory.used --format=csv,noheader
            local vals = split(line, ',')

            local model = trim(vals[1])
            local driver_version = trim(vals[2])
            local temp = tonumber(trim(vals[3]))      -- Celsius
            local gpu_util = tonumber(trim(vals[4]))  -- %
            local mem_util = tonumber(trim(vals[5]))  -- %
            mem_total = tonumber(trim(vals[6])) -- MiB
            local mem_free = tonumber(trim(vals[7]))  -- MiB
            local mem_used = tonumber(trim(vals[8]))  -- MiB

            local mem_used_perc = mem_used / mem_total

            -- Update Display Widget
            self.widget_display_bar.value = mem_used_perc

            -- Update GPU Info Section
            self.gpu_info_widget.markup =
                "Model:\t\t\t" .. model .. '\n' ..
                "Driver Version:\t\t" .. driver_version .. '\n' ..
                "Temperature:\t\t" .. temp .. '\n'

            -- Update Graph
            self.gpu_graph_widget['util']:add_value(gpu_util/100 + self.graph_max*self.graph_padding)
            self.gpu_graph_widget['mem']:add_value(mem_used_perc + self.graph_max*self.graph_padding)
            self.gpu_graph_widget['subtext'].markup =
                'GPU Utilisation:\t' .. gpu_util .. '%\n' ..
                'Memeory Used:\t\t' .. mem_used .. 'MiB / ' .. mem_total .. 'MiB'
        else
            -- Handle Processes
            local gpu_id, pid, cg_type, fb, command =
                line:match('%s*(%d+)%s+(%d+)%s+(%w+)%s+(%d+)%s+(%w+)%s*')

            gpu_processes[process_num] = {
                gpu_id  = tonumber(gpu_id),
                pid     = tonumber(pid),
                cg_type = cg_type,
                fb      = tonumber(fb),
                command = command
            }

            process_num = process_num + 1

        end
        i = i + 1
    end

    -- Update GPU Process Section via Top N Sorted Descending
    i = 1
    for k, v in spairs(gpu_processes, function(t,a,b) return t[b]['fb'] < t[a]['fb'] end) do
        if i > self.num_processes then break end
        self.gpu_processes_widget[i]['pid'].markup      = v['pid']
        self.gpu_processes_widget[i]['name'].markup     = v['command']
        self.gpu_processes_widget[i]['gpu_mem'].markup  = math.floor((v['fb'] / mem_total) * 1000 + 0.5) / 10
        i = i + 1
    end
end

return gpu_widget
