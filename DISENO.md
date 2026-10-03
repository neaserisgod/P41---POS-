# Sistema de diseño — La Plazoleta

**Este documento es la fuente de verdad de las REGLAS y VALORES del sistema
de diseño** (qué escala existe, qué significa cada rol, qué está prohibido
y por qué). La fuente de verdad EJECUTABLE — el número real que corre hoy —
es el código: `lib/ui/tema/tokens.dart` (espaciado/tipografía/medidas de
layout), `lib/ui/tema/colores_escritorio.dart` (paleta),
`lib/ui/tema/acentos.dart` (familia de acentos), `lib/ui/tema/tema.dart`
(cómo se arman los `ThemeData`), `lib/ui/tema/superficie.dart` (el widget
`Superficie`, la unidad visual del estilo) y
`lib/ui/navegacion/navbar_superior.dart` (la navegación). Si este documento
y el código alguna vez difieren en un número, gana el código — pero eso
significa que este documento quedó desactualizado y hay que corregirlo en
el mismo cambio.

Para saber qué pantallas ya tienen esto aplicado y cuáles no, ver
`ESTADO.md` — ese dato cambia seguido y no se duplica acá.

**Estética horsepos.com / antigravity (2026-10-02/03) — vigente, manda sobre todo lo de abajo.**
Es lo más reciente y lo que corre hoy (PR #24, #50 y `docs/ESTANDARES-GOOGLE.md`):

- **Paleta** (`colores_escritorio.dart`, la misma en el celular): fondo blanco `#FFFFFF`, bloques `#F3F4F7` sin
  sombra, borde `#D5D8DF`, tinta `#121317` como texto y como **único acento** (botón principal, pastilla activa),
  error `#C5221F`. Oscuro: fondo `#0E0F12`, bloques `#14161C`, acento blanco.
- **Colores con significado** (`acentos.dart`): efectivo `#B45309`, QR `#3B6CFF`, Débito `#0E9F85`, Mixto
  `#8A5CF6`, ganancia `#0E7C5A`, alerta `#9A4A06` sobre `#FFF1DC`. Fuera de eso, nada de color.
- **Figtree**, títulos grandes y livianos, poco texto; botones y selectores en pastilla.
- **Navegación (PC, 2026-10-03):** Venta es la pantalla principal (arranca ahí; la tecla Inicio vuelve ahí; el
  tablero "Inicio" es una sección más). Navbar sin marca, con las secciones como pastillas **centradas en la
  ventana**, Configuración como engranaje a la derecha y la búsqueda como **lupa** (Ctrl+F): al abrirse, el campo
  tapa las pastillas; al cerrarse vuelve vacío. En Venta la búsqueda no va en la lupa: es el campo único, siempre a
  la vista, y Ctrl+F lo enfoca. Cambios de pantalla con un fundido corto (98% → 100%), sin desplazamiento lateral.
- Los números exactos (radios, espaciado) están en `lib/ui/tema/`: si este texto y el código difieren, gana el código.

**Movimiento (2026-10-03) — vigente.** El dueño: "las animaciones son una miseria"; eligió animar todo, también la
pantalla de venta, con animaciones cortas. Dos piezas en `lib/ui/tema/movimiento.dart`, todo dura menos de un quinto de
segundo y respeta "reducir animaciones" del sistema (`MediaQuery.disableAnimations`):

- `Entrada`: lo que aparece sube unos px y se funde, una vez; en listas, escalonado (`entradaEnLista`, solo las
  primeras 12 filas: lo que aparece al scrollear no se demora).
- `Pulso`: un latido mínimo cuando cambia un valor; el texto nuevo ya está desde el primer cuadro.
- Dónde: cambio de pantalla (sube, crece y la de abajo se atenúa), diálogos del kit (`Modal`, zoom desde 0,96), lista
  de la búsqueda de Venta (cae al abrirse), líneas del carrito (entran; laten al cambiar la cantidad), total (late) y
  desglose (aparece suave), botón del medio de pago (el color llena con transición y late al elegirlo), venta cobrada
  (tilde y zoom), tarjetas de Inicio y listas de Proveedores, Historial, cierres y Configuración (escalonadas).
- Nunca: algo que demore el foco, lo que se tipea o el cobro.

**"Lenguaje de diseño" (2026-09-26/28) — reemplazado en paleta y navegación por el bloque de arriba.** Se conserva
por los mocks y las distribuciones, que siguen valiendo. El dueño dejó en `Lenguaje de diseño/` (raíz del repo) mocks `.dc.html` de
escritorio y celular más un LEEME con tokens: son **medio inspiración, pero
la distribución de cada pantalla es la idea**. Lo que cambió respecto de las
secciones de más abajo (que describen el remake del 2026-09-19 y todavía no
se reescribieron una por una):

- **Fuente**: Figtree 400/500/600/700 (`Pesos.regular`/`medium`=600/`fuerte`=700).
- **Paleta** (`colores_escritorio.dart`, compartida con el celular): canvas
  `#F0F4F9`, tarjeta `#FFFFFF`, texto `#1F1F1F`/`#444746`/`#5E5E5E`, acento
  azul `#0B57D0`, error `#B3261E`; oscuro derivado a mano con el mismo hue.
- **Colores con significado** (`acentos.dart`): efectivo naranja `#B45309`,
  Mercado Pago azul (QR `#0B57D0`, Débito `#00639B`), Mixto violeta,
  ganancia verde `#146C2E`, alerta marrón sobre crema.
- **Superficie plana**: sin sombra, sin borde, sin brillo de vidrio, radio
  20. Pieza destacada (total, acción principal) = tarjeta casi negra en
  claro, azul de acento en oscuro. Halos (`resplandorNeon`) apagados.
- **Botones** con forma de pastilla; selectores como grupo de pastillas
  (`GrupoPildoras`). Modales opacos con sombra suave (sin blur).
- **Encabezado**: el título grande se sacó (el nombre de la pantalla es el
  botón del menú de secciones); a la izquierda una línea de contexto, a la
  derecha las acciones.
- **Kit** (`lib/ui/comun/tarjetas.dart`): `TarjetaIndicador`,
  `TarjetaSeccion`, `CajaCifra`, `FilaMedio`, `FilaSuave`, `Insignia`,
  `BarraDividida`, `FilaRanking`, `BloqueSuave`, `AvatarIniciales`,
  `PuntoColor`; más `grafico_por_hora.dart` y `fechas.dart`. El celular
  usa las mismas piezas.
- **Distribuciones**: Inicio = fila de 4 indicadores + gráfico por hora
  y medios + 3 tarjetas abajo; Proveedores e Historial = lista + detalle;
  Separaciones = tarjetas por caja arriba y grilla de proveedores.

**Remake completo de la estética (2026-09-19, en curso por fases — ver el
plan en curso y `ESTADO.md` para el avance real):** El dueño pidió rehacer
toda la estética del escritorio basándose en la de la companion
(`lib/companion/`), con fidelidad completa, y reemplazar la barra lateral
por una navbar horizontal arriba. Este documento se está reescribiendo
sección por sección, en el mismo cambio que reescribe el código de cada
fase — no todo de una vez. Las secciones ya reescritas dicen "(remake
2026-09-19)" en su título; las que todavía no llegaron su turno (Venta,
"Bento con carácter") siguen documentando el sistema viejo hasta que la
fase que las toca las actualice. **La pantalla de Venta es una excepción
de layout, no de estética**: su disposición de 3 columnas sin scroll no
cambia (regla de negocio — mostrador con cliente esperando), pero sus
colores/tipografía/radios sí se actualizan como cualquier pantalla.

---

## Principio rector: evitar fatiga visual

El dueño mira esta pantalla doce horas por día, seis días por semana. Esa es
la vara de **toda** decisión de diseño de esta app, no solo de la pantalla
de venta — el principio del que se desprenden las demás reglas de este
documento, no una más entre ellas. **Cuando dos criterios choquen, gana el
que cansa menos la vista.**

En concreto, en cada pantalla:

1. **Ninguna línea de texto cruza la pantalla entera.** Es lo que más
   cansa: el ojo no debería tener que barrer 1900px para conectar una
   etiqueta con su valor. Toda fila, formulario o tabla tiene un ancho
   máximo (`Medidas.anchoMaximoContenido`) — "plata a la derecha, tabular,
   ancho fijo" sigue valiendo, cambia contra qué borde está esa derecha:
   el del contenido acotado, no el de la pantalla.
2. **La escala tipográfica sube, entera y proporcional.** Texto chico
   obliga a forzar la vista — El dueño ya se quejó de no leer de lejos. Nunca
   un tamaño suelto para "arreglar" una pantalla puntual: si hace falta
   subir, sube la escala entera (ver "Escala tipográfica" abajo).
