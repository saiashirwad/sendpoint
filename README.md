# Sendpoint

A macOS menu bar app for making voice notes while you read.

## Development

Use Swift Package Manager from the terminal; no Xcode project is needed:

```sh
swift test                     # Debug build and tests
./build.sh                     # Debug app bundle, locally signed
./install.sh                   # Replace the installed app and launch it
./build.sh release             # Optimized app bundle for performance checks
```
