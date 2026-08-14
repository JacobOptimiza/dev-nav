use std::{collections::HashSet, fs, io, path::PathBuf};

use crate::{
    config::Config,
    i18n::{KeyBinding, KeyToken, Locale, Modifier, format_binding},
    input::{self, Key},
    model::{DirectoryEntry, ShellResult},
    render::{Renderer, fit},
    terminal::Terminal,
};

#[derive(Clone)]
enum Mode {
    Normal,
    Help,
    Filter,
    Path,
    Alias { target: PathBuf },
    Command { target: PathBuf },
    ConfirmRoot { target: PathBuf },
    Commands { selected: usize },
    CommandEditor { slot: u8, field: EditorField, alias: TextField, command: TextField },
    ConfirmDelete { slot: u8 },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum EditorField {
    Alias,
    Command,
}

#[derive(Clone, Debug, Default)]
struct TextField {
    value: String,
    cursor: usize,
}

impl TextField {
    fn new(value: String) -> Self {
        let cursor = value.len();
        Self { value, cursor }
    }
    fn insert(&mut self, character: char) {
        self.value.insert(self.cursor, character);
        self.cursor += character.len_utf8();
    }
    fn backspace(&mut self) {
        if self.cursor > 0 {
            let start =
                self.value[..self.cursor].char_indices().next_back().map_or(0, |(index, _)| index);
            self.value.replace_range(start..self.cursor, "");
            self.cursor = start;
        }
    }
    fn home(&mut self) {
        self.cursor = 0;
    }
    fn end(&mut self) {
        self.cursor = self.value.len();
    }
    fn left(&mut self) {
        if self.cursor > 0 {
            self.cursor =
                self.value[..self.cursor].char_indices().next_back().map_or(0, |(index, _)| index);
        }
    }
    fn right(&mut self) {
        if self.cursor < self.value.len() {
            self.cursor += self.value[self.cursor..].chars().next().map_or(0, char::len_utf8);
        }
    }
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
    commands_return_mode: Option<Mode>,
    message: String,
    editor_error: Option<String>,
    config: Config,
    config_path: PathBuf,
    renderer: Renderer,
    locale: Locale,
}

impl App {
    pub fn new(home: PathBuf, config: Config, config_path: PathBuf) -> io::Result<Self> {
        let locale = config.language().and_then(Locale::from_tag).unwrap_or(Locale::EsEs);
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
            commands_return_mode: None,
            message: String::new(),
            editor_error: None,
            config,
            config_path,
            renderer: Renderer::new(),
            locale,
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
        if matches!(key, Key::F2) {
            self.toggle_language()?;
            return Ok(None);
        }
        if matches!(key, Key::F3)
            && !matches!(self.mode, Mode::CommandEditor { .. } | Mode::ConfirmDelete { .. })
        {
            if matches!(self.mode, Mode::Commands { .. }) {
                self.close_commands();
            } else {
                self.begin_commands();
            }
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
                            self.message = if matches!(self.locale, Locale::EsEs) {
                                format!("La ruta no existe: {}", path.display())
                            } else {
                                format!("Path does not exist: {}", path.display())
                            };
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
                        self.message = if matches!(self.locale, Locale::EsEs) {
                            "Alias guardado"
                        } else {
                            "Alias saved"
                        }
                        .into();
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
                        self.message = if matches!(self.locale, Locale::EsEs) {
                            format!("Ruta de inicio guardada: {}", target.display())
                        } else {
                            format!("Startup folder saved: {}", target.display())
                        };
                    }
                    Key::Escape | Key::Char('q') => {
                        self.mode = Mode::Normal;
                        self.message = if matches!(self.locale, Locale::EsEs) {
                            "Cambio de ruta cancelado"
                        } else {
                            "Startup folder change cancelled"
                        }
                        .into();
                    }
                    _ => {}
                }
                Ok(None)
            }
            Mode::Commands { selected } => self.handle_commands(key, *selected),
            Mode::CommandEditor { slot, field, alias, command } => {
                self.handle_command_editor(key, *slot, *field, alias.clone(), command.clone())
            }
            Mode::ConfirmDelete { slot } => self.handle_delete_confirmation(key, *slot),
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
                self.message = if matches!(self.locale, Locale::EsEs) {
                    "Directorio actualizado"
                } else {
                    "Directory refreshed"
                }
                .into();
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

