import crypto from "node:crypto";
import express, { type Request } from "express";
import cors from "cors";
import helmet from "helmet";
import { rateLimit } from "express-rate-limit";
import jwt from "jsonwebtoken";
import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import {
  createCloudPurgeReceipt,
  isCloudPurgeReceiptFor,
} from "./cloudpurge.js";

const PORT = Number(process.env.PORT || 3000);
const DATABASE_URL = process.env.DATABASE_URL;
const SERVICE_ACCOUNT = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
const TOKEN_SECRET = process.env.API_TOKEN_SIGNING_SECRET;

if (!DATABASE_URL || !SERVICE_ACCOUNT || !TOKEN_SECRET || TOKEN_SECRET.length < 32) {
  throw new Error("Set DATABASE_URL, FIREBASE_SERVICE_ACCOUNT_JSON, and a 32+ character API_TOKEN_SIGNING_SECRET.");
}

const serviceAccountJson = JSON.parse(SERVICE_ACCOUNT) as {
  project_id: string;
  client_email: string;
  private_key: string;
};
const serviceAccount = {
  projectId: serviceAccountJson.project_id,
  clientEmail: serviceAccountJson.client_email,
  privateKey: serviceAccountJson.private_key.replace(/\\n/g, "\n"),
};

if (!getApps().length) {
  initializeApp({ credential: cert(serviceAccount), databaseURL: DATABASE_URL });
}
const db = getDatabase();
const app = express();
const origins = (process.env.ALLOWED_ORIGINS || "*")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);

app.disable("x-powered-by");
app.use(helmet());
app.use(cors({
  origin: origins.includes("*") ? "*" : origins,
  methods: ["GET", "POST", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
}));
app.use(express.json({ limit: "64kb" }));

type AuthContext = { uid: string; username: string };
type AuthRequest = Request & { auth?: AuthContext };
type UserRecord = {
  uid: string;
  username: string;
  usernameLower: string;
  passwordHash: string;
  publicKey: string;
  identityEnvelope: Record<string, unknown>;
  createdAt: number;
};

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 12,
  standardHeaders: "draft-8",
  legacyHeaders: false,
});
const messageLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 90,
  standardHeaders: "draft-8",
  legacyHeaders: false,
});

function ref(path: string) {
  return db.ref(path.replace(/^\/+/, ""));
}

function derivePassword(password: string, salt: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    crypto.pbkdf2(password, salt, 310000, 32, "sha256", (error, key) => {
      if (error) reject(error);
      else resolve(key);
    });
  });
}

/** Matches the PBKDF2-HMAC-SHA256 format used by existing Flutter accounts. */
async function hashPassword(password: string): Promise<string> {
  const salt = crypto.randomBytes(16);
  const key = await derivePassword(password, salt);
  return ["pbkdf2-sha256", "310000", salt.toString("base64"), key.toString("base64")].join("$");
}

