# La Plazoleta — Sistema de caja y gestión

App de escritorio en **Flutter para Windows**, para un almacén de barrio en Bariloche.
Reemplaza un sistema anterior en Next.js + Tauri que era funcionalmente correcto pero
demasiado pesado para el hardware del local.

## Documentación del proyecto

**Si es la primera vez que abrís el proyecto, empezá por `CONTEXTO.md`**: resume el sistema completo (PC, celular y
sitio), qué se hizo, qué quiere el dueño, cómo trabaja y cómo se publica.

Este archivo es la fuente de verdad de **cómo está armado el código**: stack,
arquitectura, convenciones, fases, y la especificación de la pantalla de venta.
Todo lo demás vive en un documento aparte — no se duplica acá. Mapa completo con
el dueño de cada uno en `README.md`; los más relevantes para escribir código:

- **`REGLAS-NEGOCIO.md`** — el dominio del negocio. Si el código y ese documento
  se contradicen, el código está mal.
- **`ESTADO.md`** — qué fases están cerradas y cuáles no, HOY. La lista de fases
  de este archivo describe qué es cada una, no si ya está hecha.
- **`DECISIONES.md`** y **`TRAMPAS.md`** — leerlos antes de tocar algo que ya
  funciona: ahí está el motivo de decisiones que parecen arbitrarias y los bugs
  ya encontrados que no hay que repetir.
- **`DISENO.md`** — el sistema de diseño completo (tokens, escalas, reglas de
  alineación). La sección de la fase 11 acá abajo es solo un resumen.

