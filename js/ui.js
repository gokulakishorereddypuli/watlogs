'use strict';

/* ════════════════════════════════════════════════════
   NAVIGATION DEFINITIONS
════════════════════════════════════════════════════ */
const NAV = {
  user:[
    {v:'dashboard',icon:'🏠',label:'Dashboard'},
    {v:'checkins', icon:'⏱️',label:'Check-In / Check-Out'},
    {v:'profile',  icon:'👤',label:'My Profile'},
  ],
  admin:[
    {v:'dashboard',icon:'🏠',label:'Dashboard'},
    {v:'checkins', icon:'⏱️',label:'Check-In / Check-Out'},
    {v:'profile',  icon:'👤',label:'My Profile'},
    {section:'Admin'},
    {v:'users',    icon:'👥',label:'User Management'},
    {v:'pending-approvals',icon:'⏳',label:'Pending Approvals'},
  ],
  superadmin:[
    {v:'dashboard',   icon:'🏠',label:'Dashboard'},
    {v:'checkins',    icon:'⏱️',label:'Check-In / Check-Out'},
    {v:'profile',     icon:'👤',label:'My Profile'},
    {section:'Admin'},
    {v:'users',       icon:'👥',label:'User Management'},
    {v:'pending-approvals',icon:'⏳',label:'Pending Approvals'},
    {v:'all-hist',    icon:'📊',label:'Login History'},
    {section:'Super Admin'},
    {v:'bulk-import', icon:'📥',label:'Bulk User Import'},
    {v:'create-admin',icon:'🛡️',label:'Create Admin'},
    {v:'json-viewer', icon:'📁',label:'JSON DB Viewer'},
    {v:'lookup',      icon:'⚙️',label:'System Settings'},
  ]
};

let _timerInterval=null;
let _currentView=null;
let _confirmCb=null;

/* ════════════════════════════════════════════════════
   UI HELPERS
════════════════════════════════════════════════════ */
function showAlert(id,msg,type='error'){
  const el=document.getElementById(id);
  if(!el)return;
  el.innerHTML=`<div class="alert alert-${type}">${U.esc(msg)}</div>`;
  setTimeout(()=>{ if(el) el.innerHTML=''; },5000);
}
function showConfirm(title,msg,onYes,danger=true){
  _confirmCb=onYes;
  document.getElementById('modal-root').innerHTML=`
    <div class="modal-overlay" onclick="if(event.target===this)closeModal()">
      <div class="modal-box">
        <h3>${U.esc(title)}</h3>
        <p>${U.esc(msg)}</p>
        <div class="modal-actions">
          <button class="btn btn-outline" onclick="closeModal()">Cancel</button>
          <button class="btn ${danger?'btn-danger':'btn-primary'}" onclick="runConfirm()">Confirm</button>
        </div>
      </div>
    </div>`;
}
function runConfirm(){ const cb=_confirmCb; _confirmCb=null; closeModal(); if(cb) cb(); }
function closeModal(){ document.getElementById('modal-root').innerHTML=''; _confirmCb=null; }

/* ════════════════════════════════════════════════════
   NAVIGATION
════════════════════════════════════════════════════ */
function buildSidebar(){
  const role=Auth.s.role;
  const items=NAV[role]||NAV.user;
  document.getElementById('sb-role-lbl').textContent=
    role==='superadmin'?'Super Admin Portal':role==='admin'?'Admin Portal':'User Portal';
  document.getElementById('sb-uname').textContent=Auth.s.user.legalName||Auth.s.username;
  document.getElementById('sb-urole').textContent=role;
  document.getElementById('sb-avatar').textContent=U.initials(Auth.s.user.legalName||Auth.s.username);
  const nav=document.getElementById('sb-nav');
  nav.innerHTML=items.map(item=>{
    if(item.section) return `<div class="nav-section">${U.esc(item.section)}</div>`;
    return `<div class="nav-item" data-view="${item.v}" onclick="showView('${item.v}')">
      <span>${item.icon}</span><span>${U.esc(item.label)}</span></div>`;
  }).join('');
}

function showView(v){
  _currentView=v;
  if(_timerInterval){clearInterval(_timerInterval);_timerInterval=null;}
  document.querySelectorAll('.nav-item').forEach(el=>el.classList.toggle('active',el.dataset.view===v));
  const mc=document.getElementById('main-content');
  switch(v){
    case 'dashboard':   mc.innerHTML=vDashboard(); break;
    case 'profile':     mc.innerHTML=vProfile(); break;
    case 'checkins':    mc.innerHTML=vCheckins(); startTimer(); break;
    case 'my-hist':     mc.innerHTML=vMyHist(); break;
    case 'users':       mc.innerHTML=vUsers(); break;
    case 'pending-approvals': mc.innerHTML=vPendingApprovals(); break;
    case 'all-hist':    mc.innerHTML=vAllHist(); break;
    case 'bulk-import': mc.innerHTML=vBulkImport(); break;
    case 'create-admin':mc.innerHTML=vCreateAdmin(); break;
    case 'json-viewer': mc.innerHTML=vJsonViewer('users'); break;
    case 'lookup':      mc.innerHTML=vLookup(); break;
    default:            mc.innerHTML=vDashboard();
  }
}

function loadApp(){
  autoCheckoutPrevDays();
  const lkp=DB.all(T.lkp);
  const appName=lkp.appName||'WatLogs';
  const role=Auth.s.role;
  const portalLabel=role==='superadmin'?'Super Admin':role==='admin'?'Admin':'User';
  document.title=`${appName} – ${portalLabel} Portal`;
  buildSidebar();
  showView('dashboard');
}

function doLogout(){
  showConfirm('Sign Out','Are you sure you want to sign out?',()=>{
    if(_timerInterval){clearInterval(_timerInterval);_timerInterval=null;}
    Auth.logout();
    window.location.href = window.AUTH_PATH || '../';
  });
}

/* ════════════════════════════════════════════════════
   VIEW: DASHBOARD
════════════════════════════════════════════════════ */
function sc(icon,label,val,color='var(--text)',raw=false){
  return `<div class="stat-card">
    <div class="stat-icon">${icon}</div>
    <div class="stat-label">${U.esc(label)}</div>
    <div class="stat-value" style="color:${color}">${raw?val:U.esc(String(val))}</div>
  </div>`;
}

