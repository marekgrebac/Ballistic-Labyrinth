# Commands & Keybindings

Reference for the in-game chat console and keyboard shortcuts. All of this lives
in the chat window: press `Enter` (or `Y` / `C`) to focus the input, type a
command starting with `/`, press `Enter` again to run it — focus returns to the
game automatically. `Esc` unfocuses without sending.

Syntax conventions:

- Arguments in quotes are optional but accepted: `/maze "10 25 8 25"` and
  `/maze 10 25 8 25` both work (args are joined internally).
- **Target selector flags** (used by several commands):
  `=s <sid>` / `==sid <sid>` pick a session id, `=n <name>` / `==name <name>` /
  `=u <name>` pick a player by exact username, `=c <n>` / `==count <n>` mean
  "this many" (for bulk bot removal).
- Some destructive commands ask for confirmation — type `yes` as the next command.
- Unknown or forbidden commands answer with `command not found` (permission
  failures are intentionally indistinguishable).

## Who may run what

| Level | Meaning |
| --- | --- |
| everyone | any connected player |
| host | the room's `op` player: first joiner, or whoever received host via migration/`/makehost`. OP commands are verified server-side. |

`/help` only lists commands you are actually allowed to run. Finding session ids:
`/get_sessions` prints every session with its encoded **sid** — bots look like
`ai#1`, `ai#2`, … and the server itself is `#HOST`.

## Commands for everyone

| Command (aliases) | Syntax | Notes |
| --- | --- | --- |
| `/help` | `/help [command]` | list available commands, or describe one |
| `/help_chat` (`/chat`, `/chat_help`) | | chat window shortcuts cheat-sheet |
| `/help_controls` | | tank controls cheat-sheet |
| `/get` | `/get <attr> [sid\|=s sid\|=u name]` | read an attribute from yourself or another session (see attribute aliases below) |
| `/set` | `/set <attr> <value>` | change **your own** attributes; `admin`, `kills` and `score` are refused. Example: `/set color "1 0 0"` |
| `/get_sessions` (`/get_session`, `/get_sid`, `/get_s`) | `/get_sessions [attr]` | dump all sessions, or one attribute across all sessions |
| `/disconnect` (`/leave`) | | leave the room (asks for `yes` confirmation) |
| `/chat_resize` | `/chat_resize <px>` | resize chat font (local preference) |
| `/op` (`/master`) | `/op <true\|false> <sid> <password>` | legacy passworded op grant. The password is printed as `OP_PASSWORD: …` at the top of the room's log file and **changes after every successful use**. Hidden from `/help`; normally you never need this because the first joiner already is host. |

## Host-only commands (op)

Round control:

| Command (aliases) | Syntax | Notes |
| --- | --- | --- |
| `/start` (`/start_game`, `/play`) | | start the round (same as the *Start Game* button) |
| `/restart` (`/restart_game`, `/restart_ingame`) | | restart the current round immediately |
| `/end_game` (`/close_game`, `/end_ingame`, `/close_ingame`) | | end the match, everyone back to lobby |
| `/pause` (`/p`) | `/pause [true\|false]` | pause/resume (no arg = toggle) |

Room setup:

| Command (aliases) | Syntax | Notes |
| --- | --- | --- |
| `/bot` (`/ai`) | `/bot add [n]` | add n bots (default 1, cap `/bot_max`, default 5) |
| | `/bot delete =c <n>` | remove n bots |
| | `/bot delete =s <sid>` | remove one bot by sid (`ai#…` from `/get_sessions`); `=n <name>` also works |
| | `/bot set =s <sid> "<trait>" <value>` | set a bot personality trait; unknown names print the valid list. Note: bots start with an **empty** trait dictionary in this build, so this is expected to reply "nonexistent trait" — it is a hook for future bot personality work |
| | `/bot enable` / `/bot disable` | freeze/unfreeze all bot AI (only while a round is loaded) |
| | `/bot random [seed]` | re-randomize all bot colors (`/bot rand`, `/bot rng` …) |
| `/crate` (`/powerup`, `/weapon`) | `/crate add [n]` | spawn n random weapon crates (`"bulk"`), cap `/crate_max` (default 15) |
| | `/crate add bulk <n>` | same, explicit |
| | `/crate add <laser\|rocket\|trap> [n]` | spawn a specific crate type |
| | `/crate delete [n]` | remove crates |
| `/maze` (`/maze_set`, `/maze_size`, `/maze_set_size`, `/set_maze_size`) | `/maze <minW> <maxW> <minH> <maxH>` | sets the random maze-size range; **applies from the next round**. Commas/quotes optional. Every value must be ≥1 and ≤ `/maze_max` (default 25); min must be ≤ max. Prints confirmation. |
| `/bot_max` (`/max_bot`) | `/bot_max <n>` | raise/lower the bot cap |
| `/crate_max` (`/max_crate`) | `/crate_max <n>` | raise/lower the crate cap |
| `/maze_max` (`/max_maze`) | `/maze_max <cells>` | raise/lower the `/maze` hard limit |