    fn begin_commands(&mut self) {
        let previous = std::mem::replace(&mut self.mode, Mode::Commands { selected: 0 });
        self.commands_return_mode = Some(previous);
    }

    fn close_commands(&mut self) {
        self.mode = self.commands_return_mode.take().unwrap_or(Mode::Normal);
    }

    fn handle_commands(
        &mut self,
        key: Key,
        selected: usize,
    ) -> io::Result<Option<Option<ShellResult>>> {
        let mut index = selected;
        match key {
            Key::Escape => self.close_commands(),
            Key::Up => index = index.saturating_sub(1),
            Key::Down => index = (index + 1).min(8),
            Key::Enter => {
                let slot = (index + 1) as u8;
                let (alias, command) =
                    self.config.shortcut(slot).map_or((String::new(), String::new()), |shortcut| {
                        (shortcut.alias.clone().unwrap_or_default(), shortcut.command.clone())
                    });
                self.mode = Mode::CommandEditor {
                    slot,
                    field: EditorField::Alias,
                    alias: TextField::new(alias),
                    command: TextField::new(command),
                };
                self.editor_error = None;
            }
            Key::Delete => {
                let slot = (index + 1) as u8;
                if self.config.shortcut(slot).is_some() {
                    self.mode = Mode::ConfirmDelete { slot };
                }
            }
            _ => {}
        }
        if let Mode::Commands { selected: current } = &mut self.mode {
            *current = index;
        }
        Ok(None)
    }

    fn handle_command_editor(
        &mut self,
        key: Key,
        slot: u8,
        field: EditorField,
        mut alias: TextField,
        mut command: TextField,
    ) -> io::Result<Option<Option<ShellResult>>> {
        let mut next_field = field;
        match key {
            Key::Escape => self.close_commands(),
            Key::Tab => {
                next_field = match field {
                    EditorField::Alias => EditorField::Command,
                    EditorField::Command => EditorField::Alias,
                };
            }
            Key::Enter if command.value.trim().is_empty() => {
                self.editor_error = Some(if matches!(self.locale, Locale::EsEs) {
                    "El comando no puede estar vacío".into()
                } else {
                    "Command cannot be empty".into()
                });
            }
            Key::Enter => {
                let mut next_config = self.config.clone();
                next_config.set_shortcut(slot, Some(alias.value.clone()), command.value.clone());
                next_config.save(&self.config_path)?;
                self.config = next_config;
                self.mode = Mode::Commands { selected: usize::from(slot - 1) };
                self.message = if matches!(self.locale, Locale::EsEs) {
                    "Comando guardado"
                } else {
                    "Command saved"
                }
                .into();
            }
            Key::Backspace => {
                self.editor_error = None;
                self.active_field(field, &mut alias, &mut command).backspace();
            }
            Key::Left => self.active_field(field, &mut alias, &mut command).left(),
            Key::Right => self.active_field(field, &mut alias, &mut command).right(),
            Key::Home => self.active_field(field, &mut alias, &mut command).home(),
            Key::End => self.active_field(field, &mut alias, &mut command).end(),
            Key::Char(character) if !character.is_control() => {
                self.editor_error = None;
                self.active_field(field, &mut alias, &mut command).insert(character)
            }
            _ => {}
        }
        if matches!(self.mode, Mode::CommandEditor { .. }) {
            self.mode = Mode::CommandEditor { slot, field: next_field, alias, command };
        }
        Ok(None)
    }

