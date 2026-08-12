use std::{
    collections::{HashMap, HashSet},
    env, fs, io,
    path::{Path, PathBuf},
};

#[derive(Clone, Debug)]
pub struct Config {
    root: Option<PathBuf>,
    show_favorites: bool,
    check_updates: Option<bool>,
    favorites: HashSet<PathBuf>,
    aliases: HashMap<PathBuf, String>,
}

impl Config {
    pub fn default_path() -> io::Result<PathBuf> {
        let base = env::var_os("LOCALAPPDATA").map(PathBuf::from).ok_or_else(|| {
            io::Error::new(io::ErrorKind::NotFound, "LOCALAPPDATA no está definido")
        })?;
        Ok(base.join("DevNav").join("config.tsv"))
    }

    pub fn load(path: &Path) -> io::Result<Self> {
        let Ok(contents) = fs::read_to_string(path) else {
            return Ok(Self::default());
        };
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
                (Some("favorite"), Some(path), _) => {
                    config.favorites.insert(PathBuf::from(decode(path)));
                }
                (Some("alias"), Some(path), Some(alias)) => {
                    config.aliases.insert(PathBuf::from(decode(path)), decode(alias));
                }
                _ => {}
            }
        }
        Ok(config)
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
        fs::write(path, output)
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
}

impl Default for Config {
    fn default() -> Self {
        Self {
            root: None,
            show_favorites: true,
            check_updates: None,
            favorites: HashSet::new(),
            aliases: HashMap::new(),
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
    fn startup_root_is_persisted_with_the_rest_of_the_config() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let config_path = std::env::temp_dir().join(format!("devnav-config-{unique}.tsv"));
        let root = std::env::temp_dir().join("repositorios");
        let mut config = Config::default();
        config.set_root(root.clone());

        config.save(&config_path).expect("save config");
        let loaded = Config::load(&config_path).expect("load config");

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

        assert!(!Config::load(&config_path).expect("load config").show_favorites());
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

        assert_eq!(Config::load(&config_path).expect("load config").check_updates(), Some(false));
        fs::remove_file(config_path).expect("remove config");
    }
}
