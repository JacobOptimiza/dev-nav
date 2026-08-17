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
    CustomCommands,
    Navigate,
    Select,
    Open,
    Parent,
    ToggleFavorite,
    ToggleFavorites,
    Update,
    Quit,
    ManagerTitle,
    DeleteTitle,
    Empty,
    Alias,
    AliasOptional,
    Repo,
    Command,
    Save,
    Cancel,
    Delete,
    ConfirmDelete,
    SaveError,
    DeleteError,
    CommandSaved,
    CommandDeleted,
    ManageCommands,
}

pub fn text(locale: Locale, id: TextId) -> &'static str {
    match (locale, id) {
        (Locale::EsEs, TextId::ManagerTitle) => "COMANDOS PERSONALIZADOS",
        (Locale::EnUs, TextId::ManagerTitle) => "CUSTOM COMMANDS",
        (Locale::EsEs, TextId::DeleteTitle) => "ELIMINAR COMANDO",
        (Locale::EnUs, TextId::DeleteTitle) => "REMOVE COMMAND",
        (Locale::EsEs, TextId::Empty) => "Vacío",
        (Locale::EnUs, TextId::Empty) => "Empty",
        (Locale::EsEs, TextId::Alias) => "Alias",
        (Locale::EnUs, TextId::Alias) => "Alias",
        (Locale::EsEs, TextId::AliasOptional) => "Alias (opcional)",
        (Locale::EnUs, TextId::AliasOptional) => "Alias (optional)",
        (Locale::EsEs, TextId::Repo) => "Repo",
        (Locale::EnUs, TextId::Repo) => "Repo",
        (Locale::EsEs, TextId::Command) => "Comando",
        (Locale::EnUs, TextId::Command) => "Command",
        (Locale::EsEs, TextId::Save) => "Guardar",
        (Locale::EnUs, TextId::Save) => "Save",
        (Locale::EsEs, TextId::Cancel) => "Cancelar",
        (Locale::EnUs, TextId::Cancel) => "Cancel",
        (Locale::EsEs, TextId::Delete) => "Eliminar",
        (Locale::EnUs, TextId::Delete) => "Delete",
        (Locale::EsEs, TextId::ConfirmDelete) => "¿Eliminar comando?",
        (Locale::EnUs, TextId::ConfirmDelete) => "Remove command?",
        (Locale::EsEs, TextId::SaveError) => "No se pudo guardar",
        (Locale::EnUs, TextId::SaveError) => "Could not save",
        (Locale::EsEs, TextId::DeleteError) => "No se pudo eliminar",
        (Locale::EnUs, TextId::DeleteError) => "Could not delete",
        (Locale::EsEs, TextId::CommandSaved) => "Comando guardado",
        (Locale::EnUs, TextId::CommandSaved) => "Command saved",
        (Locale::EsEs, TextId::CommandDeleted) => "Comando eliminado",
        (Locale::EnUs, TextId::CommandDeleted) => "Command deleted",
        (Locale::EsEs, TextId::ManageCommands) => "Gestionar comandos personalizados",
        (Locale::EnUs, TextId::ManageCommands) => "Manage custom commands",
        _ => "",
    }
}

pub fn shift_range(locale: Locale) -> String {
    let prefix = match locale {
        Locale::EsEs => "Mayús",
        Locale::EnUs => "Shift",
    };
    format!("{prefix}+1–9")
}

pub fn manager_footer(locale: Locale) -> &'static str {
    match locale {
        Locale::EsEs => "↑↓ Mover · Enter Añadir/Editar · Supr Eliminar · Esc Cerrar",
        Locale::EnUs => "↑↓ Move · Enter Add/Edit · Delete Remove · Esc Close",
    }
}

pub fn manager_footer_compact(locale: Locale) -> &'static str {
    match locale {
        Locale::EsEs => "↑↓ · Enter · Supr · Esc",
        Locale::EnUs => "↑↓ · Enter · Del · Esc",
    }
}

