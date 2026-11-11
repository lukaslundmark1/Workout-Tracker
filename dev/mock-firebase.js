// Generic in-memory Firestore + Auth stand-in for testing
const DB = window.__db = new Map();           // path -> data
const L = window.__ls = [];                   // listeners
let authCb = null, user = null;
const clone = v => JSON.parse(JSON.stringify(v));
export const initializeApp = () => ({}); export const initializeAuth = () => ({});
export const indexedDBLocalPersistence = {}, browserLocalPersistence = {}, browserPopupRedirectResolver = {};
export const getRedirectResult = async () => null;
export const onAuthStateChanged = (a, cb) => { authCb = cb; setTimeout(() => cb(user), 0); return () => {}; };
export class GoogleAuthProvider {}
export const signInWithPopup = async () => {};
export const signInWithRedirect = signInWithPopup;
export const signInWithEmailAndPassword = async (a, email) => { user = { uid: { 'lukas@x.com': 'u1' }[email] || 'u9', email, providerData: [{ providerId: 'password' }] }; authCb(user); };
export const createUserWithEmailAndPassword = signInWithEmailAndPassword;
export const sendPasswordResetEmail = async () => {};
export const signOut = async () => { user = null; authCb(null); };
export const initializeFirestore = () => ({}); export const persistentLocalCache = () => ({}), persistentSingleTabManager = () => ({});
export const collection = (db, ...p) => ({ path: p.join('/') });
export const doc = (db, ...p) => ({ path: p.join('/'), id: p[p.length - 1] });
export const documentId = () => '__id__';
export const where = (field, op, val) => ({ field, op, val });
export const query = (c, ...w) => ({ path: c.path, wheres: w });
const parent = p => p.split('/').slice(0, -1).join('/');
const match = (q, path, d) => parent(path) === q.path && (q.wheres || []).every(w => {
  const v = w.field === '__id__' ? path.split('/').pop() : d[w.field];
  if (w.op === '==') return v === w.val; if (w.op === '>=') return v >= w.val; if (w.op === '>') return v > w.val;
  if (w.op === 'array-contains') return Array.isArray(v) && v.includes(w.val); return false; });
const snapDoc = (path, d) => ({ id: path.split('/').pop(), data: () => clone(d), exists: () => d !== undefined, metadata: { hasPendingWrites: false } });
const results = q => [...DB.entries()].filter(([p, d]) => match(q, p, d)).map(([p, d]) => snapDoc(p, d));
export const getDocs = async q => { const docs = results(q.wheres ? q : { path: q.path, wheres: [] }); return { docs, forEach: f => docs.forEach(f) }; };
export const getDoc = async r => snapDoc(r.path, DB.get(r.path));
function notify(path, removed) {
  L.forEach(l => {
    const was = l.seen.has(path), now = !removed && match(l.q, path, DB.get(path));
    if (!was && !now) return;
    if (now) l.seen.add(path); else l.seen.delete(path);
    const ch = [{ type: now ? (was ? 'modified' : 'added') : 'removed', doc: snapDoc(path, DB.get(path) || {}) }];
    const docs = results(l.q);
    l.next({ docs, docChanges: () => ch, metadata: { fromCache: false } });
  });
}
const put = (path, d) => { DB.set(path, clone(d)); notify(path); };
window.__put = put; window.__del = path => { DB.delete(path); notify(path, true); };
export const setDoc = async (r, d) => put(r.path, d);
export const updateDoc = async (r, patch) => {
  if (!DB.has(r.path)) throw Object.assign(new Error('no doc'), { code: 'not-found' });
  const d = clone(DB.get(r.path));
  for (const [k, v] of Object.entries(patch)) { const ks = k.split('.'); let o = d; ks.slice(0, -1).forEach(x => { o[x] = o[x] || {}; o = o[x]; }); o[ks[ks.length - 1]] = v; }
  put(r.path, d);
};
export const deleteDoc = async r => window.__del(r.path);
export const onSnapshot = (q, next) => { const qq = q.wheres ? q : { path: q.path, wheres: [] }; const l = { q: qq, next, seen: new Set(results(qq).map(d => qq.path + '/' + d.id)) };
  L.push(l); const docs = results(qq); next({ docs, docChanges: () => docs.map(d => ({ type: 'added', doc: d })), metadata: { fromCache: false } });
  return () => { const i = L.indexOf(l); if (i >= 0) L.splice(i, 1); }; };
// window.__failCommit = true makes the next batch writes fail like a rules rejection (to test that the app retries)
export const writeBatch = () => { const ops = []; return { set: (r, d) => ops.push([r, d]), commit: async () => { if (window.__failCommit) { const e = new Error('denied'); e.code = 'permission-denied'; throw e; } ops.forEach(([r, d]) => put(r.path, d)); } }; };

export const reauthenticateWithCredential = async (u, cred) => { if (cred.password !== 'secret1') { const e = new Error('wrong'); e.code = 'auth/wrong-password'; throw e; } };
export const reauthenticateWithPopup = async () => {};
export const EmailAuthProvider = { credential: (email, password) => ({ email, password }) };
export const deleteUser = async () => { window.__deletedUser = user && user.uid; localStorage.setItem('__deletedUser', user && user.uid); user = null; };
export const terminate = async () => {};
export const clearIndexedDbPersistence = async () => { localStorage.setItem('__clearedCache', '1'); };
