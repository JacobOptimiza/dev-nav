use std::{
    fs, io,
    path::{Path, PathBuf},
};

#[derive(Clone, Debug)]
pub struct DirectoryEntry {
    pub path: PathBuf,
    pub name: String,
    pub alias: Option<String>,
    pub favorite: bool,
}

impl DirectoryEntry {
    pub fn label(&self) -> String {
        match self.alias.as_deref().filter(|alias| !alias.is_empty()) {
            Some(alias) => format!("{alias} - {}", self.name),
            None => self.name.clone(),
        }
    }
}

#[derive(Debug)]
pub enum ShellResult {
    ChangeDirectory(PathBuf),
    Execute { directory: PathBuf, command: String },
}

impl ShellResult {
    pub fn write_to(&self, path: &Path) -> io::Result<()> {
        let (kind, directory, command) = match self {
            Self::ChangeDirectory(directory) => ("cd", directory, ""),
            Self::Execute { directory, command } => ("exec", directory, command.as_str()),
        };
        let payload = format!("{kind}\0{}\0{command}", directory.display());
        fs::write(path, payload)
    }
}
