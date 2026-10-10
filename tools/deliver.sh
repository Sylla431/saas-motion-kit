#!/usr/bin/env bash
# Downscale a 4K HyperFrames render to a delivery size.
#   tools/deliver.sh renders/film-2160.mp4 1920x1080 [out.mp4] [filter]
# filter: lanczos (default, for vector/3D) · area (pixel art: exact 2x box filter keeps pixels crisp)
# Audio, if present, is loudness-normalised for social (-14 LUFS, -1.5 dBTP) and checked after encoding.
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: tools/deliver.sh <in.mp4> [WxH] [out.mp4] [lanczos|area]" >&2; exit 2; }
in="$1"; size="${2:-1920x1080}"; out="${3:-${in%.*}-${size}.mp4}"; filter="${4:-lanczos}"
w="${size%x*}"; h="${size#*x}"
has_audio=false
if ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$in" | grep -q .; then
  has_audio=true
  # Aim 0.5 dB under the limit: the AAC encoder adds inter-sample peaks. At 192k ffmpeg's native
  # AAC pushed a bright mix from -2.8 to +1.7 dBTP; at 320k it stayed at -2.9.
  audio=(-af "loudnorm=I=-14:TP=-2:LRA=11" -c:a aac -b:a 320k -ar 48000)
else
  audio=(-an)
fi
ffmpeg -v error -y -i "$in" -vf "scale=${w}:${h}:flags=${filter}" \
  -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -profile:v high -movflags +faststart \
  "${audio[@]}" "$out"
echo "wrote $out"

# Measure what was actually encoded, not what loudnorm aimed for.
if $has_audio; then
  summary=$(ffmpeg -hide_banner -nostats -i "$out" -vn -af ebur128=peak=true -f null - 2>&1 | sed -n '/^\[Parsed_ebur128.*Summary:/,$p')
  lufs=$(awk '$1 == "I:" { print $2 }' <<<"$summary")
  tp=$(awk '/True peak:/ { found = 1 } found && $1 == "Peak:" { print $2; exit }' <<<"$summary")
  echo "audio: ${lufs} LUFS integrated, ${tp} dBTP true peak"
  if awk -v tp="$tp" 'BEGIN { exit !(tp > -1.5) }'; then
    echo "error: true peak ${tp} dBTP is over the -1.5 dBTP limit in $out" >&2
    exit 1
  fi
fi
