use std::{collections::HashSet, fs, io, path::PathBuf};

use crate::{
    config::Config,
    input::{self, Key},
    model::{DirectoryEntry, ShellResult},
    render::{Renderer, fit},
    terminal::Terminal,
};

enum Mode {
    Normal,
    Filter,
    Path,
    Alias { target: PathBuf },
    Command { target: PathBuf },
}

pub struct App {
    home: PathBuf,
    current: PathBuf,
    entries: Vec<DirectoryEntry>,
    visible: Vec<usize>,
    selected: usize,
    scroll: usize,
    input: String,
    mode: Mode,
    message: String,
    config: Config,
    config_path: PathBuf,
    renderer: Renderer,
}

impl App {
    pub fn new(home: PathBuf, config: Config, config_path: PathBuf) -> io::Result<Self> {
        let mut app = Self {
            current: home.clone(),
            home,
            entries: Vec::new(),
            visible: Vec::new(),
            selected: 0,
            scroll: 0,
            input: String::new(),
            mode: Mode::Normal,
            message: String::new(),
            config,
            config_path,
            renderer: Renderer::new(),
        };
        app.refresh()?;
        Ok(app)
    }

    pub fn run(mut self, terminal: &mut Terminal) -> io::Result<Option<ShellResult>> {
        loop {
            self.render(terminal)?;
            let key = input::read_key()?;
            if let Some(result) = self.handle_key(key)? {
                return Ok(result);
            }
        }
    }

    fn handle_key(&mut self, key: Key) -> io::Result<Option<Option<ShellResult>>> {
        if matches!(key, Key::CtrlC) {
            return Ok(Some(None));
        }
        match &self.mode {
            Mode::Normal => self.handle_normal(key),
            Mode::Filter => {
                match key {
                    Key::Escape => {
                        self.input.clear();
                        self.mode = Mode::Normal;
                        self.rebuild_visible();
                    }
                    Key::Enter => self.mode = Mode::Normal,
                    Key::Backspace => {
                        self.input.pop();
                        self.rebuild_visible();
                    }
                    Key::Char(character) if !character.is_control() => {
                        self.input.push(character);
                        self.rebuild_visible();
                    }
                    Key::Up => self.move_selection(-1),
                    Key::Down => self.move_selection(1),
                    _ => {}
                }
                Ok(None)
            }
            Mode::Path => {
                match key {
                    Key::Escape => {
                        self.input.clear();
                        self.mode = Mode::Normal;
                    }
                    Key::Enter => {
                        let requested = PathBuf::from(self.input.trim().trim_matches('"'));
                        let path = if requested.is_absolute() {
                            requested
                        } else {
                            self.current.join(requested)
                        };
                        if path.is_dir() {
                            self.current = path;
                            self.selected = 0;
                            self.scroll = 0;
                            self.refresh()?;
                        } else {
                            self.message = format!("La ruta no existe: {}", path.display());
                            self.input.clear();
                            self.mode = Mode::Normal;
                        }
                    }
                    Key::Backspace => {
                        self.input.pop();
                    }
                    Key::Char(character) if !character.is_control() => {
                        self.input.push(character);
                    }
                    _ => {}
                }
                Ok(None)
            }
            Mode::Alias { target } => {
                let target = target.clone();
                match key {
                    Key::Escape => {
                        self.input.clear();
                        self.mode = Mode::Normal;
                    }
                    Key::Enter => {
                        self.config.set_alias(target, self.input.clone());
                        self.config.save(&self.config_path)?;
                        self.input.clear();
                        self.mode = Mode::Normal;
                        self.refresh()?;
                        self.message = "Alias guardado".into();
                    }
                    Key::Backspace => {
                        self.input.pop();
                    }
                    Key::Char(character) if !character.is_control() => self.input.push(character),
                    _ => {}
                }
                Ok(None)
            }
            Mode::Command { target } => {
                let target = target.clone();
                match key {
                    Key::Escape => {
                        self.input.clear();
                        self.mode = Mode::Normal;
                        Ok(None)
                    }
                    Key::Enter if !self.input.trim().is_empty() => {
                        let command = self.input.trim().to_owned();
                        Ok(Some(Some(ShellResult::Execute {
                            directory: target,
                            command,
                        })))
                    }
                    Key::Backspace => {
                        self.input.pop();
                        Ok(None)
                    }
                    Key::Char(character) if !character.is_control() => {
                        self.input.push(character);
                        Ok(None)
                    }
                    _ => Ok(None),
                }
            }
        }
    }

