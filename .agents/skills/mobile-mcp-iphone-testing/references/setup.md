# Setup and diagnosis

## Canonical sources

- Repository: https://github.com/mobile-next/mobile-mcp
- Real iPhone guide: https://github.com/mobile-next/mobile-mcp/wiki/Getting-Started-with-iOS-Real-Device
- npm package: `@mobilenext/mobile-mcp`

Check these sources and the installed package version again before changing
configuration because the project evolves quickly.

## Codex configuration

Add the server with:

```sh
codex mcp add mobile-mcp npx "@mobilenext/mobile-mcp@latest"
```

Equivalent `~/.codex/config.toml`:

```toml
[mcp_servers.mobile-mcp]
command = "npx"
args = ["@mobilenext/mobile-mcp@latest"]
```

Restart or reload the MCP client after configuration. Verify with
`codex mcp list`, then call `mobile_list_available_devices` through the MCP.
For repeatable release evidence, replace `latest` with the verified version.

## Simulator baseline

- Install Xcode command-line tools and Node.js 20 or newer.
- Boot exactly the intended simulator when possible.
- Current Mobile MCP releases may bootstrap their own iOS automation support;
  if discovery or UI interaction fails, inspect the current upstream guide and
  installed package behavior before manually starting WebDriverAgent.
- Camera hardware behavior is not proven by an iOS simulator.

## Real iPhone baseline

The official README/wiki currently names these prerequisites:

1. A trusted USB-connected iPhone visible to macOS and `ios list`.
2. `go-ios` installed (`ios` CLI).
3. A userspace tunnel, commonly `ios tunnel start --userspace`.
4. Port forwarding, commonly `ios forward 8100 8100`.
5. A signed WebDriverAgent runner installed/running for the target device.

Keep tunnel, forwarding, and WebDriverAgent processes observable in dedicated
terminals. Do not start long-running processes silently during planning.

Upstream history has changed the iOS backend more than once, so treat this list
as a diagnostic starting point, not proof. Confirm actual requirements by
calling `mobile_list_available_devices` and `mobile_list_elements_on_screen` on
the installed version.

## Diagnostic order

1. `node --version` and resolved `@mobilenext/mobile-mcp` version.
2. `codex mcp list` (or the active client's equivalent).
3. `xcrun xctrace list devices` and `ios list` for a real iPhone.
4. Tunnel/forwarding process health and port 8100 reachability when required.
5. Signing/trust status of WebDriverAgent and the app.
6. `mobile_list_available_devices`.
7. `mobile_list_apps`, then `mobile_list_elements_on_screen`.

If a real device appears to Xcode but not `ios list`, fix trust/tunnel/go-ios
before blaming the app. If the device is listed but elements fail, inspect the
automation runner and accessibility tree.
