pub mod cli;
pub mod hooks;
pub mod server;
pub mod statemap;

use std::sync::Mutex;
use std::time::Duration;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{Manager, PhysicalPosition, WebviewUrl, WebviewWindowBuilder};

/// Tray menu items kept around so the language switcher can re-label them live.
struct TrayItems {
    settings: MenuItem<tauri::Wry>,
    quit: MenuItem<tauri::Wry>,
}

/// The pet's opaque region in physical pixels, relative to the window's top-left.
/// The frontend reports this (canvas + visible bubble) so the background thread
/// can make the transparent rest of the window click-through.
#[derive(Default)]
#[cfg_attr(not(windows), allow(dead_code))]
struct HitRect {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
}

fn pos_file() -> Option<std::path::PathBuf> {
    dirs::config_dir().map(|d| d.join("AgentPet").join("pos"))
}

fn read_pos() -> Option<(i32, i32)> {
    let s = std::fs::read_to_string(pos_file()?).ok()?;
    let (a, b) = s.trim().split_once(',')?;
    Some((a.trim().parse().ok()?, b.trim().parse().ok()?))
}

fn write_pos(x: i32, y: i32) {
    if let Some(p) = pos_file() {
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let _ = std::fs::write(p, format!("{x},{y}"));
    }
}

/// Current cursor position in physical screen pixels (Windows only).
#[cfg(windows)]
fn cursor_pos() -> Option<(i32, i32)> {
    use windows::Win32::Foundation::POINT;
    use windows::Win32::UI::WindowsAndMessaging::GetCursorPos;
    let mut p = POINT::default();
    unsafe { GetCursorPos(&mut p).ok()? };
    Some((p.x, p.y))
}

/// Report the pet's opaque rectangle (physical px, window-relative) so empty
/// transparent areas of the overlay let clicks pass through to apps below.
#[tauri::command]
fn set_hit_rect(app: tauri::AppHandle, x: f64, y: f64, w: f64, h: f64) {
    if let Some(state) = app.try_state::<Mutex<HitRect>>() {
        if let Ok(mut r) = state.lock() {
            *r = HitRect { x, y, w, h };
        }
    }
}

fn lang_file() -> Option<std::path::PathBuf> {
    dirs::config_dir().map(|d| d.join("AgentPet").join("lang"))
}

fn read_lang() -> String {
    lang_file()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "en".into())
}

fn write_lang(code: &str) {
    if let Some(p) = lang_file() {
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let _ = std::fs::write(p, code);
    }
}

/// Localised tray labels (the only app text on the Rust side).
fn tray_labels(code: &str) -> (&'static str, &'static str) {
    match code {
        "vi" => ("Cài đặt", "Thoát AgentPet"),
        "zh" => ("设置", "退出 AgentPet"),
        _ => ("Settings", "Quit AgentPet"),
    }
}

#[tauri::command]
fn list_agents() -> Vec<hooks::AgentInfo> {
    hooks::catalog()
}

#[tauri::command]
fn is_installed(kind: String) -> bool {
    hooks::is_installed(&kind)
}

#[tauri::command]
fn toggle_install(kind: String) -> Result<bool, String> {
    hooks::toggle(&kind)
}

#[tauri::command]
fn open_settings(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("settings") {
        let _ = w.set_focus();
        return;
    }
    let _ = WebviewWindowBuilder::new(&app, "settings", WebviewUrl::App("settings.html".into()))
        .title("AgentPet")
        .inner_size(640.0, 620.0)
        .resizable(false)
        .build();
}

/// Open an external link in the default browser (About tab buttons).
#[tauri::command]
fn open_url(url: String) {
    if !(url.starts_with("https://") || url.starts_with("http://")) {
        return;
    }
    #[cfg(windows)]
    {
        let _ = std::process::Command::new("cmd").args(["/c", "start", "", &url]).spawn();
    }
    #[cfg(target_os = "macos")]
    {
        let _ = std::process::Command::new("open").arg(&url).spawn();
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        let _ = std::process::Command::new("xdg-open").arg(&url).spawn();
    }
}

