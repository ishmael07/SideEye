APP := build/SideEye.app
# Swift Testing ships with the Command Line Tools but isn't on the default search paths.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F$(CLT_DEV)/Frameworks -Xlinker -F$(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

.PHONY: app release run demo test clean

app:
	swift build -c release --product SideEye
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/SideEye $(APP)/Contents/MacOS/SideEye
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(APP)/Contents/Resources/; fi
	codesign --force --sign - --identifier app.sideeye.SideEye $(APP)

# Universal (Apple silicon + Intel) build for a GitHub release: SideEye.dmg for people, SideEye.zip for install.sh. Without Xcode each architecture
# is built on its own and merged with lipo.
release:
	swift build -c release --product SideEye
	swift build -c release --product SideEye --triple x86_64-apple-macosx14.0
	rm -rf $(APP) build/SideEye.zip
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	lipo -create .build/arm64-apple-macosx/release/SideEye .build/x86_64-apple-macosx/release/SideEye -output $(APP)/Contents/MacOS/SideEye
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force --sign - --identifier app.sideeye.SideEye $(APP)
	cd build && ditto -c -k --keepParent SideEye.app SideEye.zip
	./scripts/make-dmg.sh
	@lipo -archs $(APP)/Contents/MacOS/SideEye; ls -lh build/SideEye.zip build/SideEye.dmg

run: app
	-pkill -x SideEye
	open $(APP)

demo: app
	-pkill -x SideEye
	open $(APP) --args --demo

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build build
