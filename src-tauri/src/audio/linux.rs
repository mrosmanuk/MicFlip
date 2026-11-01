//! Linux backend via `pactl` (PulseAudio / PipeWire's pulse shim).
//!
//! `@DEFAULT_SOURCE@` targets the active microphone. Works out of the box on
//! modern PipeWire and classic PulseAudio systems. ALSA-only systems without a
//! pulse layer aren't covered. Untested on this build host — validate on Linux.

use super::Device;
use std::process::Command;

fn pactl(args: &[&str]) -> Option<String> {
    let output = Command::new("pactl").args(args).output().ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).into_owned())
}

pub fn default_id() -> String {
    pactl(&["get-default-source"])
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "@DEFAULT_SOURCE@".to_string())
}

pub fn default_name() -> Option<String> {
    let id = default_id();
    // Match the default source's description from the verbose list.
    let list = pactl(&["list", "sources"])?;
    let mut current_name: Option<&str> = None;
    for line in list.lines() {
        let t = line.trim();
        if let Some(rest) = t.strip_prefix("Name: ") {
            current_name = Some(rest);
        } else if let Some(desc) = t.strip_prefix("Description: ") {
            if current_name == Some(id.as_str()) {
                return Some(desc.to_string());
            }
        }
    }
    Some(id)
}

pub fn get_mute_default() -> Option<bool> {
    let out = pactl(&["get-source-mute", "@DEFAULT_SOURCE@"])?;
    Some(out.to_lowercase().contains("yes"))
}

pub fn set_mute_default(muted: bool) {
    let _ = pactl(&[
        "set-source-mute",
        "@DEFAULT_SOURCE@",
        if muted { "1" } else { "0" },
    ]);
}

pub fn supports_volume_default() -> bool {
    true
}

pub fn get_volume_default() -> Option<f32> {
    // e.g. "Volume: front-left: 45875 /  70% / ..."; take the first percentage.
    let out = pactl(&["get-source-volume", "@DEFAULT_SOURCE@"])?;
    let pct = out.split('%').next()?.rsplit(|c: char| c == ' ' || c == '/').next()?;
    pct.trim().parse::<f32>().ok().map(|p| (p / 100.0).clamp(0.0, 1.0))
}

pub fn set_volume_default(value: f32) {
    let pct = (value.clamp(0.0, 1.0) * 100.0).round() as i32;
    let _ = pactl(&[
        "set-source-volume",
        "@DEFAULT_SOURCE@",
        &format!("{pct}%"),
    ]);
}

pub fn devices() -> Vec<Device> {
    let Some(list) = pactl(&["list", "short", "sources"]) else {
        return vec![];
    };
    let current = default_id();
    list.lines()
        .filter_map(|line| {
            // columns: index \t name \t driver \t sample-spec \t state
            let mut cols = line.split('\t');
            let _index = cols.next()?;
            let name = cols.next()?.to_string();
            // Skip monitor sources (loopback of outputs), not real mics.
            if name.contains(".monitor") {
                return None;
            }
            Some(Device {
                is_default: name == current,
                id: name.clone(),
                name,
            })
        })
        .collect()
}

pub fn set_default(id: &str) {
    let _ = pactl(&["set-default-source", id]);
}

// --- output (sinks) ---

pub fn output_devices() -> Vec<Device> {
    let Some(list) = pactl(&["list", "short", "sinks"]) else {
        return vec![];
    };
    let current = pactl(&["get-default-sink"])
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    list.lines()
        .filter_map(|line| {
            // columns: index \t name \t driver \t sample-spec \t state
            let mut cols = line.split('\t');
            let _index = cols.next()?;
            let name = cols.next()?.to_string();
            Some(Device {
                is_default: name == current,
                id: name.clone(),
                name,
            })
        })
        .collect()
}

pub fn set_default_output(id: &str) {
    let _ = pactl(&["set-default-sink", id]);
}

pub fn get_output_volume() -> Option<f32> {
    let out = pactl(&["get-sink-volume", "@DEFAULT_SINK@"])?;
    let pct = out.split('%').next()?.rsplit(|c: char| c == ' ' || c == '/').next()?;
    pct.trim().parse::<f32>().ok().map(|p| (p / 100.0).clamp(0.0, 1.0))
}

pub fn set_output_volume(value: f32) {
    let pct = (value.clamp(0.0, 1.0) * 100.0).round() as i32;
    let _ = pactl(&["set-sink-volume", "@DEFAULT_SINK@", &format!("{pct}%")]);
}
