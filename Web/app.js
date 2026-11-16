// Vox web. The same tree of items and notes as the phone, read and written straight in Supabase.
// Rules mirror the app (NotesModel, BoardRules, RemindersModel), so every device agrees.

// ---------- Config ----------
const SUPABASE_URL = "https://suzmgshfjscxzngcqjdh.supabase.co";
const SUPABASE_KEY = "sb_publishable_fyjXegNWaquUwHkbk_TvRw_f8mBKU3H";
const POLL_MS = 8000;

const db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
const $app = document.getElementById("app");

// ---------- Icons ----------
const P = {
  list: '<circle cx="5" cy="7" r="1.4" fill="currentColor" stroke="none"/><circle cx="5" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="5" cy="17" r="1.4" fill="currentColor" stroke="none"/><path d="M10 7h10M10 12h10M10 17h10"/>',
  checklist: '<path d="M4 7l1.6 1.6L9 5.2M4 13l1.6 1.6L9 11.2M4 19l1.6 1.6L9 17.2M12 7h8M12 13h8M12 19h8"/>',
  board: '<rect x="3" y="4" width="4.5" height="16" rx="1.2"/><rect x="9.75" y="4" width="4.5" height="11" rx="1.2"/><rect x="16.5" y="4" width="4.5" height="8" rx="1.2"/>',
  folder: '<path d="M3 7.5A1.5 1.5 0 0 1 4.5 6h4.3l2 2h8.7A1.5 1.5 0 0 1 21 9.5v8A1.5 1.5 0 0 1 19.5 19h-15A1.5 1.5 0 0 1 3 17.5z"/>',
  note: '<path d="M6 3h8l5 5v13H6z"/><path d="M14 3v5h5M9 12h7M9 16h7"/>',
  circle: '<circle cx="12" cy="12" r="8.5"/>',
  half: '<circle cx="12" cy="12" r="8.5"/><path d="M12 3.5v17A8.5 8.5 0 0 0 12 3.5z" fill="currentColor" stroke="none"/>',
  donecircle: '<circle cx="12" cy="12" r="8.5" fill="currentColor" stroke="none"/><path d="M8 12.3l2.6 2.6L16 9.5" stroke="#0A1724" stroke-width="2.4"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5" stroke-width="3.2"/>',
  right: '<path d="M9 6l6 6-6 6"/>',
  left: '<path d="M15 6l-6 6 6 6"/>',
  down: '<path d="M6 9l6 6 6-6"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  minus: '<circle cx="12" cy="12" r="9" fill="currentColor" stroke="none"/><path d="M8 12h8" stroke="#fff" stroke-width="2.4"/>',
  bell: '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0"/>',
  alarm: '<circle cx="12" cy="13" r="7"/><path d="M12 9.5V13l2.5 2M4 5l3-2.5M20 5l-3-2.5"/>',
  flag: '<path d="M5 21V4h9l.6 2H20v10h-6.4l-.6-2H7v7"/>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
  pencil: '<path d="M4 20l4.5-1L19 8.5 15.5 5 5 15.5zM13.5 7l3.5 3.5"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/>',
  dots: '<circle cx="6" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="18" cy="12" r="1.6" fill="currentColor" stroke="none"/>',
  star: '<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1.1 5.9L12 16.9l-5.3 2.8 1.1-5.9-4.3-4.1 5.9-.8z" fill="currentColor" stroke="none"/>',
  history: '<path d="M3.5 12a8.5 8.5 0 1 0 2.5-6M3.5 3.5V8H8M12 8v4.5l3 2"/>',
  grip: '<circle cx="9" cy="6" r="1.4" fill="currentColor" stroke="none"/><circle cx="15" cy="6" r="1.4" fill="currentColor" stroke="none"/><circle cx="9" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="9" cy="18" r="1.4" fill="currentColor" stroke="none"/><circle cx="15" cy="18" r="1.4" fill="currentColor" stroke="none"/>',
  x: '<path d="M6 6l12 12M18 6L6 18"/>',
  move: '<path d="M3 7.5A1.5 1.5 0 0 1 4.5 6h4.3l2 2h8.7A1.5 1.5 0 0 1 21 9.5v8A1.5 1.5 0 0 1 19.5 19h-15A1.5 1.5 0 0 1 3 17.5z"/><path d="M12 11v5M9.5 13.5L12 16l2.5-2.5"/>',
  columns: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M9 5v14M15 5v14"/>',
  section: '<rect x="3" y="4" width="18" height="7" rx="1.5"/><rect x="3" y="14" width="18" height="7" rx="1.5"/>',
  open: '<path d="M7 17L17 7M9 7h8v8"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>',
};
const I = (name, cls = "") => `<svg class="icon ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${P[name] || ""}</svg>`;

// ---------- State ----------
const S = {
  user: null,
  nodes: [],
  reminders: [],
  log: [],
  byID: new Map(),
  editing: false,
  section: {},          // boardID -> sectionID filter
  collapsed: new Set(), // checklist rows folded shut
  pending: 0,           // writes still on their way to Supabase
  sig: "",
  online: true,
  next: null,           // what the countdown pill counts to
  focusKey: null,       // input to focus again after a render
  mode: "signin",
};
const PRESETS = [
  ["Slate", "#94ADD1"], ["Amber", "#F7AD52"], ["Sage", "#8CD1B3"], ["Rose", "#E8919B"],
  ["Lavender", "#B4A3E0"], ["Sky", "#7EC8E3"], ["Sand", "#D9C3A0"], ["Stone", "#A6A6AE"],
];
const TINT = { todo: "#94ADD1", doing: "#F7AD52", done: "#8CD1B3" };
const LABEL = { todo: "Todo", doing: "Doing", done: "Done" };
const VIEWS = ["list", "checklist", "board", "folder"];
const VIEW_LABEL = { list: "List", checklist: "Checklist", board: "Board", folder: "Folder" };

// ---------- Small helpers ----------
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const nowISO = () => new Date().toISOString();
const uuid = () => crypto.randomUUID();
const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds());
const sameDay = (a, b) => startOfDay(a).getTime() === startOfDay(b).getTime();
const fmtTime = (d) => d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
const pad = (n) => String(n).padStart(2, "0");

function dayText(d, short = false) {
  const today = new Date();
  if (sameDay(d, today)) return "Today";
  if (sameDay(d, addDays(today, 1))) return "Tomorrow";
  if (sameDay(d, addDays(today, -1))) return "Yesterday";
  return d.toLocaleDateString([], short ? { weekday: "short", day: "numeric", month: "short" } : { weekday: "long", day: "numeric", month: "long" });
}
function dueText(d) {
  const now = new Date();
  if (d < now) return "Overdue";
  if (sameDay(d, now)) return "Due today " + fmtTime(d);
  if (sameDay(d, addDays(now, 1))) return "Due tomorrow";
  const days = Math.round((startOfDay(d) - startOfDay(now)) / 86400000);
  return days < 7 ? `Due in ${days} days` : "Due " + d.toLocaleDateString([], { day: "numeric", month: "short" });
}
function toLocalInput(d) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
function clockText(seconds) {
  const total = Math.max(Math.ceil(seconds), 0);
  const h = Math.floor(total / 3600), m = Math.floor(total / 60) % 60, s = total % 60;
  if (h >= 24) return `${Math.floor(h / 24)}d ${h % 24}h`;
  if (h > 0) return `${h}:${pad(m)}:${pad(s)}`;
  return `${pad(m)}:${pad(s)}`;
}
function repeatText(rule) {
  if (!rule) return "";
  if (rule === "daily") return "Every day";
  const days = { sun: "Sunday", mon: "Monday", tue: "Tuesday", wed: "Wednesday", thu: "Thursday", fri: "Friday", sat: "Saturday" };
  return "Every " + (days[rule.slice(7)] ?? rule);
}
let toastTimer, toastAction = null;
function toast(text, { error = false, action = null, label = "Undo" } = {}) {
  const el = document.getElementById("toast");
  toastAction = action;
  el.className = "toast glass show" + (error ? " err" : "");
  el.innerHTML = `<span>${esc(text)}</span>${action ? `<button id="toastBtn">${esc(label)}</button>` : ""}`;
  if (action) el.querySelector("#toastBtn").onclick = () => { el.classList.remove("show"); action(); };
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), action ? 6000 : 3500);
}
// A little burst of scenery colors, where a task was ticked off.
function burst(x, y) {
  const el = document.createElement("div");
  el.className = "burst";
  el.style.left = x + "px"; el.style.top = y + "px";
  const colors = [TINT.done, TINT.doing, TINT.todo, "#8CD9FF", "#ffffff"];
  for (let i = 0; i < 14; i++) {
    const a = (i / 14) * Math.PI * 2, r = 28 + Math.random() * 26;
    el.innerHTML += `<i style="--c:${colors[i % colors.length]};--x:${Math.cos(a) * r}px;--y:${Math.sin(a) * r}px"></i>`;
  }
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 800);
}

// ---------- Tree reads (NotesModel) ----------
const node = (id) => (id ? S.byID.get(id) : null) || null;
const children = (pid) => S.nodes.filter((n) => n.parent_id === (pid || null)).sort((a, b) => a.position - b.position || a.created_at.localeCompare(b.created_at));
function descendants(id) {
  const out = [];
  for (const kid of children(id)) { out.push(kid); out.push(...descendants(kid.id)); }
  return out;
}
const isBoard = (n) => n && n.kind === "item" && n.view === "board";
const isFolder = (n) => n && n.kind === "item" && n.view === "folder";
const isColumn = (n) => { const p = node(n?.parent_id); return !!(n && n.kind === "item" && !isBoard(n) && isBoard(p)); };
const sections = (board) => children(board.id).filter(isBoard);
const columnItems = (container) => children(container.id).filter((c) => c.kind === "item" && !isBoard(c));
// Several column items with the same title (one per section) merge into one column.
function columns(board, section = null) {
  const containers = section ? [section] : [board, ...sections(board)];
  const order = [], groups = {};
  for (const c of containers) for (const col of columnItems(c)) {
    const key = col.title.trim().toLowerCase();
    if (!groups[key]) { groups[key] = []; order.push(key); }
    groups[key].push(col);
  }
  return order.map((key) => {
    const sources = groups[key];
    return { key, title: sources[0].title, type: sources[0].column_type, sources, cards: sources.flatMap((s) => children(s.id)) };
  });
}
const cardCount = (board) => columns(board).reduce((n, c) => n + c.cards.length, 0);
function progress(id) {
  const tasks = children(id).filter((k) => k.status);
  return tasks.length ? { done: tasks.filter((k) => k.status === "done").length, total: tasks.length } : null;
}
function isDescendant(id, ancestorID) {
  for (let n = node(id); n; n = node(n.parent_id)) if (n.parent_id === ancestorID) return true;
  return false;
}
const ancestors = (n) => { const out = []; for (let p = node(n?.parent_id); p; p = node(p.parent_id)) out.unshift(p); return out; };
const remindersList = () => children(null).find((n) => n.kind === "item" && n.title.trim().toLowerCase() === "reminders");
const inRemindersList = (n) => !!n && n.parent_id != null && n.parent_id === remindersList()?.id;
// Open todos in the Reminders list with no time still to come. Ones whose reminder is ahead show in the dated list.
const reminderTodos = () => {
  const list = remindersList();
  if (!list) return [];
  const now = new Date();
  const timed = new Set(S.reminders.filter((r) => !r.done && r.node_id && nextFire(r, now)).map((r) => r.node_id));
  return children(list.id).filter((n) => n.status && n.status !== "done" && !timed.has(n.id));
};
const rating = (n) => { const d = (n.details || []).find((x) => x.key.toLowerCase() === "rating"); const v = d && parseInt(d.value, 10); return Number.isInteger(v) && v >= 0 && v <= 5 ? v : null; };
const iconFor = (n) => (n.kind === "note" ? "note" : n.view || "list");
const tintOf = (n) => n.color || PRESETS[0][1];

