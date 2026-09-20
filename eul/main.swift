import AppKit

if CommandLine.arguments.dropFirst().first == "mcp-connect" {
    McpConnectCLI.run()
} else {
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
