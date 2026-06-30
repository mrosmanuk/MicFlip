// Prevent a console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod audio;
mod miccheck;

use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use audio::{Device, Mic};
use miccheck::MicCheck;
use serde::{Deserialize, Serialize};
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

const DONATION_URL: &str = "https://paypal.me/rosmanuk";
const TRAY_ID: &str = "main";

// --- Settings ---------------------------------------------------------------

#[derive(Serialize, Deserialize, Clone)]
struct Settings {
    sound_enabled: bool,
    visual_enabled: bool,
    launch_at_login: bool,
    hotkey: String,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            sound_enabled: true,
            visual_enabled: true,
            launch_at_login: false,
            hotkey: "CmdOrCtrl+Shift+M".to_string(),
        }
    }
}

struct AppState {
    mic: Mic,
    mic_check: MicCheck,
    settings: Mutex<Settings>,
    config_path: PathBuf,
}

impl AppState {
    fn save(&self) {
        if let Ok(settings) = self.settings.lock() {
            if let Ok(json) = serde_json::to_string_pretty(&*settings) {
                if let Some(dir) = self.config_path.parent() {
                    let _ = fs::create_dir_all(dir);
                }
                let _ = fs::write(&self.config_path, json);
            }
        }
    }
}

// --- Tray + broadcast -------------------------------------------------------

fn tray_image(muted: bool) -> Image<'static> {
    let bytes: &[u8] = if muted {
        include_bytes!("../icons/tray-muted.png")
    } else {
        include_bytes!("../icons/tray-live.png")
    };
    Image::from_bytes(bytes).expect("valid tray png")
}

/// Update the tray icon and notify any open windows of the new state.
fn refresh_state(app: &AppHandle, muted: bool) {
    if let Some(tray) = app.tray_by_id(TRAY_ID) {
        let _ = tray.set_icon(Some(tray_image(muted)));
        let _ = tray.set_tooltip(Some(if muted { "Microphone muted" } else { "Microphone live" }));
    }
    let _ = app.emit("mic:state", muted);
}

fn toggle_from_app(app: &AppHandle) {
    let muted = app.state::<AppState>().mic.toggle();
    on_toggle(app, muted);
}

/// Update everything the user perceives after a toggle: tray icon, the open
/// windows, plus the optional sound and HUD notifications.
fn on_toggle(app: &AppHandle, muted: bool) {
    refresh_state(app, muted);
    let (sound, visual) = {
        let state = app.state::<AppState>();
        let g = state.settings.lock().unwrap();
        (g.sound_enabled, g.visual_enabled)
    };
    if sound {
        play_feedback(muted);
    }
    if visual {
        show_hud(app, muted);
    }
}

fn play_feedback(muted: bool) {
    #[cfg(target_os = "macos")]
    {
        let sound = if muted { "Funk" } else { "Tink" };
        let _ = std::process::Command::new("afplay")
            .arg(format!("/System/Library/Sounds/{sound}.aiff"))
            .spawn();
    }
    #[cfg(target_os = "windows")]
    {
        let wav = if muted { "chord.wav" } else { "chimes.wav" };
        let cmd = format!(
            "(New-Object Media.SoundPlayer 'C:\\Windows\\Media\\{wav}').PlaySync()"
        );
        let _ = std::process::Command::new("powershell")
            .args(["-NoProfile", "-c", &cmd])
            .spawn();
    }
    #[cfg(target_os = "linux")]
    {
        // Best-effort; relies on libcanberra sounds being present.
        let id = if muted { "dialog-warning" } else { "message" };
        let _ = std::process::Command::new("canberra-gtk-play")
            .args(["-i", id])
            .spawn();
    }
}

static HUD_GEN: AtomicU64 = AtomicU64::new(0);

