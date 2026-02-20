#!/bin/sh
# Outputs JSON for Waybar custom module with `text` (time) and `tooltip` (date)
TIME=$(date +'%-I:%M %p')
DATE=$(date +'%A, %B %-d, %Y')
printf '{"text":"%s","tooltip":"%s"}\n' "$TIME" "$DATE"
