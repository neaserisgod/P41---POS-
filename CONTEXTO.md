# Para retomar el proyecto — leer esto primero

Puerta de entrada para una sesión nueva (otra cuenta de Claude, otra persona) que no estuvo en las conversaciones de
desarrollo. Resume **qué es el sistema, cómo está armado, qué se hizo hasta hoy, qué quiere el dueño y cómo trabaja**, y
apunta al documento que es dueño de cada tema. Actualizado al **2026-10-03**.

Orden de lectura sugerido: este archivo → `CLAUDE.md` (cómo está armado el código y sus convenciones) → `ESTADO.md`
(lo último, arriba de todo) → `REGLAS-NEGOCIO.md` antes de tocar dominio → `DECISIONES.md`/`TRAMPAS.md` antes de cambiar
algo que ya funciona → `DISENO.md` antes de tocar pantallas. El sitio tiene su propio `CONTEXTO.md` en
`neaserisgod/NodoSurPage`.

---

## 1. Qué es

**Nodo Sur POS**: sistema de caja y gestión para comercios chicos (kioscos, almacenes). Nació para **La Plazoleta**, un
almacén de barrio en Bariloche, cuyo dueño es quien pide y prueba todo. Tres piezas:

| Pieza | Dónde | Qué hace |
|---|---|---|
| **PC** (Windows) | este repo, `lib/` salvo `lib/companion/` | La caja: vender, cobrar, cerrar caja, proveedores, separaciones, historial, configuración. Base SQLite local (drift). |
| **Celular** (Android, "companion") | este repo, `lib/companion/` | Vender y cobrar, productos y precios, conteo de stock, gastos/ingresos, arqueo y cierre, historial y cierres, configuración. Base propia sincronizada. |
| **Sitio** (horsepos.com) | repo `neaserisgod/NodoSurPage` | Web pública, cuentas con Google, negocios/sucursales/miembros, suscripciones, sync en la nube, copias, actualizaciones, y Mercado Pago por negocio. Cloudflare Worker + D1 + R2. |

Hay un tercer repo (`horsepospronative`) que no se tocó en estas sesiones.

## 2. Cómo trabaja el dueño (importante)

- Escribe en español rioplatense, rápido y con errores de tipeo. **Respuestas cortas, simples, sin jerga técnica.** Si
  pregunta "no entendí", reexplicar en criollo, no repetir.
- **Hacer caso a lo que pide, literal.** No suponer que se equivocó ni "corregirlo"; si algo no cierra, preguntar.
  Ejemplo real: dijo que probó con la cuenta activa y no había que dudarlo.
- **No inventar causas.** Si no se encontró el problema, decirlo y pedir el dato concreto (una captura, el PDF del día).
  Las cuentas de la caja se auditaron a fondo (ver `ESTADO.md`): los negativos que vio eran error humano, no del sistema.
- **Publicar solo cuando lo pide.** "Mergeá" = mezclar el PR; "lanzá" = publicar. Sin esas palabras, dejar el PR abierto
  y preguntar. Nunca mezclar ni publicar por iniciativa propia.
- Decisiones de negocio o ambiguas se preguntan; las técnicas (nombres, estructura) se deciden sin preguntar.
- Siempre: link al PR, qué se probó y **qué no se probó** (por ejemplo "no probado en un celular real").

## 3. Arquitectura del sistema

```
            ┌──────────── horsepos.com (Cloudflare Worker, D1, R2, Durable Object) ────────────┐
            │ cuentas Google · negocios/sucursales/miembros · suscripciones (MP de Nodo Sur)     │
            │ /api/sync (buzón por sucursal + WebSocket SyncHub) · /api/backup (copias cifradas) │
            │ /api/update (versiones Windows/Android) · /api/mp/* (Mercado Pago DEL NEGOCIO)     │
            └───────────▲───────────────────────────────▲──────────────────────────▲─────────────┘
                        │ token de dispositivo           │                          │ OAuth del negocio
                  PC (Windows)  ◄── wifi del local ──►  Celular (Android)     Mercado Pago (Point, pagos)
                  SQLite propia     (servidor HTTP       SQLite propia
                  lib/servidor/      en la PC)            lib/companion/
```

- **Datos**: cada equipo tiene su base. Se sincronizan por la nube (`lib/servicios/sync_nube.dart` ↔ `/api/sync`,
  alcance = sucursal, "gana el último en llegar") o, si el celular está en el wifi de la PC, por HTTP directo
  (`lib/servidor/servidor_companion.dart`; se empareja con un código de 6 números que muestra la PC, o con un toque si
  la PC y el celular son de la misma sucursal: la PC avisa su dirección del wifi al sitio, `/api/device/pc-local`). Motor: `lib/data/repositorio_sincronizacion.dart`
  (`global_id` + `actualizado_en`; logs de movimientos solo se insertan).
