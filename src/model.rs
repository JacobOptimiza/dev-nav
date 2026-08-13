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

#[derive(Debug, PartialEq, Eq)]
pub enum ShellResult {
    ChangeDirectory(PathBuf),
    Execute { directory: PathBuf, command: String },
    Update,
}

impl ShellResult {
    pub fn write_to(&self, path: &Path) -> io::Result<()> {
        let (kind, directory, command) = match self {
            Self::ChangeDirectory(directory) => ("cd", directory.as_path(), ""),
            Self::Execute { directory, command } => ("exec", directory.as_path(), command.as_str()),
            Self::Update => ("update", Path::new(""), ""),
        };
        let payload = format!("{kind}\0{}\0{command}", directory.display());
        fs::write(path, payload)
    }
}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::ShellResult;

    #[test]
    fn update_result_uses_a_dedicated_shell_message() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let path = std::env::temp_dir().join(format!("devnav-result-{unique}"));

        ShellResult::Update.write_to(&path).expect("write update result");

        assert_eq!(fs::read_to_string(&path).expect("read result"), "update\0\0");
        fs::remove_file(path).expect("remove result");
    }

    #[test]
    fn execute_result_carries_the_directory_and_command_verbatim() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let path = std::env::temp_dir().join(format!("devnav-exec-{unique}"));
        let directory = std::path::PathBuf::from("C:\\code\\dev-nav");
        let command = "bun run dev";

        ShellResult::Execute { directory: directory.clone(), command: command.into() }
            .write_to(&path)
            .expect("write exec result");

        let payload = fs::read_to_string(&path).expect("read exec result");
        assert_eq!(payload, format!("exec\0{}\0{command}", directory.display()));
        fs::remove_file(path).expect("remove result");
    }
}
