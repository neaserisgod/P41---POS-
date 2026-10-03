# Plan: cómo va a quedar el proyecto (2026-10-03, v2)

Segunda versión, después de **leer el código** (ver "Qué leí" al final) y de pedir el dueño la estética de horsepos.com /
antigravity.google y el estándar de diseño y funcionamiento de Google (`docs/ESTANDARES-GOOGLE.md`). Reemplaza al plan anterior.
Cada fase son PR chicos con `flutter analyze` y `flutter test` en verde; no se publica nada
hasta que el dueño diga "lanzá"; lo que cambia una regla de negocio se pregunta antes (`CLAUDE.md`).

## Dónde quedamos (2026-10-03) — leer esto primero para seguir con otra cuenta

**Rama:** `claude/zealous-galileo-5dz6j6`, en los dos repos (`P41---POS-` es donde está todo el trabajo; `NodoSurPage` no se tocó). Último commit al cierre de esta nota: ver `git log`.
**Cómo se verifica:** `flutter analyze lib` (28 avisos viejos de estilo, no deben subir) y `flutter test --exclude-tags bench` (~1964 tests, ~5 min, deben pasar todos). Los benchmarks con 60.000 ventas: `flutter test --tags bench`.
**Cómo se trabaja:** un commit por tema (probar antes), tests con cada cambio, docs en el mismo commit, `CLAUDE.md` manda. Pie de commit: `Co-Authored-By` y `Claude-Session` del recordatorio de la sesión. Cuidado: `git checkout <archivo>` descarta trabajo sin commitear (me pasó una vez).

**Hecho:** Fase 0 completa salvo 0.12 y 0.13; Fase 1 casi (ver su estado más abajo); Fase 3 completa en PC y celular; 0.11 número de venta global. Decisiones del dueño aplicadas: tema sigue al sistema, productos sin stock atenuados en la búsqueda de Venta (no se pueden agregar), número global, "Entregar y anotar deuda".

**Lo que sigue, en orden:**
1. Fase 1 restante: esqueleto de carga en Equilibrio, Dashboard y Cierre (hoy `SizedBox.shrink()`; Respaldo y Comparar precios ya lo tienen). Ojo: el esqueleto anima sin parar y los tests de Equilibrio y Dashboard esperan con `pumpAndSettle` mientras carga, así que se cuelgan: hay que cambiar esos tests a `pump` con duración antes de ponerlo (Cierre es un modal, queda como está); tests de accesibilidad (`test/accesibilidad/`) de Equilibrio, Respaldo, Impresión, los diálogos y el resto del celular; anillo de foco visible; ~~borrar `ColoresPlazoleta.claro/oscuro` y `Bloque`~~ (hecho 2026-10-03); unificar `companion/tema` en `ui/tema` (el dueño dijo que le da igual: decisión técnica, hacerlo solo si se puede sin cambiar cómo se ve el celular).
2. Fase 2 — fricciones por pantalla (lista abajo) y revisar los 37 `catch (_) {}` mudos de la PC.
3. Fase 4 — avisos y paridad PC/celular. 4. Fase 6 — Mercado Pago. 5. Fase 5 — roles: **el dueño dijo "para después"**; no empezar sin su matriz de permisos.
6. Pendientes de Fase 0: 0.12 (valores por defecto heredados: fondo $150.000, reserva $70.000, vuelto $100 — pregunta de negocio) y 0.13 (token por celular).

**Deuda conocida:** al cobrar una deuda la línea es "Varios" sin costo, así que cuenta como ganancia completa (guardar el costo al anotar la deuda); la búsqueda de Venta del celular sigue ocultando los productos sin stock (la PC los atenúa); el texto "fiado" sigue en el cierre/PDF del día (la marca `FIADO` de la venta es el rastro y se mantiene); se borró `DISENO 2.md` (variante vieja de `DISENO.md` que nadie referenciaba; sigue en el historial de git).

## Decisiones del dueño que ordenan el plan

1. Fiado y encargue son lo mismo → **una sola cosa: "Encargues"**.
2. Gasto/ingreso/Varios/vuelto en Venta: no por ahora.
3. **Roles: sí**, y exigen rehacer el sistema de usuarios.
4. **Paridad PC/celular: sí** (deuda con proveedores en ambos, Consultar precio en la PC). Sin cobro mixto en el celular (decisión
   2026-09-07, no se toca).
5. Mercado Pago: lo útil ya anda; solo falta lo nuevo (webhooks, devoluciones desde el POS, saldo real, QR en pantalla).
6. **Estética horsepos/antigravity y estándar Google en toda la app.**

