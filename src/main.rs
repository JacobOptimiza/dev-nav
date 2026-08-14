mod app;
mod config;
mod i18n;
mod input;
mod model;
mod render;
mod terminal;

use std::{env, io, path::PathBuf, process::ExitCode};

use app::App;
use config::{Config, SHORTCUT_MAX, SHORTCUT_MIN};
use i18n::{Locale, resolve_preferred_tags};
use model::ShellResult;
use terminal::Terminal;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("dev: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> io::Result<()> {
    let args: Vec<String> = env::args().skip(1).collect();
    if matches!(args.as_slice(), [argument] if argument == "--version" || argument == "-V") {
        println!("dev-nav {}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }
    let config_path = Config::default_path()?;
    // Config-only commands modify config.tsv through the canonical Rust I/O
    // path and never launch the TUI.
    if try_config_command(&args, &config_path)? {
        return Ok(());
    }
    let result_path = argument_value(&args, "--result").map(PathBuf::from);
    let config = Config::load(&config_path)?;
    let root = argument_value(&args, "--root")
        .map(PathBuf::from)
        .or_else(|| config.root().map(PathBuf::from))
        .or_else(|| env::var_os("DEV_HOME").map(PathBuf::from))
        .or_else(default_root)
        .ok_or_else(|| {
            io::Error::new(io::ErrorKind::NotFound, "no se encontró una ruta de inicio")
        })?;

    if !root.is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("la raíz no existe: {}", root.display()),
        ));
    }

    let mut terminal = Terminal::enter()?;
    let outcome = App::new(root, config, config_path)?.run(&mut terminal)?;
    drop(terminal);

    if let (Some(path), Some(outcome)) = (result_path, outcome) {
        outcome.write_to(&path)?;
    }
    Ok(())
}

fn argument_value(args: &[String], name: &str) -> Option<String> {
    args.windows(2).find(|pair| pair[0] == name).map(|pair| pair[1].clone())
}

fn default_root() -> Option<PathBuf> {
    env::var_os("USERPROFILE").map(PathBuf::from)
}

/// Handles `--set-shortcut`/`--clear-shortcut` without launching the TUI.
///
/// Returns `Ok(true)` when a config command was executed so the caller can
/// exit cleanly, and `Ok(false)` when the arguments are not a config command.
fn try_config_command(args: &[String], config_path: &std::path::Path) -> io::Result<bool> {
    match args.first().map(String::as_str) {
        Some("--set-language") => {
            let locale =
                args.get(1).and_then(|value| Locale::from_tag(value)).ok_or_else(|| {
                    io::Error::new(io::ErrorKind::InvalidInput, "language must be es-ES or en-US")
                })?;
            let mut config = Config::load(config_path)?;
            config.set_language(locale.tag());
            config.save(config_path)?;
            Ok(true)
        }
        Some("--detect-language") => {
            println!("{}", detect_system_locale().tag());
            Ok(true)
        }
        Some("--set-shortcut") => {
            let index = parse_shortcut_index(args.get(1).map(String::as_str))?;
            let mut alias: Option<String> = None;
            let mut command: Option<String> = None;
            let mut rest = args.iter().skip(2);
            while let Some(arg) = rest.next() {
                if arg == "--alias" {
                    alias = rest.next().cloned();
                } else if command.is_none() {
                    command = Some(arg.clone());
                }
            }
            let command = command.ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "uso: dev --set-shortcut <1..9> <comando> [--alias <alias>]",
                )
            })?;
            let mut config = Config::load(config_path)?;
            config.set_shortcut(index, alias, command);
            config.save(config_path)?;
            Ok(true)
        }
        Some("--clear-shortcut") => {
            let index = parse_shortcut_index(args.get(1).map(String::as_str))?;
            let mut config = Config::load(config_path)?;
            config.clear_shortcut(index);
            config.save(config_path)?;
            Ok(true)
        }
        _ => Ok(false),
    }
}

fn detect_system_locale() -> Locale {
    // The PowerShell wrapper uses this canonical Rust operation before its
    // first-run prompt, so the persisted choice is independent of region,
    // keyboard layout, timezone, or IP address.
    #[cfg(windows)]
    {
        use windows_sys::Win32::Globalization::{GetUserPreferredUILanguages, MUI_LANGUAGE_NAME};
        let mut count = 0_u32;
        let mut length = 0_u32;
        let first = unsafe {
            GetUserPreferredUILanguages(
                MUI_LANGUAGE_NAME,
                &raw mut count,
                std::ptr::null_mut(),
                &raw mut length,
            )
        };
        if first == 0 && length > 0 {
            let mut buffer = vec![0_u16; length as usize];
            let mut length = length;
            let ok = unsafe {
                GetUserPreferredUILanguages(
                    MUI_LANGUAGE_NAME,
                    &raw mut count,
                    buffer.as_mut_ptr(),
                    &raw mut length,
                )
            };
            if ok != 0 {
                let values = String::from_utf16_lossy(&buffer);
                return resolve_preferred_tags(
                    values.split('\0').filter(|value| !value.is_empty()),
                );
            }
        }
    }
    Locale::EnUs
}

fn parse_shortcut_index(raw: Option<&str>) -> io::Result<u8> {
    raw.and_then(|value| value.parse::<u8>().ok())
        .filter(|index| (SHORTCUT_MIN..=SHORTCUT_MAX).contains(index))
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("el índice del atajo debe estar entre {SHORTCUT_MIN} y {SHORTCUT_MAX}"),
            )
        })
}

#[allow(dead_code)]
fn _assert_shell_result_is_used(_: ShellResult) {}
