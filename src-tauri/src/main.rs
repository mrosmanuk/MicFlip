// Prevent a console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod audio;

use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

use audio::{Device, Mic};
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
    let state = app.state::<AppState>();
    let muted = state.mic.toggle();
    refresh_state(app, muted);
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
    refresh_state(&app, muted);
    muted
}

#[tauri::command]
fn set_muted(app: AppHandle, muted: bool) {
    app.state::<AppState>().mic.set_muted(muted);
    refresh_state(&app, muted);
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

// --- App entry --------------------------------------------------------------

fn main() {
    // Hidden one-shot for verifying the OS mute backend without the UI.
    if std::env::args().any(|a| a == "--toggle-test") {
        let mic = Mic::new();
        let muted = mic.toggle();
        println!("toggled -> muted={muted} device={}", mic.current_device_name());
        return;
    }

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
                settings: Mutex::new(settings.clone()),
                config_path,
            };
            let initial_muted = state.mic.is_muted();
            app.manage(state);

            // Tray.
            let toggle_i = MenuItem::with_id(app, "toggle", "Toggle Mute", true, None::<&str>)?;
            let settings_i = MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;
            let beer_i = MenuItem::with_id(app, "beer", "Buy Me a Beer 🍺", true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", "Quit MicFlip", true, None::<&str>)?;
            let sep = PredefinedMenuItem::separator(app)?;
            let menu = Menu::with_items(app, &[&toggle_i, &settings_i, &sep, &beer_i, &quit_i])?;

            TrayIconBuilder::with_id(TRAY_ID)
                .icon(tray_image(initial_muted))
                .tooltip(if initial_muted { "Microphone muted" } else { "Microphone live" })
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "toggle" => toggle_from_app(app),
                    "settings" => open_settings_window(app),
                    "beer" => open_url(DONATION_URL),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;

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
