const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (id) => document.getElementById(id);

// --- live state -------------------------------------------------------------

function applyState(muted, deviceName) {
  const badge = $("badge");
  badge.textContent = "LIVE";
  badge.classList.toggle("muted", muted);
  $("state").textContent = muted ? "Microphone muted" : "Microphone live";
  $("toggle").textContent = muted ? "Unmute" : "Mute";
  if (deviceName) $("device").textContent = deviceName;
}

async function refresh() {
  const s = await invoke("get_state");
  applyState(s.muted, s.device_name);
}

$("toggle").addEventListener("click", async () => {
  const muted = await invoke("toggle");
  applyState(muted);
});

listen("mic:state", (e) => applyState(e.payload));

// --- settings ---------------------------------------------------------------

let settings = null;

async function loadSettings() {
  settings = await invoke("get_settings");
  $("sound").checked = settings.sound_enabled;
  $("visual").checked = settings.visual_enabled;
  $("launch").checked = settings.launch_at_login;
  $("recorder").textContent = prettyAccelerator(settings.hotkey);
}

async function persist() {
  await invoke("save_settings", { settings });
}

$("sound").addEventListener("change", (e) => { settings.sound_enabled = e.target.checked; persist(); });
$("visual").addEventListener("change", (e) => { settings.visual_enabled = e.target.checked; persist(); });
$("launch").addEventListener("change", (e) => { settings.launch_at_login = e.target.checked; persist(); });

// --- hotkey recorder --------------------------------------------------------

const recorder = $("recorder");
let recording = false;

recorder.addEventListener("click", () => {
  recording = true;
  recorder.classList.add("recording");
  recorder.textContent = "Press keys…";
});

window.addEventListener("keydown", (e) => {
  if (!recording) return;
  e.preventDefault();
  if (e.code === "Escape") { stopRecording(); return; }
  const accel = buildAccelerator(e);
  if (!accel) return; // modifier-only, keep waiting
  settings.hotkey = accel;
  stopRecording();
  recorder.textContent = prettyAccelerator(accel);
  persist();
});

function stopRecording() {
  recording = false;
  recorder.classList.remove("recording");
  if (settings) recorder.textContent = prettyAccelerator(settings.hotkey);
}

function keyToken(e) {
  const code = e.code;
  if (code.startsWith("Key")) return code.slice(3);
  if (code.startsWith("Digit")) return code.slice(5);
  if (/^F\d{1,2}$/.test(code)) return code;
  const map = {
    Space: "Space", Enter: "Enter", Backspace: "Backspace", Tab: "Tab",
    ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left", ArrowRight: "Right",
    Minus: "-", Equal: "=", BracketLeft: "[", BracketRight: "]",
    Semicolon: ";", Quote: "'", Comma: ",", Period: ".", Slash: "/", Backquote: "`",
  };
  return map[code] || null;
}

function buildAccelerator(e) {
  // Record Ctrl and Cmd/Meta as distinct keys (don't collapse to CmdOrCtrl),
  // so the registered shortcut matches the physical keys the user pressed.
  const parts = [];
  if (e.ctrlKey) parts.push("Control");
  if (e.altKey) parts.push("Alt");
  if (e.shiftKey) parts.push("Shift");
  if (e.metaKey) parts.push("Super");
  const key = keyToken(e);
  if (!key) return null;
  parts.push(key);
  return parts.join("+");
}

function prettyAccelerator(accel) {
  if (!accel) return "-";
  const mac = navigator.platform.toLowerCase().includes("mac");
  const sym = mac
    ? { CmdOrCtrl: "⌘", Super: "⌘", Meta: "⌘", Command: "⌘", Cmd: "⌘",
        Control: "⌃", Ctrl: "⌃", Alt: "⌥", Option: "⌥", Shift: "⇧" }
    : { CmdOrCtrl: "Ctrl", Super: "Win", Meta: "Win", Command: "Win", Cmd: "Ctrl",
        Control: "Ctrl", Ctrl: "Ctrl", Alt: "Alt", Option: "Alt", Shift: "Shift" };
  const sep = mac ? "" : " + ";
  return accel.split("+").map((t) => sym[t] || t).join(sep);
}

// --- devices + volume -------------------------------------------------------

async function loadDevices() {
  const devices = await invoke("list_devices");
  const sel = $("devices");
  sel.innerHTML = "";
  for (const d of devices) {
    const opt = document.createElement("option");
    opt.value = d.id;
    opt.textContent = d.name;
    opt.selected = d.is_default;
    sel.appendChild(opt);
  }
  sel.onchange = async () => {
    await invoke("select_device", { id: sel.value });
    await refresh();
    await loadVolume();
  };
}

async function loadVolume() {
  const v = await invoke("get_volume");
  const row = $("volume-row");
  if (v === null || v === undefined) { row.style.display = "none"; return; }
  row.style.display = "flex";
  $("volume").value = v;
}

$("volume").addEventListener("input", (e) => {
  invoke("set_volume", { value: parseFloat(e.target.value) });
});

// --- support / footer -------------------------------------------------------

$("beer").addEventListener("click", () => invoke("open_donation"));
$("miccheck").addEventListener("click", () => invoke("open_mic_check"));

async function loadInfo() {
  const info = await invoke("app_info");
  $("footer").textContent = `${info.name} ${info.version} · ${info.license} · © 2026 ${info.author}`;
}

// --- init -------------------------------------------------------------------

(async () => {
  await Promise.all([refresh(), loadSettings(), loadDevices(), loadInfo()]);
  await loadVolume();
})();
