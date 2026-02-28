'use strict';

/* ════════════════════════════════════════════════════
   CONSTANTS
════════════════════════════════════════════════════ */
const PFX = 'wl_';
const SID_KEY = 'wl_sid';
const T = { users:'users', sessions:'sessions', hist:'login_history', ci:'checkins', lkp:'lookup' };

/* ════════════════════════════════════════════════════
   UTILITIES
════════════════════════════════════════════════════ */
const U = {
  uid: () => 'id' + Date.now() + Math.random().toString(36).slice(2,8),
  now: () => new Date().toISOString(),
  fmtDT: iso => iso ? new Date(iso).toLocaleString('en-US',{year:'numeric',month:'short',
    day:'numeric',hour:'2-digit',minute:'2-digit'}) : '—',
  fmtD: iso => iso ? new Date(iso).toLocaleDateString('en-US',{year:'numeric',month:'short',day:'numeric'}) : '—',
  fmtDur: m => {
    if(m===null||m===undefined) return '—';
    return Math.floor(m/60)+'h '+(m%60)+'m';
  },
  fmtTimer: s => {
    const h=Math.floor(s/3600),m=Math.floor((s%3600)/60),sec=s%60;
    return `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(sec).padStart(2,'0')}`;
  },
  hashPwd: p => btoa(encodeURIComponent(p+'__wl2024__')),
  checkPwd: (p,h) => U.hashPwd(p)===h,
  initials: n => {
    if(!n) return '?';
    const p=n.trim().split(/\s+/);
    return p.length>1?(p[0][0]+p[p.length-1][0]).toUpperCase():n.slice(0,2).toUpperCase();
  },
  esc: s => { const d=document.createElement('div'); d.textContent=String(s??''); return d.innerHTML; }
};

/* ════════════════════════════════════════════════════
   DATABASE  (localStorage — persists across sessions)
════════════════════════════════════════════════════ */
const DB = {
  key: t => PFX+t,
  all: t => { try{ const r=localStorage.getItem(DB.key(t)); return t===T.lkp?(r?JSON.parse(r):{}):r?JSON.parse(r):[]; }catch{ return t===T.lkp?{}:[]; } },
  save: (t,d) => localStorage.setItem(DB.key(t),JSON.stringify(d)),
  findId: (t,id) => DB.all(t).find(r=>r.id===id)||null,
  findOne: (t,fn) => DB.all(t).find(fn)||null,
  find: (t,fn) => fn?DB.all(t).filter(fn):DB.all(t),
  insert: (t,rec) => {
    const rows=DB.all(t);
    if(!rec.id) rec.id=U.uid();
    if(!rec.createdAt) rec.createdAt=U.now();
    rows.push(rec); DB.save(t,rows); return rec;
  },
  update: (t,id,patch) => {
    const rows=DB.all(t), i=rows.findIndex(r=>r.id===id);
    if(i<0) return null;
    rows[i]={...rows[i],...patch,updatedAt:U.now()};
    DB.save(t,rows); return rows[i];
  },
  del: (t,id) => DB.save(t,DB.all(t).filter(r=>r.id!==id)),
  setLkp: patch => DB.save(T.lkp,{...DB.all(T.lkp),...patch})
};

/* ════════════════════════════════════════════════════
   IP DETECTION  (WebRTC, no external call)
════════════════════════════════════════════════════ */
const IP = {
  _v: null,
  get: () => new Promise(res => {
    if(IP._v){res(IP._v);return;}
    try{
      const pc=new RTCPeerConnection({iceServers:[]});
      pc.createDataChannel('');
      pc.createOffer().then(o=>pc.setLocalDescription(o));
      let done=false;
      pc.onicecandidate=e=>{
        if(done)return;
        if(e&&e.candidate){
          const m=e.candidate.candidate.match(/(\d{1,3}\.){3}\d{1,3}/);
          if(m&&m[0]!=='0.0.0.0'){done=true;IP._v=m[0];try{pc.close();}catch(_){}res(m[0]);}
        }
      };
      setTimeout(()=>{if(!done){done=true;res('127.0.0.1');}},1500);
    }catch{res('127.0.0.1');}
  })
};

