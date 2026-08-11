# DevNav

DevNav es un navegador TUI nativo para moverse entre proyectos desde PowerShell
7 en Windows. Permite seleccionar una carpeta, cambiar la ubicación del shell,
guardar favoritos globales, asignar alias y abrir Codex, Claude Code, OpenCode o
Kimi en el repositorio activo.

## Requisitos

- Windows 10 u 11, x64 o ARM64.
- PowerShell 7 o posterior (`pwsh`).
- Git, únicamente para clonar el repositorio durante la instalación.
- Windows Terminal recomendado.

Los binarios publicados no requieren Rust ni Visual Studio. Windows PowerShell
5.1, Windows de 32 bits, Linux y macOS no están soportados.

## 1. Configurar la carpeta de proyectos

Haz esto **antes de instalar**. DevNav necesita saber en qué carpeta debe arrancar.

### Opción A: usar la ruta predeterminada

La ruta predeterminada es `$HOME\programacion`. Créala si no existe:

```powershell
New-Item -ItemType Directory -Path (Join-Path $HOME 'programacion') -Force
```

No necesitas configurar ninguna variable de entorno.

### Opción B: utilizar otra ruta

Sustituye `D:\Proyectos` por tu carpeta real:

```powershell
$projectRoot = 'D:\Proyectos'
New-Item -ItemType Directory -Path $projectRoot -Force

# La guarda permanentemente para tu usuario.
[Environment]::SetEnvironmentVariable('DEV_HOME', $projectRoot, 'User')

# También la activa en la PowerShell que tienes abierta ahora.
$env:DEV_HOME = $projectRoot
```

Comprueba la configuración:

```powershell
Test-Path $env:DEV_HOME
```

Debe devolver `True`. Para cambiarla en el futuro, repite los comandos con la
nueva ruta y abre una PowerShell 7 nueva.

## 2. Instalar DevNav

El repositorio puede clonarse en cualquier ubicación; no tiene que estar dentro
de la carpeta de proyectos:

```powershell
git clone https://github.com/JacobOptimiza/dev-nav.git
Set-Location dev-nav
.\install.ps1
```

El instalador:

1. Detecta si Windows es x64 o ARM64.
2. Descarga el binario desde GitHub Releases.
3. Verifica su checksum SHA-256 antes de instalarlo.
4. Copia DevNav a `%LOCALAPPDATA%\Programs\DevNav`.
5. Añade el módulo al perfil de PowerShell 7 sin modificar el `PATH` global.

Cierra y vuelve a abrir PowerShell 7. Comprueba que quedó instalado:

```powershell
Get-Command dev
Get-DevRoot
dev
```

`Get-Command dev` debe mostrar un alias y `Get-DevRoot` debe mostrar la carpeta
configurada en el paso 1.

### Compilar desde el código fuente

Solo para desarrollo; requiere Rust stable y MSVC Build Tools:

```powershell
.\install.ps1 -BuildFromSource
```

## Favoritos globales, incluso fuera de la raíz

Los favoritos no están limitados a la carpeta principal. Siempre aparecen al
principio de la lista, aunque estés navegando por otra ubicación.

Para añadir una carpeta de otro disco o de fuera de `DEV_HOME`:

1. Ejecuta `dev`.
2. Pulsa `p`.
3. Escribe una ruta absoluta, por ejemplo `D:\Clientes` o `C:\Trabajo\Repo`.
4. Pulsa `Enter` para ir a esa ubicación.
5. Navega con las flechas y `→` hasta resaltar la carpeta deseada.
6. Pulsa `f` para guardarla como favorita.

Desde ese momento aparecerá arriba en cualquier ubicación. Resáltala y vuelve a
pulsar `f` para eliminarla de favoritos. `a` permite mostrarla como
`alias - nombre-de-carpeta`.

Los favoritos y alias son locales y se guardan fuera del repositorio en
`%LOCALAPPDATA%\DevNav\config.tsv`.

## Shortcuts

Los shortcuts están agrupados por flujo de trabajo. Las acciones más frecuentes
aparecen primero para que sean fáciles de descubrir y recordar.

### Navegación y selección

| Shortcut | Acción |
|---|---|
| `↑` / `↓` o `j` / `k` | mover la selección |
| `Enter` | seleccionar la carpeta y volver a PowerShell |
| `→` / `l` | entrar en la carpeta resaltada |
| `←` / `h` | subir al directorio padre |
| `.` | seleccionar el directorio mostrado |
| `g` | volver a la raíz configurada |
| `p` | ir a cualquier ruta absoluta, incluso de otro disco |

### Agentes

| Shortcut | Acción |
|---|---|
| `c` | abrir Codex (`codex`) en la carpeta resaltada |
| `r` | reanudar la última sesión de Codex del repositorio (`codex resume --last`) |
| `d` | abrir Claude Code (`claude`) en la carpeta resaltada |
| `Shift+D` | reanudar la última sesión de Claude Code del repositorio (`claude --continue`) |
| `o` | abrir OpenCode (`opencode`) en la carpeta resaltada |
| `Shift+O` | reanudar la última sesión de OpenCode del repositorio (`opencode --continue`) |
| `i` | abrir Kimi Code (`kimi`) en la carpeta resaltada |
| `Shift+I` | reanudar la última sesión de Kimi Code del repositorio (`kimi --continue`) |

### Organización, búsqueda y acciones

| Shortcut | Acción |
|---|---|
| `/` | activar el filtro fuzzy incremental |
| `f` | añadir o quitar un favorito global |
| `a` | editar el alias de la carpeta resaltada |
| `e` | escribir y ejecutar un comando en la carpeta resaltada |
| `u` | refrescar el directorio mostrado |
| `q` / `Esc` | cancelar y volver a PowerShell |

`:` se conserva como alias compatible de `e` para quienes prefieran el estilo de
comandos de Vim.

También puedes elegir primero el repositorio y pasar un comando desde el shell:

```powershell
dev codex
dev "git status"
```

Los accesos de agentes son opcionales: DevNav devuelve el comando a PowerShell,
por lo que únicamente necesitas tener instalado y disponible en `PATH` el CLI que
quieras abrir.

## Arquitectura

- Rust 2024 y Win32 mediante `windows-sys`.
- Renderer VT propio con buffer de filas y repintado diferencial.
- Entrada raw mediante `ReadConsoleInputW`.
- Event loop sin polling ni renders cuando no hay eventos.
- Protocolo de resultados separado del stdout utilizado por la TUI.
- Sin frameworks TUI y con una sola dependencia directa.

## Seguridad y privacidad

- Sin telemetría ni red durante la ejecución normal.
- Sin credenciales, secretos o configuración personal en el repositorio.
- Binarios de release con checksum SHA-256.
- Workflows con permisos mínimos y acciones fijadas a commits concretos.
- Dependabot revisa Cargo y GitHub Actions.
- `main` está protegida y únicamente los administradores pueden actualizarla.
- El repositorio público es de solo lectura: permite consultar, clonar y descargar,
  pero no acepta Issues ni Pull Requests externos.

Consulta [SECURITY.md](SECURITY.md) para informar vulnerabilidades de forma
privada y [CONTRIBUTING.md](CONTRIBUTING.md) para conocer la política del
repositorio.

## Desarrollo

```powershell
cargo fmt -- --check
cargo test
cargo clippy --all-targets -- -D warnings
cargo build --release
```

## Licencia

MIT. Consulta [LICENSE](LICENSE).
