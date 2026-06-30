//! Live microphone level monitoring for the Mic Check window.
//!
//! Captures the default input device with cpal and emits a normalized 0..1
//! level as a `mic:level` event. The cpal stream is not Send, so it lives
//! entirely on a dedicated thread that we stop by signalling a channel.

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::mpsc::{Receiver, SyncSender};
use std::sync::Mutex;
use tauri::{AppHandle, Emitter};

pub struct MicCheck {
    stop_tx: Mutex<Option<SyncSender<()>>>,
}

impl MicCheck {
    pub fn new() -> Self {
        MicCheck {
            stop_tx: Mutex::new(None),
        }
    }

    pub fn start(&self, app: AppHandle) {
        let mut guard = self.stop_tx.lock().unwrap();
        if guard.is_some() {
            return; // already monitoring
        }
        let (tx, rx) = std::sync::mpsc::sync_channel::<()>(1);
        *guard = Some(tx);
        std::thread::spawn(move || {
            if let Err(e) = run_stream(&app, rx) {
                eprintln!("MicFlip: mic check error: {e}");
                let _ = app.emit("mic:level-error", e);
            }
        });
    }

    pub fn stop(&self) {
        if let Some(tx) = self.stop_tx.lock().unwrap().take() {
            let _ = tx.send(());
        }
    }
}

fn run_stream(app: &AppHandle, rx: Receiver<()>) -> Result<(), String> {
    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .ok_or("no default input device")?;
    let supported = device
        .default_input_config()
        .map_err(|e| e.to_string())?;
    let sample_format = supported.sample_format();
    let config: cpal::StreamConfig = supported.into();
    let err_fn = |e: cpal::StreamError| eprintln!("MicFlip: mic stream error: {e}");

    let stream = match sample_format {
        cpal::SampleFormat::F32 => {
            let a = app.clone();
            device.build_input_stream(
                &config,
                move |data: &[f32], _: &cpal::InputCallbackInfo| {
                    let _ = a.emit("mic:level", rms(data.iter().copied()));
                },
                err_fn,
                None,
            )
        }
        cpal::SampleFormat::I16 => {
            let a = app.clone();
            device.build_input_stream(
                &config,
                move |data: &[i16], _: &cpal::InputCallbackInfo| {
                    let _ = a.emit("mic:level", rms(data.iter().map(|&s| s as f32 / 32768.0)));
                },
                err_fn,
                None,
            )
        }
        cpal::SampleFormat::U16 => {
            let a = app.clone();
            device.build_input_stream(
                &config,
                move |data: &[u16], _: &cpal::InputCallbackInfo| {
                    let _ = a.emit("mic:level", rms(data.iter().map(|&s| s as f32 / 32768.0 - 1.0)));
                },
                err_fn,
                None,
            )
        }
        _ => return Err("unsupported sample format".into()),
    }
    .map_err(|e| e.to_string())?;

    stream.play().map_err(|e| e.to_string())?;
    let _ = rx.recv(); // keep the stream alive until stop() signals
    Ok(())
}

/// RMS of the samples, mapped from roughly -60..0 dBFS onto 0..1.
fn rms<I: Iterator<Item = f32>>(samples: I) -> f32 {
    let mut sum = 0.0f32;
    let mut n = 0u32;
    for s in samples {
        sum += s * s;
        n += 1;
    }
    if n == 0 {
        return 0.0;
    }
    let rms = (sum / n as f32).sqrt();
    let db = 20.0 * rms.max(1e-7).log10();
    ((db + 60.0) / 60.0).clamp(0.0, 1.0)
}
