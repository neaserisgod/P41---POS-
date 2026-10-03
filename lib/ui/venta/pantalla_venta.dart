// La pantalla de venta. Franja superior (navbar + búsqueda de ancho fijo,
// centrada) y debajo dos zonas (grilla de productos navegable, carrito +
// cobro) — rediseño de composición 2026-09-25, ver el comentario de
// `build()`. Ya no hay una tira de accesos directos por Alt+tecla (El dueño,
// cuarta pasada: "ahora no hacen falta los accesos rapidos... sacar la
// tira Y el sistema de accesos directos entero" — la grilla, táctil, la
// reemplaza). Pantalla completa, sin scroll de página salvo el propio del
// carrito. Fase 13 (hardware) devolvió las
// animaciones de transición entre pantallas (`tema.dart`) — acá adentro
// siguen sin usarse: nada de esto (agregar al carrito, cambiar de medio,
// cobrar) pasa por un `Navigator`, y la densidad/velocidad de tecleo siguen
// ganando por sobre cualquier adorno mientras hay un cliente esperando.
//
// Todos los atajos de acá son Alt+algo (incluidos los directos y el gasto
// rápido, no solo los medios de pago): el campo único tiene el foco todo el
// tiempo, así que cualquier tecla sin Alt se interpretaría como texto.
//
// Se manejan con un handler global (`HardwareKeyboard.instance.addHandler`)
// en vez de `Shortcuts`/`Actions` o un `Focus.onKeyEvent`: un FocusNode solo
// puede pertenecer a un widget de foco a la vez, y el campo único ya usa el
// suyo. Un handler global no compite por ese nodo y funciona sin importar
// qué widget tenga el foco en un instante dado — que en la práctica siempre
// va a ser el campo único.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../navegacion/refresco_por_celular.dart';
import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../data/database.dart';
import 'venta_en_curso.dart';
import '../../data/repositorio_secciones_menu.dart';
import '../../domain/medio_pago.dart';
import '../cierre/pantalla_cierre.dart';
import 'cancelar_venta_con_deshacer.dart';
import '../comun/botones.dart';
import '../comun/encabezado_pantalla.dart';
import '../comun/modal.dart';
import '../impresion/dialogo_imprimir_ticket.dart';
import '../navegacion/navbar_superior.dart';
import '../navegacion/navegacion_gestion.dart';
import '../navegacion/route_observer.dart';
import '../tema/superficie.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'acciones_venta.dart';
import 'columna_busqueda.dart';
import 'columna_carrito.dart';
import 'columna_cobro.dart';
import 'dialogo_apertura_caja.dart';
import 'dialogo_arqueo_intermedio.dart';
import 'dialogo_movimiento_rapido.dart';
import 'venta_controlador.dart';
import '../tema/iconos.dart';

class PantallaVenta extends StatefulWidget {
  const PantallaVenta({
    super.key,
    required this.db,
    this.textoBusquedaPendiente,
    this.encarguePendienteId,
  });

  final AppDatabase db;

  /// Texto a precargar en el campo único al llegar — lo manda
  /// `BarraBusquedaGlobal` (`navegacion/barra_busqueda_global.dart`) cuando
  /// se busca un producto desde OTRA pantalla de gestión (El dueño, tercera
  /// pasada: "quiero que la barra de busqueda este en todos lados"). Nunca
  /// agrega nada por su cuenta — solo deja el campo listo para que el
  /// usuario termine el mismo camino de siempre.
  final String? textoBusquedaPendiente;

  /// Encargue por apartado a entregar: al llegar abre una venta con lo apartado (lo manda la pantalla de Encargues).
  final int? encarguePendienteId;

  @override
  State<PantallaVenta> createState() => _PantallaVentaState();
}

