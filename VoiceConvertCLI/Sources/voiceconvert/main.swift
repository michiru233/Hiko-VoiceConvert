import Darwin
import VoiceConvertCLIKit

exit(CLI(arguments: Array(CommandLine.arguments.dropFirst())).run().rawValue)