Players & moderation:

| Command (aliases) | Syntax | Notes |
| --- | --- | --- |
| `/makehost` (`/host`, `/transfer_host`) | `/makehost <username>` | transfer host to another player. Usernames are **not unique** — the first case-insensitive match wins, so pick exact names (you lose op *and* admin immediately; a chat notice is broadcast) |
| `/admin` | `/admin <true\|false> <sid>` | grant/revoke admin for a player (cannot be used on the op session) |
| `/mute` | `/mute <true\|false> <sid>` | silence/unsilence a player's chat (cannot mute the op) |
| `/assign` | `/assign <attr> <value> =s <sid>` | modify any attribute of any session **except** `admin`; `=n <name>` works too. On the dedicated server the target flag is effectively mandatory (without it, the command targets the server itself and does nothing) |
| `/purge` (`/clear_chat`, `/clearchat`) | | clear chat window + history for **everyone** |
| `/toggle_ingame_states` (`/ingame_state`) | `/toggle_ingame_states [true\|false]` | log round state changes (STOPPED/ANIMATING/WAITING_BEFORE_SYNC/FINISHED) into the room log — server-side debugging |

### Attribute aliases (for `/get`, `/set`, `/assign`)

| Attribute | Aliases | Value format |
| --- | --- | --- |
| `name` | `username`, `user`, `n`, `u` | text |
| `admin` | `is_admin`, `a` | `true`/`false` (only via `/admin`, `/op`) |
| `color` | `colour`, `rgb`, `c` | `"r g b"` floats 0–1, e.g. `"1 0.2 0.2"` |
| `kills` | `kill`, `k` | integer (host-only to change) |
| `score` | `win`, `wins`, `s`, `w` | integer (host-only to change) |

## Examples

```text
/bot add 3                     three bots join the lobby
/bot delete =c 2               remove two of them
/bot random                    re-roll all bot colors
/maze 10 25 8 25               bigger, more varied mazes from next round
/crate add rocket 2            two rocket crates on the field
/mute true 4BX                 mute player with sid 4BX
/assign name "Tanklord" =s 4BX rename a player
/makehost Tanklord             hand over the room
```

## Keybindings

Everyone:

| Keys | Action |
| --- | --- |
| `W` / `↑` | drive forward |
| `S` / `↓` | drive backward |
| `A` / `←` | rotate counterclockwise |
| `D` / `→` | rotate clockwise |
| `Shift` (hold) | drift |
| `Space` / `Q` | shoot |
| `Enter` / `Y` / `C` | focus chat input |
| `Enter` (in chat) | send message/command, unfocus |
| `Esc` (in chat) | unfocus without sending |
| `Shift+M` | chat window follows the mouse (move mode, toggle) |
| `Shift+R` | chat window resize mode (toggle) |
| `Shift+H` | hide/show the chat window |
| `L` | show/hide the lobby overlay |
| `Tab` (hold) | translucent leaderboard: PLAYER, KILLS, DEATHS, K/D, SCORE, PING (refreshes every second; bots show `bot` instead of ping) |

Host only (during a round):

| Keys | Action |
| --- | --- |
| `P` / `Esc` | pause menu (Resume / End Game — pauses the room for everyone) |
| `Shift+T` | teleport your tank to the cursor |
| `Shift+I` | toggle invincibility |
| `Shift+N` | toggle noclip |

