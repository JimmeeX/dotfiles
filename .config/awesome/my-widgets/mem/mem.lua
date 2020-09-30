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

------------------------------------------
-- MEM widget
------------------------------------------

local mem_widget = class()

function mem_widget:init(args)

    -- self.cpu_info = {}
    -- self.cpu_usage = {}
    self.mem_labels = { "MEM", "SWAP" }
    self.num_processes = 10 -- Top N processes by Memory

    self.update_rate = 1 -- every N seconds
    self.graph_max = 1
    self.graph_padding = 0.01

    -- Widget References
    self.widget_display_bar = nil   -- Reference to Progress Bars
    self.mem_info_widget = {}       -- Reference to popup memory info
    self.mem_graph_widget = {}      -- Reference to popup graph
    self.mem_processes_widget = {}  -- Reference to popup processes

    self:create_widget_popup(args)
    self:create_widget_display(args)

    awful.widget.watch([[bash -c "free -m --si | tail -n +2; ps -eo '%p|%c|' -o "%mem" --sort=-%mem | head -11 | tail -n +2"]], self.update_rate, function (widget, stdout, stderr) self:update_widget(widget, stdout, stderr) end, self.widget)
end

function mem_widget:create_widget_popup(args)
    -- Memory
        -- Primary (Horizontal Stacked Progress) w/ Used | Buff/Cache | Free (Note Avail = Free + Buff/Cache)
        -- Swap    (Horizontal Progress)
    -- Graph
        -- Available / Total %
    -- Processes (Top 10) sorted by memory
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
                create_popupsection('MEMORY', self:create_widget_mem_subsection()),
                create_popupsection('GRAPH', self:create_widget_graph_subsection()),
                create_popupsection('PROCESSES', self:create_widget_process_subsection()),
                layout = wibox.layout.fixed.vertical
            },
            bg = beautiful.bg_normal,
            widget = wibox.container.background,
        }
    }
end