**Si dos documentos (o dos partes del mismo) se contradicen, vale lo más
reciente** (El dueño, 2026-10-03): la fecha escrita en el texto ("El dueño,
2026-09-16"), o la del commit si no tiene. Lo viejo se corrige en el mismo
cambio en que se detecta, para que no vuelva a confundir.

## Cómo se trabaja acá

1. **Leé `REGLAS-NEGOCIO.md` antes de escribir código de dominio.** Es la fuente
   de verdad — si hace falta un dato que no está ahí, se pregunta, no se inventa.
2. **Una fase por vez, sin adelantarse.** Cada fase se prueba antes de empezar la
   siguiente (ver "Fases" más abajo y el estado real en `ESTADO.md`).
3. **Plan antes de código en cualquier pantalla o módulo grande.** Mostrar el plan,
   marcar las ambigüedades de negocio ANTES de resolverlas — no se resuelven solas
   ni se posponen calladas.
4. **Tests primero** en `domain/`, tomando como catálogo de casos los bordes reales
   del negocio (ver `DECISIONES.md`/`TRAMPAS.md` para los que ya mordieron).
5. Las decisiones técnicas de implementación (nombres, estructura de archivos, qué
   patrón usar) se deciden sin preguntar. Las decisiones de negocio o ambiguas se
   marcan y se preguntan.

---

## Hardware — qué cambió y qué no (fase 13)

La app se diseñó al principio contra una PC de 2008: **2 núcleos, 4 GB de
RAM DDR2, disco mecánico, Windows 10 LTSC**. El sistema anterior se
descartó por lento en esa máquina, no por estar mal hecho — y varias reglas
de este documento nacieron directamente de ese límite.

**Esa máquina ya no es la que corre la app.** El local pasó a una máquina
nueva, con potencia de sobra y un monitor de 1920×1080 o más. Eso **levanta
la restricción, no cambia el criterio**: poder pagar una sombra no es
motivo para ponerla en todos lados. Cada regla de abajo se evaluó de nuevo
por su propio mérito al entrar a la fase 13, no por inercia ("ya se
puede").

**Se cae** (existía solo por el CPU/disco viejo):

- Prohibición de animaciones — vuelven, cortas (menos de un quinto de
  segundo) y **en toda la app, también en la pantalla de venta** (El dueño,
  2026-10-03: "las animaciones son una miseria", eligió animar todo): nunca
  demoran lo que se tipea ni el cobro, y respetan "reducir animaciones" del
  sistema. Piezas y lugares en `DISENO.md`, "Movimiento".
- Prohibición de `BoxShadow` en cualquier lado — los bloques (`Superficie`, que reemplazó a `Bloque`)
  siguen sin sombra porque la jerarquía por diferencia de color ya
  funciona y es más simple, no porque no se pueda pagar una. Los diálogos
  sí pueden llevar una sombra suave para despegarse del fondo.
- Prohibición de `Card` — `Superficie` sigue siendo la unidad visual única de
  la app por consistencia (un solo lenguaje visual, Regla de armonía), no
  porque `Card` traiga una elevación que ya no se puede pagar.
- `NoSplash.splashFactory` / `highlightColor: transparent` a nivel de
  tema — el ripple de Material vuelve: es la señal de "el clic entró" que
  hoy no existe en ningún botón de la app.
- El simulador de resolución de debug pasaba 1366×768/1280×720 (las dos
  candidatas de la PC vieja); pasa a simular 1920×1080 (el objetivo de
  diseño nuevo) y 1366×768 (ahora el piso mínimo que tiene que verse
  digno, no el objetivo). Ver `DISENO.md`.
- "Sin dependencias pesadas" como regla dura por costo de hardware — sigue
  siendo buen criterio no acumular peso porque sí (eso no cambió), pero ya
  no hay que rechazar una librería solo por el costo en una máquina que no
  existe más.

**Se queda** (no era por la máquina, es criterio de diseño o del negocio):

- Toda lista larga con `ListView.builder`, nunca `Column` dentro de
  `SingleChildScrollView` — es buena práctica de cualquier forma, no un
  parche de hardware.
- Sin gestor de estado ceremonioso (`provider`/`setState` alcanzan) — la
  app sigue siendo del mismo tamaño; no hay más complejidad de estado que
  gestionar por tener una máquina más rápida.
- Contraste medido, nunca blanco puro sobre negro puro (`DISENO.md`) —
  El dueño mira esta pantalla doce horas por día, seis días por semana; eso
  no cambió con la máquina.
- La densidad de la pantalla de venta — búsqueda, total y medios de pago
  siempre visibles sin scrollear sigue siendo la regla (el carrito en sí
  puede scrollear desde el remake de disposición de fase 13, ver sección
  "Pantalla de venta"), porque sigue siendo la pantalla de mostrador con
  gente esperando, no una limitación de CPU.

El desarrollo se sigue haciendo en otra máquina y el binario se copia al
local — conviene un script que buildee y copie en un paso (esto no cambió).

## Prioridad: arranque vs. operación

El arranque de la app puede tardar. Se paga una sola vez por día, con la persiana
baja. Lo que **no puede tardar es la operación**: buscar un producto, agregarlo al
carrito, cambiar el medio de pago, cobrar. Eso se repite decenas de veces por día
con gente esperando.

**Si en algún momento hay que elegir entre arrancar más rápido y operar más
rápido, se elige operar.** Precargar todo lo que haga falta al inicio (catálogo
completo en memoria, configuración, lo que sea) con tal de que después no haya
ni una consulta a disco durante la venta. Esto reemplaza la idea anterior de
"cargar diferido lo que no sea la pantalla de venta": la carga puede no ser
perezosa, pero tiene que quedar completa y en memoria antes de que la pantalla
de venta esté operativa.

## Stack

- **Flutter Desktop (Windows)**
- **SQLite** vía `drift` — se necesitan **migraciones versionadas desde la fase 1**.
  El sistema anterior acumuló 34 migraciones; actualizar una app con datos reales
  sin migraciones es perder datos.
- `pdf` + `printing` para tickets
- `csv` para importar productos
- Sin backend, sin red, sin autenticación. Todo local.

## Arquitectura

```
lib/
├── domain/        # Funciones puras. Sin Flutter, sin SQLite, sin I/O.
├── data/          # Esquema, migraciones, queries, repositorios.
├── ui/            # Pantallas y widgets.
└── main.dart
```

**`domain/` no importa nada de Flutter ni de la base.** Es la única capa que se
testea exhaustivamente y la que tiene que sobrevivir a cualquier cambio de interfaz.

Módulos de dominio previstos: `dinero`, `ganancia`, `pesables`, `recargo_cigarrillos`,
`redondeo`, `reposicion`, `equilibrio`, `retiro`, `caja`, `ticket`.

## Convenciones que no se rompen

1. **Todos los montos son `int` en centavos.** Nunca `double` para plata.
2. **La línea de venta guarda precio y costo del momento** (costo-foto), no una
   referencia al producto.
3. **Cada fórmula vive en un solo lugar.** Si un cálculo aparece en dos archivos,
   está mal. El sistema anterior tuvo un bug que hubo que parchear dos veces por
   esto exacto.
4. **El subtotal de pesables pasa siempre por su helper.** Nunca multiplicar
   precio por kilo por cantidad directamente.
5. Redondeo hacia arriba al peso entero en todo precio o costo calculado.
6. Todo movimiento de stock deja rastro.
7. Comentarios que expliquen **por qué**, no qué. Las reglas raras de este negocio
   tienen motivos que no son obvios.
8. **El total de una venta se compone en este orden: recargo de cigarrillos
   primero, redondeo después, sobre el total que ya incluye el recargo.** No es
   arbitrario: el recargo forma parte de lo que el cliente tiene que pagar, así
   que tiene que estar adentro de lo que se redondea, no afuera. Invertir el
   orden parece inocente y da un total distinto cada vez que el recargo no es
   múltiplo exacto del paso de redondeo.

## Repo de referencia

El sistema anterior está en `neaserisgod/mikioscoonline`. Es **material de consulta,
no código a copiar**. Sirve consultar únicamente:

- `src/domain/` — las fórmulas ya validadas en producción y sus comentarios
- `prisma/schema.prisma` — el modelo de datos ya pensado
- `tests/unit/` — catálogo de casos borde que ya mordieron
- `docs/MODELO-FINANCIERO.md`

**No mirar** `src/app/`, `src/components/`, `src/services/` ni nada de Next, React
o Prisma. Ese diseño no aplica acá y solo contamina las decisiones.

Del modelo de datos anterior **se descarta**: `Organization`, `User` con contraseñas,
multi-tenant en un servidor compartido, suscripciones dentro de la app, AFIP, webhooks de Mercado Pago, `OrdenMpPendiente`,
`Comprobante`, `RecuentoPendiente`.

---

## Fases

**Desarrollar una fase por vez. No adelantarse. Cada fase se prueba antes de la siguiente.**

Esta sección describe QUÉ es cada fase, no si ya está construida — el estado real
(cerrada, en curso, pendiente) vive en `ESTADO.md` y cambia con el trabajo.

### Fase 1 — Dominio
Todos los módulos de `domain/` con sus tests. Sin interfaz, sin base de datos.
Escribir los tests primero, tomando como catálogo de casos los tests unitarios del
repo de referencia. Es la fase menos vistosa y la que sostiene todo lo demás.

### Fase 2 — Base de datos
Esquema SQLite con migraciones versionadas. Tablas: productos, categorías,
proveedores, clientes, medios de pago, gastos fijos, caja, sesiones de caja,
movimientos de caja, ventas, líneas de venta, pagos, movimientos de stock,
pendientes (fiados y encargues), historial de precios.
Importador de CSV de productos.

### Fase 3 — Pantalla de venta
La más importante: es el 80% del uso. Layout horizontal de tres columnas.
Ver la sección "Pantalla de venta" más abajo.

### Fase 4 — Cierre de caja
Conteo obligatorio antes de ver la diferencia. Separación de cigarrillos.
Reserva de fijos del día. Resumen.

### Fase 5 — Productos
Lista con buscador y filtros a la izquierda, detalle editable a la derecha,
margen en vivo mientras se escribe el precio, historial de precios.

### Fase 6 — Reposición y pedidos
Fila por proveedor: vendido, costo real, colchón, total a separar, día de pedido
y de entrega. Pedidos encargados de clientes.

### Fase 7 — Rentabilidad y equilibrio
Avance del mes contra los fijos, ganancia bruta, cascada de reparto.
Solo lectura, una columna de tarjetas.

### Fase 8 — Configuración
Secciones a la izquierda, contenido a la derecha.

### Fase 9 — Historial
Lista de días; al entrar, sus ventas, con edición de una venta ya cobrada
(revirtiendo stock y caja).

### Fase 10 — Impresión y respaldo
Tickets a impresora y a PDF local. Respaldo automático de la base a carpeta
configurable (Drive/OneDrive).

### Fase 11 — Sistema de diseño
Estilo bento, minimalista, armonizado entre pantallas — salvo en la pantalla de
venta, donde la densidad gana por sobre el aire (búsqueda, total y medios de
pago siempre visibles sin scrollear; el carrito sí puede scrollear desde el
remake de disposición de fase 13). **Reglas y valores completos en `DISENO.md`** —
escalas de espaciado y tipografía, colores, el acento único, medidas de
alineación, y qué de eso era restricción de la PC vieja (sin sombras, sin
`Card`, sin animaciones — ver "Hardware" arriba, la mayoría se revisó en la
fase 13) y qué seguía por elección de diseño con cualquier máquina. Avance
real por pantalla en `ESTADO.md`.

---

## Pantalla de venta

Rediseño de composición 2026-09-25 (tres pasadas, ver `DECISIONES.md`):
primero se sacó la columna izquierda vieja (los resultados de escribir
pasaron a colgar de la barra de búsqueda misma, como un dropdown flotante);
después el dueño mandó una referencia de POS y pidió volver a un panel fijo
de carrito/cobro a la derecha, "manteniendo la estructura de dropdown"
(navbar + búsqueda); una tercera pasada corrigió cinco cosas puntuales de
esa versión (notificaciones, la búsqueda en el resto de la app, nombres
largos del carrito, el default de la grilla, los botones de cobro). La
composición actual:

**Venta es la pantalla principal** (El dueño, 2026-10-03): la app arranca
acá y la tecla Inicio vuelve acá; el tablero ("Inicio") es una sección más.

**Franja superior** — navbar y acciones de caja, en una fila (2026-10-03):
- Centro: las secciones como pastillas (la activa con fondo), centradas en
  la ventana y sin la marca (el nombre del comercio ya está en la barra de
  la ventana). No hay sidebar ni dropdown.
- Derecha: Configuración como engranaje, y en Venta la campanita y
  "Cambiar de turno" / "Cerrar caja" (detalle abajo).

**Búsqueda** — rediseño "antigravity": ya no comparte fila con la navbar.
Vive en la columna de productos, debajo del título "Vender" y arriba de la
grilla (`BarraBusquedaVenta` en `pantalla_venta.dart`):
- Campo único de texto, con foco al arrancar. Todo entra por acá. Agregar un producto (tap,
  Alt+tecla o Enter) y cobrar devuelven el foco ahí solos — es la
  continuación natural de seguir vendiendo; un diálogo secundario (Mixto,
  Varios, gasto/ingreso rápido, arqueo intermedio, editar un acceso
  directo, imprimir) YA NO lo hace (El dueño, 2026-09-16: "dejar de robar el
  foco al hacer otra cosa") — se queda donde haya quedado al cerrarse.
  - Mientras se escribe, un dropdown ANCLADO al campo mismo (no una
    columna fija de la pantalla) cuelga justo debajo con nombre, precio y
    stock por fila, 6 a 8 filas antes de scrollear. Flechas para moverse,
    Enter para agregar. Una sola coincidencia viene preseleccionada.
  - Si no hay coincidencias, el mismo dropdown muestra "Sin coincidencias"
    y nada más — dar de alta un producto nuevo es siempre desde
    Proveedores, nunca desde acá (El dueño, 2026-09-16: se sacó la alta
    rápida de esta pantalla).
  - En TODAS las demás pantallas de gestión la búsqueda (versión liviana,
    `BarraBusquedaGlobal`) es una **lupa** en la navbar (2026-10-03): Ctrl+F
    la abre y el campo se expande hasta tapar las pastillas; al cerrarla
    vuelve vacío. Ahí no agrega nada al carrito (esas pantallas no tienen
    uno): elegir un resultado vuelve a Venta con el texto ya cargado, y
    desde ahí sigue el camino de siempre. En Venta, Ctrl+F enfoca el campo
    único (que nunca se esconde detrás de la lupa).


**Notificaciones** — tercera pasada (El dueño: *"NO QUIERO QUE APAREZCA EL
COSO DEL ARQUEO OCUPANDO TODO... UN APARTADO NOTIFICACIONES"*): el aviso
de arqueo cada 2hs ya no es un banner de ancho completo en el cuerpo — es
una campanita en la franja superior, con un punto de acento cuando hay
algo pendiente. Al tocarla, un panel chico con el aviso y el botón "Hacer
arqueo", o "Sin novedades por ahora" si no hay nada. Único lugar de avisos
que no son parte del flujo de vender.

**Cuerpo, dos zonas**

Izquierda (`Expanded`): pills de categoría + grilla de productos navegable
(tocar para agregar, una forma MÁS de cargar el carrito además de
escribir/escanear) — todo el catálogo con stock, organizado por categoría.
Ya no hay una tira de accesos directos arriba de la grilla, ni un sistema
para asignarle una tecla Alt+ a un cigarrillo puntual (El dueño, cuarta
pasada: "ahora no hacen falta los accesos rapidos... sacar la tira Y el
sistema de accesos directos entero" — la grilla cubre el acceso rápido
táctil; los cigarrillos se venden igual, por búsqueda o tocando la
grilla). Alt+V (Varios) y Alt+C (Vuelto) siguen andando como siempre —
son atajos fijos, nunca fueron parte del sistema de accesos directos que
se sacó. **"Más vendidos" es la pill de entrada** (El dueño, tercera pasada:
"me abrumo al ver tantos productos... los 10 mas vendidos por default"),
calculado de verdad contra el historial de ventas (excluye anuladas);
"Todos" y cada categoría siguen disponibles como pills aparte. Sin
historial todavía (instalación nueva), "Más vendidos" se cae a mostrar el
catálogo entero en vez de una grilla vacía.

Derecha (ancho fijo) — panel de carrito + cobro apilados:

1. **Arriba (`Expanded`, scrollea si no entra)** — el carrito. Una línea
   por producto: nombre (hasta 2 líneas — El dueño, tercera pasada: "los
   nombres largos no se ven bien"), cantidad o gramos, precio unitario
   (solo por unidad, no pesables, y solo si el panel tiene ancho para
   mostrarlo), subtotal, y un ícono de tacho para eliminar esa línea
   puntual (con mouse — no hay atajo de teclado para esto, a propósito:
   ver "Sin stock..." más abajo por el mismo criterio de una sola forma
   de hacer las cosas).
   - Cantidad ajustable con mouse: botones "−"/"+" al lado (solo por
     unidad, restar en 1 saca la línea entera), y doble clic sobre la
     cantidad o los gramos abre un campo para tipear el valor exacto de
     un tirón (anda para las dos formas de línea).
   - Última línea agregada resaltada.
   - Nombre en rojo si el stock quedó en 0 o negativo (se vende igual) —
     caso cada vez más raro desde que sin stock no se puede agregar (en la
     búsqueda aparece atenuado, 2026-10-03)
     (`REGLAS-NEGOCIO.md` §8): pasa si se agregó al carrito antes de
     llegar a 0, o con stock ya negativo de antes.

2. **Abajo, alto fijo** — panel de cobro, horizontal, siempre visible sin
   scrollear:
   - Total grande, como pieza destacada de ancho completo (degradé +
     resplandor).
   - Desglose solo cuando corresponde: recargo QR, descuento, redondeo.
   - Descuento sobre el total de la venta entera (Regla 17, generalizada):
     el cajero elige $ o %, nunca por línea.
   - Cuatro botones de medio de pago en **grilla 2×2** (El dueño, tercera
     pasada: "los botones de cobro... no se ven bien" — en una sola fila
     de 4, el panel angosto truncaba la etiqueta), cada uno con su color
     propio y grandes: Efectivo, QR, Débito, Mixto. Mixto abre campo para
     la parte en efectivo. QR y Débito son dos acciones separadas para
     quien cobra (cada una manda su propia orden a la terminal Point —
     fase 12, ver `ESTADO.md`, todavía sin código), pero en la caja
     **siguen siendo un solo medio de pago, "Mercado Pago"**: los dos
     liquidan al mismo saldo, y separarlos ahí rompería el arqueo y todo
     lo que asume un solo medio no efectivo. El canal (QR/débito) se
     guarda como dato del pago, no como un medio de pago nuevo.
   - Botón de cobrar.

Regla dura: **el carrito scrollea si no entra completo, pero el resto del
mostrador — búsqueda, total, los cuatro medios de pago — está siempre
visible, nunca detrás de un scroll.** Es la pantalla de mostrador con
gente esperando: lo que se toca para cobrar no puede quedar fuera de
vista por un carrito largo.

### Entrada del campo único

| Se escribe | Resultado |
|---|---|
| Código escaneado | Agrega el producto, cantidad 1 |
| Mismo código otra vez | Suma cantidad en la misma línea |
| Código desconocido | Aviso "Sin coincidencias" — no se puede cargar desde acá |
| Texto | Busca productos, abre dropdown |
| `200 queso barra` | 200 gramos del pesable; el dropdown filtra solo pesables y muestra el subtotal calculado |

La búsqueda **ignora mayúsculas y acentos**.

### Atajos

Todos con **`Alt`**, para que nunca choquen con la escritura. Impresos en cada
botón, en tamaño chico. Las dos excepciones (2026-10-03) son de toda la app,
no de cobrar: `Ctrl+F` busca (en Venta enfoca el campo único) y la tecla
`Inicio` vuelve a Venta (salvo escribiendo en un campo, donde mueve el cursor).

- `Alt+E` efectivo · `Alt+Q` QR · `Alt+D` débito · `Alt+X` mixto · `Alt+M`
  cobro manual
- `Alt+Q`/`Alt+D` (y los botones QR/Débito con mouse) eligen el canal nada
  más — de vuelta a dos pasos (El dueño, 2026-09-08: "necesito cobro
  manual... no hay más modal para seleccionarlo", revierte el paso único
  de la fase 12). "Cobrar" (`Enter` con el campo vacío, o el botón) recién
  ahí abre el diálogo que manda la orden a la terminal Point.
- `Alt+M`, o el botón "Cobrar a mano (sin terminal)" que aparece una vez
  elegido QR/Débito: cobra la venta directo, sin tocar la terminal —
  mismo camino que "Cobrar a mano" del diálogo de Point cuando la orden
  falla, pero elegible desde el arranque. Solo tiene efecto con un canal
  ya elegido; con Efectivo puro no hace nada (no pasa por Point).
- `Enter` con el dropdown abierto: agrega el producto seleccionado
- `Enter` con el campo vacío: cobra la venta
- `Esc`: cancela la venta entera
- Guion para gasto rápido (ya no hay teclas de cigarrillos propias — el
  sistema de accesos directos configurables se sacó, cuarta pasada de este
  rediseño)
- `Alt+I` ingreso rápido (espejo de gasto rápido: mismas tres cajas — cajón
  normal, lata, Mercado Pago —, pero suma en vez de restar)

El recargo de cigarrillos **no tiene tecla**: se calcula solo según el medio de pago.

---

## Qué es configurable y qué no

**Configurable:** los tres montos del recargo de cigarrillos · ganancia de referencia (sobre el precio)
por categoría · fondo fijo de caja · reserva diaria de fijos · día del retiro
semanal · colchón de reposición por proveedor · paso de redondeo en efectivo
(default 100) · producto del botón de vuelto · rutas de respaldo y de PDF · qué
secciones se ven y en qué orden · productos, precios, costos, proveedores,
categorías, medios de pago, gastos fijos.

**Fijo en el código:** encabezado del ticket · atajos de teclado · y todas las
reglas de negocio del documento de dominio (reposición igual al costo real,
efectivo redondea y virtual no, recargo completo en mixtos, cigarrillos a la lata
a precio de lista, arqueo obligatorio, sin stock no se vende — ver
`REGLAS-NEGOCIO.md` §8).