    fn handle_normal(&mut self, key: Key) -> io::Result<Option<Option<ShellResult>>> {
        match key {
            Key::Char('q') | Key::Escape => return Ok(Some(None)),
            Key::Up | Key::Char('k') => self.move_selection(-1),
            Key::Down | Key::Char('j') => self.move_selection(1),
            Key::Left | Key::Char('h') | Key::Backspace => self.go_parent()?,
            Key::Right | Key::Char('l') => self.open_selected()?,
            Key::Enter => {
                if let Some(entry) = self.selected_entry() {
                    return Ok(Some(Some(ShellResult::ChangeDirectory(entry.path.clone()))));
                }
            }
            Key::Char('.') => {
                return Ok(Some(Some(ShellResult::ChangeDirectory(
                    self.current.clone(),
                ))));
            }
            Key::Char('g') => {
                self.current = self.home.clone();
                self.refresh()?;
            }
            Key::Char('u') => {
                self.refresh()?;
                self.message = "Directorio actualizado".into();
            }
            Key::Char('/') => {
                self.input.clear();
                self.mode = Mode::Filter;
            }
            Key::Char('p') => {
                self.input.clear();
                self.mode = Mode::Path;
            }
            Key::Char('f') => self.toggle_favorite()?,
            Key::Char('a') => self.begin_alias(),
            Key::Char(':') => self.begin_command(),
            Key::Char(character) => {
                if let Some(command) = agent_command(character) {
                    return Ok(self.execute_selected(command));
                }
            }
            _ => {}
        }
        Ok(None)
    }

    fn refresh(&mut self) -> io::Result<()> {
        let mut entries = Vec::new();
        let mut seen = HashSet::new();
        for result in fs::read_dir(&self.current)? {
            let entry = match result {
                Ok(entry) => entry,
                Err(_) => continue,
            };
            let file_type = match entry.file_type() {
                Ok(kind) => kind,
                Err(_) => continue,
            };
            if !file_type.is_dir() {
                continue;
            }
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            seen.insert(path.clone());
            entries.push(DirectoryEntry {
                alias: self.config.alias(&path).map(str::to_owned),
                favorite: self.config.is_favorite(&path),
                path,
                name,
            });
        }
        for path in self.config.favorite_paths() {
            if path == self.current || seen.contains(path) || !path.is_dir() {
                continue;
            }
            let name = path
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_else(|| path.display().to_string());
            entries.push(DirectoryEntry {
                alias: self.config.alias(path).map(str::to_owned),
                favorite: true,
                path: path.to_path_buf(),
                name,
            });
        }
        entries.sort_by(|left, right| {
            right.favorite.cmp(&left.favorite).then_with(|| {
                left.label()
                    .to_lowercase()
                    .cmp(&right.label().to_lowercase())
            })
        });
        self.entries = entries;
        self.input.clear();
        self.mode = Mode::Normal;
        self.rebuild_visible();
        Ok(())
    }

    fn rebuild_visible(&mut self) {
        let query = self.input.to_lowercase();
        let mut scored: Vec<(usize, i32)> = self
            .entries
            .iter()
            .enumerate()
            .filter_map(|(index, entry)| {
                fuzzy_score(&entry.label(), &query).map(|score| (index, score))
            })
            .collect();
        if !query.is_empty() {
            scored.sort_by(|(left_index, left_score), (right_index, right_score)| {
                right_score.cmp(left_score).then_with(|| {
                    self.entries[*left_index]
                        .label()
                        .cmp(&self.entries[*right_index].label())
                })
            });
        }
        self.visible = scored.into_iter().map(|(index, _)| index).collect();
        self.selected = self.selected.min(self.visible.len().saturating_sub(1));
        self.scroll = self.scroll.min(self.selected);
    }

    fn selected_entry(&self) -> Option<&DirectoryEntry> {
        self.visible
            .get(self.selected)
            .and_then(|index| self.entries.get(*index))
    }

