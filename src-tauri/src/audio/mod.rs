//! Cross-platform microphone control.
//!
//! Each OS provides a `platform` backend with a small set of free functions
//! operating on the *default input device*. The shared `Mic` controller layers
//! the robust mute strategy on top (drive input volume to zero AND set the
//! hardware mute flag), mirroring the original macOS implementation — many
//! devices expose a mute flag that reports muted yet still pass audio, so
//! zeroing the gain is the reliable silencer.

use std::collections::HashMap;
use std::sync::Mutex;

#[cfg(target_os = "macos")]
#[path = "macos.rs"]
mod platform;

#[cfg(target_os = "windows")]
#[path = "windows.rs"]
mod platform;

#[cfg(target_os = "linux")]
#[path = "linux.rs"]
mod platform;

#[derive(serde::Serialize, Clone)]
pub struct Device {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

const SILENT: f32 = 0.0001;

pub struct Mic {
    /// Per-device-id volume saved when muting, restored on unmute.
    volume_backup: Mutex<HashMap<String, f32>>,
}

impl Mic {
    pub fn new() -> Self {
        Mic {
            volume_backup: Mutex::new(HashMap::new()),
        }
    }

    pub fn is_muted(&self) -> bool {
        if let Some(v) = platform::get_volume_default() {
            if v <= SILENT {
                return true;
            }
        }
        platform::get_mute_default().unwrap_or(false)
    }

    pub fn set_muted(&self, muted: bool) {
        if platform::supports_volume_default() {
            let id = platform::default_id();
            if muted {
                if let Some(v) = platform::get_volume_default() {
                    if v > SILENT {
                        self.volume_backup.lock().unwrap().insert(id, v);
                    }
                }
                platform::set_volume_default(0.0);
            } else {
                let restore = self
                    .volume_backup
                    .lock()
                    .unwrap()
                    .get(&id)
                    .copied()
                    .unwrap_or(1.0);
                platform::set_volume_default(restore);
            }
        }
        // Also set the hardware mute flag (proper indicator + the only lever on
        // devices without a volume control).
        platform::set_mute_default(muted);
    }

    /// Toggle and return the resulting muted state.
    pub fn toggle(&self) -> bool {
        let next = !self.is_muted();
        self.set_muted(next);
        self.is_muted()
    }

    pub fn devices(&self) -> Vec<Device> {
        platform::devices()
    }

    pub fn select_device(&self, id: &str) {
        platform::set_default(id);
    }

    pub fn volume(&self) -> Option<f32> {
        platform::get_volume_default()
    }

    pub fn set_volume(&self, value: f32) {
        platform::set_volume_default(value.clamp(0.0, 1.0));
    }

    pub fn current_device_name(&self) -> String {
        platform::default_name().unwrap_or_else(|| "—".to_string())
    }
}