function vDashboard(){
  const {s}=Auth, role=s.role;
  const users=DB.all(T.users), hist=DB.all(T.hist), ci=DB.all(T.ci);
  const today=U.today();
  const myCI=ci.filter(c=>c.userId===s.userId);
  const todayCI=myCI.find(c=>new Date(c.checkinTime).toDateString()===today);
  const pending=users.filter(u=>u.status==='pending');

  let statsHtml='';
  if(role==='superadmin'){
    const todayLogins=hist.filter(h=>new Date(h.loginTime).toDateString()===today).length;
    statsHtml=`<div class="stats-grid">
      ${sc('👥','Total Users',users.length,'var(--primary)')}
      ${sc('✅','Active',users.filter(u=>u.status==='active').length,'var(--success)')}
      ${sc('🔒','Frozen',users.filter(u=>u.status==='frozen').length,'var(--info)')}
      ${sc('🛡️','Admins',users.filter(u=>u.role==='admin').length,'var(--warning)')}
      ${sc('📊','Today Logins',todayLogins)}
      ${sc('⏳','Pending Approvals',pending.length,'var(--warning)')}
    </div>`;
  } else if(role==='admin'){
    const regUsers=users.filter(u=>u.role==='user');
    statsHtml=`<div class="stats-grid">
      ${sc('👥','Total Users',regUsers.filter(u=>u.status!=='pending').length,'var(--primary)')}
      ${sc('✅','Active',regUsers.filter(u=>u.status==='active').length,'var(--success)')}
      ${sc('🔒','Frozen',regUsers.filter(u=>u.status==='frozen').length,'var(--info)')}
      ${sc('⏳','Pending Approvals',pending.length,'var(--warning)')}
    </div>`;
  } else {
    const totalMins=myCI.reduce((s,c)=>s+(c.duration||0),0);
    const todayMins=todayCI?(todayCI.duration||Math.round((new Date()-new Date(todayCI.checkinTime))/60000)):0;
    const checkedOutToday=todayCI&&todayCI.checkoutTime;
    statsHtml=`<div class="stats-grid">
      ${sc('🕐','Today',U.fmtDur(todayMins),'var(--primary)',true)}
      ${sc('⏱️','Total Hours',U.fmtDur(totalMins),'var(--success)',true)}
      ${sc('📋','CI Records',myCI.length)}
      ${sc('📅','Today Status',checkedOutToday?'Checked Out':todayCI?'Checked In':'Not Yet','var(--text)',true)}
    </div>`;
  }

  let recentHtml='';
  if(role==='superadmin'){
    const recent=hist.sort((a,b)=>new Date(b.loginTime)-new Date(a.loginTime)).slice(0,5);
    const rows=recent.length?recent.map(h=>{
      const dur=h.logoutTime?Math.round((new Date(h.logoutTime)-new Date(h.loginTime))/60000):null;
      return `<tr>
        <td><strong>${U.esc(h.username)}</strong></td>
        <td>${U.fmtDT(h.loginTime)}</td><td>${U.fmtDT(h.logoutTime)}</td>
        <td>${dur!==null?U.fmtDur(dur):'—'}</td>
        <td><code>${U.esc(h.ipAddress||'—')}</code></td>
        <td><span class="badge ${h.status==='logged_in'?'b-in':'b-out'}">${h.status==='logged_in'?'● Active':'● Ended'}</span></td>
      </tr>`;
    }).join(''):`<tr><td colspan="6" style="text-align:center;padding:24px;color:var(--muted)">No records yet</td></tr>`;
    recentHtml=`<div class="card">
      <div class="card-header">
        <h3>Recent Login Activity</h3>
        <button class="btn btn-sm btn-outline" onclick="showView('all-hist')">View All →</button>
      </div>
      <div class="tbl-wrap"><table><thead><tr>
        <th>User</th><th>Login</th><th>Logout</th><th>Duration</th><th>IP</th><th>Status</th>
      </tr></thead><tbody>${rows}</tbody></table></div>
    </div>`;
  }

  return `<div class="page-header">
    <h2>👋 Welcome, ${U.esc(s.user.legalName||s.username)}!</h2>
    <p>${new Date().toLocaleDateString('en-US',{weekday:'long',year:'numeric',month:'long',day:'numeric'})}
       · IP: <code>${U.esc(s.ipAddress||'—')}</code></p>
  </div>
  ${statsHtml}
  ${recentHtml}`;
}

