#!/bin/sh

# Prevent Auto-sleep (after approx 10 minutes by default)
xset s off
xset -dpms
xset s noblank

# Initialise Keybindings (based on .xbindkeysrc)
xbindkeys