async function verifyPassword(password: string, encoded: string): Promise<boolean> {
  const parts = encoded.split("$");
  if (parts.length !== 4 || parts[0] !== "pbkdf2-sha256" || parts[1] !== "310000") return false;
  try {
    const salt = Buffer.from(parts[2]!, "base64");
    const expected = Buffer.from(parts[3]!, "base64");
    if (salt.length !== 16 || expected.length !== 32) return false;
    const actual = await derivePassword(password, salt);
    return crypto.timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}

function validUsername(value: unknown): value is string {
  return typeof value === "string" && /^[a-zA-Z0-9_]{3,20}$/.test(value);
}

function validPassword(value: unknown): value is string {
  return typeof value === "string" && value.length >= 12 && value.length <= 256;
}

function isBase64(value: unknown, expectedBytes?: number): value is string {
  if (typeof value !== "string" || value.length > 12000 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    return false;
  }
  const bytes = Buffer.from(value, "base64");
  return bytes.length > 0 && (expectedBytes === undefined || bytes.length === expectedBytes);
}

function validEnvelope(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const envelope = value as Record<string, unknown>;
  return envelope.version === 1 &&
    envelope.kdf === "Argon2id" &&
    isBase64(envelope.salt, 16) &&
    isBase64(envelope.nonce, 12) &&
    isBase64(envelope.ciphertext) &&
    isBase64(envelope.mac, 16) &&
    isBase64(envelope.publicKey, 32);
}

function issueToken(user: UserRecord): string {
  return jwt.sign(
    { username: user.username },
    TOKEN_SECRET!,
    {
      subject: user.uid,
      issuer: "crazechat-api",
      audience: "crazechat-client",
      expiresIn: "7d",
    },
  );
}

function requireAuth(req: Request, res: express.Response, next: express.NextFunction): void {
  const header = req.header("authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  try {
    const payload = jwt.verify(token, TOKEN_SECRET!, {
      issuer: "crazechat-api",
      audience: "crazechat-client",
    }) as jwt.JwtPayload;
    if (!payload.sub || typeof payload.username !== "string") throw new Error("Invalid token.");
    (req as AuthRequest).auth = { uid: String(payload.sub), username: payload.username };
    next();
  } catch {
    res.status(401).json({ error: "Authentication required. Please sign in again." });
  }
}

function me(req: Request): AuthContext {
  return (req as AuthRequest).auth!;
}

function safeProfile(user: UserRecord) {
  return { id: user.uid, username: user.username, publicKey: user.publicKey };
}

function validChatId(value: string): boolean {
  return /^[a-f0-9]{32}$/.test(value);
}

function validMessageId(value: string): boolean {
  return /^[a-f0-9]{32}$/.test(value);
}

async function findUser(username: string): Promise<UserRecord | null> {
  const index = await ref("usernames/" + username.toLowerCase()).get();
  if (!index.exists()) return null;
  const user = await ref("users/" + String(index.val().uid)).get();
  return user.exists() ? user.val() as UserRecord : null;
}

async function memberChat(chatId: string, uid: string): Promise<Record<string, any> | null> {
  if (!validChatId(chatId)) return null;
  const snapshot = await ref("chats/" + chatId).get();
  if (!snapshot.exists()) return null;
  const chat = snapshot.val() as Record<string, any>;
  return chat.participants?.[uid] === true ? chat : null;
}

async function mappedChat(id: string, chat: Record<string, any>) {
  const ids = Object.keys(chat.participants || {});
  const members = await Promise.all(ids.map(async (uid) => {
    const snapshot = await ref("users/" + uid).get();
    return snapshot.exists() ? safeProfile(snapshot.val() as UserRecord) : null;
  }));
  return {
    id,
    type: "direct",
    name: null,
    createdAt: chat.createdAt,
    updatedAt: chat.updatedAt,
    members: members.filter(Boolean),
  };
}

function asTimestamp(value: unknown): number {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isSafeInteger(number) && number >= 0 ? number : 0;
}

app.get("/api/health", async (_req, res) => {
  try {
    await ref("users").limitToFirst(1).get();
    res.json({ ok: true, database: "connected", authentication: "jwt", cloudPurge: "receiver-acknowledged" });
  } catch {
    res.status(503).json({ ok: false, database: "unavailable" });
  }
});

app.get("/api/docs", (_req, res) => res.json({
  name: "CrazeChat API",
  authentication: "Per-user short-lived JWT bearer sessions.",
  encryption: "The API accepts encrypted message envelopes only.",
  cloudPurge: "The receiver acknowledges after decrypting and durably caching a message; the API writes a tombstone and removes the server ciphertext.",
  routes: [
    "POST /auth/register",
    "POST /auth/login",
    "GET /auth/me",
    "GET /users?q=username",
    "POST /chats",
    "GET /chats",
    "GET /chats/:chatId/messages",
    "POST /chats/:chatId/messages",
    "POST /chats/:chatId/messages/:messageId/ack",
    "DELETE /chats/:chatId/messages/:messageId",
    "GET /chats/:chatId/purges",
  ],
}));

app.post("/auth/register", authLimiter, async (req, res) => {
  try {
    const { username, password, publicKey, identityEnvelope } = req.body ?? {};
    if (!validUsername(username)) {
      return res.status(400).json({ error: "Username must be 3–20 letters, numbers, or underscores." });
    }
    if (!validPassword(password)) {
      return res.status(400).json({ error: "Use a password of at least 12 characters." });
    }
    if (!isBase64(publicKey, 32) || !validEnvelope(identityEnvelope) ||
        identityEnvelope.publicKey !== publicKey) {
      return res.status(400).json({ error: "A valid encrypted identity key is required." });
    }

    const normalized = username.toLowerCase();
    const uid = crypto.randomBytes(16).toString("hex");
    const usernameRef = ref("usernames/" + normalized);
    const claim = await usernameRef.transaction((current) => current === null ? { uid } : undefined);
    if (!claim.committed) return res.status(409).json({ error: "That username is already taken." });

    const user: UserRecord = {
      uid,
      username,
      usernameLower: normalized,
      passwordHash: await hashPassword(password),
      publicKey,
      identityEnvelope,
      createdAt: Date.now(),
    };
    try {
      await ref("users/" + uid).set(user);
    } catch (error) {
      await usernameRef.remove();
      throw error;
    }
    return res.status(201).json({ token: issueToken(user), user: safeProfile(user), identityEnvelope });
  } catch (error) {
    console.error("register failed", error);
    return res.status(500).json({ error: "Could not create the account." });
  }
});

app.post("/auth/login", authLimiter, async (req, res) => {
  try {
    const { username, password } = req.body ?? {};
    if (!validUsername(username) || typeof password !== "string" || password.length > 256) {
      return res.status(400).json({ error: "Enter your username and password." });
    }
    const user = await findUser(username);
    if (!user || !(await verifyPassword(password, user.passwordHash))) {
      return res.status(401).json({ error: "Incorrect username or password." });
    }
    return res.json({ token: issueToken(user), user: safeProfile(user), identityEnvelope: user.identityEnvelope });
  } catch (error) {
    console.error("login failed", error);
    return res.status(500).json({ error: "Could not sign in right now." });
  }
});

app.get("/auth/me", requireAuth, async (req, res) => {
  try {
    const snapshot = await ref("users/" + me(req).uid).get();
    if (!snapshot.exists()) return res.status(401).json({ error: "Account no longer exists." });
    return res.json({ user: safeProfile(snapshot.val() as UserRecord) });
  } catch (error) {
    console.error("session validation failed", error);
    return res.status(500).json({ error: "Could not validate this session." });
  }
});

app.get("/users", requireAuth, async (req, res) => {
  try {
    const query = String(req.query.q || "").toLowerCase().trim();
    if (!/^[a-z0-9_]{2,20}$/.test(query)) {
      return res.status(400).json({ error: "Search with at least 2 username characters." });
    }
    const snapshot = await ref("users")
      .orderByChild("usernameLower")
      .startAt(query)
      .endAt(query + "\uf8ff")
      .limitToFirst(20)
      .get();
    const users: ReturnType<typeof safeProfile>[] = [];
    snapshot.forEach((child) => {
      const user = child.val() as UserRecord;
      if (user.uid !== me(req).uid) users.push(safeProfile(user));
    });
    return res.json({ users });
  } catch (error) {
    console.error("user search failed", error);
    return res.status(500).json({ error: "User search failed." });
  }
});

app.post("/chats", requireAuth, async (req, res) => {
  try {
    const username = typeof req.body?.username === "string" ? req.body.username.trim() : "";
    if (!validUsername(username)) return res.status(400).json({ error: "Enter a valid username." });
    const self = me(req);
    const target = await findUser(username);
    if (!target) return res.status(404).json({ error: "No CrazeChat user found with that username." });
    if (target.uid === self.uid) return res.status(400).json({ error: "You cannot start a chat with yourself." });

    const pair = [self.uid, target.uid].sort();
    const chatId = crypto.createHash("sha256").update(pair.join(":")).digest("hex").slice(0, 32);
    const chatRef = ref("chats/" + chatId);
    await chatRef.transaction((current) => current ?? {
      participants: { [pair[0]!]: true, [pair[1]!]: true },
      createdAt: Date.now(),
      updatedAt: Date.now(),
    });
    await Promise.all(pair.map((uid) => ref("userChats/" + uid + "/" + chatId).set(true)));
    const chat = (await chatRef.get()).val() as Record<string, any>;
    return res.json({ chat: await mappedChat(chatId, chat) });
  } catch (error) {
    console.error("create chat failed", error);
    return res.status(500).json({ error: "Could not open this chat." });
  }
});

app.get("/chats", requireAuth, async (req, res) => {
  try {
    const uid = me(req).uid;
    const index = await ref("userChats/" + uid).get();
    const ids = index.exists() ? Object.keys(index.val()) : [];
    const chats = await Promise.all(ids.map(async (id) => {
      if (!validChatId(id)) return null;
      const snapshot = await ref("chats/" + id).get();
      if (!snapshot.exists()) return null;
      const chat = snapshot.val() as Record<string, any>;
      if (chat.participants?.[uid] !== true) return null;
      return { ...await mappedChat(id, chat), lastMessageAt: chat.lastMessageAt || chat.updatedAt };
    }));
    chats.sort((a, b) => Number(b?.lastMessageAt || 0) - Number(a?.lastMessageAt || 0));
    return res.json({ chats: chats.filter(Boolean) });
  } catch (error) {
    console.error("list chats failed", error);
    return res.status(500).json({ error: "Could not load conversations." });
  }
});

app.get("/chats/:chatId/messages", requireAuth, async (req, res) => {
  try {
    const chatId = String(req.params.chatId || "");
    if (!(await memberChat(chatId, me(req).uid))) {
      return res.status(404).json({ error: "Conversation not found." });
    }
    const limitValue = Number(req.query.limit ?? 50);
    if (!Number.isInteger(limitValue) || limitValue < 1 || limitValue > 100) {
      return res.status(400).json({ error: "Message limit must be between 1 and 100." });
    }
    const sinceValue = req.query.since === undefined ? null : Number(req.query.since);
    if (sinceValue !== null && (!Number.isSafeInteger(sinceValue) || sinceValue < 0)) {
      return res.status(400).json({ error: "Invalid message sync cursor." });
    }
    let query = ref("Massages/" + chatId).orderByChild("createdAt");
    if (sinceValue !== null) query = query.startAt(sinceValue);
    const snapshot = await query.limitToLast(limitValue).get();
    const messages: Record<string, unknown>[] = [];
    snapshot.forEach((child) => {
      if (child.key && child.val() && typeof child.val() === "object") {
        messages.push({ id: child.key, ...(child.val() as object) });
      }
    });
    messages.sort((a, b) => asTimestamp(a.createdAt) - asTimestamp(b.createdAt));
    return res.json({ messages });
  } catch (error) {
    console.error("list messages failed", error);
    return res.status(500).json({ error: "Could not load messages." });
  }
});

app.post("/chats/:chatId/messages", requireAuth, messageLimiter, async (req, res) => {
  try {
    const uid = me(req).uid;
    const chatId = String(req.params.chatId || "");
    const chat = await memberChat(chatId, uid);
    if (!chat) return res.status(404).json({ error: "Conversation not found." });

    const { ciphertext, nonce, mac, format } = req.body ?? {};
    const messageId = typeof req.body?.id === "string" ? req.body.id : crypto.randomBytes(16).toString("hex");
    if (!validMessageId(messageId)) return res.status(400).json({ error: "Invalid message identifier." });
    if (format !== "cc-e2ee-v1" || !isBase64(ciphertext) || !isBase64(nonce, 12) || !isBase64(mac, 16)) {
      return res.status(400).json({ error: "Only valid encrypted message envelopes are accepted." });
    }
    if (Buffer.from(ciphertext, "base64").length > 12000) {
      return res.status(413).json({ error: "Message is too large." });
    }

    const createdAt = Date.now();
    const message = { id: messageId, senderId: uid, format, ciphertext, nonce, mac, createdAt };
    const messageRef = ref("Massages/" + chatId + "/" + messageId);
    const transaction = await messageRef.transaction((current) => current === null ? message : undefined);
    if (!transaction.committed) {
      const existing = transaction.snapshot.val() as Record<string, unknown> | null;
      if (!existing || existing.senderId !== uid || existing.ciphertext !== ciphertext ||
          existing.nonce !== nonce || existing.mac !== mac) {
        return res.status(409).json({ error: "That message identifier is already in use." });
      }
      return res.json({ message: existing, duplicate: true });
    }
    await ref("chats/" + chatId).update({ updatedAt: createdAt, lastMessageAt: createdAt });
    return res.status(201).json({ message });
  } catch (error) {
    console.error("send message failed", error);
    return res.status(500).json({ error: "Could not send the encrypted message." });
  }
});

app.post("/chats/:chatId/messages/:messageId/ack", requireAuth, messageLimiter, async (req, res) => {
  try {
    const uid = me(req).uid;
    const chatId = String(req.params.chatId || "");
    const messageId = String(req.params.messageId || "");
    const chat = await memberChat(chatId, uid);
    if (!chat || !validMessageId(messageId)) {
      return res.status(404).json({ error: "Message not found." });
    }

    const messageRef = ref("Massages/" + chatId + "/" + messageId);
    const tombstoneRef = ref("MassagesPurge/" + chatId + "/" + messageId);
    const [messageSnapshot, tombstoneSnapshot] = await Promise.all([messageRef.get(), tombstoneRef.get()]);
    if (!messageSnapshot.exists()) {
      const existing = tombstoneSnapshot.val();
      if (isCloudPurgeReceiptFor(existing, uid)) {
        await messageRef.remove();
        return res.json({ ok: true, alreadyAcknowledged: true, purgedAt: existing.purgedAt });
      }
      return res.status(404).json({ error: "Message is no longer available for receipt." });
    }

    const message = messageSnapshot.val() as { id: string; senderId: string; createdAt: number };
    if (message.senderId === uid) {
      return res.status(403).json({ error: "The sender cannot acknowledge their own message." });
    }
    const receipt = createCloudPurgeReceipt(message, uid, Date.now());
    await db.ref().update({
      ["MassagesPurge/" + chatId + "/" + messageId]: receipt,
      ["Massages/" + chatId + "/" + messageId]: null,
    });
    return res.json({ ok: true, alreadyAcknowledged: false, purgedAt: receipt.purgedAt });
  } catch (error) {
    console.error("CloudPurge acknowledgement failed", error);
    return res.status(500).json({ error: "Could not confirm message receipt." });
  }
});

app.delete("/chats/:chatId/messages/:messageId", requireAuth, async (req, res) => {
  try {
    const uid = me(req).uid;
    const chatId = String(req.params.chatId || "");
    const messageId = String(req.params.messageId || "");
    if (!(await memberChat(chatId, uid)) || !validMessageId(messageId)) {
      return res.status(404).json({ error: "Message not found." });
    }
    const messageRef = ref("Massages/" + chatId + "/" + messageId);
    const tombstoneRef = ref("MassagesPurge/" + chatId + "/" + messageId);
    const [messageSnapshot, tombstoneSnapshot] = await Promise.all([messageRef.get(), tombstoneRef.get()]);
    if (!messageSnapshot.exists()) {
      const existing = tombstoneSnapshot.val() as Record<string, unknown> | null;
      if (existing?.reason === "sender-delete" && existing.senderId === uid) {
        return res.json({ ok: true, alreadyDeleted: true });
      }
      return res.status(404).json({ error: "Message not found." });
    }
    const message = messageSnapshot.val() as Record<string, unknown>;
    if (message.senderId !== uid) {
      return res.status(403).json({ error: "You can only delete messages you sent." });
    }
    const participants = Object.keys((await memberChat(chatId, uid))?.participants || {});
    const receiverId = participants.find((participant) => participant !== uid) || "";
    const purgedAt = Date.now();
    await db.ref().update({
      ["MassagesPurge/" + chatId + "/" + messageId]: {
        messageId,
        senderId: uid,
        receiverId,
        createdAt: asTimestamp(message.createdAt),
        purgedAt,
        reason: "sender-delete",
        deletedBy: uid,
      },
      ["Massages/" + chatId + "/" + messageId]: null,
    });
    return res.json({ ok: true, deleted: messageId, purgedAt });
  } catch (error) {
    console.error("delete message failed", error);
    return res.status(500).json({ error: "Could not delete this message." });
  }
});

app.get("/chats/:chatId/purges", requireAuth, async (req, res) => {
  try {
    const chatId = String(req.params.chatId || "");
    if (!(await memberChat(chatId, me(req).uid))) {
      return res.status(404).json({ error: "Conversation not found." });
    }
    const since = req.query.since === undefined ? null : Number(req.query.since);
    if (since !== null && (!Number.isSafeInteger(since) || since < 0)) {
      return res.status(400).json({ error: "Invalid CloudPurge sync cursor." });
    }
    let query = ref("MassagesPurge/" + chatId).orderByChild("purgedAt");
    if (since !== null) query = query.startAt(since);
    const snapshot = await query.limitToLast(100).get();
    const purges: Record<string, unknown>[] = [];
    snapshot.forEach((child) => {
      if (child.key && child.val() && typeof child.val() === "object") {
        purges.push({ messageId: child.key, ...(child.val() as object) });
      }
    });
    purges.sort((a, b) => asTimestamp(a.purgedAt) - asTimestamp(b.purgedAt));
    return res.json({ purges });
  } catch (error) {
    console.error("list CloudPurge receipts failed", error);
    return res.status(500).json({ error: "Could not load CloudPurge receipts." });
  }
});

app.use((_req, res) => res.status(404).json({ error: "Route not found." }));
app.use((error: unknown, _req: Request, res: express.Response, _next: express.NextFunction) => {
  console.error("unhandled request error", error);
  res.status(500).json({ error: "Unexpected server error." });
});

app.listen(PORT, "0.0.0.0", () => console.log("CrazeChat authenticated API listening on " + PORT));