- **Mercado Pago**: dos cosas separadas. (1) Las **suscripciones** de los clientes a Nodo Sur usan la cuenta de Nodo Sur
  (`MP_ACCESS_TOKEN` del sitio). (2) Los **cobros del negocio** usan la cuenta del comercio, conectada por OAuth en
  `/negocio` (app de MP "Nodo Sur POS"). El token queda cifrado en el servidor; la PC y el celular le piden al sitio:
  crear/consultar/cancelar órdenes Point, imprimir en la terminal, y leer los cobros reales del día
  (`/api/mp/orden`, `/api/mp/imprimir`, `/api/mp/cobros`). La PC también puede cobrar directo con un token local
  (Configuración → Impresión y posnet), con un interruptor "Cobrar e imprimir por Nodo Sur".
- **Actualizaciones**: Windows (Inno Setup + WinSparkle, firma DSA) y Android (APK) se publican en R2 y se registran en
  D1 (`releases`). El sitio conserva solo las 2 últimas por plataforma y canal.

### Código de este repo

```
lib/domain/     funciones puras (dinero, caja, recargo, redondeo, separación, conciliación MP...). Tests exhaustivos.
lib/data/       esquema drift (schemaVersion 50), migraciones, repositorios (ventas, cierre, gastos, sync, PDFs...).
lib/ui/         pantallas de la PC (venta, cierre, proveedores, separaciones, historial, configuración...).
lib/companion/  la app del celular entera.
lib/servicios/  cuenta y sync de Nodo Sur, Mercado Pago por el servidor, actualizaciones, módulos activos.
lib/servidor/   API HTTP que la PC expone al celular por wifi.
```

Lo que más importa del dinero vive en `lib/data/repositorio_cierre.dart` (esperado de efectivo, MP y lata),
`repositorio_ventas.dart`, `repositorio_gastos.dart`/`repositorio_ingresos.dart`, `repositorio_deuda_proveedores.dart`
y `lib/domain/caja.dart`. `test/data/conciliacion_caja_test.dart` arma 120 días al azar con todas las formas de mover
plata y comprueba que el esperado coincide con un libro independiente.

## 4. Lenguaje de diseño

Estilo **antigravity.google + horsepos.com**, igual en PC, celular y web: fondo blanco, bloques gris claro `#F3F4F7`
sin sombra, tinta `#121317` como acento (botón principal, pastilla activa), botones y selectores en forma de pastilla,
radios grandes, tipografía **Figtree**, títulos grandes y livianos, poco texto. Fuente de verdad: `DISENO.md` (tokens en
`lib/ui/tema/`). Mocks de referencia en `Lenguaje de diseño/*.dc.html` y en `NodoSurPage/mocks/antigravity/`
(`docs/anotaciones-mocks.md` lista lo que está en los mocks pero no en la app).

- **PC** (2026-10-03): Venta es la pantalla principal (la tecla Inicio vuelve ahí). Arriba, las secciones como
  pastillas centradas (sin la marca), el **engranaje de Configuración** a la derecha y la búsqueda como lupa (Ctrl+F);
  en Venta, la campanita y "Cambiar de turno"/"Cerrar caja", y la búsqueda es el campo único siempre a la vista. Configuración en **5 grupos** (Negocio, Caja y cobros, Productos,
  Equipos y cuenta, Apariencia) con pastillas por sección.
- **Celular**: barra inferior flotante de tinta con 4 pestañas de texto (Inicio, Productos, Historial, Gestión);
  pantallas secundarias con título grande y "Volver" en pastilla arriba a la derecha.
- Para revisar a ojo: `flutter test test/ui/capturas_escritorio_test.dart` y `test/companion/capturas_companion_test.dart`
  dejan PNG en `capturas/` (ignorada por git).

## 5. Cómo se trabaja y se publica

- Rama por tarea desde `main`, PR, CI (`tests.yml`: análisis + `flutter test`). **Merge solo con el OK del dueño.**
- **Windows**: el merge a `main` publica **solo si el título del commit empieza con `release:`** (estable) o `beta:`
  (beta). Cualquier otro merge no compila nada. También se puede disparar a mano (`publicar-beta.yml`). El número de
  compilación lo sube el propio workflow.
- **Android**: a mano, `publicar-apk.yml` con `canal`, `notas` y **`build` mayor que el último APK publicado — mirarlo en
  el sitio, no en estos docs** (el 03/10 los docs decían 2128 y ya existía la 2129: se pisó el archivo)
  (consultarlo en `/admin/` → Versiones del sitio, o en la tabla `releases`). Sin `build` usa el de `pubspec.yaml`, que
  puede chocar con uno ya publicado (error "exists").
