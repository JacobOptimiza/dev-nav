use std::io;

use windows_sys::Win32::System::Console::{
    GetStdHandle, INPUT_RECORD, KEY_EVENT, LEFT_ALT_PRESSED, LEFT_CTRL_PRESSED, RIGHT_ALT_PRESSED,
    RIGHT_CTRL_PRESSED, ReadConsoleInputW, SHIFT_PRESSED, STD_INPUT_HANDLE,
    WINDOW_BUFFER_SIZE_EVENT,
};

const VK_BACK: u16 = 0x08;
const VK_RETURN: u16 = 0x0D;
const VK_ESCAPE: u16 = 0x1B;
const VK_F1: u16 = 0x70;
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
    F1,
    CtrlC,
    CtrlS,
    CtrlU,
    Resize,
    /// A Shift+digit slot (1..=9). Detected from the physical virtual key code
    /// plus the SHIFT modifier so it is independent of the character produced
    /// by the active keyboard layout (e.g. `!` on the US layout).
    Shortcut(u8),
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
        // Raw pointer borrows avoid creating aliasing references handed to FFI.
        let success =
            unsafe { ReadConsoleInputW(input, &raw mut record, 1, &raw mut records_read) };
        if success == 0 {
            return Err(io::Error::last_os_error());
        }
        if records_read == 0 {
            continue;
        }
        if u32::from(record.EventType) == WINDOW_BUFFER_SIZE_EVENT {
            return Ok(Key::Resize);
        }
        if u32::from(record.EventType) != KEY_EVENT {
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
    if control && event.wVirtualKeyCode == u16::from(b'C') {
        return Key::CtrlC;
    }
    if control && event.wVirtualKeyCode == u16::from(b'S') {
        return Key::CtrlS;
    }
    if control && event.wVirtualKeyCode == u16::from(b'U') {
        return Key::CtrlU;
    }
    // Shift+digit maps to a shortcut slot only when Shift is held and no
    // control/alt modifier accompanies it, so a plain digit stays a character
    // and Ctrl+Shift+digit / Alt+Shift+digit stay available for the OS.
    let shift = event.dwControlKeyState & SHIFT_PRESSED != 0;
    let no_modifiers =
        !control && event.dwControlKeyState & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED) == 0;
    if shift
        && no_modifiers
        && let Some(slot) = shortcut_slot(event.wVirtualKeyCode)
    {
        return Key::Shortcut(slot);
    }

    match event.wVirtualKeyCode {
        VK_UP => Key::Up,
        VK_DOWN => Key::Down,
        VK_LEFT => Key::Left,
        VK_RIGHT => Key::Right,
        VK_RETURN => Key::Enter,
        VK_BACK => Key::Backspace,
        VK_ESCAPE => Key::Escape,
        VK_F1 => Key::F1,
        _ => char::from_u32(u32::from(unsafe { event.uChar.UnicodeChar }))
            .filter(|character| !character.is_control())
            .map_or(Key::Unknown, Key::Char),
    }
}

/// Maps a top-row digit virtual key (`VK_1`..`VK_9`) to its 1-based shortcut
/// slot. `VK_0`, numpad keys and anything else return `None`.
fn shortcut_slot(virtual_key: u16) -> Option<u8> {
    // checked_sub handles keys below '0'; try_from + range filter keep this
    // cast-free and provably within u8 range.
    let offset = virtual_key.checked_sub(0x30)?;
    u8::try_from(offset).ok().filter(|slot| (1..=9).contains(slot))
}

#[cfg(test)]
mod tests {
    use super::{Key, VK_DOWN, VK_ESCAPE, VK_F1, VK_UP, map_key};
    use windows_sys::Win32::System::Console::KEY_EVENT_RECORD;
    use windows_sys::Win32::System::Console::{LEFT_CTRL_PRESSED, SHIFT_PRESSED};

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
        assert_eq!(map_key(key_event(VK_F1)), Key::F1);
    }

    #[test]
    fn control_s_has_a_dedicated_shortcut() {
        let mut event = key_event(u16::from(b'S'));
        event.dwControlKeyState = LEFT_CTRL_PRESSED;

        assert_eq!(map_key(event), Key::CtrlS);
    }

    #[test]
    fn control_u_has_a_dedicated_shortcut() {
        let mut event = key_event(u16::from(b'U'));
        event.dwControlKeyState = LEFT_CTRL_PRESSED;

        assert_eq!(map_key(event), Key::CtrlU);
    }

    #[test]
    fn shift_digits_map_to_their_shortcut_slots() {
        let mut event = key_event(u16::from(b'1'));
        event.dwControlKeyState = SHIFT_PRESSED;
        assert_eq!(map_key(event), Key::Shortcut(1));

        let mut event = key_event(u16::from(b'9'));
        event.dwControlKeyState = SHIFT_PRESSED;
        assert_eq!(map_key(event), Key::Shortcut(9));
    }

    #[test]
    fn intermediate_shift_digits_map_to_intermediate_slots() {
        for digit in b'1'..=b'9' {
            let mut event = key_event(u16::from(digit));
            event.dwControlKeyState = SHIFT_PRESSED;
            assert_eq!(map_key(event), Key::Shortcut(digit - b'0'));
        }
    }

    #[test]
    fn shift_zero_is_not_a_shortcut() {
        let mut event = key_event(u16::from(b'0'));
        event.dwControlKeyState = SHIFT_PRESSED;
        assert!(matches!(map_key(event), Key::Char(_) | Key::Unknown));
    }

    #[test]
    fn ctrl_shift_digit_is_not_a_shortcut() {
        let mut event = key_event(u16::from(b'1'));
        event.dwControlKeyState = SHIFT_PRESSED | LEFT_CTRL_PRESSED;
        assert_ne!(map_key(event), Key::Shortcut(1));
    }

    #[test]
    fn plain_digit_without_shift_is_not_a_shortcut() {
        let event = key_event(u16::from(b'1'));
        assert_ne!(map_key(event), Key::Shortcut(1));

        let mut shifted = key_event(u16::from(b'1'));
        shifted.dwControlKeyState = SHIFT_PRESSED;
        assert_eq!(map_key(shifted), Key::Shortcut(1));
    }
}
