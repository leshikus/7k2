#!/bin/sh
# Launch Seven Kingdoms II (Godot edition). Extra arguments go to the game
# (for example: ./play.sh -- --autostart).
# Set GODOT to your Godot 4.3 executable if it is not on the PATH.
cd "$(dirname "$0")" || exit 1
GODOT="${GODOT:-$(command -v godot || command -v godot4 || echo "$HOME/tools/godot/Godot_v4.3-stable_win64.exe")}"
exec "$GODOT" --path . "$@"
