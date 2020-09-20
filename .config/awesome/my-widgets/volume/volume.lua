-- -------------------------------------------------
-- -- Volume Arc Widget for Awesome Window Manager
-- -- Shows the current volume level
-- -- More details could be found here:
-- -- https://github.com/streetturtle/awesome-wm-widgets/tree/master/volumearc-widget

-- -- @author Pavel Makhov
-- -- @copyright 2018 Pavel Makhov
-- -------------------------------------------------

-- local awful = require("awful")
-- local beautiful = require("beautiful")
-- local spawn = require("awful.spawn")
-- local watch = require("awful.widget.watch")
-- local wibox = require("wibox")

-- local GET_VOLUME_CMD = '/usr/bin/amixer get Master'
-- local INC_VOLUME_CMD = '/usr/bin/amixer set Master 5%+'
-- local DEC_VOLUME_CMD = '/usr/bin/amixer set Master 5%-'
-- local TOG_VOLUME_CMD = '/usr/bin/amixer set Master toggle'

-- local widget = {}

-- local function worker(args)

--     local args = args or {}

--     local main_color = args.main_color or beautiful.fg_color
--     local bg_color = args.bg_color or '#ffffff11'
--     local mute_color = args.mute_color or beautiful.fg_urgent
--     local path_to_icon = args.path_to_icon or ICON_VOLUME
--     local thickness = args.thickness or 2
--     local height = args.height or 18

--     local get_volume_cmd = args.get_volume_cmd or GET_VOLUME_CMD
--     local inc_volume_cmd = args.inc_volume_cmd or INC_VOLUME_CMD
--     local dec_volume_cmd = args.dec_volume_cmd or DEC_VOLUME_CMD
--     local tog_volume_cmd = args.tog_volume_cmd or TOG_VOLUME_CMD

--     local icon = {
--         id = "icon",
--         image = path_to_icon,
--         resize = true,
--         widget = wibox.widget.imagebox,
--     }

--     local volumearc = wibox.widget {
--         icon,
--         max_value = 1,
--         thickness = thickness,
--         start_angle = 4.71238898, -- 2pi*3/4
--         forced_height = height,
--         forced_width = height,
--         bg = bg_color,
--         paddings = 2,
--         widget = wibox.container.arcchart
--     }

--     local update_graphic = function(widget, stdout, _, _, _)
--         local mute = string.match(stdout, "%[(o%D%D?)%]")   -- \[(o\D\D?)\] - [on] or [off]
--         local volume = string.match(stdout, "(%d?%d?%d)%%") -- (\d?\d?\d)\%)
--         volume = tonumber(string.format("% 3d", volume))

--         widget.value = volume / 100;
--         widget.colors = mute == 'off'
--                 and { mute_color }
--                 or { main_color }
--     end

--     local button_press = args.button_press or  function(_, _, _, button)
--         if (button == 4) then awful.spawn(inc_volume_cmd, false)
--         elseif (button == 5) then awful.spawn(dec_volume_cmd, false)
--         elseif (button == 1) then awful.spawn(tog_volume_cmd, false)
--         end

--         spawn.easy_async(get_volume_cmd, function(stdout, stderr, exitreason, exitcode)
--             update_graphic(volumearc, stdout, stderr, exitreason, exitcode)
--         end)
--     end
--     volumearc:connect_signal("button::press", button_press)

--     watch(get_volume_cmd, 1, update_graphic, volumearc)

--     return volumearc
-- end

-- return setmetatable(widget, { __call = function(_, ...) return worker(...) end })

-- Volume Control
local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")

-- compatibility fallbacks for 3.5:
local timer = gears.timer or timer
local spawn = awful.spawn or awful.util.spawn
local watch = awful.spawn and awful.spawn.with_line_callback

local PATH_TO_ICONS = os.getenv("HOME") .. "/.config/awesome/my-widgets/volume/icons/"
local ICON_VOLUME = PATH_TO_ICONS .. "volume.png"
local ICON_VOLUME_MUTE = PATH_TO_ICONS .. "volume-mute.png"
local ICON_VOLUME_ZERO = PATH_TO_ICONS .. "volume-zero.png"

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

------------------------------------------
-- Volume control interface
------------------------------------------

local vcontrol = class()

function vcontrol:init(args)
    self.callbacks = {}
    self.cmd = "amixer"
    self.device = args.device or nil
    self.cardid  = args.cardid or nil
    self.channel = args.channel or "Master"
    self.step = args.step or '5%'

    self.timer = timer({ timeout = args.timeout or 0.5 })
    self.timer:connect_signal("timeout", function() self:get() end)
    self.timer:start()

    if args.listen and watch then
        self.listener = watch({'stdbuf', '-oL', 'alsactl', 'monitor'}, {
          stdout = function(line) self:get() end,
        })
        awesome.connect_signal("exit", function()
            awesome.kill(self.listener, awesome.unix_signal.SIGTERM)
        end)
    end
end

function vcontrol:register(callback)
    if callback then
        table.insert(self.callbacks, callback)
    end
end

function vcontrol:action(action)
    if self[action]                   then self[action](self)
    elseif type(action) == "function" then action(self)
    elseif type(action) == "string"   then spawn(action)
    end
end

