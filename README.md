# DevNav

Navegador TUI nativo para moverse entre proyectos desde PowerShell 7 en Windows.
Arranca en `$HOME\programacion`, muestra los favoritos primero y devuelve la
selección al shell para que el cambio de directorio persista.

## Compatibilidad

- Windows 10/11 x64 o ARM64.
- PowerShell 7 o posterior.
- Windows Terminal recomendado.
- No requiere Rust para instalar los binarios publicados.

No es compatible con Linux, macOS, Windows PowerShell 5.1 ni arquitecturas x86 de
32 bits. La raíz predeterminada es `$HOME\programacion`; puede cambiarse mediante
la variable de entorno `DEV_HOME`.

## Instalación

```powershell
git clone https://github.com/JacobOptimiza/dev-nav.git
cd dev-nav
.\install.ps1
```

El instalador detecta x64/ARM64, descarga el binario correspondiente desde GitHub
Releases, lo copia a `%LOCALAPPDATA%\Programs\DevNav` y registra el módulo en el
perfil de PowerShell 7. No modifica el `PATH` global.

Para compilar el código local en vez de descargar un release:

```powershell
.\install.ps1 -BuildFromSource
```

Ese modo sí requiere Rust stable y MSVC Build Tools.

## Uso

```powershell
dev
dev codex
dev "git status"
```

| Tecla | Acción |
|---|---|
| `↑` / `↓`, `j` / `k` | mover selección |
| `Enter` | seleccionar carpeta y volver a PowerShell |
| `→` / `l` | entrar en la carpeta |
| `←` / `h` | subir al directorio padre |
| `.` | seleccionar el directorio mostrado |
| `g` | volver a la raíz de proyectos |
| `f` | añadir o quitar favorito |
| `a` | editar alias |
| `c` | abrir `codex` en la carpeta resaltada |
| `r` | ejecutar `codex resume --last` en la carpeta resaltada |
| `/` | filtro fuzzy incremental |
| `:` | ejecutar un comando en la carpeta resaltada |
| `u` | refrescar |
| `q` / `Esc` | cancelar |

Los favoritos y alias se guardan fuera del repositorio, en
`%LOCALAPPDATA%\DevNav\config.tsv`.

## Arquitectura

- Rust 2024 y Win32 mediante `windows-sys`.
- Renderer VT propio con buffer de filas y repintado diferencial.
- Synchronized Output (`DEC 2026`) para minimizar tearing.
- Entrada raw mediante `ReadConsoleInputW`, sin ambigüedad entre flechas y Escape.
- Event loop sin polling ni renders cuando no hay eventos.
- Protocolo de resultados separado del stdout utilizado por la TUI.
- Cero frameworks TUI y una sola dependencia directa.

## Privacidad y seguridad

DevNav no contiene telemetría, no necesita credenciales y no accede a la red en
tiempo de ejecución. Únicamente `install.ps1` usa la red para descargar el binario
público desde GitHub Releases. No se versionan favoritos, alias, variables de
entorno, perfiles de PowerShell ni archivos de usuario.

## Desarrollo

```powershell
cargo fmt -- --check
cargo test
cargo clippy --all-targets -- -D warnings
cargo build --release
```

## Licencia

MIT. Consulta [LICENSE](LICENSE).