3. **Aire, no densidad.** La densidad extrema (del carrito, o de cualquier
   lista) fue una regla escrita para 720px de alto. Con 1080 sobra
   espacio: apretar cuando no hace falta es exactamente lo que cansa.
4. **Nada se mueve sin que el dueño lo haya pedido.** Cada transición
   responde a una acción suya. Ningún parpadeo, nada que aparezca o
   cambie solo mientras está cobrando.
5. **La misma cosa en el mismo lugar en todas las pantallas.** Buscar
   dónde está algo es fatiga también. Un título, una lista, un valor, un
   botón de acción se ubican igual en las nueve pantallas de gestión —
   esto es la mitad del sentido de la fase 13.
6. **Lo que ya está bien no se toca**: el contraste medido a propósito
   (nunca blanco puro sobre negro puro), los tres usos exactos del acento,
   y una sola escala de espaciado — ver "Filosofía" y "Colores" abajo.
   Bajar más el contraste no descansa la vista, la fuerza.

El tema automático sigue al sistema (decisión del dueño, 2026-10-03; antes era por
horario del local, 10 a 22): usa el modo claro u oscuro que tenga Windows. Está prendido
por default; tocar el switch manual de "Modo oscuro" en Configuración deja de seguir al
sistema. Esto es una medida de la prioridad de ojos cansados, no una comodidad.

**Primera aplicación — la pantalla de venta**: barra lateral plegable,
productos en cards, "imprimir" solo al final del cobro, y la columna de
búsqueda más ancha (`Medidas.anchoColumnaBusquedaVenta`) a costa del
sobrante del carrito. Las nueve pantallas de gestión se revisan contra las
seis reglas de arriba, una por una, antes de darlas por terminadas — ver
`ESTADO.md` para el avance real.

## Principio rector: tres niveles de información

Mismo principio de arriba, mirado desde la información en vez de desde el
espacio en pantalla. El dueño, textual: *"al entrar al menú me muestre toda la
información resumida, no el detalle, eso agobia... recién ahí un menú
avanzado, pero la simplicidad debe ser máxima"*. La vara: **si al abrir una
pantalla hay que leer para encontrar lo que importa, está mal.**

Tres niveles, siempre en el mismo orden:

1. **Al entrar a una sección: solo el resumen.** Una línea por elemento,
   con las pocas cifras que importan — nada de estados, configuración ni
   estadísticas secundarias mezcladas en la misma fila.
2. **Al entrar a un elemento: el detalle.** Lo que se consulta o edita
   seguido — el trabajo real de esa pantalla vive acá, no en el nivel 1.
3. **Detrás de un botón "Avanzado": el resto.** Lo que se toca una vez por
   año (códigos, días de configuración, activar/desactivar) no ocupa lugar
   el resto del año. Mismo lugar en todas las pantallas: un botón al pie
   del nivel 2, nunca una pestaña ni un menú aparte — abre un diálogo
   simple con esos campos y un botón "Guardar".

Encaja sobre el patrón lista + detalle ya existente (más abajo), no lo
reemplaza: el nivel 1 es la columna de lista (`Medidas.anchoListaMaestra`),
el nivel 2 es el bloque de detalle, el nivel 3 es el diálogo "Avanzado" que
ese bloque de detalle abre.

**Primera aplicación — Proveedores** (reemplaza a Reposición), en su forma
actual tras DOS correcciones post-revisión sobre la primera versión. Estado
real (lo que hay que construir igual en Productos):