## Fase 0 — Correcciones antes de tocar nada (en curso, 2026-10-03)

Cada una con su test. Estado real, incluyendo lo que **corregí de mi propio diagnóstico** después de mirar el código de nuevo.

| # | Qué | Estado |
|---|---|---|
| 0.1 | Cobrar contra una caja ya cerrada: `registrarVenta` ahora lo rechaza (`SesionCerradaException`, dentro de la transacción). La carga histórica es la única excepción. PC avisa en pantalla; el servidor del celular responde 409 (y si el pago por terminal ya se aprobó, deja la orden sin resolver para que el cierre avise). Registrar el pago de un fijo también lo verifica | ✅ hecho, con test (repositorio y servidor) |
| 0.2 | Reintento duplicado desde el celular: el celular manda una `claveCobro` por intento y el servidor devuelve la misma venta si se repite (10 min, en memoria) | ✅ hecho, con test contra el servidor real |
| 0.3 | "Tokens hardcodeados" en `comparador_precios_todoatucasa.dart` | ❌ **diagnóstico mío incorrecto**: son las credenciales de invitado que el propio sitio le manda a cualquier visitante y el dueño ya tiene la autorización de Todo a tu Casa documentada en el archivo. No se toca. Lo que sí queda anotado: ese comparador está atado a comercios de Bariloche |
| 0.4 | SQL de sincronización con nombres de columna remotos | ✅ hecho: solo se escriben columnas que existen en la tabla local (también tolera columnas de versiones más nuevas), con test |
| 0.5 | El cursor de sincronización LAN avanzaba aunque quedaran filas sin aplicar | ✅ hecho: las no aplicadas se reintentan al final del ciclo y, si siguen sin aplicar, el cursor no pasa de la más vieja. ⚠️ El ejemplo que di (configuración antes que productos) **estaba mal**: la lista ya baja productos primero. No pude armar un test del caso con dos bases independientes |
| 0.6 | Cambios que no se sincronizaban: activar/desactivar producto (y en lote), activar/desactivar promo, medios de pago, y 6 escrituras de proveedores (pagar, revisar ganancia, colchón, etc.) ahora actualizan `actualizadoEn`. Separar/desmarcar **ya lo hacían** | ✅ hecho (sin test propio) |
| 0.7 | Importar CSV: fila corta, nombre o código duplicado, todo en una transacción, y **reimportar ya no deja el stock en 0** (descubierto al probar; antes pisaba el stock de todos los productos sin dato). Si la planilla trae stock, queda en el registro de movimientos | ✅ hecho, con 3 tests |
| 0.8 | Búsqueda "7 up" / "2 cocas": si ningún pesable coincide, se busca el texto completo | ✅ hecho, con test |
| 0.9 | Pago de fijo sin caja abierta ya no cierra el diálogo como si hubiera guardado | ✅ hecho |
| 0.10 | Conteo de stock: los ajustes se aplican en una sola transacción | ✅ hecho |
| 0.11 | Número de venta global y en el ticket | ✅ hecho (dueño dijo que sí, 2026-10-03): `ventas.numero` = `prefijo-correlativo` (ej. K7-0123), prefijo de dos letras por equipo (`configuracion_tabla.prefijo_ventas`, no se sincroniza), migración v48. Sale en el ticket de la terminal y el PDF. Las ventas viejas siguen con `#id`. Se ve también en el historial (PC y celular) y en el diálogo de imprimir |
| 0.12 | Valores heredados del local original (fondo $150.000, reserva $70.000, `vueltoEsCaramelo` = $100) | ⏸ es una decisión de negocio (qué valor por defecto tiene un comercio nuevo): se pregunta |
| 0.13 | Token del celular = acceso total sobre el wifi | ⏸ pasa a "token por celular, revocable desde el sitio", fase aparte |
| 0.14 | Escalabilidad con dos años de historial (60.000 ventas, medido con `test/bench`) | ✅ hecho: Inicio 8,3 s → 0,25 s; Separaciones 6 s → 0,13 s; lista de proveedores 6,5 s → 0,14 s; cierres anteriores 3,3 s → 0,1 s; el detalle de un proveedor se rompía por el límite de variables de SQLite y ahora tarda 16 ms |
| 0.15 | Log a archivo (`<datos>/logs/errores.log`, rotado a 512 KB) y los tres puntos por donde se escapa un error en Flutter | ✅ hecho, con test. Los 37 `catch (_) {}` mudos se revisan pantalla por pantalla en la Fase 2 |

