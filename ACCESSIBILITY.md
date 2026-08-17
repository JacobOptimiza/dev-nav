# Accessibility audit

This is the project's accessibility review of the DevNav TUI and its
documentation, performed against common accessibility best practices
(WCAG 2.1 principles applied to a terminal user interface where reasonable).
It records what was verified, what is strong, and the residual limitations.

## TUI (the `dev` navigator)

### Keyboard operation — PASS

- DevNav is fully keyboard-driven: every function, mode, and dialog is
  reachable and completable from the keyboard only (see the shortcut tables
  in [README.md](README.md)). No operation requires a mouse, and no function
  is mouse-only.
- No time-limited input or auto-dismissing dialog exists; modal panels
  (help, command manager, delete confirmation) stay until explicitly closed.
- Focus is always visible: the highlighted row uses a distinct
  background/foreground pair plus a `>` marker, so the selection is
  identifiable without relying on color alone.

### Color and contrast — PASS with notes

Audited foreground colors (defined in `src/render.rs`) against a dark
terminal background:

| Element | Color (RGB) | Contrast vs black | WCAG AA (4.5:1) |
|---|---|---|---|
| Normal text / selected row text | SELECTED_FG (232,238,252) | 18.1:1 | PASS |
| Titles / accents | CYAN (116,199,236) | 11.1:1 | PASS |
| Shortcut highlights | SHORTCUT (255,203,107) | 14.0:1 | PASS |
| Selected-row background pairing | SELECTED_FG on SELECTED_BG (32,43,65) | 12.2:1 | PASS |
| Frame/border glyphs | FRAME (90,100,120) | 3.5:1 | Decorative (non-text), exempt |

All *text* elements meet WCAG AA contrast on dark terminal backgrounds. The
frame color is decorative (borders only) and carries no information by
itself.

### Residual limitations (documented, not claimed as met)

- **Light terminal themes**: on white/light terminal backgrounds the light
  foreground palette does not meet AA contrast. DevNav inherits the terminal's
  default background rather than forcing one. Recommendation for affected
  users: use a dark terminal theme (e.g., Windows Terminal's dark profiles).
  Changing the application to force its own background would alter rendering
  for every user and is tracked as a possible future option, not adopted in
  this audit.
- **Screen readers**: the TUI draws a raw console screen buffer with ANSI
  escape sequences and differential updates; it does not expose a UIA/Accessibility
  tree. Screen-reader users cannot meaningfully operate the interactive TUI
  today. The non-interactive paths (`dev --version`, config commands such as
  `dev language` / `dev shortcut`) work normally with assistive technology
  because they are plain console I/O.

## Project sites and documentation — PASS

- Documentation (README, TROUBLESHOOTING, CONTRIBUTING, this file) is plain
  Markdown: text-first, screen-reader friendly, with semantic heading
  structure and descriptive link text.
- All user-facing content is available in two languages (English and Spanish).
- No documentation feature relies on color-only information or on
  time-limited interaction.

## Conclusion

DevNav follows accessibility best practices where it is reasonable for a
terminal application: complete keyboard operability, no time constraints,
visible focus, AA-contrast text on dark backgrounds, and accessible
documentation. The two residual limitations above are real and recorded
rather than claimed as solved.