/* ════════════════════════════════════════════════════
   VIEW: PROFILE
════════════════════════════════════════════════════ */
function vProfile(){
  const u=Auth.s.user;
  const role=Auth.s.role;
  const histHtml=role==='superadmin'?(()=>{
    const hist=DB.find(T.hist,h=>h.userId===u.id).sort((a,b)=>new Date(b.loginTime)-new Date(a.loginTime)).slice(0,15);
    const rows=hist.length?hist.map((h,i)=>{
      const dur=h.logoutTime?Math.round((new Date(h.logoutTime)-new Date(h.loginTime))/60000):null;
      return `<tr>
        <td class="text-muted">${hist.length-i}</td>
        <td>${U.fmtDT(h.loginTime)}</td><td>${U.fmtDT(h.logoutTime)}</td>
        <td>${dur!==null?U.fmtDur(dur):'—'}</td>
        <td><code>${U.esc(h.ipAddress||'—')}</code></td>
        <td><span class="badge ${h.status==='logged_in'?'b-in':'b-out'}">${h.status==='logged_in'?'● Active':'● Ended'}</span></td>
      </tr>`;
    }).join(''):`<tr><td colspan="6" style="text-align:center;padding:20px;color:var(--muted)">No history</td></tr>`;
    return `<div class="card">
      <div class="card-header"><h3>📍 Last Login History</h3></div>
      <div class="tbl-wrap"><table><thead><tr>
        <th>#</th><th>Login</th><th>Logout</th><th>Duration</th><th>IP</th><th>Status</th>
      </tr></thead><tbody>${rows}</tbody></table></div>
    </div>`;
  })():'';

  return `<div class="page-header"><h2>👤 My Profile</h2><p>Manage your personal information and security</p></div>
  <div id="prof-alert"></div>
  <div class="card">
    <div class="card-header"><h3>Personal Information</h3></div>
    <div class="grid-2">
      <div class="form-group"><label>Legal Name</label>
        <input class="form-control" id="p-name" value="${U.esc(u.legalName||'')}" placeholder="Full legal name"></div>
      <div class="form-group"><label>Username (read-only)</label>
        <input class="form-control" value="${U.esc(u.username)}" disabled style="opacity:.6"></div>
      <div class="form-group"><label>Email</label>
        <input type="email" class="form-control" id="p-email" value="${U.esc(u.email||'')}" placeholder="your@email.com"></div>
      <div class="form-group"><label>Contact Info</label>
        <input class="form-control" id="p-contact" value="${U.esc(u.contactInfo||'')}" placeholder="Phone or other contact"></div>
    </div>
    <button class="btn btn-primary" onclick="saveProfile()">💾 Save Changes</button>
  </div>
  <div class="card">
    <div class="card-header"><h3>Change Password</h3></div>
    <div class="grid-2">
      <div class="form-group"><label>Current Password</label>
        <input type="password" class="form-control" id="p-cpwd" placeholder="Current password"></div>
      <div></div>
      <div class="form-group"><label>New Password</label>
        <input type="password" class="form-control" id="p-npwd" placeholder="New password (min 6)"></div>
      <div class="form-group"><label>Confirm New Password</label>
        <input type="password" class="form-control" id="p-rpwd" placeholder="Repeat new password"></div>
    </div>
    <button class="btn btn-warning" onclick="changePassword()">🔑 Update Password</button>
  </div>
  ${histHtml}`;
}

/* ════════════════════════════════════════════════════
   VIEW: CHECK-IN / CHECK-OUT
════════════════════════════════════════════════════ */
function vCheckins(){
  const uid=Auth.s.userId;
  const today=U.today();
  const active=DB.findOne(T.ci,c=>c.userId===uid&&!c.checkoutTime);
  const todayDone=!active&&DB.findOne(T.ci,c=>c.userId===uid&&new Date(c.checkinTime).toDateString()===today&&c.checkoutTime);
  const minH=DB.all(T.lkp).minLoginHours||10, minM=minH*60;
  const recs=DB.find(T.ci,c=>c.userId===uid).sort((a,b)=>new Date(b.checkinTime)-new Date(a.checkinTime));
  const rows=recs.length?recs.map(c=>{
    const dur=c.duration??( c.checkoutTime?Math.round((new Date(c.checkoutTime)-new Date(c.checkinTime))/60000):null );
    const isAuto=c.autoCheckout||c.flagged, isShort=dur!==null&&dur<minM, isActive=!c.checkoutTime;
    const rowStyle=isAuto?'style="background:rgba(239,68,68,0.08)"':'';
    return `<tr ${rowStyle}>
      <td>${U.fmtD(c.checkinTime)}</td>
      <td>${U.fmtDT(c.checkinTime)}</td>
      <td>${c.checkoutTime?U.fmtDT(c.checkoutTime):'<span class="badge b-in">● Active</span>'}</td>
      <td>${dur!==null?U.fmtDur(dur):'—'}</td>
      <td>${isAuto?'<span class="badge b-flag">🚩 Auto Checkout</span>':isActive?'<span class="badge b-current">Active</span>':isShort?'<span class="badge b-short">Short</span>':'<span class="badge b-ok">Complete</span>'}</td>
    </tr>`;
  }).join(''):`<tr><td colspan="5" style="text-align:center;padding:24px;color:var(--muted)">No records yet</td></tr>`;

  return `<div class="page-header"><h2>⏱️ Check-In / Check-Out</h2>
    <p>Track daily attendance. Minimum session: <strong>${minH} hours</strong></p></div>
  <div class="card">
    <div class="ci-status ${active?'ci-in':'ci-out'}">
      <div class="ci-dot ${active?'':'off'}"></div>
      <div style="flex:1">
        <div style="font-weight:600">${active?'🟢 Currently Checked In':'⚪ Not Checked In'}</div>
        <div class="text-sm text-muted">${active?'Since '+U.fmtDT(active.checkinTime):'Check in to start tracking your time'}</div>
      </div>
      ${active?`<div><div id="ci-timer">00:00:00</div><div class="text-sm text-muted">elapsed</div></div>`:''}
    </div>
    ${active
      ?`<div id="ci-warn" class="alert alert-warning" style="display:none">
          ⚠️ You haven't reached the minimum ${minH}-hour threshold yet. You may still check out.
        </div>
        <button class="btn btn-danger" onclick="doCheckout()">🚪 Check Out</button>`
      :todayDone
        ?`<div class="alert alert-warning">✅ You have already completed your check-in for today. You can check in again tomorrow.</div>`
        :`<button class="btn btn-success" onclick="doCheckin()">✅ Check In</button>`}
  </div>
  <div class="card">
    <div class="card-header"><h3>📋 Attendance History</h3></div>
    <div class="tbl-wrap"><table><thead><tr>
      <th>Date</th><th>Check-In</th><th>Check-Out</th><th>Duration</th><th>Status</th>
    </tr></thead><tbody>${rows}</tbody></table></div>
  </div>`;
}

function startTimer(){
  const uid=Auth.s.userId;
  const active=DB.findOne(T.ci,c=>c.userId===uid&&!c.checkoutTime);
  if(!active)return;
  const minM=(DB.all(T.lkp).minLoginHours||10)*60;
  function tick(){
    const el=document.getElementById('ci-timer');
    const w=document.getElementById('ci-warn');
    if(!el){clearInterval(_timerInterval);return;}
    const elapsed=Math.floor((new Date()-new Date(active.checkinTime))/1000);
    el.textContent=U.fmtTimer(elapsed);
    if(w) w.style.display=Math.floor(elapsed/60)<minM?'flex':'none';
  }
  tick();
  _timerInterval=setInterval(tick,1000);
}