    fn move_selection(&mut self, delta: isize) {
        if self.visible.is_empty() {
            return;
        }
        self.selected = self
            .selected
            .saturating_add_signed(delta)
            .min(self.visible.len() - 1);
    }

    fn open_selected(&mut self) -> io::Result<()> {
        if let Some(path) = self.selected_entry().map(|entry| entry.path.clone()) {
            self.current = path;
            self.selected = 0;
            self.scroll = 0;
            self.refresh()?;
        }
        Ok(())
    }

    fn go_parent(&mut self) -> io::Result<()> {
        if let Some(parent) = self.current.parent() {
            self.current = parent.to_path_buf();
            self.selected = 0;
            self.scroll = 0;
            self.refresh()?;
        }
        Ok(())
    }

    fn toggle_favorite(&mut self) -> io::Result<()> {
        if let Some(path) = self.selected_entry().map(|entry| entry.path.clone()) {
            let enabled = self.config.toggle_favorite(&path);
            self.config.save(&self.config_path)?;
            self.refresh()?;
            self.message = if enabled {
                "Añadido a favoritos"
            } else {
                "Eliminado de favoritos"
            }
            .into();
        }
        Ok(())
    }

    fn begin_alias(&mut self) {
        if let Some(entry) = self.selected_entry() {
            let target = entry.path.clone();
            let alias = entry.alias.clone().unwrap_or_default();
            self.input = alias;
            self.mode = Mode::Alias { target };
        }
    }

    fn begin_command(&mut self) {
        let target = self
            .selected_entry()
            .map(|entry| entry.path.clone())
            .unwrap_or_else(|| self.current.clone());
        self.input.clear();
        self.mode = Mode::Command { target };
    }

    fn execute_selected(&self, command: &str) -> Option<Option<ShellResult>> {
        self.selected_entry().map(|entry| {
            Some(ShellResult::Execute {
                directory: entry.path.clone(),
                command: command.to_owned(),
            })
        })
    }

    fn render(&mut self, terminal: &Terminal) -> io::Result<()> {
        let (width, height) = terminal.size();
        let width = usize::from(width.max(42));
        let height = usize::from(height.max(12));
        let inner = width.saturating_sub(4);
        let list_height = height.saturating_sub(7);
        if self.selected < self.scroll {
            self.scroll = self.selected;
        }
        if self.selected >= self.scroll + list_height {
            self.scroll = self.selected + 1 - list_height;
        }

        let mut rows = Vec::with_capacity(height);
        rows.push(format!(
            "\x1b[38;2;116;199;236m╭─ DEV \x1b[2m{}\x1b[22m{}╮\x1b[0m",
            fit(&self.current.display().to_string(), width.saturating_sub(9)),
            "─"
        ));
        rows.push(format!(
            "\x1b[38;2;90;100;120m│\x1b[0m {} \x1b[38;2;90;100;120m│\x1b[0m",
            fit("★  ALIAS / DIRECTORIO", inner)
        ));
        rows.push(format!(
            "\x1b[38;2;90;100;120m├{}┤\x1b[0m",
            "─".repeat(width.saturating_sub(2))
        ));

        for row_index in 0..list_height {
            let visible_index = self.scroll + row_index;
            let content = if let Some(entry_index) = self.visible.get(visible_index) {
                let entry = &self.entries[*entry_index];
                let marker = if entry.favorite { "★" } else { " " };
                let prefix = if visible_index == self.selected {
                    "›"
                } else {
                    " "
                };
                let label = format!("{prefix} {marker}  {}", entry.label());
                if visible_index == self.selected {
                    format!(
                        "\x1b[48;2;32;43;65m\x1b[38;2;232;238;252m{}\x1b[0m",
                        fit(&label, inner)
                    )
                } else {
                    fit(&label, inner)
                }
            } else {
                " ".repeat(inner)
            };
            rows.push(format!(
                "\x1b[38;2;90;100;120m│\x1b[0m {content} \x1b[38;2;90;100;120m│\x1b[0m"
            ));
        }

        rows.push(format!(
            "\x1b[38;2;90;100;120m├{}┤\x1b[0m",
            "─".repeat(width.saturating_sub(2))
        ));
        let prompt = match self.mode {
            Mode::Normal => {
                if self.message.is_empty() {
                    format!("{} carpetas", self.visible.len())
                } else {
                    self.message.clone()
                }
            }
            Mode::Filter => format!("/{}", self.input),
            Mode::Path => format!("ruta › {}_", self.input),
            Mode::Alias { .. } => format!("alias › {}_", self.input),
            Mode::Command { .. } => format!("comando › {}_", self.input),
        };
        rows.push(format!(
            "\x1b[38;2;90;100;120m│\x1b[0m {} \x1b[38;2;90;100;120m│\x1b[0m",
            fit(&prompt, inner)
        ));
        let help = "c Codex  r última sesión Codex del repo  d Claude  o OpenCode  i Kimi  Mayús+D/O/I última sesión  ↑↓ mover  Enter cd  → abrir  p ruta  f favorito  a alias  / filtrar  q salir";
        rows.push(format!(
            "\x1b[38;2;90;100;120m╰─{}─╯\x1b[0m",
            fit(help, width.saturating_sub(4))
        ));
        self.renderer.draw(rows)
    }
}

