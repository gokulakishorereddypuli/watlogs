'use strict';

const http = require('http');
const fs   = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const ROOT = __dirname;
const DB_DIR = path.join(ROOT, 'DB');

/* ── Allowed table names → file names (strict allow-list prevents path traversal) ── */
const TABLE_FILES = {
  users:                    'users.json',
  sessions:                 'sessions.json',
  loginhistory:             'loginhistory.json',
  checkincheckouthistory:   'checkincheckouthistory.json',
  config:                   'config.json'
};

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
  '.js':   'application/javascript; charset=utf-8',
  '.json': 'application/json',
  '.png':  'image/png',
  '.ico':  'image/x-icon',
  '.svg':  'image/svg+xml',
};

/* ── Helpers ────────────────────────────────────────────────────────────────── */
function parseCookies(str) {
  const out = {};
  (str || '').split(';').forEach(pair => {
    const idx = pair.indexOf('=');
    if (idx < 0) return;
    const k = pair.slice(0, idx).trim();
    const v = pair.slice(idx + 1).trim();
    if (k) out[k] = decodeURIComponent(v);
  });
  return out;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try { resolve(JSON.parse(body)); }
      catch (e) { reject(e); }
    });
    req.on('error', reject);
  });
}

function readTableFile(table) {
  const file = path.join(DB_DIR, TABLE_FILES[table]);
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return table === 'config' ? {} : [];
  }
}

function writeTableFile(table, data) {
  const file = path.join(DB_DIR, TABLE_FILES[table]);
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n', 'utf8');
}

function json(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

/* ── Request handler ────────────────────────────────────────────────────────── */
const server = http.createServer(async (req, res) => {
  const url      = new URL(req.url, `http://localhost`);
  const pathname = url.pathname;
  const cookies  = parseCookies(req.headers.cookie);

  /* ── API: GET /api/data/:table ─────────────────────────────────────────── */
  if (req.method === 'GET' && pathname.startsWith('/api/data/')) {
    const table = pathname.slice('/api/data/'.length);
    if (!TABLE_FILES[table]) return json(res, 404, { error: 'Unknown table' });
    return json(res, 200, readTableFile(table));
  }

  /* ── API: PUT /api/data/:table ─────────────────────────────────────────── */
  if (req.method === 'PUT' && pathname.startsWith('/api/data/')) {
    const table = pathname.slice('/api/data/'.length);
    if (!TABLE_FILES[table]) return json(res, 404, { error: 'Unknown table' });
    try {
      const body = await readBody(req);
      writeTableFile(table, body);
      return json(res, 200, { ok: true });
    } catch (_) {
      return json(res, 400, { error: 'Invalid JSON body' });
    }
  }

  /* ── API: GET /api/session ─────────────────────────────────────────────── */
  if (req.method === 'GET' && pathname === '/api/session') {
    return json(res, 200, { sid: cookies.wl_sid || null });
  }

  /* ── API: POST /api/session ────────────────────────────────────────────── */
  if (req.method === 'POST' && pathname === '/api/session') {
    try {
      const body = await readBody(req);
      const sid  = String(body.sid || '').replace(/[^\w-]/g, ''); // sanitize
      if (sid) {
        res.setHeader('Set-Cookie',
          `wl_sid=${sid}; HttpOnly; SameSite=Strict; Path=/`);
      }
      return json(res, 200, { ok: true });
    } catch (_) {
      return json(res, 400, { error: 'Invalid JSON body' });
    }
  }

  /* ── API: DELETE /api/session ──────────────────────────────────────────── */
  if (req.method === 'DELETE' && pathname === '/api/session') {
    res.setHeader('Set-Cookie',
      'wl_sid=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0');
    return json(res, 200, { ok: true });
  }

  /* ── Static file serving ────────────────────────────────────────────────── */

  // Block direct access to the DB folder
  if (pathname.startsWith('/DB/') || pathname === '/DB') {
    res.writeHead(403); res.end('Forbidden'); return;
  }

  let filePath = path.join(ROOT, pathname === '/' ? 'index.html' : pathname);
  // Serve index.html for bare directory paths (e.g. /admin, /admin/)
  if (!path.extname(filePath)) {
    filePath = path.join(filePath, 'index.html');
  }

  // Security: ensure resolved path stays within ROOT
  const realRoot = fs.realpathSync(ROOT);
  let realFile;
  try { realFile = fs.realpathSync(filePath); } catch (_) { realFile = filePath; }
  if (!realFile.startsWith(realRoot + path.sep) && realFile !== realRoot) {
    res.writeHead(403); res.end('Forbidden'); return;
  }

  const ext  = path.extname(filePath).toLowerCase();
  const mime = MIME[ext] || 'application/octet-stream';
  try {
    const content = fs.readFileSync(filePath);
    res.writeHead(200, { 'Content-Type': mime });
    res.end(content);
  } catch (_) {
    res.writeHead(404); res.end('Not found');
  }
});

server.listen(PORT, () => {
  console.log(`WatLogs server running → http://localhost:${PORT}`);
});
