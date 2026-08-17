# DevNav

**Salta entre tus espacios de trabajo en Windows, lanza agentes de código y ejecuta comandos de proyecto sin salir de PowerShell.**

[![CI](https://github.com/JacobOptimiza/dev-nav/actions/workflows/ci.yml/badge.svg)](https://github.com/JacobOptimiza/dev-nav/actions/workflows/ci.yml)
[![CodeQL](https://github.com/JacobOptimiza/dev-nav/actions/workflows/codeql.yml/badge.svg)](https://github.com/JacobOptimiza/dev-nav/actions/workflows/codeql.yml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14088/badge)](https://www.bestpractices.dev/projects/14088)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/JacobOptimiza/dev-nav/badge)](https://scorecard.dev/viewer/?uri=github.com/JacobOptimiza/dev-nav)
[![Windows](https://img.shields.io/badge/Windows-x64%20%7C%20ARM64-0078D4)](https://github.com/JacobOptimiza/dev-nav/releases/latest)
[![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Rust 1.97+](https://img.shields.io/badge/Rust-1.97%2B-orange?logo=rust&logoColor=white)](https://www.rust-lang.org/tools/install)
[![npm](https://img.shields.io/npm/v/@jacoboptimiza/devnav?logo=npm)](https://www.npmjs.com/package/@jacoboptimiza/devnav)
[![Licencia: MIT](https://img.shields.io/badge/licencia-MIT-blue.svg)](LICENSE)

[English](README.md) | **Español**

DevNav es una TUI nativa en Rust, rápida y orientada al teclado, para quienes trabajan con muchos repositorios. Encuentra un espacio de trabajo con búsqueda difusa, entra directamente, lanza o reanuda un agente de código o ejecuta un comando de proyecto guardado en unas pocas teclas.

**[Instalar](#instalar) · [Inicio rápido](#inicio-rápido) · [Flujo de trabajo](#hecho-para-tu-flujo-de-trabajo-en-terminal) · [Seguridad](#seguridad-por-defecto) · [Documentación](#documentación-del-proyecto)**

![Interfaz animada de DevNav en terminal](assets/demo/devnav.gif)

## Por qué DevNav

- **Salta más rápido** — encuentra proyectos con búsqueda difusa sin memorizar rutas ni recorrer árboles de carpetas.
- **Mantén el contexto cerca** — favoritos globales y alias dejan tus espacios de trabajo habituales a una sola acción.
- **Lanza donde trabajas** — inicia o reanuda Codex, Claude Code, OpenCode y Kimi directamente en el repositorio seleccionado.
- **Automatiza lo repetitivo** — asigna hasta nueve comandos de proyecto a `Shift+1–9`.
- **Sigue siendo nativo** — Rust + Win32, una única dependencia directa, sin framework TUI y sin runtime de aplicación después de instalar.

## Instalar

### PowerShell

```powershell
irm https://raw.githubusercontent.com/JacobOptimiza/dev-nav/main/install.ps1 | iex
```

O usa la herramienta de paquetes que ya tengas:

| Canal | Comando |
|---|---|
| Scoop | `scoop bucket add jacoboptimiza https://github.com/JacobOptimiza/scoop-bucket; scoop install jacoboptimiza/devnav` |
| npm | `npx --yes @jacoboptimiza/devnav install` |
| Bun | `bunx --bun @jacoboptimiza/devnav install` |
| pnpm | `pnx @jacoboptimiza/devnav install` |
| Yarn | `yarn dlx -p @jacoboptimiza/devnav devnav install` |

También puedes descargar el instalador oficial x64 o ARM64 desde la [última release de GitHub](https://github.com/JacobOptimiza/dev-nav/releases/latest).

Los comandos de los gestores son canales de instalación, no una versión JavaScript de DevNav. Después de instalar usa `dev update`; las instalaciones gestionadas por Scoop se actualizan con `scoop update devnav`.

## Inicio rápido

Abre una nueva sesión de PowerShell 7 y ejecuta:

```powershell
dev
```

Elige el espacio de trabajo que quieres abrir por defecto y pulsa `Ctrl+S` una vez. A partir de ahí, todo sigue un flujo orientado al teclado:

| Tecla | Acción |
|---|---|
| `/` | Filtrar espacios de trabajo |
| `Enter` | Saltar al directorio seleccionado |
| `f` / `a` | Favorito / alias |
| `c` / `r` | Codex nuevo / reanudar |
| `d` / `Shift+D` | Claude Code nuevo / reanudar |
| `o` / `Shift+O` | OpenCode nuevo / reanudar |
| `i` / `Shift+I` | Kimi nuevo / reanudar |
| `Shift+1–9` | Ejecutar un comando guardado |
| `F3` | Gestionar comandos personalizados |
| `F1` | Ayuda completa de teclado |

Pulsa `F2` para cambiar entre English y Español.

## Hecho para tu flujo de trabajo en terminal

- **Favoritos globales** disponibles incluso fuera del directorio inicial o al moverte entre unidades.
- **Aliases legibles** que añaden un nombre amigable sin ocultar el repositorio o comando real.
- **Búsqueda difusa rápida** para filtrar árboles grandes sin salir de la TUI.
- **Acciones siempre en contexto** — agentes y comandos se lanzan dentro del directorio seleccionado.
- **Actualizaciones sencillas** — usa `Shift+U` en la TUI o `dev update` desde PowerShell.

Los alias de repositorio mantienen visible la identidad real:

```text
Navegador PowerShell | dev-nav
```

Los comandos personalizados hacen lo mismo con la acción ejecutada:

```text
Lanzar servidor > bun run dev
```

## Agentes de código

DevNav puede lanzar o reanudar **Codex, Claude Code, OpenCode y Kimi** directamente en el repositorio seleccionado.

Codex, Claude y OpenCode mantienen un título `Agente/repo` durante la sesión. Kimi usa actualmente su propio título de sesión; DevNav restaura el título anterior del terminal cuando Kimi termina.

Las CLI de los agentes son opcionales y deben estar instaladas y disponibles en `PATH`.

## Comandos personalizados

Guarda hasta nueve comandos de proyecto y ejecútalos con `Shift+1–9`. Pulsa `F3` para crearlos, editarlos o eliminarlos.

```powershell
dev shortcut 1 "Tests" "cargo test"
dev shortcut 2 "Dev" "bun run dev"
```

Los alias siguen siendo fáciles de leer sin ocultar lo que realmente se ejecuta, y las asignaciones permanecen en la configuración local de DevNav.

## Seguridad por defecto

- **Sin telemetría.** El acceso de red se limita a instalación, comprobaciones de releases y actualizaciones explícitas.
- Las descargas se comprueban contra **metadatos SHA-256 de la release** antes de instalar o actualizar.
- El pipeline de release usa **firmas Sigstore keyless, attestations de build de GitHub y provenance in-toto**.
- La publicación en npm usa **OIDC Trusted Publishing** sin ningún `NPM_TOKEN` persistente.
- GitHub Actions usa **permisos mínimos y acciones fijadas por commit**, con reporte privado para vulnerabilidades sensibles.

Consulta [SECURITY.md](SECURITY.md) para la política de seguridad y [SIGNING.md](SIGNING.md) para verificar releases.

## Requisitos

- Windows 10 u 11 en x64 o ARM64.
- PowerShell 7 o posterior.
- Windows Terminal recomendado.

Los binarios publicados no necesitan Rust, Visual Studio, Node.js ni Bun en tiempo de ejecución. Node.js o Bun sólo son necesarios si eliges uno de esos canales de instalación.

## Documentación del proyecto

| Documento | Contenido |
|---|---|
| [TROUBLESHOOTING.es.md](TROUBLESHOOTING.es.md) | Diagnóstico de instalación y ejecución |
| [SECURITY.md](SECURITY.md) | Política de seguridad y reporte de vulnerabilidades |
| [SIGNING.md](SIGNING.md) | Firmas y verificación de releases |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Arquitectura interna y límites de confianza |
| [ASSURANCE.md](ASSURANCE.md) | Assurance basado en evidencias |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Desarrollo, pruebas y política de releases |
| [ROADMAP.md](ROADMAP.md) | Distribución y trabajo futuro |

## Licencia

MIT. Consulta [LICENSE](LICENSE).