function vcontrol:update(status)
    local volume = status:match("(%d?%d?%d)%%")
    local state  = status:match("%[(o[nf]*)%]")
    if volume and state then
        local volume = tonumber(volume)
        local state = state:lower()
        local muted = state == "off"
        for _, callback in ipairs(self.callbacks) do
            callback(self, {
                volume = volume,
                state = state,
                muted = muted,
                on = not muted,
            })
        end
    end
end

function vcontrol:mixercommand(...)
    local args = awful.util.table.join(
      {self.cmd},
      (self.cmd == "amixer") and {"-M"} or {},
      self.device and {"-D", self.device} or {},
      self.cardid and {"-c", self.cardid} or {},
      {...})
    return readcommand(make_argv(args))
end

function vcontrol:get()
    self:update(self:mixercommand("get", self.channel))
end

function vcontrol:up()
    self:update(self:mixercommand("set", self.channel, self.step .. "+"))
end

function vcontrol:down()
    self:update(self:mixercommand("set", self.channel, self.step .. "-"))
end

function vcontrol:toggle()
    self:update(self:mixercommand("set", self.channel, "toggle"))
end

function vcontrol:mute()
    self:update(self:mixercommand("set", "Master", "mute"))
end

function vcontrol:unmute()
    self:update(self:mixercommand("set", "Master", "unmute"))
end

function vcontrol:list_sinks()
    local sinks = {}
    local sink
    for line in io.popen("env LC_ALL=C pactl list sinks"):lines() do
        if line:match("Sink #%d+") then
            sink = {}
            table.insert(sinks, sink)
        else
            local k, v = line:match("^%s*(%S+):%s*(.-)%s*$")
            if k and v then sink[k:lower()] = v end
        end
    end
    return sinks
end

function vcontrol:set_default_sink(name)
    os.execute(make_argv{"pactl set-default-sink", name})
end

------------------------------------------
-- Volume control widget
------------------------------------------

-- derive so that users can still call up/down/mute etc
local vwidget = class(vcontrol)

function vwidget:init(args)
    vcontrol.init(self, args)

    self.lclick = args.lclick or "toggle"
    self.mclick = args.mclick or "pavucontrol"
    self.rclick = args.rclick or self.show_menu

    self.font = args.font        or nil
    self.widget = args.widget    or (self:create_widget(args)  or self.widget)
    self.tooltip = args.tooltip and (self:create_tooltip(args) or self.tooltip)

    self:register(args.callback or self.update_widget)
    self:register(args.tooltip and self.update_tooltip)

    self.widget:buttons(awful.util.table.join(
        awful.button({}, 1, function() self:action(self.lclick) end),
        -- awful.button({}, 2, function() self:action(self.mclick) end),
        -- awful.button({}, 3, function() self:action(self.rclick) end),
        awful.button({}, 4, function() self:up() end),
        awful.button({}, 5, function() self:down() end)
    ))

    self:get()
end

-- text widget
function vwidget:create_widget(args)
    self.widget = wibox.widget {
        min_value = 0,
        max_value = 100,
        thickness = 2,
        start_angle = 4.71238898, -- 2pi*3/4
        forced_height = 18,
        forced_width = 18,
        bg = beautiful.bg_normal,
        -- colors = {beautiful.border_focus},
        paddings = 2,
        widget = wibox.container.arcchart
    }
end

function vwidget:create_menu()
    local sinks = {}
    for i, sink in ipairs(self:list_sinks()) do
        table.insert(sinks, {sink.description, function()
            self:set_default_sink(sink.name)
        end})
    end
    return awful.menu { items = {
        { "mute", function() self:mute() end },
        { "unmute", function() self:unmute() end },
        { "Default Sink", sinks },
        { "pavucontrol", function() self:action("pavucontrol") end },
    } }
end

function vwidget:show_menu()
    if self.menu then
        self.menu:hide()
    else
        self.menu = self:create_menu()
        self.menu:show()
        self.menu.wibox:connect_signal("property::visible", function()
            self.menu = nil
        end)
    end
end

function vwidget:update_widget(setting)
    self.widget.value = setting.volume

    local new_icon = ''
    if (setting.state == 'on' and setting.volume > 0) then
        new_icon = ICON_VOLUME
    elseif (setting.state == 'on') then -- setting.volume == 0
        new_icon = ICON_VOLUME_ZERO
    else -- setting.state == off
        new_icon = ICON_VOLUME_MUTE
    end

    self.widget.widget = wibox.widget {
        id = "icon",
        image = new_icon,
        resize = true,
        widget = wibox.widget.imagebox,
    }

end

-- tooltip
function vwidget:create_tooltip(args)
    self.tooltip_text = args.tooltip_text or [[
Volume: ${volume}% ${state}
Channel: ${channel}
Device: ${device}
Card: ${card}]]
    self.tooltip = args.tooltip and awful.tooltip({objects={self.widget}})
end

function vwidget:update_tooltip(setting)
    self.tooltip:set_text(substitute(self.tooltip_text, {
        volume  = setting.volume,
        state   = setting.state,
        device  = self.device,
        card    = self.card,
        channel = self.channel,
    }))
end

-- provide direct access to the control class
vwidget.control = vcontrol
return vwidget
