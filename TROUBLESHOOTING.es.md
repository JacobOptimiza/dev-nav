# Troubleshooting

[English](TROUBLESHOOTING.md) | **Español**

Utiliza esta guía cuando la instalación o la ejecución de DevNav muestre un
error. Las respuestas breves y conceptuales están en la sección
[FAQ del README](README.es.md#faq); aquí se documentan únicamente el diagnóstico y
los procedimientos de resolución.

## Diagnóstico rápido

Ejecuta estas comprobaciones desde PowerShell 7:

```powershell
$PSVersionTable.PSVersion
Get-Command dev -ErrorAction SilentlyContinue
Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\DevNav\DevNav.psm1')
```

Si `dev` está disponible, comprueba también la raíz configurada:

```powershell
Get-DevRoot
Test-Path -LiteralPath (Get-DevRoot)
```

## Instalación

### `install.ps1` bloqueado por PowerShell

No desactives globalmente la [política de ejecución de
PowerShell](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies).
Revisa el script y, si confías en esta copia del repositorio, desbloquea
únicamente ese archivo:

```powershell
Get-ExecutionPolicy -List
Get-Content -LiteralPath .\install.ps1
Unblock-File -LiteralPath .\install.ps1
.\install.ps1
```

Si `MachinePolicy` o `UserPolicy` imponen el bloqueo, es una directiva de grupo.
Consulta al administrador del equipo en lugar de intentar evitarla.

### Rust o `cargo` no disponibles al compilar

Este error solo corresponde a `install.ps1 -BuildFromSource`. Para instalar el
binario publicado, ejecuta el instalador sin ese switch:

```powershell
.\install.ps1
```

Si necesitas compilar, instala Rust mediante
[rustup](https://rust-lang.org/tools/install/) y el workload **Desktop
development with C++** de [Visual Studio Build
Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/). Abre una
PowerShell nueva y verifica el entorno antes de repetir la compilación:

```powershell
rustc --version
cargo --version
.\install.ps1 -BuildFromSource
```

### Fallo de descarga o checksum

El instalador cancela la operación si no puede descargar la release o si el hash
del ejecutable no coincide con `SHA256SUMS.txt`.

1. Comprueba el acceso a GitHub desde el navegador.
2. Revisa el proxy o firewall corporativo.
3. Vuelve a ejecutar `install.ps1`.
4. Si el hash vuelve a fallar, no instales el binario ni omitas la verificación.

Un checksum incorrecto puede indicar una descarga incompleta o manipulada.

## Integración con PowerShell

### El alias `dev` no está disponible

DevNav debe cargarse mediante su módulo para poder cambiar la ubicación de la
PowerShell actual. Cierra todas las ventanas de PowerShell 7 y abre una nueva.
Si el alias sigue sin aparecer, ejecuta:

```powershell
$module = Join-Path $env:LOCALAPPDATA 'Programs\DevNav\DevNav.psm1'
Test-Path -LiteralPath $module
Import-Module $module -Force
Get-Command dev
```

- Si `Test-Path` devuelve `False`, vuelve a ejecutar `install.ps1`.
- Si la importación manual funciona, verifica el perfil del host actual:

```powershell
$PSVersionTable.PSVersion
$PROFILE
Test-Path -LiteralPath $PROFILE
```

PowerShell mantiene [perfiles diferentes según el usuario y el
host](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles).
Ejecuta el instalador desde el mismo PowerShell 7 en el que quieras usar `dev`.
No añadas `dev.exe` directamente al `PATH`: omitiría el wrapper necesario.

### Corregir la ruta de inicio

Consulta la ruta efectiva y comprueba que exista:

```powershell
Get-DevRoot
Test-Path -LiteralPath (Get-DevRoot)
```

La forma recomendada es abrir `dev`, resaltar la carpeta correcta, pulsar
`Ctrl+S` y confirmar con `Enter`. Desde PowerShell puedes guardar la misma
configuración con:

```powershell
Set-DevRoot $HOME
Get-DevRoot
```

La carpeta debe existir. Para volver a la carpeta de usuario:

```powershell
Set-DevRoot $HOME
```

`DEV_HOME` se mantiene como fallback de compatibilidad cuando todavía no existe
una ruta guardada. `Ctrl+S` y `Set-DevRoot` tienen prioridad sobre esa variable.

### CLI de agente no encontrado

Comprueba qué agentes están disponibles en la PowerShell actual:

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

Utiliza preferentemente el instalador oficial de cada CLI. Si el ejecutable ya
existe, añade al `PATH` la carpeta que lo contiene, no el archivo `.exe`:

```powershell
$toolDirectory = 'C:\ruta\al\directorio\bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @($userPath -split ';' | Where-Object { $_ })

if ($entries -notcontains $toolDirectory) {
    $updatedPath = (@($entries) + $toolDirectory) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')
}

$env:Path = "$env:Path;$toolDirectory"
```

Repite `Get-Command <nombre>` antes de abrir el agente desde DevNav.

## Ejecución de la TUI

### Cierre inesperado o entrada de teclado incorrecta

1. Utiliza PowerShell 7 dentro de Windows Terminal.
2. Ejecuta `dev`, no el `dev.exe` interno.
3. Cierra cualquier instancia anterior.
4. Actualiza DevNav mediante el canal de instalación que gestiona la copia y
   abre una terminal nueva.

Si el problema persiste, conserva el mensaje mostrado al volver al prompt y la
salida de:

```powershell
$PSVersionTable.PSVersion
Get-Command dev
Get-DevRoot
```

## Mantenimiento

### Cambiar la comprobación al iniciar

Pulsa `Ctrl+U` dentro de la TUI o establece la preferencia desde PowerShell:

```powershell
Set-DevUpdateCheck $true   # activar
Set-DevUpdateCheck $false  # desactivar
```

DevNav sólo pregunta una vez cuando todavía no existe una preferencia. No muestra
nada si la versión instalada ya es la última o falla la red, y nunca instala una
actualización sin confirmación explícita.

### Actualización

Si la instalación está gestionada por Scoop, utiliza `scoop update devnav` en
lugar de `dev update` o `Mayús+U`.

La instalación publicada se actualiza directamente con:

```powershell
dev update
```

El comando informa de la versión instalada y la última publicada, evita una
descarga innecesaria si coinciden y verifica los checksums antes de sustituir
archivos. La ruta de inicio, los favoritos y los alias permanecen en el archivo
de configuración separado y no se sobrescriben. Si `dev update` todavía no
existe porque utilizas una versión anterior
a la 0.5.0, actualiza una vez desde el clon:

```powershell
Set-Location C:\ruta\al\clon\dev-nav
git pull --ff-only
.\install.ps1
```

El instalador puede ejecutarse varias veces: sustituye el binario y el módulo,
verifica nuevamente el checksum y evita duplicar la importación en el perfil.