fn show_hud(app: &AppHandle, muted: bool) {
    let Some(hud) = app.get_webview_window("hud") else {
        return;
    };
    let _ = hud.emit("hud:show", muted);
    position_hud(&hud);
    let _ = hud.show();

    // Auto-hide after a moment; a generation counter prevents an earlier
    // timer from hiding the HUD that a later toggle just re-showed.
    let generation = HUD_GEN.fetch_add(1, Ordering::SeqCst) + 1;
    let app = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(1200));
        if HUD_GEN.load(Ordering::SeqCst) == generation {
            if let Some(hud) = app.get_webview_window("hud") {
                let _ = hud.hide();
            }
        }
    });
}

fn position_hud(hud: &tauri::WebviewWindow) {
    if let Ok(Some(monitor)) = hud.current_monitor() {
        let screen = monitor.size();
        if let Ok(win) = hud.outer_size() {
            let x = (screen.width as i32 - win.width as i32) / 2;
            let y = (screen.height as f64 * 0.78) as i32;
            let _ = hud.set_position(tauri::PhysicalPosition::new(x, y));
        }
    }
}

// --- Commands ---------------------------------------------------------------

#[derive(Serialize)]
struct MicState {
    muted: bool,
    device_name: String,
}

#[tauri::command]
fn get_state(state: State<AppState>) -> MicState {
    MicState {
        muted: state.mic.is_muted(),
        device_name: state.mic.current_device_name(),
    }
}

#[tauri::command]
fn toggle(app: AppHandle) -> bool {
    let muted = app.state::<AppState>().mic.toggle();
    on_toggle(&app, muted);
    muted
}

#[tauri::command]
fn set_muted(app: AppHandle, muted: bool) {
    app.state::<AppState>().mic.set_muted(muted);
    on_toggle(&app, muted);
}

#[tauri::command]
fn list_devices(state: State<AppState>) -> Vec<Device> {
    state.mic.devices()
}

#[tauri::command]
fn select_device(app: AppHandle, id: String) {
    let state = app.state::<AppState>();
    state.mic.select_device(&id);
    let muted = state.mic.is_muted();
    refresh_state(&app, muted);
}

#[tauri::command]
fn get_volume(state: State<AppState>) -> Option<f32> {
    state.mic.volume()
}

#[tauri::command]
fn set_volume(state: State<AppState>, value: f32) {
    state.mic.set_volume(value);
}

#[tauri::command]
fn get_settings(state: State<AppState>) -> Settings {
    state.settings.lock().unwrap().clone()
}

#[tauri::command]
fn save_settings(app: AppHandle, settings: Settings) {
    let state = app.state::<AppState>();
    let old_hotkey = state.settings.lock().unwrap().hotkey.clone();
    {
        let mut guard = state.settings.lock().unwrap();
        *guard = settings.clone();
    }
    state.save();
    if settings.hotkey != old_hotkey {
        register_hotkey(&app, &settings.hotkey);
    }
}

#[tauri::command]
fn open_donation() {
    open_url(DONATION_URL);
}

#[tauri::command]
fn open_mic_check(app: AppHandle) {
    open_mic_check_window(&app);
}

#[tauri::command]
fn start_mic_check(app: AppHandle) {
    app.state::<AppState>().mic_check.start(app.clone());
}

#[tauri::command]
fn stop_mic_check(app: AppHandle) {
    app.state::<AppState>().mic_check.stop();
}

#[derive(Serialize)]
struct AppInfo {
    name: String,
    version: String,
    author: String,
    license: String,
    donation_url: String,
}

#[tauri::command]
fn app_info() -> AppInfo {
    AppInfo {
        name: "MicFlip".into(),
        version: env!("CARGO_PKG_VERSION").into(),
        author: "Maksim Rosmanuk".into(),
        license: "MIT License".into(),
        donation_url: DONATION_URL.into(),
    }
}

// --- Helpers ----------------------------------------------------------------