const ColumnRules = {
  accepts: (type, status) => (type ? status === type : status !== "done"),
  statusOnDrop: (type, current) => type || (current && current !== "done" ? current : "todo"),
};
const fittingColumn = (cols, status) => cols.find((c) => c.column_type && c.column_type === status) || cols.find((c) => ColumnRules.accepts(c.column_type, status)) || null;
function positionBetween(before, after) {
  if (before != null && after != null) return (before + after) / 2;
  if (before != null) return before + 1;
  if (after != null) return after - 1;
  return 1;
}
const endPosition = (pid, excluding) => positionBetween(children(pid).filter((n) => n.id !== excluding).at(-1)?.position ?? null, null);

// ---------- Reminder reads (RemindersModel) ----------
const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
function occurrences(r, from, to) {
  const first = new Date(r.fire_at);
  if (!r.repeat_rule) return first >= from && first < to ? [first] : [];
  const out = [];
  const start = first > from ? first : from;
  for (let day = startOfDay(start); day < to; day = addDays(day, 1)) {
    const when = new Date(day.getFullYear(), day.getMonth(), day.getDate(), first.getHours(), first.getMinutes());
    if (when < start || when >= to) continue;
    if (r.repeat_rule === "daily" || WEEKDAYS[when.getDay()] === r.repeat_rule.slice(7)) out.push(when);
  }
  return out;
}
const nextFire = (r, after = new Date()) => occurrences(r, new Date(after.getTime() + 1000), addDays(after, 8))[0] ?? null;
const pendingReminders = () => S.reminders.filter((r) => !r.done);
// Reminders, alarms and deadlines on one day. Ones that already went off stay, so the day shows everything it had.
function entriesOn(day) {
  const from = startOfDay(day), to = addDays(from, 1), now = new Date();
  const out = [];
  for (const r of S.reminders) {
    if (r.done && new Date(r.fire_at) > now) continue;
    for (const when of occurrences(r, from, to)) out.push({ when, kind: r.kind, title: r.title, reminder: r });
  }
  for (const n of S.nodes) {
    if (!n.due_at || n.status === "done") continue;
    const due = new Date(n.due_at);
    if (due >= from && due < to) out.push({ when: due, kind: "deadline", title: n.title, node: n });
  }
  return out.sort((a, b) => a.when - b.when);
}
function upcoming(limit) {
  const now = new Date();
  const out = pendingReminders().map((r) => ({ when: nextFire(r, now), kind: r.kind, title: r.title, reminder: r })).filter((e) => e.when);
  for (const n of S.nodes) if (n.due_at && n.status !== "done" && new Date(n.due_at) > now) out.push({ when: new Date(n.due_at), kind: "deadline", title: n.title, node: n });
  out.sort((a, b) => a.when - b.when);
  return limit ? out.slice(0, limit) : out;
}
// The next thing on the clock, and when the wait for it started (the countdown bar runs between the two).
function nextTimed() {
  const now = new Date();
  const all = upcoming();
  if (!all.length) return null;
  const next = all[0];
  const set = new Date(next.reminder ? next.reminder.updated_at : next.node.updated_at);
  const lastDay = addDays(now, -1);
  let previous = null;
  for (const r of pendingReminders()) for (const d of occurrences(r, lastDay, now)) if (!previous || d > previous) previous = d;
  const since = new Date(Math.max((previous || set).getTime(), next.when.getTime() - 86400000));
  return { entry: next, since: since < now ? since : now };
}

// ---------- Writes ----------
// Local first, then Supabase. Loads wait until every write landed, so the screen never flashes stale rows.
async function write(query) {
  S.pending++;
  try {
    const { error } = await query;
    if (error) { toast(error.message, { error: true }); S.sig = ""; }
  } finally {
    S.pending--;
    if (S.pending === 0) scheduleLoad(400);
  }
}
function patchNode(id, changes) {
  const n = node(id);
  if (!n) return;
  Object.assign(n, changes, { updated_at: nowISO() });
  write(db.from("nodes").update({ ...changes, updated_at: n.updated_at }).eq("id", id));
}
function insertNode(fields) {
  const t = nowISO();
  const n = { id: uuid(), parent_id: null, kind: "item", title: "", body: null, status: null, view: null, color: null, column_type: null, details: null, due_at: null, estimate_minutes: null, position: 1, created_at: t, updated_at: t, deleted: false, ...fields };
  if (n.kind === "item" && !n.view) n.view = "list";
  if (n.kind === "note") { n.view = null; n.status = null; n.color = null; n.column_type = null; }
  S.nodes.push(n); S.byID.set(n.id, n);
  write(db.from("nodes").insert(n));
  return n;
}
function patchReminder(id, changes) {
  const r = S.reminders.find((x) => x.id === id);
  if (!r) return;
  Object.assign(r, changes, { updated_at: nowISO() });
  write(db.from("reminders").update({ ...changes, updated_at: r.updated_at }).eq("id", id));
}