/* ════════════════════════════════════════════════════
   VIEW: MY LOGIN HISTORY
════════════════════════════════════════════════════ */
function vMyHist(){
  const hist=DB.find(T.hist,h=>h.userId===Auth.s.userId)
    .sort((a,b)=>new Date(b.loginTime)-new Date(a.loginTime));
  const rows=hist.length?hist.map((h,i)=>{
    const dur=h.logoutTime?Math.round((new Date(h.logoutTime)-new Date(h.loginTime))/60000):null;
    return `<tr>
      <td class="text-muted">${hist.length-i}</td>
      <td>${U.fmtDT(h.loginTime)}</td><td>${U.fmtDT(h.logoutTime)}</td>
      <td>${dur!==null?U.fmtDur(dur):'—'}</td>
      <td><code>${U.esc(h.ipAddress||'—')}</code></td>
      <td><span class="badge ${h.status==='logged_in'?'b-in':'b-out'}">${h.status==='logged_in'?'● Active':'● Ended'}</span></td>
    </tr>`;
  }).join(''):`<tr><td colspan="6" style="text-align:center;padding:24px;color:var(--muted)">No history yet</td></tr>`;
  return `<div class="page-header"><h2>📜 My Login History</h2><p>Your complete session history</p></div>
  <div class="card"><div class="tbl-wrap"><table><thead><tr>
    <th>#</th><th>Login</th><th>Logout</th><th>Duration</th><th>IP</th><th>Status</th>
  </tr></thead><tbody>${rows}</tbody></table></div></div>`;
}

/* ════════════════════════════════════════════════════
   VIEW: USER MANAGEMENT  (Admin+)
════════════════════════════════════════════════════ */
function vUsers(){
  const role=Auth.s.role;
  const users=DB.all(T.users).filter(u=>{
    if(role==='admin') return u.role!=='superadmin'&&u.id!==Auth.s.userId&&u.status!=='pending';
    return u.id!==Auth.s.userId&&u.status!=='pending';
  }).sort((a,b)=>a.username.localeCompare(b.username));

  const rows=users.length?users.map(u=>`
    <tr data-row="${U.esc((u.username+' '+u.legalName+' '+u.email).toLowerCase())}">
      <td><div class="fw-6">${U.esc(u.username)}</div><div class="text-sm text-muted">${U.esc(u.legalName||'')}</div></td>
      <td><span class="badge b-${u.role}">${u.role}</span></td>
      <td>${U.esc(u.email||'—')}</td>
      <td>${U.esc(u.contactInfo||'—')}</td>
      <td><span class="badge b-${u.status}">${u.status}</span></td>
      <td class="text-sm">${U.fmtDT(u.lastLogin)}</td>
      <td><code>${U.esc(u.lastIp||'—')}</code></td>
      <td><div class="flex gap-2">
        ${u.status==='active'
          ?`<button class="btn btn-sm btn-warning" onclick="toggleUser('${u.id}','freeze','${U.esc(u.username)}')">🔒 Freeze</button>`
          :`<button class="btn btn-sm btn-success" onclick="toggleUser('${u.id}','activate','${U.esc(u.username)}')">✅ Activate</button>`}
        ${role==='superadmin'?`<button class="btn btn-sm btn-outline" onclick="viewUserHist('${u.id}','${U.esc(u.username)}')">📜 History</button>`:''}
      </div></td>
    </tr>`).join('')
    :`<tr><td colspan="8" style="text-align:center;padding:24px;color:var(--muted)">No users found</td></tr>`;

  return `<div class="page-header"><h2>👥 User Management</h2><p>Manage accounts and permissions</p></div>
  <div id="users-alert"></div>
  <div class="card">
    <div class="card-header">
      <h3>All Users (${users.length})</h3>
      <input class="form-control" id="usr-search" style="width:200px" placeholder="Search…" oninput="filterUsersTable()">
    </div>
    <div class="tbl-wrap"><table id="usr-tbl"><thead><tr>
      <th>User</th><th>Role</th><th>Email</th><th>Contact</th><th>Status</th><th>Last Login</th><th>Last IP</th><th>Actions</th>
    </tr></thead><tbody>${rows}</tbody></table></div>
  </div>`;
}

function filterUsersTable(){
  const q=document.getElementById('usr-search').value.toLowerCase();
  document.querySelectorAll('#usr-tbl tbody tr[data-row]').forEach(r=>{
    r.style.display=r.dataset.row.includes(q)?'':'none';
  });
}

/* ════════════════════════════════════════════════════
   VIEW: ALL LOGIN HISTORY  (Admin+)
════════════════════════════════════════════════════ */
function vAllHist(){
  const users=DB.all(T.users);
  const opts=users.map(u=>`<option value="${u.id}">${U.esc(u.username)}</option>`).join('');
  return `<div class="page-header"><h2>📊 Login History</h2><p>All user login and session records</p></div>
  <div class="card">
    <div class="card-header"><h3>Filters</h3></div>
    <div class="filter-row">
      <div class="form-group"><label>User</label>
        <select class="form-control" id="hf-user" style="min-width:160px">
          <option value="">All Users</option>${opts}
        </select></div>
      <div class="form-group"><label>From</label><input type="date" class="form-control" id="hf-from"></div>
      <div class="form-group"><label>To</label><input type="date" class="form-control" id="hf-to"></div>
      <div class="form-group"><label>Status</label>
        <select class="form-control" id="hf-status">
          <option value="">All</option>
          <option value="logged_in">Active</option>
          <option value="logged_out">Ended</option>
        </select></div>
      <div class="form-group" style="align-self:flex-end">
        <button class="btn btn-primary" onclick="applyHistFilter()">Apply</button>
        <button class="btn btn-outline" style="margin-left:8px" onclick="resetHistFilter()">Reset</button>
      </div>
    </div>
  </div>
  <div class="card"><div id="hist-tbl">${histTable(DB.all(T.hist).sort((a,b)=>new Date(b.loginTime)-new Date(a.loginTime)))}</div></div>`;
}

