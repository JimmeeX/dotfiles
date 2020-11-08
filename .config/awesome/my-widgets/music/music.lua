local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")

local ICON_DIR = os.getenv("HOME") .. "/.config/awesome/my-widgets/music/icons/"
local IM_PATH = os.getenv("HOME") .. "/.config/awesome/my-widgets/music/images/image.png"
local IM_DEFAULT_PATH = os.getenv("HOME") .. "/.config/awesome/my-widgets/music/images/default.png"

local icon = {}
icon['Chrome']  = ICON_DIR .. "chrome.png"
icon['Firefox'] = ICON_DIR .. "firefox.png"
icon['Spotify'] = ICON_DIR .. "spotify.png"
icon['Youtube Music'] = ICON_DIR .. "youtube.png"
icon['N/A'] = nil

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

local function trim(s)
    if s == nil then return nil
    else return s:gsub("^%s*(.-)%s*$", "%1")
    end
end

local function isempty(s)
    return s == nil or s == ''
end

local function format_title_artist(title, artist)
    if isempty(artist) then
        return '<b>' .. title .. '</b>'
    else
        return '<b>' .. title .. '</b> - <i>' .. artist .. '</i>'
    end
end

local function format_bar_text(duration)
    -- Microseconds
    local seconds_total = duration / 1000000
    -- Get Minutes
    local minutes = string.format("%02.f", seconds_total // 60)
    -- Get Seconds
    local seconds = string.format("%02.f", seconds_total % 60)

    return minutes .. ':' .. seconds
end

local function fix_image_url(source, art_url)
    if source ~= 'Youtube Music' and source ~= 'Spotify' then return nil end

    if source == 'Spotify' then
        -- Fix Url https://i.scdn.co/image/{art-address} instead of https://open.spotify.com/image/{art-address}
        local art_id = art_url:match("^https://open%.spotify%.com/image/(.-)$")
        if isempty(art_id) then return nil end
        art_url = 'https://i.scdn.co/image/' .. art_id
    end

    return art_url
end

local function download_image(url)
    awful.spawn.with_shell('curl "' .. url .. '" > ' .. IM_PATH);
end

local function get_media_source(trackid)
    if isempty(trackid) then return 'N/A'
    elseif string.find(trackid, 'spotify') then return 'Spotify'
    elseif string.find(trackid, 'youtubemusic') then return 'Youtube Music'
    elseif string.find(trackid, 'firefox') then return 'Firefox'
    else return 'N/A'
    end
end

------------------------------------------
-- MUSIC widget
------------------------------------------

local music_widget = class()

function music_widget:init(args)

    self.update_rate = 1 -- every N seconds

    self.prev_art_url = nil
    -- Widget References
    self.widget_display = {}        -- Reference to Progress Bars
    self.widget_popup_info = {}     -- Reference to popup info

    self:create_widget_popup(args)
    self:create_widget_display(args)

    awful.widget.watch([[bash -c "playerctl metadata --player=playerctld --format ' {{mpris:trackid}} ;; {{title}} ;; {{artist}} ;; {{album}} ;; {{mpris:artUrl}} ;; {{position}} ;; {{mpris:length}} ;; {{status}} '"]], self.update_rate, function (widget, stdout, stderr) self:update_widget(widget, stdout, stderr) end, self.widget)
end

function music_widget:create_widget_popup(args)
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
                create_popupsection('MUSIC', self:create_widget_music_subsection()),
                layout = wibox.layout.fixed.vertical
            },
            bg = beautiful.bg_normal,
            widget = wibox.container.background,
        }
    }
end

