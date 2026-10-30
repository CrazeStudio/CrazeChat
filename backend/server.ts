import crypto from 'node:crypto';
import express, { type Request } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { rateLimit } from 'express-rate-limit';
import jwt from 'jsonwebtoken';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';

const PORT = Number(process.env.PORT || 3000);
const DATABASE_URL = process.env.DATABASE_URL;
const SERVICE_ACCOUNT = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
const TOKEN_SECRET = process.env.API_TOKEN_SIGNING_SECRET;
const APP_ACCESS_KEY = process.env.APP_ACCESS_KEY;
const ROOT = 'crazechat/v1';

if (!DATABASE_URL || !SERVICE_ACCOUNT || !TOKEN_SECRET || TOKEN_SECRET.length < 32 || !APP_ACCESS_KEY) {
  throw new Error('Set DATABASE_URL, FIREBASE_SERVICE_ACCOUNT_JSON, a 32+ character API_TOKEN_SIGNING_SECRET, and APP_ACCESS_KEY.');
}
const serviceAccountJson = JSON.parse(SERVICE_ACCOUNT) as { project_id: string; client_email: string; private_key: string };
const serviceAccount = {
  projectId: serviceAccountJson.project_id,
  clientEmail: serviceAccountJson.client_email,
  privateKey: serviceAccountJson.private_key.replace(/\\n/g, '\n'),
};
if (!getApps().length) initializeApp({ credential: cert(serviceAccount), databaseURL: DATABASE_URL });
const db = getDatabase();
const app = express();
const origins = (process.env.ALLOWED_ORIGINS || '*').split(',').map((v) => v.trim()).filter(Boolean);
app.disable('x-powered-by');
app.use(helmet());
app.use(cors({ origin: origins.includes('*') ? '*' : origins, methods: ['GET','POST','PATCH','DELETE','OPTIONS'], allowedHeaders: ['Content-Type','Authorization','X-API-Key'] }));
app.use(express.json({ limit: '64kb' }));

function requireAppAccessKey(req: Request, res: express.Response, next: express.NextFunction): void {
  const provided = Buffer.from(req.header('x-api-key') || '');
  const expected = Buffer.from(APP_ACCESS_KEY!);
  if (provided.length !== expected.length || !crypto.timingSafeEqual(provided, expected)) {
    res.status(403).json({ error: 'API access denied.' });
    return;
  }
  next();
}

// Public health/docs endpoints remain available to deployment monitors.
// All application API routes require the app's X-API-Key header.
app.use(['/auth', '/users', '/chats'], requireAppAccessKey);

type AuthContext = { uid: string; username: string };
type AuthRequest = Request & { auth?: AuthContext };
type UserRecord = { uid: string; username: string; usernameLower: string; passwordHash: string; publicKey: string; identityEnvelope: Record<string, unknown>; createdAt: number };

const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 12, standardHeaders: 'draft-8', legacyHeaders: false });
const messageLimiter = rateLimit({ windowMs: 60 * 1000, limit: 50, standardHeaders: 'draft-8', legacyHeaders: false });

function deriveScrypt(password: string, salt: Buffer, length: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, length, { N: 1 << 15, r: 8, p: 1, maxmem: 64 * 1024 * 1024 }, (error, key) => {
      if (error) reject(error); else resolve(key);
    });
  });
}
async function hashPassword(password: string): Promise<string> {
  const salt = crypto.randomBytes(16);
  const key = await deriveScrypt(password, salt, 64);
  return ['scrypt','32768','8','1',salt.toString('base64'),key.toString('base64')].join('$');
}
async function verifyPassword(password: string, encoded: string): Promise<boolean> {
  const p = encoded.split('$');
  if (p.length !== 6 || p[0] !== 'scrypt') return false;
  const salt = Buffer.from(p[4]!, 'base64');
  const expected = Buffer.from(p[5]!, 'base64');
  const actual = await deriveScrypt(password, salt, expected.length);
  return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
}
function validUsername(v: unknown): v is string { return typeof v === 'string' && /^[a-zA-Z0-9_]{3,20}$/.test(v); }
function validPassword(v: unknown): v is string { return typeof v === 'string' && v.length >= 12 && v.length <= 256; }
function isBase64(v: unknown, expectedBytes?: number): v is string {
  if (typeof v !== 'string' || v.length > 12000 || !/^[A-Za-z0-9+/]+={0,2}$/.test(v)) return false;
  const bytes = Buffer.from(v, 'base64');
  return bytes.length > 0 && (expectedBytes === undefined || bytes.length === expectedBytes);
}
function validEnvelope(v: unknown): v is Record<string, unknown> {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return false;
  const e = v as Record<string, unknown>;
  return e.version === 1 && e.kdf === 'Argon2id' && isBase64(e.salt,16) && isBase64(e.nonce,12) && isBase64(e.ciphertext) && isBase64(e.mac,16);
}
function issueToken(user: UserRecord): string {
  return jwt.sign({ username: user.username }, TOKEN_SECRET!, { subject: user.uid, issuer: 'crazechat-api', audience: 'crazechat-client', expiresIn: 604800 });
}
function requireAuth(req: Request, res: express.Response, next: express.NextFunction): void {
  const header = req.header('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  try {
    const payload = jwt.verify(token, TOKEN_SECRET!, { issuer: 'crazechat-api', audience: 'crazechat-client' }) as jwt.JwtPayload;
    if (!payload.sub || typeof payload.username !== 'string') throw new Error('invalid token');
    (req as AuthRequest).auth = { uid: String(payload.sub), username: payload.username };
    next();
  } catch { res.status(401).json({ error: 'Authentication required. Please sign in again.' }); }
}
function me(req: Request): AuthContext { return (req as AuthRequest).auth!; }
function safeProfile(u: UserRecord) { return { id: u.uid, username: u.username, publicKey: u.publicKey }; }
async function findUser(username: string): Promise<UserRecord | null> {
  const index = await db.ref(ROOT + '/usernames/' + username.toLowerCase()).get();
  if (!index.exists()) return null;
  const user = await db.ref(ROOT + '/users/' + String(index.val().uid)).get();
  return user.exists() ? user.val() as UserRecord : null;
}
async function memberChat(chatId: string, uid: string) {
  if (!/^[a-f0-9]{32}$/.test(chatId)) return null;
  const snap = await db.ref(ROOT + '/chats/' + chatId).get();
  if (!snap.exists()) return null;
  const chat = snap.val() as Record<string, any>;
  return chat.participants?.[uid] === true ? chat : null;
}
async function mappedChat(id: string, chat: Record<string, any>) {
  const ids = Object.keys(chat.participants || {});
  const members = await Promise.all(ids.map(async (uid) => {
    const snap = await db.ref(ROOT + '/users/' + uid).get();
    return snap.exists() ? safeProfile(snap.val() as UserRecord) : null;
  }));
  return { id, type: 'direct', name: null, createdAt: chat.createdAt, updatedAt: chat.updatedAt, members: members.filter(Boolean) };
}

