use std::{
    collections::{HashMap, HashSet},
    env, fs, io,
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, Default)]
pub struct Config {
    favorites: HashSet<PathBuf>,
    aliases: HashMap<PathBuf, String>,
}

impl Config {
    pub fn default_path() -> io::Result<PathBuf> {
        let base = env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .ok_or_else(|| {
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
                (Some("favorite"), Some(path), _) => {
                    config.favorites.insert(PathBuf::from(decode(path)));
                }
                (Some("alias"), Some(path), Some(alias)) => {
                    config
                        .aliases
                        .insert(PathBuf::from(decode(path)), decode(alias));
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

fn encode(value: &str) -> String {
    value
        .replace('%', "%25")
        .replace('\t', "%09")
        .replace('\n', "%0A")
}

fn decode(value: &str) -> String {
    value
        .replace("%0A", "\n")
        .replace("%09", "\t")
        .replace("%25", "%")
}

#[cfg(test)]
mod tests {
    use super::{decode, encode};

    #[test]
    fn encoding_round_trip() {
        let input = "C:\\code\t100%\nnext";
        assert_eq!(decode(&encode(input)), input);
    }
}
