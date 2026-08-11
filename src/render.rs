use std::io::{self, Write};

pub struct Renderer {
    previous: Vec<String>,
}

impl Renderer {
    pub fn new() -> Self {
        Self {
            previous: Vec::new(),
        }
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