class _PantallaVentaState extends State<PantallaVenta>
    with RouteAware, RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _controlador.cargarTodo();

  late final VentaControlador _controlador;

  /// Qué pantallas de gestión aparecen en el menú y en qué orden (fase 8) —
  /// "Cerrar caja" y "Configuración" quedan fijos, no pasan por acá.
  List<SeccionMenu> _seccionesVisibles = [];

  @override
  void initState() {
    super.initState();
    _controlador = VentaControlador(widget.db);
    _controlador.addListener(_publicarVentaEnCurso);
    HardwareKeyboard.instance.addHandler(_manejarTeclaGlobal);
    _controlador.cargarTodo().then((_) {
      if (mounted) {
        // El arranque tiene que ser inmediato (CLAUDE.md): el foco se pide
        // recién cuando ya hay algo cargado para mostrar, no antes.
        final encargue = widget.encarguePendienteId;
        if (encargue != null) unawaited(_controlador.cargarEncargue(encargue));
        final pendiente = widget.textoBusquedaPendiente;
        if (pendiente != null && pendiente.isNotEmpty) {
          // Dispara `_alCambiarTexto` solo (el controlador ya escucha a
          // `campoTexto`) — no hace falta llamar a nada más a mano.
          _controlador.campoTexto.text = pendiente;
        }
        _controlador.focoCampoPrincipal.requestFocus();
      }
    });
    _cargarSecciones();
  }

  Future<void> _cargarSecciones() async {
    final secciones = await listarSeccionesVisibles(widget.db);
    if (mounted) setState(() => _seccionesVisibles = secciones);
  }

  bool _soyRaiz = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ruta = ModalRoute.of(context)!;
    routeObserver.subscribe(this, ruta as PageRoute<dynamic>);
    if (ruta.isFirst && !_soyRaiz) {
      _soyRaiz = true;
      ventaEsRaiz.value = true;
    }
  }

  /// Lo que otra pantalla mandó a cargar al volver a Venta (texto de la búsqueda global o un encargue a entregar).
  void _tomarPedido() {
    final pedido = pedidoParaVenta.value;
    if (pedido == null) return;
    pedidoParaVenta.value = null;
    if (pedido.encargueId != null) unawaited(_controlador.cargarEncargue(pedido.encargueId!));
    final texto = pedido.texto;
    if (texto != null && texto.isNotEmpty) _controlador.campoTexto.text = texto;
  }

  void _publicarVentaEnCurso() =>
      hayVentaEnCurso.value = _controlador.hayVentaAbierta;

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    HardwareKeyboard.instance.removeHandler(_manejarTeclaGlobal);
    if (_soyRaiz) ventaEsRaiz.value = false;
    _controlador.removeListener(_publicarVentaEnCurso);
    _controlador.dispose();
    super.dispose();
  }

  /// Se llama cuando esta pantalla vuelve a quedar arriba de todo porque la
  /// ruta que la tapaba se sacó — sin importar cuál era esa ruta ni por
  /// dónde se volvió (`Navigator.pop`, la flecha de atrás, o `popUntil`
  /// saltando de una sección de gestión a otra sin pasar por acá, ver
  /// `route_observer.dart`). Cualquiera de esas pantallas pudo haber
  /// cambiado productos, proveedores, stock o configuración.
  @override
  void didPopNext() {
    _controlador.cargarTodo().then((_) {
      if (mounted) _tomarPedido();
    });
    _controlador.focoCampoPrincipal.requestFocus();
  }

  bool _manejarTeclaGlobal(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // `HardwareKeyboard.instance.addHandler` es un registro global: no sabe
    // nada del `Navigator`, así que sigue llamando a este handler aunque
    // haya un diálogo (o cualquier otra pantalla pusheada) tapando la venta.
    // Bug real, encontrado antes de la fase 12 — ver TRAMPAS.md: Alt+Q con
    // el diálogo de mixto abierto cambiaba el medio elegido por detrás, y
    // una tecla de accesorio directo con "alta rápida" abierta agregaba el
    // producto al carrito sin que el diálogo se enterara.
    //
    // `ModalRoute.of(context)` engancha una dependencia de `InheritedWidget`
    // — esta pantalla se reconstruye cada vez que una ruta se pone o se
    // saca de encima. Es aceptable (ya se reconstruye por `provider` en
    // cada cambio del carrito) y está evaluado a propósito, no pasado por
    // alto: en una app que cuida cada repintado por el hardware, un
    // rebuild ocasional al navegar es un costo real pero raro, contra un
    // bug de plata que pasa todos los días.
    //
    // `== false` explícito, no `!isCurrent`: si `ModalRoute.of()` da `null`
    // (sin ruta contenedora — no debería pasar en esta pantalla, pero el
    // default tiene que ser seguro), el handler sigue activo en vez de
    // apagarse por accidente.
    if (ModalRoute.of(context)?.isCurrent == false) return false;

    final c = _controlador;

    // Bug real (reportado por el dueño): con la caja cerrada, `ColumnaBusqueda`/
    // `ColumnaCarrito`/`ColumnaCobro` desaparecen de la pantalla ("Caja
    // cerrada.", ver `build()`), pero este handler es global — no sabe nada
    // del árbol de widgets ni de qué hay pintado — y seguía reaccionando a
    // Alt+directo/Alt+V/Alt+X/Alt+E/Alt+Q, agregando al carrito o cambiando
    // el medio elegido a espaldas de la pantalla. El resultado: se podía
    // "vender" (armar un carrito entero) mientras se mostraba el aviso de
    // caja cerrada, y aparecía recién al volver a abrir caja, ya cargado.
    // Mismo bloqueo si la sesión abierta es de un día anterior (Regla 5): no
    // se puede vender bajo ella aunque siga técnicamente "abierta".
    if (c.sesion == null || c.sesionVencida) return false;

    // Ctrl+F: el atajo de buscar de toda la app (El dueño, 2026-10-03). En Venta el campo ya está a la vista: lo enfoca.
    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      c.focoCampoPrincipal.requestFocus();
      return true;
    }

    // `!isControlPressed`: en Windows, AltGr (tecla de la derecha en un
    // teclado latinoamericano/español — necesaria para escribir '@', '#',
    // etc.) se reporta como Ctrl+Alt sintético, así que `isAltPressed` solo
    // da `true` también con AltGr. Sin este chequeo, escribir un carácter
    // compuesto con AltGr en el campo de búsqueda podía disparar un atajo
    // reservado (ej. Alt+Q cambia el medio de pago a QR) en vez de escribir
    // el carácter, si la letra de esa combinación coincidía con una de
    // `teclasReservadas`.
    if (HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isControlPressed) {
      final etiqueta = event.logicalKey.keyLabel.toLowerCase();

      // Gobernado por `teclasReservadas` (acciones_venta.dart) — las únicas
      // combinaciones Alt+tecla que quedan desde que se sacó el sistema de
      // accesos directos configurables (El dueño, cuarta pasada).
      if (teclasReservadas.containsKey(etiqueta)) {
        switch (etiqueta) {
          case 'e':
            c.elegirMedio(ComposicionPago.efectivo);
          // QR y Débito eligen el canal nada más (El dueño, 2026-09-08: volvió
          // a ser de dos pasos — "necesito cobro manual... no hay más modal
          // para seleccionarlo"). "Cobrar" (Enter con el campo vacío, o el
          // botón) recién ahí abre el diálogo que manda la orden a la
          // terminal; Alt+M cobra directo sin pasar por ella.
          case 'q':
            c.elegirCanalDirecto('qr');
          case 'd':
            c.elegirCanalDirecto('debit_card');
          case 'm':
            cobrarAMano(context, c);
          case 'x':
            abrirMixto(context, c);
          case 'v':
            agregarVarios(context, c);
          case 'c':
            final vuelto = c.productoVuelto;
            if (vuelto != null) {
              c.agregarProducto(vuelto);
              c.focoCampoPrincipal.requestFocus();
            }
          case '-':
            _abrirGastoRapido();
          case 'i':
            _abrirIngresoRapido();
          case 'n':
            c.nuevaVenta();
          case 's':
            if (c.cantidadPestanas > 1) {
              c.cambiarAPestana((c.pestanaActiva + 1) % c.cantidadPestanas);
            }
        }
        return true;
      }
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      c.moverSeleccion(1);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      c.moverSeleccion(-1);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      cancelarVentaConDeshacer(context, c);
      return true;
    }
    return false;
  }

  /// Turno entrante: un turno es una sesión completa (El dueño, sesión del
  /// 31/08/2026), así que después de un cierre voluntario mid-día tiene que
  /// poder abrirse una hoja nueva ahí mismo — reiniciar la app entera para
  /// seguir vendiendo era el callejón sin salida que esto reemplaza.
  Future<void> _abrirCaja() async {
    await mostrarDialogoAperturaCaja(context, db: widget.db);
    await _controlador.cargarTodo();
    if (mounted) _controlador.focoCampoPrincipal.requestFocus();
  }

  // Diálogos secundarios (gasto/ingreso rápido) — el foco ya no vuelve solo
  // al cerrarse (El dueño, 2026-09-16: "dejar de robar el foco al hacer otra
  // cosa"), a diferencia de agregar un producto o cobrar.
  Future<void> _abrirGastoRapido() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    await mostrarDialogoGastoRapido(
      context,
      db: widget.db,
      sesionCajaId: sesion.id,
      usuarioId: sesion.usuarioAbrioId,
    );
  }

  Future<void> _abrirIngresoRapido() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    await mostrarDialogoIngresoRapido(
      context,
      db: widget.db,
      sesionCajaId: sesion.id,
      usuarioId: sesion.usuarioAbrioId,
    );
  }

  /// Cierre desde la pantalla de venta — tanto el voluntario (botón "Cerrar
  /// caja" del pie) como el de una sesión de un día anterior (Regla 5,
  /// `_EstadoBloqueado` en `build()`) pasan por acá: los dos vuelven a esta
  /// misma pantalla al terminar, nunca hay nada más a donde ir.
  ///
  /// No recarga acá al volver — `didPopNext()` (`RouteAware`, ver
  /// `route_observer.dart`) lo hace solo apenas esta pantalla vuelve a
  /// quedar arriba, sin importar por dónde se volvió.
  Future<void> _irACierre() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    await mostrarModal<void>(
      context,
      builder: (context) => PantallaCierre(
        db: widget.db,
        sesionId: sesion.id,
        usuarioId: sesion.usuarioAbrioId,
      ),
    );
  }

  /// "Cambiar de turno" (2026-09-12, el dueño: viene ayuda de fin de semana a
  /// mitad de sesión) — mismo arqueo obligatorio que "Cerrar caja", nada
  /// queda sin contar antes de soltar la caja, pero encadena directo a
  /// abrir la hoja de quien entra en vez de dejar la pantalla en "Caja
  /// cerrada" esperando un segundo clic.
  Future<void> _cambiarTurno() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    // `cerrado` distingue "llegó a cerrar" de "canceló a mitad de camino"
    // (Esc en conteo/revisado) — `_controlador.sesion` todavía no se puede
    // usar acá para eso: recién se actualiza cuando `didPopNext()` termine
    // su propio `cargarTodo()`, después de este `await`.
    var cerrado = false;
    await mostrarModal<void>(
      context,
      builder: (context) => PantallaCierre(
        db: widget.db,
        sesionId: sesion.id,
        usuarioId: sesion.usuarioAbrioId,
        textoBotonFinal: 'Abrir para el que entra',
        onFinalizado: () {
          cerrado = true;
          Navigator.of(context).pop();
        },
      ),
    );
    if (cerrado) await _abrirCaja();
  }

  /// Arqueo sugerido cada 2hs (turnos por usuario, 2026-09-12; el dueño,
  /// 2026-09-15: "que se cambie a una sugerencia únicamente" — ya no
  /// bloquea la venta, solo muestra `_AvisoArqueoIntermedio` en `build()`
  /// mientras no se haga). A diferencia de "Cerrar caja"/"Cambiar de
  /// turno", no corta la sesión: solo recarga el controlador para que
  /// `arqueoIntermedioVencido` vea el arqueo recién registrado y deje de
  /// mostrar el aviso.
  Future<void> _hacerArqueoIntermedio() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    await mostrarDialogoArqueoIntermedio(
      context,
      db: widget.db,
      sesionId: sesion.id,
      usuarioId: sesion.usuarioAbrioId,
    );
    await _controlador.cargarTodo();
  }

  Future<void> _imprimirUltimoTicket() async {
    final ventaId = _controlador.ultimaVentaId;
    if (ventaId == null) return;
    await mostrarDialogoImprimirTicket(
      context,
      db: widget.db,
      ventaId: ventaId,
    );
  }


  /// "Dashboard" (la raíz, un clic para volver) + "Venta" (la pantalla en
  /// la que ya se está) + las secciones configurables visibles +
  /// "Configuración" (fija, no pasa por `secciones_menu`) — mismo orden que
  /// `itemsNavGestion` en el resto de las pantallas.
  List<ItemNavbarSuperior> get _itemsNav => [
    const ItemNavbarSuperior(clave: 'dashboard', etiqueta: 'Inicio'),
    const ItemNavbarSuperior(clave: 'venta', etiqueta: 'Venta'),
    for (final seccion in _seccionesVisibles)
      ItemNavbarSuperior(clave: seccion.clave, etiqueta: seccion.etiqueta),
    const ItemNavbarSuperior(clave: 'configuracion', etiqueta: 'Configuración'),
  ];

  /// Venta es la raíz de la app (El dueño, 2026-10-03): cada sección se abre encima con la misma navegación que el
  /// resto de las pantallas, y al volver se recargan las secciones (pudieron cambiar en Configuración).
  Future<void> _onSeleccionarSeccion(String clave) async {
    if (clave == 'venta') return; // ya estamos acá
    final sesion = _controlador.sesion;
    await navegarASeccionDeGestion(
      context,
      clave,
      db: widget.db,
      usuarioId: sesion?.usuarioAbrioId ?? 0,
      sesionCajaId: sesion?.id,
    );
    await _cargarSecciones();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<VentaControlador>.value(
      value: _controlador,
      child: Scaffold(
        body: SafeArea(
          child: Consumer<VentaControlador>(
            builder: (context, c, _) {
              // Primer frame, antes de que `cargarTodo()` resuelva: todavía
              // no hay sesión (ni se sabe si hay una) para decidir entre el
              // layout de venta o "Caja cerrada". Nada que mostrar todavía,
              // mismo criterio que el arranque de `main.dart`.
              if (c.cargando) return const SizedBox.shrink();

              final accionesPie = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // El arqueo sugerido cada 2 horas es parte de los turnos.
                  SiModulo(
                    Modulo.turnos,
                    hijo: _BotonNotificaciones(
                      hayArqueoVencido: c.arqueoIntermedioVencido,
                      onHacerArqueo: _hacerArqueoIntermedio,
                    ),
                  ),
                  _AccionesPie(
                    puedeCerrarCaja: c.sesion != null,
                    onCerrarCaja: _irACierre,
                    onCambiarTurno: _cambiarTurno,
                  ),
                ],
              );
              final hayVenta = c.sesion != null && !c.sesionVencida;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // "Estética Google" (El dueño, rediseño 2026-09-25): navbar
                  // a la izquierda, búsqueda al centro con ANCHO FIJO (no
                  // `Expanded` — El dueño: "la barra de busqueda debe ocpar un
                  // espacio fijo al centro, no extenderse en todos lados"),
                  // acciones de caja al extremo derecho — mismo patrón que
                  // la franja superior de Gmail/Drive. Sin sesión activa no
                  // hay nada que buscar (el handler global de teclado ya
                  // bloquea toda entrada en ese caso, ver más abajo) — la
                  // navbar sola vuelve a quedar sin acompañantes.
                  // Rediseño "antigravity": la barra de arriba lleva la marca,
                  // las secciones en pastillas y las acciones de caja; la
                  // búsqueda baja a la columna de productos, debajo del
                  // título "Vender" (igual que el mock).
                  // La búsqueda de Venta no se esconde detrás de la lupa: es el campo único (y el lector de códigos escribe
                  // ahí), siempre visible en la columna de productos (CLAUDE.md, "Pantalla de venta"). Ctrl+F lo enfoca.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
                    child: NavbarSuperior(
                      claveActiva: 'venta',
                      items: _itemsNav,
                      onSeleccionar: _onSeleccionarSeccion,
                      acciones: hayVenta ? accionesPie : null,
                    ),
                  ),
                  Expanded(
                    child: c.sesion == null
                        ? _EstadoBloqueado(
                            mensaje: 'Caja cerrada.',
                            etiquetaBoton: 'Abrir caja',
                            onPressed: _abrirCaja,
                          )
                        : c.sesionVencida
                        ? _EstadoBloqueado(
                            mensaje:
                                'Queda una sesión de un día anterior sin cerrar.',
                            etiquetaBoton: 'Cerrar caja',
                            onPressed: _irACierre,
                          )
                        : Padding(
                            padding: const EdgeInsets.all(Espaciado.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // El aviso de arqueo cada 2hs ya no vive acá
                                // (El dueño, tercera pasada: "NO QUIERO QUE
                                // APAREZCA EL COSO DEL ARQUEO OCUPANDO
                                // TODO... UN APARTADO NOTIFICACIONES") — se
                                // mudó a `_BotonNotificaciones`, en la
                                // franja superior.
                                // Rediseño de composición (2026-09-25,
                                // segunda pasada: El dueño mandó una
                                // referencia de POS y contestó "1 pero
                                // manteniendo la estructura de dropdown")
                                // — dos zonas: izquierda la grilla navegable
                                // por categoría (los resultados de escribir
                                // siguen colgando de la barra, arriba, sin
                                // relación con esto; cuarta pasada: se sacó
                                // la tira de accesos directos de encima, la
                                // grilla ya cubre el acceso rápido táctil);
                                // derecha un panel FIJO con el carrito
                                // (scroll propio si no entra completo —
                                // regla dura vieja de "sin scroll" revisada
                                // a propósito, ver CLAUDE.md) y el cobro al
                                // pie.
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            const EncabezadoPantalla(
                                              titulo: 'Vender',
                                              subtitulo:
                                                  'Escribí, escaneá o tocá un producto',
                                            ),
                                            const SizedBox(
                                              height: Espaciado.lg,
                                            ),
                                            LayoutBuilder(
                                              builder:
                                                  (context, restricciones) =>
                                                      SizedBox(
                                                        height: 60,
                                                        child:
                                                            BarraBusquedaVenta(
                                                              anchoDropdown:
                                                                  restricciones
                                                                      .maxWidth,
                                                            ),
                                                      ),
                                            ),
                                            const SizedBox(
                                              height: Espaciado.lg,
                                            ),
                                            const Expanded(
                                              child: RejillaProductos(),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: Espaciado.md),
                                      SizedBox(
                                        width: Medidas.anchoPanelCobroVenta,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              child: ColumnaCarrito(
                                                ventaConfirmada:
                                                    c.ultimaVentaId,
                                                totalConfirmadoCentavos: c
                                                    .ultimoTotalCobradoCentavos,
                                                onImprimir:
                                                    _imprimirUltimoTicket,
                                              ),
                                            ),
                                            const SizedBox(
                                              height: Espaciado.md,
                                            ),
                                            PanelCobro(
                                              usuarioId:
                                                  c.sesion?.usuarioAbrioId ?? 0,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Reemplaza el carrito cuando no se puede vender — sin sesión abierta, o
/// con una sesión abierta pero de un día anterior (Regla 5). El resto de la
/// pantalla (barra lateral, navegación) sigue disponible igual: El dueño,
/// 2026-09-06, "que no salga obligatoriamente al abrir la app" — el bloqueo
/// es solo para vender, nunca para el resto de la app.
class _EstadoBloqueado extends StatelessWidget {
  const _EstadoBloqueado({
    required this.mensaje,
    required this.etiquetaBoton,
    required this.onPressed,
  });

  final String mensaje;
  final String etiquetaBoton;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mensaje),
          const SizedBox(height: 12),
          BotonPrimario(texto: etiquetaBoton, onPressed: onPressed),
        ],
      ),
    );
  }
}

/// Campanita de notificaciones (El dueño, tercera pasada: *"NO QUIERO QUE
/// APAREZCA EL COSO DEL ARQUEO OCUPANDO TODO, DEBEMOS TENER UN APARTADO
/// NOTIFICACIONES"*) — reemplaza al banner de ancho completo
/// (`_AvisoArqueoIntermedio`, hasta acá) que empujaba todo lo de abajo
/// cada vez que pasaban 2hs sin arqueo. El aviso sigue siendo sugerencia,
/// no bloqueo (El dueño, 2026-09-15): se puede seguir vendiendo con el panel
/// cerrado; desaparece solo cuando se hace el arqueo
/// (`_hacerArqueoIntermedio` recarga `arqueoIntermedioVencido`) o cambia de
/// sesión.
///
/// Mismo mecanismo que el dropdown de resultados de búsqueda
/// (`columna_busqueda.dart::BarraBusquedaVenta`): `CompositedTransformTarget`
/// + `OverlayPortal` + `CompositedTransformFollower`, acá anclado a un
/// ícono en vez de a un campo, con `UnconstrainedBox` para que el panel se
/// mida por su contenido (mismo bug ya resuelto ahí). Queda como el único
/// lugar de avisos que no son parte del flujo de vender — no solo para el
/// arqueo, una base para sumar más el día que haga falta.
class _BotonNotificaciones extends StatefulWidget {
  const _BotonNotificaciones({
    required this.hayArqueoVencido,
    required this.onHacerArqueo,
  });

  final bool hayArqueoVencido;
  final VoidCallback onHacerArqueo;

  @override
  State<_BotonNotificaciones> createState() => _BotonNotificacionesState();
}

class _BotonNotificacionesState extends State<_BotonNotificaciones> {
  final _link = LayerLink();
  final _overlayController = OverlayPortalController();
  bool _abierto = false;

  @override
  void initState() {
    super.initState();
    _overlayController.show();
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (context) {
        if (!_abierto) return const SizedBox.shrink();
        return CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, Espaciado.sm),
          child: UnconstrainedBox(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 320,
              child: Superficie(
                relleno: colores.fondoBloque,
                // Arqueo opcional (El dueño, 2026-09-28: "que los arqueos
                // durante el turno dejen de ser obligatorios"): el botón está
                // siempre, y a las 2hs solo se prende el punto — el aviso
                // suave que eligió, sin panel ni banner que insista.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.hayArqueoVencido
                          ? 'Pasaron 2 horas desde el último arqueo.'
                          : 'Sin novedades por ahora.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Espaciado.xs),
                    Text(
                      'Contar la caja es opcional. Lo que cuentes queda '
                      'precargado en el cierre.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: Espaciado.md),
                    BotonSecundario(
                      texto: 'Hacer arqueo',
                      onPressed: () {
                        setState(() => _abierto = false);
                        widget.onHacerArqueo();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Tooltip(
              message: 'Notificaciones',
              child: Semantics(
                button: true,
                label: widget.hayArqueoVencido ? 'Notificaciones: hay un aviso pendiente' : 'Notificaciones',
                excludeSemantics: true,
                onTap: () => setState(() => _abierto = !_abierto),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(radioControlEscritorio),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(radioControlEscritorio),
                    onTap: () => setState(() => _abierto = !_abierto),
                    child: SizedBox(
                      width: Medidas.alturaControl,
                      height: Medidas.alturaControl,
                      child: Icon(
                        IconosPlazoleta.notificationsOutlined,
                        size: 20,
                        color: colores.textoSecundario,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.hayArqueoVencido)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colores.acento,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Acciones del extremo derecho de la navbar — "Cerrar caja" es una acción,
/// no una sección (El dueño): va apartada del listado de navegación por hueco,
/// nunca mezclada con él. "Imprimir ticket" ya no vive acá (fase 13, ítem
/// 3): dejó de ser una acción permanente, ahora aparece junto al acuse de
/// cobro (`ColumnaCarrito`) solo mientras hay algo reciente para imprimir.
/// Remake 2026-09-19: pasa de pie vertical de `BarraLateral` a fila de
/// íconos con tooltip en el slot `accion` de `NavbarSuperior` — siempre
/// ícono solo (la navbar ya es compacta de por sí en este slot, no
/// necesita su propio modo expandido).
class _AccionesPie extends StatelessWidget {
  const _AccionesPie({
    required this.puedeCerrarCaja,
    required this.onCerrarCaja,
    required this.onCambiarTurno,
  });

  final bool puedeCerrarCaja;
  final VoidCallback onCerrarCaja;
  final VoidCallback onCambiarTurno;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Separadas a propósito (El dueño, 2026-09-12): "Cerrar caja" es el fin
        // del día, no encadena nada después. "Cambiar de turno" es el mismo
        // arqueo obligatorio, pero para cuando viene ayuda a mitad de
        // sesión — al terminar, encadena directo a abrir la hoja de quien
        // entra en vez de dejar la venta bloqueada esperando un segundo clic.
        SiModulo(
          Modulo.turnos,
          hijo: _BotonAccion(
            icono: IconosPlazoleta.swapHoriz,
            etiqueta: 'Cambiar de turno',
            onPressed: puedeCerrarCaja ? onCambiarTurno : null,
          ),
        ),
        _BotonAccion(
          icono: IconosPlazoleta.lockOutline,
          etiqueta: 'Cerrar caja',
          onPressed: puedeCerrarCaja ? onCerrarCaja : null,
        ),
      ],
    );
  }
}

class _BotonAccion extends StatelessWidget {
  const _BotonAccion({
    required this.icono,
    required this.etiqueta,
    required this.onPressed,
  });

  final IconData icono;
  final String etiqueta;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final color = onPressed == null
        ? colores.textoTenue
        : colores.textoSecundario;
    return Tooltip(
      message: etiqueta,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: etiqueta,
        excludeSemantics: true,
        onTap: onPressed,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(radioControlEscritorio),
          child: InkWell(
            borderRadius: BorderRadius.circular(radioControlEscritorio),
            onTap: onPressed,
            child: SizedBox(
              width: Medidas.alturaControl,
              height: Medidas.alturaControl,
              child: Icon(icono, size: 20, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