- Todos los workflows de publicación comparten el grupo de concurrencia `publicar`: van de a uno. **Nunca publicar dos
  veces la misma versión a la vez**: pisan el mismo archivo en R2 y la firma deja de coincidir (pasó con la 2122).
- Probar en una sesión en la nube: el contenedor no trae Flutter. Bajar Flutter 3.47.5 (la versión de los workflows),
  `flutter pub get`, `flutter analyze` (tiene que dar "No issues found!", CI lo exige) y
  `flutter test --exclude-tags bench` (~1981 tests, ~5 minutos).

## 6. Estado al 2026-10-03

- **Publicado**: Windows estable **1.0.0.2129** y Android estable **1.0.0+2130** (03/10, noche). Incluyen todo lo de la
  lista de abajo, el plan v2 (`docs/PLAN.md`) y los arreglos de la revisión (`ESTADO.md`).
- Lo hecho entre el 02 y el 03/10 (detalle en `ESTADO.md` y en cada PR):
  - Mercado Pago por negocio: cobro QR/débito por el servidor (PC sin token y celular sin PC), interruptor para usarlo
    aunque haya token local, imprimir en la terminal por el servidor, registro de actividad en `/negocio`.
  - Cuentas: los miembros heredan lo del dueño; cuentas admin/eximidas se tratan como suscripción activa sin
    vencimiento; un empleado ve "las copias las maneja el dueño".
  - Auditoría de caja: las fórmulas están bien (test de 120 días). Arreglos: abrir caja desde el celular arrastra el
    último MP contado; una caja cerrada no se reabre por una fila vieja de la sync; cerrar caja desde el aviso de
    "cerrar la app" termina con "Cerrar el sistema".
  - Celular: exportar el día completo en PDF (Gestión → Cierres → un día), bienvenida al primer arranque, entrar con
    Google y "Configurá tu negocio".
  - Cierre de caja: **"Mercado Pago según Mercado Pago"** (cobros reales, comisiones, neto, diferencia de cobros, cobros
    sin venta y ventas sin cobro) en la PC y en el detalle de cada cierre del celular.
  - Rediseño de la navbar (engranaje) y de Configuración (grupos) en PC y celular.
  - Rendimiento: índices en la base, "Más vendidos" memorizado; en el sitio, caché de 2 minutos del estado de pago y
    caché larga de `.js`/`.css` con huella.

## 7. Lo que el dueño quiere y quedó pendiente

Por orden aproximado de interés (nada de esto está pedido para hacer ya; confirmar antes de arrancar):

1. **Integración total con Mercado Pago** (le interesa mucho): avisos en vivo por webhooks (venta confirmada al
   instante y alerta de cobros que entraron sin venta), **devoluciones desde el POS** al anular una venta cobrada por
   MP, **saldo real automático** en el cierre (reporte de liquidaciones; hay que verificar que se pueda), cobrar con
   **QR en pantalla** sin terminal, y crédito/cuotas por la Point. El MCP de Mercado Pago solo sirve para documentación,
   webhooks de la app, usuarios de prueba y homologación: no lee la cuenta real.
2. **Pagar a un proveedor con Mercado Pago desde el celular**: lo factible es copiar alias/CVU y abrir la app de MP, y
   al volver preguntar "¿se hizo la transferencia?" para registrarla. MP no devuelve solo a la app; detectar la
   transferencia por API está sin verificar. Se le propuso; no lo pidió todavía.
3. "Etapa 3" de Mercado Pago: esconder como "avanzado" los campos de token y terminal locales de la PC, después de
   unos días de uso del cobro por el servidor.
4. Ofrecido y no pedido: hacer obligatorio el motivo de cada gasto.
5. Limpieza: `.gitignore` no ignora `android/build` ni `android/app/build` (en una PC que compila el APK aparecen miles
   de cambios). (Los restos de Firestore/Supabase que se listaban acá ya no existen en el código.)
   (`ESTADO.md` ya se resumió el 2026-10-03; el detalle viejo está en `docs/ESTADO-ARCHIVO.md`.)

## 8. Datos útiles

- Admin del sitio: `/admin/` (solo administradores). Ahí están versiones, clientes y el bloqueo de una versión.
- D1 del sitio: base `nodosur`. Tablas clave: `users`, `orgs`, `branches`, `memberships`, `invitations`, `devices`,
  `releases`, `mp_conexiones` (token cifrado), `mp_actividad`, `sync_lotes`.
- Antes de hacer público este repo: `python3 tool/limpiar_datos_personales.py --aplicar`.
