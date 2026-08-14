use std::io::{self, Write};

pub const CYAN: &str = "\x1b[38;2;116;199;236m";
pub const FRAME: &str = "\x1b[38;2;90;100;120m";
pub const SELECTED_BG: &str = "\x1b[48;2;32;43;65m";
pub const SELECTED_FG: &str = "\x1b[38;2;232;238;252m";
pub const SHORTCUT: &str = "\x1b[38;2;255;203;107m";
pub const RESET: &str = "\x1b[0m";

pub fn selected(text: &str, width: usize) -> String {
    format!("{SELECTED_BG}{SELECTED_FG}{}{}", fit(text, width), RESET)
}

pub struct Renderer {
    previous: Vec<String>,
}

impl Renderer {
    pub fn new() -> Self {
        Self { previous: Vec::new() }
    }

    pub fn draw(&mut self, rows: Vec<String>) -> io::Result<()> {
        let mut output = String::with_capacity(4096);
        output.push_str("\x1b[?2026h");
        for (index, row) in rows.iter().enumerate() {
            if self.previous.get(index) != Some(row) {
                output.push_str(&format!("\x1b[{};1H\x1b[2K{}", index + 1, row));
            }
        }
        if self.previous.len() > rows.len() {
            for index in rows.len()..self.previous.len() {
                output.push_str(&format!("\x1b[{};1H\x1b[2K", index + 1));
            }
        }
        output.push_str("\x1b[?2026l");
        let mut stdout = io::stdout().lock();
        stdout.write_all(output.as_bytes())?;
        stdout.flush()?;
        self.previous = rows;
        Ok(())
    }
}

pub fn fit(text: &str, width: usize) -> String {
    let count = text.chars().count();
    if count <= width {
        format!("{text}{}", " ".repeat(width - count))
    } else if width > 1 {
        format!("{}…", text.chars().take(width - 1).collect::<String>())
    } else {
        text.chars().take(width).collect()
    }
}