/* ════════════════════════════════════════════════════
   AUTH
════════════════════════════════════════════════════ */
const Auth = {
  s: null,   // current session object (with .user)

  async login(username, password, role){
    const ip = await IP.get();
    const lkp = DB.all(T.lkp);

    // IP restriction
    if(lkp.ipRestrictionEnabled && (lkp.allowedIPs||[]).length){
      const ipParts=ip.split('.');
      const ok=(lkp.allowedIPs).some(pat=>{
        const base=pat.trim().split('/')[0];
        const baseParts=base.split('.');
        return baseParts.every((part,i)=>part===ipParts[i]);
      });
      if(!ok) return {ok:false,err:`Your IP (${ip}) is not on the allowed list.`};
    }

    const user=DB.findOne(T.users,u=>u.username.toLowerCase()===username.toLowerCase());
    if(!user) return {ok:false,err:'Invalid username or password.'};
    if(!U.checkPwd(password,user.password)) return {ok:false,err:'Invalid username or password.'};
    if(user.status==='frozen') return {ok:false,err:'Account is frozen. Contact an administrator.'};
    if(role && user.role!==role)
      return {ok:false,err:`This account has role "${user.role}". Please select the correct role.`};

    // One session per user
    const existing=DB.findOne(T.sessions,s=>s.userId===user.id&&s.active);
    if(existing) return {ok:false,err:'This account already has an active session. Logout from the other device first.'};

    const sess=DB.insert(T.sessions,{userId:user.id,username:user.username,role:user.role,
      loginTime:U.now(),ipAddress:ip,active:true,logoutTime:null});
    DB.insert(T.hist,{userId:user.id,username:user.username,role:user.role,
      loginTime:U.now(),logoutTime:null,ipAddress:ip,status:'logged_in',sessionId:sess.id});
    DB.update(T.users,user.id,{lastLogin:U.now(),lastIp:ip});
    // Use localStorage so session persists across browser restarts
    localStorage.setItem(SID_KEY, sess.id);
    Auth.s={...sess,user};
    return {ok:true};
  },

  logout(){
    if(!Auth.s)return;
    const now=U.now(), sid=Auth.s.id, uid=Auth.s.userId;
    DB.update(T.sessions,sid,{active:false,logoutTime:now});
    const h=DB.findOne(T.hist,x=>x.sessionId===sid&&x.status==='logged_in');
    if(h) DB.update(T.hist,h.id,{logoutTime:now,status:'logged_out'});
    const ci=DB.findOne(T.ci,c=>c.userId===uid&&!c.checkoutTime);
    if(ci) DB.update(T.ci,ci.id,{checkoutTime:now,duration:Math.round((new Date()-new Date(ci.checkinTime))/60000)});
    localStorage.removeItem(SID_KEY);
    Auth.s=null;
  },

  restore(){
    const sid=localStorage.getItem(SID_KEY);
    if(!sid)return null;
    const sess=DB.findId(T.sessions,sid);
    if(!sess||!sess.active){localStorage.removeItem(SID_KEY);return null;}
    const user=DB.findId(T.users,sess.userId);
    Auth.s={...sess,user};
    return Auth.s;
  },

  signup(d){
    if(DB.findOne(T.users,u=>u.username.toLowerCase()===d.username.toLowerCase()))
      return {ok:false,err:'Username already taken.'};
    if(d.email&&DB.findOne(T.users,u=>u.email.toLowerCase()===d.email.toLowerCase()))
      return {ok:false,err:'Email already registered.'};
    DB.insert(T.users,{username:d.username,password:U.hashPwd(d.password),role:'user',
      legalName:d.legalName||'',email:d.email||'',contactInfo:d.contact||'',
      status:'active',createdBy:'signup',lastLogin:null,lastIp:null});
    return {ok:true};
  }
};

/* ════════════════════════════════════════════════════
   BOOTSTRAP  – seed default data if first run
════════════════════════════════════════════════════ */
function bootstrap(){
  if(!DB.findOne(T.users,u=>u.username==='superadmin')){
    DB.insert(T.users,{id:'superadmin_root',username:'superadmin',
      password:U.hashPwd('superadmin'),role:'superadmin',legalName:'Super Administrator',
      email:'superadmin@watlogs.local',contactInfo:'',status:'active',
      createdBy:'system',lastLogin:null,lastIp:null});
  }
  const lkp=DB.all(T.lkp);
  if(!lkp.minLoginHours) DB.setLkp({minLoginHours:10,ipRestrictionEnabled:false,
    allowedIPs:[],appName:'WatLogs'});
}
