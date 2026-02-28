'use strict';

/* ════════════════════════════════════════════════════
   JSON-DB  – Seeds localStorage from JSON files on first run.
   Replaces hard-coded bootstrap values with file-based defaults.
════════════════════════════════════════════════════ */
const JsonDB = (() => {
  // Resolve path to DB/ folder regardless of which portal loaded this script
  const _base = /\/(admin|superadmin|user)\//.test(window.location.pathname)
    ? '../DB/' : 'DB/';

  async function _fetchJson(file) {
    try {
      const r = await fetch(_base + file);
      if (!r.ok) return null;
      return await r.json();
    } catch (e) {
      console.warn('[JsonDB] Failed to load', file, e);
      return null;
    }
  }

  return {
    /**
     * Seeds localStorage tables from JSON files if the table is empty.
     * Must be awaited before any DB reads during bootstrap.
     */
    async init() {
      const PFX = 'wl_';

      if (!localStorage.getItem(PFX + 'users')) {
        const users = await _fetchJson('users.json');
        if (users) localStorage.setItem(PFX + 'users', JSON.stringify(users));
      }

      if (!localStorage.getItem(PFX + 'lookup')) {
        const config = await _fetchJson('config.json');
        if (config) localStorage.setItem(PFX + 'lookup', JSON.stringify(config));
      }

      if (!localStorage.getItem(PFX + 'login_history')) {
        const hist = await _fetchJson('loginhistory.json');
        if (hist) localStorage.setItem(PFX + 'login_history', JSON.stringify(hist));
      }

      if (!localStorage.getItem(PFX + 'checkins')) {
        const ci = await _fetchJson('checkincheckouthistory.json');
        if (ci) localStorage.setItem(PFX + 'checkins', JSON.stringify(ci));
      }
    }
  };
})();