function addNode(kind, title, parentID, extra = {}) {
  title = title.trim();
  if (!title) return null;
  const n = insertNode({ kind, title, parent_id: parentID || null, position: endPosition(parentID, null), ...extra });
  render();
  return n;
}
function addFolder(title, parentID) {
  const count = children(parentID).filter(isFolder).length;
  return addNode("item", title, parentID, { view: "folder", color: PRESETS[count % PRESETS.length][1] });
}
function addDefaultColumns(itemID) {
  ["todo", "doing", "done"].forEach((s, i) => insertNode({ kind: "item", title: LABEL[s], parent_id: itemID, column_type: s, position: i + 1 }));
}
function rename(id, title) {
  title = title.trim();
  if (title && node(id)?.title !== title) patchNode(id, { title });
  render();
}
// Cards that no longer fit their column move to one that does, so every view agrees.
function moveToFittingColumn(id) {
  const card = node(id), col = node(card?.parent_id);
  if (!col || !isColumn(col)) return;
  const board = node(col.parent_id);
  if (ColumnRules.accepts(col.column_type, card.status)) return;
  const target = fittingColumn(columnItems(board), card.status);
  if (target && target.id !== col.id) patchNode(id, { parent_id: target.id, position: endPosition(target.id, id) });
}
// A repeating reminder's own todo in the Reminders list, ticked, counts for this time only. It keeps repeating.
function cancelRemindersFor(nodeID) {
  const own = inRemindersList(node(nodeID));
  for (const r of S.reminders) if (r.node_id === nodeID && !r.done && !(own && r.repeat_rule)) patchReminder(r.id, { done: true });
}
function ensureRemindersList() {
  return remindersList() || insertNode({ kind: "item", title: "Reminders", view: "checklist", position: endPosition(null, null) });
}
// Every reminder is a todo you can tick off. One about nothing in particular gets its own in the Reminders list,
// with the reminder's id, so the phone and the website linking the same reminder make one item, not two.
function makeTodoFor(r) {
  if (node(r.id)) return node(r.id);
  const list = ensureRemindersList(), t = nowISO();
  const n = { id: r.id, parent_id: list.id, kind: "item", title: r.title, body: null, status: "todo", view: "list", color: null, column_type: null, details: null, due_at: null, estimate_minutes: null, position: endPosition(list.id, null), created_at: t, updated_at: t, deleted: false };
  S.nodes.push(n); S.byID.set(n.id, n);
  write(db.from("nodes").upsert(n));
  return n;
}
// After loading: link reminders that have no todo yet, and open ticked repeating ones again once they went off again.
function reconcileReminders() {
  const now = new Date();
  for (const r of S.reminders) {
    if (r.done) continue;
    if (!r.node_id) { patchReminder(r.id, { node_id: makeTodoFor(r).id }); continue; }
    const n = node(r.node_id);
    if (n && n.status === "done" && r.repeat_rule && inRemindersList(n) && occurrences(r, new Date(n.updated_at), now).length) patchNode(n.id, { status: "todo" });
  }
}
function setStatus(id, status, at) {
  const n = node(id);
  if (!n || n.status === status) return;
  patchNode(id, { status });
  if (status === "done") { cancelRemindersFor(id); if (at) burst(at.x, at.y); }
  moveToFittingColumn(id);
  render();
}
const toggleDone = (id, at) => setStatus(id, node(id)?.status === "done" ? "todo" : "done", at);
function setView(id, view) {
  const n = node(id);
  if (!n || n.kind !== "item") return;
  const changes = { view };
  if (view === "folder") { changes.status = null; if (!n.color) changes.color = PRESETS[children(n.parent_id).filter(isFolder).length % PRESETS.length][1]; }
  patchNode(id, changes);
  if (view === "board" && children(id).length === 0) addDefaultColumns(id);
  render();
}
function setType(id, type) {
  const n = node(id);
  if (!n) return;
  if (type === "note") {
    if (children(id).length) return toast("Only an empty item can become a note.", { error: true });
    patchNode(id, { kind: "note", view: null, status: null, column_type: null });
    return render();
  }
  if (n.kind === "note") patchNode(id, { kind: "item" });
  setView(id, type);
}
function moveTo(id, parentID, index) {
  const n = node(id);
  if (!n || (parentID && (parentID === id || isDescendant(parentID, id)))) return;
  const siblings = children(parentID).filter((x) => x.id !== id);
  const before = siblings[index - 1]?.position ?? null, after = siblings[index]?.position ?? null;
  patchNode(id, { parent_id: parentID || null, position: positionBetween(before, after) });
  render();
}
// Into a folder or list: at the end. Into a board: as a card in the column that fits.
function moveInto(id, parentID) {
  const target = node(parentID);
  if (parentID && (!target || target.kind === "note" || parentID === id || isDescendant(parentID, id))) return;
  if (target && isBoard(target)) {
    const col = fittingColumn(columnItems(target), node(id).status) || columnItems(target)[0];
    if (col) {
      patchNode(id, { parent_id: col.id, position: endPosition(col.id, id), status: ColumnRules.statusOnDrop(col.column_type, node(id).status) });
      return render();
    }
  }
  patchNode(id, { parent_id: parentID || null, position: endPosition(parentID, id) });
  render();
}
function deleteNodes(ids) {
  const all = [...new Set(ids.flatMap((id) => [id, ...descendants(id).map((d) => d.id)]))];
  const t = nowISO();
  for (const id of all) { const n = node(id); if (n) { n.deleted = true; n.updated_at = t; } }
  for (const id of all) for (const r of S.reminders) if (r.node_id === id && !r.done) patchReminder(r.id, { done: true });
  S.nodes = S.nodes.filter((n) => !n.deleted);
  write(db.from("nodes").update({ deleted: true, updated_at: t }).in("id", all));
  const titles = ids.map((id) => S.byID.get(id)?.title).filter(Boolean);
  render();
  toast(`Deleted ${titles.length === 1 ? titles[0] : titles.length + " items"}`, { action: () => restoreNodes(all) });
}
function restoreNodes(ids) {
  const t = nowISO();
  for (const id of ids) { const n = S.byID.get(id); if (n) { n.deleted = false; n.updated_at = t; S.nodes.push(n); } }
  write(db.from("nodes").update({ deleted: false, updated_at: t }).in("id", ids));
  render();
}
function addSection(title, boardID) {
  const s = addNode("item", title, boardID, { view: "board" });
  if (s) addDefaultColumns(s.id);
  render();
}
function addCard(title, col) {
  const source = col.sources[0];
  if (source) addNode("item", title, source.id, { status: ColumnRules.statusOnDrop(col.type, null) });
}
// Drop a card into a column. It stays in its own section; a missing column there is created.
function dropCard(cardID, key, boardID, index) {
  const card = node(cardID), board = node(boardID);
  const col = columns(board, node(S.section[boardID])).find((c) => c.key === key);
  if (!card || !board || !col) return;
  let container = board.id;
  const cur = node(card.parent_id);
  if (cur && isColumn(cur) && (cur.parent_id === board.id || sections(board).some((s) => s.id === cur.parent_id))) container = cur.parent_id;
  let target = col.sources.find((s) => s.parent_id === container);
  if (!target) target = insertNode({ kind: "item", title: col.title, parent_id: container, column_type: col.type, position: endPosition(container, null) });
  const list = col.cards.filter((c) => c.id !== cardID);
  const before = list[index - 1], after = list[index];
  const b = before && before.parent_id === target.id ? before.position : null;
  const a = after && after.parent_id === target.id ? after.position : null;
  const wasDone = card.status === "done";
  const status = ColumnRules.statusOnDrop(target.column_type, card.status);
  patchNode(cardID, { parent_id: target.id, position: b == null && a == null ? endPosition(target.id, cardID) : positionBetween(b, a), status });
  if (status === "done" && !wasDone) cancelRemindersFor(cardID);
  render();
}
// The column editor. Removed columns hand their cards to the first remaining column.
function saveColumns(drafts, container) {
  if (!drafts.length) return;
  const existing = columnItems(container);
  const kept = [];
  drafts.forEach((d, i) => {
    const title = d.title.trim() || (d.type ? LABEL[d.type] : "Column");
    const old = d.id && existing.find((c) => c.id === d.id);
    if (old) { patchNode(old.id, { title, column_type: d.type, position: i + 1 }); kept.push(old); }
    else kept.push(insertNode({ kind: "item", title, parent_id: container.id, column_type: d.type, position: i + 1 }));
  });
  const removed = existing.filter((c) => !kept.some((k) => k.id === c.id));
  for (const col of removed) {
    for (const card of children(col.id)) patchNode(card.id, { parent_id: kept[0].id, position: endPosition(kept[0].id, card.id), status: ColumnRules.statusOnDrop(kept[0].column_type, card.status) });
    deleteNodesQuiet([col.id]);
  }
  for (const col of columnItems(container)) for (const card of children(col.id)) moveToFittingColumn(card.id);
  render();
}
function deleteNodesQuiet(ids) {
  const t = nowISO();
  for (const id of ids) { const n = node(id); if (n) { n.deleted = true; n.updated_at = t; } }
  S.nodes = S.nodes.filter((n) => !n.deleted);
  write(db.from("nodes").update({ deleted: true, updated_at: t }).in("id", ids));
}
function saveReminder(r) {
  const existing = S.reminders.find((x) => x.id === r.id);
  const own = node(r.node_id);
  if (own && inRemindersList(own) && own.title !== r.title) patchNode(own.id, { title: r.title });
  if (existing) { patchReminder(r.id, { title: r.title, fire_at: r.fire_at, kind: r.kind, repeat_rule: r.repeat_rule, node_id: r.node_id, done: false }); }
  else {
    if (!r.node_id) r = { ...r, node_id: makeTodoFor(r).id };
    const row = { ...r, done: false, deleted: false, updated_at: nowISO() };
    S.reminders.push(row);
    write(db.from("reminders").insert(row));
  }
  render();
  toast(`${r.kind === "alarm" ? "Alarm" : "Reminder"} saved. It rings on your phone once Vox syncs.`);
}
function deleteReminder(id) {
  const r = S.reminders.find((x) => x.id === id);
  // Its own todo in the Reminders list goes with it. Items elsewhere stay.
  const own = r && inRemindersList(node(r.node_id)) ? node(r.node_id) : null;
  S.reminders = S.reminders.filter((x) => x.id !== id);
  write(db.from("reminders").update({ deleted: true, updated_at: nowISO() }).eq("id", id));
  if (own) deleteNodesQuiet([own.id]);
  render();
  if (r) toast(`Deleted ${r.title}`, { action: () => {
    S.reminders.push(r);
    write(db.from("reminders").update({ deleted: false, updated_at: nowISO() }).eq("id", id));
    if (own) { const t = nowISO(); own.deleted = false; own.updated_at = t; S.nodes.push(own); S.byID.set(own.id, own); write(db.from("nodes").update({ deleted: false, updated_at: t }).eq("id", own.id)); }
    render();
  } });
}

// ---------- Loading ----------
let loadTimer = null, pollTimer = null;
function scheduleLoad(ms = 0) { clearTimeout(loadTimer); loadTimer = setTimeout(load, ms); }
async function load() {
  if (!S.user) return;
  if (S.pending > 0 || DnD.active) return scheduleLoad(500);
  const [n, r, l] = await Promise.all([
    db.from("nodes").select("id,parent_id,kind,title,body,status,view,color,column_type,details,due_at,estimate_minutes,position,created_at,updated_at").eq("deleted", false).limit(10000),
    db.from("reminders").select("id,node_id,title,fire_at,kind,repeat_rule,done,updated_at").eq("deleted", false).limit(5000),
    db.from("action_log").select("id,created_at,transcript,summary,undone").order("created_at", { ascending: false }).limit(100),
  ]);
  const ok = !n.error && !r.error && !l.error;
  if (S.online !== ok) { S.online = ok; S.sig = ""; }
  if (!ok) return;
  if (S.pending > 0 || DnD.active) return scheduleLoad(500);
  const sig = [n.data.map((x) => x.id + x.updated_at).join(), r.data.map((x) => x.id + x.updated_at).join(), l.data.map((x) => x.id + x.undone).join()].join("|");
  if (sig === S.sig) return;
  S.sig = sig;
  S.nodes = n.data.map((x) => ({ ...x, deleted: false }));
  S.reminders = r.data;
  S.log = l.data;
  S.byID = new Map(S.nodes.map((x) => [x.id, x]));
  reconcileReminders();
  render();
}
function startSync() {
  load();
  clearInterval(pollTimer);
  pollTimer = setInterval(load, POLL_MS);
  // Instant updates when Realtime is on for the tables. Polling covers it otherwise.
  db.channel("vox-web").on("postgres_changes", { event: "*", schema: "public" }, () => scheduleLoad(250)).subscribe();
}

