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
    Execute { directory: PathBuf, command: String, context: Option<ExecutionContext> },
    Update,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AgentIdentity {
    Codex,
    Claude,
    OpenCode,
    Kimi,
}

impl AgentIdentity {
    pub const fn display_name(&self) -> &'static str {
        match self {
            Self::Codex => "Codex",
            Self::Claude => "Claude",
            Self::OpenCode => "OpenCode",
            Self::Kimi => "Kimi",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExecutionContext {
    pub agent: AgentIdentity,
    pub repository: String,
}

impl ShellResult {
    pub fn write_to(&self, path: &Path) -> io::Result<()> {
        let (kind, directory, command) = match self {
            Self::ChangeDirectory(directory) => ("cd", directory.as_path(), ""),
            Self::Execute { directory, command, context } => {
                let payload = match context {
                    Some(context) => format!(
                        "exec\0{}\0{}\0{}\0{}",
                        directory.display(),
                        command,
                        context.agent.display_name(),
                        context.repository
                    ),
                    None => format!("exec\0{}\0{command}", directory.display()),
                };
                return fs::write(path, payload);
            }
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

    use super::{DirectoryEntry, ShellResult};

    #[test]
    fn label_prefers_a_non_empty_alias_over_the_name() {
        let mut entry = DirectoryEntry {
            path: std::path::PathBuf::from("C:\\code\\dev-nav"),
            name: "dev-nav".into(),
            alias: Some("principal".into()),
            favorite: false,
        };
        assert_eq!(entry.label(), "principal - dev-nav");

        entry.alias = Some("   ".into());
        assert_eq!(entry.label(), "    - dev-nav");

        entry.alias = Some(String::new());
        assert_eq!(entry.label(), "dev-nav");

        entry.alias = None;
        assert_eq!(entry.label(), "dev-nav");
    }

    #[test]
    fn change_directory_result_carries_the_path_verbatim() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let path = std::env::temp_dir().join(format!("devnav-cd-{unique}"));
        let directory = std::path::PathBuf::from("C:\\code\\dev-nav");

        ShellResult::ChangeDirectory(directory.clone()).write_to(&path).expect("write cd result");

        let payload = fs::read_to_string(&path).expect("read cd result");
        assert_eq!(payload, format!("cd\0{}\0", directory.display()));
        fs::remove_file(path).expect("remove result");
    }

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

        ShellResult::Execute {
            directory: directory.clone(),
            command: command.into(),
            context: None,
        }
        .write_to(&path)
        .expect("write exec result");

        let payload = fs::read_to_string(&path).expect("read exec result");
        assert_eq!(payload, format!("exec\0{}\0{command}", directory.display()));
        fs::remove_file(path).expect("remove result");
    }

    #[test]
    fn agent_result_appends_explicit_context_without_parsing_the_command() {
        let unique = SystemTime::now().duration_since(UNIX_EPOCH).expect("system time").as_nanos();
        let path = std::env::temp_dir().join(format!("devnav-agent-{unique}"));
        let directory = std::path::PathBuf::from("C:\\code\\dev-nav");
        let context = super::ExecutionContext {
            agent: super::AgentIdentity::Codex,
            repository: "dev-nav".into(),
        };

        ShellResult::Execute {
            directory,
            command: "codex resume --last".into(),
            context: Some(context),
        }
        .write_to(&path)
        .expect("write result");

        assert_eq!(
            fs::read_to_string(&path).expect("read result"),
            "exec\0C:\\code\\dev-nav\0codex resume --last\0Codex\0dev-nav"
        );
        fs::remove_file(path).expect("remove result");
    }
}