/// Persist the chosen language (for the tray on next launch) and re-label the
/// tray menu items now. Called by the Settings language switcher.
#[tauri::command]
fn set_lang(app: tauri::AppHandle, code: String) {
    write_lang(&code);
    let (s, q) = tray_labels(&code);
    if let Some(items) = app.try_state::<Mutex<TrayItems>>() {
        if let Ok(it) = items.lock() {
            let _ = it.settings.set_text(s);
            let _ = it.quit.set_text(q);
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // Must be the first plugin: a second launch (double-clicking the
        // shortcut while the app runs) exits immediately and the running
        // instance opens Settings instead , no duplicate pets.
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            open_settings(app.clone());
        }))
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .invoke_handler(tauri::generate_handler![
            list_agents,
            is_installed,
            toggle_install,
            open_settings,
            open_url,
            set_lang,
            set_hit_rect
        ])
        .setup(|app| {
            server::start(app.handle().clone());
            app.manage(Mutex::new(HitRect::default()));

            // Restore where the user last dragged the pet. First run (no saved
            // position) parks it near the bottom-right of the primary screen;
            // the LogicalPosition keeps it on-screen on smaller/HiDPI displays.
            if let Some(win) = app.get_webview_window("pet") {
                // Only restore a saved position that still lands on a monitor
                // (displays may have been unplugged/rearranged since last run).
                let on_screen = |x: i32, y: i32| {
                    win.available_monitors().map_or(false, |mons| {
                        mons.iter().any(|m| {
                            let p = m.position();
                            let s = m.size();
                            x >= p.x
                                && x < p.x + s.width as i32
                                && y >= p.y
                                && y < p.y + s.height as i32
                        })
                    })
                };
                if let Some((px, py)) = read_pos().filter(|&(x, y)| on_screen(x, y)) {
                    let _ = win.set_position(PhysicalPosition::new(px, py));
                } else if let Ok(Some(mon)) = win.primary_monitor() {
                    let s = mon.scale_factor();
                    let sz = mon.size();
                    let x = (sz.width as f64 / s) - 260.0 - 40.0;
                    let y = (sz.height as f64 / s) - 320.0 - 70.0;
                    let _ = win.set_position(tauri::LogicalPosition::new(x.max(0.0), y.max(0.0)));
                }
            }

            // Background loop: (1) make transparent areas of the overlay
            // click-through by toggling cursor-event capture based on whether the
            // cursor is over the pet's opaque rect, and (2) persist the pet's
            // position so it survives a restart. Click-through is Windows-only;
            // position saving runs everywhere.
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                #[cfg(windows)]
                let mut last_ignore: Option<bool> = None;
                let mut last_saved = read_pos();
                let mut tick: u32 = 0;
                loop {
                    std::thread::sleep(Duration::from_millis(30));
                    let Some(win) = handle.get_webview_window("pet") else {
                        continue;
                    };

                    #[cfg(windows)]
                    if let (Some((cx, cy)), Ok(wp)) = (cursor_pos(), win.outer_position()) {
                        let inside = handle
                            .try_state::<Mutex<HitRect>>()
                            .and_then(|s| s.lock().ok().map(|r| (r.x, r.y, r.w, r.h)))
                            .map(|(x, y, w, h)| {
                                let rx = (cx - wp.x) as f64;
                                let ry = (cy - wp.y) as f64;
                                w > 0.0 && rx >= x && rx <= x + w && ry >= y && ry <= y + h
                            })
                            .unwrap_or(false);
                        // ignore_cursor_events = true  -> clicks pass through.
                        let ignore = !inside;
                        if Some(ignore) != last_ignore {
                            let _ = win.set_ignore_cursor_events(ignore);
                            last_ignore = Some(ignore);
                        }
                    }

                    tick = tick.wrapping_add(1);
                    if tick % 33 == 0 {
                        if let Ok(p) = win.outer_position() {
                            if last_saved != Some((p.x, p.y)) {
                                write_pos(p.x, p.y);
                                last_saved = Some((p.x, p.y));
                            }
                        }
                    }
                }
            });

            // Tray menu , the pet window is frameless, so this is how you reach
            // Settings or quit the app. Labels start in the saved language; the
            // Settings switcher re-labels them live via the `set_lang` command.
            let (s_lbl, q_lbl) = tray_labels(&read_lang());
            let settings_i = MenuItem::with_id(app, "settings", s_lbl, true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", q_lbl, true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&settings_i, &quit_i])?;
            app.manage(Mutex::new(TrayItems {
                settings: settings_i.clone(),
                quit: quit_i.clone(),
            }));
            let mut tray = TrayIconBuilder::new()
                .tooltip("AgentPet")
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "settings" => open_settings(app.clone()),
                    "quit" => app.exit(0),
                    _ => {}
                });
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            let _tray = tray.build(app)?;

            // First run: open Settings so the user knows to pick a pet and
            // connect an agent (otherwise the pet just sits there silently).
            let marker = dirs::config_dir().map(|d| d.join("AgentPet").join(".onboarded"));
            if let Some(m) = marker {
                if !m.exists() {
                    open_settings(app.handle().clone());
                    if let Some(parent) = m.parent() {
                        let _ = std::fs::create_dir_all(parent);
                    }
                    let _ = std::fs::write(&m, "1");
                }
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running AgentPet");
}