// ---------- Router ----------
function route() {
  const h = location.hash.replace(/^#\/?/, "");
  if (h.startsWith("node/")) return { name: "node", id: h.slice(5) };
  if (h === "reminders" || h === "history") return { name: h };
  return { name: "home" };
}
const go = (hash) => { location.hash = hash; };
window.addEventListener("hashchange", () => { S.editing = false; closeMenu(); render(true); });

// ---------- Rendering ----------
let renderQueued = false;
function render(fresh = false) {
  if (!S.user) return renderLogin();
  // Never pull the rug from under a drag or a half typed word.
  const typing = document.activeElement && $app.contains(document.activeElement) && /^(INPUT|TEXTAREA)$/.test(document.activeElement.tagName);
  if (DnD.active || (typing && !S.focusKey)) { renderQueued = true; return; }
  renderQueued = false;
  const r = route();
  const before = fresh ? null : snapshotRects();
  let html = "";
  let depth = 0;
  if (r.name === "node") {
    const n = node(r.id);
    if (!n) { html = screenMissing(); }
    else { depth = ancestors(n).length + 1; html = screenNode(n); }
  } else if (r.name === "reminders") { depth = 1; html = screenReminders(); }
  else if (r.name === "history") { depth = 1; html = screenHistory(); }
  else html = screenHome();
  document.documentElement.style.setProperty("--bg-blur", Math.min(depth * 7, 28) + "px");
  document.documentElement.style.setProperty("--bg-dim", Math.min(depth * 0.08, 0.32));
  $app.innerHTML = `<div class="screen" ${fresh ? "" : 'style="animation:none"'}>${html}</div>`;
  if (before) flipFrom(before);
  if (S.focusKey) {
    const el = $app.querySelector(`[data-key="${S.focusKey}"]`);
    S.focusKey = null;
    if (el) { el.focus(); if (el.select && el.dataset.select) el.select(); }
  }
  S.next = nextTimed();
  tick();
}
function snapshotRects() {
  const m = new Map();
  for (const el of $app.querySelectorAll("[data-drag]")) m.set(el.dataset.drag, el.getBoundingClientRect());
  return m;
}
// Elements that are still on screen slide from where they were to where they are now.
function flipFrom(before) {
  for (const el of $app.querySelectorAll("[data-drag]")) {
    const b = before.get(el.dataset.drag);
    if (!b) continue;
    const a = el.getBoundingClientRect();
    const dx = b.left - a.left, dy = b.top - a.top;
    if (!dx && !dy) continue;
    if (Math.abs(dx) > 1200 || Math.abs(dy) > 1200) continue;
    el.style.transition = "none";
    el.style.transform = `translate(${dx}px, ${dy}px)`;
    el.getBoundingClientRect();
    el.style.transition = "transform 0.28s var(--ease)";
    el.style.transform = "";
    el.addEventListener("transitionend", () => { el.style.transition = ""; }, { once: true });
  }
}

// Pieces
const live = () => `<span class="live ${S.online ? "" : "off"}"><i></i>${S.online ? "Live" : "Offline"}</span>`;
const stars = (v) => `<span class="stars">${[0, 1, 2, 3, 4].map((i) => I("star", i < v ? "" : "off")).join("")}</span>`;
function subtitleFor(n) {
  if (n.kind === "note") return esc((n.body || "").split("\n").find((l) => l.trim()) || "Note");
  const parts = [];
  const r = rating(n);
  const details = (n.details || []).filter((d) => r == null || d.key.toLowerCase() !== "rating");
  if (details.length) parts.push(esc(details.map((d) => `${d.key} ${d.value}`).join(" · ")));
  if (isBoard(n)) { const c = cardCount(n); parts.push(`Board · ${c === 1 ? "1 card" : c + " cards"}`); }
  else { const p = progress(n.id); if (p) parts.push(`${p.done}/${p.total} done`); else { const c = children(n.id).length; if (c) parts.push(c === 1 ? "1 item" : c + " items"); } }
  if (n.due_at) parts.push(`<span class="${new Date(n.due_at) < new Date() && n.status !== "done" ? "badge late" : ""}">${dueText(new Date(n.due_at))}</span>`);
  return (r != null ? stars(r) + " " : "") + parts.join(" · ");
}
function checkbox(n, tinted = false) {
  const st = n.status || "";
  return `<button class="check ${st} ${tinted ? "tinted" : ""}" data-act="toggle" data-id="${n.id}" title="${st === "done" ? "Mark not done" : "Mark done"}">${I("check")}</button>`;
}
// One row that opens an item or a note. Used on Home, in lists and in checklists.
function row(n, { into = true, dragable = true, tree = false, hasKids = false } = {}) {
  const container = n.kind === "note" || children(n.id).length > 0 || (n.view && n.view !== "list");
  let lead;
  if (n.status) lead = checkbox(n);
  else if (tree && n.kind === "item") lead = `<button class="check" data-act="toggle" data-id="${n.id}">${I("check")}</button>`;
  else if (container) lead = `<span class="tile ${isFolder(n) ? "folder" : ""}" style="--c:${tintOf(n)}">${I(iconFor(n))}</span>`;
  else lead = `<span class="dot"></span>`;
  const fold = tree ? `<button class="fold ${hasKids ? "" : "none"} ${S.collapsed.has(n.id) ? "closed" : ""}" data-act="fold" data-id="${n.id}">${I("down")}</button>` : "";
  const sub = subtitleFor(n);
  return `<div class="row ${n.status === "done" ? "done" : ""} ${container ? "" : "plain"}" data-node="${n.id}" ${dragable ? `data-drag="${n.id}"` : ""} ${into && n.kind === "item" ? `data-into="${n.id}"` : ""}>
    ${S.editing ? `<button class="del" data-act="delete" data-id="${n.id}" title="Delete">${I("minus")}</button>` : ""}
    ${fold}${lead}
    <div class="open" data-act="open" data-id="${n.id}">
      <div class="text"><div class="t">${esc(n.title)}</div>${sub ? `<div class="s">${sub}</div>` : ""}</div>
      ${n.status === "doing" ? '<span class="badge">Doing</span>' : ""}
    </div>
    <button class="more" data-act="menu" data-id="${n.id}">${I("dots")}</button>
    <span class="chev">${I("right")}</span>
  </div>`;
}
function addRow(parentID, placeholder = "Add item", kind = "item", extra = "") {
  return `<form class="addrow" data-add="${parentID || ""}" data-kind="${kind}" ${extra}><span class="plus">${I("plus")}</span><input placeholder="${esc(placeholder)}" data-key="add-${parentID || "home"}" autocomplete="off"></form>`;
}
const empty = (title, text) => `<div class="empty"><b>${esc(title)}</b>${esc(text)}</div>`;
const entryIcon = (e) => (e.kind === "alarm" ? "alarm" : e.kind === "deadline" ? "flag" : "bell");
// A reminder about an item opens the item. One with its own todo in the Reminders list opens its editor.
function entryAttrs(e) {
  if (!e.reminder) return `data-act="open" data-id="${e.node.id}"`;
  const item = node(e.reminder.node_id);
  return item && !inRemindersList(item) ? `data-act="open" data-id="${item.id}"` : `data-act="reminder" data-id="${e.reminder.id}"`;
}
// The todo an entry ticks off: the reminder's item, or the item with the deadline.
const entryTodo = (e) => (e.reminder ? node(e.reminder.node_id) : e.node);
const entryCheck = (e) => { const n = entryTodo(e); return n && n.kind === "item" ? checkbox(n) : ""; };
const entryDone = (e) => (entryTodo(e)?.status === "done" ? "done" : "");

// ----- Home -----
function screenHome() {
  const today = entriesOn(new Date()), tomorrow = entriesOn(addDays(new Date(), 1));
  const up = upcoming(6), todos = reminderTodos(), kids = children(null);
  const now = new Date();
  const dayBox = (title, entries) => `<section class="glass day"><h3>${title}</h3>${entries.length ? `<div class="rows">${entries.map((e) => `<div class="dayrow ${e.kind} ${e.when < now ? "past" : ""}" ${entryAttrs(e)}><span class="time">${fmtTime(e.when)}</span>${I(entryIcon(e))}<span class="t">${esc(e.title)}</span></div>`).join("")}</div>` : '<div class="none">Nothing planned</div>'}</section>`;
  return `
  <div class="topbar">
    <div class="left"><div>
      <div class="eyebrow">${now.toLocaleDateString([], { weekday: "long", month: "short", day: "numeric" })}</div>
      <h1 class="title">Vox</h1>
    </div></div>
    <div class="right">
      ${live()}
      <button class="btn glass ${S.editing ? "on" : ""}" data-act="edit">${I(S.editing ? "check" : "pencil")}<span class="label">${S.editing ? "Done" : "Edit"}</span></button>
      <button class="btn glass round" data-act="addmenu" data-parent="" title="Add">${I("plus")}</button>
      <button class="btn glass round" data-act="settings" title="Settings">${I("gear")}</button>
    </div>
  </div>
  <div id="pill"></div>
  <div class="home-grid">
    <div class="col">
      <div class="days">${dayBox("Today", today)}${dayBox("Tomorrow", tomorrow)}</div>
      <section class="glass card">
        <div class="card-head"><a class="link" href="#/reminders"><h2>Reminders<span class="count">${up.length + todos.length}</span></h2><span class="chev">${I("right")}</span></a></div>
        ${!up.length && !todos.length ? '<div class="hint">Tap + to add a reminder or alarm.</div>' : ""}
        ${up.map((e) => `<div class="row plain ${entryDone(e)}" ${entryAttrs(e)}>${entryCheck(e)}<span class="bullet" style="${e.kind === "alarm" ? "color:var(--accent)" : ""}">${I(entryIcon(e))}</span><div class="text"><div class="t">${esc(e.title)}</div><div class="s">${dayText(e.when, true)} at ${fmtTime(e.when)}${e.reminder?.repeat_rule ? " · " + repeatText(e.reminder.repeat_rule) : ""}</div></div>${e.kind === "alarm" ? '<span class="badge alarm">Alarm</span>' : ""}<span class="chev">${I("right")}</span></div>`).join("")}
        ${todos.length ? `<div class="eyebrow" style="padding:14px 6px 4px">To do</div>${todos.slice(0, 3).map((n) => row(n, { into: false, dragable: false })).join("")}` : ""}
      </section>
    </div>
    <div class="col">
      <section class="glass card">
        <div class="card-head"><h2>Notes<span class="count">${kids.length}</span></h2></div>
        ${kids.length ? "" : '<div class="hint">Nothing yet. Tap + to make a list, note or folder.</div>'}
        <div class="rows-list" data-zone data-parent="">${kids.map((n) => row(n)).join("")}</div>
      </section>
    </div>
  </div>`;
}
function tick() {
  const pill = document.getElementById("pill");
  if (!pill) return;
  const n = S.next;
  if (!n) { pill.innerHTML = ""; return; }
  const now = new Date();
  if (n.entry.when <= now) { S.next = nextTimed(); render(); return; }
  const total = n.entry.when - n.since, done = Math.min(Math.max((now - n.since) / total, 0), 1);
  const clock = clockText((n.entry.when - now) / 1000);
  if (!pill.firstChild) {
    pill.innerHTML = `<button class="pill glass" ${entryAttrs(n.entry)}>${I(entryIcon(n.entry))}<span class="clock"></span><span class="what">${esc(n.entry.title)}</span><span class="bar"><i></i></span></button>`;
  }
  pill.querySelector(".clock").textContent = clock;
  pill.querySelector(".bar i").style.width = done * 100 + "%";
}
setInterval(() => { if (S.user) tick(); }, 1000);
setInterval(() => { if (S.user) { S.next = nextTimed(); } }, 30000);

// ----- Node screen -----
function crumbs(n) {
  const chain = ancestors(n);
  return `<div class="eyebrow crumbs"><a href="#/" data-into="" data-into-band="full">Vox</a>${chain.map((a) => `<span class="sep">/</span><a href="#/node/${a.id}" data-into="${a.id}" data-into-band="full">${esc(a.title)}</a>`).join("")}</div>`;
}
function screenNode(n) {
  const view = n.kind === "note" ? "note" : n.view || "list";
  const back = ancestors(n).at(-1);
  let body;
  if (view === "note") body = noteView(n);
  else if (view === "board") body = boardView(n);
  else if (view === "folder") body = folderView(n);
  else if (view === "checklist") body = checklistView(n);
  else body = listView(n);
  const seg = n.kind === "item" ? `<div class="seg glass">${VIEWS.map((v) => `<button class="${view === v ? "on" : ""}" data-act="view" data-id="${n.id}" data-view="${v}" title="${VIEW_LABEL[v]}">${I(v)}<span class="label">${VIEW_LABEL[v]}</span></button>`).join("")}</div>` : "";
  return `
  <div class="topbar">
    <div class="left">
      <a class="btn glass round" href="#/${back ? "node/" + back.id : ""}" title="Back">${I("left")}</a>
      <div style="min-width:0">${crumbs(n)}<h1 class="title editable" data-act="rename" data-id="${n.id}" title="Click to rename">${esc(n.title)}</h1></div>
    </div>
    <div class="right">
      ${seg}
      ${n.kind === "item" && view !== "note" ? `<button class="btn glass ${S.editing ? "on" : ""}" data-act="edit">${I(S.editing ? "check" : "pencil")}</button>` : ""}
      ${n.kind === "item" ? `<button class="btn glass round" data-act="addmenu" data-parent="${n.id}" title="Add">${I("plus")}</button>` : ""}
      <button class="btn glass round" data-act="info" data-id="${n.id}" title="Info">${I("info")}</button>
    </div>
  </div>
  ${body}`;
}
function listView(n) {
  const kids = children(n.id);
  return `<section class="glass card">
    <div class="rows-list" data-zone data-parent="${n.id}">${kids.map((k) => row(k)).join("")}</div>
    ${kids.length ? "" : empty("Empty list", "Add the first item below, or drop something here.")}
    ${addRow(n.id)}
  </section>`;
}
function checklistView(n) {
  const tree = (pid) => {
    const kids = children(pid);
    if (!kids.length) return `<ul data-zone data-parent="${pid}"></ul>`;
    return `<ul data-zone data-parent="${pid}" class="${S.collapsed.has(pid) ? "closed" : ""}">${kids.map((k) => `<li data-drag="${k.id}" ${k.kind === "item" ? `data-into="${k.id}"` : ""}>${row(k, { dragable: false, into: false, tree: true, hasKids: children(k.id).length > 0 })}${k.kind === "item" ? tree(k.id) : ""}</li>`).join("")}</ul>`;
  };
  const kids = children(n.id);
  return `<section class="glass card">
    <div class="tree">${tree(n.id)}</div>
    ${kids.length ? "" : empty("Empty checklist", "Add the first item below.")}
    ${addRow(n.id, "Add item", "item", 'data-status="todo"')}
  </section>`;
}
function folderView(n) {
  const kids = children(n.id);
  return `<div class="grid" data-zone data-grid data-parent="${n.id}">
    ${kids.map((k) => `<div class="glass tile-card ${isFolder(k) ? "folder" : ""}" style="--c:${tintOf(k)}" data-node="${k.id}" data-drag="${k.id}" ${k.kind === "item" ? `data-into="${k.id}" data-into-band="full"` : ""} data-act="open" data-id="${k.id}">
      ${I(iconFor(k))}<span class="sp"></span>
      <div class="t">${esc(k.title)}</div><div class="s">${k.kind === "note" ? "Note" : isBoard(k) ? "Board" : (children(k.id).length === 1 ? "1 item" : children(k.id).length + " items")}</div>
      <button class="more" data-act="menu" data-id="${k.id}">${I("dots")}</button>
    </div>`).join("")}
  </div>
  ${kids.length ? "" : `<section class="glass card">${empty("Empty folder", "Use + to add a list, note or folder, or drag things onto this folder.")}</section>`}`;
}
function boardView(board) {
  const secs = sections(board);
  const section = node(S.section[board.id]);
  const cols = columns(board, secs.length ? section : null);
  const chips = secs.length ? `<div class="chips"><button class="chip glass ${!section ? "on" : ""}" data-act="section" data-board="${board.id}" data-id="">All</button>${secs.map((s) => `<button class="chip glass ${section?.id === s.id ? "on" : ""}" data-act="section" data-board="${board.id}" data-id="${s.id}">${esc(s.title)}</button>`).join("")}</div>` : "";
  const sectionName = (card, col) => { const src = col.sources.find((s) => s.id === card.parent_id); return src && src.parent_id !== board.id ? node(src.parent_id)?.title : null; };
  return `${chips}<div class="board">
    ${cols.map((col) => `<section class="glass column" style="--c:${col.type ? TINT[col.type] : ""}">
      <div class="head"><span class="d"></span><span class="n">${esc(col.title)}</span><span class="k">${col.cards.length}</span><button data-act="addcard" data-col="${col.key}" title="Add card">${I("plus")}</button></div>
      <div class="cards" data-zone data-column="${col.key}" data-board="${board.id}" data-parent="${col.sources[0].id}">
        ${col.cards.map((c) => card(c, col, !section && secs.length ? sectionName(c, col) : null)).join("")}
      </div>
      <form class="addcard" data-add="${col.sources[0].id}" data-kind="item" data-status="${ColumnRules.statusOnDrop(col.type, null)}">${I("plus")}<input placeholder="Add card" data-key="add-${col.key}" autocomplete="off"></form>
    </section>`).join("")}
    <button class="glass edit-tile" data-act="columns" data-id="${(section || board).id}">${I(cols.length ? "columns" : "plus")}${cols.length ? "Edit columns" : "Add columns"}</button>
  </div>`;
}
function card(c, col, sec) {
  const tint = col.type ? TINT[col.type] : null;
  const p = progress(c.id), r = rating(c);
  const sub = [];
  if (r != null) sub.push(stars(r));
  if (p) sub.push(`${p.done}/${p.total}`);
  if (c.due_at) sub.push(`<span class="${new Date(c.due_at) < new Date() && c.status !== "done" ? "badge late" : ""}">${dueText(new Date(c.due_at))}</span>`);
  if (sec) sub.push(`<span class="sec">${esc(sec)}</span>`);
  return `<div class="tcard ${tint ? "tinted" : ""} ${c.status === "done" ? "done" : ""}" style="--c:${tint || ""}" data-node="${c.id}" data-drag="${c.id}">
    ${checkbox(c, !!tint)}
    <div class="text" data-act="open" data-id="${c.id}"><div class="t">${esc(c.title)}</div>${sub.length ? `<div class="s">${sub.join(" · ")}</div>` : ""}</div>
    <button class="more" data-act="menu" data-id="${c.id}">${I("dots")}</button>
  </div>`;
}
function noteView(n) {
  return `<section class="glass note-editor"><textarea data-note="${n.id}" placeholder="Write something">${esc(n.body || "")}</textarea><div class="saved" id="saved"></div></section>`;
}
const screenMissing = () => `<div class="topbar"><div class="left"><a class="btn glass round" href="#/">${I("left")}</a><h1 class="title">Not found</h1></div></div><section class="glass card">${empty("This item is gone", "It may have been deleted on another device.")}</section>`;

// ----- Reminders screen -----
function screenReminders() {
  const up = upcoming(), todos = reminderTodos();
  return `<div class="topbar">
    <div class="left"><a class="btn glass round" href="#/">${I("left")}</a><div><div class="eyebrow">Everything on the clock</div><h1 class="title">Reminders</h1></div></div>
    <div class="right"><button class="btn glass" data-act="newreminder" data-kind="reminder">${I("bell")}<span class="label">Reminder</span></button><button class="btn glass" data-act="newreminder" data-kind="alarm">${I("alarm")}<span class="label">Alarm</span></button></div>
  </div>
  <section class="glass card">
    ${up.length ? up.map((e) => `<div class="row plain ${entryDone(e)}" ${entryAttrs(e)}>${entryCheck(e)}<span class="bullet" style="${e.kind === "alarm" ? "color:var(--accent)" : ""}">${I(entryIcon(e))}</span><div class="text"><div class="t">${esc(e.title)}</div><div class="s">${dayText(e.when, true)} at ${fmtTime(e.when)}${e.reminder?.repeat_rule ? " · " + repeatText(e.reminder.repeat_rule) : ""}${e.reminder?.node_id && node(e.reminder.node_id) ? " · " + esc(node(e.reminder.node_id).title) : ""}</div></div>${e.kind === "alarm" ? '<span class="badge alarm">Alarm</span>' : e.kind === "deadline" ? '<span class="badge todo">Deadline</span>' : ""}${e.reminder ? `<button class="more" style="opacity:1" data-act="reminder" data-id="${e.reminder.id}">${I("pencil")}</button>` : ""}</div>`).join("") : empty("Nothing coming up", "Add a reminder or an alarm with the buttons above.")}
    ${todos.length ? `<div class="eyebrow" style="padding:16px 6px 4px">To do</div><div class="rows-list" data-zone data-parent="${remindersList().id}">${todos.map((n) => row(n, { into: false })).join("")}</div>` : ""}
  </section>`;
}

// ----- History screen -----
function screenHistory() {
  return `<div class="topbar">
    <div class="left"><a class="btn glass round" href="#/">${I("left")}</a><div><div class="eyebrow">Voice commands</div><h1 class="title">History</h1></div></div>
  </div>
  <section class="glass card hist">
    ${S.log.length ? S.log.map((e) => `<div class="row ${e.undone ? "undone" : ""}"><span class="when">${dayText(new Date(e.created_at), true)}<br>${fmtTime(new Date(e.created_at))}</span><div class="text"><div class="t">${esc(e.summary || "(no summary)")}</div><div class="q">“${esc(e.transcript)}”</div></div>${e.undone ? '<span class="badge todo">Undone</span>' : ""}</div>`).join("") : empty("No commands yet", "Everything you say to Vox on the phone shows up here.")}
  </section>`;
}

// ----- Login -----
function renderLogin() {
  document.documentElement.style.setProperty("--bg-blur", "6px");
  const signup = S.mode === "signup";
  $app.innerHTML = `<div class="login"><form class="glass modal" id="loginForm">
    <h1 class="brand">Vo<span>x</span></h1>
    <p class="sub">${signup ? "Create an account. The same login works in the app." : "Your notes, tasks and alarms, from any browser."}</p>
    <div class="field"><label>Email</label><input id="email" type="email" autocomplete="email" required></div>
    <div class="field"><label>Password</label><input id="password" type="password" autocomplete="${signup ? "new-password" : "current-password"}" minlength="6" required></div>
    <button class="btn primary" style="width:100%" type="submit">${signup ? "Create account" : "Sign in"}</button>
    <div class="err" id="loginErr"></div>
    <div class="switch">${signup ? "Already have an account?" : "New here?"} <button type="button" id="switchMode">${signup ? "Sign in" : "Create one"}</button></div>
  </form></div>`;
  $app.querySelector("#switchMode").onclick = () => { S.mode = signup ? "signin" : "signup"; renderLogin(); };
  $app.querySelector("#loginForm").onsubmit = async (e) => {
    e.preventDefault();
    const email = $app.querySelector("#email").value.trim(), password = $app.querySelector("#password").value;
    const err = $app.querySelector("#loginErr");
    err.textContent = "";
    const { data, error } = signup ? await db.auth.signUp({ email, password }) : await db.auth.signInWithPassword({ email, password });
    if (error) err.textContent = error.message;
    else if (signup && !data.session) err.textContent = "Check your email for a confirmation link, then sign in.";
  };
}

// ---------- Menus and modals ----------
let menuEl = null;
function closeMenu() { if (menuEl) { menuEl.remove(); menuEl = null; } document.querySelectorAll(".menu-open").forEach((e) => e.classList.remove("menu-open")); }
function openMenu(items, x, y, anchorEl) {
  closeMenu();
  menuEl = document.createElement("div");
  menuEl.className = "menu glass";
  menuEl.innerHTML = items.map((it) => it === "-" ? "<hr>" : it.label ? `<div class="lbl">${esc(it.label)}</div>` : `<button class="${it.on ? "on" : ""} ${it.danger ? "danger" : ""}" data-i="${items.indexOf(it)}">${I(it.icon || "circle")}${esc(it.text)}</button>`).join("");
  document.body.appendChild(menuEl);
  const r = menuEl.getBoundingClientRect();
  menuEl.style.left = Math.min(x, innerWidth - r.width - 8) + "px";
  menuEl.style.top = Math.min(y, innerHeight - r.height - 8) + "px";
  menuEl.onclick = (e) => { const b = e.target.closest("button"); if (!b) return; const it = items[+b.dataset.i]; closeMenu(); it.run(); };
  if (anchorEl) anchorEl.closest(".row, .tcard, .tile-card")?.classList.add("menu-open");
}
document.addEventListener("pointerdown", (e) => { if (menuEl && !menuEl.contains(e.target)) closeMenu(); }, true);
document.addEventListener("keydown", (e) => { if (e.key === "Escape") { closeMenu(); closeModal(); } });

function nodeMenu(id, x, y, anchor) {
  const n = node(id);
  if (!n) return;
  const items = [
    { text: "Open", icon: "open", run: () => go("#/node/" + id) },
    { text: "Rename", icon: "pencil", run: () => renameModal(n) },
    { text: "Info", icon: "info", run: () => infoModal(n) },
  ];
  if (n.kind === "item" && !isFolder(n) && !isColumn(n)) {
    items.push("-", { label: "Status" });
    for (const s of ["todo", "doing", "done"]) items.push({ text: LABEL[s], icon: s === "done" ? "donecircle" : s === "doing" ? "half" : "circle", on: n.status === s, run: () => setStatus(id, s) });
    items.push({ text: "Not a task", icon: "x", on: !n.status, run: () => setStatus(id, null) });
  }
  items.push("-", { text: "Move to…", icon: "move", run: () => moveModal(n) }, { text: "Delete", icon: "trash", danger: true, run: () => deleteNodes([id]) });
  openMenu(items, x, y, anchor);
}
function addMenu(parentID, x, y) {
  const p = node(parentID);
  const items = [];
  if (!parentID) items.push({ text: "Reminder", icon: "bell", run: () => reminderModal(newReminder("reminder")) }, { text: "Alarm", icon: "alarm", run: () => reminderModal(newReminder("alarm")) }, "-");
  if (p && isBoard(p)) items.push({ text: "Column", icon: "columns", run: () => promptModal("New column", "Column name", (t) => { insertNode({ kind: "item", title: t, parent_id: p.id, position: endPosition(p.id, null) }); render(); }) }, { text: "Section", icon: "section", run: () => promptModal("New section", "Section name", (t) => addSection(t, p.id)) }, "-");
  items.push(
    { text: "Item", icon: "circle", run: () => promptModal("New item", "Title", (t) => addNode("item", t, parentID)) },
    { text: "Note", icon: "note", run: () => promptModal("New note", "Title", (t) => { const n = addNode("note", t, parentID); if (n) go("#/node/" + n.id); }) },
    { text: "Folder", icon: "folder", run: () => promptModal("New folder", "Folder name", (t) => addFolder(t, parentID)) },
  );
  if (!parentID) items.push("-", { text: "History", icon: "history", run: () => go("#/history") });
  openMenu(items, x, y);
}

let modalEl = null;
function openModal(html, onReady) {
  closeModal();
  modalEl = document.createElement("div");
  modalEl.className = "backdrop";
  modalEl.innerHTML = `<div class="glass modal">${html}</div>`;
  modalEl.addEventListener("pointerdown", (e) => { if (e.target === modalEl) closeModal(); });
  document.body.appendChild(modalEl);
  const m = modalEl.querySelector(".modal");
  m.querySelectorAll("[data-close]").forEach((b) => (b.onclick = closeModal));
  if (onReady) onReady(m);
  const first = m.querySelector("input:not([type=hidden]), textarea, select");
  if (first) { first.focus(); if (first.select) first.select(); }
  return m;
}
function closeModal() { if (modalEl) { modalEl.remove(); modalEl = null; } }
const field = (label, inner) => `<div class="field"><label>${label}</label>${inner}</div>`;

function promptModal(title, placeholder, done, initial = "") {
  openModal(`<h2>${esc(title)}</h2><form id="pf">${field("Title", `<input id="pv" value="${esc(initial)}" placeholder="${esc(placeholder)}" required>`)}<div class="actions"><button type="button" class="btn glass" data-close>Cancel</button><button class="btn primary" type="submit">OK</button></div></form>`, (m) => {
    m.querySelector("#pf").onsubmit = (e) => { e.preventDefault(); const v = m.querySelector("#pv").value.trim(); closeModal(); if (v) done(v); };
  });
}
const renameModal = (n) => promptModal("Rename", "Title", (t) => rename(n.id, t), n.title);

function newReminder(kind) {
  const d = new Date(); d.setHours(d.getHours() + 1, 0, 0, 0);
  return { id: uuid(), title: "", fire_at: d.toISOString(), kind, repeat_rule: null, node_id: null };
}
function reminderModal(r) {
  const saved = S.reminders.some((x) => x.id === r.id);
  const linked = node(r.node_id);
  const tasks = S.nodes.filter((n) => n.kind === "item" && n.status && n.status !== "done" && !isColumn(n)).sort((a, b) => a.title.localeCompare(b.title));
  openModal(`<h2>${saved ? "Edit" : "New"} ${r.kind === "alarm" ? "alarm" : "reminder"}</h2><form id="rf">
    ${field("Title", `<input id="rt" value="${esc(r.title)}" placeholder="${r.kind === "alarm" ? "Wake up" : "Call mom"}" required>`)}
    <div class="two">${field("Type", `<select id="rk"><option value="reminder" ${r.kind === "reminder" ? "selected" : ""}>Reminder</option><option value="alarm" ${r.kind === "alarm" ? "selected" : ""}>Alarm (rings)</option></select>`)}${field("When", `<input id="rw" type="datetime-local" value="${toLocalInput(new Date(r.fire_at))}" required>`)}</div>
    ${field("Repeat", `<select id="rr"><option value="">Once</option><option value="daily">Every day</option>${WEEKDAYS.map((d) => `<option value="weekly:${d}">${repeatText("weekly:" + d)}</option>`).join("")}</select>`)}
    ${field("Linked task", `<select id="rn"><option value="">None</option>${linked && !tasks.some((t) => t.id === linked.id) ? `<option value="${linked.id}" selected>${esc(linked.title)}</option>` : ""}${tasks.map((t) => `<option value="${t.id}" ${t.id === r.node_id ? "selected" : ""}>${esc(t.title)}</option>`).join("")}</select>`)}
    <div class="actions">${saved ? `<button type="button" class="btn danger" id="rd">${I("trash")}Delete</button>` : ""}<span class="sp"></span><button type="button" class="btn glass" data-close>Cancel</button><button class="btn primary" type="submit">Save</button></div>
  </form>`, (m) => {
    m.querySelector("#rr").value = r.repeat_rule || "";
    if (saved) m.querySelector("#rd").onclick = () => { closeModal(); deleteReminder(r.id); };
    m.querySelector("#rf").onsubmit = (e) => {
      e.preventDefault();
      const when = new Date(m.querySelector("#rw").value);
      if (isNaN(when)) return;
      const rule = m.querySelector("#rr").value || null;
      if (when <= new Date() && !rule) return toast("Pick a time in the future.", { error: true });
      closeModal();
      saveReminder({ ...r, title: m.querySelector("#rt").value.trim(), kind: m.querySelector("#rk").value, fire_at: when.toISOString(), repeat_rule: rule, node_id: m.querySelector("#rn").value || null });
    };
  });
}
function infoModal(n) {
  const type = n.kind === "note" ? "note" : n.view || "list";
  const details = (n.details || []).concat([{ key: "", value: "" }]);
  const folders = S.nodes.filter((f) => isFolder(f) && f.id !== n.id && !isDescendant(f.id, n.id));
  const linked = S.reminders.filter((r) => r.node_id === n.id && !r.done);
  openModal(`<h2>Info</h2><form id="if">
    ${field("Title", `<input id="it" value="${esc(n.title)}" required>`)}
    <div class="two">
      ${field("Type", `<select id="iv">${VIEWS.map((v) => `<option value="${v}" ${type === v ? "selected" : ""}>${VIEW_LABEL[v]}</option>`).join("")}<option value="note" ${type === "note" ? "selected" : ""}>Note</option></select>`)}
      ${field("Where", `<select id="ip"><option value="">Home</option>${folders.map((f) => `<option value="${f.id}" ${f.id === n.parent_id ? "selected" : ""}>${esc(f.title)}</option>`).join("")}${n.parent_id && !folders.some((f) => f.id === n.parent_id) ? `<option value="${n.parent_id}" selected>${esc(node(n.parent_id)?.title || "Current place")}</option>` : ""}</select>`)}
    </div>
    <div id="ifolder" ${type === "folder" ? "" : "hidden"}>${field("Color", `<div class="swatches">${PRESETS.map(([name, hex]) => `<button type="button" class="swatch ${(n.color || PRESETS[0][1]).toUpperCase() === hex ? "on" : ""}" style="background:${hex}" title="${name}" data-hex="${hex}"></button>`).join("")}<span class="swatch custom" title="Custom"><input type="color" id="ic" value="${esc(n.color || PRESETS[0][1])}"></span></div>`)}</div>
    <div id="itask" ${type === "folder" || type === "note" ? "hidden" : ""}>
      <div class="two">
        ${field("Status", `<select id="is"><option value="">Not a task</option>${["todo", "doing", "done"].map((s) => `<option value="${s}" ${n.status === s ? "selected" : ""}>${LABEL[s]}</option>`).join("")}</select>`)}
        ${field("Estimate (minutes)", `<input id="ie" type="number" min="0" value="${n.estimate_minutes ?? ""}" placeholder="30">`)}
      </div>
      ${field("Due", `<input id="id" type="datetime-local" value="${n.due_at ? toLocalInput(new Date(n.due_at)) : ""}">`)}
    </div>
    ${field("Details", `<div class="details-list" id="idl">${details.map((d) => `<div class="d"><input placeholder="rating" value="${esc(d.key)}" data-k><input placeholder="4" value="${esc(d.value)}" data-v><button type="button" data-rm>${I("x")}</button></div>`).join("")}</div>`)}
    ${linked.length ? field("Reminders", linked.map((r) => `<div class="row plain" data-act="reminder" data-id="${r.id}" style="cursor:pointer"><span class="bullet">${I(r.kind)}</span><div class="text"><div class="t">${esc(r.title)}</div><div class="s">${dayText(new Date(r.fire_at), true)} at ${fmtTime(new Date(r.fire_at))}</div></div><span class="chev">${I("right")}</span></div>`).join("")) : ""}
    <div class="actions"><button type="button" class="btn danger" id="idel">${I("trash")}Delete</button><span class="sp"></span><button type="button" class="btn glass" data-close>Cancel</button><button class="btn primary" type="submit">Save</button></div>
  </form>`, (m) => {
    let color = n.color || null;
    const iv = m.querySelector("#iv");
    iv.onchange = () => { m.querySelector("#ifolder").hidden = iv.value !== "folder"; m.querySelector("#itask").hidden = iv.value === "folder" || iv.value === "note"; };
    m.querySelectorAll(".swatch[data-hex]").forEach((b) => (b.onclick = () => { color = b.dataset.hex; m.querySelectorAll(".swatch").forEach((s) => s.classList.toggle("on", s === b)); }));
    m.querySelector("#ic").oninput = (e) => { color = e.target.value.toUpperCase(); m.querySelectorAll(".swatch").forEach((s) => s.classList.remove("on")); };
    const dl = m.querySelector("#idl");
    dl.addEventListener("input", (e) => { const last = dl.lastElementChild; if (e.target.closest(".d") === last && (last.querySelector("[data-k]").value || last.querySelector("[data-v]").value)) dl.insertAdjacentHTML("beforeend", `<div class="d"><input placeholder="key" data-k><input placeholder="value" data-v><button type="button" data-rm>${I("x")}</button></div>`); });
    dl.addEventListener("click", (e) => { const b = e.target.closest("[data-rm]"); if (b && dl.children.length > 1) b.closest(".d").remove(); });
    m.querySelector("#idel").onclick = () => { closeModal(); deleteNodes([n.id]); if (route().id === n.id) go(n.parent_id ? "#/node/" + n.parent_id : "#/"); };
    m.querySelector("#if").onsubmit = (e) => {
      e.preventDefault();
      const title = m.querySelector("#it").value.trim();
      const newType = iv.value;
      const changes = {};
      if (title && title !== n.title) changes.title = title;
      const details = [...dl.querySelectorAll(".d")].map((d) => ({ key: d.querySelector("[data-k]").value.trim(), value: d.querySelector("[data-v]").value.trim() })).filter((d) => d.key);
      if (JSON.stringify(details) !== JSON.stringify(n.details || [])) changes.details = details.length ? details : null;
      if (newType !== "note" && newType !== "folder") {
        const st = m.querySelector("#is").value || null;
        if (st !== n.status) changes.status = st;
        const est = m.querySelector("#ie").value;
        changes.estimate_minutes = est === "" ? null : parseInt(est, 10);
        const due = m.querySelector("#id").value;
        changes.due_at = due ? new Date(due).toISOString() : null;
      }
      if (newType === "folder" && color && color !== n.color) changes.color = color;
      const parent = m.querySelector("#ip").value || null;
      closeModal();
      if (Object.keys(changes).length) {
        patchNode(n.id, changes);
        if (changes.status === "done") cancelRemindersFor(n.id);
        if ("status" in changes) moveToFittingColumn(n.id);
      }
      if (newType !== type) setType(n.id, newType);
      if (parent !== (n.parent_id || null)) moveInto(n.id, parent);
      render();
    };
  });
}
function moveModal(n) {
  const places = S.nodes.filter((f) => f.kind === "item" && f.id !== n.id && !isDescendant(f.id, n.id) && !isColumn(f)).sort((a, b) => a.title.localeCompare(b.title));
  openModal(`<h2>Move “${esc(n.title)}”</h2><form id="mf">${field("To", `<select id="mp"><option value="">Home</option>${places.map((f) => `<option value="${f.id}" ${f.id === n.parent_id ? "selected" : ""}>${esc(ancestors(f).map((a) => a.title + " / ").join("") + f.title)}${isBoard(f) ? " (board)" : isFolder(f) ? " (folder)" : ""}</option>`).join("")}</select>`)}<div class="actions"><button type="button" class="btn glass" data-close>Cancel</button><button class="btn primary" type="submit">Move</button></div></form>`, (m) => {
    m.querySelector("#mf").onsubmit = (e) => { e.preventDefault(); const p = m.querySelector("#mp").value || null; closeModal(); if (p !== (n.parent_id || null)) moveInto(n.id, p); };
  });
}
function columnsModal(container) {
  let drafts = columnItems(container).map((c) => ({ id: c.id, title: c.title, type: c.column_type }));
  if (!drafts.length) drafts = ["todo", "doing", "done"].map((s) => ({ id: null, title: LABEL[s], type: s }));
  const rowHTML = (d, i) => `<div class="c" data-i="${i}"><span class="grip">${I("grip")}</span><input value="${esc(d.title)}" placeholder="Column" data-t><select data-ty><option value="">Neutral</option>${["todo", "doing", "done"].map((s) => `<option value="${s}" ${d.type === s ? "selected" : ""}>${LABEL[s]}</option>`).join("")}</select><button type="button" data-rm title="Remove">${I("x")}</button></div>`;
  openModal(`<h2>Columns</h2><form id="cf"><div class="cols-list" id="cl">${drafts.map(rowHTML).join("")}</div><div class="actions" style="justify-content:flex-start;margin-top:12px"><button type="button" class="btn glass sm" id="cadd">${I("plus")}Add column</button></div><p class="hint">Removing a column moves its cards to the first remaining one.</p><div class="actions"><button type="button" class="btn glass" data-close>Cancel</button><button class="btn primary" type="submit">Save</button></div></form>`, (m) => {
    const list = m.querySelector("#cl");
    m.querySelector("#cadd").onclick = () => { list.insertAdjacentHTML("beforeend", rowHTML({ id: null, title: "", type: null }, list.children.length)); list.lastElementChild.querySelector("input").focus(); };
    list.addEventListener("click", (e) => { const b = e.target.closest("[data-rm]"); if (b && list.children.length > 1) b.closest(".c").remove(); });
    // Grip to reorder.
    list.addEventListener("pointerdown", (e) => {
      const grip = e.target.closest(".grip"); if (!grip) return;
      const item = grip.closest(".c"); item.style.opacity = 0.5;
      const move = (ev) => { const over = document.elementFromPoint(ev.clientX, ev.clientY)?.closest(".c"); if (over && over !== item && over.parentElement === list) { const r = over.getBoundingClientRect(); list.insertBefore(item, ev.clientY < r.top + r.height / 2 ? over : over.nextSibling); } };
      const up = () => { item.style.opacity = ""; document.removeEventListener("pointermove", move); document.removeEventListener("pointerup", up); };
      document.addEventListener("pointermove", move); document.addEventListener("pointerup", up);
      e.preventDefault();
    });
    m.querySelector("#cf").onsubmit = (e) => {
      e.preventDefault();
      const out = [...list.children].map((c) => ({ id: drafts[+c.dataset.i]?.id || null, title: c.querySelector("[data-t]").value, type: c.querySelector("[data-ty]").value || null }));
      closeModal();
      saveColumns(out, container);
    };
  });
}
function settingsModal() {
  const dark = +(localStorage.getItem("glassDarkness") ?? 0.6), frost = +(localStorage.getItem("glassFrost") ?? 0.3);
  openModal(`<h2>Settings</h2>
    ${field("Account", `<div class="row plain" style="padding:6px 0"><div class="text"><div class="t">${esc(S.user.email)}</div><div class="s">Same account as the app. Changes here reach the phone when Vox syncs.</div></div><button type="button" class="btn glass sm" id="so">Sign out</button></div>`)}
    ${field("Glass darkness", `<div class="range"><input type="range" min="0" max="1" step="0.05" value="${dark}" id="sd"><span>${Math.round(dark * 100)}%</span></div>`)}
    ${field("Frost", `<div class="range"><input type="range" min="0" max="1" step="0.05" value="${frost}" id="sf"><span>${Math.round(frost * 100)}%</span></div>`)}
    ${field("More", `<a class="btn glass sm" href="#/history" data-close>${I("history")}Voice command history</a>`)}
    <div class="actions"><button type="button" class="btn primary" data-close>Done</button></div>`, (m) => {
    m.querySelector("#so").onclick = () => { closeModal(); db.auth.signOut(); };
    const bind = (id, key, cssVar) => { const el = m.querySelector(id); el.oninput = () => { localStorage.setItem(key, el.value); applyGlass(); el.nextElementSibling.textContent = Math.round(el.value * 100) + "%"; }; };
    bind("#sd", "glassDarkness", "--dark"); bind("#sf", "glassFrost", "--frost");
  });
}
function applyGlass() {
  try {
    document.documentElement.style.setProperty("--dark", localStorage.getItem("glassDarkness") ?? 0.6);
    document.documentElement.style.setProperty("--frost", localStorage.getItem("glassFrost") ?? 0.3);
  } catch {}
}

// ---------- Clicks and forms ----------
let suppressClick = false;
$app.addEventListener("click", (e) => {
  if (suppressClick) { e.preventDefault(); e.stopPropagation(); return; }
  const el = e.target.closest("[data-act]");
  if (!el || !$app.contains(el)) return;
  if (e.target.closest("a") && !el.dataset.act) return;
  const { act, id } = el.dataset;
  // The innermost action wins: a checkbox inside a tile should not open the tile.
  if (e.target.closest("[data-act]") !== el) return;
  switch (act) {
    case "open": go("#/node/" + id); break;
    case "toggle": { const r = el.getBoundingClientRect(); toggleDone(id, { x: r.left + r.width / 2, y: r.top + r.height / 2 }); break; }
    case "menu": { const r = el.getBoundingClientRect(); e.preventDefault(); nodeMenu(id, r.left, r.bottom + 4, el); break; }
    case "delete": deleteNodes([id]); break;
    case "edit": S.editing = !S.editing; render(); break;
    case "addmenu": { const r = el.getBoundingClientRect(); addMenu(el.dataset.parent || null, r.right - 200, r.bottom + 6); break; }
    case "settings": settingsModal(); break;
    case "info": infoModal(node(id)); break;
    case "reminder": { const r = S.reminders.find((x) => x.id === id); if (r) { closeModal(); reminderModal(r); } break; }
    case "newreminder": reminderModal(newReminder(el.dataset.kind)); break;
    case "view": setView(id, el.dataset.view); break;
    case "section": S.section[el.dataset.board] = id || null; render(); break;
    case "columns": columnsModal(node(id)); break;
    case "fold": S.collapsed.has(id) ? S.collapsed.delete(id) : S.collapsed.add(id); render(); break;
    case "addcard": { const inp = $app.querySelector(`[data-key="add-${el.dataset.col}"]`); if (inp) inp.focus(); break; }
    case "rename": {
      const n = node(id);
      el.outerHTML = `<h1 class="title"><input value="${esc(n.title)}" data-rename="${id}" data-key="rename" data-select="1"></h1>`;
      const inp = $app.querySelector("[data-rename]"); inp.focus(); inp.select();
      break;
    }
  }
});
document.addEventListener("click", (e) => { if (modalEl && modalEl.contains(e.target)) { const el = e.target.closest("[data-act=reminder]"); if (el) { const r = S.reminders.find((x) => x.id === el.dataset.id); if (r) { closeModal(); reminderModal(r); } } } });
$app.addEventListener("submit", (e) => {
  const f = e.target.closest("form[data-add]");
  if (!f) return;
  e.preventDefault();
  const inp = f.querySelector("input");
  const title = inp.value.trim();
  if (!title) return;
  S.focusKey = inp.dataset.key;
  addNode(f.dataset.kind, title, f.dataset.add || null, f.dataset.status ? { status: f.dataset.status } : {});
});
$app.addEventListener("keydown", (e) => {
  const r = e.target.closest("[data-rename]");
  if (r && e.key === "Enter") { e.preventDefault(); rename(r.dataset.rename, r.value); }
  if (r && e.key === "Escape") render();
});
$app.addEventListener("focusout", (e) => {
  const r = e.target.closest?.("[data-rename]");
  if (r) rename(r.dataset.rename, r.value);
  else if (renderQueued) setTimeout(() => { if (renderQueued && !DnD.active) render(); }, 50);
});
let noteTimer = null;
$app.addEventListener("input", (e) => {
  const ta = e.target.closest("[data-note]");
  if (!ta) return;
  const saved = document.getElementById("saved");
  if (saved) saved.textContent = "Saving…";
  clearTimeout(noteTimer);
  noteTimer = setTimeout(() => { patchNode(ta.dataset.note, { body: ta.value }); if (saved) saved.textContent = "Saved"; }, 600);
});
$app.addEventListener("contextmenu", (e) => {
  const el = e.target.closest("[data-node]");
  if (!el || e.target.closest("input, textarea")) return;
  e.preventDefault();
  nodeMenu(el.dataset.node, e.clientX, e.clientY, el);
});

// ---------- Drag and drop ----------
// Pointer based, so it is the same on mouse and touch. The element you grab stays in place as a faded
// placeholder and a ghost follows the pointer. Dropping on a folder, list or breadcrumb moves inside it.
const DnD = {
  active: false,
  s: null,
  onDown(e) {
    if (e.button !== 0 || modalEl) return;
    const el = e.target.closest("[data-drag]");
    if (!el || !$app.contains(el) || e.target.closest("button, input, textarea, select, a, [data-nodrag]")) return;
    const zone = el.parentElement.closest("[data-zone]");
    if (!zone) return;
    const s = DnD.s = { el, zone, id: el.dataset.drag, x: e.clientX, y: e.clientY, sx: e.clientX, sy: e.clientY, started: false, touch: e.pointerType === "touch", into: null, timer: null };
    if (s.touch) s.timer = setTimeout(() => DnD.start(), 320);
    document.addEventListener("pointermove", DnD.onMove);
    document.addEventListener("pointerup", DnD.onUp);
    document.addEventListener("pointercancel", DnD.onUp);
  },
  start() {
    const s = DnD.s;
    if (!s || s.started) return;
    s.started = true;
    DnD.active = true;
    closeMenu();
    const r = s.el.getBoundingClientRect();
    s.offX = s.x - r.left; s.offY = s.y - r.top; s.w = r.width; s.h = r.height;
    const g = s.ghost = s.el.cloneNode(true);
    g.classList.add("drag-ghost", "live");
    g.removeAttribute("data-drag");
    g.style.width = r.width + "px"; g.style.height = r.height + "px";
    document.body.appendChild(g);
    s.el.classList.add("drag-placeholder");
    document.body.classList.add("dragging");
    DnD.place();
  },
  onMove(e) {
    const s = DnD.s;
    if (!s) return;
    s.x = e.clientX; s.y = e.clientY;
    if (!s.started) {
      const d = Math.hypot(s.x - s.sx, s.y - s.sy);
      if (s.touch) { if (d > 10) DnD.cleanup(); return; }
      if (d > 6) DnD.start(); else return;
    }
    e.preventDefault();
    DnD.place();
    DnD.autoscroll();
    DnD.target();
  },
  place() {
    const s = DnD.s;
    s.ghost.style.transform = `translate(${s.x - s.offX}px, ${s.y - s.offY}px) scale(1.03)`;
  },
  autoscroll() {
    const s = DnD.s, m = 60;
    if (s.y < m) scrollBy(0, -12); else if (s.y > innerHeight - m) scrollBy(0, 12);
    const board = document.elementFromPoint(s.x, s.y)?.closest(".board");
    if (board) { const r = board.getBoundingClientRect(); if (s.x < r.left + m) board.scrollLeft -= 14; else if (s.x > r.right - m) board.scrollLeft += 14; }
  },
  target() {
    const s = DnD.s;
    const under = document.elementFromPoint(s.x, s.y);
    if (!under) return;
    // Dropping inside something: folders, lists, breadcrumbs. Rows only in their middle band, so reordering stays easy.
    const into = under.closest("[data-into]");
    if (into && into.dataset.into !== s.id && !isDescendant(into.dataset.into, s.id) && !(into.dataset.into === "" && !node(s.id).parent_id)) {
      const r = into.getBoundingClientRect();
      const full = into.dataset.intoBand === "full";
      const band = full || (s.y > r.top + r.height * 0.3 && s.y < r.bottom - r.height * 0.3);
      if (band && !(into.dataset.into === node(s.id).parent_id && !full)) { DnD.setInto(into); return; }
    }
    DnD.setInto(null);
    const zone = under.closest("[data-zone]");
    if (!zone) return;
    const parent = zone.dataset.parent;
    if (parent && (parent === s.id || isDescendant(parent, s.id))) return;
    const items = [...zone.children].filter((c) => c.hasAttribute("data-drag") && c !== s.el);
    let index = items.length;
    if (zone.hasAttribute("data-grid")) {
      for (let i = 0; i < items.length; i++) {
        const r = items[i].getBoundingClientRect();
        if (s.y < r.top) { index = i; break; }
        if (s.y <= r.bottom && s.x < r.left + r.width / 2) { index = i; break; }
      }
    } else {
      index = items.filter((it) => { const r = it.getBoundingClientRect(); return r.top + r.height / 2 < s.y; }).length;
    }
    const ref = items[index] || null;
    if (s.el.parentElement === zone && s.el.nextElementSibling === ref) return;
    if (s.el.parentElement === zone && ref === null && zone.lastElementChild === s.el) return;
    const moving = [...new Set([...zone.children, ...s.el.parentElement.children])].filter((c) => c.hasAttribute("data-drag") && c !== s.el);
    const before = new Map(moving.map((c) => [c, c.getBoundingClientRect()]));
    zone.insertBefore(s.el, ref);
    for (const c of moving) {
      const b = before.get(c), a = c.getBoundingClientRect();
      const dx = b.left - a.left, dy = b.top - a.top;
      if (!dx && !dy) continue;
      c.style.transition = "none"; c.style.transform = `translate(${dx}px, ${dy}px)`;
      c.getBoundingClientRect();
      c.style.transition = "transform 0.2s var(--ease)"; c.style.transform = "";
    }
    document.querySelectorAll(".column.over").forEach((c) => c.classList.remove("over"));
    zone.closest(".column")?.classList.add("over");
  },
  setInto(el) {
    const s = DnD.s;
    if (s.into === el) return;
    if (s.into) s.into.classList.remove("drop-into", "drop-into-crumb");
    s.into = el;
    if (el) el.classList.add(el.matches(".crumbs a") ? "drop-into-crumb" : "drop-into");
  },
  onUp() {
    const s = DnD.s;
    if (!s) return;
    if (!s.started) return DnD.cleanup();
    const result = s.into ? { into: s.into.dataset.into } : DnD.result();
    const r = s.el.getBoundingClientRect();
    const g = s.ghost;
    g.classList.remove("live");
    g.style.transform = `translate(${r.left}px, ${r.top}px) scale(1)`;
    g.style.opacity = s.into ? 0 : 0.9;
    setTimeout(() => g.remove(), 230);
    s.ghost = null;
    DnD.cleanup();
    suppressClick = true;
    setTimeout(() => (suppressClick = false), 50);
    if (result) handleDrop(s.id, result);
  },
  result() {
    const s = DnD.s;
    const zone = s.el.parentElement.closest("[data-zone]");
    if (!zone) return null;
    const items = [...zone.children].filter((c) => c.hasAttribute("data-drag"));
    const index = items.indexOf(s.el);
    if (zone.dataset.column) return { column: zone.dataset.column, board: zone.dataset.board, index };
    return { parent: zone.dataset.parent, index };
  },
  cleanup() {
    const s = DnD.s;
    if (!s) return;
    clearTimeout(s.timer);
    if (s.ghost) s.ghost.remove();
    s.el.classList.remove("drag-placeholder");
    DnD.setInto(null);
    document.body.classList.remove("dragging");
    document.querySelectorAll(".column.over").forEach((c) => c.classList.remove("over"));
    document.removeEventListener("pointermove", DnD.onMove);
    document.removeEventListener("pointerup", DnD.onUp);
    document.removeEventListener("pointercancel", DnD.onUp);
    DnD.s = null;
    DnD.active = false;
    if (renderQueued) render();
  },
};
document.addEventListener("pointerdown", DnD.onDown);
document.addEventListener("touchmove", (e) => { if (DnD.active) e.preventDefault(); }, { passive: false });
document.addEventListener("contextmenu", (e) => { if (DnD.s?.touch || DnD.active) e.preventDefault(); });
function handleDrop(id, res) {
  if (res.into !== undefined) return moveInto(id, res.into || null);
  if (res.column) return dropCard(id, res.column, res.board, res.index);
  const n = node(id);
  const same = (n.parent_id || "") === res.parent && children(n.parent_id).filter((x) => x.id !== id).findIndex((x) => x.position > n.position) === res.index;
  if (!same) moveTo(id, res.parent || null, res.index);
  else render();
}

// ---------- Auth ----------
db.auth.onAuthStateChange((event, session) => {
  if (event === "TOKEN_REFRESHED") return;
  const user = session?.user || null;
  const was = !!S.user;
  S.user = user;
  if (user) {
    if (!was) { S.sig = ""; S.nodes = []; S.reminders = []; S.byID = new Map(); render(true); startSync(); }
  } else {
    clearInterval(pollTimer);
    S.nodes = []; S.reminders = []; S.log = []; S.byID = new Map();
    renderLogin();
  }
});
document.addEventListener("visibilitychange", () => { if (!document.hidden && S.user) load(); });
applyGlass();
renderLogin();
