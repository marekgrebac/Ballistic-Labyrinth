# Ballistic Labyrinth — Self-Hosted Web Edition

A 2D multiplayer tank maze game (Tank-Trouble-style) that runs **entirely in the browser**, with rooms hosted on **your own server**.

This is a heavily modified, self-hosted fork of
[Wizzoplit273/Ballistic-Labyrinth](https://github.com/Wizzoplit273/Ballistic-Labyrinth)
(Godot, MIT). The original ENet/UDP multiplayer was replaced with WebSockets so the
game can be played from any browser, and the whole stack — web client, room API and
game traffic — is served behind **a single port**, designed to sit behind a
Cloudflare Tunnel.

![Godot 4.7.1](https://img.shields.io/badge/Godot-4.7.1-478CBF)
![Docker Compose](https://img.shields.io/badge/deploy-Docker%20Compose-2496ED)
![License MIT](https://img.shields.io/badge/license-MIT-green)
![Self hosted](https://img.shields.io/badge/hosting-self--hosted-orange)

## Screenshots

> **TODO:** add screenshots of the home screen, lobby and in-game action.
> The upstream project page has representative screenshots:
> https://github.com/Wizzoplit273/Ballistic-Labyrinth

## For players

1. Open the game URL, e.g. `https://game.example.com/`.
2. Pick a **username** and a **color** — both save automatically as you type.
3. Press **Create Room** and share the link (`https://game.example.com/?room=ABC123`)
   or just the 6-character room code with your friends. Or paste a code into the
   **ROOM ID** field and press **Join Room**.
4. The first person in a room becomes its **host**: they get the *Start Game* and
   *Close Room* buttons plus host chat commands (`/bot add 3`, `/maze`, `/restart`, …).
   If the host leaves, hosting passes to the longest-present remaining player.

### Controls

| Action | Keys |
| --- | --- |
| Drive | `WASD` or arrow keys |
| Drift | hold `Shift` |
| Shoot | `Space` or `Q` |
| Chat | `Enter` (or `Y` / `C`) to open, `Enter` to send, `Esc` to unfocus |
| Leaderboard | hold `Tab` (kills, deaths, K/D, score, ping) |
| Lobby overlay | `L` |
| Chat window | `Shift+M` move, `Shift+R` resize, `Shift+H` hide |

Host-only fun: `P`/`Esc` pause menu, `Shift+T` teleport, `Shift+I` invincibility,
`Shift+N` noclip.

## For hosts (run your own)

```bash
cd /root/Ballistic-Labyrinth
docker compose up -d --build
```

Then point a Cloudflare Tunnel public hostname at `http://localhost:8137` — that is
the only port the stack publishes. Full instructions, tunnel config and
troubleshooting: **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)**.

## Features

- **Browser-native multiplayer** — Godot 4.7.1 web export (wasm + threads) talking
  WebSockets; no plugins, no UDP, no port forwarding for players.
- **Rooms on demand** — every room is its own headless Godot dedicated-server
  process, spawned by a small Node.js room manager; 6-character share codes and
  `?room=CODE` auto-join links.
- **Real gameplay** — procedurally generated mazes, ricocheting bullets, bots,
  weapon crates (laser, rocket, trap), rounds with a top-left `ROUND n` indicator,
  spectate window when joining mid-round.
- **Lobby & chat** — colored player list, in-game chat with BBCode colors,
  command console (`/help`), translucent `Tab` leaderboard with live ping.
- **Host administration** — host migration when the host leaves, `/makehost`,
  bots, maze size, crates, mute, pause, chat purge, room close.

## Documentation

| Doc | Contents |
| --- | --- |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Install, Cloudflare Tunnel setup, rebuilds, tuning, troubleshooting |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the pieces fit: Caddy, room manager, Godot servers, protocols |
| [docs/COMMANDS.md](docs/COMMANDS.md) | Full chat/console command reference and keybindings |
| [docs/CHANGELOG-SELFHOST.md](docs/CHANGELOG-SELFHOST.md) | Everything this fork changed relative to upstream |

## Credits & license

- Original game: **[Wizzoplit273](https://github.com/Wizzoplit273)** —
  [Ballistic-Labyrinth](https://github.com/Wizzoplit273/Ballistic-Labyrinth)
  (also on itch.io: [full](https://wizzoplit273.itch.io/ballistic-labyrinth),
  [lite](https://wizzoplit273.itch.io/ballistic-labyrinth-lite)).
- Self-hosting fork: WebSocket networking, room manager, Docker packaging, web UI
  and stability fixes by the repo owner.
- License: [MIT](LICENSE) (same as upstream — the `LICENSE` file is retained).
