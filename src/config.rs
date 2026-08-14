use std::{
    collections::{HashMap, HashSet},
    env, fs, io,
    io::Write,
    path::{Path, PathBuf},
};

/// The lowest and highest configurable shortcut slot indexes.
pub const SHORTCUT_MIN: u8 = 1;
pub const SHORTCUT_MAX: u8 = 9;

/// A user-defined command bound to a Shift+digit slot.
///
/// `alias` is the optional visible label shown in the UI; `command` is the
/// shell command executed in the selected project directory by the
/// `PowerShell` wrapper. The command is never interpreted by `DevNav` during
/// configuration.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Shortcut {
    pub alias: Option<String>,
    pub command: String,
}

#[derive(Clone, Debug)]
pub struct Config {
    root: Option<PathBuf>,
    show_favorites: bool,
    check_updates: Option<bool>,
    language: Option<String>,
    favorites: HashSet<PathBuf>,
    aliases: HashMap<PathBuf, String>,
    shortcuts: HashMap<u8, Shortcut>,
}

impl Config {
    pub fn default_path() -> io::Result<PathBuf> {
        let base = env::var_os("LOCALAPPDATA").map(PathBuf::from).ok_or_else(|| {
            io::Error::new(io::ErrorKind::NotFound, "LOCALAPPDATA no está definido")
        })?;
        Ok(base.join("DevNav").join("config.tsv"))
    }

