local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")

------------------------------------------
-- Private utility functions
------------------------------------------

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

------------------------------------------
-- Storage widget
------------------------------------------

local storage_widget = class()

function storage_widget:init(args)
    -- storage_widget.init(self, args)
    -- args
    -- self.primary = '/dev/sda3'
    self.drives = {'sda', 'sdb'}
    self.drive_disks = {
        sda = { '/dev/sda3' },
        sdb = { '/dev/sdb1' }
    }
    self.root_disk = '/dev/sda3'


    self.disk_keys = {'/dev/sda3', '/dev/sdb1'} -- Assume First Disk is primary (root)
    self.disk_info = {}
    -- self.root_partition = '/dev/sda3'

    self.lclick = args.lclick or "toggle"

    -- self.font = args.font        or nil
    self.popup_info_widget = {}
    self:create_widget(args)

    awful.widget.watch([[bash -c "df -hT | tail -n +2"]], 200, function (widget, stdout, stderr) self:update_widget(widget, stdout, stderr) end, self.widget)
end

function storage_widget:create_widget(args)
    -- Display Widget
    self.primary_progress = wibox.widget {
        max_value     = 100,
        -- value         = 8,
        color         = beautiful.progress_vertbar,
        background_color = '#2C2F5D',
        widget        = wibox.widget.progressbar,
    }

    self.widget_bg = wibox.widget {
        {
            {
                {
                    markup = 'SSD',
                    font = beautiful.font_msmall,
                    widget = wibox.widget.textbox
                },
                direction     = 'east',
                layout        = wibox.container.rotate
            },
            {
                self.primary_progress,
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

    -- Popup Widget
    self:create_storagesection()

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
                self:create_popupsection('STORAGE', self:create_storagesection()),
                layout = wibox.layout.fixed.vertical
            },
            bg = beautiful.bg_normal,
            widget = wibox.container.background,
        }
    }

    self.widget:connect_signal("mouse::enter", function(c)
        self.widget_popup:move_next_to(mouse.current_widget_geometry)
        self.widget_popup.visible = true
    end)
    self.widget:connect_signal("mouse::leave", function(c) self.widget_popup.visible = false end)
end

function storage_widget:create_popupsection(section_title, section_content)
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

function storage_widget:create_storagesection()
    local storage_info_widget = wibox.widget {
        layout = wibox.layout.fixed.vertical
    }

    for i, drive in pairs(self.drives) do
        -- Create ProgressBar
        -- Details
        local model = os.capture(string.format("cat /sys/class/block/%s/device/model", drive))

        -- Initialise Drive
        local drive_header_widget = wibox.widget {
            {
                markup = '<b>' .. drive ..'</b> [' .. model .. ']',
                font = beautiful.font_small,
                align = 'center',
                widget = wibox.widget.textbox
            },
            top = 1,
            bottom = 1,
            color = beautiful.fg_normal,
            widget = wibox.container.margin
        }
        storage_info_widget:add(drive_header_widget)

        local partitions_widget = wibox.widget {
            layout = wibox.layout.fixed.vertical
        }

        for j, partition in pairs(self.drive_disks[drive]) do
            local partition_info = partition
            if partition_info == self.root_disk then
                partition_info = partition_info .. ' [Root]'
            end

            local partition_widget, partition_bar_widget, partition_perc_widget = self:create_drivebarwidget(partition_info)

            self.popup_info_widget[partition] = {}
            self.popup_info_widget[partition]['bar'] = partition_bar_widget
            self.popup_info_widget[partition]['perc'] = partition_perc_widget


            partitions_widget:add(wibox.widget {
                partition_widget,
                -- left = 25,
                -- right = 5,
                widget = wibox.container.margin
            })

        end

        storage_info_widget:add(partitions_widget)

    end

    return storage_info_widget
end

function storage_widget:create_drivebarwidget(name_info, value, perc_info)
    local partition_info_widget = wibox.widget {
        markup = name_info,
        font = beautiful.font_small,
        widget = wibox.widget.textbox
    }

    local partition_bar_widget = wibox.widget {
        max_value     = 100,
        value         = value,
        forced_height = 5,
        forced_width  = 45,
        color         = beautiful.fg_normal,
        background_color = '#2C2F5D',
        widget = wibox.widget.progressbar
    }

    local partition_perc_widget = wibox.widget {
        markup = perc_info,
        align = 'right',
        font = beautiful.font_small,
        widget = wibox.widget.textbox
    }

    return wibox.widget {
        {
            partition_info_widget,
            {
                partition_bar_widget,
                margins = 3,
                widget = wibox.container.margin
            },
            { markup = '', widget = wibox.widget.textbox },
            partition_perc_widget,
            forced_num_cols = 2,
            forced_num_rows = 2,
            homogeneous = true,
            expand = true,
            layout = wibox.layout.grid
        },
        top    = 5,
        bottom = 10,
        widget = wibox.container.margin,
    }, partition_bar_widget, partition_perc_widget
end

function storage_widget:update_widget(widget, stdout, stderr)
    for line in stdout:gmatch("[^\r\n$]+") do
        local filesystem, format, size, used, avail, used_perc, mount = line:match('([%p%w]+)%s+([%w]+)%s+([%.%w]+)%s+([%.%w]+)%s+([%.%w]+)%s+([%d]+)%%%s+([%p%w]+)')

        self.disk_info[filesystem] = {}
        self.disk_info[filesystem].format = format
        self.disk_info[filesystem].size = size
        self.disk_info[filesystem].used = used
        self.disk_info[filesystem].avail = avail
        self.disk_info[filesystem].used_perc = used_perc
        self.disk_info[filesystem].mount = mount

        if self.popup_info_widget[filesystem] ~= nil then
            self.popup_info_widget[filesystem]['bar'].value = tonumber(used_perc)
            self.popup_info_widget[filesystem]['perc'].markup = used .. '/' .. size .. '[' .. used_perc ..'%]'
        end



    end

    self.primary_progress.value = tonumber(self.disk_info[self.disk_keys[1]].used_perc)
end

return storage_widget