function histTable(data){
  if(!data.length) return '<div class="empty"><div class="empty-icon">📭</div><p>No records found</p></div>';
  const rows=data.map(h=>{
    const dur=h.logoutTime?Math.round((new Date(h.logoutTime)-new Date(h.loginTime))/60000):null;
    return `<tr>
      <td><strong>${U.esc(h.username)}</strong></td>
      <td><span class="badge b-${h.role||'user'}">${h.role||'user'}</span></td>
      <td>${U.fmtDT(h.loginTime)}</td><td>${U.fmtDT(h.logoutTime)}</td>
      <td>${dur!==null?U.fmtDur(dur):'—'}</td>
      <td><code>${U.esc(h.ipAddress||'—')}</code></td>
      <td><span class="badge ${h.status==='logged_in'?'b-in':'b-out'}">${h.status==='logged_in'?'● Active':'● Ended'}</span></td>
    </tr>`;
  }).join('');
  return `<div class="tbl-wrap"><table><thead><tr>
    <th>User</th><th>Role</th><th>Login</th><th>Logout</th><th>Duration</th><th>IP</th><th>Status</th>
  </tr></thead><tbody>${rows}</tbody></table></div>`;
}

function applyHistFilter(){
  let data=DB.all(T.hist);
  const uid=document.getElementById('hf-user').value;
  const from=document.getElementById('hf-from').value;
  const to=document.getElementById('hf-to').value;
  const st=document.getElementById('hf-status').value;
  if(uid) data=data.filter(h=>h.userId===uid);
  if(from) data=data.filter(h=>new Date(h.loginTime)>=new Date(from));
  if(to) data=data.filter(h=>new Date(h.loginTime)<=new Date(to+'T23:59:59'));
  if(st) data=data.filter(h=>h.status===st);
  data.sort((a,b)=>new Date(b.loginTime)-new Date(a.loginTime));
  document.getElementById('hist-tbl').innerHTML=histTable(data);
}
function resetHistFilter(){
  ['hf-user','hf-from','hf-to','hf-status'].forEach(id=>{const el=document.getElementById(id);if(el)el.value='';});
  document.getElementById('hist-tbl').innerHTML=histTable(DB.all(T.hist).sort((a,b)=>new Date(b.loginTime)-new Date(a.loginTime)));
}
function viewUserHist(uid,uname){
  showView('all-hist');
  setTimeout(()=>{const s=document.getElementById('hf-user');if(s){s.value=uid;applyHistFilter();}},80);
}

/* ════════════════════════════════════════════════════
   VIEW: BULK IMPORT  (Super Admin)
════════════════════════════════════════════════════ */
function vBulkImport(){
  return `<div class="page-header"><h2>📥 Bulk User Import</h2><p>Import multiple users at once via CSV</p></div>
  <div id="bulk-alert"></div>
  <div class="card">
    <div class="card-header"><h3>CSV Format</h3></div>
    <p class="text-sm text-muted mb-3">One user per line. First row treated as header if it starts with "Legal".</p>
    <div style="background:#f8fafc;border:1px solid var(--border);border-radius:8px;padding:12px;font-family:monospace;font-size:12px;margin-bottom:14px;line-height:1.8">
      LegalName,Username,Email,ContactInfo,Password<br>
      John Doe,johndoe,john@example.com,555-1234,TempPass123<br>
      Jane Smith,janesmith,jane@example.com,555-5678,TempPass456
    </div>
    <div class="form-group">
      <label>CSV Data *</label>
      <textarea class="form-control" id="bulk-csv" rows="8"
        placeholder="LegalName,Username,Email,ContactInfo,Password&#10;John Doe,johndoe,john@example.com,555-1234,TempPass123"></textarea>
    </div>
    <div class="flex gap-2">
      <button class="btn btn-primary" onclick="doBulkImport()">📥 Import</button>
      <button class="btn btn-outline" onclick="downloadTemplate()">⬇️ Download Template</button>
    </div>
    <div id="bulk-result" style="margin-top:14px"></div>
  </div>`;
}

/* ════════════════════════════════════════════════════
   VIEW: CREATE ADMIN  (Super Admin)
════════════════════════════════════════════════════ */
function vCreateAdmin(){
  const admins=DB.find(T.users,u=>u.role==='admin');
  const rows=admins.length?admins.map(u=>`<tr>
    <td><strong>${U.esc(u.username)}</strong></td>
    <td>${U.esc(u.legalName||'—')}</td>
    <td>${U.esc(u.email||'—')}</td>
    <td><span class="badge b-${u.status}">${u.status}</span></td>
    <td class="text-sm">${U.fmtD(u.createdAt)}</td>
    <td><div class="flex gap-2">
      ${u.status==='active'
        ?`<button class="btn btn-sm btn-warning" onclick="toggleUser('${u.id}','freeze','${U.esc(u.username)}')">🔒 Freeze</button>`
        :`<button class="btn btn-sm btn-success" onclick="toggleUser('${u.id}','activate','${U.esc(u.username)}')">✅ Activate</button>`}
    </div></td>
  </tr>`).join(''):`<tr><td colspan="6" style="text-align:center;padding:20px;color:var(--muted)">No admins yet</td></tr>`;

  return `<div class="page-header"><h2>🛡️ Create Admin User</h2><p>Create a new administrator account</p></div>
  <div id="adm-alert"></div>
  <div class="card" style="max-width:560px">
    <div class="card-header"><h3>New Admin Details</h3></div>
    <div class="form-group"><label>Legal Name *</label>
      <input class="form-control" id="na-name" placeholder="Full legal name"></div>
    <div class="grid-2">
      <div class="form-group"><label>Username *</label>
        <input class="form-control" id="na-user" placeholder="Admin username"></div>
      <div class="form-group"><label>Email *</label>
        <input type="email" class="form-control" id="na-email" placeholder="admin@example.com"></div>
    </div>
    <div class="form-group"><label>Contact Info</label>
      <input class="form-control" id="na-contact" placeholder="Phone or other contact"></div>
    <div class="grid-2">
      <div class="form-group"><label>Password *</label>
        <input type="password" class="form-control" id="na-pass" placeholder="Set password"></div>
      <div class="form-group"><label>Confirm Password *</label>
        <input type="password" class="form-control" id="na-conf" placeholder="Confirm password"></div>
    </div>
    <button class="btn btn-primary" onclick="doCreateAdmin()">🛡️ Create Admin</button>
  </div>
  <div class="card">
    <div class="card-header"><h3>Existing Admins (${admins.length})</h3></div>
    <div class="tbl-wrap"><table><thead><tr>
      <th>Username</th><th>Legal Name</th><th>Email</th><th>Status</th><th>Created</th><th>Actions</th>
    </tr></thead><tbody>${rows}</tbody></table></div>
  </div>`;
}