    fn active_field<'a>(
        &self,
        field: EditorField,
        alias: &'a mut TextField,
        command: &'a mut TextField,
    ) -> &'a mut TextField {
        match field {
            EditorField::Alias => alias,
            EditorField::Command => command,
        }
    }

    fn handle_delete_confirmation(
        &mut self,
        key: Key,
        slot: u8,
    ) -> io::Result<Option<Option<ShellResult>>> {
        match key {
            Key::Escape => self.mode = Mode::Commands { selected: usize::from(slot - 1) },
            Key::Enter => {
                let mut next_config = self.config.clone();
                next_config.clear_shortcut(slot);
                next_config.save(&self.config_path)?;
                self.config = next_config;
                self.mode = Mode::Commands { selected: usize::from(slot - 1) };
                self.message = if matches!(self.locale, Locale::EsEs) {
                    "Comando eliminado"
                } else {
                    "Command deleted"
                }
                .into();
            }
            _ => {}
        }
        Ok(None)
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
            self.message = if matches!(self.locale, Locale::EsEs) {
                if enabled { "Añadido a favoritos" } else { "Eliminado de favoritos" }
            } else if enabled {
                "Added to favorites"
            } else {
                "Removed from favorites"
            }
            .into();
        }
        Ok(())
    }

    fn toggle_favorites_visibility(&mut self) -> io::Result<()> {
        let visible = self.config.toggle_favorites_visibility();
        self.config.save(&self.config_path)?;
        self.selected = 0;
        self.scroll = 0;
        self.refresh()?;
        self.message = if matches!(self.locale, Locale::EsEs) {
            if visible { "Favoritos globales visibles" } else { "Favoritos globales ocultos" }
        } else if visible {
            "Global favorites visible"
        } else {
            "Global favorites hidden"
        }
        .into();
        Ok(())
    }

    fn toggle_update_checks(&mut self) -> io::Result<()> {
        let enabled = self.config.toggle_update_checks();
        self.config.save(&self.config_path)?;
        self.message = if matches!(self.locale, Locale::EsEs) {
            if enabled {
                "Comprobación de actualizaciones al iniciar: activada"
            } else {
                "Comprobación de actualizaciones al iniciar: desactivada"
            }
        } else if enabled {
            "Startup update checks: enabled"
        } else {
            "Startup update checks: disabled"
        }
        .into();
        Ok(())
    }

    fn toggle_language(&mut self) -> io::Result<()> {
        self.locale = self.locale.other();
        self.config.set_language(self.locale.tag());
        self.config.save(&self.config_path)?;
        self.message = match self.locale {
            Locale::EsEs => "Idioma: Español",
            Locale::EnUs => "Language: English",
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
            match self.locale {
                Locale::EsEs => "★  FAVORITOS VISIBLES · ALIAS / DIRECTORIO",
                Locale::EnUs => "★  FAVORITES VISIBLE · ALIAS / DIRECTORY",
            }
        } else {
            match self.locale {
                Locale::EsEs => "☆  FAVORITOS OCULTOS · Mayús+F para mostrar",
                Locale::EnUs => "☆  FAVORITES HIDDEN · Shift+F to show",
            }
        };
        rows.push(format!(
            "\x1b[38;2;90;100;120m│\x1b[0m {} \x1b[38;2;90;100;120m│\x1b[0m",
            fit(list_header, inner)
        ));
        rows.push(format!("\x1b[38;2;90;100;120m├{}┤\x1b[0m", "─".repeat(width.saturating_sub(2))));

        let lines = help_lines_for(&self.config, self.locale);
        let help_layout = matches!(self.mode, Mode::Help).then(|| {
            HelpLayout::new(inner, list_height, &mut self.help_scroll, lines.clone(), self.locale)
        });
        for row_index in 0..list_height {
            let content = if let Some(layout) = &help_layout {
                layout.render_row(row_index, inner)
            } else if matches!(
                self.mode,
                Mode::Commands { .. } | Mode::CommandEditor { .. } | Mode::ConfirmDelete { .. }
            ) {
                self.command_panel_row(row_index, list_height, inner)
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
                    if matches!(self.locale, Locale::EsEs) {
                        format!("{} carpetas", self.visible.len())
                    } else {
                        format!("{} folders", self.visible.len())
                    }
                } else {
                    self.message.clone()
                }
            }
            Mode::Help => {
                if matches!(self.locale, Locale::EsEs) {
                    format!(
                        "Atajos · {} acciones disponibles",
                        lines
                            .iter()
                            .filter(|line| matches!(line, HelpLine::Shortcut(_, _)))
                            .count()
                    )
                } else {
                    format!(
                        "Shortcuts · {} actions available",
                        lines
                            .iter()
                            .filter(|line| matches!(line, HelpLine::Shortcut(_, _)))
                            .count()
                    )
                }
            }
            Mode::Filter => format!("/{}", self.input),
            Mode::Path => {
                if matches!(self.locale, Locale::EsEs) {
                    format!("ruta › {}_", self.input)
                } else {
                    format!("path › {}_", self.input)
                }
            }
            Mode::Alias { .. } => format!("alias › {}_", self.input),
            Mode::Command { .. } => {
                if matches!(self.locale, Locale::EsEs) {
                    format!("comando › {}_", self.input)
                } else {
                    format!("command › {}_", self.input)
                }
            }
            Mode::ConfirmRoot { ref target } => {
                if matches!(self.locale, Locale::EsEs) {
                    format!("¿Guardar como inicio?  {}", target.display())
                } else {
                    format!("Save as startup folder?  {}", target.display())
                }
            }
            Mode::Commands { .. } => match self.locale {
                Locale::EsEs => "↑↓ Mover · Enter Añadir/Editar · Supr Eliminar · Esc Cerrar",
                Locale::EnUs => "↑↓ Move · Enter Add/Edit · Delete Remove · Esc Close",
            }
            .into(),
            Mode::CommandEditor { field, .. } => match (self.locale, field) {
                (Locale::EsEs, EditorField::Alias) => {
                    "Tab Cambiar campo · Enter Guardar · Esc Cancelar · Alias".into()
                }
                (Locale::EsEs, EditorField::Command) => {
                    "Tab Cambiar campo · Enter Guardar · Esc Cancelar · Comando".into()
                }
                (Locale::EnUs, EditorField::Alias) => {
                    "Tab Switch field · Enter Save · Esc Cancel · Alias".into()
                }
                (Locale::EnUs, EditorField::Command) => {
                    "Tab Switch field · Enter Save · Esc Cancel · Command".into()
                }
            },
            Mode::ConfirmDelete { .. } => match self.locale {
                Locale::EsEs => "Enter Confirmar · Esc Cancelar",
                Locale::EnUs => "Enter Confirm · Esc Cancel",
            }
            .into(),
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

    fn command_panel_row(&self, row: usize, list_height: usize, width: usize) -> String {
        let line = match &self.mode {
            Mode::Commands { selected } => {
                if row == 0 {
                    return fit(
                        if matches!(self.locale, Locale::EsEs) {
                            "╭─ COMANDOS PERSONALIZADOS ─────────────────────────────╮"
                        } else {
                            "╭─ CUSTOM COMMANDS ────────────────────────────────────╮"
                        },
                        width,
                    );
                }
                if row <= 9 {
                    let slot = row as u8;
                    let binding = format_binding(
                        KeyBinding::with_modifier(
                            Modifier::Shift,
                            KeyToken::Char(char::from(b'0' + slot)),
                        ),
                        self.locale,
                    );
                    let content = self.config.shortcut(slot).map_or_else(
                        || {
                            if matches!(self.locale, Locale::EsEs) {
                                "—  Vacío".to_owned()
                            } else {
                                "—  Empty".to_owned()
                            }
                        },
                        |shortcut| {
                            format!(
                                "{}  {}",
                                shortcut.alias.as_deref().unwrap_or("—"),
                                shortcut.command
                            )
                        },
                    );
                    let prefix = if usize::from(slot - 1) == *selected { "›" } else { " " };
                    return fit(&format!("{prefix} {binding:<8} {content}"), width);
                }
                if row == list_height.saturating_sub(1) {
                    return fit(
                        if matches!(self.locale, Locale::EsEs) {
                            "╰─ ↑↓ Mover · Enter Añadir/Editar · Supr Eliminar · Esc Cerrar ─╯"
                        } else {
                            "╰─ ↑↓ Move · Enter Add/Edit · Delete Remove · Esc Close ─╯"
                        },
                        width,
                    );
                }
                "".to_owned()
            }
            Mode::CommandEditor { slot, field, alias, command } => {
                let title = if matches!(self.locale, Locale::EsEs) {
                    format!(
                        "MAYÚS+{slot} · {}",
                        if command.value.is_empty() { "NUEVO COMANDO" } else { "EDITAR COMANDO" }
                    )
                } else {
                    format!(
                        "SHIFT+{slot} · {}",
                        if command.value.is_empty() { "NEW COMMAND" } else { "EDIT COMMAND" }
                    )
                };
                match row {
                    0 => format!("╭─ {title} ─────────────────────────────────────────╮"),
                    2 => format!(
                        "  {}: {}",
                        if matches!(self.locale, Locale::EsEs) {
                            "Alias (opcional)"
                        } else {
                            "Alias (optional)"
                        },
                        cursor_text(alias, *field == EditorField::Alias)
                    ),
                    4 => format!(
                        "  {}: {}",
                        if matches!(self.locale, Locale::EsEs) { "Comando" } else { "Command" },
                        cursor_text(command, *field == EditorField::Command)
                    ),
                    5 => self.editor_error.clone().unwrap_or_default(),
                    6 => format!(
                        "╰─ Tab {} · Enter {} · Esc {} ─╯",
                        if matches!(self.locale, Locale::EsEs) {
                            "Cambiar campo"
                        } else {
                            "Switch field"
                        },
                        if matches!(self.locale, Locale::EsEs) { "Guardar" } else { "Save" },
                        if matches!(self.locale, Locale::EsEs) { "Cancelar" } else { "Cancel" }
                    ),
                    _ => String::new(),
                }
            }
            Mode::ConfirmDelete { slot } => {
                let detail = self
                    .config
                    .shortcut(*slot)
                    .map(|s| format!("{}: {}", s.alias.as_deref().unwrap_or("—"), s.command))
                    .unwrap_or_default();
                match row {
                    2 => {
                        if matches!(self.locale, Locale::EsEs) {
                            format!("¿Eliminar Mayús+{slot}? {detail}")
                        } else {
                            format!("Remove Shift+{slot}? {detail}")
                        }
                    }
                    _ => String::new(),
                }
            }
            _ => String::new(),
        };
        fit(&line, width)
    }

    /// Normal-mode footer with the configured shortcut aliases appended so the
    /// bound slots are visible at a glance; other modes reuse the static copy.
    fn footer_line(&self) -> String {
        let Mode::Normal = &self.mode else {
            return footer_help_for(&self.mode, self.locale).to_string();
        };
        let mut footer = footer_help_for(&Mode::Normal, self.locale).to_string();
        let shortcuts = self.config.configured_shortcuts();
        if shortcuts.is_empty() {
            return footer;
        }
        footer.push_str("  ");
        for (slot, shortcut) in shortcuts {
            use std::fmt::Write as _;
            let binding = format_binding(
                KeyBinding::with_modifier(Modifier::Shift, KeyToken::Char(char::from(b'0' + slot))),
                self.locale,
            );
            let _ = write!(footer, "{binding}");
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

#[allow(dead_code)]
fn help_lines(config: &Config) -> Vec<HelpLine> {
    help_lines_for(config, Locale::EsEs)
}

fn help_lines_for(config: &Config, locale: Locale) -> Vec<HelpLine> {
    let es = matches!(locale, Locale::EsEs);
    let shift = |key: char| {
        format_binding(KeyBinding::with_modifier(Modifier::Shift, KeyToken::Char(key)), locale)
    };
    let text = |es_text: &'static str, en_text: &'static str| if es { es_text } else { en_text };
    let mut lines: Vec<HelpLine> = vec![
        HelpLine::Section(text("NAVEGACIÓN", "NAVIGATION").into()),
        HelpLine::Shortcut(
            "↑ / ↓ · j / k".into(),
            text("Navegar por las carpetas", "Navigate folders").into(),
        ),
        HelpLine::Shortcut(
            "→ / l".into(),
            text("Entrar en la carpeta resaltada", "Open highlighted folder").into(),
        ),
        HelpLine::Shortcut(
            format!("← / h / {}", format_binding(KeyBinding::plain(KeyToken::Backspace), locale)),
            text("Volver a la carpeta padre", "Go to parent folder").into(),
        ),
        HelpLine::Shortcut(
            format_binding(KeyBinding::plain(KeyToken::Enter), locale),
            text(
                "Seleccionar carpeta y volver a PowerShell",
                "Select folder and return to PowerShell",
            )
            .into(),
        ),
        HelpLine::Shortcut(
            ".".into(),
            text("Seleccionar la carpeta mostrada", "Select the current folder").into(),
        ),
        HelpLine::Shortcut(
            "g".into(),
            text("Volver a la ruta de inicio", "Return to startup folder").into(),
        ),
        HelpLine::Shortcut(
            "p".into(),
            text("Abrir cualquier ruta o unidad", "Open any path or drive").into(),
        ),
        HelpLine::Shortcut(
            format_binding(KeyBinding::with_modifier(Modifier::Ctrl, KeyToken::Char('S')), locale),
            text(
                "Guardar la carpeta resaltada como inicio",
                "Save highlighted folder as startup folder",
            )
            .into(),
        ),
        HelpLine::Blank,
        HelpLine::Section(text("BÚSQUEDA Y ORGANIZACIÓN", "SEARCH AND ORGANIZATION").into()),
        HelpLine::Shortcut(
            "/".into(),
            text("Filtrar carpetas mientras escribes", "Filter folders as you type").into(),
        ),
        HelpLine::Shortcut(
            "f".into(),
            text("Añadir o quitar un favorito global", "Add or remove a global favorite").into(),
        ),
        HelpLine::Shortcut(
            shift('F'),
            text("Mostrar u ocultar los favoritos globales", "Show or hide global favorites")
                .into(),
        ),
        HelpLine::Shortcut(
            "a".into(),
            text("Crear o editar el alias de la carpeta", "Create or edit the folder alias").into(),
        ),
        HelpLine::Shortcut(
            "u".into(),
            text("Actualizar el directorio actual", "Refresh the current directory").into(),
        ),
        HelpLine::Shortcut(
            format_binding(KeyBinding::with_modifier(Modifier::Ctrl, KeyToken::Char('U')), locale),
            text(
                "Activar o desactivar comprobación al iniciar",
                "Enable or disable startup checks",
            )
            .into(),
        ),
        HelpLine::Shortcut(
            shift('U'),
            text("Actualizar DevNav a la última versión", "Update DevNav to the latest version")
                .into(),
        ),
        HelpLine::Blank,
        HelpLine::Section(text("AGENTES EN EL REPOSITORIO", "AGENTS IN REPOSITORY").into()),
        HelpLine::Shortcut("c".into(), text("Codex: sesión nueva", "Codex: new session").into()),
        HelpLine::Shortcut(
            "r".into(),
            text("Codex: última sesión del repositorio", "Codex: resume last session").into(),
        ),
        HelpLine::Shortcut(
            format!("d / {}", shift('D')),
            text("Claude Code: sesión nueva / última sesión", "Claude Code: new / last session")
                .into(),
        ),
        HelpLine::Shortcut(
            format!("o / {}", shift('O')),
            text("OpenCode: sesión nueva / última sesión", "OpenCode: new / last session").into(),
        ),
        HelpLine::Shortcut(
            format!("i / {}", shift('I')),
            text("Kimi: sesión nueva / última sesión", "Kimi: new / last session").into(),
        ),
        HelpLine::Blank,
        HelpLine::Section(text("ACCIONES", "ACTIONS").into()),
        HelpLine::Shortcut(
            "e / :".into(),
            text(
                "Ejecutar un comando en la carpeta resaltada",
                "Run a command in the highlighted folder",
            )
            .into(),
        ),
        HelpLine::Shortcut(
            format!("{} … {}", shift('1'), shift('9')),
            text("Ejecutar un comando personalizado", "Run a configured custom command").into(),
        ),
        HelpLine::Shortcut(
            "F1".into(),
            text("Abrir o cerrar este panel de ayuda", "Open or close this help").into(),
        ),
        HelpLine::Shortcut("F2".into(), text("Cambiar idioma", "Change language").into()),
        HelpLine::Shortcut(
            "q / Esc".into(),
            text("Salir de DevNav o cancelar", "Quit DevNav or cancel").into(),
        ),
    ];
    // Dynamic section: only configured slots appear, so the panel never lists
    // nine empty entries.
    let shortcuts = config.configured_shortcuts();
    if !shortcuts.is_empty() {
        lines.push(HelpLine::Blank);
        lines.push(HelpLine::Section(text("ATAJOS PERSONALIZADOS", "CUSTOM COMMANDS").into()));
        for (slot, shortcut) in shortcuts {
            let description = match shortcut.alias.as_deref().filter(|alias| !alias.is_empty()) {
                Some(alias) => format!("{alias} → {}", shortcut.command),
                None => shortcut.command.clone(),
            };
            lines.push(HelpLine::Shortcut(shift(char::from(b'0' + slot)), description));
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
    locale: Locale,
}

impl HelpLayout {
    fn new(
        inner: usize,
        list_height: usize,
        scroll: &mut usize,
        lines: Vec<HelpLine>,
        locale: Locale,
    ) -> Self {
        let width = inner.min(104);
        let height = list_height.min(lines.len().saturating_add(2));
        let capacity = height.saturating_sub(2);
        let max_scroll = lines.len().saturating_sub(capacity);
        *scroll = (*scroll).min(max_scroll);
        Self {
            width,
            height,
            top: list_height.saturating_sub(height) / 2,
            start: *scroll,
            lines,
            locale,
        }
    }

    fn render_row(&self, row: usize, outer_width: usize) -> String {
        if row < self.top || row >= self.top + self.height || self.height < 2 {
            return " ".repeat(outer_width);
        }
        let local = row - self.top;
        let panel = if local == 0 {
            panel_border(
                self.width,
                if matches!(self.locale, Locale::EsEs) {
                    "ATAJOS DE TECLADO"
                } else {
                    "KEYBOARD SHORTCUTS"
                },
                true,
            )
        } else if local + 1 == self.height {
            panel_border(
                self.width,
                match self.locale {
                    Locale::EsEs => "↑↓ DESPLAZAR · F1 / ESC CERRAR",
                    Locale::EnUs => "↑↓ SCROLL · F1 / ESC CLOSE",
                },
                false,
            )
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

fn cursor_text(field: &TextField, active: bool) -> String {
    if !active {
        return field.value.clone();
    }
    let (left, right) = field.value.split_at(field.cursor);
    format!("{left}_{right}")
}

#[allow(dead_code)]
fn footer_help(mode: &Mode) -> &'static str {
    footer_help_for(mode, Locale::EsEs)
}

fn footer_help_for(mode: &Mode, locale: Locale) -> &'static str {
    if matches!(locale, Locale::EnUs) {
        return match mode {
            Mode::Normal => {
                "↑↓ Navigate  Enter Select  → Open  Ctrl+S Home  F1 Help  F2 Language  F3 Commands  q Quit"
            }
            Mode::Help => "↑↓ Scroll  F1 / Esc Close help",
            Mode::Filter => "Type to filter  ↑↓ Navigate  Enter Apply  Esc Cancel",
            Mode::Path => "Type a path  Enter Open  Esc Cancel",
            Mode::Alias { .. } => "Type an alias  Enter Save  Esc Cancel",
            Mode::Command { .. } => "Type a command  Enter Run  Esc Cancel",
            Mode::ConfirmRoot { .. } => "Enter Confirm startup folder  Esc Cancel",
            Mode::Commands { .. } | Mode::CommandEditor { .. } | Mode::ConfirmDelete { .. } => {
                "F3 Commands  Enter Confirm  Esc Cancel"
            }
        };
    }
    match mode {
        Mode::Normal => {
            "↑↓ Navegar  Enter Seleccionar  → Abrir  Ctrl+S Inicio  F1 Ayuda  F2 Idioma  F3 Comandos  q Salir"
        }
        Mode::Help => "↑↓ Desplazar  F1 / Esc Cerrar ayuda",
        Mode::Filter => "Escribe para buscar  ↑↓ Navegar  Enter Aplicar  Esc Cancelar",
        Mode::Path => "Escribe una ruta  Enter Abrir  Esc Cancelar",
        Mode::Alias { .. } => "Escribe un alias  Enter Guardar  Esc Cancelar",
        Mode::Command { .. } => "Escribe un comando  Enter Ejecutar  Esc Cancelar",
        Mode::ConfirmRoot { .. } => "Enter Confirmar nueva ruta de inicio  Esc Cancelar",
        Mode::Commands { .. } | Mode::CommandEditor { .. } | Mode::ConfirmDelete { .. } => {
            "F3 Comandos  Enter Confirmar  Esc Cancelar"
        }
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

        assert!(footer.contains("Ctrl+S Inicio"));
        assert!(footer.contains("F1 Ayuda"));
        assert!(footer.contains("Enter Seleccionar"));
        assert!(footer.chars().count() < 115);
    }

    #[test]
    fn f2_toggles_language_persists_and_keeps_help_open() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let sandbox = std::env::temp_dir().join(format!("devnav-language-app-{unique}"));
        fs::create_dir_all(&sandbox).expect("create sandbox");
        let config_path = sandbox.join("config.tsv");
        let mut config = Config::default();
        config.set_language("es-ES");
        let mut app = App::new(sandbox.clone(), config, config_path.clone()).expect("create app");
        app.handle_key(Key::F1).expect("open help");
        assert!(matches!(app.mode, Mode::Help));
        app.handle_key(Key::F2).expect("toggle language");
        assert!(matches!(app.mode, Mode::Help));
        assert_eq!(app.locale, crate::i18n::Locale::EnUs);
        assert_eq!(Config::load(&config_path).expect("load").language(), Some("en-US"));
        fs::remove_dir_all(sandbox).expect("clean sandbox");
    }

    #[test]
    fn f3_opens_a_manager_without_executing_shortcuts() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let sandbox = std::env::temp_dir().join(format!("devnav-commands-{unique}"));
        fs::create_dir_all(&sandbox).expect("create sandbox");
        let config_path = sandbox.join("config.tsv");
        let config = Config::default();
        let mut app = App::new(sandbox.clone(), config, config_path).expect("create app");
        app.handle_key(Key::F3).expect("open manager");
        assert!(matches!(app.mode, Mode::Commands { selected: 0 }));
        app.handle_key(Key::Shortcut(1)).expect("ignore slot in manager");
        assert!(matches!(app.mode, Mode::Commands { selected: 0 }));
        fs::remove_dir_all(sandbox).expect("clean sandbox");
    }

    #[test]
    fn command_editor_save_and_delete_round_trip_through_config() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let sandbox = std::env::temp_dir().join(format!("devnav-command-edit-{unique}"));
        fs::create_dir_all(&sandbox).expect("create sandbox");
        let config_path = sandbox.join("config.tsv");
        let mut app =
            App::new(sandbox.clone(), Config::default(), config_path.clone()).expect("create app");
        app.handle_key(Key::F3).expect("open manager");
        app.handle_key(Key::Enter).expect("edit slot");
        for character in "Dev".chars() {
            app.handle_key(Key::Char(character)).expect("type alias");
        }
        app.handle_key(Key::Tab).expect("switch field");
        for character in "bun run dev".chars() {
            app.handle_key(Key::Char(character)).expect("type command");
        }
        app.handle_key(Key::Enter).expect("save command");
        assert_eq!(app.config.shortcut(1).map(|s| s.command.as_str()), Some("bun run dev"));
        app.handle_key(Key::Delete).expect("confirm delete");
        assert!(matches!(app.mode, Mode::ConfirmDelete { slot: 1 }));
        app.handle_key(Key::Enter).expect("delete command");
        assert!(app.config.shortcut(1).is_none());
        assert!(Config::load(&config_path).expect("reload").shortcut(1).is_none());
        fs::remove_dir_all(sandbox).expect("clean sandbox");
    }

    #[test]
    fn empty_command_is_rejected_with_inline_feedback() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let sandbox = std::env::temp_dir().join(format!("devnav-command-error-{unique}"));
        fs::create_dir_all(&sandbox).expect("create sandbox");
        let mut app = App::new(sandbox.clone(), Config::default(), sandbox.join("config.tsv"))
            .expect("create app");
        app.handle_key(Key::F3).expect("open manager");
        app.handle_key(Key::Enter).expect("open editor");
        app.handle_key(Key::Enter).expect("reject empty command");
        assert!(app.editor_error.is_some());
        assert!(matches!(app.mode, Mode::CommandEditor { .. }));
        fs::remove_dir_all(sandbox).expect("clean sandbox");
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
                super::HelpLine::Shortcut(key, description) if key.starts_with("Mayús+") => {
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

        assert!(footer.contains("Mayús+1 Dev"));
        assert!(footer.contains("Mayús+2"));
        // Unconfigured slots must not clutter the footer.
        assert!(!footer.contains("Mayús+3"));
        fs::remove_dir_all(sandbox).expect("clean test sandbox");
    }
}
