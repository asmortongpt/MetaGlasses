tell application "Xcode"
    activate
    delay 2
end tell

tell application "System Events"
    tell process "Xcode"
        -- Click on the scheme/device selector
        keystroke "0" using {command down, shift down}
        delay 1

        -- Type to search for iPhone
        keystroke "iPhone (26.2)"
        delay 1
        keystroke return
        delay 2

        -- Press Command+R to build and run
        keystroke "r" using {command down}
    end tell
end tell
