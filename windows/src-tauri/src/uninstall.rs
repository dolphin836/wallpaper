// Uninstall flow invoked from the tray menu. On Windows we shell out
// to msiexec / the registered uninstall string in the registry so
// the user lands on the standard Windows uninstaller UI. The current
// process exits before the uninstaller runs (Windows can't replace a
// running binary).
//
// On other platforms this is a no-op + log line so cargo dev on
// macOS still compiles. The tray menu hides the option on non-
// Windows builds.

use tauri::{AppHandle, Runtime};

#[cfg(target_os = "windows")]
const PRODUCT_NAME: &str = "Wallpaper Exchange";

pub fn run_uninstaller<R: Runtime>(app: &AppHandle<R>) {
    #[cfg(target_os = "windows")]
    {
        if let Err(e) = launch_windows_uninstaller() {
            log::error!("uninstall: launch failed: {e}");
            return;
        }
        // Quit the running app so Windows can replace / remove its files.
        app.exit(0);
    }
    #[cfg(not(target_os = "windows"))]
    {
        log::info!("uninstall: no-op on non-Windows");
        let _ = app;
    }
}

#[cfg(target_os = "windows")]
fn launch_windows_uninstaller() -> Result<(), String> {
    use std::process::Command;
    use windows::core::HSTRING;
    use windows::Win32::System::Registry::{
        RegCloseKey, RegOpenKeyExW, RegQueryValueExW, HKEY, HKEY_LOCAL_MACHINE, KEY_READ,
        REG_VALUE_TYPE,
    };

    // The Tauri NSIS bundle registers its uninstall string under
    //   HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{<bundle-name>}
    // where <bundle-name> is the productName from tauri.conf.json.
    // We probe both that path and the WOW6432Node variant for 32-bit
    // shells; the first hit wins.
    let candidates = [
        format!(
            r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{}",
            PRODUCT_NAME
        ),
        format!(
            r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{}",
            PRODUCT_NAME
        ),
    ];
    for sub in &candidates {
        if let Some(cmd) = read_uninstall_string(sub) {
            // Some uninstall strings come quoted with arguments
            // (`"C:\...\uninst.exe" /something`). Spawn through cmd
            // /C so quoting is handled the way Windows expects.
            Command::new("cmd")
                .args(["/C", "start", "", &cmd])
                .spawn()
                .map_err(|e| format!("spawn uninstaller: {e}"))?;
            return Ok(());
        }
    }
    Err(format!(
        "uninstall entry for {PRODUCT_NAME:?} not found in HKLM Uninstall keys"
    ))
}

#[cfg(target_os = "windows")]
fn read_uninstall_string(sub_path: &str) -> Option<String> {
    use windows::core::HSTRING;
    use windows::Win32::System::Registry::{
        RegCloseKey, RegOpenKeyExW, RegQueryValueExW, HKEY, HKEY_LOCAL_MACHINE, KEY_READ,
        REG_VALUE_TYPE,
    };

    let path = HSTRING::from(sub_path);
    let mut hkey = HKEY::default();
    let opened = unsafe { RegOpenKeyExW(HKEY_LOCAL_MACHINE, &path, 0, KEY_READ, &mut hkey) };
    if opened.is_err() {
        return None;
    }

    let value_name = HSTRING::from("UninstallString");
    let mut data_type = REG_VALUE_TYPE::default();
    let mut bytes_needed: u32 = 0;
    unsafe {
        let _ = RegQueryValueExW(
            hkey,
            &value_name,
            None,
            Some(&mut data_type),
            None,
            Some(&mut bytes_needed),
        );
    }
    if bytes_needed == 0 {
        unsafe { let _ = RegCloseKey(hkey); }
        return None;
    }
    let mut buf = vec![0u8; bytes_needed as usize];
    let mut got = bytes_needed;
    let res = unsafe {
        RegQueryValueExW(
            hkey,
            &value_name,
            None,
            Some(&mut data_type),
            Some(buf.as_mut_ptr()),
            Some(&mut got),
        )
    };
    unsafe {
        let _ = RegCloseKey(hkey);
    }
    if res.is_err() {
        return None;
    }
    let wide: Vec<u16> = buf
        .chunks_exact(2)
        .map(|c| u16::from_le_bytes([c[0], c[1]]))
        .take_while(|&u| u != 0)
        .collect();
    Some(String::from_utf16_lossy(&wide))
}
