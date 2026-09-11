# Architecture

How the self-hosted Ballistic Labyrinth stack fits together. Read this before
touching `compose.yaml`, `deploy/Caddyfile` or `manager/manager.js`.

## Big picture

The upstream game used Godot's ENet/UDP multiplayer, which browsers cannot speak.
This fork replaced it with `WebSocketMultiplayerPeer` end-to-end, so **one HTTPS
port** carries the web client download, the room REST API and all multiplayer
traffic:

```
players' browsers (Godot web export, wasm)
        │  GET /                     static client (index.html, .wasm, .pck)
        │  POST /api/rooms           create room
        │  GET  /api/rooms/<code>    room exists?
        │  WSS  /ws/<code>           multiplayer ( Godot high-level MP over WS )
        ▼
┌──────────────────────────────┐   compose service "web"
│ Caddy :80 (published 8137)   │   • COOP/COEP headers (threaded Godot 4 export)
│  /ws/*, /api/rooms* ─────────┼──► manager:8899 (compose service "manager")
│  everything else → static    │
└──────────────────────────────┘
                                   ┌─────────────────────────────────────┐
                                   │ Node manager (manager/manager.js)   │
                                   │  • room registry (code → process)   │
                                   │  • spawns/kills room processes      │
                                   │  • WS → raw TCP pipe to room port   │
                                   │                                     │
                                   │   room ABC123: /app/server --headless, BL_PORT=7900
                                   │   room DEF456: /app/server --headless, BL_PORT=7901
                                   │   ... up to MAX_ROOMS (24)          │
                                   └─────────────────────────────────────┘
```

## Components

### `web` container — Caddy (`Dockerfile.web`, `deploy/Caddyfile`)

Base image `caddy:2.10-alpine`; serves `build/web` from `/srv`.

```caddy
:80 {
    encode zstd gzip
    header {
        Cross-Origin-Opener-Policy "same-origin"
        Cross-Origin-Embedder-Policy "require-corp"
    }
    @ws    path /ws/*         → reverse_proxy manager:8899
    @rooms path /api/rooms*   → reverse_proxy manager:8899
    handle { root * /srv; try_files {path} /index.html; file_server }
}
```

- **COOP/COEP headers are mandatory**: the Godot 4 web export uses
  `SharedArrayBuffer` threads (`variant/thread_support=true` in
  `export_presets.cfg`), which browsers only allow on cross-origin-isolated pages.
  Removing these headers = black screen.
- `/healthz` is intentionally **not** proxied; it is only used by the manager's
  own Docker HEALTHCHECK and ad-hoc debugging inside the network.
- Everything not matching `/ws/*` or `/api/rooms*` falls through to the static
  site with an SPA fallback to `/index.html` (keeps `?room=CODE` links working).

### `manager` container — room manager (`Dockerfile.server`, `manager/manager.js`)

Base image `node:24-bookworm-slim` with two things copied in:
`/app/server` (the headless Godot build) and `/app/manager.js` (plain Node, no
npm dependencies). Listens on `0.0.0.0:8899` (container-internal only).

#### HTTP API

| Endpoint | Behavior |
| --- | --- |
| `POST /api/rooms` | creates a room → `201 {"code":"ABC123"}`; `429 too_many_rooms` at 24 rooms; `503 no_capacity` if no free port/code |
| `GET /api/rooms/<code>` | `200 {"code":…}` if the room exists, else `404` (codes compared uppercased, 4–12 alnum accepted) |
| `GET /healthz` | `200 {"ok":true,"rooms":N}` — Docker healthcheck + debugging |

Room codes: 6 characters from `ABCDEFGHJKMNPQRSTUVWXYZ123456789`
(32 symbols; `I`, `L`, `O`, `0` omitted to avoid confusion).

#### Room lifecycle

1. `POST /api/rooms` → pick a free port from `7900–8090`, then
   `spawn('/app/server', ['--headless'], { env: { …, BL_PORT: String(port) } })`.
   The Godot server reads `BL_PORT` (`NetworkManager.get_server_port()`,
   default `7777` when unset) and starts a WebSocket server on it.
2. Room stdout/stderr is teed to manager stdout with a `[room CODE]` prefix **and**
   appended to `/app/roomlogs/<code>.log` (the `room-logs` named volume).
3. A sweeper every 30 s SIGTERMs any room with **zero active sockets** idle for
   15 min (`IDLE_TIMEOUT_MS`). Host closing the room, crashes and idles all end
   with the process exiting and the room being dropped from the registry.
4. On manager `SIGTERM`/`SIGINT`, every room process is **SIGKILL**ed
   (`manager shutdown (…), killing N room processes`) — rooms never outlive
   the manager.

#### WebSocket tunnel — `GET /ws/<code>` (Upgrade)

The manager answers the Upgrade itself, opens a raw TCP connection to
`127.0.0.1:<roomPort>`, replays the original request line + headers upstream, then
pipes both sockets together. From the Godot server's point of view the client
connected directly. If the room process has not finished booting, the manager
retries every 300 ms up to 20 times (~6 s) before answering `504`; unknown codes
get a plain `404`. Every connect/disconnect refreshes the room's idle clock.

### The Godot project (shared by both exports)

One codebase, two presets (`export_presets.cfg`):

| Preset | Output | Runtime role |
| --- | --- | --- |
| `Web` | `build/web/index.html` (+ `.wasm`, `.pck`) | the client every player runs |
| `Linux/X11` (`dedicated_server=true`, embedded PCK) | `build/server/ballistic-labyrinth.x86_64` | per-room authoritative server, run with `--headless` |

The binary decides its role at boot (`globals/network_manager.gd`): a
headless/dedicated build immediately calls `start_server()` and listens on
`BL_PORT`; a web build shows the lobby and never hosts.

