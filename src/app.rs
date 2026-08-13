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
    Help,
    Filter,
    Path,
    Alias { target: PathBuf },
    Command { target: PathBuf },
    ConfirmRoot { target: PathBuf },
}

pub struct App {
    home: PathBuf,
    current: PathBuf,
    entries: Vec<DirectoryEntry>,
    visible: Vec<usize>,
    selected: usize,
    scroll: usize,
    help_scroll: usize,
    input: String,
    mode: Mode,
    help_return_mode: Option<Mode>,
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
            help_scroll: 0,
            input: String::new(),
            mode: Mode::Normal,
            help_return_mode: None,
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

    // The nested Option is the intentional run-loop outcome protocol:
    //   None         = keep running (no result)
    //   Some(None)   = leave the loop without a shell result (quit)
    //   Some(Some(r))= leave the loop and emit `r` to the wrapper
    // A dedicated enum would be clearer, but that is a semantic refactor of
    // working code, out of scope for a pedantic audit.
    #[allow(clippy::option_option)]
    #[allow(clippy::too_many_lines)]
    fn handle_key(&mut self, key: Key) -> io::Result<Option<Option<ShellResult>>> {
        if matches!(key, Key::CtrlC) {
            return Ok(Some(None));
        }
        if matches!(key, Key::F1) {
            self.toggle_help();
            return Ok(None);
        }
        match &self.mode {
            Mode::Normal => self.handle_normal(key),
            Mode::Help => {
                match key {
                    Key::Escape | Key::Enter | Key::Char('q') => {
                        self.close_help();
                    }
                    Key::Up | Key::Char('k') => {
                        self.help_scroll = self.help_scroll.saturating_sub(1);
                    }
                    Key::Down | Key::Char('j') => {
                        self.help_scroll = self.help_scroll.saturating_add(1);
                    }
                    _ => {}
                }
                Ok(None)
            }
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
                        Ok(Some(Some(ShellResult::Execute { directory: target, command })))
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
            Mode::ConfirmRoot { target } => {
                let target = target.clone();
                match key {
                    Key::Enter => {
                        self.config.set_root(target.clone());
                        self.config.save(&self.config_path)?;
                        self.home.clone_from(&target);
                        self.mode = Mode::Normal;
                        self.message = format!("Ruta de inicio guardada: {}", target.display());
                    }
                    Key::Escape | Key::Char('q') => {
                        self.mode = Mode::Normal;
                        self.message = "Cambio de ruta cancelado".into();
                    }
                    _ => {}
                }
                Ok(None)
            }
        }
    }

