//! macOS CoreAudio backend (raw FFI against the HAL).

#![allow(non_upper_case_globals, non_snake_case, dead_code)]

use core_foundation::base::TCFType;
use core_foundation::string::{CFString, CFStringRef};
use std::os::raw::c_void;
use std::ptr;

use super::Device;

type AudioObjectID = u32;
type OSStatus = i32;
type Boolean = u8;

#[repr(C)]
struct AudioObjectPropertyAddress {
    selector: u32,
    scope: u32,
    element: u32,
}

const fn fourcc(s: &[u8; 4]) -> u32 {
    ((s[0] as u32) << 24) | ((s[1] as u32) << 16) | ((s[2] as u32) << 8) | (s[3] as u32)
}

const kAudioObjectSystemObject: AudioObjectID = 1;
const kElementMain: u32 = 0;
const kScopeGlobal: u32 = fourcc(b"glob");
const kScopeInput: u32 = fourcc(b"inpt");
const kScopeOutput: u32 = fourcc(b"outp");
const kDefaultInputDevice: u32 = fourcc(b"dIn ");
const kDefaultOutputDevice: u32 = fourcc(b"dOut");
const kDevices: u32 = fourcc(b"dev#");
const kMute: u32 = fourcc(b"mute");
const kVolumeScalar: u32 = fourcc(b"volm");
const kObjectName: u32 = fourcc(b"lnam");
const kStreamConfiguration: u32 = fourcc(b"slay");

#[link(name = "CoreAudio", kind = "framework")]
extern "C" {
    fn AudioObjectGetPropertyData(
        id: AudioObjectID,
        addr: *const AudioObjectPropertyAddress,
        qual_size: u32,
        qual: *const c_void,
        size: *mut u32,
        data: *mut c_void,
    ) -> OSStatus;
    fn AudioObjectSetPropertyData(
        id: AudioObjectID,
        addr: *const AudioObjectPropertyAddress,
        qual_size: u32,
        qual: *const c_void,
        size: u32,
        data: *const c_void,
    ) -> OSStatus;
    fn AudioObjectGetPropertyDataSize(
        id: AudioObjectID,
        addr: *const AudioObjectPropertyAddress,
        qual_size: u32,
        qual: *const c_void,
        size: *mut u32,
    ) -> OSStatus;
    fn AudioObjectHasProperty(id: AudioObjectID, addr: *const AudioObjectPropertyAddress) -> Boolean;
    fn AudioObjectIsPropertySettable(
        id: AudioObjectID,
        addr: *const AudioObjectPropertyAddress,
        settable: *mut Boolean,
    ) -> OSStatus;
}

fn addr(selector: u32, scope: u32, element: u32) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress { selector, scope, element }
}

const ELEMENTS: [u32; 3] = [kElementMain, 1, 2];

fn default_device_for(selector: u32) -> AudioObjectID {
    let a = addr(selector, kScopeGlobal, kElementMain);
    let mut dev: AudioObjectID = 0;
    let mut size = std::mem::size_of::<AudioObjectID>() as u32;
    unsafe {
        AudioObjectGetPropertyData(
            kAudioObjectSystemObject,
            &a,
            0,
            ptr::null(),
            &mut size,
            &mut dev as *mut _ as *mut c_void,
        );
    }
    dev
}

fn default_device() -> AudioObjectID {
    default_device_for(kDefaultInputDevice)
}

fn string_property(dev: AudioObjectID, selector: u32) -> Option<String> {
    let a = addr(selector, kScopeGlobal, kElementMain);
    if unsafe { AudioObjectHasProperty(dev, &a) } == 0 {
        return None;
    }
    let mut cf: CFStringRef = ptr::null_mut();
    let mut size = std::mem::size_of::<CFStringRef>() as u32;
    let st = unsafe {
        AudioObjectGetPropertyData(dev, &a, 0, ptr::null(), &mut size, &mut cf as *mut _ as *mut c_void)
    };
    if st != 0 || cf.is_null() {
        return None;
    }
    // CoreAudio returns a +1 retained CFString for these properties.
    let s = unsafe { CFString::wrap_under_create_rule(cf) };
    Some(s.to_string())
}

fn device_name(dev: AudioObjectID) -> Option<String> {
    string_property(dev, kObjectName)
}

fn has_stream(dev: AudioObjectID, scope: u32) -> bool {
    let a = addr(kStreamConfiguration, scope, kElementMain);
    let mut size = 0u32;
    if unsafe { AudioObjectGetPropertyDataSize(dev, &a, 0, ptr::null(), &mut size) } != 0 || size < 4 {
        return false;
    }
    let mut buf = vec![0u8; size as usize];
    if unsafe {
        AudioObjectGetPropertyData(dev, &a, 0, ptr::null(), &mut size, buf.as_mut_ptr() as *mut c_void)
    } != 0
    {
        return false;
    }
    // First field of AudioBufferList is mNumberBuffers (UInt32).
    let num_buffers = u32::from_ne_bytes([buf[0], buf[1], buf[2], buf[3]]);
    num_buffers > 0
}

fn has_input(dev: AudioObjectID) -> bool {
    has_stream(dev, kScopeInput)
}

fn has_output(dev: AudioObjectID) -> bool {
    has_stream(dev, kScopeOutput)
}

/// Enumerate every audio device the system knows about (their raw ids).
fn all_device_ids() -> Vec<AudioObjectID> {
    let a = addr(kDevices, kScopeGlobal, kElementMain);
    let mut size = 0u32;
    if unsafe { AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, ptr::null(), &mut size) }
        != 0
    {
        return vec![];
    }
    let count = size as usize / std::mem::size_of::<AudioObjectID>();
    let mut ids = vec![0u32; count];
    if unsafe {
        AudioObjectGetPropertyData(
            kAudioObjectSystemObject,
            &a,
            0,
            ptr::null(),
            &mut size,
            ids.as_mut_ptr() as *mut c_void,
        )
    } != 0
    {
        return vec![];
    }
    ids
}

