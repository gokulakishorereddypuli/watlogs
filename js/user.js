'use strict';

window.UserStore = {
  findById: id => DB.findId(T.users,id),
  findByUsername: username => DB.findOne(T.users,u=>u.username.toLowerCase()===String(username||'').toLowerCase()),
  findByEmail: email => DB.findOne(T.users,u=>u.email.toLowerCase()===String(email||'').toLowerCase()),
  insert: user => DB.insert(T.users,user),
  update: (id,patch) => DB.update(T.users,id,patch)
};