pub fn editor_footer(locale: Locale) -> &'static str {
    match locale {
        Locale::EsEs => "Tab Cambiar campo · Enter Guardar · Esc Cancelar",
        Locale::EnUs => "Tab Switch field · Enter Save · Esc Cancel",
    }
}

pub fn editor_footer_compact(_locale: Locale) -> &'static str {
    "Tab · Enter · Esc"
}

pub fn delete_footer(locale: Locale) -> &'static str {
    match locale {
        Locale::EsEs => "Enter Confirmar · Esc Cancelar",
        Locale::EnUs => "Enter Confirm · Esc Cancel",
    }
}

pub fn editor_title(locale: Locale, is_new: bool) -> &'static str {
    match (locale, is_new) {
        (Locale::EsEs, true) => "NUEVO COMANDO",
        (Locale::EsEs, false) => "EDITAR COMANDO",
        (Locale::EnUs, true) => "NEW COMMAND",
        (Locale::EnUs, false) => "EDIT COMMAND",
    }
}

pub fn delete_prompt(locale: Locale) -> &'static str {
    match locale {
        Locale::EsEs => "¿Eliminar este comando?",
        Locale::EnUs => "Remove this command?",
    }
}

/// Canonical actions. UI layers should describe these actions rather than
/// inventing independent key labels.
#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Action {
    Help,
    ToggleLanguage,
    CustomCommands,
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
        KeyBinding, KeyToken, Locale, Modifier, TextId, delete_footer, editor_footer,
        editor_footer_compact, editor_title, format_binding, manager_footer,
        manager_footer_compact, official_bindings, resolve_preferred_tags, shift_range, text,
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

    #[test]
    fn locale_tags_and_alternation_are_symmetric() {
        assert_eq!(Locale::EsEs.tag(), "es-ES");
        assert_eq!(Locale::EnUs.tag(), "en-US");
        assert_eq!(Locale::EsEs.other(), Locale::EnUs);
        assert_eq!(Locale::EnUs.other(), Locale::EsEs);
        assert_eq!(Locale::EsEs.other().other(), Locale::EsEs);
    }

    #[test]
    fn every_defined_text_id_is_translated_in_both_locales() {
        let cases: [(TextId, &str, &str); 14] = [
            (TextId::ManagerTitle, "COMANDOS PERSONALIZADOS", "CUSTOM COMMANDS"),
            (TextId::DeleteTitle, "ELIMINAR COMANDO", "REMOVE COMMAND"),
            (TextId::Empty, "Vacío", "Empty"),
            (TextId::AliasOptional, "Alias (opcional)", "Alias (optional)"),
            (TextId::Command, "Comando", "Command"),
            (TextId::Save, "Guardar", "Save"),
            (TextId::Cancel, "Cancelar", "Cancel"),
            (TextId::Delete, "Eliminar", "Delete"),
            (TextId::ConfirmDelete, "¿Eliminar comando?", "Remove command?"),
            (TextId::SaveError, "No se pudo guardar", "Could not save"),
            (TextId::DeleteError, "No se pudo eliminar", "Could not delete"),
            (TextId::CommandSaved, "Comando guardado", "Command saved"),
            (TextId::CommandDeleted, "Comando eliminado", "Command deleted"),
            (TextId::ManageCommands, "Gestionar comandos personalizados", "Manage custom commands"),
        ];
        for (id, expected_es, expected_en) in cases {
            assert_eq!(text(Locale::EsEs, id), expected_es, "es-ES {id:?}");
            assert_eq!(text(Locale::EnUs, id), expected_en, "en-US {id:?}");
        }
        // Identifiers without UI copy resolve to an empty string.
        assert_eq!(text(Locale::EsEs, TextId::Help), "");
        assert_eq!(text(Locale::EnUs, TextId::Quit), "");
    }

    #[test]
    fn shift_range_and_panel_copy_are_localized() {
        assert_eq!(shift_range(Locale::EsEs), "Mayús+1–9");
        assert_eq!(shift_range(Locale::EnUs), "Shift+1–9");
        assert!(manager_footer(Locale::EsEs).contains("Supr"));
        assert!(manager_footer(Locale::EnUs).contains("Delete"));
        assert!(manager_footer_compact(Locale::EsEs).contains("Supr"));
        assert!(manager_footer_compact(Locale::EnUs).contains("Del"));
        assert!(editor_footer(Locale::EsEs).contains("Tab"));
        assert!(editor_footer(Locale::EnUs).contains("Tab"));
        assert_eq!(editor_footer_compact(Locale::EsEs), "Tab · Enter · Esc");
        assert_eq!(editor_footer_compact(Locale::EnUs), "Tab · Enter · Esc");
        assert!(delete_footer(Locale::EsEs).contains("Confirmar"));
        assert!(delete_footer(Locale::EnUs).contains("Confirm"));
    }

    #[test]
    fn editor_title_distinguishes_new_from_edit_in_both_locales() {
        assert_eq!(editor_title(Locale::EsEs, true), "NUEVO COMANDO");
        assert_eq!(editor_title(Locale::EsEs, false), "EDITAR COMANDO");
        assert_eq!(editor_title(Locale::EnUs, true), "NEW COMMAND");
        assert_eq!(editor_title(Locale::EnUs, false), "EDIT COMMAND");
    }

    #[test]
    fn format_binding_covers_modifiers_and_special_keys() {
        let cases: [(KeyBinding, Locale, &str); 18] = [
            (
                KeyBinding::with_modifier(Modifier::Ctrl, KeyToken::Char('S')),
                Locale::EsEs,
                "Ctrl+S",
            ),
            (
                KeyBinding::with_modifier(Modifier::Ctrl, KeyToken::Char('U')),
                Locale::EnUs,
                "Ctrl+U",
            ),
            (
                KeyBinding::with_modifier(Modifier::Shift, KeyToken::Char('F')),
                Locale::EsEs,
                "Mayús+F",
            ),
            (
                KeyBinding::with_modifier(Modifier::Shift, KeyToken::Char('F')),
                Locale::EnUs,
                "Shift+F",
            ),
            (KeyBinding::plain(KeyToken::Char('q')), Locale::EsEs, "q"),
            (KeyBinding::plain(KeyToken::F1), Locale::EsEs, "F1"),
            (KeyBinding::plain(KeyToken::F2), Locale::EnUs, "F2"),
            (KeyBinding::plain(KeyToken::F3), Locale::EsEs, "F3"),
            (KeyBinding::plain(KeyToken::Enter), Locale::EnUs, "Enter"),
            (KeyBinding::plain(KeyToken::Escape), Locale::EsEs, "Esc"),
            (KeyBinding::plain(KeyToken::Up), Locale::EsEs, "↑"),
            (KeyBinding::plain(KeyToken::Down), Locale::EnUs, "↓"),
            (KeyBinding::plain(KeyToken::Left), Locale::EsEs, "←"),
            (KeyBinding::plain(KeyToken::Right), Locale::EnUs, "→"),
            (KeyBinding::plain(KeyToken::Backspace), Locale::EsEs, "Retroceso"),
            (KeyBinding::plain(KeyToken::Backspace), Locale::EnUs, "Backspace"),
            (
                KeyBinding::with_modifier(Modifier::Shift, KeyToken::Enter),
                Locale::EnUs,
                "Shift+Enter",
            ),
            (
                KeyBinding::with_modifier(Modifier::Ctrl, KeyToken::Backspace),
                Locale::EsEs,
                "Ctrl+Retroceso",
            ),
        ];
        for (binding, locale, expected) in cases {
            assert_eq!(format_binding(binding, locale), expected);
        }
    }
}
