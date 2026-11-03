//! Mirror the mic state on an SDINNOVATION "SIDE-KEYBOARD" macro pad: the
//! mute key glows red while the mic is live and goes dark when muted.
//! Protocol taken from the vendor's WebHID configurator (sdcx-tech.com).

use hidapi::HidApi;

const VID: u16 = 0x0816;
const PID: u16 = 0x246f;
const VENDOR_USAGE_PAGE: u16 = 0xff00;
/// Bottom-left key, the one bound to the mute shortcut.
const MUTE_KEY: u16 = 3;

/// Push the LED state in the background; silently does nothing without the pad.
pub fn set_led(muted: bool) {
    std::thread::spawn(move || {
        let _ = send(muted);
    });
}

fn send(muted: bool) -> hidapi::HidResult<()> {
    let api = HidApi::new()?;
    let Some(info) = api.device_list().find(|d| {
        d.vendor_id() == VID && d.product_id() == PID && d.usage_page() == VENDOR_USAGE_PAGE
    }) else {
        return Ok(());
    };
    let dev = info.open_device(&api)?;
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
        super::send(true).unwrap();
        std::thread::sleep(std::time::Duration::from_secs(3));
        super::send(false).unwrap();
    }
}
