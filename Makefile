APP := build/SideEye.app
# Swift Testing ships with the Command Line Tools but isn't on the default search paths.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F$(CLT_DEV)/Frameworks -Xlinker -F$(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

.PHONY: app run demo test clean

app:
	swift build -c release --product SideEye
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/SideEye $(APP)/Contents/MacOS/SideEye
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(APP)/Contents/Resources/; fi
	codesign --force --sign - --identifier app.sideeye.SideEye $(APP)

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