#### Autoloads (`project.godot`)

| Autoload | File | Responsibility |
| --- | --- | --- |
| `NetworkManager` | `globals/network_manager.gd` | WS server/client setup, connect URL derivation, kick/close, ping probes, host migration |
| `SessionManager` | `globals/session_manager.gd` | session registry (name/color/kills/score/deaths/ping, admin/op/muted), bots, crates, sid encoding |
| `UIManager` | `globals/ui_manager.gd` | lobby/pause/chat scenes, `ROUND n` label, `Tab` leaderboard, global key handling |
| `IngameManager` | `globals/ingame_manager.gd` | round state machine (STOPPED→ANIMATING→WAITING_BEFORE_SYNC→FINISHED), maze/pawn/bullet spawning, `BLTRACE` breadcrumbs |
| `MasterManager` | `globals/master_manager.gd` | pause plumbing, server-synced sounds, soundtrack |
| `ChatManager` | `globals/chat_manager.gd` | chat history (100 msgs), channels (peer/global/admin/target/shell), mute enforcement, purge |
| `ConsoleManager` | `globals/console_manager.gd` | `/command` registry + permission checks (ANY/ADMIN/OP), stdin console on the server |

#### Client ↔ server protocol

- Transport: `WebSocketMultiplayerPeer` with **4 MiB** in/out buffers on both ends
  (`WS_BUFFER_SIZE`) — the 64 KiB default truncated replication payloads
  ("Buffer payload full") on busy rounds. Transfer mode is set to
  `TRANSFER_MODE_UNRELIABLE_ORDERED` after peer setup.
- Godot's high-level multiplayer API does the rest: servers are authoritative,
  clients call `rpc_id(1, …)` to request actions (start game, pause, chat,
  profile updates), the server validates (`is_op`/`is_admin` checks) and
  broadcasts state (session registry, maze seed, pawn spawns).
- The connect URL is derived in JS from the page origin — there is no IP field
  anywhere (`get_connect_url()`): `wss://<host>/ws/<code>` (`ws://` on plain http).
- **Ping:** every 5 s the client sends `ping_probe(now)`; the server reflects it
  with `pong_probe`; the client reports the RTT via `report_ping`; the server
  stores it in `SessionManager.data[sid].ping` and rebroadcasts the registry —
  this feeds the `PING` column of the `Tab` leaderboard.

#### Rooms, host, and authority

- First human to register a profile in a room gets `op`+`admin`
  (`SessionManager.request_profile_update` grants power when no other op exists).
  The room host sees *Start Game* / *Close Room* buttons and may run OP chat
  commands.
- If the host disconnects, `NetworkManager.migrate_host_if_needed()` promotes the
  lowest remaining peer id and announces it in chat. The room itself is never
  tied to a browser — simulation always runs in the headless Godot process.
- *Close Room* (`request_close_room` rpc, op-only) broadcasts
  "Room was closed by the room admin", then the server process quits after 0.4 s;
  clients land back on the home screen via `server_disconnected`.
- Late joiners mid-round get a spectate window; on the next round
  `create_controllers()` gives them a tank.
- Sessions are identified by encoded sids (`#HOST` = server, `ai#…` = bots,
  base-N alphabet otherwise) — see `/get_sessions` in `docs/COMMANDS.md`.

#### Game flow inside a room process

`start_game` (op) → maze dimensions rolled from the `/maze` range
(default always 20×12 cells) → `start_ingame(seed, dims)` → maze animates/syncs
(`BLTRACE broadcast_generation_finish`) → `place_pawns()` spawns one tank per
session → state `FINISHED` (round live). A round ends when ≤1 tank remains
(`DeathDelay` timer) → `_on_ingame_next_round` → `restart_ingame()`.
`alive_tanks_count` is carefully repaired when a player leaves mid-round so the
round can still end — that was a real deadlock fixed in this fork.

## Repository map

| Path | What it is |
| --- | --- |
| `compose.yaml` | the two services; publishes `8137:80`; `room-logs` volume |
| `Dockerfile.web` / `Dockerfile.server` | Caddy image; Node + Godot server image |
| `deploy/Caddyfile` | headers + routing for the single entrypoint |
| `manager/manager.js` | room orchestrator (API, WS tunnel, lifecycle) |
| `project.godot` | Godot 4.7.1 project, autoloads, input map, version `1.21` |
| `export_presets.cfg` | `Web` + `Linux/X11` dedicated-server presets |
| `globals/` | the seven autoload singletons (network/session/UI/ingame/master/chat/console) |
| `ingame/` | maze scene, tank pawns, bullets, crates, bot & player controllers |
| `ui/` | lobby (home screen, help panel), chat menu, pause menu |
| `build/web`, `build/server` | exported artifacts (git-ignored, required for the images) |
| `docs/` | this documentation set |

## Hard limits (verified in code)

| Limit | Value | Where |
| --- | --- | --- |
| Published ports | 1 (`8137`) | `compose.yaml` |
| Rooms | 24 concurrent, 15 min idle reaping | `manager/manager.js` |
| Room code | 6 chars, 32-symbol alphabet | `manager/manager.js` |
| Internal room ports | 7900–8090 | `manager/manager.js` |
| WS buffer | 4 MiB each direction | `globals/network_manager.gd` |
| Bots | 5 default (`/bot_max`) | `globals/session_manager.gd` |
| Crates | 15 default (`/crate_max`), auto-spawn caps at alive-tank count | `globals/session_manager.gd`, `ingame/ingame.gd` |
| Maze size | 20×12 default, max 25 cells (`/maze_max`), width ≥ height enforced | `globals/ingame_manager.gd` |
| Chat history | 100 messages | `globals/chat_manager.gd` |
| Ping cadence | 5 s | `globals/network_manager.gd` |
