# Troubleshooting

Esta guía reúne los diagnósticos y soluciones detalladas para DevNav. Para la
instalación inicial y el uso diario, consulta primero el [README](README.md).

## ¿La instalación normal necesita Rust o Visual Studio?

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

## `dev` no se reconoce después de instalar

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

## DevNav abre una carpeta de proyectos incorrecta

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

## Codex, Claude, OpenCode o Kimi muestran «comando no encontrado»

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

## PowerShell bloquea `install.ps1`

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

## Falla la descarga o no coincide el checksum

El instalador cancela la operación si no puede descargar la release o si el hash
del ejecutable no coincide con `SHA256SUMS.txt`. Comprueba la conexión a GitHub,
el proxy o firewall corporativo y vuelve a intentarlo. No omitas la verificación:
un checksum incorrecto puede indicar una descarga incompleta o manipulada.

## La TUI se cierra o las teclas no responden correctamente

Confirma que utilizas PowerShell 7 dentro de Windows Terminal y ejecuta `dev`, no
el `dev.exe` interno. Cierra cualquier instancia anterior, actualiza DevNav y abre
una terminal nueva. Si persiste, anota el mensaje mostrado al volver al prompt y
la salida de:

```powershell
$PSVersionTable.PSVersion
Get-Command dev
Get-DevRoot
```

## ¿Cómo se actualiza DevNav?

Desde el clon local:

```powershell
Set-Location C:\ruta\al\clon\dev-nav
git pull --ff-only
.\install.ps1
```

El instalador puede ejecutarse varias veces: sustituye el binario y el módulo,
verifica nuevamente el checksum y evita duplicar la línea de importación en el
perfil.
