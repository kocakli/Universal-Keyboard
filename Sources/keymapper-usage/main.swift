import Foundation
import KeyMapperUsage

// Bundled helper (KeyMapper.app/Contents/MacOS/keymapper-usage). Reads the user's AI tool sign-ins,
// fetches quotas and prints only normalised quota data; credentials never leave this short-lived process.
let output = await UsageEngine.run(arguments: Array(CommandLine.arguments.dropFirst()))
FileHandle.standardOutput.write(output)