**Sin probar:** el cambio de cursor de sincronización (0.5) pasa los tests existentes pero no tiene uno propio; las correcciones de `actualizadoEn` (0.6) tampoco.

## Fase 1 — Un solo sistema de diseño (base de todo lo visual)

**Estado (2026-10-03):** ✅ fondo oscuro `#0E0F12`; ✅ `es_AR`; ✅ tests de accesibilidad (tamaño táctil, etiquetas, contraste) en Venta, Inicio, Historial,
Proveedores, Separaciones, Configuración, Encargues, Cierre y 4 pantallas del celular, y lo que fallaba arreglado; ✅ `AlertDialog`/`ElevatedButton` crudos fuera
del kit (queda a propósito el botón rojo de restaurar); ✅ esqueletos en 4 pantallas; ✅ deshacer en Venta (quitar línea, Esc, cerrar pestaña) y en el carrito
del celular. **Falta:** pasar `companion/tema` a `ui/tema` (hoy `AcentosCompanion`, chip, `superficie` y `colores_companion` siguen separados — decidir cuál versión
gana, cambia cómo se ve el celular); ~~borrar los tokens legados `ColoresPlazoleta.claro/oscuro` y `Bloque`~~ (hecho 2026-10-03); esqueleto en Equilibrio, Respaldo, Comparar precios,
Dashboard y Cierre; tests de accesibilidad de Equilibrio, Respaldo, Impresión, diálogos y el resto del celular; anillo de foco visible; tema oscuro "seguir al
sistema" (pregunta 5 al dueño).

- Unificar `companion/tema/*` dentro de `ui/tema/` (ver `docs/ESTANDARES-GOOGLE.md` §1).
- Tokens: acento único, colores solo de estado, oscuro `#0E0F12`, borrar legados, cero `Color(0xFF…)` sueltos.
- Kit completo y usado en todos lados: `Modal`, `HojaInferior` (celular), `BotonPrimario/Secundario`, `Campo*`, `EstadoVacio/Error`,
  `Esqueleto*`, `Snackbar con deshacer`, `FilaDato`, píldoras. Se eliminan los `AlertDialog`/`ElevatedButton` crudos.
- `es_AR` y `flutter_localizations`; `Semantics`/`tooltip` en todo ícono; anillo de foco; objetivos de 48 dp.
- Test automático de contraste y de tamaño táctil sobre el kit.

## Fase 2 — Fricciones por pantalla (sobre el kit nuevo)

**PC — Venta:** `−`/`+`, tacho y cerrar pestaña a 48 dp; **deshacer** al quitar línea, cerrar pestaña y Esc (Esc ya no cancela la
venta de golpe: pide deshacer); cantidad editable con un toque en la cantidad (hoy es doble clic oculto); "Cambiar de turno" y
"Cerrar caja" con texto; pantalla de caja cerrada con el kit; atajos del mixto (Mitad, $10.000, $20.000); sin stock: mostrar el
producto atenuado en la búsqueda con "sin stock" en vez de "Sin coincidencias" (❓ regla `REGLAS-NEGOCIO.md` §8, se pregunta).
**PC — Inicio:** filas de "Stock bajo" y "Encargues" tocables; tarjeta "Deuda con proveedores"; esqueleto al cargar.
**PC — Cierre:** el paso de conteo gana "Cancelar"; MP y lata contados pasan a "0 si no usás"; protección de doble clic.
**PC — Proveedores:** "Conteo de stock" visible; "Avanzado" se parte en "Pedidos y pagos" y "Datos del proveedor";
Importar CSV con plantilla descargable y errores completos.
**PC — Configuración:** guardado uniforme con aviso; sin jerga ("fase 12"); "Desconectar celulares" con confirmación.
**PC — Historial/Impresión:** "Cargar día histórico" a un menú; imprimir ticket con el kit; número de venta global.
**Celular:** carrito persistente (como los borradores de la PC) y con deshacer; un solo "Hacer arqueo" (queda en Gestión);
Gestión reordenada (Cerrar caja · Arqueo · Separaciones · Conteo · Encargues · Carga histórica · Cuenta · Configuración);
Historial con **Ventas y Cierres**; "Anular" en vez de "Eliminar"; pestaña "Productos" (hoy "Precios"); un toque menos en el cobro
(confirmar desde la misma vista del medio de pago).

## Fase 3 — Unificar fiado y encargue (Encargues)

