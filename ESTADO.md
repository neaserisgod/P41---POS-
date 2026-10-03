# Estado actual — La Plazoleta / Nodo Sur POS

**Fuente de verdad de cómo está el proyecto HOY.** Corto a propósito: lo que ya se resolvió vive en `DECISIONES.md`
(por qué se hizo así) y `TRAMPAS.md` (bugs que no hay que repetir); el detalle cronológico anterior al 2026-10-03 está en
[`docs/ESTADO-ARCHIVO.md`](./docs/ESTADO-ARCHIVO.md). Si algo de acá contradice al código o a `git log`, gana el código y
se corrige este archivo. Para retomar desde cero: `CONTEXTO.md`.

Se actualiza al cerrar cada sesión de trabajo. **No agregar acá historias de "Resuelto"**: una línea en "Últimos cambios"
y el detalle en `DECISIONES.md`.

---

## Publicado (2026-10-03)

- **Windows**: estable 1.0.0.2129 (03/10, al 100 %).
- **Android**: estable 1.0.0+2130 (03/10, al 100 %). **La 1.0.0+2129 de Android quedó rota**: una segunda
  publicación con el mismo número pisó su archivo en R2 y el sitio conserva la firma del anterior. La 2130 la reemplaza
  (los celulares toman la más nueva). La 2129 quedó **bloqueada** en el sitio (03/10).
- **Sitio** (`NodoSurPage`): en producción al mezclar a `main`.

## Métricas

- **Tests**: 1981 verdes (`flutter test --exclude-tags bench`, 2026-10-03). La suite completa a veces muestra 1–3 fallos que cambian de nombre
  entre corridas, todos en `test/ui/venta/` (hit-test warnings de Flutter); en aislamiento pasan siempre. Flakiness del
  runner, sin investigar.
- **`flutter analyze`**: "No issues found!" en todo el repo (2026-10-03); CI lo exige.
- **`schemaVersion`**: **50** (`lib/data/database.dart`; las v40–v50 están comentadas en `onUpgrade`).
- Capturas para revisar a ojo: `flutter test test/ui/capturas_escritorio_test.dart` y
  `test/companion/capturas_companion_test.dart` (PNG en `capturas/`, ignorada por git; no son golden tests).

## Fases del roadmap

Qué es cada una: `CLAUDE.md`, sección "Fases".

| Fase | Contenido | Estado |
|---|---|---|
| 1–10 | Dominio, base, venta, cierre, productos, reposición, rentabilidad, configuración, historial, impresión y respaldo | **Cerradas** |
| 11 | Sistema de diseño | Aplicado a toda la app (ver `DISENO.md`) |
| 12 | Cobro por terminal Point (QR/débito) | **Cerrada** (ver abajo, Mercado Pago) |
| 13 | Pulido visual tras el cambio de hardware | **Cerrada** (el tema automático sigue al del sistema, decisión del dueño 2026-10-03) |
| 14 | Remake de estética basado en la companion (navbar superior, `Superficie`) | **Hecho** en todas las pantallas; luego se pasó al lenguaje "antigravity" (`DISENO.md`) |
| — | Generalización a Nodo Sur POS (módulos, rubros, marca configurable) | **Completa** (fases 1–5 y 8–9; 6 y 7 descartadas) |
| — | Nube: cuenta, copias, sync por sucursal, actualizaciones | **Hecha**; probar con equipos y cuentas reales sigue siendo lo que más falta |

Quedó en el archivo, sin tocar a propósito: `Bloque` y los tokens viejos deprecados (Fase 6 del remake) y la vitrina de
test `test/capturas/pantalla_muestra_kit.dart`. Borrarlos solo tiene sentido con el visto bueno visual final del dueño.

## Lo que existe hoy (mapa rápido)

- **PC**: menú de 6 apartados (Inicio · Venta · Proveedores · Separaciones · Historial · Configuración) con Configuración
  como engranaje y búsqueda en lupa (Ctrl+F). Venta: carrito + cobro a la derecha, grilla de productos con "Más vendidos"
  por defecto, ventas abiertas múltiples y persistentes (Alt+N / Alt+S), descuento sobre el total, cobro manual.
  Proveedores: lista y detalle, cuenta corriente ("Deuda"), precio automático por ganancia, edición masiva, promos.
  Separaciones (solo de hoy, dividido cajón/Mercado Pago), Encargues por apartado, Inicio con tablero del día y "Este mes"
  (estado de resultados, margen necesario). Ventana propia con barra de título dibujada.
- **Celular** (`lib/companion/`): vender y cobrar, productos y precios, conteo de stock, gastos/ingresos, arqueo y cierre,
  historial y cierres (con PDF del día completo), pagar proveedor (necesita la PC), encargues, bienvenida y "Configurá tu
  negocio". Sync con la PC por wifi y, si no contesta, por la nube.
- **Sync**: motor en `repositorio_sincronizacion.dart` (`global_id` + `actualizado_en`, "gana el último en llegar"). Ya no
  hay Supabase ni Firebase como transporte: los restos de Firestore de arriba son código muerto.
- **Mercado Pago**: cobro QR/débito por la Orders API de la Point (`MODELO__SERIAL` como terminal; cancelar por API solo
  funciona mientras la orden está en `created`), con token local o por el servidor de Nodo Sur (MP del negocio conectado
  en `/negocio`). En la caja QR y Débito son un solo medio, "Mercado Pago"; el canal se guarda por pago. El cierre muestra
  "Mercado Pago según Mercado Pago" (cobros reales, comisiones, diferencias; nunca frena el cierre).
