pub mod cli;
pub mod hooks;
pub mod server;
pub mod statemap;
pub mod transcript;

use std::sync::Mutex;
use std::time::Duration;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{Emitter, Manager, PhysicalPosition, WebviewUrl, WebviewWindowBuilder};

/// Tray menu items kept around so the language switcher can re-label them live.
struct TrayItems {
    show_pet: tauri::menu::CheckMenuItem<tauri::Wry>,
    settings: MenuItem<tauri::Wry>,
    quit: MenuItem<tauri::Wry>,
    tray: tauri::tray::TrayIcon<tauri::Wry>,
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

/// Append a line to %APPDATA%/AgentPet/debug.log , lightweight field
/// diagnostics for the Windows build (no console there).
fn dlog(msg: &str) {
    if let Some(p) = dirs::config_dir().map(|d| d.join("AgentPet").join("debug.log")) {
        if let Some(dir) = p.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) {
            use std::io::Write;
            let ts = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let _ = writeln!(f, "[{ts}] {msg}");
        }
    }
}

#[tauri::command]
fn log_debug(msg: String) {
    dlog(&msg);
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
fn tray_labels(code: &str) -> (&'static str, &'static str, &'static str) {
    match code {
        "vi" => ("Hiện pet", "Cài đặt", "Thoát AgentPet"),
        "zh" => ("显示宠物", "设置", "退出 AgentPet"),
        _ => ("Show pet", "Settings", "Quit AgentPet"),
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

/// Window creation MUST NOT run inside a sync command / menu callback on
/// Windows (the webview build deadlocks against the blocked event loop), so
/// every caller goes through this thread-spawning wrapper.
fn open_settings_impl(app: tauri::AppHandle) {
    std::thread::spawn(move || {
        dlog("open_settings: worker thread");
        if let Some(w) = app.get_webview_window("settings") {
            dlog("open_settings: existing window, showing");
            let _ = w.show();
            let _ = w.unminimize();
            let _ = w.set_focus();
            return;
        }
        match WebviewWindowBuilder::new(&app, "settings", WebviewUrl::App("settings.html".into()))
            .title("AgentPet")
            .inner_size(640.0, 620.0)
            .resizable(false)
            .build()
        {
            Ok(_) => dlog("open_settings: window created"),
            Err(e) => dlog(&format!("open_settings: BUILD FAILED: {e}")),
        }
    });
}

#[tauri::command]
async fn open_settings(app: tauri::AppHandle) {
    dlog("open_settings called");
    open_settings_impl(app);
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

/// Bring the terminal running a session to the front when its bubble row is
/// clicked. Warp exports a `warp://session/<uuid>` deep link that focuses the
/// exact pane , the one reliable cross-platform "focus exact tab". Other
/// terminals have no dependable tab-focus API on Windows/Linux, so we only
/// best-effort activate the app on macOS (where the Tauri build is dev-only).
/// A safe `warp://session/<uuid>` deep link: scheme + only URL-safe characters,
/// so it can never carry shell metacharacters into `cmd /c start`.
fn is_safe_warp_url(url: &str) -> bool {
    let Some(rest) = url.strip_prefix("warp://") else { return false };
    !rest.is_empty()
        && rest
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '/' | '-'))
}

#[tauri::command]
fn focus_terminal(program: String, focus_url: String) {
    if is_safe_warp_url(&focus_url) {
        #[cfg(windows)]
        { let _ = std::process::Command::new("cmd").args(["/c", "start", "", &focus_url]).spawn(); }
        #[cfg(target_os = "macos")]
        { let _ = std::process::Command::new("open").arg(&focus_url).spawn(); }
        #[cfg(all(unix, not(target_os = "macos")))]
        { let _ = std::process::Command::new("xdg-open").arg(&focus_url).spawn(); }
        return;
    }
    #[cfg(target_os = "macos")]
    {
        let app = match program.as_str() {
            "Apple_Terminal" => Some("Terminal"),
            "iTerm.app" => Some("iTerm"),
            _ => None,
        };
        if let Some(a) = app {
            let _ = std::process::Command::new("open").args(["-a", a]).spawn();
        }
    }
    let _ = program;
}

/// Deliver the user's Allow/Deny decision for a gated tool call back to the
/// parked hook request (see server::handle_approval).
#[tauri::command]
fn resolve_approval(id: String, decision: String) {
    crate::server::resolve_approval(&id, &decision);
}

/// Split-pet: ensure exactly one extra pet window `pet-<projectId>` exists per
/// configured project, cloning the main pet's chrome. Each loads `index.html`
/// with a `?project=<id>` query so its script shows only that project. Closing
/// happens for any `pet-*` window no longer in the list (merge back). With split
/// off, the frontend calls this with an empty list, so all extras close.
#[tauri::command]
fn sync_project_windows(app: tauri::AppHandle, projects: Vec<String>) {
    use std::collections::HashSet;
    let want: HashSet<String> = projects.iter().map(|id| format!("pet-{id}")).collect();
    for (label, win) in app.webview_windows() {
        if label.starts_with("pet-") && !want.contains(&label) {
            let _ = win.close();
        }
    }
    for (i, id) in projects.iter().enumerate() {
        let label = format!("pet-{id}");
        if app.get_webview_window(&label).is_some() {
            continue;
        }
        let url = format!("index.html?project={id}");
        let _ = WebviewWindowBuilder::new(&app, &label, WebviewUrl::App(url.into()))
            .title("AgentPet")
            .inner_size(260.0, 320.0)
            .position(1200.0 - (i as f64 + 1.0) * 60.0, 600.0)
            .transparent(true)
            .decorations(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .resizable(false)
            .shadow(false)
            .focused(false)
            .build();
    }
}

/// Persist the chosen language (for the tray on next launch) and re-label the
/// tray menu items now. Called by the Settings language switcher.
#[tauri::command]
fn set_lang(app: tauri::AppHandle, code: String) {
    write_lang(&code);
    let (p, s, q) = tray_labels(&code);
    if let Some(items) = app.try_state::<Mutex<TrayItems>>() {
        if let Ok(it) = items.lock() {
            let _ = it.show_pet.set_text(p);
            let _ = it.settings.set_text(s);
            let _ = it.quit.set_text(q);
        }
    }
}

/// Live agent counts from the pet window → tray tooltip (the macOS app shows
/// the count next to the menu bar icon; the Windows tray equivalent).
#[tauri::command]
fn set_tray_status(app: tauri::AppHandle, working: u32, waiting: u32) {
    if let Some(items) = app.try_state::<Mutex<TrayItems>>() {
        if let Ok(it) = items.lock() {
            let tip = if waiting > 0 {
                format!("AgentPet , {waiting} waiting for you")
            } else if working > 0 {
                format!("AgentPet , {working} working")
            } else {
                "AgentPet".to_string()
            };
            let _ = it.tray.set_tooltip(Some(tip));
        }
    }
}

#[tauri::command]
fn get_pet_visible(app: tauri::AppHandle) -> bool {
    app.get_webview_window("pet")
        .and_then(|w| w.is_visible().ok())
        .unwrap_or(true)
}

/// Show the popover (the macOS menu-bar popover equivalent) near the cursor.
fn show_popover(app: &tauri::AppHandle) {
    let win = match app.get_webview_window("popover") {
        Some(w) => w,
        None => {
            match WebviewWindowBuilder::new(app, "popover", WebviewUrl::App("popover.html".into()))
                .title("AgentPet")
                .inner_size(300.0, 430.0)
                .decorations(false)
                .transparent(true)
                .always_on_top(true)
                .skip_taskbar(true)
                .resizable(false)
                .focused(true)
                .visible(false)
                .build()
            {
                Ok(w) => {
                    dlog("popover: window created");
                    // Transient popover: losing focus hides it (Rust-side net,
                    // independent of the webview's own blur listener).
                    let wh = w.clone();
                    w.on_window_event(move |ev| {
                        if let tauri::WindowEvent::Focused(false) = ev {
                            let _ = wh.hide();
                        }
                    });
                    w
                }
                Err(e) => {
                    dlog(&format!("popover: BUILD FAILED: {e}"));
                    return;
                }
            }
        }
    };
    // Place near the cursor, clamped onto the monitor under it.
    if let Ok(cur) = app.cursor_position() {
        let sf = win.scale_factor().unwrap_or(1.0);
        let (w, h) = (300.0 * sf, 430.0 * sf);
        let mut x = cur.x - w / 2.0;
        let mut y = cur.y - h - 12.0; // prefer above the cursor (tray at bottom)
        if let Ok(Some(mon)) = app.monitor_from_point(cur.x, cur.y) {
            let mp = mon.position();
            let ms = mon.size();
            if y < mp.y as f64 {
                y = cur.y + 12.0; // no room above , drop below
            }
            x = x.max(mp.x as f64).min(mp.x as f64 + ms.width as f64 - w);
            y = y.max(mp.y as f64).min(mp.y as f64 + ms.height as f64 - h);
        }
        let _ = win.set_position(PhysicalPosition::new(x, y));
    }
    let _ = win.show();
    let _ = win.set_focus();
    let _ = win.emit("popover-shown", ());
}

#[tauri::command]
async fn open_popover(app: tauri::AppHandle) {
    dlog("open_popover called");
    std::thread::spawn(move || show_popover(&app));
}

/// Show/hide the pet overlay (tray toggle , the macOS "Show pet" switch).
#[tauri::command]
fn set_pet_visible(app: tauri::AppHandle, visible: bool) {
    if let Some(win) = app.get_webview_window("pet") {
        if visible {
            let _ = win.show();
        } else {
            let _ = win.hide();
        }
    }
    if let Some(p) = dirs::config_dir().map(|d| d.join("AgentPet").join("petvisible")) {
        let _ = std::fs::write(p, if visible { "1" } else { "0" });
    }
    if let Some(items) = app.try_state::<Mutex<TrayItems>>() {
        if let Ok(it) = items.lock() {
            let _ = it.show_pet.set_checked(visible);
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
            open_settings_impl(app.clone());
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
            focus_terminal,
            resolve_approval,
            sync_project_windows,
            set_lang,
            set_tray_status,
            set_pet_visible,
            get_pet_visible,
            open_popover,
            log_debug,
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
            // cursor is over the pet's opaque rect (cross-platform via tao), and
            // (2) persist the pet's position so it survives a restart.
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                let mut last_ignore: Option<bool> = None;
                let mut flip_logs: u32 = 0;
                let mut last_saved = read_pos();
                let mut tick: u32 = 0;
                loop {
                    std::thread::sleep(Duration::from_millis(30));
                    let Some(win) = handle.get_webview_window("pet") else {
                        continue;
                    };

                    // Cross-platform (tao): cursor + window in physical px.
                    // Fail-safe: while the hit rect is unknown (webview still
                    // booting) or the cursor can't be read, keep the window
                    // INTERACTIVE , a clickable pet beats an untouchable one.
                    match (handle.cursor_position(), win.outer_position()) {
                        (Ok(cur), Ok(wp)) => {
                            let rect = handle
                                .try_state::<Mutex<HitRect>>()
                                .and_then(|s| s.lock().ok().map(|r| (r.x, r.y, r.w, r.h)));
                            let inside = match rect {
                                Some((x, y, w, h)) if w > 0.0 => {
                                    let rx = cur.x - wp.x as f64;
                                    let ry = cur.y - wp.y as f64;
                                    rx >= x && rx <= x + w && ry >= y && ry <= y + h
                                }
                                _ => true, // no rect yet , stay interactive
                            };
                            // ignore_cursor_events = true -> clicks pass through.
                            let ignore = !inside;
                            if Some(ignore) != last_ignore {
                                let _ = win.set_ignore_cursor_events(ignore);
                                last_ignore = Some(ignore);
                                if flip_logs < 30 {
                                    flip_logs += 1;
                                    dlog(&format!(
                                        "hit flip: ignore={ignore} cur=({:.0},{:.0}) win=({},{}) rect={:?}",
                                        cur.x, cur.y, wp.x, wp.y, rect
                                    ));
                                }
                            }
                        }
                        (Err(e), _) => {
                            if last_ignore != Some(false) {
                                dlog(&format!("cursor_position error: {e} , forcing interactive"));
                                let _ = win.set_ignore_cursor_events(false);
                                last_ignore = Some(false);
                            }
                        }
                        _ => {}
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
            let (p_lbl, s_lbl, q_lbl) = tray_labels(&read_lang());
            let pet_visible = dirs::config_dir()
                .map(|d| d.join("AgentPet").join("petvisible"))
                .and_then(|p| std::fs::read_to_string(p).ok())
                .map(|s| s.trim() != "0")
                .unwrap_or(true);
            let show_pet_i = tauri::menu::CheckMenuItem::with_id(
                app, "show_pet", p_lbl, true, pet_visible, None::<&str>)?;
            let settings_i = MenuItem::with_id(app, "settings", s_lbl, true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", q_lbl, true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_pet_i, &settings_i, &quit_i])?;
            let mut tray = TrayIconBuilder::new()
                .tooltip("AgentPet")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_tray_icon_event(|tray, event| {
                    // Left-click on the tray icon opens Settings; the pet's
                    // right-click popover covers the quick controls.
                    if let tauri::tray::TrayIconEvent::Click {
                        button: tauri::tray::MouseButton::Left,
                        button_state: tauri::tray::MouseButtonState::Up,
                        ..
                    } = event
                    {
                        open_settings_impl(tray.app_handle().clone());
                    }
                })
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show_pet" => {
                        let now_visible = app
                            .get_webview_window("pet")
                            .and_then(|w| w.is_visible().ok())
                            .unwrap_or(true);
                        set_pet_visible(app.clone(), !now_visible);
                    }
                    "settings" => open_settings_impl(app.clone()),
                    "quit" => app.exit(0),
                    _ => {}
                });
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            let tray = tray.build(app)?;
            app.manage(Mutex::new(TrayItems {
                show_pet: show_pet_i.clone(),
                settings: settings_i.clone(),
                quit: quit_i.clone(),
                tray,
            }));
            if !pet_visible {
                if let Some(win) = app.get_webview_window("pet") {
                    let _ = win.hide();
                }
            }

            dlog("setup complete, tray + loop running");
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