    pub fn load(path: &Path) -> io::Result<Self> {
        // A missing config is normal (first run) and yields defaults; any other
        // I/O failure (permissions, disk error) is real and must propagate
        // instead of being silently swallowed.
        let contents = match fs::read_to_string(path) {
            Ok(contents) => contents,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Self::default()),
            Err(error) => return Err(error),
        };
        Ok(Self::parse_tsv(&contents))
    }

    /// Parses the textual `config.tsv` representation without performing I/O.
    ///
    /// Unknown or malformed records are ignored for backwards compatibility,
    /// while valid records retain the same semantics as [`Config::load`].
    pub fn parse_tsv(contents: &str) -> Self {
        let mut config = Self::default();
        for line in contents.lines() {
            let mut fields = line.splitn(3, '\t');
            match (fields.next(), fields.next(), fields.next()) {
                (Some("root"), Some(path), _) => {
                    config.root = Some(PathBuf::from(decode(path)));
                }
                (Some("show_favorites"), Some(value), _) => {
                    config.show_favorites = value != "false";
                }
                (Some("check_updates"), Some(value), _) => {
                    config.check_updates = Some(value == "true");
                }
                (Some("language"), Some(value), _) => {
                    if value == "es-ES" || value == "en-US" {
                        config.language = Some(value.to_owned());
                    }
                }
                (Some("favorite"), Some(path), _) => {
                    config.favorites.insert(PathBuf::from(decode(path)));
                }
                (Some("alias"), Some(path), Some(alias)) => {
                    config.aliases.insert(PathBuf::from(decode(path)), decode(alias));
                }
                // Shortcut lines carry four logical fields:
                // `shortcut\t<index>\t<encoded alias>\t<encoded command>`.
                // splitn(3) keeps the alias/command pair together; we split it
                // again on the single literal tab, which is safe because the
                // encoded values never contain a raw tab.
                (Some("shortcut"), Some(index_text), Some(rest)) => {
                    if let Ok(index) = index_text.parse::<u8>()
                        && (SHORTCUT_MIN..=SHORTCUT_MAX).contains(&index)
                    {
                        let (alias_raw, command_raw) = rest.split_once('\t').unwrap_or((rest, ""));
                        let command = decode(command_raw);
                        if !command.trim().is_empty() {
                            let alias = decode(alias_raw);
                            let alias = if alias.trim().is_empty() { None } else { Some(alias) };
                            config.shortcuts.insert(
                                index,
                                Shortcut { alias, command: command.trim().to_owned() },
                            );
                        }
                    }
                }
                _ => {}
            }
        }
        config
    }

    pub fn save(&self, path: &Path) -> io::Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut favorites: Vec<_> = self.favorites.iter().collect();
        favorites.sort();
        let mut aliases: Vec<_> = self.aliases.iter().collect();
        aliases.sort_by(|left, right| left.0.cmp(right.0));

        let mut output = String::new();
        if let Some(root) = &self.root {
            output.push_str("root\t");
            output.push_str(&encode(&root.to_string_lossy()));
            output.push('\n');
        }
        output.push_str("show_favorites\t");
        output.push_str(if self.show_favorites { "true" } else { "false" });
        output.push('\n');
        if let Some(check_updates) = self.check_updates {
            output.push_str("check_updates\t");
            output.push_str(if check_updates { "true" } else { "false" });
            output.push('\n');
        }
        if let Some(language) = &self.language {
            output.push_str("language\t");
            output.push_str(language);
            output.push('\n');
        }
        for favorite in favorites {
            output.push_str("favorite\t");
            output.push_str(&encode(&favorite.to_string_lossy()));
            output.push('\n');
        }
        for (path, alias) in aliases {
            output.push_str("alias\t");
            output.push_str(&encode(&path.to_string_lossy()));
            output.push('\t');
            output.push_str(&encode(alias));
            output.push('\n');
        }
        for (index, shortcut) in self.configured_shortcuts() {
            output.push_str("shortcut\t");
            output.push_str(&index.to_string());
            output.push('\t');
            output.push_str(&encode(shortcut.alias.as_deref().unwrap_or_default()));
            output.push('\t');
            output.push_str(&encode(&shortcut.command));
            output.push('\n');
        }
        save_atomic(path, output.as_bytes())
    }

    pub fn is_favorite(&self, path: &Path) -> bool {
        self.favorites.contains(path)
    }

    pub fn root(&self) -> Option<&Path> {
        self.root.as_deref()
    }

    pub fn set_root(&mut self, path: PathBuf) {
        self.root = Some(path);
    }

    pub fn show_favorites(&self) -> bool {
        self.show_favorites
    }

    pub fn toggle_favorites_visibility(&mut self) -> bool {
        self.show_favorites = !self.show_favorites;
        self.show_favorites
    }

    #[cfg(test)]
    pub fn check_updates(&self) -> Option<bool> {
        self.check_updates
    }

    pub fn toggle_update_checks(&mut self) -> bool {
        let enabled = !self.check_updates.unwrap_or(true);
        self.check_updates = Some(enabled);
        enabled
    }

    pub fn language(&self) -> Option<&str> {
        self.language.as_deref()
    }

    pub fn set_language(&mut self, language: &str) {
        if language == "es-ES" || language == "en-US" {
            self.language = Some(language.to_owned());
        }
    }

    pub fn favorite_paths(&self) -> impl Iterator<Item = &Path> {
        self.favorites.iter().map(PathBuf::as_path)
    }

    pub fn toggle_favorite(&mut self, path: &Path) -> bool {
        if self.favorites.remove(path) {
            false
        } else {
            self.favorites.insert(path.to_path_buf());
            true
        }
    }

    pub fn alias(&self, path: &Path) -> Option<&str> {
        self.aliases.get(path).map(String::as_str)
    }

    pub fn set_alias(&mut self, path: PathBuf, alias: String) {
        if alias.trim().is_empty() {
            self.aliases.remove(&path);
        } else {
            self.aliases.insert(path, alias.trim().to_owned());
        }
    }

    /// Returns the shortcut bound to `index` (1..=9), or `None` if the slot is
    /// empty or the index is out of range.
    pub fn shortcut(&self, index: u8) -> Option<&Shortcut> {
        if (SHORTCUT_MIN..=SHORTCUT_MAX).contains(&index) {
            self.shortcuts.get(&index)
        } else {
            None
        }
    }

    /// Binds a command (and optional alias) to `index`. Returns `false` and
    /// changes nothing when `index` is outside 1..=9. An empty command clears
    /// the slot instead of storing an empty entry.
    pub fn set_shortcut(&mut self, index: u8, alias: Option<String>, command: String) -> bool {
        if !(SHORTCUT_MIN..=SHORTCUT_MAX).contains(&index) {
            return false;
        }
        let command = command.trim().to_owned();
        if command.is_empty() {
            self.shortcuts.remove(&index);
        } else {
            let alias = alias.map(|a| a.trim().to_owned()).filter(|a| !a.is_empty());
            self.shortcuts.insert(index, Shortcut { alias, command });
        }
        true
    }

    /// Removes the shortcut bound to `index`. Returns `false` for out-of-range
    /// indexes.
    pub fn clear_shortcut(&mut self, index: u8) -> bool {
        if !(SHORTCUT_MIN..=SHORTCUT_MAX).contains(&index) {
            return false;
        }
        self.shortcuts.remove(&index);
        true
    }

    /// Configured shortcuts ordered by slot index, for stable UI rendering.
    pub fn configured_shortcuts(&self) -> Vec<(u8, &Shortcut)> {
        let mut slots: Vec<_> = self.shortcuts.iter().map(|(index, slot)| (*index, slot)).collect();
        slots.sort_by_key(|(index, _)| *index);
        slots
    }
}

