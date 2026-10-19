# Perfect Fit

**Perfect Fit** es un puzzle espacial tranquilo de BluBer Games para iPhone: amuebla pequeñas habitaciones en 3D para que todo quepa, se pueda usar y se llegue a todo desde la puerta.

Es una app nativa, hecha con Swift, SwiftUI y SceneKit. No necesita internet, no tiene anuncios ni compras y no usa cuentas.

## Abrir y compilar

1. Necesitas Xcode 26 o más reciente.
2. Abre `PerfectFit.xcodeproj` y elige el esquema **PerfectFit** y un simulador de iPhone.
3. Presiona Run. El proyecto se genera desde `project.yml` con `xcodegen generate`.

## Instalar en tu iPhone (sin App Store)

```bash
tools/dev-install.sh
```

El script compila en modo Release, firma con el equipo del estudio e instala **"Perfect Fit Dev"** en el iPhone conectado. Es una app aparte, con la franja DEV en el ícono.

Antes de correrlo:
- El iPhone debe estar desbloqueado, con el Modo de desarrollador activo, y confiar en esta Mac.
- La firma usa la clave de API del estudio que está en `~/.appstoreconnect/`.

Si prefieres hacerlo desde Xcode:
1. Abre el proyecto y elige tu iPhone como destino.
2. En *Signing & Capabilities* revisa que el equipo sea **Patricio Garza T (CGW77RJS5Q)**.
3. Presiona Run.

## Pruebas

Comprueban que los 10 niveles existen, están bien formados, tienen solución y se pueden ganar con 3 estrellas:

```bash
cd Packages/PerfectFitCore && swift test -c release --scratch-path /tmp/pfspm
```

## Herramienta de niveles

Imprime cuántas soluciones tiene cada nivel y el plano de la mejor:

```bash
cd Packages/PerfectFitCore && swift run -c release --scratch-path /tmp/pfspm pf-levels ../../PerfectFit/Resources/Levels
```

## Assets

Los modelos, texturas y el HDRI son de Poly Haven, con licencia CC0. La lista completa está en [ASSET_SOURCES.md](ASSET_SOURCES.md). Los sonidos se sintetizan en el código.