- **Distribución**: instalador Inno Setup + WinSparkle (firma DSA, `dsa_pub.pem` en el repo, la privada fuera). Publicar:
  título del commit con `release:` o `beta:`; Android a mano con `publicar-apk.yml` y un `build` mayor al último publicado.
  Detalle en `CONTEXTO.md` §5 y `docs/PRIMERA-VERSION.md`.

## Últimos cambios (02–03/10/2026)

- **Auditoría de la caja**: `test/data/conciliacion_caja_test.dart` arma 120 días al azar y coincide siempre con un libro
  independiente; las diferencias negativas que veía el dueño eran plata que salió sin anotarse. Arreglos: abrir caja desde
  el celular arrastra el último MP contado, la sync no reabre una caja `CERRADA` con una fila vieja, y cerrar desde el aviso
  de "cerrar la app" termina en "Cerrar el sistema".
- **Mercado Pago por negocio**: cobro por el servidor, interruptor "Cobrar e imprimir por Nodo Sur", imprimir en la
  terminal por el servidor, conciliación en el cierre.
- **Navbar y Configuración rehechas** (engranaje, 5 grupos) en PC y celular; navbar centrada con lupa y Venta como pantalla
  principal.
- **Celular**: PDF del día completo, bienvenida, "Entrar con Google", "Configurá tu negocio", accesos de Inicio (Pagar
  proveedor, Hacer arqueo), encargues.
- **Rendimiento**: índices en la base, "Más vendidos" memorizado; en el sitio, caché de 2 min del estado de pago y caché
  larga de estáticos.

- **Arreglos de la revisión (03/10)**: una PC instalada de cero sincroniza su usuario inicial, "Varios" y las categorías
  de la plantilla (antes nacían sin `global_id` y el celular rechazaba sus cajas; migración v49 para las ya instaladas);
  un mixto cuyo total baja después de cargar el efectivo ya no graba Mercado Pago negativo (y `registrarVenta` rechaza
  pagos negativos); "con cuánto paga" del celular ya no repite $100.000. La configuración del negocio (recargos, redondeo,
  módulos) es una sola fila por equipo también para la sync: nace con un id fijo, una que llega con otro id se toma como
  la misma y gana la más reciente (antes una PC nueva no la mandaba nunca, y un equipo podía quedar con dos filas y sin
  poder leerla); migración v50 deja una sola.

## Sin probar en real

- Conciliación de Mercado Pago contra la cuenta real en un cierre.
- Bienvenida, "Entrar con Google" y "Configurá tu negocio" en un celular real y contra la nube real.
- Pagar proveedor del celular contra la PC real; sync por la nube con dos dispositivos reales (WebSocket/Durable Object).
- Una actualización real de una PC instalada contra el feed real, y que WinSparkle rechace una firma inválida.
- Impresión física de prueba en la Point (consume un ticket; la corre o autoriza el dueño).
- Ganancia real en vez de markup (migración v46) y asistente contable (primera parte): se escribieron sin Flutter en la
  sesión; correr `flutter analyze` y `flutter test` antes de darlos por cerrados.
- **Validación real del dominio**: correr una semana en paralelo con el sistema anterior y comparar cierres. Los tests
  prueban que el código hace lo pedido, no que el modelo de negocio sea correcto.

## Pendiente

**Pedido por el dueño / a confirmar antes de arrancar** (lista completa y orden de interés en `CONTEXTO.md` §7):
integración total con Mercado Pago (webhooks, devoluciones desde el POS, saldo real en el cierre, QR en pantalla, cuotas);
pagar a un proveedor con MP desde el celular; "etapa 3" de MP (esconder token/terminal locales como avanzado); motivo
obligatorio en cada gasto.

**Pendientes técnicos conocidos:**

- Fiado cobrado sin verificar estado ni transacción; separar/pagar proveedor sin transacción (de la revisión del
  2026-09-29, no tocado). Las búsquedas tipo "7 up" ya se arreglaron (`docs/PLAN.md`, 0.8).
- Ventas abiertas: decidir si el fiado pasa a ser una venta abierta con nombre; refrescar precios de un borrador viejo.
- Cuenta corriente: falta la deuda total en el Dashboard; el celular no tiene el apartado.
- Promos: no se venden desde el celular; una venta ya cobrada se edita como líneas sueltas. Precio automático por proveedor:
  el celular no tiene el selector ni sincroniza el % y la marca de fijo.
- Dos caminos para reimprimir un ticket (pantalla Impresión y detalle del día en Historial), sin unificar.
- Limitación conocida: en una venta mixta con varios productos no se sabe cuál se pagó con qué medio (no se guarda medio de
  pago por línea). Los montos y el arqueo salen bien; arreglarlo es un cambio de modelo, y el dueño dejó que quede así
  (`lib/data/planilla_dia.dart`).
- Carga histórica: sigue producto por producto (el mock proponía totales del día con costo estimado; el dueño decidió no).

- Clave privada DSA (`Documents\la_plazoleta_claves\dsa_priv.pem`): respaldarla (USB + otro lugar). Si se pierde, ninguna PC
  instalada recibe más actualizaciones. Firma de código real: sin certificado todavía (SmartScreen avisa).

## Descartado (decisión del dueño, no pendiente)

- Descuento de Cliente Frecuente (Regla 17): no se hace. Las columnas `clientes.descuentoBp` y `ventas.descuentoCentavos`
  quedan sin usar a propósito (borrarlas es una migración sobre datos reales para no ganar nada).
- Reportes y Equilibrio como pantallas aparte (hoy Equilibrio es la mitad "del mes" de Inicio), retiro semanal de ganancias.
