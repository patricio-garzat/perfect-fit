# Perfect Fit · fuentes de los assets

Todo lo que viene de fuera es **CC0** (dominio público). Se puede usar comercialmente y redistribuir dentro del juego, y no pide crédito.

- **Licencia de Poly Haven** (revisada el 18 oct 2026, https://polyhaven.com/license): *"Our assets are all licensed as CC0, which is effectively Public Domain"*. Cubre modelos, texturas y HDRIs. El sitio en sí (logos, renders, textos) no es CC0, y no usamos nada de eso.
- **Descarga:** 18 oct 2026, desde la API oficial (`api.polyhaven.com`, servidor `dl.polyhaven.org`), con verificación MD5 de cada archivo. Los originales quedan en `assets-src/polyhaven/`, fuera del repo (pesan 54 MB). `tools/assets/fetch.py` los vuelve a bajar.
- **Lo que va dentro de la app** sale de `tools/assets/pipeline.swift`: geometría unida y normalizada en `.scn` y texturas JPG/PNG a 1k o 512 px, en `PerfectFit/Resources/Models/`. Las texturas de cuarto y muebles a medida están en `PerfectFit/Resources/Textures/`.

## Modelos 3D (Poly Haven, CC0)

| En el juego | Asset | Autor | URL |
|---|---|---|---|
| Sillón (`armchair`) | Mid Century Lounge Chair | Kuutti Siitonen | https://polyhaven.com/a/mid_century_lounge_chair |
| Mesa de centro (`coffee_table`) | Modern Coffee Table 01 | Amin | https://polyhaven.com/a/modern_coffee_table_01 |
| Mesa redonda (`round_table`) | Coffee Table Round 01 | Ulan Cabanilla | https://polyhaven.com/a/coffee_table_round_01 |
| Librero (`bookcase`) | Wooden Display Shelves 01 | James Ray Cock | https://polyhaven.com/a/wooden_display_shelves_01 |
| Cómoda (`dresser`) | Vintage Wooden Drawer 01 | James Ray Cock | https://polyhaven.com/a/vintage_wooden_drawer_01 |
| Planta (`plant`): maceta | Potted Plant 04 (solo la maceta y la tierra) | James Ray Cock | https://polyhaven.com/a/potted_plant_04 |
| Planta (`plant`): hojas | Calathea Orbifolia 01 (variante 1) | Rob Tuytel, Rico Cilliers | https://polyhaven.com/a/calathea_orbifolia_01 |
| Suculenta (decoración de la cómoda) | Potted Plant 04 | James Ray Cock | https://polyhaven.com/a/potted_plant_04 |
| Florero (decoración de la cómoda) | Ceramic Vase 01 | James Ray Cock | https://polyhaven.com/a/ceramic_vase_01 |

**Descargados pero sin usar** (no combinan con el estilo contemporáneo; están en `assets-src/`, no en la app): Sofa 02 (Kirill Sannikov), Classic Nightstand 01 (Kirill Sannikov), Side Table 01 (James Ray Cock), Round Wooden Table 02 (Ulan Cabanilla), Dining Table (Aron Łyczek), Dining Chair 02 (James Ray Cock), Metal Office Desk (Ulan Cabanilla) y Shelf 01 (Gabriel Radić).

## Texturas PBR (Poly Haven, CC0)

| Uso | Asset | Autor | URL |
|---|---|---|---|
| Piso | Wood Floor | Dimitrios Savva | https://polyhaven.com/a/wood_floor |
| Muros (relieve; el color lo pone el juego) | White Plaster 02 | Rob Tuytel | https://polyhaven.com/a/white_plaster_02 |
| Ropa de cama, cojines (relieve) | Rough Linen | colormass, Rico Cilliers | https://polyhaven.com/a/rough_linen |
| Sofá, alfombras (relieve) | Wool Boucle | colormass, Rico Cilliers | https://polyhaven.com/a/wool_boucle |
| Madera de los muebles a medida y la puerta | White Oak Veneer | Jenelle van Heerden | https://polyhaven.com/a/white_oak_veneer |

## Iluminación (Poly Haven, CC0)

| Uso | Asset | Autor | URL |
|---|---|---|---|
| Luz ambiental (IBL) | White Home Studio (HDRI 1k) | Grzegorz Wronkowski | https://polyhaven.com/a/white_home_studio |

## Hecho en el proyecto

- **Muebles modelados por código** (`Render/FurnitureModels.swift`): camas, buró con lámpara, armario, escritorio, silla, sofá, lámpara de pie, alfombras y los libros del librero. Usan las texturas de arriba.
- **Habitación** (`Render/RoomBuilder.swift`): piso, muros, puertas, ventanas, columnas y luz de ventana.
- **Sonidos:** todos sintetizados en `Audio/Sound.swift`. No hay archivos de audio.
- **Ícono:** render del propio juego (`Render/IconMaker.swift`).
- **Logo de BluBer** (intro): el oficial del estudio, copiado sin cambios de la intro de Cube Swipe (`Resources/Intro/studio.html`).