/* ════════════════════════════════════════════════════
   VIEW: JSON DB VIEWER  (Super Admin)
════════════════════════════════════════════════════ */
const JSON_TABLES=[
  {k:'users',label:'👥 Users'},
  {k:'sessions',label:'🔐 Sessions'},
  {k:'login_history',label:'📜 Login History'},
  {k:'checkins',label:'⏱️ Check-ins'},
  {k:'lookup',label:'⚙️ Lookup'}
];
const TK_MAP={'users':T.users,'sessions':T.sessions,'login_history':T.hist,'checkins':T.ci,'lookup':T.lkp};

function vJsonViewer(activeK){
  activeK=activeK||'users';
  return `<div class="page-header"><h2>📁 JSON Database Viewer</h2><p>View and export all database tables</p></div>
  <div class="tbl-btns" id="jtbl-btns">
    ${JSON_TABLES.map(t=>`<button class="tbl-btn ${t.k===activeK?'active':''}" data-tk="${t.k}" onclick="switchJsonTbl('${t.k}')">${t.label}</button>`).join('')}
  </div>
  <div class="card" id="jtbl-content">${jsonTblContent(activeK)}</div>`;
}

function jsonTblContent(k){
  const tkey=TK_MAP[k]||k;
  const data=DB.all(tkey);
  const exportBtn=`<button class="btn btn-sm btn-outline" onclick="exportJson('${k}')">⬇️ Export JSON</button>`;
  if(k==='lookup'){
    const entries=Object.entries(data);
    return `<div class="card-header"><h3>⚙️ Lookup Settings</h3>${exportBtn}</div>
    <div class="tbl-wrap"><table><thead><tr><th>Key</th><th>Value</th></tr></thead><tbody>
    ${entries.length?entries.map(([key,val])=>`<tr>
      <td><strong>${U.esc(key)}</strong></td>
      <td>${U.esc(typeof val==='object'?JSON.stringify(val):String(val))}</td>
    </tr>`).join(''):'<tr><td colspan="2" style="text-align:center;padding:20px;color:var(--muted)">Empty</td></tr>'}
    </tbody></table></div>`;
  }
  if(!Array.isArray(data)||!data.length)
    return `<div class="card-header"><h3>${U.esc(k)}</h3>${exportBtn}</div>
    <div class="empty"><div class="empty-icon">📭</div><p>No records</p></div>`;
  const cols=Object.keys(data[0]);
  const rows=data.map(row=>`<tr>${cols.map(c=>{
    let v=row[c];
    if(c==='password') v='••••••••';
    else if(v===null||v===undefined) v='—';
    else if(typeof v==='boolean') v=v?'true':'false';
    else if(typeof v==='object') v=JSON.stringify(v);
    else v=String(v);
    return `<td style="max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${U.esc(v)}">${U.esc(v)}</td>`;
  }).join('')}</tr>`).join('');
  return `<div class="card-header"><h3>${U.esc(k)} <span class="text-muted">(${data.length} records)</span></h3>${exportBtn}</div>
  <div class="tbl-wrap"><table><thead><tr>${cols.map(c=>`<th>${U.esc(c)}</th>`).join('')}</tr></thead>
  <tbody>${rows}</tbody></table></div>`;
}

function switchJsonTbl(k){
  document.querySelectorAll('.tbl-btn').forEach(b=>b.classList.toggle('active',b.dataset.tk===k));
  document.getElementById('jtbl-content').innerHTML=jsonTblContent(k);
}

function exportJson(k){
  const tkey=TK_MAP[k]||k;
  let data=DB.all(tkey);
  if(Array.isArray(data)) data=data.map(r=>{const c={...r};if(c.password)c.password='**REDACTED**';return c;});
  const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json'});
  const url=URL.createObjectURL(blob);
  const a=document.createElement('a');a.href=url;a.download=k+'.json';a.click();URL.revokeObjectURL(url);
}

/* ════════════════════════════════════════════════════
   VIEW: LOOKUP / SYSTEM SETTINGS  (Super Admin)
════════════════════════════════════════════════════ */
function vLookup(){
  const lkp=DB.all(T.lkp);
  const ips=(lkp.allowedIPs||[]).join('\n');
  return `<div class="page-header"><h2>⚙️ System Settings</h2><p>Configure lookup values and access controls</p></div>
  <div id="lkp-alert"></div>
  <div class="card" style="max-width:640px">
    <div class="card-header"><h3>IP Address Restriction</h3></div>
    <div class="form-group">
      <label><input type="checkbox" id="ip-ena" ${lkp.ipRestrictionEnabled?'checked':''} style="margin-right:6px">
        Enable IP Address Restriction</label>
      <p class="text-sm text-muted mt-2">When enabled, users can only login from the listed IP addresses.</p>
    </div>
    <div class="form-group">
      <label>Allowed IP Addresses <span class="text-muted">(one per line)</span></label>
      <textarea class="form-control" id="ip-list" rows="5" placeholder="192.168.1.100&#10;10.0.0.1">${U.esc(ips)}</textarea>
      <p class="text-sm text-muted mt-2">Exact IP or prefix (e.g. <code>192.168.1</code> matches all 192.168.1.x)</p>
    </div>
    <div class="divider"></div>
    <div class="grid-2">
      <div class="form-group">
        <label>Minimum Login Hours</label>
        <input type="number" class="form-control" id="min-h" value="${lkp.minLoginHours||10}" min="1" max="24">
        <p class="text-sm text-muted mt-2">Minimum hours per check-in session (default: 10)</p>
      </div>
      <div class="form-group">
        <label>Application Name</label>
        <input class="form-control" id="app-name" value="${U.esc(lkp.appName||'WatLogs')}">
      </div>
    </div>
    <button class="btn btn-primary" onclick="saveLookup()">💾 Save Settings</button>
  </div>
  <div class="card" style="max-width:640px">
    <div class="card-header"><h3>Current Settings</h3></div>
    <div class="tbl-wrap"><table><thead><tr><th>Setting</th><th>Value</th></tr></thead><tbody>
      <tr><td>IP Restriction</td><td>${lkp.ipRestrictionEnabled?'<span class="badge b-in">Enabled</span>':'<span class="badge b-out">Disabled</span>'}</td></tr>
      <tr><td>Allowed IPs</td><td>${(lkp.allowedIPs||[]).length?(lkp.allowedIPs).map(ip=>`<code style="margin-right:4px">${U.esc(ip)}</code>`).join(''):'—'}</td></tr>
      <tr><td>Min Login Hours</td><td>${lkp.minLoginHours||10} hours</td></tr>
      <tr><td>App Name</td><td>${U.esc(lkp.appName||'WatLogs')}</td></tr>
    </tbody></table></div>
  </div>`;
}

