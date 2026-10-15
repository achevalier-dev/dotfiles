#!/bin/bash
# Flat NC hardtop wallpaper, traced from a CC BY-SA 4.0 blueprint (see CREDITS.md).
# usage: make-nc-wallpaper.sh W H carW horizonY sunR out
#   ./make-nc-wallpaper.sh 2560 1440 1500 1010 430 nc-silhouette.jpg
#   ./make-nc-wallpaper.sh 2160 3840 1850 2480 560 nc-silhouette-portrait.jpg
set -e
S=$(dirname "$0")/nc-src; W=$1; H=$2; CW=$3; HY=$4; R=$5; OUT=$6
OUT=$(realpath -m "$OUT"); T=$(mktemp -d); cp "$S"/*.png "$T"; cd "$T"
CJK=$(fc-match -f '%{file}' 'Noto Serif CJK JP:style=Regular')
MONO=$HOME/.local/share/fonts/JetBrainsMonoNLNerdFontMono-Regular.ttf
# car layers at target width: body mask, panel lines, cropped to bbox
magick sil.png -crop 1250x390+43+20 +repage -resize ${CW}x car_mask.png
magick side_clean.png -crop 1250x390+43+20 +repage -resize ${CW}x -negate -threshold 30% car_lines.png
CH=$(magick identify -format %h car_mask.png)
CX=$(( (W-CW)/2 )); CY=$(( HY-CH+CH/40 ))
# body: near-black with faint panel lines, clipped to silhouette
magick -size ${CW}x${CH} xc:'#0b0b0c' \( -size ${CW}x${CH} xc:'#2b2d31' car_lines.png -alpha off -compose copy_opacity -composite \) -compose over -composite \
  car_mask.png -alpha off -compose copy_opacity -composite car_body.png
# chrome rim light: mask shifted up 3px minus mask
magick car_mask.png \( car_mask.png -roll +0-3 \) -compose minus_dst -composite -blur 0x0.6 rim_a.png
magick -size ${CW}x${CH} xc:'#8a8e93' rim_a.png -alpha off -compose copy_opacity -composite car_rim.png
magick car_body.png -flip \( +clone -alpha extract \( -size ${CW}x${CH} gradient:'gray(22%)'-black \) -compose multiply -composite \) -alpha off -compose copy_opacity -composite reflect.png
# taillight (rear = right end, ~ 95% x, 45% y) and headlight glow (front = left)
TX=$((CX+CW*955/1000)); TY=$((CY+CH*42/100)); HX=$((CX+CW*5/100)); HY2=$((CY+CH*44/100)); G=$((CW/60))
magick -size ${W}x${H} xc:'#1d1e21' \
  \( -size ${W}x${HY} gradient:'#151618'-'#26282b' \) -geometry +0+0 -compose over -composite \
  \( -size ${W}x$((H-HY)) gradient:'#121314'-'#0b0b0c' \) -geometry +0+${HY} -compose over -composite \
  \( -size ${W}x${H} xc:none -fill '#7a332d' -draw "circle $((W/2+W/9)),$((HY-R/3)) $((W/2+W/9)),$((HY-R/3-R))" -crop ${W}x${HY}+0+0 -background none -extent ${W}x${H} \) -compose over -composite \
  -fill '#2e3034' -draw "rectangle 0,${HY} ${W},$((HY+1))" \
  reflect.png -geometry +${CX}+$((HY+CH/40)) -compose over -composite \
  car_body.png -geometry +${CX}+${CY} -compose over -composite \
  car_rim.png -geometry +${CX}+${CY} -compose over -composite \
  \( -size ${W}x${H} xc:none -fill '#c4392f' -draw "circle ${TX},${TY} $((TX+G/2)),${TY}" -blur 0x$((G/2)) \) -compose screen -composite \
  \( -size ${W}x${H} xc:none -fill '#c4392f' -draw "circle ${TX},${TY} $((TX+G/5)),${TY}" \) -compose over -composite \
  \( -size ${W}x${H} xc:none -fill '#d8d4c8' -draw "circle ${HX},${HY2} $((HX+G/4)),${HY2}" -blur 0x$((G/3)) \) -compose screen -composite \
  -font "$CJK" -pointsize $((H/40)) -fill '#4a4c50' -gravity southeast -annotate +$((W/24))+$((H/18)) '人馬一体' \
  -font "$MONO" -pointsize $((H/110)) -fill '#3a3c40' -annotate +$((W/24))+$((H/18-H/40)) 'jinba ittai · mx-5 nc' \
  -quality 94 "$OUT"
