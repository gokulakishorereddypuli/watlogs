'use strict';

/* ════════════════════════════════════════════════════
   API  – Client-side store backed by server JSON files.
   Reads are synchronous (from in-memory cache loaded at startup).
   Writes update the cache immediately and async-persist to the server.
   Sessions are managed via HTTP cookies (no localStorage).
════════════════════════════════════════════════════ */
const API = (() => {
  /* Map internal table key → server endpoint segment */
  const ENDPOINT = {
    users:         'users',
    sessions:      'sessions',
    login_history: 'loginhistory',
    checkins:      'checkincheckouthistory',
    lookup:        'config'
  };

  const _cache = {};

  async function _get(table) {
    try {
      const r = await fetch('/api/data/' + ENDPOINT[table]);
      if (!r.ok) throw new Error(r.status);
      return await r.json();
    } catch (e) {
      console.warn('[API] Read failed for', table, e);
      return table === 'lookup' ? {} : [];
    }
  }

  function _put(table, data) {
    fetch('/api/data/' + ENDPOINT[table], {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    }).catch(e => {
      console.error('[API] Write failed for', table, e);
      // Retry once after a short delay
      setTimeout(() => {
        fetch('/api/data/' + ENDPOINT[table], {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(data)
        }).catch(e2 => console.error('[API] Retry write also failed for', table, e2));
      }, 2000);
    });
  }

  return {
    /** Load all tables into the in-memory cache from the server. */
    async init() {
      const tables  = Object.keys(ENDPOINT);
      const results = await Promise.all(tables.map(t => _get(t)));
      tables.forEach((t, i) => { _cache[t] = results[i]; });
    },

    /** Synchronous read from cache (available after init()). */
    all(table) {
      return _cache[table] ?? (table === 'lookup' ? {} : []);
    },

    /** Write data to cache and async-persist to the server. */
    save(table, data) {
      _cache[table] = data;
      _put(table, data);
    },

    /* ── Cookie-based session management ───────────────────────────────── */
    async getSession() {
      try {
        const r = await fetch('/api/session');
        const d = await r.json();
        return d.sid || null;
      } catch (e) {
        console.warn('[API] getSession failed', e);
        return null;
      }
    },

    async setSession(sid) {
      try {
        await fetch('/api/session', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ sid })
        });
      } catch (e) {
        console.warn('[API] setSession failed', e);
      }
    },

    async clearSession() {
      try {
        await fetch('/api/session', { method: 'DELETE' });
      } catch (e) {
        console.warn('[API] clearSession failed', e);
      }
    }
  };
})();