/* ════════════════════════════════════════════════════
   ACTION HANDLERS
════════════════════════════════════════════════════ */
function saveProfile(){
  const name=document.getElementById('p-name').value.trim();
  const email=document.getElementById('p-email').value.trim();
  const contact=document.getElementById('p-contact').value.trim();
  if(!name){showAlert('prof-alert','Legal name cannot be empty.');return;}
  if(email&&email!==Auth.s.user.email){
    const dup=DB.findOne(T.users,u=>u.email.toLowerCase()===email.toLowerCase()&&u.id!==Auth.s.userId);
    if(dup){showAlert('prof-alert','Email already used by another account.');return;}
  }
  DB.update(T.users,Auth.s.userId,{legalName:name,email,contactInfo:contact});
  Auth.s.user=DB.findId(T.users,Auth.s.userId);
  document.getElementById('sb-uname').textContent=name||Auth.s.username;
  document.getElementById('sb-avatar').textContent=U.initials(name||Auth.s.username);
  showAlert('prof-alert','Profile updated successfully!','success');
}

async function changePassword(){
  const cur=document.getElementById('p-cpwd').value;
  const np=document.getElementById('p-npwd').value;
  const rp=document.getElementById('p-rpwd').value;
  if(!cur||!np||!rp){showAlert('prof-alert','Fill in all password fields.');return;}
  if(!await U.checkPwd(cur,Auth.s.user.password)){showAlert('prof-alert','Current password is incorrect.');return;}
  if(np.length<6){showAlert('prof-alert','New password must be at least 6 characters.');return;}
  if(np!==rp){showAlert('prof-alert','New passwords do not match.');return;}
  DB.update(T.users,Auth.s.userId,{password:await U.hashPwd(np)});
  Auth.s.user=DB.findId(T.users,Auth.s.userId);
  ['p-cpwd','p-npwd','p-rpwd'].forEach(id=>{const el=document.getElementById(id);if(el)el.value='';});
  showAlert('prof-alert','Password updated successfully!','success');
}

function doCheckin(){
  const uid=Auth.s.userId;
  const today=U.today();
  const exists=DB.findOne(T.ci,c=>c.userId===uid&&!c.checkoutTime);
  if(exists){alert('You are already checked in.');return;}
  const todayCI=DB.findOne(T.ci,c=>c.userId===uid&&new Date(c.checkinTime).toDateString()===today&&c.checkoutTime);
  if(todayCI){alert('You have already completed check-in for today. Re-check-in is not allowed for the same day.');return;}
  DB.insert(T.ci,{userId:uid,username:Auth.s.username,checkinTime:U.now(),checkoutTime:null,duration:null});
  showView('checkins');
}

function doCheckout(){
  const act=DB.findOne(T.ci,c=>c.userId===Auth.s.userId&&!c.checkoutTime);
  if(!act){alert('You are not checked in.');return;}
  const mins=Math.round((new Date()-new Date(act.checkinTime))/60000);
  const minM=(DB.all(T.lkp).minLoginHours||10)*60;
  const msg=mins<minM
    ?`You've been checked in for ${U.fmtDur(mins)} (minimum: ${U.fmtDur(minM)}). Check out anyway?`
    :`Check out after ${U.fmtDur(mins)}?`;
  showConfirm('Check Out',msg,()=>{
    if(_timerInterval){clearInterval(_timerInterval);_timerInterval=null;}
    DB.update(T.ci,act.id,{checkoutTime:U.now(),duration:mins});
    showView('checkins');
  },mins<minM);
}

function toggleUser(uid,action,uname){
  const title=action==='freeze'?'🔒 Freeze Account':'✅ Activate Account';
  const msg=action==='freeze'
    ?`Freeze account of "${uname}"? They will not be able to login.`
    :`Activate account of "${uname}"?`;
  showConfirm(title,msg,()=>{
    const st=action==='freeze'?'frozen':'active';
    DB.update(T.users,uid,{status:st});
    if(action==='freeze'){
      const sess=DB.findOne(T.sessions,s=>s.userId===uid&&s.active);
      if(sess) DB.update(T.sessions,sess.id,{active:false,logoutTime:U.now()});
    }
    showView(_currentView);
    const alertId=_currentView==='users'?'users-alert':_currentView==='create-admin'?'adm-alert':null;
    if(alertId) showAlert(alertId,`User "${uname}" has been ${st}.`,'success');
  },action==='freeze');
}

