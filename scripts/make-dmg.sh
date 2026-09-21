#!/bin/bash
# Packs build/SideEye.app into build/SideEye.dmg: a window with the app and an Applications shortcut to drag it onto.
set -euo pipefail
cd "$(dirname "$0")/../build"
rm -rf dmg SideEye.dmg rw.dmg
mkdir dmg && cp -R SideEye.app dmg/ && ln -s /Applications dmg/Applications
hdiutil create -quiet -volname SideEye -srcfolder dmg -fs HFS+ -format UDRW rw.dmg
mount=$(hdiutil attach -nobrowse -noautoopen rw.dmg | awk -F'\t' '/\/Volumes\//{print $3}')
# The mounted disk wears the app's icon. (hdiutil drops this file from -srcfolder, so it is added after mounting.)
cp SideEye.app/Contents/Resources/AppIcon.icns "$mount/.VolumeIcon.icns" && SetFile -a C "$mount" 2>/dev/null || true
# Icon layout is cosmetic: if Finder scripting isn't permitted the DMG still works, just unarranged.
perl -e 'alarm 25; exec @ARGV' osascript >/dev/null 2>&1 <<OSA || echo "note: Finder layout skipped"
tell application "Finder"
  tell disk "SideEye"
    open
    set w to container window
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set bounds of w to {300, 200, 840, 540}
    set o to icon view options of w
    set arrangement of o to not arranged
    set icon size of o to 112
    set position of item "SideEye.app" to {140, 165}
    set position of item "Applications" to {400, 165}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync; hdiutil detach -quiet "$mount"
hdiutil convert -quiet rw.dmg -format UDZO -imagekey zlib-level=9 -o SideEye.dmg
rm -rf dmg rw.dmg
ls -lh SideEye.dmg
