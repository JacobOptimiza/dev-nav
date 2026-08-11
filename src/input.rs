use std::io;

use windows_sys::Win32::System::Console::{
    GetStdHandle, INPUT_RECORD, KEY_EVENT, LEFT_CTRL_PRESSED, RIGHT_CTRL_PRESSED,
    ReadConsoleInputW, STD_INPUT_HANDLE, WINDOW_BUFFER_SIZE_EVENT,
};

const VK_BACK: u16 = 0x08;
const VK_RETURN: u16 = 0x0D;
const VK_ESCAPE: u16 = 0x1B;
const VK_LEFT: u16 = 0x25;
const VK_UP: u16 = 0x26;
const VK_RIGHT: u16 = 0x27;
const VK_DOWN: u16 = 0x28;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Key {
    Up,
    Down,
    Left,
    Right,
    Enter,
    Backspace,
    Escape,
    CtrlC,
    Resize,
    Char(char),
    Unknown,
}

pub fn read_key() -> io::Result<Key> {
    let input = unsafe { GetStdHandle(STD_INPUT_HANDLE) };
    if input.is_null() {
        return Err(io::Error::last_os_error());
    }

    loop {
        let mut record = INPUT_RECORD::default();
        let mut records_read = 0_u32;
        let success = unsafe { ReadConsoleInputW(input, &mut record, 1, &mut records_read) };
        if success == 0 {
            return Err(io::Error::last_os_error());
        }
        if records_read == 0 {
            continue;
        }
        if record.EventType as u32 == WINDOW_BUFFER_SIZE_EVENT {
            return Ok(Key::Resize);
        }
        if record.EventType as u32 != KEY_EVENT {
            continue;
        }

        let event = unsafe { record.Event.KeyEvent };
        if event.bKeyDown == 0 {
            continue;
        }

        return Ok(map_key(event));
    }
}

fn map_key(event: windows_sys::Win32::System::Console::KEY_EVENT_RECORD) -> Key {
    let control = event.dwControlKeyState & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED) != 0;
    if control && event.wVirtualKeyCode == b'C' as u16 {
        return Key::CtrlC;
    }

    match event.wVirtualKeyCode {
        VK_UP => Key::Up,
        VK_DOWN => Key::Down,
        VK_LEFT => Key::Left,
        VK_RIGHT => Key::Right,
        VK_RETURN => Key::Enter,
        VK_BACK => Key::Backspace,
        VK_ESCAPE => Key::Escape,
        _ => {
            let unicode = unsafe { event.uChar.UnicodeChar };
            char::from_u32(u32::from(unicode))
                .filter(|character| !character.is_control())
                .map(Key::Char)
                .unwrap_or(Key::Unknown)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{Key, VK_DOWN, VK_ESCAPE, VK_UP, map_key};
    use windows_sys::Win32::System::Console::KEY_EVENT_RECORD;

    fn key_event(virtual_key: u16) -> KEY_EVENT_RECORD {
        KEY_EVENT_RECORD {
            bKeyDown: 1,
            wRepeatCount: 1,
            wVirtualKeyCode: virtual_key,
            ..Default::default()
        }
    }

    #[test]
    fn navigation_keys_are_not_escape() {
        assert_eq!(map_key(key_event(VK_UP)), Key::Up);
        assert_eq!(map_key(key_event(VK_DOWN)), Key::Down);
        assert_eq!(map_key(key_event(VK_ESCAPE)), Key::Escape);
    }
}
