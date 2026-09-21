#!/bin/bash
# Renders dev/person.html headlessly to a PNG:  dev/shot.sh out.png "who=me&poses=0:0,32:0"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --use-angle=swiftshader --enable-unsafe-swiftshader --hide-scrollbars --force-device-scale-factor=1 \
  --window-size="${3:-2240},420" --virtual-time-budget=12000 --screenshot="$1" "http://localhost:8765/dev/person.html?$2" >/dev/null 2>&1
