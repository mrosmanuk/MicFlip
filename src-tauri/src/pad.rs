//! Mirror the mic state on an SDINNOVATION "SIDE-KEYBOARD" macro pad: the
//! mute key glows red while the mic is live and goes dark when muted.
//! Protocol taken from the vendor's WebHID configurator (sdcx-tech.com).

use hidapi::HidApi;
use std::sync::{mpsc, Mutex, OnceLock};

const VID: u16 = 0x0816;
const PID: u16 = 0x246f;
const VENDOR_USAGE_PAGE: u16 = 0xff00;
/// Bottom-left key, the one bound to the mute shortcut.
const MUTE_KEY: u16 = 3;

/// Push the LED state in the background; silently does nothing without the pad.
/// One long-lived worker owns the HidApi: hidapi's macOS backend keeps a global
/// HID manager bound to its creating thread's run loop, so per-call threads crashed.
pub fn set_led(muted: bool) {
    static TX: OnceLock<Mutex<mpsc::Sender<bool>>> = OnceLock::new();
    let tx = TX.get_or_init(|| {
        let (tx, rx) = mpsc::channel::<bool>();
        std::thread::spawn(move || {
            let mut api = None;
            while let Ok(mut muted) = rx.recv() {
                // Only the latest state matters.
                while let Ok(m) = rx.try_recv() {
                    muted = m;
                }
                if api.is_none() {
                    api = HidApi::new().ok();
                }
                if let Some(api) = api.as_mut() {
                    let _ = send(api, muted);
                }
            }
        });
        Mutex::new(tx)
    });
    let _ = tx.lock().map(|tx| tx.send(muted));
}

fn send(api: &mut HidApi, muted: bool) -> hidapi::HidResult<()> {
    api.refresh_devices()?; // pick up a replugged pad
    let Some(info) = api.device_list().find(|d| {
        d.vendor_id() == VID && d.product_id() == PID && d.usage_page() == VENDOR_USAGE_PAGE
    }) else {
        return Ok(());
    };
    let dev = info.open_device(api)?;
    // Light mode 5 ("custom", per-key colors) at full brightness, so the
    // per-key color below is what shows.
    write(&dev, &[6, 11, 11, 0, 0, 1, 0, 5, 4, 0, 0, 0, 0, 0, 0, 0])?;
    let i = MUTE_KEY * 3;
    let red = if muted { 0 } else { 255 };
    write(&dev, &[6, 20, 3, i as u8, (i >> 8) as u8, 0, 0, 0, red, 0, 0])
}

/// One 64-byte output report (report id 0), zero padded.
fn write(dev: &hidapi::HidDevice, payload: &[u8]) -> hidapi::HidResult<()> {
    let mut buf = [0u8; 65];
    buf[1..=payload.len()].copy_from_slice(payload);
    dev.write(&buf).map(|_| ())
}

#[cfg(test)]
mod tests {
    /// `cargo test -- --ignored`: the mute key goes dark for 3s, then red.
    #[test]
    #[ignore = "needs the pad plugged in"]
    fn blink() {
        let mut api = hidapi::HidApi::new().unwrap();
        super::send(&mut api, true).unwrap();
        std::thread::sleep(std::time::Duration::from_secs(3));
        super::send(&mut api, false).unwrap();
    }
}
