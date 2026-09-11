# Deployment Guide

How to run your own Ballistic Labyrinth instance. Everything happens in the
repository directory — on the reference host that is `/root/Ballistic-Labyrinth`.

## What you are deploying

```
                       Internet
                          │  HTTPS + WSS (one public hostname)
                 Cloudflare Tunnel
                          │
                    http://localhost:8137          ← the ONLY published port
                          │
                ┌─────────┴──────────┐
                │  web (Caddy :80)   │  serves the Godot web build,
                │                    │  reverse-proxies /ws/* and /api/rooms*
                └─────────┬──────────┘
                          │  (internal docker network)
                ┌─────────┴──────────┐
                │ manager (Node :8899)│  room API + WebSocket tunnel
                │  ├─ room ABC123 → headless Godot server on 127.0.0.1:7900
                │  ├─ room DEF456 → headless Godot server on 127.0.0.1:7901
                │  └─ … up to 24 rooms
                └────────────────────┘
```

- `web` — Caddy 2.10 serving `build/web` (the exported HTML5/wasm client) with the
  COOP/COEP headers Godot 4 web threads require, and proxying game traffic.
- `manager` — plain Node.js (`manager/manager.js`, zero dependencies) that spawns
  one headless Godot dedicated server (`build/server/ballistic-labyrinth.x86_64`,
  ~84 MB) per room and pipes WebSocket connections to it.

Because all multiplayer runs over WebSocket on the same hostname/port as the web
page, there is **no UDP, no ENet and no TURN server** anywhere in the stack.

## Prerequisites