/// Writes a complete payload and replaces the old configuration atomically.
fn save_atomic(path: &Path, payload: &[u8]) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let temp = path.with_extension(format!("tmp-{}", std::process::id()));
    let write_result = (|| -> io::Result<()> {
        let mut file = fs::File::create(&temp)?;
        file.write_all(payload)?;
        file.sync_all()?;
        Ok(())
    })();
    if let Err(error) = write_result {
        let _ = fs::remove_file(&temp);
        return Err(error);
    }
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        use windows_sys::Win32::Storage::FileSystem::ReplaceFileW;
        if !path.exists() {
            let result = fs::rename(&temp, path);
            if result.is_err() {
                let _ = fs::remove_file(&temp);
            }
            return result;
        }
        let replaced: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
        let replacement: Vec<u16> = temp.as_os_str().encode_wide().chain(Some(0)).collect();
        let result = unsafe {
            ReplaceFileW(
                replaced.as_ptr(),
                replacement.as_ptr(),
                std::ptr::null(),
                0,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            )
        };
        if result == 0 {
            let error = io::Error::last_os_error();
            let _ = fs::remove_file(&temp);
            return Err(error);
        }
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let result = fs::rename(&temp, path);
        if result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        result
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            root: None,
            show_favorites: true,
            check_updates: None,
            language: None,
            favorites: HashSet::new(),
            aliases: HashMap::new(),
            shortcuts: HashMap::new(),
        }
    }
}

fn encode(value: &str) -> String {
    value.replace('%', "%25").replace('\t', "%09").replace('\n', "%0A")
}