fn agent_command(key: char) -> Option<&'static str> {
    match key {
        'c' => Some("codex"),
        'r' => Some("codex resume --last"),
        'd' => Some("claude"),
        'D' => Some("claude --continue"),
        'o' => Some("opencode"),
        'O' => Some("opencode --continue"),
        'i' => Some("kimi"),
        'I' => Some("kimi --continue"),
        _ => None,
    }
}

fn fuzzy_score(candidate: &str, query: &str) -> Option<i32> {
    if query.is_empty() {
        return Some(0);
    }
    let candidate = candidate.to_lowercase();
    let mut score = 0_i32;
    let mut cursor = 0;
    let mut previous = None;
    for wanted in query.chars() {
        let found = candidate[cursor..]
            .char_indices()
            .find(|(_, character)| *character == wanted)?;
        let absolute = cursor + found.0;
        score += 20;
        if previous == Some(absolute.saturating_sub(1)) {
            score += 25;
        }
        if absolute == 0 || candidate[..absolute].ends_with(['-', '_', ' ', '\\', '/']) {
            score += 15;
        }
        score -= absolute as i32;
        cursor = absolute + wanted.len_utf8();
        previous = Some(absolute);
    }
    Some(score)
}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::{App, agent_command, fuzzy_score};
    use crate::{config::Config, render::fit};

    #[test]
    fn contiguous_matches_rank_higher() {
        assert!(
            fuzzy_score("renderer-core", "core") > fuzzy_score("code-old-rust-example", "core")
        );
    }

    #[test]
    fn rejects_non_matching_text() {
        assert_eq!(fuzzy_score("alpha", "xyz"), None);
    }

    #[test]
    fn agent_shortcuts_map_to_new_and_previous_repo_sessions() {
        assert_eq!(agent_command('c'), Some("codex"));
        assert_eq!(agent_command('r'), Some("codex resume --last"));
        assert_eq!(agent_command('d'), Some("claude"));
        assert_eq!(agent_command('D'), Some("claude --continue"));
        assert_eq!(agent_command('o'), Some("opencode"));
        assert_eq!(agent_command('O'), Some("opencode --continue"));
        assert_eq!(agent_command('i'), Some("kimi"));
        assert_eq!(agent_command('I'), Some("kimi --continue"));
        assert_eq!(agent_command('x'), None);
    }

    #[test]
    fn top_border_uses_the_full_terminal_width() {
        let width = 120_usize;
        let border = format!(
            "╭─ DEV {}─╮",
            fit("C:\\Users\\User\\programacion", width.saturating_sub(9))
        );

        assert_eq!(border.chars().count(), width);
    }

    #[test]
    fn favorites_outside_root_are_always_injected() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time")
            .as_nanos();
        let sandbox = std::env::temp_dir().join(format!("devnav-test-{unique}"));
        let root = sandbox.join("root");
        let external = sandbox.join("external-repo");
        fs::create_dir_all(&root).expect("create root");
        fs::create_dir_all(&external).expect("create external favorite");

        let mut config = Config::default();
        config.toggle_favorite(&external);
        let app = App::new(root, config, sandbox.join("config.tsv")).expect("create app");

        assert!(
            app.entries
                .iter()
                .any(|entry| entry.path == external && entry.favorite)
        );
        fs::remove_dir_all(sandbox).expect("clean test sandbox");
    }
}