app.get('/api/health', async (_req, res) => {
  try {
    await db.ref(ROOT + '/meta').limitToFirst(1).get();
    res.json({ ok: true, database: 'connected', encryption: 'client-side-only', api: 'CrazeChat' });
  } catch { res.status(503).json({ ok: false, database: 'unavailable' }); }
});
app.get('/api/docs', (_req, res) => res.json({
  name: 'CrazeChat API',
  security: 'Message routes accept ciphertext envelopes only. The API has no plaintext message field.',
  routes: ['POST /auth/register','POST /auth/login','GET /users?q=username','POST /chats','GET /chats','GET /chats/:chatId/messages','POST /chats/:chatId/messages','GET /api/health'],
}));

app.post('/auth/register', authLimiter, async (req, res) => {
  try {
    const { username, password, publicKey, identityEnvelope } = req.body ?? {};
    if (!validUsername(username)) return res.status(400).json({ error: 'Username must be 3–20 letters, numbers, or underscores.' });
    if (!validPassword(password)) return res.status(400).json({ error: 'Use a password of at least 12 characters.' });
    if (!isBase64(publicKey,32) || !validEnvelope(identityEnvelope) || identityEnvelope.publicKey !== publicKey) return res.status(400).json({ error: 'A valid encrypted identity key is required.' });
    const normalized = username.toLowerCase();
    const passwordHash = await hashPassword(password);
    const uid = crypto.randomUUID().replaceAll('-','');
    const claim = await db.ref(ROOT + '/usernames/' + normalized).transaction((value) => value === null ? { uid } : undefined);
    if (!claim.committed) return res.status(409).json({ error: 'That username is already taken.' });
    const user: UserRecord = { uid, username, usernameLower: normalized, passwordHash, publicKey, identityEnvelope, createdAt: Date.now() };
    try { await db.ref(ROOT + '/users/' + uid).set(user); }
    catch (error) { await db.ref(ROOT + '/usernames/' + normalized).remove(); throw error; }
    res.status(201).json({ token: issueToken(user), user: safeProfile(user), identityEnvelope });
  } catch (error) { console.error('register failed', error); res.status(500).json({ error: 'Could not create the account.' }); }
});

app.post('/auth/login', authLimiter, async (req, res) => {
  try {
    const { username, password } = req.body ?? {};
    if (!validUsername(username) || typeof password !== 'string' || password.length > 256) return res.status(400).json({ error: 'Enter your username and password.' });
    const user = await findUser(username);
    if (!user || !(await verifyPassword(password, user.passwordHash))) return res.status(401).json({ error: 'Incorrect username or password.' });
    res.json({ token: issueToken(user), user: safeProfile(user), identityEnvelope: user.identityEnvelope });
  } catch (error) { console.error('login failed', error); res.status(500).json({ error: 'Could not sign in right now.' }); }
});