fn decode(value: &str) -> String {
    value.replace("%0A", "\n").replace("%09", "\t").replace("%25", "%")
}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::{Config, decode, encode};

    #[test]
    fn encoding_round_trip() {
        let input = "C:\\code\t100%\nnext";
        assert_eq!(decode(&encode(input)), input);
    }

    #[test]
    fn parser_ignores_malformed_records_without_losing_valid_shortcuts() {
        let config = Config::parse_tsv(
            "shortcut\t0\tignored\tnope\nshortcut\t2\tTests\tcargo test\ninvalid\n",
        );

        assert!(config.shortcut(0).is_none());
        assert_eq!(config.shortcut(2).map(|slot| slot.alias.as_deref()), Some(Some("Tests")));
        assert_eq!(config.shortcut(2).map(|slot| slot.command.as_str()), Some("cargo test"));
    }

    #[test]
    fn startup_root_is_persisted_with_the_rest_of_the_config() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let config_path = std::env::temp_dir().join(format!("devnav-config-{unique}.tsv"));
        let root = std::env::temp_dir().join("repositorios");
        let mut config = Config::default();
        config.set_root(root.clone());

        config.save(&config_path).expect("save config");
        let loaded = Config::load(&config_path).expect("load");

        assert_eq!(loaded.root(), Some(root.as_path()));
        fs::remove_file(config_path).expect("remove config");
    }

    #[test]
    fn favorites_are_visible_by_default_and_the_preference_persists() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let config_path = std::env::temp_dir().join(format!("devnav-visibility-{unique}.tsv"));
        let mut config = Config::default();
        assert!(config.show_favorites());

        assert!(!config.toggle_favorites_visibility());
        config.save(&config_path).expect("save config");

        assert!(!Config::load(&config_path).expect("load").show_favorites());
        fs::remove_file(config_path).expect("remove config");
    }

    #[test]
    fn update_check_consent_is_unset_until_answered_and_then_persists() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let config_path = std::env::temp_dir().join(format!("devnav-consent-{unique}.tsv"));
        let mut config = Config::default();
        assert_eq!(config.check_updates(), None);

        assert!(!config.toggle_update_checks());
        config.save(&config_path).expect("save config");

        assert_eq!(Config::load(&config_path).expect("load").check_updates(), Some(false));
        fs::remove_file(config_path).expect("remove config");
    }

    #[test]
    fn language_round_trip_and_legacy_config_compatibility() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let config_path = std::env::temp_dir().join(format!("devnav-language-{unique}.tsv"));
        let mut config = Config::default();
        assert_eq!(config.language(), None);
        config.set_language("es-ES");
        config.save(&config_path).expect("save language");
        assert_eq!(Config::load(&config_path).expect("load").language(), Some("es-ES"));
        fs::write(&config_path, "show_favorites\ttrue\nlanguage\tfr-FR\n").expect("write legacy");
        assert_eq!(Config::load(&config_path).expect("load legacy").language(), None);
        fs::remove_file(config_path).expect("remove config");
    }

    fn empty_shortcut_config_is_blank() {
        let config = Config::default();
        for index in super::SHORTCUT_MIN..=super::SHORTCUT_MAX {
            assert!(config.shortcut(index).is_none());
        }
    }

    #[test]
    fn shortcut_slots_round_trip_across_the_full_range() {
        empty_shortcut_config_is_blank();
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let config_path = std::env::temp_dir().join(format!("devnav-shortcut-range-{unique}.tsv"));
        let mut config = Config::default();
        for index in super::SHORTCUT_MIN..=super::SHORTCUT_MAX {
            assert!(config.set_shortcut(
                index,
                Some(format!("alias{index}")),
                format!("cmd {index}")
            ));
        }
        config.save(&config_path).expect("save shortcuts");

        let loaded = Config::load(&config_path).expect("load");
        for index in super::SHORTCUT_MIN..=super::SHORTCUT_MAX {
            let slot = loaded.shortcut(index).expect("slot configured");
            assert_eq!(slot.alias.as_deref(), Some(format!("alias{index}").as_str()));
            assert_eq!(slot.command, format!("cmd {index}"));
        }
        fs::remove_file(config_path).expect("remove config");
    }

    #[test]
    fn shortcut_without_alias_is_stored_and_persists() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let config_path =
            std::env::temp_dir().join(format!("devnav-shortcut-noalias-{unique}.tsv"));
        let mut config = Config::default();
        assert!(config.set_shortcut(2, None, "cargo test".into()));
        assert!(config.shortcut(2).is_some());
        config.save(&config_path).expect("save");

        let loaded = Config::load(&config_path).expect("load");
        let slot = loaded.shortcut(2).expect("slot present");
        assert_eq!(slot.alias, None);
        assert_eq!(slot.command, "cargo test");
        fs::remove_file(config_path).expect("remove config");
    }

    #[test]
    fn empty_slot_is_not_stored_and_does_not_execute() {
        let mut config = Config::default();
        // A valid index with an empty command is accepted (it clears the slot)
        // but never stores a runnable binding.
        assert!(config.set_shortcut(3, Some("Alias".into()), "   ".into()));
        assert!(config.shortcut(3).is_none());
        assert!(config.configured_shortcuts().is_empty());
    }

    #[test]
    fn shortcut_overwrite_replaces_the_previous_binding() {
        let mut config = Config::default();
        assert!(config.set_shortcut(1, Some("Old".into()), "npm run old".into()));
        assert!(config.set_shortcut(1, Some("New".into()), "bun run dev".into()));

        let slot = config.shortcut(1).expect("overwritten slot");
        assert_eq!(slot.alias.as_deref(), Some("New"));
        assert_eq!(slot.command, "bun run dev");
    }

    #[test]
    fn clear_shortcut_removes_the_binding() {
        let mut config = Config::default();
        config.set_shortcut(4, Some("Build".into()), "bun run build".into());
        assert!(config.shortcut(4).is_some());

        assert!(config.clear_shortcut(4));
        assert!(config.shortcut(4).is_none());
        assert!(config.configured_shortcuts().is_empty());
    }

    #[test]
    fn out_of_range_indexes_are_rejected_for_every_operation() {
        let mut config = Config::default();
        assert!(!config.set_shortcut(0, None, "cmd".into()));
        assert!(!config.set_shortcut(10, None, "cmd".into()));
        assert!(!config.clear_shortcut(0));
        assert!(!config.clear_shortcut(10));
        assert!(config.shortcut(0).is_none());
        assert!(config.shortcut(10).is_none());
    }

    #[test]
    fn existing_config_remains_valid_when_shortcuts_are_added() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let config_path = std::env::temp_dir().join(format!("devnav-mixed-{unique}.tsv"));
        let root = std::env::temp_dir().join(format!("devnav-root-{unique}"));
        fs::create_dir_all(&root).expect("create root");

        let mut config = Config::default();
        config.set_root(root.clone());
        config.toggle_favorite(&root);
        config.set_alias(root.clone(), "principal".into());
        config.set_shortcut(1, Some("Dev".into()), "bun run dev".into());
        config.set_shortcut(9, Some("Tests".into()), "cargo test".into());
        config.save(&config_path).expect("save mixed config");

        let loaded = Config::load(&config_path).expect("load");
        assert_eq!(loaded.root(), Some(root.as_path()));
        assert!(loaded.is_favorite(&root));
        assert_eq!(loaded.alias(&root).map(str::to_owned), Some("principal".into()));
        assert_eq!(loaded.shortcut(1).map(|s| s.command.clone()), Some("bun run dev".into()));
        assert_eq!(loaded.shortcut(9).map(|s| s.command.clone()), Some("cargo test".into()));

        fs::remove_file(config_path).expect("remove config");
        fs::remove_dir_all(root).expect("remove root");
    }

    #[test]
    fn shortcut_commands_preserve_spaces_percent_and_special_characters() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let config_path =
            std::env::temp_dir().join(format!("devnav-shortcut-special-{unique}.tsv"));
        let mut config = Config::default();
        let alias = "100% dev";
        let command = "echo \"hello world\"\t&& cargo test";
        assert!(config.set_shortcut(5, Some(alias.into()), command.into()));
        config.save(&config_path).expect("save special");

        let loaded = Config::load(&config_path).expect("load");
        let slot = loaded.shortcut(5).expect("slot");
        assert_eq!(slot.alias.as_deref(), Some(alias));
        assert_eq!(slot.command, command);
        fs::remove_file(config_path).expect("remove config");
    }
}