function mem_widget:create_widget_display(args)
    -- Memory

    -- Display Widget (Used/Total)
    self.widget_display_bar = wibox.widget {
        max_value     = 1,
        color         = beautiful.progress_vertbar,
        background_color = beautiful.bg_focus,
        widget        = wibox.widget.progressbar,
    }

    self.widget_bg = wibox.widget {
        {
            {
                {
                    markup = 'MEM',
                    font = beautiful.font_msmall,
                    widget = wibox.widget.textbox
                },
                direction     = 'east',
                layout        = wibox.container.rotate
            },
            {
                self.widget_display_bar,
                forced_width  = 10,
                direction     = 'east',
                layout        = wibox.container.rotate
            },
            layout = wibox.layout.fixed.horizontal
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

function mem_widget:create_widget_mem_subsection()
    -- Primary (Horizontal Stacked Progress) w/ Used | Buff/Cache | Free (Note Avail = Free + Buff/Cache)
    local function create_widget_membar(name_info, value, perc_info)
        local mem_info_widget = wibox.widget {
            markup = name_info,
            font = beautiful.font_small,
            widget = wibox.widget.textbox
        }

        local stacked_free_widget, stacked_free_text = create_coloured_container(beautiful.bg_focus, 'Free')
        local stacked_cache_widget, stacked_cache_text = create_coloured_container(beautiful.fg_normal, 'Buff/Cache')
        local stacked_used_widget, stacked_used_text = create_coloured_container('#FF407B', 'Used')

        local mem_bar_text = {}
        mem_bar_text['free'] = stacked_free_text
        mem_bar_text['cache'] = stacked_cache_text
        mem_bar_text['used'] = stacked_used_text

        local mem_bar_widget = wibox.widget {
            stacked_used_widget,           -- Used
            stacked_cache_widget, -- Buff/Cache
            stacked_free_widget,  -- Free
            -- forced_height = 10,
            -- forced_width = 75,
            layout = wibox.layout.ratio.horizontal
        }

        local mem_perc_widget = wibox.widget {
            markup = perc_info,
            align = 'right',
            font = beautiful.font_small,
            widget = wibox.widget.textbox
        }

        local mem_row_layout = wibox.widget {
            homogeneous   = true,
            expand        = true,
            min_cols_size = 10,
            min_rows_size = 10,
            layout        = wibox.layout.grid,
        }

        mem_row_layout:add_widget_at(mem_info_widget, 1, 1, 1, 1)
        mem_row_layout:add_widget_at(mem_bar_widget, 1, 2, 1, 5)
        mem_row_layout:add_widget_at(mem_perc_widget, 2, 2, 1, 5)

        return wibox.widget {
            mem_row_layout,
            bottom = 10,
            widget = wibox.container.margin,
        }, mem_bar_widget, mem_perc_widget, mem_bar_text
    end

    local mem_info_widgets = wibox.widget {
        layout = wibox.layout.fixed.vertical
    }

    for i, mem_name in pairs(self.mem_labels) do
        local mem_row_widget, mem_bar_widget, mem_perc_widget, mem_bar_text = create_widget_membar(mem_name)

        self.mem_info_widget[mem_name] = {}
        self.mem_info_widget[mem_name]['bar'] = mem_bar_widget
        self.mem_info_widget[mem_name]['perc'] = mem_perc_widget
        self.mem_info_widget[mem_name]['bar_text'] = mem_bar_text

        mem_info_widgets:add(mem_row_widget)
    end

    return mem_info_widgets
end

function mem_widget:create_widget_graph_subsection()
    -- Total MEM
    self.mem_graph_widget['graph'] = wibox.widget {
        max_value = self.graph_max + self.graph_max*self.graph_padding,
        background_color = beautiful.bg_focus,
        forced_height = 50,
        step_width = 2,
        step_spacing = 1.5,
        color = beautiful.graph,
        widget = wibox.widget.graph
    }

    self.mem_graph_widget['subtext'] = wibox.widget {
        align = 'left',
        font = beautiful.font_small,
        widget = wibox.widget.textbox
    }

    return wibox.widget {
        {
            {
                -- Mirrored so graph starts on right
                self.mem_graph_widget['graph'],
                reflection = { horizontal = true },
                widget = wibox.container.mirror
            },
            bg = beautiful.bg_focus,
            widget = wibox.container.background
        },
        {
            self.mem_graph_widget['subtext'],
            top = 5,
            widget = wibox.container.margin
        },
        layout = wibox.layout.fixed.vertical
    }
end

function mem_widget:create_widget_process_subsection()
    -- PID Name %CPU (Ordered from highest to lowest)
    local function create_process_row(pid, name, mem)
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
        local mem_container = wibox.widget {
            markup = mem,
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
            mem_container,
            layout  = wibox.layout.ratio.horizontal
        }
        process_row_container:ajust_ratio(2, 0.2, 0.47, 0.33)

        local process_row_widgets = {}
        process_row_widgets['pid'] = pid_container
        process_row_widgets['name'] = name_container
        process_row_widgets['mem'] = mem_container

        return process_row_container, process_row_widgets
    end

    local process_layout = wibox.widget {
        layout = wibox.layout.fixed.vertical
    }

    local header_container, header_row_widgets = create_process_row("<b>PID</b>", "<b>Name</b>", "<b>MEM%</b>")
    process_layout:add(header_container)

    for i = 1, self.num_processes do
        local process_row_container, process_row_widgets = create_process_row()
        table.insert(self.mem_processes_widget, process_row_widgets)
        process_layout:add(process_row_container)
    end

    return process_layout

end

function mem_widget:update_widget(widget, stdout, stderr)
    local mem_num = 1
    local process_num = 1

    for line in stdout:gmatch("[^\r\n]+") do
        if mem_num <= 2 then
            -- Parse Free Command
            if mem_num == 1 then
                -- Parse Mem
                local name, total, used, free, shared, buff_cache, available =
                    line:match('(%w+):%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)')

                -- Calculate Ratio Used | Buff/Cache | Free
                local used_perc = tonumber(used) / tonumber(total)
                local buff_cache_perc = tonumber(buff_cache) / tonumber(total)
                local free_perc = 1 - used_perc - buff_cache_perc

                -- Update Mem Info (1st Section)
                self.widget_display_bar.value = used_perc

                self.mem_info_widget[self.mem_labels[mem_num]]['bar']:set_ratio(1, used_perc)
                self.mem_info_widget[self.mem_labels[mem_num]]['bar']:set_ratio(2, buff_cache_perc)
                self.mem_info_widget[self.mem_labels[mem_num]]['bar']:set_ratio(3, free_perc)

                self.mem_info_widget[self.mem_labels[mem_num]]['bar_text']['free'].markup = 'Free [' .. math.floor(free_perc*100+0.5) .. '%]'
                self.mem_info_widget[self.mem_labels[mem_num]]['bar_text']['cache'].markup = 'Buff/Cache [' .. math.floor(buff_cache_perc*100+0.5) .. '%]'
                self.mem_info_widget[self.mem_labels[mem_num]]['bar_text']['used'].markup = 'Used [' .. math.floor(used_perc*100+0.5) .. '%]'

                self.mem_info_widget[self.mem_labels[mem_num]]['perc'].markup =
                    '(' .. used .. ' + ' .. buff_cache .. ')M / ' .. total .. 'M [' .. math.floor((used_perc+buff_cache_perc)*100+0.5) .. '%]'

                -- Update Graph
                self.mem_graph_widget['graph']:add_value(used_perc + self.graph_max*self.graph_padding)
                self.mem_graph_widget['subtext'].markup = 'Used: ' .. used .. 'M / ' .. total .. 'M [' .. math.floor(used_perc*100+0.5) .. '%]'
            else
                -- Parse Swap
                local name, total, used, free =
                    line:match('(%w+):%s+(%d+)%s+(%d+)%s+(%d+)')
                local used_perc = tonumber(used) / tonumber(total)
                local buff_cache_perc = 0
                local free_perc = 1 - used_perc

                self.mem_info_widget[self.mem_labels[mem_num]]['bar']:set_ratio(1, used_perc)
                self.mem_info_widget[self.mem_labels[mem_num]]['bar']:set_ratio(2, buff_cache_perc)
                self.mem_info_widget[self.mem_labels[mem_num]]['bar']:set_ratio(3, free_perc)
                self.mem_info_widget[self.mem_labels[mem_num]]['bar_text']['free'].markup = 'Free [' .. math.floor(free_perc*100+0.5) .. '%]'
                self.mem_info_widget[self.mem_labels[mem_num]]['bar_text']['cache'].markup = 'Buff/Cache [' .. math.floor(buff_cache_perc*100+0.5) .. '%]'
                self.mem_info_widget[self.mem_labels[mem_num]]['bar_text']['used'].markup = 'Used [' .. math.floor(used_perc*100+0.5) .. '%]'
                self.mem_info_widget[self.mem_labels[mem_num]]['perc'].markup =
                    used .. 'M / ' .. total .. 'M [' .. math.floor(used_perc*100+0.5) .. '%]'
            end

            mem_num = mem_num + 1
        else
            local columns = split(line, '|')

            local pid = columns[1]
            local name = columns[2]
            local mem = columns[3]

            self.mem_processes_widget[process_num]['pid'].markup = pid
            self.mem_processes_widget[process_num]['name'].markup = name
            self.mem_processes_widget[process_num]['mem'].markup = mem

            process_num = process_num + 1
        end
    end
    -- show_warning("END")
end

return mem_widget