    /// See `handle_key`: the nested Option encodes the run-loop outcome
    /// (continue / quit / emit) and is intentional.
    #[allow(clippy::option_option)]
    fn handle_normal(&mut self, key: Key) -> io::Result<Option<Option<ShellResult>>> {
        match key {
            Key::Char('q') | Key::Escape => return Ok(Some(None)),
            Key::CtrlS => self.begin_root_confirmation(),
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
                return Ok(Some(Some(ShellResult::ChangeDirectory(self.current.clone()))));
            }
            Key::Char('g') => {
                self.current = self.home.clone();
                self.refresh()?;
            }
            Key::Char('u') => {
                self.refresh()?;
                self.message = "Directorio actualizado".into();
            }
            Key::Char('U') => return Ok(Some(Some(ShellResult::Update))),
            Key::CtrlU => self.toggle_update_checks()?,
            Key::Char('/') => {
                self.input.clear();
                self.mode = Mode::Filter;
            }
            Key::Char('p') => {
                self.input.clear();
                self.mode = Mode::Path;
            }
            Key::Char('f') => self.toggle_favorite()?,
            Key::Char('F') => self.toggle_favorites_visibility()?,
            Key::Char('a') => self.begin_alias(),
            Key::Char(character) if is_command_shortcut(character) => self.begin_command(),
            Key::Shortcut(slot) => return Ok(self.execute_shortcut(slot).map(Some)),
            Key::Char(character) => {
                if let Some(command) = agent_command(character) {
                    return Ok(self.execute_selected(command).map(Some));
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
        if self.config.show_favorites() {
            for path in self.config.favorite_paths() {
                if seen.contains(path) || !path.is_dir() {
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
        }
        entries.sort_by(|left, right| {
            right
                .favorite
                .cmp(&left.favorite)
                .then_with(|| left.label().to_lowercase().cmp(&right.label().to_lowercase()))
        });
        self.entries = entries;
        self.input.clear();
        self.mode = Mode::Normal;
        self.help_return_mode = None;
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
                    self.entries[*left_index].label().cmp(&self.entries[*right_index].label())
                })
            });
        }
        self.visible = scored.into_iter().map(|(index, _)| index).collect();
        self.selected = self.selected.min(self.visible.len().saturating_sub(1));
        self.scroll = self.scroll.min(self.selected);
    }

    fn selected_entry(&self) -> Option<&DirectoryEntry> {
        self.visible.get(self.selected).and_then(|index| self.entries.get(*index))
    }

    fn move_selection(&mut self, delta: isize) {
        if self.visible.is_empty() {
            return;
        }
        self.selected = self.selected.saturating_add_signed(delta).min(self.visible.len() - 1);
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
            self.message =
                if enabled { "Añadido a favoritos" } else { "Eliminado de favoritos" }.into();
        }
        Ok(())
    }

    fn toggle_favorites_visibility(&mut self) -> io::Result<()> {
        let visible = self.config.toggle_favorites_visibility();
        self.config.save(&self.config_path)?;
        self.selected = 0;
        self.scroll = 0;
        self.refresh()?;
        self.message =
            if visible { "Favoritos globales visibles" } else { "Favoritos globales ocultos" }
                .into();
        Ok(())
    }

    fn toggle_update_checks(&mut self) -> io::Result<()> {
        let enabled = self.config.toggle_update_checks();
        self.config.save(&self.config_path)?;
        self.message = if enabled {
            "Comprobación de actualizaciones al iniciar: activada"
        } else {
            "Comprobación de actualizaciones al iniciar: desactivada"
        }
        .into();
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

    fn begin_root_confirmation(&mut self) {
        let target = self
            .selected_entry()
            .map(|entry| entry.path.clone())
            .unwrap_or_else(|| self.current.clone());
        self.mode = Mode::ConfirmRoot { target };
    }

    fn toggle_help(&mut self) {
        if matches!(self.mode, Mode::Help) {
            self.close_help();
        } else {
            let previous = std::mem::replace(&mut self.mode, Mode::Help);
            self.help_return_mode = Some(previous);
            self.help_scroll = 0;
        }
    }

    fn close_help(&mut self) {
        self.mode = self.help_return_mode.take().unwrap_or(Mode::Normal);
    }

    fn execute_selected(&self, command: &str) -> Option<ShellResult> {
        self.selected_entry().map(|entry| ShellResult::Execute {
            directory: entry.path.clone(),
            command: command.to_owned(),
        })
    }

    /// Runs the Shift+digit shortcut bound to `slot` against the highlighted
    /// entry. An empty or out-of-range slot, or an empty list, is a no-op
    /// (returns `None`) and never falls through to another action.
    fn execute_shortcut(&self, slot: u8) -> Option<ShellResult> {
        let shortcut = self.config.shortcut(slot)?;
        self.selected_entry().map(|entry| ShellResult::Execute {
            directory: entry.path.clone(),
            command: shortcut.command.clone(),
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
        let list_header = if self.config.show_favorites() {
            "★  FAVORITOS VISIBLES · ALIAS / DIRECTORIO"
        } else {
            "☆  FAVORITOS OCULTOS · Mayús+F para mostrar"
        };
        rows.push(format!(
            "\x1b[38;2;90;100;120m│\x1b[0m {} \x1b[38;2;90;100;120m│\x1b[0m",
            fit(list_header, inner)
        ));
        rows.push(format!("\x1b[38;2;90;100;120m├{}┤\x1b[0m", "─".repeat(width.saturating_sub(2))));

        let lines = help_lines(&self.config);
        let help_layout = matches!(self.mode, Mode::Help)
            .then(|| HelpLayout::new(inner, list_height, &mut self.help_scroll, lines.clone()));
        for row_index in 0..list_height {
            let content = if let Some(layout) = &help_layout {
                layout.render_row(row_index, inner)
            } else {
                let visible_index = self.scroll + row_index;
                if let Some(entry_index) = self.visible.get(visible_index) {
                    let entry = &self.entries[*entry_index];
                    let marker = if entry.favorite { "★" } else { " " };
                    let prefix = if visible_index == self.selected { "›" } else { " " };
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
                }
            };
            rows.push(format!(
                "\x1b[38;2;90;100;120m│\x1b[0m {content} \x1b[38;2;90;100;120m│\x1b[0m"
            ));
        }

        rows.push(format!("\x1b[38;2;90;100;120m├{}┤\x1b[0m", "─".repeat(width.saturating_sub(2))));
        let prompt = match self.mode {
            Mode::Normal => {
                if self.message.is_empty() {
                    format!("{} carpetas", self.visible.len())
                } else {
                    self.message.clone()
                }
            }
            Mode::Help => format!(
                "Shortcuts · {} acciones disponibles",
                lines.iter().filter(|line| matches!(line, HelpLine::Shortcut(_, _))).count()
            ),
            Mode::Filter => format!("/{}", self.input),
            Mode::Path => format!("ruta › {}_", self.input),
            Mode::Alias { .. } => format!("alias › {}_", self.input),
            Mode::Command { .. } => format!("comando › {}_", self.input),
            Mode::ConfirmRoot { ref target } => {
                format!("¿Guardar como inicio?  {}", target.display())
            }
        };
        rows.push(format!(
            "\x1b[38;2;90;100;120m│\x1b[0m {} \x1b[38;2;90;100;120m│\x1b[0m",
            fit(&prompt, inner)
        ));
        let help = self.footer_line();
        rows.push(format!(
            "\x1b[38;2;90;100;120m╰─{}─╯\x1b[0m",
            fit(&help, width.saturating_sub(4))
        ));
        self.renderer.draw(rows)
    }

    /// Normal-mode footer with the configured shortcut aliases appended so the
    /// bound slots are visible at a glance; other modes reuse the static copy.
    fn footer_line(&self) -> String {
        let Mode::Normal = &self.mode else {
            return footer_help(&self.mode).to_string();
        };
        let mut footer = footer_help(&Mode::Normal).to_string();
        let shortcuts = self.config.configured_shortcuts();
        if shortcuts.is_empty() {
            return footer;
        }
        footer.push_str("  ");
        for (slot, shortcut) in shortcuts {
            use std::fmt::Write as _;
            let _ = write!(footer, "⇧{slot}");
            if let Some(alias) = shortcut.alias.as_deref().filter(|alias| !alias.is_empty()) {
                footer.push(' ');
                footer.push_str(alias);
            }
            footer.push_str("  ");
        }
        footer
    }
}

#[derive(Clone, Debug)]
enum HelpLine {
    Section(String),
    Shortcut(String, String),
    Blank,
}

fn help_lines(config: &Config) -> Vec<HelpLine> {
    let mut lines: Vec<HelpLine> = vec![
        HelpLine::Section("NAVEGACIÓN".into()),
        HelpLine::Shortcut("↑ / ↓ · j / k".into(), "Navegar por las carpetas".into()),
        HelpLine::Shortcut("→ / l".into(), "Entrar en la carpeta resaltada".into()),
        HelpLine::Shortcut("← / h / Retroceso".into(), "Volver a la carpeta padre".into()),
        HelpLine::Shortcut("Enter".into(), "Seleccionar carpeta y volver a PowerShell".into()),
        HelpLine::Shortcut(".".into(), "Seleccionar la carpeta mostrada".into()),
        HelpLine::Shortcut("g".into(), "Volver a la ruta de inicio".into()),
        HelpLine::Shortcut("p".into(), "Abrir cualquier ruta o unidad".into()),
        HelpLine::Shortcut("Ctrl+S".into(), "Guardar la carpeta resaltada como inicio".into()),
        HelpLine::Blank,
        HelpLine::Section("BÚSQUEDA Y ORGANIZACIÓN".into()),
        HelpLine::Shortcut("/".into(), "Filtrar carpetas mientras escribes".into()),
        HelpLine::Shortcut("f".into(), "Añadir o quitar un favorito global".into()),
        HelpLine::Shortcut("Mayús+F".into(), "Mostrar u ocultar los favoritos globales".into()),
        HelpLine::Shortcut("a".into(), "Crear o editar el alias de la carpeta".into()),
        HelpLine::Shortcut("u".into(), "Actualizar el directorio actual".into()),
        HelpLine::Shortcut("Ctrl+U".into(), "Activar o desactivar comprobación al iniciar".into()),
        HelpLine::Shortcut("Mayús+U".into(), "Actualizar DevNav a la última versión".into()),
        HelpLine::Blank,
        HelpLine::Section("AGENTES EN EL REPOSITORIO".into()),
        HelpLine::Shortcut("c".into(), "Codex: sesión nueva".into()),
        HelpLine::Shortcut("r".into(), "Codex: última sesión del repositorio".into()),
        HelpLine::Shortcut(
            "d / Mayús+D".into(),
            "Claude Code: sesión nueva / última sesión".into(),
        ),
        HelpLine::Shortcut("o / Mayús+O".into(), "OpenCode: sesión nueva / última sesión".into()),
        HelpLine::Shortcut("i / Mayús+I".into(), "Kimi: sesión nueva / última sesión".into()),
        HelpLine::Blank,
        HelpLine::Section("ACCIONES".into()),
        HelpLine::Shortcut("e / :".into(), "Ejecutar un comando en la carpeta resaltada".into()),
        HelpLine::Shortcut(
            "⇧1-⇧9".into(),
            "Ejecutar un atajo configurado en la carpeta resaltada".into(),
        ),
        HelpLine::Shortcut("F1".into(), "Abrir o cerrar este panel de ayuda".into()),
        HelpLine::Shortcut("q / Esc".into(), "Salir de DevNav o cancelar".into()),
    ];
    // Dynamic section: only configured slots appear, so the panel never lists
    // nine empty entries.
    let shortcuts = config.configured_shortcuts();
    if !shortcuts.is_empty() {
        lines.push(HelpLine::Blank);
        lines.push(HelpLine::Section("ATAJOS PERSONALIZADOS".into()));
        for (slot, shortcut) in shortcuts {
            let description = match shortcut.alias.as_deref().filter(|alias| !alias.is_empty()) {
                Some(alias) => format!("{alias} → {}", shortcut.command),
                None => shortcut.command.clone(),
            };
            lines.push(HelpLine::Shortcut(format!("⇧{slot}"), description));
        }
    }
    lines
}

struct HelpLayout {
    width: usize,
    height: usize,
    top: usize,
    start: usize,
    lines: Vec<HelpLine>,
}

impl HelpLayout {
    fn new(inner: usize, list_height: usize, scroll: &mut usize, lines: Vec<HelpLine>) -> Self {
        let width = inner.min(104);
        let height = list_height.min(lines.len().saturating_add(2));
        let capacity = height.saturating_sub(2);
        let max_scroll = lines.len().saturating_sub(capacity);
        *scroll = (*scroll).min(max_scroll);
        Self { width, height, top: list_height.saturating_sub(height) / 2, start: *scroll, lines }
    }

    fn render_row(&self, row: usize, outer_width: usize) -> String {
        if row < self.top || row >= self.top + self.height || self.height < 2 {
            return " ".repeat(outer_width);
        }
        let local = row - self.top;
        let panel = if local == 0 {
            panel_border(self.width, "SHORTCUTS", true)
        } else if local + 1 == self.height {
            panel_border(self.width, "↑↓ DESPLAZAR  ·  F1 / ESC CERRAR", false)
        } else {
            render_help_line(
                self.lines.get(self.start + local - 1).cloned().unwrap_or(HelpLine::Blank),
                self.width,
            )
        };
        let left = outer_width.saturating_sub(self.width) / 2;
        let right = outer_width.saturating_sub(self.width + left);
        format!("{}{}{}", " ".repeat(left), panel, " ".repeat(right))
    }
}

fn render_help_line(line: HelpLine, width: usize) -> String {
    let content_width = width.saturating_sub(2);
    match line {
        HelpLine::Section(title) => format!(
            "\x1b[38;2;90;100;120m│\x1b[0m\x1b[38;2;116;199;236m{}\x1b[0m\x1b[38;2;90;100;120m│\x1b[0m",
            fit(&format!("  {title}"), content_width)
        ),
        HelpLine::Shortcut(keys, description) => {
            let key_width = 18.min(content_width.saturating_sub(12)).max(1);
            let description_width = content_width.saturating_sub(key_width + 3);
            format!(
                "\x1b[38;2;90;100;120m│\x1b[0m  \x1b[38;2;255;203;107m{}\x1b[0m {}\x1b[38;2;90;100;120m│\x1b[0m",
                fit(&keys, key_width),
                fit(&description, description_width)
            )
        }
        HelpLine::Blank => format!(
            "\x1b[38;2;90;100;120m│\x1b[0m{}\x1b[38;2;90;100;120m│\x1b[0m",
            " ".repeat(content_width)
        ),
    }
}

fn panel_border(width: usize, label: &str, top: bool) -> String {
    let (left, right) = if top { ('╭', '╮') } else { ('╰', '╯') };
    let label = label.chars().take(width.saturating_sub(5)).collect::<String>();
    let prefix = format!("{left}─ {label} ");
    let fill = width.saturating_sub(prefix.chars().count() + 1);
    format!("\x1b[38;2;116;199;236m{prefix}{}{right}\x1b[0m", "─".repeat(fill))
}

fn footer_help(mode: &Mode) -> &'static str {
    match mode {
        Mode::Normal => {
            "↑↓ Navegar  Enter Seleccionar  → Abrir  Ctrl+S Guardar inicio  F1 Shortcuts  q Salir"
        }
        Mode::Help => "↑↓ Desplazar  F1 / Esc Cerrar ayuda",
        Mode::Filter => "Escribe para buscar  ↑↓ Navegar  Enter Aplicar  Esc Cancelar",
        Mode::Path => "Escribe una ruta  Enter Abrir  Esc Cancelar",
        Mode::Alias { .. } => "Escribe un alias  Enter Guardar  Esc Cancelar",
        Mode::Command { .. } => "Escribe un comando  Enter Ejecutar  Esc Cancelar",
        Mode::ConfirmRoot { .. } => "Enter Confirmar nueva ruta de inicio  Esc Cancelar",
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

fn is_command_shortcut(key: char) -> bool {
    matches!(key, 'e' | ':')
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
        let found =
            candidate[cursor..].char_indices().find(|(_, character)| *character == wanted)?;
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
        collections::HashSet,
        fs,
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::{
        App, Mode, ShellResult, agent_command, footer_help, fuzzy_score, is_command_shortcut,
    };
    use crate::{config::Config, input::Key, render::fit};

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
    fn execute_uses_a_mnemonic_key_and_keeps_the_legacy_alias() {
        assert!(is_command_shortcut('e'));
        assert!(is_command_shortcut(':'));
        assert!(!is_command_shortcut('x'));
    }

    #[test]
    fn normal_footer_keeps_help_discoverable_without_overloading_it() {
        let footer = footer_help(&Mode::Normal);

        assert!(footer.contains("Ctrl+S Guardar inicio"));
        assert!(footer.contains("F1 Shortcuts"));
        assert!(footer.contains("Enter Seleccionar"));
        assert!(footer.chars().count() < 90);
    }

    #[test]
    fn top_border_uses_the_full_terminal_width() {
        let width = 120_usize;
        let border = format!("╭─ DEV {}─╮", fit("C:\\Users\\Example", width.saturating_sub(9)));

        assert_eq!(border.chars().count(), width);
    }

    #[test]
    fn every_global_favorite_is_injected_including_the_current_directory() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let sandbox = std::env::temp_dir().join(format!("devnav-test-{unique}"));
        let root = sandbox.join("root");
        let external_one = sandbox.join("external-one");
        let external_two = sandbox.join("external-two");
        fs::create_dir_all(&root).expect("create root");
        fs::create_dir_all(&external_one).expect("create first external favorite");
        fs::create_dir_all(&external_two).expect("create second external favorite");

        let mut config = Config::default();
        config.toggle_favorite(&root);
        config.toggle_favorite(&external_one);
        config.toggle_favorite(&external_two);
        let app = App::new(root, config, sandbox.join("config.tsv")).expect("create app");

        let favorite_paths: HashSet<_> = app
            .entries
            .iter()
            .filter(|entry| entry.favorite)
            .map(|entry| entry.path.clone())
            .collect();
        assert_eq!(favorite_paths.len(), 3);
        assert!(favorite_paths.contains(&app.current));
        assert!(favorite_paths.contains(&external_one));
        assert!(favorite_paths.contains(&external_two));
        fs::remove_dir_all(sandbox).expect("clean test sandbox");
    }

    #[test]
    fn hidden_global_favorites_do_not_remove_real_child_directories() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let sandbox = std::env::temp_dir().join(format!("devnav-hidden-test-{unique}"));
        let root = sandbox.join("root");
        let child = root.join("favorite-child");
        let external = sandbox.join("external");
        fs::create_dir_all(&child).expect("create child");
        fs::create_dir_all(&external).expect("create external");
        let mut config = Config::default();
        config.toggle_favorite(&child);
        config.toggle_favorite(&external);
        config.toggle_favorites_visibility();

        let app = App::new(root, config, sandbox.join("config.tsv")).expect("create app");

        assert!(app.entries.iter().any(|entry| entry.path == child));
        assert!(!app.entries.iter().any(|entry| entry.path == external));
        fs::remove_dir_all(sandbox).expect("clean test sandbox");
    }

    #[test]
    fn control_s_requires_confirmation_before_saving_the_highlighted_root() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let sandbox = std::env::temp_dir().join(format!("devnav-root-test-{unique}"));
        let initial_root = sandbox.join("home");
        let selected_root = initial_root.join("repositorios");
        let config_path = sandbox.join("config.tsv");
        fs::create_dir_all(&selected_root).expect("create selected root");
        let mut app =
            App::new(initial_root, Config::default(), config_path.clone()).expect("create app");

        app.handle_key(Key::CtrlS).expect("open confirmation");
        assert!(matches!(
            &app.mode,
            Mode::ConfirmRoot { target } if target == &selected_root
        ));
        assert!(Config::load(&config_path).expect("load").root().is_none());

        app.handle_key(Key::Enter).expect("confirm root");
        assert_eq!(Config::load(&config_path).expect("load").root(), Some(selected_root.as_path()));
        fs::remove_dir_all(sandbox).expect("clean test sandbox");
    }

    fn shortcut_sandbox(label: &str) -> (std::path::PathBuf, std::path::PathBuf) {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let sandbox = std::env::temp_dir().join(format!("devnav-shortcut-{label}-{unique}"));
        let root = sandbox.join("home");
        fs::create_dir_all(&root).expect("create sandbox root");
        (sandbox, root)
    }

    #[test]
    fn configured_shortcut_executes_against_the_selected_path() {
        let (sandbox, root) = shortcut_sandbox("exec");
        let project = root.join("my-project");
        fs::create_dir_all(&project).expect("create project");

        let mut config = Config::default();
        assert!(config.set_shortcut(1, Some("Dev".into()), "bun run dev".into()));
        let mut app = App::new(root, config, sandbox.join("config.tsv")).expect("create app");
        assert_eq!(app.selected_entry().map(|entry| entry.path.clone()), Some(project.clone()));

        match app.handle_key(Key::Shortcut(1)).expect("run shortcut") {
            Some(Some(ShellResult::Execute { directory, command })) => {
                assert_eq!(directory, project);
                assert_eq!(command, "bun run dev");
            }
            other => panic!("expected ShellResult::Execute for the selected path, got {other:?}"),
        }
        fs::remove_dir_all(sandbox).expect("clean test sandbox");
    }

    #[test]
    fn empty_shortcut_slot_does_nothing() {
        let (sandbox, root) = shortcut_sandbox("empty");
        let project = root.join("project");
        fs::create_dir_all(&project).expect("create project");

        let mut app =
            App::new(root, Config::default(), sandbox.join("config.tsv")).expect("create app");

        for slot in [1_u8, 5, 9] {
            assert_eq!(app.handle_key(Key::Shortcut(slot)).expect("empty slot"), None);
        }
        assert!(matches!(app.mode, Mode::Normal));
        fs::remove_dir_all(sandbox).expect("clean test sandbox");
    }

    #[test]
    fn shortcut_persists_and_runs_again_after_reload() {
        let (sandbox, root) = shortcut_sandbox("reload");
        let project = root.join("project");
        fs::create_dir_all(&project).expect("create project");
        let config_path = sandbox.join("config.tsv");

        let mut config = Config::default();
        assert!(config.set_shortcut(9, Some("Tests".into()), "cargo test".into()));
        config.save(&config_path).expect("save shortcut");

        let reloaded = Config::load(&config_path).expect("load");
        let mut app = App::new(root, reloaded, config_path).expect("create app");
        match app.handle_key(Key::Shortcut(9)).expect("run shortcut") {
            Some(Some(ShellResult::Execute { command, .. })) => assert_eq!(command, "cargo test"),
            other => panic!("expected Execute after reload, got {other:?}"),
        }
        fs::remove_dir_all(sandbox).expect("clean test sandbox");
    }

    #[test]
    fn configured_shortcuts_appear_in_the_help_panel_with_alias_and_command() {
        let mut config = Config::default();
        config.set_shortcut(1, Some("Dev".into()), "bun run dev".into());
        config.set_shortcut(2, None, "cargo test".into());

        let lines = super::help_lines(&config);
        let has_section = lines.iter().any(|line| {
            matches!(line, super::HelpLine::Section(title) if title == "ATAJOS PERSONALIZADOS")
        });
        assert!(has_section, "dynamic shortcuts section must appear when slots are configured");

        let descriptions: Vec<String> = lines
            .iter()
            .filter_map(|line| match line {
                super::HelpLine::Shortcut(key, description) if key.starts_with('⇧') => {
                    Some(description.clone())
                }
                _ => None,
            })
            .collect();
        assert!(descriptions.iter().any(|d| d.contains("Dev") && d.contains("bun run dev")));
        assert!(descriptions.iter().any(|d| d == "cargo test"));
    }

    #[test]
    fn no_shortcuts_section_when_nothing_is_configured() {
        let lines = super::help_lines(&Config::default());
        assert!(!lines.iter().any(|line| {
            matches!(line, super::HelpLine::Section(title) if title == "ATAJOS PERSONALIZADOS")
        }));
    }

    #[test]
    fn normal_footer_lists_configured_shortcut_aliases() {
        let (sandbox, root) = shortcut_sandbox("footer");
        let mut config = Config::default();
        config.set_shortcut(1, Some("Dev".into()), "bun run dev".into());
        config.set_shortcut(2, None, "cargo test".into());

        let app = App::new(root, config, sandbox.join("config.tsv")).expect("create app");
        let footer = app.footer_line();

        assert!(footer.contains("⇧1 Dev"));
        assert!(footer.contains("⇧2"));
        // Unconfigured slots must not clutter the footer.
        assert!(!footer.contains("⇧3"));
        fs::remove_dir_all(sandbox).expect("clean test sandbox");
    }
}
