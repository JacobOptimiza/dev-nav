//! Small, dependency-free localization layer for the two supported UI locales.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Locale {
    EsEs,
    EnUs,
}

impl Locale {
    pub fn from_tag(tag: &str) -> Option<Self> {
        let language = tag.split(['-', '_']).next()?.to_ascii_lowercase();
        match language.as_str() {
            "es" => Some(Self::EsEs),
            "en" => Some(Self::EnUs),
            _ => None,
        }
    }

    pub const fn tag(self) -> &'static str {
        match self {
            Self::EsEs => "es-ES",
            Self::EnUs => "en-US",
        }
    }

    pub const fn other(self) -> Self {
        match self {
            Self::EsEs => Self::EnUs,
            Self::EnUs => Self::EsEs,
        }
    }
}

/// Resolves the first supported language from Windows' ordered preference list.
/// Unsupported entries are skipped; English is the deterministic fallback.
pub fn resolve_preferred_tags<I, S>(tags: I) -> Locale
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    tags.into_iter().find_map(|tag| Locale::from_tag(tag.as_ref())).unwrap_or(Locale::EnUs)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Modifier {
    Ctrl,
    Shift,
}

/// Stable semantic identifiers shared by input, help and status rendering.
#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TextId {
    Help,
    Language,
    Navigate,
    Select,
    Open,
    Parent,
    ToggleFavorite,
    ToggleFavorites,
    Update,
    Quit,
}

/// Canonical actions. UI layers should describe these actions rather than
/// inventing independent key labels.
#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Action {
    Help,
    ToggleLanguage,
    NavigateUp,
    NavigateDown,
    OpenFolder,
    GoParent,
    Select,
    ToggleFavorite,
    ToggleFavoritesVisibility,
    Refresh,
    ToggleUpdateCheck,
    Update,
    Quit,
    CustomShortcut(u8),
}

#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum KeyToken {
    Char(char),
    F1,
    F2,
    F3,
    Enter,
    Escape,
    Up,
    Down,
    Left,
    Right,
    Backspace,
}

/// A binding can represent at most one modifier and one physical key.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct KeyBinding {
    pub modifier: Option<Modifier>,
    pub key: KeyToken,
}

impl KeyBinding {
    pub const fn plain(key: KeyToken) -> Self {
        Self { modifier: None, key }
    }

    pub const fn with_modifier(modifier: Modifier, key: KeyToken) -> Self {
        Self { modifier: Some(modifier), key }
    }
}

pub fn format_binding(binding: KeyBinding, locale: Locale) -> String {
    let modifier = match (binding.modifier, locale) {
        (Some(Modifier::Ctrl), _) => Some("Ctrl"),
        (Some(Modifier::Shift), Locale::EsEs) => Some("Mayús"),
        (Some(Modifier::Shift), Locale::EnUs) => Some("Shift"),
        (None, _) => None,
    };
    let key = match binding.key {
        KeyToken::Char(value) => value.to_string(),
        KeyToken::F1 => "F1".into(),
        KeyToken::F2 => "F2".into(),
        KeyToken::F3 => "F3".into(),
        KeyToken::Enter => "Enter".into(),
        KeyToken::Escape => "Esc".into(),
        KeyToken::Up => "↑".into(),
        KeyToken::Down => "↓".into(),
        KeyToken::Left => "←".into(),
        KeyToken::Right => "→".into(),
        KeyToken::Backspace => match locale {
            Locale::EsEs => "Retroceso".into(),
            Locale::EnUs => "Backspace".into(),
        },
    };
    modifier.map_or(key.clone(), |value| format!("{value}+{key}"))
}

/// Every official binding is represented here so the two-key contract is
/// testable and future additions cannot silently introduce a chord.
#[allow(dead_code)]
pub fn official_bindings() -> &'static [KeyBinding] {
    const BINDINGS: [KeyBinding; 9] = [
        KeyBinding::plain(KeyToken::F1),
        KeyBinding::plain(KeyToken::F2),
        KeyBinding::plain(KeyToken::F3),
        KeyBinding::plain(KeyToken::Enter),
        KeyBinding::plain(KeyToken::Escape),
        KeyBinding::with_modifier(Modifier::Ctrl, KeyToken::Char('S')),
        KeyBinding::with_modifier(Modifier::Ctrl, KeyToken::Char('U')),
        KeyBinding::with_modifier(Modifier::Shift, KeyToken::Char('F')),
        KeyBinding::with_modifier(Modifier::Shift, KeyToken::Char('U')),
    ];
    &BINDINGS
}

#[cfg(test)]
mod tests {
    use super::{
        KeyBinding, KeyToken, Locale, Modifier, format_binding, official_bindings,
        resolve_preferred_tags,
    };

    #[test]
    fn official_bindings_have_at_most_one_modifier_and_two_physical_keys() {
        assert!(official_bindings().iter().all(|binding| {
            binding.modifier.is_none()
                || matches!(binding.modifier, Some(Modifier::Ctrl | Modifier::Shift))
        }));
    }

    #[test]
    fn shift_format_is_localized_without_arrow_glyphs() {
        let binding = KeyBinding::with_modifier(Modifier::Shift, KeyToken::Char('F'));
        assert_eq!(format_binding(binding, Locale::EsEs), "Mayús+F");
        assert_eq!(format_binding(binding, Locale::EnUs), "Shift+F");
        assert!(
            !format_binding(binding, Locale::EsEs).chars().any(|character| character == '\u{21e7}')
        );
    }

    #[test]
    fn language_tags_use_language_not_region() {
        assert_eq!(Locale::from_tag("es-MX"), Some(Locale::EsEs));
        assert_eq!(Locale::from_tag("en-GB"), Some(Locale::EnUs));
        assert_eq!(Locale::from_tag("de-DE"), None);
    }

    #[test]
    fn preferred_language_resolution_uses_order_and_english_fallback() {
        assert_eq!(resolve_preferred_tags(["de-DE", "en-GB"]), Locale::EnUs);
        assert_eq!(resolve_preferred_tags(["de-DE", "es-ES", "en-US"]), Locale::EsEs);
        assert_eq!(resolve_preferred_tags(["de-DE", "fr-FR"]), Locale::EnUs);
    }
}
