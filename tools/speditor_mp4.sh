#!/bin/sh
# SPeditor / SAeditor: turns rendered videos into small MP4 files (H.264 video, AAC sound).
#
# The game can only write MJPEG video (every frame is a separate JPEG picture) and gives
# addons no way to run an H.264 encoder, so <name>.avi.dat files are large. This script
# re-encodes each of them into <name>.mp4 next to it — several times smaller, the sound
# track is kept. Needs ffmpeg. Videos that already have an up-to-date .mp4 are skipped.
#
#   sh speditor_mp4.sh              all videos in garrysmod/data/speditor/renders
#   sh speditor_mp4.sh <folder>     all videos in another folder
#   sh speditor_mp4.sh --watch      stay running: every video is converted as soon as the
#                                   editor has finished rendering it (start it before the game)
#   CRF=23 sh speditor_mp4.sh       smaller files (18 by default: visually lossless)
set -e
WATCH=0
if [ "$1" = "--watch" ]; then WATCH=1; shift; fi
DIR="${1:-$(dirname "$0")/../../../data/speditor/renders}"
CRF="${CRF:-18}"
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is not installed"; exit 1; }

# The editor writes the total size into the file header only when the render has ended:
# while it is zero, the video is still being rendered.
finished() {
	[ "$(od -A n -t u4 -j 4 -N 4 "$1" 2>/dev/null | tr -d ' ')" != "0" ]
}

# An .mp4 whose conversion was cut short (the window was closed, the computer went to
# sleep) has no index and no player opens it: such a file is made again.
valid() {
	command -v ffprobe >/dev/null 2>&1 || return 0
	ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" >/dev/null 2>&1
}

convert_all() {
	found=0
	for src in "$DIR"/*.avi.dat "$DIR"/*.avi; do
		[ -f "$src" ] || continue
		found=1
		out="${src%.dat}"; out="${out%.avi}.mp4"
		if [ -f "$out" ] && [ "$out" -nt "$src" ] && { [ ! -s "$out" ] || valid "$out"; }; then
			[ "$WATCH" = 1 ] || echo "up to date: $(basename "$out")"
			continue
		fi
		if ! finished "$src"; then
			[ "$WATCH" = 1 ] || echo "still being rendered: $(basename "$src")"
			continue
		fi
		# H.264 needs even sizes; a video without sound is converted as is
		if ffmpeg -v error -y -f avi -i "$src" -c:v libx264 -preset slow -crf "$CRF" -pix_fmt yuv420p \
			-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:a aac -b:a 192k -movflags +faststart "$out.part.mp4"; then
			mv "$out.part.mp4" "$out"
			a=$(wc -c < "$src"); b=$(wc -c < "$out")
			echo "$(basename "$src"): $((a / 1024)) KB -> $(basename "$out"): $((b / 1024)) KB"
		else
			rm -f "$out.part.mp4"
			echo "could not convert $(basename "$src")"
			# not tried again until the video changes
			[ "$WATCH" = 1 ] && touch "$out"
		fi
	done
}

if [ "$WATCH" = 1 ]; then
	echo "watching $DIR (Ctrl+C to stop)"
	while :; do
		convert_all
		sleep 2
	done
fi
convert_all
[ "$found" = 1 ] || echo "no videos (*.avi.dat) in $DIR"
