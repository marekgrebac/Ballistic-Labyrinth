// Ballistic Labyrinth room manager
// - HTTP API: POST /api/rooms (create), GET /api/rooms/<code> (exists), GET /healthz
// - WS tunnel: /ws/<code> -> 127.0.0.1:<roomPort> (raw TCP pipe after Upgrade)
// - Spawns one headless Godot dedicated server per room (BL_PORT env).
// Plain Node.js, no dependencies.
const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const LOG_DIR = '/app/roomlogs';
try { fs.mkdirSync(LOG_DIR, { recursive: true }); } catch {}

const API_PORT = 8899;
const ROOM_PORT_BASE = 7900;
const ROOM_PORT_MAX = 8090;
const MAX_ROOMS = 24;
const IDLE_TIMEOUT_MS = 15 * 60 * 1000;
const CONNECT_RETRY_MS = 300;
const CONNECT_RETRY_MAX = 20; // ~6s for a room process to boot
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ123456789';
const CODE_LEN = 6;

const rooms = new Map(); // code -> { code, port, proc, sockets:Set, lastActive }

function makeCode() {
  for (let tries = 0; tries < 50; tries++) {
    let s = '';
    for (let i = 0; i < CODE_LEN; i++) {
      s += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
    }
    if (!rooms.has(s)) return s;
  }
  return null;
}

function findPort() {
  const used = new Set([...rooms.values()].map((r) => r.port));
  for (let p = ROOM_PORT_BASE; p <= ROOM_PORT_MAX; p++) if (!used.has(p)) return p;
  return null;
}

function createRoom(code) {
  const port = findPort();
  if (port == null) return null;
  const proc = spawn('/app/server', ['--headless'], {
    env: { ...process.env, BL_PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const room = { code, port, proc, sockets: new Set(), lastActive: Date.now() };
  const fileLog = fs.createWriteStream(path.join(LOG_DIR, `${code}.log`), { flags: 'a' });
  const onData = (d) => { process.stdout.write(`[room ${code}] ${d}`); fileLog.write(d); };
  proc.stdout.on('data', onData);
  proc.stderr.on('data', onData);
  proc.on('exit', (c) => {
    console.log(`room ${code} exited (${c})`);
    fileLog.end();
    const current = rooms.get(code);
    if (current && current.proc === proc) rooms.delete(code);
  });
  rooms.set(code, room);
  console.log(`room ${code} created on port ${port}`);
  return room;
}

function killRoom(room, why) {
  console.log(`room ${room.code} killed: ${why}`);
  try { room.proc.kill('SIGTERM'); } catch {}
  rooms.delete(room.code);
}

function sendJson(res, status, obj) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(obj));
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname.startsWith('/api/')) console.log(`${req.method} ${url.pathname} from ${req.headers['user-agent']}`);
  if (req.method === 'GET' && url.pathname === '/healthz') {
    sendJson(res, 200, { ok: true, rooms: rooms.size });
    return;
  }
  if (req.method === 'POST' && url.pathname === '/api/rooms') {
    if (rooms.size >= MAX_ROOMS) return sendJson(res, 429, { error: 'too_many_rooms' });
    const code = makeCode();
    const room = code && createRoom(code);
    if (!room) return sendJson(res, 503, { error: 'no_capacity' });
    return sendJson(res, 201, { code: room.code });
  }
  const m = url.pathname.match(/^\/api\/rooms\/([A-Za-z0-9]{4,12})$/);
  if (req.method === 'GET' && m) {
    const code = m[1].toUpperCase();
    if (rooms.has(code)) return sendJson(res, 200, { code });
    return sendJson(res, 404, { error: 'not_found' });
  }
  sendJson(res, 404, { error: 'not_found' });
});

function connectUpstream(room, attempt, cb) {
  const upstream = net.connect(room.port, '127.0.0.1', () => cb(null, upstream));
  upstream.once('error', (err) => {
    if (attempt < CONNECT_RETRY_MAX && rooms.get(room.code) === room) {
      setTimeout(() => connectUpstream(room, attempt + 1, cb), CONNECT_RETRY_MS);
    } else {
      cb(err);
    }
  });
}

server.on('upgrade', (req, clientSocket, head) => {
  const m = req.url.match(/^\/ws\/([A-Za-z0-9]{4,12})\/?$/);
  const code = m && m[1].toUpperCase();
  const room = code && rooms.get(code);
  if (!room) {
    clientSocket.write('HTTP/1.1 404 Not Found\r\n\r\n');
    clientSocket.destroy();
    return;
  }
  connectUpstream(room, 0, (err, upstream) => {
    if (err) {
      clientSocket.write('HTTP/1.1 504 Gateway Timeout\r\n\r\n');
      clientSocket.destroy();
      return;
    }
    room.lastActive = Date.now();
    room.sockets.add(upstream);
    upstream.write(`${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`);
    for (const [k, v] of Object.entries(req.headers)) upstream.write(`${k}: ${v}\r\n`);
    upstream.write('\r\n');
    if (head && head.length) upstream.write(head);
    upstream.pipe(clientSocket);
    clientSocket.pipe(upstream);
    const cleanup = () => {
      room.sockets.delete(upstream);
      room.lastActive = Date.now();
      upstream.destroy();
      clientSocket.destroy();
    };
    upstream.on('error', cleanup);
    upstream.on('close', cleanup);
    clientSocket.on('error', cleanup);
    clientSocket.on('close', cleanup);
  });
});

setInterval(() => {
  const now = Date.now();
  for (const room of rooms.values()) {
    if (room.sockets.size === 0 && now - room.lastActive > IDLE_TIMEOUT_MS) {
      killRoom(room, 'idle');
    }
  }
}, 30 * 1000);

// per-room resource stats every 30s: CPU (from /proc), RSS, live sockets
function sampleRoomStats() {
  for (const room of rooms.values()) {
    try {
      const stat = fs.readFileSync(`/proc/${room.proc.pid}/stat`, 'utf8');
      const parts = stat.split(' ');
      const utime = Number(parts[13]), stime = Number(parts[14]);
      const ticks = utime + stime;
      const rss = Number(fs.readFileSync(`/proc/${room.proc.pid}/statm`, 'utf8').split(' ')[1]) * 4096;
      if (room.lastTicks !== undefined) {
        const cpu = ((ticks - room.lastTicks) / 30);
        console.log(`[room ${room.code}] stats cpu=${cpu.toFixed(1)}% rss=${(rss / 1048576).toFixed(0)}MB conns=${room.sockets.size}`);
        room.lastWarn = cpu > 150 ? `room ${room.code} hot: ${cpu.toFixed(0)}% cpu` : '';
      }
      room.lastTicks = ticks;
    } catch {}
  }
}
setInterval(sampleRoomStats, 30 * 1000);

function shutdown(sig) {
  console.log(`manager shutdown (${sig}), killing ${rooms.size} room processes`);
  for (const room of rooms.values()) {
    try { room.proc.kill('SIGKILL'); } catch {}
  }
  process.exit(0);
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

server.listen(API_PORT, '0.0.0.0', () => {
  console.log(`room manager listening on :${API_PORT}`);
});
