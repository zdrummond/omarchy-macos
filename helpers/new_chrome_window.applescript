-- Omarchy explicit Chrome launch; the existing macOS Service owns the shortcut.
on writeDiagnostic(messageText)
    try
        do shell script "/usr/bin/printf '[%s] chrome-service: %s\\n' \"$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)\" " & (quoted form of messageText) & " >> /tmp/omarchy_window_state.log"
    end try
end writeDiagnostic

on run {input, parameters}
    my writeDiagnostic("invoked")
    set broker to (POSIX path of (path to home folder)) & "Applications/Omarchy Dock Launch.app/Contents/MacOS/dock_launch_follow"
    set launchToken to do shell script "/usr/bin/uuidgen"
    try
        do shell script (quoted form of broker) & " --arm-chrome " & (quoted form of launchToken)
        my writeDiagnostic("arm-accepted")
    on error messageText number errorCode
        -- Numeric codes only: avoid logging script arguments, window contents,
        -- or any application-provided error text.
        my writeDiagnostic("arm-failed code=" & errorCode)
    end try
    try
        tell application "System Events"
            tell application "Google Chrome"
                make new window
                activate
            end tell
        end tell
        my writeDiagnostic("creation-returned")
    on error errorMessage number errorNumber
        my writeDiagnostic("creation-failed code=" & errorNumber)
        try
            do shell script (quoted form of broker) & " --cancel-chrome " & (quoted form of launchToken)
        end try
        error errorMessage number errorNumber
    end try
    return input
end run
