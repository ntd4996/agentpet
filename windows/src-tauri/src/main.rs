// Prevents an extra console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // Fix a blank/white WebView on some Linux setups: newer WebKitGTK (2.42+)
    // uses a DMABUF renderer that fails to composite on certain GPU/compositor
    // combos (notably KDE + Wayland), leaving the window blank. Disable it unless
    // the user set their own value. Set before the webview initializes. (#52)
    #[cfg(target_os = "linux")]
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }

    let args: Vec<String> = std::env::args().collect();
    // Invoked by an agent's hook: `agentpet hook --agent <kind>` (reads stdin).
    if args.get(1).map(String::as_str) == Some("hook") {
        agentpet_lib::cli::run_hook(&args[2..]);
        return;
    }
    // `agentpet run [--session id] [--project path] [--agent kind] -- <cmd...>`:
    // wraps any CLI agent , working while it runs, done when it exits.
    if args.get(1).map(String::as_str) == Some("run") {
        agentpet_lib::cli::run_wrapper(&args[2..]);
    }
    agentpet_lib::run();
}
