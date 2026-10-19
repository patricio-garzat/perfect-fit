# Perfect Fit · juego #4 de BluBer Games

> Las reglas del estudio (marca, logo, preferencias, App Store y landing) están en `../CLAUDE.md`, y Claude las lee automáticamente. Este archivo es solo para lo de **este** juego.

## Estado (18 oct 2026)
- **Prototipo 0.1.0** con 10 niveles jugables. Repo `patricio-garzat/perfect-fit`.
- Se instala en el iPhone del usuario como **"Perfect Fit Dev"** (`tools/dev-install.sh`).
- **Todavía no va a App Store Connect** (pedido del usuario): no hay `release.sh` ni ficha en la landing.

## Concepto
Puzzle espacial tranquilo: amueblar habitaciones en 3D (cámara isométrica) respetando medidas, puertas, ventanas y el espacio que cada mueble necesita. Las reglas se presentan poco a poco. Un nivel puede tener muchas soluciones válidas.

## Diferencias con la plantilla del estudio (decisión del usuario, 18 oct 2026)
- **App nativa:** Swift, SwiftUI y SceneKit. No usa Capacitor y por ahora no hay versión web.
- **SceneKit** (y no RealityKit): Apple ya no le agrega funciones desde 2025, pero funciona en iOS 26. La lógica vive aparte (`Packages/PerfectFitCore`), así que se podría migrar.
- Se mantiene lo del estudio:
  - Intro de BluBer con el logo oficial.
  - Inglés por defecto y español en Ajustes.
  - Sesión de audio `ambient`.
  - Sin emojis.
  - Inicio, Ajustes, Cómo jugar y Récords.
  - Tema Auto/Claro/Oscuro.

## Identidad
- **Paleta** (`App/Theme.swift`):
  - Lino `#F3EEE7`, tinta `#2F2B27` y roble `#A97B50`.
  - Válido en salvia `#7E9A83` e inválido en terracota `#C27C62`.
  - Estrellas en oro cálido `#C9974E`.
  - Nada de los rombos de Cube Swipe.
- **Tipografía:** la del sistema. Los títulos van en serif ligera (New York) y "PERFECT FIT" lleva espaciado amplio.
- **Íconos:** SF Symbols de línea.
- **Ícono de la app:** render del propio juego (el cuarto "Snug" amueblado, sin el armario), hecho con `Render/IconMaker.swift` y `tools/make-icons.sh`.

## Estructura
- `project.yml`: el proyecto se genera con `xcodegen generate`. iOS 17+, solo iPhone y vertical. Equipo `CGW77RJS5Q`.
- **Los recursos van en carpetas separadas en la raíz del bundle** (`Models`, `Textures`, `Levels`, `Intro`). Una carpeta `Resources` en la raíz rompe la firma de iOS.
- `Packages/PerfectFitCore` (sin UIKit), con la lógica:
  - `Grid` (celdas de 50 cm y rotaciones) y `Catalog` (muebles: tamaño, pared atrás, alto, zonas de uso, preferencia).
  - `Level` (JSON) y `Layout.evaluate()` (reglas, armonía y circulación).
  - `Solver` (búsqueda con poda, reinicios aleatorios y `find(stars:)`).
  - Ejecutable `pf-levels`.
- `PerfectFit/` (la app):
  - `App/`: estado, guardado y textos en/es.
  - `Game/GameSession.swift`: acciones y pistas.
  - `Render/`: `SceneController` (cámara, arrastre, overlays), `RoomBuilder` (cuarto tipo maqueta), `FurnitureModels`, `Materials`, `Thumbnails` e `IconMaker`.
  - `UI/` (SwiftUI) y `Audio/` (sonido sintetizado y Core Haptics).
- `tools/assets/`: `fetch.py` (descarga de Poly Haven) y `pipeline.swift` (USD → `.scn` ligeros).

## Reglas del juego (`Layout.evaluate`)
- **Siempre:**
  - Dentro del cuarto y sin encimarse. Las alfombras son "piso": se pueden poner muebles encima, pero no otra alfombra.
  - Libre el barrido de la puerta (2×2 frente a cada puerta).
  - Respaldo contra la pared en camas, burós, armarios, cómodas, libreros, escritorios y sofás.
- **Por nivel (`rules` en el JSON):**
  - `clearance`: zonas de uso libres. La cama necesita un lado, el armario su frente y la silla espacio atrás. El escritorio deja entrar una silla en su zona, y el sofá y el sillón una mesa de centro.
  - `access`: a cada zona de uso se llega caminando desde la puerta.
  - `windows`: nada alto frente a una ventana, y el escritorio junto a una.
- **Estrellas:**
  - ★ Todo cabe.
  - ★ Armonía: cada mueble cumple su preferencia (buró junto a la cabecera, silla frente al escritorio, mesa de centro frente a un asiento, lámpara junto a asiento, escritorio o cama, planta en la luz de la ventana o en una esquina, alfombra bajo la cama o frente a un asiento, cama doble con los dos lados libres).
  - ★ Circulación: todo el piso libre se alcanza desde la puerta.
  - No depende del tiempo y mover muebles no penaliza.
- **Pistas:** se empieza con 3 y se gana 1 con cada nivel nuevo de 3 estrellas. El solver busca una solución que respete lo que ya está bien puesto y mueve un mueble.

## Niveles (`PerfectFit/Resources/Levels/NN.json`)
- **Formato:** `shape` (filas con `#` piso, `.` fuera y `X` columna), `doors` y `windows` (`cell`, `side` N/E/S/W, `width`), `pieces`, `rules`, `style` (`oak`/`linen`/`walnut`) y `hint` en/es.
- **Para diseñar:** `cd Packages/PerfectFitCore && swift run -c release --scratch-path /tmp/pfspm pf-levels ../../PerfectFit/Resources/Levels [ids]`. Imprime cuántas soluciones hay (1★/2★/3★) y el plano de la mejor. `PF_SECONDS` cambia el límite.
- **Pruebas:** `swift test -c release` en el paquete comprueba que hay 10 niveles bien formados, cada uno con solución y con solución de 3★.
- En esta Mac, SwiftPM y xcodebuild fallan con "disk I/O error" si su carpeta de build está dentro del Escritorio. Usa `--scratch-path` o `-derivedDataPath` en `/tmp`.

## Probar
- **Simulador:** abre `PerfectFit.xcodeproj` en Xcode, o usa xcodebuild con el destino `iPhone 17`. Atajos al lanzar: `-pfLevel N` abre un nivel, `-pfHome` se salta la intro y `-pfTheme dark|light`.
- **iPhone:** `tools/dev-install.sh` compila en Release, firma con la clave de API del estudio e instala "Perfect Fit Dev".
