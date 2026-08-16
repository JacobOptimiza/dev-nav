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

#[cfg(test)]
mod tests {
    use super::{SELECTED_BG, SELECTED_FG, fit, selected};

    #[test]
    fn fit_pads_short_text_to_the_requested_width() {
        assert_eq!(fit("dev", 6), "dev   ");
        assert_eq!(fit("", 3), "   ");
        assert_eq!(fit("exact", 5), "exact");
    }

    #[test]
    fn fit_truncates_long_text_with_an_ellipsis() {
        assert_eq!(fit("abcdef", 4), "abc…");
        assert_eq!(fit("carpeta", 2), "c…");
    }

    #[test]
    fn fit_handles_degenerate_widths() {
        assert_eq!(fit("abc", 1), "a");
        assert_eq!(fit("abc", 0), "");
        assert_eq!(fit("", 0), "");
    }

    #[test]
    fn fit_counts_unicode_scalar_values_not_bytes() {
        assert_eq!(fit("áé", 4), "áé  ");
        assert_eq!(fit("áéí", 2), "á…");
        assert_eq!(fit("日本語", 2), "日…");
    }

    #[test]
    fn selected_wraps_the_fitted_text_in_highlight_colors() {
        let row = selected("entry", 8);
        assert!(row.starts_with(SELECTED_BG));
        assert!(row.contains(SELECTED_FG));
        assert!(row.contains("entry   "));
    }
}