| Requirement | Notes |
| --- | --- |
| Docker with the Compose plugin | `docker compose version` should print v2.x |
| This repo at `/root/Ballistic-Labyrinth` | `build/web` and `build/server` must exist (see [Rebuilding](#rebuilding-the-game)) |
| Cloudflare account + `cloudflared` | only for the public tunnel setup below |

Exported binaries (`build/`) and `export_presets.cfg` are **git-ignored** — after a
fresh clone you must export the game before `docker compose up` will work.

## Quick start

```bash
cd /root/Ballistic-Labyrinth
docker compose up -d --build
docker compose ps          # both services should be "running" (manager: healthy)
docker compose logs -f     # follow logs
```

The game is now reachable at `http://localhost:8137`. Verify the pieces:

```bash
curl -s http://localhost:8137/ | head -c 200        # the game's index.html
docker exec ballistic-labyrinth-manager-1 \
  node -e "fetch('http://127.0.0.1:8899/healthz').then(r=>r.json()).then(console.log)"
# → { ok: true, rooms: 0 }
```

Useful lifecycle commands:

```bash
docker compose up -d --build   # build + (re)start
docker compose down            # stop and remove containers (keeps the log volume)
docker compose restart manager # restart ONLY the manager (kills all rooms!)
docker compose logs -f manager # manager + per-room stdout
docker compose logs -f web     # Caddy access/errors
```

> **Warning:** restarting or stopping the `manager` container SIGKILLs every room
> process. All players are dropped back to their home screens and must create or
> join new rooms.

## Exposing it: Cloudflare Tunnel

The stack is designed for exactly **one** public hostname served by a Cloudflare
Tunnel. WebSockets pass through Cloudflare natively — no extra options, timeouts
or port openings are needed.

1. Create a tunnel and a public hostname, e.g. `game.example.com`, in the
   Cloudflare Zero Trust dashboard (or with `cloudflared`).
2. Point the hostname's service at the published port on this machine:

   ```yaml
   # ~/.cloudflared/config.yml  (on the same host as docker compose)
   tunnel: <your-tunnel-id>
   credentials-file: /root/.cloudflared/<your-tunnel-id>.json
   ingress:
     - hostname: game.example.com
       service: http://localhost:8137
     - service: http_status:404
   ```

   If `cloudflared` runs on a *different* machine than the Docker host, use that
   machine's address instead, e.g. `http://192.168.1.10:8137`.
3. Run the tunnel: `cloudflared tunnel run <your-tunnel-id>`
   (or install it as a service).

Share `https://game.example.com/` with your friends. Room links look like
`https://game.example.com/?room=ABC123` — opening one auto-fills the room code and
joins immediately.

### Ports & firewall

| Port | Exposed? | Purpose |
| --- | --- | --- |
| `8137` | **yes** (published by compose) | the whole application; point the tunnel here |
| `8899` | no (container-internal) | manager room API + WS tunnel |
| `7900–8090` | no (container-internal) | one headless Godot server per room |

You do **not** need any cloud firewall rules, UDP openings or NAT forwards.
(If you want to be extra strict, bind the published port to localhost by changing
the compose mapping to `"127.0.0.1:8137:80"` so only the tunnel can reach it.)

## Rebuilding the game

Required after any change to the Godot project (`.gd` files, scenes, assets). The
reference host has Godot 4.7.1 headless at `/root/godot/godot` with export
templates installed under `~/.local/share/godot/export_templates/4.7.1.stable/`.

```bash
cd /root/Ballistic-Labyrinth

# 1) web client → build/web (index.html + index.wasm + index.pck, ...)
GODOT_SILENCE_ROOT_WARNING=1 /root/godot/godot --headless --path . --export-release "Web"

# 2) dedicated server → build/server/ballistic-labyrinth.x86_64
GODOT_SILENCE_ROOT_WARNING=1 /root/godot/godot --headless --path . --export-release "Linux/X11"

# 3) rebuild and restart the containers
docker compose up -d --build
```

- The **Web** preset (`export_presets.cfg`) exports with thread support to
  `build/web/index.html`. `Dockerfile.web` copies `build/web` into the Caddy image.
- The **Linux/X11** preset is a `dedicated_server=true` export with the PCK
  embedded, to `build/server/ballistic-labyrinth.x86_64`. `Dockerfile.server`
  copies it into the manager image.
- You do not need to restart *players'* browsers — the web client is re-downloaded
  on next page load.

The manager image is based on `node:24-bookworm-slim` and runs
`node /app/manager.js`; it has a Docker HEALTHCHECK hitting `/healthz` every 10 s,
and `web` waits for the manager to be healthy before starting.

## Tuning knobs

### Manager (`manager/manager.js` — edit, then `docker compose up -d --build`)

| Constant | Default | Meaning |
| --- | --- | --- |
| `MAX_ROOMS` | `24` | max simultaneous room processes (API returns `429 too_many_rooms` above) |
| `IDLE_TIMEOUT_MS` | `15 * 60 * 1000` | rooms with **zero** connected players are reaped after 15 min (sweeper runs every 30 s, SIGTERM) |
| `ROOM_PORT_BASE` / `ROOM_PORT_MAX` | `7900` / `8090` | internal port range handed to room processes |
| `CONNECT_RETRY_MS` × `CONNECT_RETRY_MAX` | `300` × `20` | ~6 s grace for a room process to boot before WS joins get a `504` |
| `CODE_ALPHABET` / `CODE_LEN` | 32 symbols / `6` | room codes; ambiguous `I`, `L`, `O`, `0` are excluded |

### Game side (in-game host console, per room)

| Command | Default | Meaning |
| --- | --- | --- |
| `/bot_max N` | `5` | max bots per room |
| `/crate_max N` | `15` | max weapon crates on the field |
| `/maze_max N` | `25` | max maze dimension (cells) that `/maze` may request |

Game-side limits are per room process and reset when the room is reaped.

## Logs and crash forensics

- **Manager stdout:** `docker compose logs -f manager` — API requests
  (`POST /api/rooms …`), room lifecycle (`room ABC123 created on port 7900`,
  `room ABC123 killed: idle`, exits) and each room's stdout/stderr prefixed with
  `[room ABC123]`.
- **Per-room files:** `/app/roomlogs/<CODE>.log` inside the manager container,
  persisted in the `ballistic-labyrinth_room-logs` Docker volume:

  ```bash
  docker exec ballistic-labyrinth-manager-1 ls /app/roomlogs
  docker exec ballistic-labyrinth-manager-1 tail -100 /app/roomlogs/ABC123.log
  ```

- **`BLTRACE` breadcrumbs:** the server binary prints lifecycle markers
  (`BLTRACE place_pawns …`, `BLTRACE start_ingame …`, `BLTRACE peer_connected …`,
  `BLTRACE tank_die …`, …) into the room log. When a room process segfaults, the
  last `BLTRACE` lines before `room <CODE> exited (…)` tell you which phase died.
- **OP password:** each room prints a line `OP_PASSWORD: …` at the top of its log —
  needed for the passworded `/op` command (see `docs/COMMANDS.md`). Treat room
  logs as sensitive.

## Performance & capacity

- One room ≈ one headless Godot process. Rooms with several bots cost
  **roughly one CPU core each** (bot pathfinding is rate-limited to 15 Hz per bot;
  see `AI_TICKS` in `ingame/controllers/bot_controller/bot_controller.gd`).
  Size the host for `MAX_ROOMS` × ~1 core worst case, far less in practice.
- The web client download is ~39 MB wasm + ~11 MB pck on first load (compressed by
  Caddy `zstd`/`gzip`); subsequent loads come from browser cache.
- Room processes are only spawned when someone presses **Create Room** — idle
  instances cost nothing.

## Troubleshooting

**A room everyone left is gone 15 minutes later.**
Working as intended: the manager reaps rooms with zero connected players after
`IDLE_TIMEOUT_MS` (15 min). The log shows `room <CODE> killed: idle`. Create a new
room.

**Everyone was dropped after a deploy/restart.**
Stopping the manager container SIGKILLs all room processes
(`manager shutdown (SIGTERM), killing N room processes`). Plan deploys for when no
matches are running, or warn players first. `docker compose restart manager` has
the same effect — restart only `web` when you can.

**"Room not found" right after creating one / join hangs then fails.**
The room process gets ~6 s to boot (`CONNECT_RETRY_MS × CONNECT_RETRY_MAX`). On an
overloaded host, first joins can time out with a `504`; retry. Check
`docker compose logs manager` for `room <CODE> created on port …` and crashes.

**Browser tab throttling / a player "lags out" in a background tab.**
Browsers aggressively throttle timers and rAF in hidden tabs, which can stall a
web-export Godot client. Players should keep the game tab **visible** during
matches. Note this is purely client-side: the room's simulation runs on the
dedicated Godot server, so the host closing their browser never ends the room —
hosting just migrates to the next player.

**First load takes very long in automation/VMs but is fine for real users.**
Headless browsers and VMs without a GPU fall back to SwiftShader (software WebGL);
shader warmup can take up to ~60 s and headless screenshots during that window are
unreliable. Real users on hardware GPUs load in seconds. Don't panic-test the
deploy with a headless browser and judge it by the first screenshot.

**`docker compose up` fails because `build/web` or `build/server` is missing.**
Both directories are git-ignored. Export the game first — see
[Rebuilding the game](#rebuilding-the-game).

**Where are the logs again?**
`docker compose logs -f manager` (live, all rooms), and per-room files at
`/app/roomlogs/<CODE>.log` (persisted in the `room-logs` volume, survives
`docker compose down`, removed only by `docker compose down -v`).

**API returns `429 too_many_rooms`.**
24 rooms (`MAX_ROOMS`) are already running. Wait for idle reaping, or raise the
constant in `manager/manager.js` and rebuild — mind the CPU budget.
