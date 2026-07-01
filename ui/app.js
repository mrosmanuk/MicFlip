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
  if (!Array.isArray(settings.device_hotkeys)) settings.device_hotkeys = [];
  $("sound").checked = settings.sound_enabled;
  $("visual").checked = settings.visual_enabled;
  $("notify-switch").checked = settings.device_switch_notify;
  $("launch").checked = settings.launch_at_login;
  $("recorder").textContent = prettyAccelerator(settings.hotkey);
}

async function persist() {
  await invoke("save_settings", { settings });
}

$("sound").addEventListener("change", (e) => { settings.sound_enabled = e.target.checked; persist(); });
$("visual").addEventListener("change", (e) => { settings.visual_enabled = e.target.checked; persist(); });
$("notify-switch").addEventListener("change", (e) => { settings.device_switch_notify = e.target.checked; persist(); });
$("launch").addEventListener("change", (e) => { settings.launch_at_login = e.target.checked; persist(); });

// --- hotkey recorder --------------------------------------------------------

// A single recorder can be active at a time (the mute toggle or any device
// row). `activeRecorder` holds the button plus a callback fired on capture.
const recorder = $("recorder");
let activeRecorder = null;

function startRecording(el, onCapture) {
  if (activeRecorder) cancelRecording();
  activeRecorder = { el, onCapture, prev: el.textContent };
  el.classList.add("recording");
  el.textContent = "Press keys…";
}

function cancelRecording() {
  if (!activeRecorder) return;
  activeRecorder.el.classList.remove("recording");
  activeRecorder.el.textContent = activeRecorder.prev;
  activeRecorder = null;
}

window.addEventListener("keydown", (e) => {
  if (!activeRecorder) return;
  e.preventDefault();
  if (e.code === "Escape") { cancelRecording(); return; }
  const accel = buildAccelerator(e);
  if (!accel) return; // modifier-only, keep waiting
  const { el, onCapture } = activeRecorder;
  el.classList.remove("recording");
  activeRecorder = null;
  onCapture(accel);
});

recorder.addEventListener("click", () => {
  startRecording(recorder, (accel) => {
    settings.hotkey = accel;
    recorder.textContent = prettyAccelerator(accel);
    persist();
  });
});

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

let inputDevices = [];
let outputDevices = [];

async function loadDevices() {
  inputDevices = await invoke("list_devices");
  outputDevices = await invoke("list_output_devices");
  const sel = $("devices");
  sel.innerHTML = "";
  for (const d of inputDevices) {
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

  const outSel = $("output-devices");
  outSel.innerHTML = "";
  for (const d of outputDevices) {
    const opt = document.createElement("option");
    opt.value = d.id;
    opt.textContent = d.name;
    opt.selected = d.is_default;
    outSel.appendChild(opt);
  }
  outSel.onchange = async () => {
    await invoke("select_output_device", { id: outSel.value });
    await loadOutputVolume();
  };

  renderDeviceHotkeys();
}

// --- device shortcuts -------------------------------------------------------

function devicesFor(kind) {
  return kind === "output" ? outputDevices : inputDevices;
}

function renderDeviceHotkeys() {
  const container = $("device-hotkeys");
  container.innerHTML = "";
  settings.device_hotkeys.forEach((hk, i) => {
    container.appendChild(deviceHotkeyRow(hk, i));
  });
}

function deviceHotkeyRow(hk, index) {
  const row = document.createElement("div");
  row.className = "hotkey-row";

  const kindSel = document.createElement("select");
  kindSel.className = "hk-kind";
  for (const [value, label] of [["input", "Input"], ["output", "Output"]]) {
    const opt = document.createElement("option");
    opt.value = value;
    opt.textContent = label;
    opt.selected = hk.kind === value;
    kindSel.appendChild(opt);
  }

  const deviceSel = document.createElement("select");
  deviceSel.className = "hk-device";
  fillDeviceOptions(deviceSel, hk.kind, hk.device_id);

  const keys = document.createElement("button");
  keys.className = "recorder hk-keys";
  keys.textContent = hk.accelerator ? prettyAccelerator(hk.accelerator) : "Set keys…";

  const remove = document.createElement("button");
  remove.className = "hk-remove";
  remove.textContent = "×";
  remove.title = "Remove shortcut";

  kindSel.onchange = () => {
    hk.kind = kindSel.value;
    const list = devicesFor(hk.kind);
    const first = list[0];
    hk.device_id = first ? first.id : "";
    hk.device_name = first ? first.name : "";
    fillDeviceOptions(deviceSel, hk.kind, hk.device_id);
    persist();
  };

  deviceSel.onchange = () => {
    hk.device_id = deviceSel.value;
    hk.device_name = deviceSel.selectedOptions[0]?.textContent || "";
    persist();
  };

  keys.onclick = () => {
    startRecording(keys, (accel) => {
      hk.accelerator = accel;
      keys.textContent = prettyAccelerator(accel);
      persist();
    });
  };

  remove.onclick = () => {
    settings.device_hotkeys.splice(index, 1);
    renderDeviceHotkeys();
    persist();
  };

  row.append(kindSel, deviceSel, keys, remove);
  return row;
}

function fillDeviceOptions(sel, kind, selectedId) {
  sel.innerHTML = "";
  const list = devicesFor(kind);
  if (list.length === 0) {
    const opt = document.createElement("option");
    opt.textContent = "No devices";
    opt.disabled = true;
    opt.selected = true;
    sel.appendChild(opt);
    return;
  }
  for (const d of list) {
    const opt = document.createElement("option");
    opt.value = d.id;
    opt.textContent = d.name;
    opt.selected = d.id === selectedId;
    sel.appendChild(opt);
  }
}

$("add-hotkey").addEventListener("click", () => {
  const first = inputDevices[0];
  settings.device_hotkeys.push({
    accelerator: "",
    kind: "input",
    device_id: first ? first.id : "",
    device_name: first ? first.name : "",
  });
  renderDeviceHotkeys();
});

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

async function loadOutputVolume() {
  const v = await invoke("get_output_volume");
  const row = $("output-volume-row");
  if (v === null || v === undefined) { row.style.display = "none"; return; }
  row.style.display = "flex";
  $("output-volume").value = v;
}

$("output-volume").addEventListener("input", (e) => {
  invoke("set_output_volume", { value: parseFloat(e.target.value) });
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
  await loadSettings(); // device-shortcut rows read `settings`, so load it first
  await Promise.all([refresh(), loadDevices(), loadInfo()]);
  await Promise.all([loadVolume(), loadOutputVolume()]);
})();
