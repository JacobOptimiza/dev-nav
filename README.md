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

## FAQ y solución de problemas

### ¿La instalación normal necesita Rust o Visual Studio?

No. `install.ps1` descarga el binario correcto para Windows x64 o ARM64 y
comprueba su checksum SHA-256 antes de instalarlo. No uses `-BuildFromSource` si
solo quieres utilizar DevNav.

Rust y MSVC Build Tools únicamente son necesarios para compilar. En ese caso,
instala Rust mediante [rustup](https://rust-lang.org/tools/install/) y el workload
**Desktop development with C++** de
[Visual Studio Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/).
Después, abre una PowerShell nueva y comprueba:

```powershell
rustc --version
cargo --version
.\install.ps1 -BuildFromSource
```

El instalador detecta si falta `cargo` y muestra un error antes de intentar
compilar.

### `dev` no se reconoce después de instalar

DevNav no añade `dev.exe` al `PATH`. Instala un módulo de PowerShell que crea el
alias `dev`; este wrapper es necesario para que la carpeta seleccionada se
convierta en la ubicación de la PowerShell actual.

Primero, cierra todas las ventanas de PowerShell 7 y abre una nueva. Si continúa
sin aparecer, ejecuta:

```powershell
$module = Join-Path $env:LOCALAPPDATA 'Programs\DevNav\DevNav.psm1'
Test-Path -LiteralPath $module
Import-Module $module -Force
Get-Command dev
```

Si `Test-Path` devuelve `False`, vuelve a ejecutar `install.ps1`. Si la importación
manual funciona, comprueba que estás usando PowerShell 7 (`pwsh`) y que su perfil
se carga al iniciar:

```powershell
$PSVersionTable.PSVersion
$PROFILE
Test-Path -LiteralPath $PROFILE
```

PowerShell mantiene [perfiles diferentes según el usuario y el
host](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles).
Ejecuta el instalador desde el mismo PowerShell 7 en el que quieras usar `dev`.

### DevNav abre una carpeta de proyectos incorrecta

Comprueba primero el valor efectivo:

```powershell
Get-DevRoot
Test-Path -LiteralPath (Get-DevRoot)
```

Para corregirlo de forma persistente y aplicarlo también a la sesión actual:

```powershell
$newRoot = (Resolve-Path -LiteralPath 'D:\Proyectos').Path
[Environment]::SetEnvironmentVariable('DEV_HOME', $newRoot, 'User')
$env:DEV_HOME = $newRoot
Get-DevRoot
```

La carpeta debe existir antes de usar `Resolve-Path`. Para recuperar la ruta
predeterminada `$HOME\programacion`:

```powershell
[Environment]::SetEnvironmentVariable('DEV_HOME', '', 'User')
Remove-Item Env:DEV_HOME -ErrorAction SilentlyContinue
```

El valor con alcance `User` persiste para futuras terminales; `$env:DEV_HOME`
solo cambia el proceso actual. Consulta la documentación de
[variables de entorno de PowerShell](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_environment_variables)
para conocer los distintos alcances.

### Codex, Claude, OpenCode o Kimi muestran «comando no encontrado»

Los agentes son opcionales y no los instala DevNav. Comprueba cuáles están
disponibles en la PowerShell actual:

```powershell
'codex', 'claude', 'opencode', 'kimi' | ForEach-Object {
    $command = Get-Command $_ -ErrorAction SilentlyContinue
    [pscustomobject]@{
        CLI        = $_
        Disponible = [bool] $command
        Ruta       = $command.Source
    }
}
```

Utiliza preferentemente el instalador oficial de cada CLI, que normalmente
configura el `PATH`. Si el ejecutable ya existe pero su carpeta no está incluida,
añade **la carpeta que contiene el ejecutable**, no el archivo `.exe`:

```powershell
$toolDirectory = 'C:\ruta\al\directorio\bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @($userPath -split ';' | Where-Object { $_ })

if ($entries -notcontains $toolDirectory) {
    $updatedPath = (@($entries) + $toolDirectory) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')
}

# Lo activa también en esta PowerShell.
$env:Path = "$env:Path;$toolDirectory"
```

Después, repite `Get-Command <nombre>` antes de abrir el agente desde DevNav.

### PowerShell bloquea `install.ps1`

No desactives globalmente la [política de ejecución de
PowerShell](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies).
Revisa primero el script y, si confías en esta copia del repositorio, desbloquea
únicamente ese archivo:

```powershell
Get-ExecutionPolicy -List
Get-Content -LiteralPath .\install.ps1
Unblock-File -LiteralPath .\install.ps1
.\install.ps1
```

Si `MachinePolicy` o `UserPolicy` imponen el bloqueo, es una directiva de grupo:
consulta al administrador del equipo en lugar de intentar evitarla.

### Falla la descarga o no coincide el checksum

El instalador cancela la operación si no puede descargar la release o si el hash
del ejecutable no coincide con `SHA256SUMS.txt`. Comprueba la conexión a GitHub,
el proxy o firewall corporativo y vuelve a intentarlo. No omitas la verificación:
un checksum incorrecto puede indicar una descarga incompleta o manipulada.

### La TUI se cierra o las teclas no responden correctamente

Confirma que utilizas PowerShell 7 dentro de Windows Terminal y ejecuta `dev`, no
el `dev.exe` interno. Cierra cualquier instancia anterior, actualiza DevNav y abre
una terminal nueva. Si persiste, anota el mensaje mostrado al volver al prompt y
la salida de:

```powershell
$PSVersionTable.PSVersion
Get-Command dev
Get-DevRoot
```

### ¿Cómo se actualiza DevNav?

Desde el clon local:

```powershell
Set-Location C:\ruta\al\clon\dev-nav
git pull --ff-only
.\install.ps1
```

El instalador puede ejecutarse varias veces: sustituye el binario y el módulo,
verifica nuevamente el checksum y evita duplicar la línea de importación en el
perfil.

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
