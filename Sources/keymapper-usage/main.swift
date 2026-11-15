import Foundation
import KeyMapperUsage

let arguments = Array(CommandLine.arguments.dropFirst())

// `hook --provider <codex|claude|cursor>`: passive agent hook receiver. Records only fixed activity codes and
// always answers `{}` with exit status 0; no credentials, network or permission decisions.
if arguments.first == "hook" {
    ActivityHookReceiver.main(arguments: Array(arguments.dropFirst()))
}

// Bundled helper (KeyMapper.app/Contents/MacOS/keymapper-usage). Reads the user's AI tool sign-ins,
// fetches quotas and prints only normalised quota data; credentials never leave this short-lived process.
let output = await UsageEngine.run(arguments: arguments)
FileHandle.standardOutput.write(output)
