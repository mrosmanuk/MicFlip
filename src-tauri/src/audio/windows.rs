//! Windows WASAPI backend.
//!
//! Mutes/adjusts the default capture (microphone) endpoint via
//! `IAudioEndpointVolume` — the canonical OS-level mic mute on Windows, honored
//! by every app. COM is initialized per call (idempotent).
//!
//! NOTE: device enumeration/switching is intentionally minimal for v1 (returns
//! the current default endpoint). Full enumeration + default-device switching
//! (which needs the undocumented IPolicyConfig) is a TODO to validate on real
//! Windows hardware.

#![allow(non_snake_case)]

use super::Device;
use windows::core::Interface;
use windows::Win32::Foundation::BOOL;
use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
use windows::Win32::Media::Audio::{
    eCapture, eConsole, IMMDevice, IMMDeviceEnumerator, MMDeviceEnumerator,
};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_MULTITHREADED,
};

fn ensure_com() {
    // Safe to call repeatedly; RPC_E_CHANGED_MODE / S_FALSE are fine to ignore.
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
    }
}

fn default_endpoint() -> Option<IMMDevice> {
    ensure_com();
    unsafe {
        let enumerator: IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL).ok()?;
        enumerator.GetDefaultAudioEndpoint(eCapture, eConsole).ok()
    }
}

fn endpoint_volume() -> Option<IAudioEndpointVolume> {
    let device = default_endpoint()?;
    unsafe { device.Activate::<IAudioEndpointVolume>(CLSCTX_ALL, None).ok() }
}

pub fn default_id() -> String {
    "default".to_string()
}

pub fn default_name() -> Option<String> {
    Some("Default microphone".to_string())
}

pub fn get_mute_default() -> Option<bool> {
    let vol = endpoint_volume()?;
    unsafe { vol.GetMute().ok().map(|b: BOOL| b.as_bool()) }
}

pub fn set_mute_default(muted: bool) {
    if let Some(vol) = endpoint_volume() {
        unsafe {
            let _ = vol.SetMute(BOOL::from(muted), None);
        }
    }
}

pub fn supports_volume_default() -> bool {
    endpoint_volume().is_some()
}

pub fn get_volume_default() -> Option<f32> {
    let vol = endpoint_volume()?;
    unsafe { vol.GetMasterVolumeLevelScalar().ok() }
}

pub fn set_volume_default(value: f32) {
    if let Some(vol) = endpoint_volume() {
        unsafe {
            let _ = vol.SetMasterVolumeLevelScalar(value.clamp(0.0, 1.0), None);
        }
    }
}

pub fn devices() -> Vec<Device> {
    // v1: expose the current default endpoint only.
    vec![Device {
        id: default_id(),
        name: default_name().unwrap_or_else(|| "Default microphone".to_string()),
        is_default: true,
    }]
}

pub fn set_default(_id: &str) {
    // No public Windows API to set the default device; requires IPolicyConfig.
    // TODO: implement via IPolicyConfig and validate on Windows.
}