- **Nivel 1 — la lista: solo nombre**, angosta
  (`Medidas.anchoListaMaestra`, 360). Nada de cifras — son del proveedor
  ELEGIDO, no de todos a la vez (segunda corrección: la primera versión
  ponía cuatro cifras acá, y "eso agobia" repetía exactamente lo que este
  principio existe para evitar). Los proveedores sin venta en el período
  van al final de la lista y se pintan en `colores.textoTenue` en vez de
  `colores.textoPrimario` — siguen ahí y siguen siendo clickeables, solo
  dejan de competir por atención con los que sí tuvieron movimiento
  (`ResumenProveedorNivel1.sinMovimiento`, primera corrección: "11 de 14
  proveedores en cero ocupan media pantalla").
- **Nivel 2 — panel derecho, dos bloques apilados, cero campos.** Arriba,
  un resumen de **cinco cifras** del proveedor elegido, "compacto, sin
  campos, sin desplegables, sin botones de guardar — es para mirar"
  (El dueño, dibujado a mano): dos filas de tres celdas, Stock/Costo/Venta
  arriba, Ganancia/(vacío)/Separado abajo. Stock y costo son la misma
  cuenta —el stock que queda de ese proveedor— a dos precios distintos:
  **Stock** valoriza a precio de venta ("cuánto vale en la góndola"),
  **Costo** valoriza a costo ("cuánto me costó") —
  `lib/domain/stock_valorizado.dart` calcula las dos en el mismo recorrido
  de productos, ninguna cuenta un producto sin ese dato cargado como $0
  (Regla 5). El bloque del resumen tiene su propio ancho máximo
  (`Medidas.anchoMaximoContenido`) — no se estira a todo el `Expanded` que
  le sobra a la lista (primera corrección: un card de ~1400px con un
  formulario de 760px pegado a una esquina se leía como "roto/estirado",
  no como aire).

  Abajo, **la tabla de productos del proveedor** (segunda corrección,
  nueva): nombre, costo, venta, margen % — "el corazón de la pantalla...
  ver qué le comprás, a cuánto, a cuánto lo vendés y cuánto sacás" (El dueño).
  A diferencia del resumen, este bloque SÍ es `Expanded` a todo el ancho —
  tiene contenido real que lo aprovecha (`lib/data/repositorio_reposicion.dart`,
  `productosDeProveedor`; margen vía `gananciaBpDesdeCostoYPrecio`,
  `lib/domain/ganancia.dart` — mismo cálculo que "Margen en vivo" de
  Productos, Regla 14, un producto sin costo cargado no inventa un margen).
  `ListView.builder` (CLAUDE.md: la lista de productos de un proveedor no
  tiene cota).
- **Nivel 3 "Avanzado"**: todo lo editable o accionable del proveedor —
  colchón, medio de pago, código, días de pedido/entrega,
  activar/desactivar, **y las acciones de separar y pagar** (con el
  contexto que hace falta para decidirlas: costo real pendiente, cuánto
  separar). "Es donde correspondían según los tres niveles" (El dueño,
  segunda corrección) — el panel principal pasó a ser puramente
  informativo, así que todo lo demás se mudó atrás de un solo botón. El
  diálogo es reactivo al controlador (`ListenableBuilder`, no una foto fija
  del proveedor al abrirse): separar o pagar sin cerrar el diálogo
  actualiza los números ahí mismo.

Productos sigue el mismo esquema de tres paneles a continuación (nivel 1
angosto, resumen + tabla en el panel derecho, edición en "Avanzado"). Las
nueve pantallas de gestión se revisan contra este principio (y el de
fatiga visual, arriba) antes de darlas por terminadas.

**Fiados y encargues** (antes, una columna dentro de Reposición) quedaron
afuera de Proveedores — no son proveedores, y mezclarlos de nuevo hubiera
repetido el problema que este principio resuelve. Decisión de el dueño:
sacarlos por ahora, pendientes de una sección propia ("Pendientes") más
adelante — la lógica de datos (`repositorio_pendientes.dart`) sigue
completa e intacta, solo se borró la UI vieja que dependía del controlador
de Reposición.

## Filosofía (por qué existe cada regla)

Dos consecuencias concretas del principio de arriba:

- **Armonía**: un solo sistema, no una suma de pantallas parecidas. Si un
  valor no sale de una de las escalas de abajo, está mal — no importa
  cuánto "quede bien" mirado suelto.
- **Descanso visual**: contraste medido (nunca blanco puro sobre negro
  puro), pocos colores con significado, y todo lo demás resuelto con
  espacio antes que con una línea o un color nuevo.

**Estilo general (remake 2026-09-19): profundidad vía vidrio y color, no
bento plano.** Hasta acá, "bento" significaba bloques de esquinas
redondeadas sin borde ni sombra, jerarquía solo por diferencia de color
entre el fondo de pantalla y el fondo de cada bloque. El remake porta la
estética de la companion con fidelidad completa: `Superficie` (reemplazo
de `Bloque`) sigue siendo plana y sin blur — el blur queda reservado para
lo que de verdad flota (la navbar superior, `Modal`) — pero suma dos
herramientas nuevas que "bento" no tenía: **relleno sólido o degradé**
para la pieza que más importa de cada pantalla (`Superficie.degrade`,
"color-blocking" en vez de "todo gris + acento en el texto"), y
**resplandor neón** (`resplandorNeon`, halo de color) reservado para esas
mismas piezas "hero". La jerarquía entre bloques normales sigue siendo
diferencia de color, como antes — lo que cambia es que ahora existe un
tercer nivel, "esto es lo más importante de la pantalla", con su propio
tratamiento visual en vez de compartir el mismo gris que todo lo demás.
Esto no diluye el "Principio rector: evitar fatiga visual" de arriba — al
contrario, es la misma vara: el color-blocking/resplandor se reserva a
propósito para una sola pieza por pantalla (si todo brillara, nada
señalaría nada), y `Superficie` normal sigue siendo tan neutra como
`Bloque` lo era.

---

## Escala de espaciado

Una sola escala para TODO margen, padding y hueco de la app. Ningún valor
suelto (7, 13, 22...) en ningún lado.

| Token (`Espaciado.*`) | Valor |
|---|---|
| `xs` | 4 |
| `sm` | 8 |
| `md` | 12 |
| `lg` | 16 |
| `xl` | 24 |
| `xxl` | 32 |
| `xxxl` | 48 (remake 2026-09-19, para piezas "hero" grandes) |

La pantalla de venta logra su densidad (ver más abajo) **eligiendo los
valores chicos de esta misma escala** (`xs`/`sm`), no con una escala
aparte. No existe un `EspaciadoDenso` ni ningún otro token de espaciado
fuera de esta tabla.

## Escala tipográfica (remake 2026-09-19)

Un tamaño = un rol, siempre el mismo rol en toda la app. Familia:
**Glacial Indifference**, empaquetada (no depende de que Windows la tenga
instalada) — sin cambios en el remake, ya era la misma que usa la
companion (`familiaTipografica`, compartida entre las dos apps).

Realineada a los mismos valores que ya usa la companion
(`TemaCompanion._construirTextTheme`) — full fidelity con el celular:

| Token (`TamanioTexto.*`) | Tamaño (antes, fase 13) | Rol / uso |
|---|---|---|
| `pequeno` | 12 (nuevo) | Uso puntual, el más chico (`labelSmall`) |
| `etiqueta` | 13 (13) | Aclaraciones chicas, atajos entre paréntesis |
| `secundario` | 14 (14) | Texto mutado, de apoyo |
| `cuerpo` | 16 (16) | Texto de lista estándar (nombres, filas) |
| `subtitulo` | 18 (19) | Título de un bloque o de un diálogo |
| `titulo` | 22 (24) | Título de la pantalla |
| `grande` | 32 (nuevo) | Uso puntual, un paso antes de `total` (`headlineMedium`) |
| `total` | 44 (48) | La cifra grande — el total de una venta, de un mes |

`etiqueta`/`secundario`/`cuerpo` ya coincidían con la escala de la
companion de antes del remake; solo `subtitulo`/`titulo`/`total` bajan un
toque para alinearse del todo, y se suman `pequeno`/`grande` (roles que la
companion ya tenía y el escritorio no usaba todavía).

**Reconciliado en el remake (2026-09-19)**: las dos excepciones de acá
abajo siguen vigentes tal cual — el "préstamo de un escalón" de la
tipografía de venta usa automáticamente los números nuevos de la tabla de
arriba (es la misma escala compartida, no una copia propia); `TactoVenta.radio`
se reancló explícitamente entre los radios nuevos
(`radioControlEscritorio`=18, `radioSuperficieEscritorio`=22) — detalle en
`lib/ui/venta/tacto_venta.dart`.

**Excepción puntual, solo en venta (2026-09-06)**: El dueño pidió aprovechar
mejor la pantalla ("todo se ve chico en general") — el precio real de un
producto en el dropdown de búsqueda ya usaba `subtitulo` (19) mientras el
nombre y el stock de esa misma fila usaban `cuerpo`/`secundario` (16/14),
una inconsistencia dentro de la propia fila. Se corrigió llevando todo un
escalón arriba **solo dentro de los widgets propios de venta**
(`columna_carrito.dart`, `columna_busqueda.dart`, `columna_cobro.dart`):
nombre del carrito y de la búsqueda, subtotal, precio unitario, stock, y
las etiquetas de los botones (medios de pago, "Cobrar", accesos directos)
pasan de `cuerpo`/`labelLarge` (16) a `subtitulo` (19), y los datos
secundarios de `secundario` (14) a `cuerpo` (16). Es un préstamo del rol
"título de bloque" para texto de lista/botón, no una redefinición de ese
rol — se limita a venta a propósito, sin tocar `bodyMedium`/`bodySmall`
del tema global (eso movería a Proveedores, Cierre, Configuración, etc.,
pantallas que no pidieron este cambio).

**Segunda excepción, "estilo táctil" (2026-09-16)**: El dueño pidió que venta
"parezca táctil" aunque se siga operando con mouse/teclado (el campo único
con foco permanente no cambia). `lib/ui/venta/tacto_venta.dart`:

- `TactoVenta.radio` (12) — más redondeado que `Radios.control` (8, el
  resto de la app) pero sin llegar a `Bento.radio` (14, reservado para
  bloques). Se usa en las filas del carrito/búsqueda y en los botones de
  medio de pago/Cobrar de venta.
- `TactoVenta.alturaControl` sigue igual a `Medidas.alturaControl` (48) **a
  propósito** — la columna de cobro ya está al límite de espacio vertical
  en el piso mínimo (1366×768): subirla de verdad hizo overflow real en los
  tests (siete controles con esa altura), así que la sensación táctil sale
  del radio, el ícono más grande (`TactoVenta.icono`, 24) y el feedback de
  presión, no de más alto.
- **Feedback de presión** (`SuperficieTactil`/`EscalaAlPresionar`, mismo
  archivo): cualquier fila o botón de venta se achica levemente
  (`AnimatedScale` a 0.96, `Animaciones.corta`) al presionar y vuelve al
  soltar, sumado al ripple de Material que ya tenía toda la app — "esto es
  un botón que se hunde". Responde siempre a una acción del usuario, así
  que no contradice la regla 4 del principio de fatiga visual ("nada se
  mueve solo").
- Excepción puntual, solo en venta, mismo criterio que la tipográfica de
  arriba: `Radios.control`/`Medidas.alturaControl` (tokens.dart) siguen
  intactos para el resto de la app.

### Pesos

Solo tres pesos empaquetados en la fuente (Regular/Medium/SemiBold — el
archivo pesa varios megas la familia completa, por eso solo estos tres), y
de esos tres, el sistema de diseño **usa dos**:

- **Regular** para todo lo que es lectura (cuerpo, secundario, etiqueta).
- **Medium** para lo que tiene que destacar (subtítulo, título, la cifra
  grande del total).
- **`SemiBold` queda sin usar** en ningún rol — no reintroducirlo sin que
  El dueño lo pida explícitamente.
- **Nunca `FontWeight.bold`/w700.** Sin el archivo de ese peso empaquetado,
  Flutter sintetiza un bold falso a partir del Regular (más lento de
  renderizar y se ve distinto a un bold real).

## Colores (remake 2026-09-19)

Tres niveles de texto y solo tres — si hace falta un cuarto matiz, se
resuelve con espacio, no con otro gris. Paleta nueva, portada con fidelidad
completa de `lib/companion/tema/colores_companion.dart`
(`coloresCompanionOscuro`/`Claro`) — verde-azulado como acento en vez de
ámbar, fondo casi negro azulado en oscuro en vez de gris neutro.

| Token | Oscuro (default) | Claro |
|---|---|---|
| `fondo` | `#0B0E13` | `#F2F4F6` |
| `fondoBloque` | `#151A21` | `#FFFFFF` |
| `textoPrimario` | `#F2F4F7` | `#12181F` |
| `textoSecundario` | `#93A0AD` | `#5B6672` |
| `textoTenue` | `#57626D` | `#9AA5B0` |
| `borde` | `#242C35` | `#E1E5E9` |
| `acento` | `#22D3AA` | `#0E9E7E` |
| `acentoTexto` (texto sobre `acento` sólido) | `#04211A` | `#FFFFFF` |
| `error` | `#FF5470` | `#E23A57` |
| `errorTexto` (texto sobre `error` sólido, ej. un botón de acción destructiva) | `#FFFFFF` | `#FFFFFF` |

Notar: nunca negro puro (`#000000`) ni blanco puro (`#FFFFFF`) como color de
**texto sobre fondo**, ni negro puro como `fondo` en modo oscuro — eso vibra
contra el ojo en una sesión larga. `fondoBloque` claro sí es blanco puro
porque ahí actúa como superficie, no como texto. Este criterio no lo tocó
el remake: la paleta nueva se eligió respetando el mismo principio de
contraste medido que ya regía la paleta ámbar/gris vieja.

### Acentos: familia de cuatro + degradés (remake 2026-09-19)

**Reemplaza la regla vieja de "un solo acento, tres usos exactos".** Toda
la app pasó a tener, además del acento único de arriba (selección/acción
en general), una familia de cuatro colores semánticos — uno por medio de
pago — portada con fidelidad completa de `AcentosCompanion`
(`lib/companion/tema/colores_companion.dart`) como el nuevo tipo
`AcentosPlazoleta` (`lib/ui/tema/acentos.dart`), `context.acentosPlazoleta`:

| Token (`AcentosPlazoleta.*`) | Oscuro | Claro | Uso |
|---|---|---|---|
| `dinero` | `#FFB020` | `#B9720A` | Cifras de dinero grandes — el total de una venta, el resumen del día (Venta lo reconcilia en la Fase 5) |
| `qr` | `#9C7CFF` | `#7C5CE0` | Medio de pago QR |
| `debito` | `#4FA8FF` | `#2E7FD9` | Medio de pago Débito |
| `mixto` | `#FF7E6B` | `#E85D48` | Medio de pago Mixto |
| `textoSobreColor` | `#FFFFFF` | `#FFFFFF` | Texto/ícono sobre cualquiera de los cuatro en modo sólido |
| `gradienteAcento` | `#22D3AA → #19A7D6` | `#0E9E7E → #0C86C9` | Degradé de dos tonos para piezas "hero" (Dashboard, "Ventas de hoy") |
| `gradienteDinero` | `#FFC94D → #FF8A3D` | `#D48A12 → #C9501E` | Degradé de dos tonos para piezas "hero" de dinero |

**El acento único (`colores.acento`) sigue existiendo** — sigue siendo el
color de selección/acción general (línea recién agregada de una lista,
sección activa de la navbar, foco de un campo) — pero deja de ser el ÚNICO
color con significado de la app: cada medio de pago tiene su propio color
fijo en vez de compartir el acento cuando está elegido. Si un color
aparece sin corresponder a ninguno de estos dos grupos (acento único o
familia de acentos), es un error de implementación — la regla de
moderación sigue vigente, solo que ahora hay cinco colores con
significado en vez de uno.

`Superficie.resplandor` (halo de color, `resplandorNeon`,
`lib/ui/tema/resplandor.dart`) se reserva para las piezas "hero" que usan
`relleno`/`degrade` — nunca en una `Superficie` gris normal, mismo
criterio de "si todo brillara, nada señalaría nada" que ya regía el acento
único.

### Excepción de venta: "Bento con carácter" — reconciliada (remake 2026-09-19)

Ya NO es un préstamo LOCAL aislado: `ColorMedioPago` (`lib/ui/venta/color_categoria.dart`)
dejó de tener su propia paleta hardcodeada — Efectivo pasa a ser
`colores.acento` (el acento único de la app, mismo criterio que ya usa la
companion: "es el medio más usado, tiene sentido que sea 'el' acento"), y
QR/Débito/Mixto pasan a `AcentosPlazoleta.{qr,debito,mixto}` — los mismos
cuatro conceptos, ahora compartidos con el resto de la app en vez de
duplicados. `PuntoCategoria` (paleta de 8 tonos por categoría) queda
igual, aparte — no es un acento de medio de pago.

El filete ámbar del total (`Bloque.colorFilete`) se reemplazó por el
tratamiento "hero" completo: `Superficie(degrade: acentos.gradienteDinero,
resplandor: true)`, mismo criterio que la tarjeta "Ventas de hoy" del
Dashboard (con `gradienteAcento` ahí, `gradienteDinero` acá — el total de
Venta es la cifra que más se mira de esta pantalla en particular, se
reserva el degradé "dinero" para remarcarlo).

Con esto Venta deja de ser la única pantalla con color más allá del acento
único — es una pantalla más bajo el sistema multi-acento que ahora
gobierna toda la app.

El dueño, textual: *"quiero que la interfaz de la app desktop sea llamativa al
estilo de que parezca táctil, al menos la parte de ventas"*, y después,
viendo que "solo forma" no alcanzaba: *"quiero que esté pensada visualmente
para estar 24/7, dejemos el monocromo y démosle vida, lo mismo para el
layout"*. Se armó un mockup con tres direcciones de color/layout (fuera del
repo, un artifact) y el dueño eligió **"Bento con carácter"**: el esqueleto
bento de siempre, sin agregar sombra ni cambiar el radio de bloque, pero
**venta deja de ser escala de grises + un acento** — mismo criterio de
excepción puntual que ya usa la tipografía de venta y `TactoVenta`
(`lib/ui/venta/tacto_venta.dart`): un préstamo LOCAL a los widgets propios
de esta pantalla. La regla de "un acento, tres usos exactos" de arriba
sigue gobernando el resto de la app tal cual — esto no la reemplaza.

Vive en `lib/ui/venta/color_categoria.dart`:

- **Los cuatro medios de pago tienen color propio y fijo** (`ColorMedioPago`):
  Efectivo verde, QR violeta, Débito azul, Mixto coral — en vez de que los
  cuatro compartan el ámbar del resto de la app cuando están elegidos. Fijos
  porque los cuatro medios son un dato FIJO del código (`CLAUDE.md`), no uno
  configurable — no hace falta ningún cálculo. Texto blanco encima del
  color sólido, mismo criterio que `colores.errorTexto` (blanco puro SÍ
  vale como texto sobre una superficie sólida y saturada; lo que sigue
  prohibido es blanco/negro puro como texto de lectura sobre un fondo
  neutro).
- **Cada categoría de producto tiene un punto de color** (`PuntoCategoria`,
  8px) antes del nombre, en el carrito y en las filas de resultado de
  búsqueda — no en los accesos directos todavía. Las categorías son un dato
  de negocio configurable (Configuración → Categorías), así que el color
  **no se elige a mano por nombre**: sale de una paleta fija de 8 tonos
  recorrida por posición (`categoriaId % 8`, `colorCategoria`) — mismo color
  siempre para la misma categoría, sin mantenimiento cuando el dueño crea una
  nueva. `null` (sin categoría cargada, o "Varios") no dibuja nada.
- (Histórico) El bloque del total sumaba un filete superior ámbar
  (`Bloque.colorFilete`); `Bloque` se borró el 2026-10-03 y hoy el total es
  una `Superficie`.

**Alcance: solo venta, por ahora** — mismo ritual que el resto de la fase
13 (`ESTADO.md`: "El dueño pidió ver tokens + la pantalla de venta... antes de
aplicar bento a las 9 restantes de una sola pasada"). Extender "Bento con
carácter" a Proveedores/Cierre/Reportes/etc. es un paso aparte, no
implícito en esta excepción.

El resalte de "línea elegida" (punto 3) **no es un color guardado aparte**:
es un getter calculado, `colores.destacado = Color.alphaBlend(acento al
16%, fondoBloque)`. Así solo hay un color de acento que mantener en todo el
sistema.

`error` (rojo) es el único otro color con significado, y es exclusivo de lo
que está mal: stock agotado, **diferencia de caja distinta de cero** (no
solo negativa — que sobre plata también es un descuadre: si sobran $500 es
porque una venta no quedó registrada, tan real como si faltaran. Solo el
cero va sin color). Nunca decorativo, nunca para "avisos" de datos
incompletos (esos van en `textoSecundario`, sin color de estado) ni para un
flujo normal del negocio aunque suene a advertencia (ej. la separación
parcial de cigarrillos que arrastra pendiente al día siguiente — Regla 6,
es el mecanismo funcionando, no un error).

## Superficie: medidas de bloque (remake 2026-09-19)

| Token | Valor | Qué es |
|---|---|---|
| `radioSuperficieEscritorio` (`tema.dart`) | 22 | Radio de esquina de una `Superficie` — antes `Bento.radio` (14) |
| `Espaciado.md` | 12 | Separación entre bloques — igual en horizontal y en vertical, siempre (antes nombrado `Bento.hueco`) |
| `Espaciado.lg` | 16 | Margen externo de pantalla y padding interno de cualquier `Superficie` (antes `Bento.paddingPantalla`/`paddingBloque`) |
| `radioControlEscritorio` (`tema.dart`) | 18 | Radio de botones, campos de texto, filas resaltadas — antes `Radios.control` (8) |

Un solo radio de superficie, un solo radio de control. Nunca un tercer
radio en ninguna pantalla. Todo bloque lleva el mismo padding interno en
los cuatro lados, sin excepción — el bloque del carrito de venta la tuvo
hasta la fase 13 (ver "Densidad" más abajo), ya no.

`Bento`/`Radios` (`tokens.dart`) quedan deprecados durante el rollout del
remake — pantallas todavía no migradas los siguen leyendo con sus valores
viejos — y se borran en la fase de limpieza final, cuando no quede
ninguna referencia.

### `Superficie`, no `Card`/`Bloque` (remake 2026-09-19)

`lib/ui/tema/superficie.dart` define el widget `Superficie`, reemplazo de
`Bloque` (ya borrado, 2026-10-03) — puerto de `lib/companion/tema/superficie.dart`: mismo
`Container` sin blur ni sombra por default, pero con dos modos nuevos que
`Bloque` no tenía — `relleno`/`degrade` (color-blocking sólido o degradé,
para la pieza "hero" de la pantalla) y `resplandor` (halo de color, solo
con `relleno`/`degrade` puesto). **Nunca usar `Card` en código nuevo.**

El motivo de fondo no cambió con el remake: es la única unidad visual del
sistema, un solo lenguaje en toda la app (Regla de armonía) — mezclar
`Card` de a pantallas rompería eso. Cuando hace falta una sombra de
verdad (un diálogo, la navbar superior), se agrega vía `DialogThemeData`
o directo en el widget (`NavbarSuperior`, `Modal`), no resucitando `Card`.

## Medidas de alineación reutilizables

| Token | Valor | Uso |
|---|---|---|
| `Medidas.anchoValorLista` | 110 (antes 90) | Ancho fijo del monto (a la derecha) en CUALQUIER fila de lista con etiqueta a la izquierda y plata a la derecha — carrito, dropdown de búsqueda, y cualquier lista nueva con el mismo patrón. Garantiza que "una fila de lista se vea igual en toda la app". Subido junto con la escala tipográfica (fase 13): el mismo monto tabular ocupa más ancho con `cuerpo` en 16 que en 13.5. |
| `Medidas.alturaControl` | 48 (antes 40) | Altura fija de un botón que pertenece a un grupo de opciones del mismo tamaño (ej. los medios de pago de la pantalla de venta: "rectángulos idénticos" — hoy tres, cuatro cuando se sume el botón de débito de la fase 12). Subida en la pasada de fatiga visual de la fase 13, mismo criterio que el resto de la escala. |
| `Medidas.anchoListaMaestra` | 360 (antes 580, antes 460, antes 320) | Ancho fijo de la columna angosta en cualquier pantalla con patrón lista + detalle (Proveedores, y a continuación Productos y Configuración). Subió a 460 y después a 580 mientras el nivel 1 mostraba cifras (fase 13, primera corrección). Bajó a 360 en la SEGUNDA corrección post-revisión (dibujo de el dueño): las cifras dejaron de vivir en la lista — son del proveedor elegido, no de todos a la vez — así que vuelve a ser una columna de solo nombre. Sigue siendo un valor compartido con Productos, que va a seguir el mismo esquema de tres paneles. |
| `Medidas.anchoColumnaCobroVenta` | 340 (antes 260) | Ancho de la columna de cobro de la pantalla de venta (fase 13). Con `TamanioTexto.total` en 48, 260 se quedaba chico — un total de varias cifras envolvía a una segunda línea. |
| `Medidas.anchoColumnaBusquedaVenta` | 440 | Ancho de la columna de búsqueda de la pantalla de venta (fase 13, primera aplicación del principio de fatiga visual). Antes 320, el mismo valor que `anchoListaMaestra` — pero ahí ese ancho salía de un motivo propio de venta, no del vocabulario compartido de columna angosta: el carrito de al lado le sobraba ancho (`anchoFilaCarrito` ya lo acota), así que ese sobrante pasó a esta columna en vez de quedar vacío. |
| `Medidas.anchoMaximoContenido` | 760 (antes 640) | Ancho máximo de una columna de contenido tipo formulario (patrón A, ver "Patrones de composición") — también el ancho máximo de la `Superficie` de resumen en Proveedores (nivel 2, ver "Principio rector: tres niveles de información" arriba): ese bloque no se estira a todo lo que le sobra a la lista, a diferencia del bloque de la tabla de productos, que sí es `Expanded` porque tiene contenido real que lo aprovecha. Resuelta la revisión pendiente contra 1920×1080: 640 apuntaba al objetivo viejo. Ya NO es el ancho del carrito de venta (ver `anchoFilaCarrito`) — dejaron de compartir motivo en la corrección post-revisión. |
| `Medidas.anchoFilaCarrito` | 640 (antes 520) | Ancho máximo de una fila del carrito de venta. Subió de 520 a 640 (El dueño, 2026-09-06: "aprovechemos la pantalla de venta al máximo" — a 1920×1080 quedaba una franja vacía a la derecha de cada fila). Sigue sin ser `anchoMaximoContenido` (760, pensado para un formulario de varios campos) — la fila ahora tiene cuatro datos (nombre, cantidad, precio unitario, subtotal) más un ícono de eliminar, no dos, así que ensancha de nuevo pero con tope propio. |
| `Medidas.anchoBarraLateral` | 300 | Sin uso desde el remake (remake 2026-09-19) salvo por `BarraLateral`, que sigue viva solo dentro de Venta hasta la Fase 5 — la navbar superior no tiene un ancho fijo, cada ítem mide lo que necesita su contenido (ícono, o ícono+nombre). Se borra junto con `BarraLateral` en la fase de limpieza. |
| `Medidas.anchoBarraLateralPlegada` | 64 | Ídem. |

## Patrones de composición

Toda pantalla de gestión (todo lo que no sea la pantalla de venta) resuelve
su layout con uno de estos dos patrones. Ninguna pantalla nueva inventa un
tercero.

### Patrón A — Formulario

Una acción, pocos campos, un botón que la confirma. Columna centrada,
`Center` + `ConstrainedBox(maxWidth: Medidas.anchoMaximoContenido)`, con una
o más `Superficie` (remake 2026-09-19: antes `Bloque`) adentro según haga
falta. Ejemplos: apertura de caja, el paso de conteo del cierre de caja
(Regla 10 — mientras se cuenta, no hay nada más en pantalla).

### Patrón B — Panel de datos

Varios bloques de contenido que se leen juntos. Grilla de **dos
columnas**, separadas por `Espaciado.md` tanto horizontal como vertical
entre bloques. Cada bloque es una `Superficie` con su propio título
arriba. Ningún alto forzado entre bloques — cada uno mide lo que su
contenido necesita.

**Las dos columnas terminan a alturas parecidas.** La regla de alineación
de "dos bloques lado a lado arrancan y terminan a la misma altura" no se
puede cumplir bloque por bloque en una grilla de alturas distintas — acá se
aplica a nivel columna: si una columna queda mucho más larga que la otra,
se **rebalancea moviendo un bloque entero a la otra columna**, nunca se
deja un hueco muerto al final de la más corta. El criterio de qué bloque va
en qué columna es el mismo que ordena las columnas de la pantalla de venta:
izquierda lo que se mira primero (el resultado, la conclusión), derecha lo
que se consulta después (el detalle que sostiene ese resultado) — pero el
balance de altura es la restricción dura; si el criterio de lectura y el
balance chocan, se ajusta el reparto hasta que las dos columnas midan
parecido sin dejar de tener sentido de lectura.

**Siempre dos columnas — sin lógica responsive.** Nada de `LayoutBuilder`
decidiendo cuántas columnas entran, ni un fallback a una columna para una
pantalla angosta. Antes de la fase 13 esto se apoyaba en que el hardware
era fijo (la app corría en una de dos resoluciones conocidas y en ninguna
otra). Eso ya no es tan cerrado — **1920×1080 es la resolución de diseño,
1366×768 el piso mínimo que tiene que seguir viéndose digno** (ver
"Restricciones de hardware" más abajo) — pero la regla de fondo se
mantiene por una razón que no dependía del hardware: un layout de dos
columnas fijas es más simple de razonar y de mantener consistente entre
pantallas que uno con breakpoints, y ninguna pantalla de esta app necesita
angostarse a una columna en la práctica. El simulador de resolución de
debug ahora prueba esas dos resoluciones (el objetivo y el piso), no una
muestra de un rango — ver "Simulador de resolución" más abajo.

**El patrón B scrollea como página entera**, las dos columnas juntas en un
solo `SingleChildScrollView` (o `ListView`) exterior — nunca dos scrolls
independientes, uno por columna: eso descoloca las dos mitades entre sí, es
peor que scrollear. Esto no contradice la regla de `CLAUDE.md` de "toda
lista larga con `ListView.builder`, nunca `Column` en
`SingleChildScrollView`" — esa regla apunta a listas **sin cota** (productos,
historial, ventas de un día). El patrón B es un conjunto FIJO de bloques
(seis en Equilibrio, por ejemplo), no una lista que crece. Si un bloque
puntual dentro del patrón B contiene una lista sin cota (ej. una lista larga
de conceptos), esa lista interna sigue usando `ListView.builder` con su
propio alto acotado — la regla de `CLAUDE.md` sigue valiendo entera ahí
adentro, es un problema distinto al del scroll de la página.

### Cierre de caja usa los dos patrones, en secuencia

Mientras se cuenta el efectivo (Regla 10, "primero se cuenta"): patrón A,
nada más visible. Confirmado el conteo, la pantalla pasa a patrón B con los
bloques del resumen — Arqueo a la izquierda (lo que se mira primero:
caja esperada, diferencia), Cigarrillos y Resumen del día a la derecha (el
detalle que sostiene ese número). No es una excepción al patrón: es la
pantalla cambiando de patrón porque cambió lo que está haciendo.

## Patrón lista + detalle

Proveedores, Productos y Configuración usan este patrón. Una sola
definición para las tres, no una por pantalla:

- **Dos `Superficie` separadas** (remake 2026-09-19: antes `Bloque`) — una
  para la lista, una para el detalle — con `Espaciado.md` entre ellas.
  Nunca un `VerticalDivider`: separar con una línea es exactamente lo que
  "Preferí espacio antes que línea" (más abajo) prohíbe: es un borde, y de
  los evitables.
- La columna de la lista mide `Medidas.anchoListaMaestra` (460); el bloque
  de detalle es `Expanded` — ocupa el resto del ancho de pantalla.
- Si la lista tiene buscador (como Productos), va **arriba, dentro de la
  misma `Superficie` de la lista** — mismo lugar que el campo único de
  venta arriba de su propio dropdown.
- Sin nada seleccionado, el bloque de detalle muestra un estado vacío (ver
  "Estados vacíos" más abajo), centrado.
- El bloque de detalle es `Expanded` (ocupa el ancho que le sobra a la
  lista), pero **su contenido no se estira a ese ancho completo** — un
  formulario de 900px de ancho es tan ilegible como uno de 1280px. El
  contenido interno respeta el mismo límite de ancho cómodo que un
  formulario (ver "Patrones de composición" más abajo); el bloque en sí
  ocupa el espacio que le toca, el contenido adentro no.

## Navegación: navbar superior (remake 2026-09-19)

**Cómo es HOY (2026-10-03)** — lo de más abajo es la historia del remake y
algunas partes ya no aplican (vidrio, compacta/expandida, íconos): la barra
es la marca (insignia con iniciales + nombre del comercio), las secciones
como **pastillas de texto** (la activa con fondo `fondoBloque`) y
**Configuración como engranaje** al final de la fila (`_BotonConfiguracion`
en `navbar_superior.dart`, `Key('nav_configuracion')`), no como pastilla.
A la derecha, la búsqueda (o en Venta, campanita + "Cambiar de turno" /
"Cerrar caja"). **Configuración** se muestra en 5 grupos
(`GrupoConfiguracion`: Negocio, Caja y cobros, Productos, Equipos y cuenta,
Apariencia): lista de grupos a la izquierda; a la derecha título grande,
una línea de descripción y pastillas por sección (la activa en tinta).
Sin títulos repetidos dentro de cada sección y sin referencias internas
("Regla N") en la interfaz. El celular usa los mismos grupos en una sola
página con "Guardar" abajo y "Volver" arriba (`AppBarCompanion`).

**Reemplaza la barra lateral** (`lib/ui/navegacion/barra_lateral.dart`,
`BarraLateral` — sigue en el árbol solo dentro de Venta hasta la Fase 5,
se borra en la limpieza final). El dueño pidió el cambio de lugar como parte
del remake completo de estética ("una navbar en la mitad superior en vez
de una tabbar a la izquierda"); el resto de las reglas de fondo (siempre
visible, nunca se abre/cierra, recuerda la preferencia de compactado) no
cambió, solo la orientación y el look.

- **Flotante arriba, siempre visible**, en toda pantalla que la use — no
  un cajón que se abre y se cierra. `lib/ui/navegacion/navbar_superior.dart`
  (`NavbarSuperior`), reutilizable: cada pantalla arma su propia lista de
  `ItemNavbarSuperior` y su propia clave activa. Look de vidrio esmerilado
  — píldora horizontal, blur, borde de 1px, sombra — mismo tratamiento que
  `NavbarCompanion` de la companion, adaptado a mecánica de capas de
  escritorio (ver más abajo).
- **A diferencia de la companion, no flota SOBRE contenido scrolleable.**
  En el celular la navbar flota sobre contenido que se scrollea debajo
  (necesario en un teléfono); en escritorio vive en un `Column` arriba de
  `Expanded(child)` (`EnvolturaConNavbarSuperior`), nunca superpuesta —
  mismo look, mecánica de layout más simple, sin reservar espacio ni
  arriesgar que el último elemento de una lista quede tapado.
- **Compacta o expandida, nunca intermedia, nunca por hover** — mismo
  criterio que la barra lateral que reemplaza: `compactaEfectiva()`
  combina la preferencia guardada (`configuracion_tabla.barra_lateral_plegada`,
  mismo campo de siempre, reinterpretado — sin migración de esquema) con
  un umbral automático de ancho de ventana (`Medidas.anchoUmbralCompacto`).
  Un botón (☰ / ícono de "compactar") cambia entre los dos modos a mano.
- **Ícono + nombre** expandida, solo ícono compacta (con tooltip) — nunca
  al revés. El ícono sigue siendo una decisión puramente visual (mismo
  mapa fijo en el código que ya tenía `BarraLateral`) — no vive en
  `secciones_menu` (esa tabla es orden/visibilidad, un dato de negocio
  configurable, fase 8).
- El orden y la visibilidad de las secciones siguen saliendo de
  `secciones_menu` tal cual — la navbar es solo el widget que las muestra.
- **Sección activa**: tinte de `colores.acento` de fondo + `resplandorNeon`
  — mismo espíritu que el fondo `destacado` de antes (es "esto está
  elegido"), con el tratamiento de resplandor que ya usa toda la familia
  de acentos nueva (ver "Acentos" arriba) en vez del cuarto-uso-puntual
  que documentaba la versión vieja de esta regla.
- **"Cerrar caja" sigue siendo una acción, no una sección**: va en un slot
  de acción al extremo derecho de la navbar (`NavbarSuperior.accion`,
  reemplaza al `pie` de `BarraLateral`), separado del listado de
  navegación por hueco. Hoy específica de Venta, que arma su propia
  `NavbarSuperior` a mano por ese motivo (mismo motivo que ya tenía con
  `BarraLateral`: foco del campo único, atajos de teclado). "Imprimir
  ticket" sigue sin vivir acá — ver "Acuse de cobro y reimpresión" más
  abajo.

**Se preserva la excepción de "flujo bloqueante"**: `pantalla_detalle_dia.dart`
y `pantalla_editor_venta.dart` siguen con su propio `AppBar`, no son
destino de la navbar — solo cambian sus tokens internos (paleta, radios).
`PantallaCierre` sigue siendo un `Modal` (con el vidrio nuevo), tampoco es
destino de navbar.

`lib/ui/navegacion/navegacion_gestion.dart` (`itemsNavGestion`,
`navegarASeccionDeGestion`) sigue exactamente igual en su lógica — mismo
criterio de `Navigator.popUntil(isFirst)` antes de empujar el destino
nuevo, la pila nunca crece más allá de `[Dashboard, X]` — solo cambió el
tipo que devuelve (`ItemNavbarSuperior` en vez de `ItemBarraLateral`,
renombre cosmético). `lib/ui/comun/armazon_gestion.dart` (`PantallaGestion`)
pasó a envolver con `EnvolturaConNavbarSuperior` en vez de
`EnvolturaConBarraLateral` (esta última, sin más llamadores, se borró).

**Estado real (ver `ESTADO.md`)**: aplicada a **todas** las pantallas de
gestión (heredada automáticamente vía `PantallaGestion`/
`EnvolturaConNavbarSuperior`) y a Venta (`NavbarSuperior` armada a mano,
igual que antes con `BarraLateral`) — El dueño pidió no esperar a las fases
2-5 del plan original ("la pantalla de ventas se adapte también"), así que
todo el remake de tokens/navbar/`Superficie` se completó en la misma
sesión que la Fase 1. Solo queda la Fase 6 (limpieza: borrar `Bloque` y
los tokens viejos deprecados cuando no quede ninguna referencia real, hoy
solo la vitrina del kit en `test/capturas/pantalla_muestra_kit.dart` los
sigue usando a propósito).

## Búsqueda de venta: filas de una línea, tres datos

Fase 13, ítem 2, con una corrección post-revisión encima. Primer intento:
El dueño, textual: *"el nombre se trunca"* — el dropdown viejo era una lista
de filas angostas de una sola línea, con el nombre recortado por
`TextOverflow.ellipsis`. La respuesta a eso fue una card de dos líneas
(nombre arriba, precio/unidad abajo) — pero la revisión encontró que esa
card se leía en diagonal y gastaba 96px de alto para solo dos datos, y que
faltaba un tercero (el stock). Vuelta a filas, con lo que sí valía la pena
conservar del intento de las cards: el alto cómodo.

- **Fila de una línea, no card de dos**: sin borde propio (`Material` +
  `InkWell`, mismo criterio que cualquier fila de lista de la app —
  Proveedores, por ejemplo), sin fondo propio salvo la preselección
  (`colores.destacado`). Tres datos, siempre en el mismo orden: **nombre ·
  stock · precio**. El nombre se trunca con `ellipsis` si no entra —
  vuelta atrás deliberada: la fila prioriza una sola línea por sobre
  mostrar el nombre completo de uno particularmente largo.
- **Stock, la columna que faltaba**: unidades (`"12 un."`) o gramos
  disponibles (`"3200 g"`) — el dato que la card anterior no mostraba en
  absoluto. Ancho `Medidas.anchoValorListaCompacto`, texto secundario (no
  es el dato principal de la fila).
- **Precio**: el subtotal a pagar en `titleMedium` (el dato que más importa
  leer rápido); si es una TARIFA de referencia y no un monto a pagar
  todavía (un pesable sin gramos escritos, `"$8.500/kg"` — sin centavos
  desde 2026-09-16, ver "Plata sin centavos" más abajo), un tamaño menor
  (`bodySmall`) lo distingue — y sigue siendo un solo `Text`, nunca
  partido en dos widgets (bug real, ver `TRAMPAS.md`: precio y "/kg" como
  widgets separados se veían partidos en dos líneas).
- **"Varios" se distingue, no se esconde**: sin precio fijo ni stock real,
  mostrar esas dos celdas vacías se leía como un error. Un guion ("—") en
  cada una dice "no aplica", no "falta un dato".
- **Sin marcar stock bajo en rojo acá**: esa señal vive en el carrito
  (`columna_carrito.dart`, que es donde `CLAUDE.md` la pide desde el
  principio) — tenerla en los dos lugares a la vez era literalmente
  duplicar el aviso ("un producto sin stock se marca en un solo lugar, no
  en los dos", revisión). Menos rojo en pantalla en general: la regla de
  "pocos colores con significado" (Filosofía, arriba) también aplica acá.
- **El teclado sigue mandando**: flechas mueven la preselección, Enter
  agrega. Tocar una fila con el mouse hace lo mismo, pero nunca hace falta
  — es una superficie más grande para el mouse, no un cambio de quién
  maneja la pantalla. El campo tiene foco al arrancar y lo recupera solo
  después de agregar/cobrar — ya no después de cualquier acción (ver
  "Foco: solo donde hace falta" más abajo).
- **Una sola superficie, no dos bloques**: antes había un bloque de
  resultados (vacío la mayor parte del tiempo, sin texto escrito) y, abajo,
  un bloque aparte con la grilla de accesos directos — el primero era
  hueco muerto casi siempre. Ahora es la misma superficie: sin texto
  escrito, accesos directos; escribiendo, las filas (o "Sin coincidencias"
  si no hay ninguna — sin alta rápida, ver más abajo). Nunca las dos cosas
  a la vez.
- **Sin alta rápida (2026-09-16)**: dar de alta un producto nuevo desde
  esta pantalla (El dueño: "eliminar el alta rápida de esa pantalla") se
  sacó — un código o nombre sin coincidencias muestra el aviso y nada más,
  sin acción. Cargar un producto nuevo pasa a ser siempre desde
  Proveedores. `dialogo_alta_rapida.dart` se borró (sin más llamadores).

## Foco: solo donde hace falta (2026-09-16)

El dueño: *"quiero que en la pantalla venta se optimice el uso de teclado y
mouse... escribir sin poner obligatorio el foco en teclado"* — hasta acá,
CUALQUIER acción de la pantalla de venta devolvía el foco al campo único al
terminar ("punto crítico #1"), incluso cerrar un diálogo secundario que no
tiene nada que ver con seguir escribiendo. Eso quedó dividido en dos
categorías, no eliminado del todo (el campo sigue siendo la entrada
principal para escanear/escribir):

- **Devuelven el foco** (es la continuación natural de seguir vendiendo):
  agregar un producto por tap, Alt+tecla o Enter; elegir un medio de pago
  (chip o Alt+tecla); cobrar (botón, Enter, o Alt+M); volver de una
  pantalla de gestión pusheada (`didPopNext`); abrir caja desde el estado
  bloqueado.
- **YA NO lo hacen** (diálogo secundario, no es el flujo de escanear): Mixto,
  Varios, gasto rápido, ingreso rápido, arqueo intermedio, editar un acceso
  directo, imprimir el último ticket. El foco se queda donde haya quedado
  al cerrarse esos diálogos, en vez de saltar solo.

`lib/ui/venta/acciones_venta.dart` y `pantalla_venta.dart` tienen el
criterio completo, función por función.
- **Ancho de columna**: `Medidas.anchoColumnaBusquedaVenta` (440) — ver la
  tabla de Medidas arriba para por qué dejó de compartir valor con
  `anchoListaMaestra`.

## Acuse de cobro y reimpresión

Fase 13, ítem 3. "Imprimir ticket" deja de ser una acción permanente de la
barra lateral — imprimir solo tiene sentido inmediatamente después de
cobrar, no todo el tiempo que dura una venta.

- El ícono de imprimir aparece **junto al acuse** ("Venta #N cobrada ·
  $X", `columna_carrito.dart`), nunca solo: no hay forma de imprimir sin
  que el acuse también esté visible, porque son la misma pieza de
  información ("esto es lo último que cobré").
- Se va con el resto del acuse, sin timer, en cuanto entra la primera
  línea de la venta siguiente — mismo mecanismo que ya tenía el acuse
  antes de que existiera el botón.
- **Historial es el único camino para reimprimir un ticket de un día
  anterior** (la pantalla de Impresión está oculta del menú desde la v13
  del esquema). Cada venta del detalle de día tiene su propio botón
  "Imprimir", mismo diálogo (`mostrarDialogoImprimirTicket`) que usaba la
  barra lateral — no una pantalla nueva.

## Estados vacíos y de error (remake 2026-09-19)

`EstadoVacio`/`EstadoError` (`lib/ui/comun/`) — reemplazadas por la
versión estilo companion: ícono dentro de un círculo con tinte de color
(`textoTenue`@12% en vacío, `error`@14% en error) en vez de un ícono
suelto en gris, mismo criterio que
`lib/companion/tema/estado_vacio_companion.dart`/`estado_error_companion.dart`
("íconos siempre dentro de un contenedor, nunca sueltos"). `EstadoError`
suma un `FilledButton` de "Reintentar" en vez de `OutlinedButton`. Misma
forma de constructor que antes (`mensaje`, `icono` opcional,
`onReintentar` en el de error) — ningún llamador existente cambia.

Se usan igual que antes: cambia solo el mensaje/ícono según la pantalla
("Elegí un producto de la lista", "Sin fiados pendientes"), nunca un
cuarto matiz de gris ni un tratamiento nuevo por pantalla.

## Plata sin centavos (2026-09-16)

El dueño: *"dejemos de mostrar centavos"*. `formatearARS` (`lib/domain/dinero.dart`,
el único punto de conversión centavos → texto, Regla 3) dejó de imprimir la
parte decimal en toda la app — `150050` centavos da `"$1.501"`, no
`"$1.500,50"`: redondea al peso más cercano en vez de truncar, para no
mostrar sistemáticamente de menos. Es solo la CAPA DE TEXTO: `precioCentavos`
sigue siendo el entero de centavos real en la base (Regla 1 de `CLAUDE.md`
sin tocar), y `parsearARS` sigue aceptando centavos al cargar un precio a
mano — lo que cambió es cómo se lee, no qué se guarda ni cómo se calcula.
`formatearParaMercadoPago` (Fase 12, la API de Orders exige centavos exactos)
es una función aparte y no se tocó.

## Reglas de alineación y simetría

- **Grilla**: si dos bloques están uno al lado del otro, sus contenidos
  arrancan y terminan a la misma altura. Sin desniveles de dos o tres
  píxeles.
- **Plata siempre a la derecha**, en todas las pantallas, con números
  tabulares (`fontFeatures: FontFeature.tabularFigures`, expuesto como el
  getter `.tabular` sobre cualquier `TextStyle` en `tokens.dart`) para que
  unidades, decenas y centenas caigan en la misma columna. Ancho fijo
  (`Medidas.anchoValorLista`), nunca "lo que ocupe el texto".
- **Etiqueta a la izquierda, valor a la derecha**: el mismo par, siempre
  igual, en toda la app.
- **Baseline, no centro**, cuando una fila mezcla texto chico y un número
  grande — el número grande no debe hacer "flotar" el texto chico que lo
  acompaña.
- **Íconos centrados ópticamente** con el texto que acompañan, no
  matemáticamente. Si uno se ve torcido, correrlo un píxel a mano.
- **Padding simétrico** en los cuatro lados de un bloque salvo que haya un
  motivo documentado (la densidad del carrito es el único hoy).
- **Grupos de botones**: mismo ancho, misma altura (`Medidas.alturaControl`
  cuando aplica), mismo hueco entre ellos.
- **Huecos entre bloques, todos iguales** — si el horizontal es `Espaciado.md`,
  el vertical es el mismo valor, siempre.
- **Texto dentro de un botón, centrado de verdad**: mismo espacio arriba
  que abajo, mismo a izquierda que a derecha.
- Prueba concreta para revisar cualquier pantalla nueva: trazar una línea
  vertical por el borde derecho de una columna — todo lo que esté en esa
  columna tiene que tocarla. Nada colgando un par de píxeles más adentro o
  más afuera.

## "Preferí espacio antes que línea"

`colores.borde` quedó reservado para **un solo uso real**: el borde de
`OutlinedButton` y el riel apagado de un `Switch` (son controles, no
separadores de contenido). Nunca se usa para separar bloques entre sí ni
filas de una lista — eso se resuelve con `Espaciado.md` o con una diferencia
de fondo (`colores.destacado`), no con una línea.

## Densidad: ya no hay una excepción documentada

Hasta la fase 13, esta sección decía que la pantalla de venta priorizaba
**densidad** por sobre aire — el bloque del carrito usaba
`vertical: Espaciado.sm` en vez de `Bento.paddingBloque`, la única
excepción documentada al padding estándar de cualquier bloque. Esa regla
estaba escrita para 720px de alto (hardware 2008, ver `CLAUDE.md`,
"Hardware — qué cambió y qué no"): apretar el carrito era el único modo de
que entrara completo sin scrollear.

**Con 1080px de alto sobra espacio** para que el carrito use el mismo
padding que cualquier otro bloque de la app (regla 3 del principio rector,
arriba) y siga entrando cómodo sin scroll en el uso real — no hace falta
elegir entre las dos cosas. La única regla que sigue siendo específica de
venta es de **ancho**, no de padding: cada fila del carrito tiene un ancho
máximo (`Medidas.anchoFilaCarrito`, 520 — no `anchoMaximoContenido`, ver
"Principio rector" y la tabla de Medidas arriba) en vez de estirarse hasta
el borde de la columna — el carrito sigue siendo `Expanded` (le sobra
ancho, por diseño: es lo que financia la columna de búsqueda más ancha),
pero su contenido no se estira a ese ancho completo, mismo criterio que ya
vale para el bloque de detalle del patrón lista + detalle. `anchoFilaCarrito`
es más angosto que `anchoMaximoContenido` a propósito (corrección
post-revisión: "el monto queda muy lejos del nombre" con 760) — una fila
de dos datos necesita bastante menos ancho que un formulario de varios
campos, y desde esta corrección cada uno tiene su propio token en vez de
compartir uno pensado para el otro caso.

Todas las pantallas de gestión, venta incluida, usan hoy la escala
completa de `Espaciado` para su padding y sus huecos — no queda ninguna
pantalla que elija los valores chicos de esa escala por densidad.

## Simulador de resolución (solo debug)

`lib/ui/tema/simulador_resolucion.dart` agrega un chip flotante (esquina
inferior derecha, solo cuando `kDebugMode`) con tres botones: **1920×1080**,
**1366×768 (piso)** y **960×1080 (mitad)**. Al tocarlos, fuerza la ventana
a ese tamaño exacto (`window_manager`, paquete agregado solo para esto).

**Por qué existe, y por qué cambió en la fase 13**: hasta la fase 11
simulaba 1366×768 y 1280×720 porque el monitor de la PC de 2008 era uno de
esos dos tamaños y no se sabía cuál hasta probarlo — las dos eran
candidatas al mismo título, ninguna era "la buena". Esa PC se reemplazó por
una con monitor de 1920×1080 o más: ahora hay una resolución de diseño real
(1920×1080, no una entre dos candidatas) y un piso mínimo que **tiene que
seguir viéndose digno** si la app corre en una pantalla más chica
(1366×768) — no un segundo objetivo con el mismo peso que el primero. El
desarrollo se sigue haciendo en otra máquina; sin este selector, cualquier
ajuste de layout se estaría diseñando a ciegas para una resolución que
El dueño nunca va a ver. El tamaño de ventana por defecto del runner
(`windows/runner/main.cpp`) es 1920×1080 desde la fase 13, así que esa
resolución se ve "sin tocar nada" al abrir la app en debug — el botón de
1366×768 es el que hace falta para simular el piso.

**960×1080 agregado en la fase 13, "mitad de pantalla"** (El dueño,
2026-09-07: "prepara la app desktop para funcionar en la mitad de la
pantalla de 1920×1080... nada se vaya por las ramas" — la mitad de un
monitor de 1920 al snapear dos ventanas lado a lado en Windows). Es más
angosto que el piso de 1366, un escalón más allá de "seguir viéndose
digno": acá el objetivo es "no romper" — la barra lateral se pliega sola
y la pantalla de venta usa columnas angostas por debajo de
`Medidas.anchoUmbralCompacto` (`lib/ui/navegacion/barra_lateral.dart`,
`plegadaEfectiva`), sin pisar la preferencia guardada de la barra a los
anchos normales. `Metrica` (borrada el 2026-10-03, sin uso) achicaba la letra
de la cifra con `FittedBox` en vez de partirla en dos líneas o truncarla
— una cifra de plata cortada con "..." podría leerse como un monto
distinto. Verificado con capturas reales a 960×1080 de Venta, Proveedores
y Reportes (`test/capturas/`, sufijo `-mitad-pantalla`) — ninguna
pantalla de gestión más se revisó pantalla por pantalla todavía, pero el
mecanismo (barra compartida + `Metrica` compartida) alcanza a todas por
igual.

En release, ni el chip se arma ni se llama a `window_manager` — el `if
(kDebugMode)` lo saca del árbol entero, costo cero.

## Restricciones de hardware — cuáles siguen y por qué (fase 13)

Hasta la fase 11, esta sección listaba reglas "no negociables" por costo de
CPU/disco de la PC de 2008. Esa PC ya no corre la app (ver `CLAUDE.md`,
"Hardware — qué cambió y qué no") — cada regla de acá se revisó de nuevo
por su propio mérito, no se mantuvo por inercia.

- **`BoxShadow` deja de estar prohibido en general.** `Superficie` sigue
  sin sombra por default (la jerarquía entre bloques normales se sigue
  resolviendo con diferencia de color) — pero ya no porque no se pueda
  pagar una. Los diálogos y la navbar superior sí llevan sombra (fase 13,
  ítem 4, y remake 2026-09-19): ahí la sombra cumple un rol que el color
  solo no cumple (separar una capa flotante del resto de la pantalla), así
  que se agrega ahí y en ningún otro lado sin un motivo igual de concreto.
- **`BackdropFilter` (vidrio esmerilado), sumado en el remake 2026-09-19.**
  Exclusivo de lo que de verdad flota — la navbar superior y `Modal` — con
  la misma disciplina de rendimiento que ya usa la companion: sigma de
  blur moderado (16, no el default más caro), y **siempre** dentro de un
  `RepaintBoundary` propio (`BackdropFilter` repinta su capa en cada frame
  mientras algo cambia detrás; sin ese límite, ese repintado puede
  arrastrar de vuelta al resto del árbol). Cualquier uso nuevo de
  `BackdropFilter` sigue esta misma regla — nunca sin `RepaintBoundary`,
  nunca en una `Superficie` de contenido normal.
- **Las transiciones entre pantallas dejan de estar prohibidas en
  general.** Vuelven cortas, orientando una navegación real (fase 13, ítem
  4) — nunca decorativas, y nunca en la pantalla de venta durante un
  cobro. `PageTransitionsTheme` en `tema.dart` es el lugar donde se
  configuran cuando se implementen; hasta entonces sigue en
  `_SinTransicion`.
- **`splashFactory`/`highlightColor` dejan de estar fijos a "sin ripple".**
  El ripple de Material vuelve (fase 13, ítem 4): es la única señal hoy de
  "el clic entró" en cualquier botón o fila clickeable de la app, y
  costaba tan poco de repintar que prohibirlo por hardware nunca compró
  mucho — el motivo real de sacarlo era estético (`NoSplash` en
  `tema.dart:49`), no una necesidad real de la PC vieja.
- **`Card` sigue evitándose en código nuevo** — ver "`Superficie`, no
  `Card`/`Bloque`" arriba: el motivo cambió (armonía visual, no costo de
  sombra), la regla práctica no.