**Estado (2026-10-03), PC:** ✅ hay un solo nombre ("Encargues y deudas") en Inicio y en el módulo; ✅ "Entregar y anotar deuda" (el dueño dijo que sí):
el encargue pasa a una deuda por el total a precios de hoy, sin mover el stock otra vez, y se cobra desde la sección "Deudas" de la pantalla Encargues
(efectivo o Mercado Pago, entra como venta del día). Hay 1 encargue en la base real y ningún fiado (el dueño no recuerda fiados). ✅ **celular** con las mismas dos acciones (endpoints `/encargues/<id>/deuda`, `/deudas`, `/deudas/<id>/cobrar`, con test; también sin la PC). **Falta:** el texto "fiado" en el cierre/PDF del día (la marca `FIADO` de la venta se mantiene: es el rastro)
y un límite conocido: al cobrar la deuda la línea de venta es "Varios" sin costo, así que esa venta cuenta como ganancia completa.

Una tarjeta en Inicio, una pantalla en PC y celular, un solo nombre. Se saca el módulo "Fiado" y sus textos (cierre, PDF,
`modulos.dart`). **No se borra ninguna columna ni fila.**
❓ ¿Hay fiados cargados en la base real? (consulta de solo lectura, antes de empezar).
❓ ¿"Entregar y anotar deuda" (se lo lleva y paga después) entra en Encargues? Hoy un encargue aparta stock y entregar abre la venta.

## Fase 4 — Avisos y paridad PC/celular

Campanita única (PC) y Inicio (celular) con: arqueo vencido, falta separar, stock bajo, caja de ayer sin cerrar, encargues por
entregar. Deuda con proveedores en ambos; Consultar precio en la PC (extender Ctrl+F).

## Fase 5 — Roles y usuarios (con documento de diseño primero)

- Hoy: `usuarios` = nombre + activo, sin PIN; los roles existen en el sitio (`permisos.js`, `/api/device/me`) pero el POS no los
  usa, y el token del celular es administrador total.
- Propuesta: `domain/permisos.dart` con `puede(rol, capacidad)` (un solo lugar); capacidades: ver costos y ganancia, anular y
  editar ventas, ver/cerrar cierres, retirar ganancia, configuración, pagar proveedores, editar precios/importar, gestionar
  usuarios. **Los permisos los aplica la app** (se oculta y se bloquea la acción según rol y PIN; decisión del dueño 2026-10-03: no se valida en la nube, cada equipo tiene su base completa, así que protege del error pero no de un ataque técnico).
  Rol por cuenta cuando el equipo está vinculado y PIN por usuario cuando se usa solo local (migración: `rol`, `pin_hash`).
  El sitio suma el rol por usuario del POS y su sincronización.
- ❓ Hay que definir con el dueño qué puede y qué no puede un empleado y un encargado.

## Fase 6 — Mercado Pago: lo que falta
Webhooks, devolución desde el POS al anular, saldo real en el cierre, QR en pantalla. Se lee primero el código de MP a fondo
(solo leí lo que toca el cobro y la conciliación). Detalle en `CONTEXTO.md` §7.

## Fase 7 — Pedido a proveedores por WhatsApp (si se confirma)

Limpieza: ~~`.gitignore` de `android/build`, restos de Firestore, `Bloque` y tokens deprecados~~ (hecho 2026-10-03; el análisis da "No issues found!" y CI lo exige), ver fallos
intermitentes de `test/ui/venta/`.

## Orden

**0 → 1 → 2 → 3 → 4 → 5 → 6** (7 cuando se decida). La 0 va primero porque es plata y datos; la 1 antes que la 2 para no
arreglar dos veces la misma pantalla; la 5 y la 6 son las grandes y conviene hacerlas con la app ordenada.

## Preguntas al dueño

Respondidas el 2026-10-03: tema oscuro sigue al sistema; hay 1 encargue y ningún fiado conocido en la base; "Entregar y anotar deuda" sí entra en Encargues; sin stock se ve atenuado; número global con prefijo del equipo sí. **Abierta:** qué puede hacer cada rol (después).

## Qué leí y qué no

Leído línea por línea: `domain/`, `data/`, `servidor/` y `servicios/`, el sitio (`functions/`, `worker.js`) y **toda la UI de la
PC** (venta, cierre, inicio, proveedores, separaciones, historial, impresión, configuración, respaldo, navegación, tema).
Celular: leí gestión, inicio, menú, carrito y cobro, historial, encargues, precios, separaciones, cierre, formulario de
producto, entrar con cuenta y el cliente local. **No leí completos**: bienvenida/animaciones, asistente de negocio nuevo, carga
histórica, configuración, conteo y arqueo del celular, las páginas estáticas del sitio, ni ejecuté la app en dispositivos
reales (falta probar con Windows al 125 %/150 %, escáner, cajón y terminal Point).
