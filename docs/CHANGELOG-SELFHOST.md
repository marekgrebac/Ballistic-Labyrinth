# Self-Host Fork Changelog

Everything this fork changed relative to upstream
[Wizzoplit273/Ballistic-Labyrinth](https://github.com/Wizzoplit273/Ballistic-Labyrinth)
(forked from its `main` branch; upstream is MIT-licensed and the `LICENSE` file is
retained). Game version shown in the lobby: `1.21` (Godot `4.7.1.stable`,
Compatibility renderer).

## 2026-09-11 — self-hosted web edition

### Added

- **Room-based multiplayer over one port.** A small Node.js room manager
  (`manager/manager.js`) spawns one headless Godot dedicated server per room,
  each on its own internal port (`BL_PORT`, starting at 7900). Public surface:
  `POST /api/rooms` (create, 6-char code), `GET /api/rooms/<code>` (exists),
  `GET /healthz`, and a WebSocket tunnel `GET /ws/<code>` that pipes raw TCP to
  the room process after the HTTP Upgrade.
- **Docker packaging.** `compose.yaml` + `Dockerfile.web` (Caddy 2.10 serving the
  web export with the COOP/COEP headers Godot 4 threads require, SPA fallback,
  reverse proxy to the manager) + `Dockerfile.server` (Node 24 + the headless
  server binary, `/healthz` healthcheck). Single published port: **8137**.
- **Web lobby flow.** *Create Room* calls the API and connects automatically;
  *Join Room* validates the code against the API first; `?room=CODE` URL query
  auto-fills and auto-joins for share links; connect URL derived from the page
  origin (`wss://<host>/ws/<code>`) — no IP input anywhere.
- **Room host concept.** First human to join a room receives op+admin and sees
  *Start Game* / *Close Room* buttons. Host migration on disconnect (earliest
  remaining player, announced in chat) and `/makehost <username>` to transfer
  host voluntarily.
- **Close Room** — the host can terminate the room for everyone
  (`request_close_room` rpc); players are notified and land back on the home
  screen.
- **`ROUND n` indicator** top-left during matches (`UIManager.set_round_label`).
- **Hold-`Tab` leaderboard**: PLAYER (in their color), KILLS, DEATHS, K/D, SCORE,
  PING; sorted by score; refreshes every second while held. Ping is measured
  app-side every 5 s (`ping_probe`/`pong_probe`/`report_ping` rpcs) and
  distributed in the session registry.
- **Lobby help panel** on the home screen: two columns (Controls + Room host
  commands). Hidden while online.
- **Spectate window** when joining a room mid-round.
- **`/purge`** clears chat for everyone; **`/makehost`**; name & color autosave
  on every input change (no Enter needed).
- **BLTRACE forensics** — the server binary emits `BLTRACE …` breadcrumbs
  (peer connect/disconnect, controller/ingame lifecycle, `place_pawns` steps,
  tank deaths) into the per-room log.

### Changed

- **ENet → WebSockets.** All multiplayer now uses `WebSocketMultiplayerPeer`
  (`globals/network_manager.gd`). WS in/out buffers raised 64 KiB → **4 MiB** on
  both peers, fixing "Buffer payload full" replication loss during busy rounds.
- **The dead console commands `connect`, `start_server`, `close_server` were
  removed** — connections are room-code driven; `/disconnect` issued against the
  server now answers "can't disconnect with this command: only the room's server
  process may stop it".
- **Chat UX:** Enter (or Y/C) opens, Enter sends and unfocuses back to the game;
  Shift+M move / Shift+R resize / Shift+H hide; chat names colored by each
  player's chosen color (BBCode-enabled `ChatText`, user text bracket-escaped).
  The chat window (CanvasLayer layer 100) is **hidden while offline** so it no
  longer overlaps and swallows lobby button clicks. Chat history capped at 100.
- **Privileged commands are OP-only** (`/start`, `/maze`, `/bot`, `/crate`,
  `/assign`, `/mute`, `/pause`, `/admin`, `/makehost`, limits, …). Guest verbs:
  chat, `help*`, `disconnect/leave`, `get`/`set` (own attributes), `get_sessions`.
- **Bot AI throttled.** Pathfinding/target scans ran every physics frame per bot
  (~3.5 cores per bot-heavy room); now staggered to every 4th tick
  (`AI_TICKS = 4` in `bot_controller.gd`, 60 Hz → 15 Hz per bot, phase-offset per
  bot) ≈ 99% of one core.
- **Profile updates preserve stats.** Re-sending your profile (name/color change)
  keeps kills/score/deaths/ping instead of wiping them.
- **`/maze` ergonomics.** Arguments are joined and validated
  (`min ≤ max`, `≤ /maze_max` (25), all ≥ 1) with explicit feedback instead of
  silently failing on unquoted args; quotes still accepted.

### Fixed

- **Segfault: `add_crate`/`remove_crate`** read the `Crates` node from a wrong
  path (`ingame_container.get_node("Crates")`); now resolved from the spawned
  ingame child with null guards (crashes previously killed whole room processes).
- **Use-after-free: stale `pawn` pointers.** Player and bot controllers kept
  references to tanks freed during round restarts; all accesses now guarded with
  `is_instance_valid`, plus an `ingame_container` emptiness guard before bot
  target scans. `bullet.gd` `owner_node` accesses guarded the same way.
- **Rounds never ended after a mid-game leave.** `delete_player` did not
  decrement `alive_tanks_count`, so the "≤1 tank remains" condition never fired;
  it now decrements and starts the `DeathDelay` round-end timer. Orphan
  controllers left behind by disconnects outside the FINISHED state are cleaned
  up too.
- **Fake-connected clients.** `connection_failed`/`server_disconnected` left the
  client thinking it was online; both now reset state, clear the registry and
  return to the offline lobby.
- **First-joiner privilege grant** (`SessionManager.request_profile_update`)
  gives op+admin to the first human in a room — previously a freshly spawned
  dedicated room had no one able to start the game.

### Ops

- **Idle room reaping:** rooms with zero connected players are SIGTERMed after
  15 min (sweeper every 30 s); capacity cap `MAX_ROOMS = 24` with
  `429 too_many_rooms`; new-room joins get ~6 s of connect retries while the room
  process boots (`504` after that).
- **Clean shutdown:** on manager SIGTERM/SIGINT all room processes are SIGKILLed
  and logged (`manager shutdown (…), killing N room processes`).
- **Logging:** API requests logged with user-agent; per-room stdout/stderr teed
  to manager stdout with `[room CODE]` prefix and to `/app/roomlogs/<CODE>.log`
  (named volume `room-logs`, survives `docker compose down`).
- **No UDP/ENet/TURN anywhere** — the whole stack is one HTTP(S) port behind a
  Cloudflare Tunnel; WebSockets pass through natively.
- Room logs contain the per-room `OP_PASSWORD: …` line (password rotates after
  each successful `/op`) — treat room logs as sensitive.
