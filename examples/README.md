# Lua plugin examples

These examples only use Plugin API 1.0 features implemented by the current runtime:

- `api-showcase` (`1.0.0`): lifecycle, entity streaming, outgoing and TextDraw interception, chat, checkpoint, menu, mutable damage and player-state events, generation-safe server entity reads, controlled player/vehicle writes, low-level physics leases, Lua-composed gameplay, game/server snapshots, a local module, timers, menus and HUD text.
- `fps-counter`: smoothed FPS display with menu controls.
- `session-timer`: elapsed session time with pause and reset controls.
- `crosshair-guide`: configurable line and rectangle drawing.

All examples declare immediate activation. Their menu values use `samp.storage`, so settings survive plugin reloads and later game sessions. The FPS counter uses `samp.format.number(value, precision)` for bounded, platform-independent numeric HUD formatting. Plugin code should prefer this API over Lua's native floating-point string formatting.

All other example packages use version `1.0.0`.

Use the repository CLI to validate and package an example:

```bash
go run ./cmd/samp-plugin validate examples/fps-counter
go run ./cmd/samp-plugin pack examples/fps-counter
```

The packer places `manifest.json` at the ZIP root and writes portable entry paths. Import the generated `.splug` from **Resources → Plugins** and enable it in the in-game plugin menu. Each example is intentionally independent and may be installed alongside the others.

ZIP entry names must use `/` as their path separator. Backslashes are rejected as unsafe paths on every platform. Prefer the repository CLI instead of a platform-specific ZIP command.

The examples declare the `multiplayer` context. Plugins intended for both game modes may omit `contexts`; plugins restricted to offline play can declare `singleplayer`.