app.get('/users', requireAuth, async (req, res) => {
  try {
    const q = String(req.query.q || '').toLowerCase().trim();
    if (!/^[a-z0-9_]{2,20}$/.test(q)) return res.status(400).json({ error: 'Search with at least 2 username characters.' });
    const snap = await db.ref(ROOT + '/users').orderByChild('usernameLower').startAt(q).endAt(q + '\uf8ff').limitToFirst(20).get();
    const users: ReturnType<typeof safeProfile>[] = [];
    snap.forEach((child) => { const user = child.val() as UserRecord; if (user.uid !== me(req).uid) users.push(safeProfile(user)); });
    res.json({ users });
  } catch (error) { console.error('user search failed', error); res.status(500).json({ error: 'User search failed.' }); }
});

app.post('/chats', requireAuth, async (req, res) => {
  try {
    const username = typeof req.body?.username === 'string' ? req.body.username.trim() : '';
    if (!validUsername(username)) return res.status(400).json({ error: 'Enter a valid username.' });
    const self = me(req);
    const target = await findUser(username);
    if (!target) return res.status(404).json({ error: 'No CrazeChat user found with that username.' });
    if (target.uid === self.uid) return res.status(400).json({ error: 'You cannot start a chat with yourself.' });
    const pair = [self.uid, target.uid].sort();
    const chatId = crypto.createHash('sha256').update(pair.join(':')).digest('hex').slice(0,32);
    const ref = db.ref(ROOT + '/chats/' + chatId);
    await ref.transaction((value) => value ?? { participants: { [pair[0]!]: true, [pair[1]!]: true }, createdAt: Date.now(), updatedAt: Date.now() });
    await Promise.all(pair.map((uid) => db.ref(ROOT + '/userChats/' + uid + '/' + chatId).set(true)));
    res.json({ chat: await mappedChat(chatId, (await ref.get()).val() as Record<string, any>) });
  } catch (error) { console.error('create chat failed', error); res.status(500).json({ error: 'Could not open this chat.' }); }
});

app.get('/chats', requireAuth, async (req, res) => {
  try {
    const index = await db.ref(ROOT + '/userChats/' + me(req).uid).get();
    const ids = index.exists() ? Object.keys(index.val()) : [];
    const chats = await Promise.all(ids.map(async (id) => {
      const snap = await db.ref(ROOT + '/chats/' + id).get();
      if (!snap.exists()) return null;
      const chat = snap.val() as Record<string, any>;
      return { ...await mappedChat(id, chat), lastMessageAt: chat.lastMessageAt || chat.updatedAt };
    }));
    chats.sort((a, b) => Number(b?.lastMessageAt || 0) - Number(a?.lastMessageAt || 0));
    res.json({ chats: chats.filter(Boolean) });
  } catch (error) { console.error('list chats failed', error); res.status(500).json({ error: 'Could not load conversations.' }); }
});

app.get('/chats/:chatId/messages', requireAuth, async (req, res) => {
  try {
    const chatId = typeof req.params.chatId === 'string' ? req.params.chatId : '';
    if (!(await memberChat(chatId, me(req).uid))) return res.status(404).json({ error: 'Conversation not found.' });
    const snap = await db.ref(ROOT + '/messages/' + chatId).orderByChild('createdAt').limitToLast(60).get();
    const messages: Record<string, unknown>[] = [];
    snap.forEach((child) => { messages.push({ id: child.key, ...(child.val() as object) }); });
    messages.sort((a,b) => Number(a.createdAt) - Number(b.createdAt));
    res.json({ messages });
  } catch (error) { console.error('list messages failed', error); res.status(500).json({ error: 'Could not load messages.' }); }
});

app.post('/chats/:chatId/messages', requireAuth, messageLimiter, async (req, res) => {
  try {
    const uid = me(req).uid;
    const chatId = typeof req.params.chatId === 'string' ? req.params.chatId : '';
    if (!(await memberChat(chatId, uid))) return res.status(404).json({ error: 'Conversation not found.' });
    const { ciphertext, nonce, mac, format } = req.body ?? {};
    if (format !== 'cc-e2ee-v1' || !isBase64(ciphertext) || !isBase64(nonce,12) || !isBase64(mac,16)) {
      return res.status(400).json({ error: 'Only valid encrypted message envelopes are accepted.' });
    }
    if (Buffer.from(ciphertext,'base64').length > 12000) return res.status(413).json({ error: 'Message is too large.' });
    const id = crypto.randomUUID().replaceAll('-','');
    const createdAt = Date.now();
    const message = { id, senderId: uid, format, ciphertext, nonce, mac, createdAt };
    await db.ref(ROOT + '/messages/' + chatId + '/' + id).set(message);
    await db.ref(ROOT + '/chats/' + chatId).update({ updatedAt: createdAt, lastMessageAt: createdAt });
    res.status(201).json({ message });
  } catch (error) { console.error('send message failed', error); res.status(500).json({ error: 'Could not send the encrypted message.' }); }
});

app.use((_req, res) => res.status(404).json({ error: 'Route not found.' }));
app.use((error: unknown, _req: Request, res: express.Response, _next: express.NextFunction) => {
  console.error('unhandled request error', error);
  res.status(500).json({ error: 'Unexpected server error.' });
});
app.listen(PORT, '0.0.0.0', () => console.log('CrazeChat API listening on ' + PORT));