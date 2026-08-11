mod app;
mod config;
mod input;
mod model;
mod render;
mod terminal;

use std::{env, io, path::PathBuf, process::ExitCode};

use app::App;
use config::Config;
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
    let result_path = argument_value(&args, "--result").map(PathBuf::from);
    let config_path = Config::default_path()?;
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
    args.windows(2)
        .find(|pair| pair[0] == name)
        .map(|pair| pair[1].clone())
}

fn default_root() -> Option<PathBuf> {
    env::var_os("USERPROFILE").map(PathBuf::from).map(|home| {
        let projects = home.join("programacion");
        if projects.is_dir() { projects } else { home }
    })
}

#[allow(dead_code)]
fn _assert_shell_result_is_used(_: ShellResult) {}