fn open_url(url: &str) {
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("open").arg(url).spawn();
    #[cfg(target_os = "windows")]
    let _ = std::process::Command::new("cmd").args(["/C", "start", "", url]).spawn();
    #[cfg(target_os = "linux")]
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}

fn register_hotkey(app: &AppHandle, accelerator: &str) {
    let gs = app.global_shortcut();
    let _ = gs.unregister_all();
    if let Err(e) = gs.register(accelerator) {
        eprintln!("MicFlip: failed to register hotkey '{accelerator}': {e}");
    }
}

fn open_settings_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("settings") {
        let _ = win.show();
        let _ = win.set_focus();
        return;
    }
    let _ = WebviewWindowBuilder::new(app, "settings", WebviewUrl::App("index.html".into()))
        .title("MicFlip Settings")
        .inner_size(460.0, 600.0)
        .resizable(false)
        .build();
}

fn open_mic_check_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("miccheck") {
        let _ = win.show();
        let _ = win.set_focus();
        return;
    }
    let _ = WebviewWindowBuilder::new(app, "miccheck", WebviewUrl::App("miccheck.html".into()))
        .title("Mic Check")
        .inner_size(380.0, 260.0)
        .resizable(false)
        .build();
}

// --- App entry --------------------------------------------------------------

fn main() {
    tauri::Builder::default()
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _shortcut, event| {
                    if event.state() == ShortcutState::Pressed {
                        toggle_from_app(app);
                    }
                })
                .build(),
        )
        .setup(|app| {
            let handle = app.handle();

            // Load settings.
            let config_path = app
                .path()
                .app_config_dir()
                .unwrap_or_else(|_| PathBuf::from("."))
                .join("settings.json");
            let settings: Settings = fs::read_to_string(&config_path)
                .ok()
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_default();

            let state = AppState {
                mic: Mic::new(),
                mic_check: MicCheck::new(),
                settings: Mutex::new(settings.clone()),
                config_path,
            };
            let initial_muted = state.mic.is_muted();
            app.manage(state);

            // Tray.
            let toggle_i = MenuItem::with_id(app, "toggle", "Toggle Mute", true, None::<&str>)?;
            let miccheck_i = MenuItem::with_id(app, "miccheck", "Mic Check…", true, None::<&str>)?;
            let settings_i = MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", "Quit MicFlip", true, None::<&str>)?;
            let sep = PredefinedMenuItem::separator(app)?;
            let menu = Menu::with_items(app, &[&toggle_i, &miccheck_i, &settings_i, &sep, &quit_i])?;

            TrayIconBuilder::with_id(TRAY_ID)
                .icon(tray_image(initial_muted))
                .tooltip(if initial_muted { "Microphone muted" } else { "Microphone live" })
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "toggle" => toggle_from_app(app),
                    "miccheck" => open_mic_check_window(app),
                    "settings" => open_settings_window(app),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;

            // Pre-create the hidden HUD overlay window (transparent, floating).
            let _ = WebviewWindowBuilder::new(app, "hud", WebviewUrl::App("hud.html".into()))
                .title("MicFlip HUD")
                .inner_size(220.0, 220.0)
                .decorations(false)
                .transparent(true)
                .always_on_top(true)
                .skip_taskbar(true)
                .resizable(false)
                .shadow(false)
                .focused(false)
                .visible(false)
                .build()?;

            // Global shortcut.
            register_hotkey(&handle, &settings.hotkey);

            // Menu-bar-only on macOS (no Dock icon).
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_state,
            toggle,
            set_muted,
            list_devices,
            select_device,
            get_volume,
            set_volume,
            get_settings,
            save_settings,
            open_donation,
            open_mic_check,
            start_mic_check,
            stop_mic_check,
            app_info,
        ])
        .build(tauri::generate_context!())
        .expect("error building MicFlip")
        .run(|_app, event| {
            // Keep running with no windows open (tray app).
            if let tauri::RunEvent::ExitRequested { api, .. } = event {
                api.prevent_exit();
            }
        });
}
