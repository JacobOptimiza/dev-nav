use std::io::{self, Write};

use windows_sys::Win32::{
    Foundation::{HANDLE, INVALID_HANDLE_VALUE},
    System::Console::{
        CONSOLE_SCREEN_BUFFER_INFO, DISABLE_NEWLINE_AUTO_RETURN, ENABLE_ECHO_INPUT,
        ENABLE_EXTENDED_FLAGS, ENABLE_LINE_INPUT, ENABLE_PROCESSED_INPUT, ENABLE_QUICK_EDIT_MODE,
        ENABLE_VIRTUAL_TERMINAL_INPUT, ENABLE_VIRTUAL_TERMINAL_PROCESSING, ENABLE_WINDOW_INPUT,
        GetConsoleMode, GetConsoleScreenBufferInfo, GetStdHandle, STD_INPUT_HANDLE,
        STD_OUTPUT_HANDLE, SetConsoleMode,
    },
};

pub struct Terminal {
    input: HANDLE,
    output: HANDLE,
    original_input_mode: u32,
    original_output_mode: u32,
}

impl Terminal {
    pub fn enter() -> io::Result<Self> {
        unsafe {
            let input = GetStdHandle(STD_INPUT_HANDLE);
            let output = GetStdHandle(STD_OUTPUT_HANDLE);
            validate_handle(input)?;
            validate_handle(output)?;

            let mut original_input_mode = 0;
            let mut original_output_mode = 0;
            win32(GetConsoleMode(input, &mut original_input_mode))?;
            win32(GetConsoleMode(output, &mut original_output_mode))?;

            let input_mode = (original_input_mode
                & !(ENABLE_ECHO_INPUT
                    | ENABLE_LINE_INPUT
                    | ENABLE_PROCESSED_INPUT
                    | ENABLE_QUICK_EDIT_MODE
                    | ENABLE_VIRTUAL_TERMINAL_INPUT))
                | ENABLE_EXTENDED_FLAGS
                | ENABLE_WINDOW_INPUT;
            let output_mode = original_output_mode
                | ENABLE_VIRTUAL_TERMINAL_PROCESSING
                | DISABLE_NEWLINE_AUTO_RETURN;
            win32(SetConsoleMode(input, input_mode))?;
            if let Err(error) = win32(SetConsoleMode(output, output_mode)) {
                let _ = SetConsoleMode(input, original_input_mode);
                return Err(error);
            }

            print!("\x1b[?1049h\x1b[?25l\x1b[2J");
            io::stdout().flush()?;
            Ok(Self { input, output, original_input_mode, original_output_mode })
        }
    }

    pub fn size(&self) -> (u16, u16) {
        unsafe {
            let mut info: CONSOLE_SCREEN_BUFFER_INFO = std::mem::zeroed();
            if GetConsoleScreenBufferInfo(self.output, &mut info) != 0 {
                let width = (info.srWindow.Right - info.srWindow.Left + 1).max(1) as u16;
                let height = (info.srWindow.Bottom - info.srWindow.Top + 1).max(1) as u16;
                (width, height)
            } else {
                (100, 30)
            }
        }
    }
}

impl Drop for Terminal {
    fn drop(&mut self) {
        unsafe {
            let _ = SetConsoleMode(self.input, self.original_input_mode);
            let _ = SetConsoleMode(self.output, self.original_output_mode);
        }
        let _ = write!(io::stdout(), "\x1b[0m\x1b[?25h\x1b[?1049l");
        let _ = io::stdout().flush();
    }
}

fn validate_handle(handle: HANDLE) -> io::Result<()> {
    if handle.is_null() || handle == INVALID_HANDLE_VALUE {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn win32(success: i32) -> io::Result<()> {
    if success == 0 { Err(io::Error::last_os_error()) } else { Ok(()) }
}