async function doBulkImport(){
  const csv=document.getElementById('bulk-csv').value.trim();
  if(!csv){showAlert('bulk-alert','Please enter CSV data.');return;}
  const lines=csv.split('\n').map(l=>l.trim()).filter(Boolean);
  let start=0;
  if(lines[0].toLowerCase().startsWith('legal')) start=1;
  let ok=0; const errs=[];
  for(let i=start;i<lines.length;i++){
    const p=lines[i].split(',').map(x=>x.trim());
    if(p.length<5){errs.push(`Line ${i+1}: Need 5 fields (LegalName,Username,Email,ContactInfo,Password)`);continue;}
    const [legalName,username,email,contactInfo,password]=p;
    if(!username||!password){errs.push(`Line ${i+1}: Username and password required`);continue;}
    if(DB.findOne(T.users,u=>u.username.toLowerCase()===username.toLowerCase())){errs.push(`Line ${i+1}: Username "${username}" already exists`);continue;}
    DB.insert(T.users,{username,password:await U.hashPwd(password),role:'user',
      legalName,email,contactInfo,status:'active',createdBy:Auth.s.username,lastLogin:null,lastIp:null});
    ok++;
  }
  let html='';
  if(ok) html+=`<div class="alert alert-success">✅ Imported ${ok} user(s) successfully.</div>`;
  if(errs.length) html+=`<div class="alert alert-error"><div><strong>⚠️ ${errs.length} error(s):</strong>
    <ul style="margin-top:6px;padding-left:18px">${errs.map(e=>`<li>${U.esc(e)}</li>`).join('')}</ul></div></div>`;
  document.getElementById('bulk-result').innerHTML=html;
}

function downloadTemplate(){
  const csv='LegalName,Username,Email,ContactInfo,Password\nJohn Doe,johndoe,john@example.com,555-1234,TempPass123\nJane Smith,janesmith,jane@example.com,555-5678,TempPass456';
  const blob=new Blob([csv],{type:'text/csv'});
  const url=URL.createObjectURL(blob);
  const a=document.createElement('a');a.href=url;a.download='bulk_import_template.csv';a.click();URL.revokeObjectURL(url);
}

async function doCreateAdmin(){
  const name=document.getElementById('na-name').value.trim();
  const user=document.getElementById('na-user').value.trim();
  const email=document.getElementById('na-email').value.trim();
  const contact=document.getElementById('na-contact').value.trim();
  const pass=document.getElementById('na-pass').value;
  const conf=document.getElementById('na-conf').value;
  if(!name||!user||!email||!pass){showAlert('adm-alert','Fill in all required fields.');return;}
  if(pass!==conf){showAlert('adm-alert','Passwords do not match.');return;}
  if(DB.findOne(T.users,u=>u.username.toLowerCase()===user.toLowerCase())){showAlert('adm-alert','Username already taken.');return;}
  if(email&&DB.findOne(T.users,u=>u.email.toLowerCase()===email.toLowerCase())){showAlert('adm-alert','Email already registered.');return;}
  DB.insert(T.users,{username:user,password:await U.hashPwd(pass),role:'admin',
    legalName:name,email,contactInfo:contact,status:'active',createdBy:Auth.s.username,lastLogin:null,lastIp:null});
  showAlert('adm-alert',`Admin "${user}" created successfully!`,'success');
  ['na-name','na-user','na-email','na-contact','na-pass','na-conf'].forEach(id=>{const el=document.getElementById(id);if(el)el.value='';});
  showView('create-admin');
}

/* ════════════════════════════════════════════════════
   AUTO-CHECKOUT PREVIOUS DAYS
════════════════════════════════════════════════════ */
function autoCheckoutPrevDays(){
  const today=U.today();
  DB.find(T.ci,c=>!c.checkoutTime).forEach(ci=>{
    if(new Date(ci.checkinTime).toDateString()!==today){
      const eod=new Date(ci.checkinTime);
      eod.setHours(23,59,59,0);
      const duration=Math.round((eod-new Date(ci.checkinTime))/60000);
      DB.update(T.ci,ci.id,{checkoutTime:eod.toISOString(),duration,autoCheckout:true,flagged:true});
    }
  });
}

/* ════════════════════════════════════════════════════
   VIEW: PENDING APPROVALS  (Admin+)
════════════════════════════════════════════════════ */
function vPendingApprovals(){
  const pending=DB.find(T.users,u=>u.status==='pending');
  const rows=pending.length?pending.map(u=>`
    <tr>
      <td><div class="fw-6">${U.esc(u.username)}</div><div class="text-sm text-muted">${U.esc(u.legalName||'')}</div></td>
      <td>${U.esc(u.email||'—')}</td>
      <td>${U.esc(u.contactInfo||'—')}</td>
      <td class="text-sm">${U.fmtDT(u.createdAt)}</td>
      <td><div class="flex gap-2">
        <button class="btn btn-sm btn-success" onclick="approveUser('${u.id}','${U.esc(u.username)}')">✅ Approve</button>
        <button class="btn btn-sm btn-danger" onclick="rejectUser('${u.id}','${U.esc(u.username)}')">❌ Reject</button>
      </div></td>
    </tr>`).join('')
    :`<tr><td colspan="5" style="text-align:center;padding:24px;color:var(--muted)">No pending approvals</td></tr>`;
  return `<div class="page-header"><h2>⏳ Pending Approvals</h2><p>Approve or reject new account requests</p></div>
  <div id="pend-alert"></div>
  <div class="card">
    <div class="card-header"><h3>Pending Accounts (${pending.length})</h3></div>
    <div class="tbl-wrap"><table><thead><tr>
      <th>User</th><th>Email</th><th>Contact</th><th>Requested</th><th>Actions</th>
    </tr></thead><tbody>${rows}</tbody></table></div>
  </div>`;
}

function approveUser(uid,uname){
  showConfirm('✅ Approve Account',`Approve account for "${uname}"? They will be able to login.`,()=>{
    DB.update(T.users,uid,{status:'active'});
    showView('pending-approvals');
    showAlert('pend-alert',`Account "${uname}" has been approved.`,'success');
  },false);
}

function rejectUser(uid,uname){
  showConfirm('❌ Reject Account',`Reject and delete account for "${uname}"?`,()=>{
    DB.del(T.users,uid);
    showView('pending-approvals');
  },true);
}

function saveLookup(){
  const enabled=document.getElementById('ip-ena').checked;
  const rawIPs=document.getElementById('ip-list').value;
  const allowedIPs=rawIPs.split('\n').map(s=>s.trim()).filter(Boolean);
  const minH=parseInt(document.getElementById('min-h').value,10)||10;
  const appName=document.getElementById('app-name').value.trim()||'WatLogs';
  DB.setLkp({ipRestrictionEnabled:enabled,allowedIPs,minLoginHours:minH,appName});
  showAlert('lkp-alert','Settings saved successfully!','success');
  showView('lookup');
}
