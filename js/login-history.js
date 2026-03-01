'use strict';

window.LoginHistoryStore = {
  insert: entry => DB.insert(T.hist,entry),
  findActiveBySessionId: sessionId => DB.findOne(T.hist,h=>h.sessionId===sessionId&&h.status==='logged_in'),
  update: (id,patch) => DB.update(T.hist,id,patch)
};