function music_widget:create_widget_display(args)
    -- Icon - Song Name - Artist

    -- Display Widget
    self.widget_display['icon'] = wibox.widget {
        widget = wibox.widget.imagebox
    }

    -- Text Widget
    self.widget_display['text'] = wibox.widget {
        -- font = beautiful.font_small,
        widget = wibox.widget.textbox
    }

    self.widget = wibox.widget {
        {
            {
                self.widget_display['icon'],
                right = 5,
                widget = wibox.container.margin
            },
            {
                self.widget_display['text'],
                speed = 20,
                extra_space = 50,
                max_size = 200,
                step_function = wibox.container.scroll.step_functions.linear_increase,
                widget = wibox.container.scroll.horizontal,
            },
            layout = wibox.layout.fixed.horizontal
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

function music_widget:create_widget_music_subsection()
    -- Left - Album Art (if not, Default Art)
    -- Right
        -- Source/PlayerName (YoutubeMusic; Spotify, etc)
        -- [Status]
        -- Song Name
        -- Album
        -- Playlist
        -- ProgressBar (Current / TotalLength)

    self.widget_popup_info['album-art'] = wibox.widget {
        image = IM_DEFAULT_PATH,
        widget = wibox.widget.imagebox
    }

    self.widget_popup_info['info'] = wibox.widget {
        font = beautiful.font_small,
        widget = wibox.widget.textbox
    }

    self.widget_popup_info['bar'] = wibox.widget {
        max_value     = 1,
        forced_height = 5,
        shape         = gears.shape.rounded_bar,
        border_width  = 1,
        color         = beautiful.fg_normal,
        background_color = beautiful.bg_focus,
        border_color  = beautiful.border_color,
        widget        = wibox.widget.progressbar
    }

    self.widget_popup_info['bar-text'] = wibox.widget {
        font = beautiful.font_small,
        widget = wibox.widget.textbox
    }

    self.widget_popup_info['info_bar_container'] = wibox.widget {
        self.widget_popup_info['info'],
        {
            self.widget_popup_info['bar'],
            top = 5,
            bottom = 5,
            widget = wibox.container.margin
        },
        self.widget_popup_info['bar-text'],
        layout = wibox.layout.fixed.vertical
    }

    self.widget_popup_info['layout'] = wibox.widget {
        self.widget_popup_info['album-art'],
        self.widget_popup_info['info_bar_container'],
        spacing = 5,
        layout = wibox.layout.ratio.horizontal
    }

    self.widget_popup_info['layout']:set_ratio(1, 0.4)
    self.widget_popup_info['layout']:set_ratio(2, 0.6)

    return self.widget_popup_info['layout']
end


function music_widget:update_widget(widget, stdout, stderr)
    if isempty(stdout) then
        -- Defaults
        self.widget_display['icon'].image = nil
        self.widget_display['text'].markup = 'No Music Sources Detected'
        self.widget_popup_info['album-art']:set_image(IM_DEFAULT_PATH)
        self.widget_popup_info['info'].markup = 'No Music Sources Detected'
        self.widget_popup_info['bar'].visible = false
        self.widget_popup_info['bar-text'].markup = ' '
        return
    end

    local vals = split(stdout, ';;')
    local trackid = trim(vals[1])
    local title = trim(vals[2])
    local artist = trim(vals[3])
    local album = trim(vals[4])
    local art_url = trim(vals[5])
    local position = trim(vals[6])
    local length = trim(vals[7])
    local status = trim(vals[8])

    local source = get_media_source(trackid)
    -- Update Display
    self.widget_display['icon'].image = icon[source]
    self.widget_display['text'].markup = format_title_artist(title, artist)

    -- Update Popup Art
    art_url = fix_image_url(source, art_url)
    if art_url ~= self.prev_art_url then
        if art_url == nil then
            self.widget_popup_info['album-art']:set_image(IM_DEFAULT_PATH)
        else
            download_image(art_url)
            self.widget_popup_info['album-art']:set_image(gears.surface.load_uncached(IM_PATH))
        end
        self.prev_art_url = art_url
    end

    if art_url ~= nil then self.widget_popup_info['album-art']:set_image(gears.surface.load_uncached(IM_PATH)) end

    -- Update Popup Text Info
    self.widget_popup_info['info'].markup =
        'Source:\t' .. source .. '\n' ..
        'Title:\t' .. (isempty(title) and 'N/A' or title) .. '\n' ..
        'Artist:\t' .. (isempty(artist) and 'N/A' or artist) .. '\n' ..
        'Album:\t' .. (isempty(album) and 'N/A' or album) .. '\n' ..
        'Status:\t' .. status

    -- Update Popup progressbar (if both position && length exists)
    if isempty(position) or isempty(length) then
        -- Set Progress Bar to not visible
        self.widget_popup_info['bar'].visible = false
    else
        self.widget_popup_info['bar'].visible = true
        self.widget_popup_info['bar'].value = tonumber(position) / tonumber(length)
        self.widget_popup_info['bar-text'].markup = format_bar_text(position) .. ' / ' .. format_bar_text(length)
    end
end

return music_widget

-- INFO
-- Find Player -- [youtubemusic, firefox, spotify]
-- Keys [Spotify]
    -- mpris:trackid
    -- mpris:length
    -- mpris:artUrl (300x300) https://i.scdn.co/image/{art-address} instead of https://open.spotify.com/image/{art-address}

    -- xesam:album
    -- xesam:albumArtist
    -- xesam:artist
    -- xesam:autoRating
    -- xesam:discNumber
    -- xesam:title
    -- xesam:trackNumber
    -- xesam:url
-- [YoutubeMusic (Desktop)]
    -- mpris:trackid
    -- mpris:length
    -- mpris:artUrl (Variable in Size)

    -- xesam:title
    -- xesam:album
    -- xesam:artist
    -- position (needs to be independently called via playerctl position --player=playerctld --format "{{ position }}")
-- [Firefox (Youtube)]
    -- mpris:trackid

    -- xesam:title
    -- xesam:album (usually empty)
    -- xesam:artist (usually empty)