fn set_default_for(selector: u32, id: &str) {
    let Ok(dev) = id.parse::<AudioObjectID>() else {
        return;
    };
    let a = addr(selector, kScopeGlobal, kElementMain);
    let mut v = dev;
    unsafe {
        AudioObjectSetPropertyData(
            kAudioObjectSystemObject,
            &a,
            0,
            ptr::null(),
            std::mem::size_of::<AudioObjectID>() as u32,
            &mut v as *mut _ as *const c_void,
        );
    }
}

// --- mute flag ---

fn mute_value(dev: AudioObjectID, element: u32) -> Option<bool> {
    let a = addr(kMute, kScopeInput, element);
    if unsafe { AudioObjectHasProperty(dev, &a) } == 0 {
        return None;
    }
    let mut val: u32 = 0;
    let mut size = 4u32;
    let st = unsafe {
        AudioObjectGetPropertyData(dev, &a, 0, ptr::null(), &mut size, &mut val as *mut _ as *mut c_void)
    };
    if st == 0 {
        Some(val == 1)
    } else {
        None
    }
}

fn set_mute_value(dev: AudioObjectID, muted: bool) -> bool {
    let mut did_set = false;
    let mut val: u32 = if muted { 1 } else { 0 };
    for &el in &ELEMENTS {
        let a = addr(kMute, kScopeInput, el);
        if unsafe { AudioObjectHasProperty(dev, &a) } == 0 {
            continue;
        }
        let mut settable: Boolean = 0;
        if unsafe { AudioObjectIsPropertySettable(dev, &a, &mut settable) } != 0 || settable == 0 {
            continue;
        }
        if unsafe {
            AudioObjectSetPropertyData(dev, &a, 0, ptr::null(), 4, &mut val as *mut _ as *const c_void)
        } == 0
        {
            did_set = true;
        }
    }
    did_set
}

// --- volume ---

fn volume_value(dev: AudioObjectID, scope: u32) -> Option<f32> {
    for &el in &ELEMENTS {
        let a = addr(kVolumeScalar, scope, el);
        if unsafe { AudioObjectHasProperty(dev, &a) } == 0 {
            continue;
        }
        let mut v: f32 = 0.0;
        let mut size = 4u32;
        if unsafe {
            AudioObjectGetPropertyData(dev, &a, 0, ptr::null(), &mut size, &mut v as *mut _ as *mut c_void)
        } == 0
        {
            return Some(v);
        }
    }
    None
}

fn set_volume_value(dev: AudioObjectID, scope: u32, value: f32) -> bool {
    let mut did_set = false;
    let mut v: f32 = value.clamp(0.0, 1.0);
    for &el in &ELEMENTS {
        let a = addr(kVolumeScalar, scope, el);
        if unsafe { AudioObjectHasProperty(dev, &a) } == 0 {
            continue;
        }
        let mut settable: Boolean = 0;
        if unsafe { AudioObjectIsPropertySettable(dev, &a, &mut settable) } != 0 || settable == 0 {
            continue;
        }
        if unsafe {
            AudioObjectSetPropertyData(dev, &a, 0, ptr::null(), 4, &mut v as *mut _ as *const c_void)
        } == 0
        {
            did_set = true;
        }
    }
    did_set
}

// === Backend interface used by audio::Mic ===

pub fn default_id() -> String {
    default_device().to_string()
}

pub fn default_name() -> Option<String> {
    device_name(default_device())
}

pub fn get_mute_default() -> Option<bool> {
    let dev = default_device();
    let mut saw = false;
    let mut muted = false;
    for &el in &ELEMENTS {
        if let Some(m) = mute_value(dev, el) {
            saw = true;
            muted |= m;
        }
    }
    if saw {
        Some(muted)
    } else {
        None
    }
}

pub fn set_mute_default(muted: bool) {
    set_mute_value(default_device(), muted);
}

pub fn supports_volume_default() -> bool {
    volume_value(default_device(), kScopeInput).is_some()
}

pub fn get_volume_default() -> Option<f32> {
    volume_value(default_device(), kScopeInput)
}

pub fn set_volume_default(value: f32) {
    set_volume_value(default_device(), kScopeInput, value);
}

pub fn devices() -> Vec<Device> {
    let current = default_device();
    all_device_ids()
        .into_iter()
        .filter(|&id| has_input(id))
        .map(|id| Device {
            id: id.to_string(),
            name: device_name(id).unwrap_or_else(|| "Unknown device".to_string()),
            is_default: id == current,
        })
        .collect()
}

pub fn set_default(id: &str) {
    set_default_for(kDefaultInputDevice, id);
}

// --- output (playback) devices ---

pub fn output_devices() -> Vec<Device> {
    let current = default_device_for(kDefaultOutputDevice);
    all_device_ids()
        .into_iter()
        .filter(|&id| has_output(id))
        .map(|id| Device {
            id: id.to_string(),
            name: device_name(id).unwrap_or_else(|| "Unknown device".to_string()),
            is_default: id == current,
        })
        .collect()
}

pub fn set_default_output(id: &str) {
    set_default_for(kDefaultOutputDevice, id);
}

pub fn get_output_volume() -> Option<f32> {
    volume_value(default_device_for(kDefaultOutputDevice), kScopeOutput)
}

pub fn set_output_volume(value: f32) {
    set_volume_value(default_device_for(kDefaultOutputDevice), kScopeOutput, value);
}
