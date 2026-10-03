// Estado de la pantalla de venta. Un solo ChangeNotifier (CLAUDE.md: "sin
// gestor de estado ceremonioso, provider o setState alcanzan"), no varios
// controladores por columna: el total depende del carrito Y del medio de
// pago a la vez, y separar el estado en pedazos solo crearía la tentación de
// sincronizarlos a mano.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../../data/busqueda_productos.dart';
import '../../data/cobro_posnet.dart';
import '../../servicios/nube.dart' show nubeApp;
import '../../servicios/pasarela_point_nube.dart';
import '../../servicios/preferencia_cobro_nube.dart';
import '../../data/database.dart';
import '../../data/normalizacion_texto.dart';
import '../../data/repositorio_arqueo_intermedio.dart';
import '../../data/repositorio_cierre.dart' show esDeOtroDia;
import '../../data/repositorio_cobro.dart';
import '../../data/repositorio_encargues.dart' show lineasParaEntregar;
import '../../data/repositorio_configuracion.dart' show configuracionNegocioActual;
import '../../data/repositorio_productos.dart' show listarCategorias;
import '../../data/repositorio_ventas.dart';
import '../../domain/caja.dart' show necesitaArqueoIntermedio;
import '../../domain/cobro_posnet.dart';
import '../../data/repositorio_promos.dart' show componentesDePromos;
import '../../data/repositorio_ventas_abiertas.dart';
import '../../domain/descuento.dart';
import '../../domain/promo.dart' show stockDePromo;
import '../../domain/dinero.dart';
import '../../domain/medio_pago.dart';
import '../../domain/recargo_cigarrillos.dart';
import '../../domain/venta.dart';
import '../../servicios/registro_errores.dart';

class VentaControlador extends ChangeNotifier {
  VentaControlador(this.db, {this.httpClientDePrueba}) {
    // El campo único maneja su propio TextEditingController: escuchamos sus
    // cambios acá en vez de que cada widget tenga que acordarse de llamar a
    // `alCambiarTexto` a mano — así campoTexto.text y las coincidencias
    // nunca pueden quedar desincronizados.
    campoTexto.addListener(_alCambiarTexto);
    // Mismo motivo que el campo único: el descuento se recalcula en vivo
    // mientras se tipea, sin que `ColumnaCobro` tenga que acordarse de
    // notificar cada tecla.
    campoDescuentoCtrl.addListener(notifyListeners);
    // El aviso de arqueo cada 2hs (turnos por usuario) tiene que aparecer
    // solo, sin que nadie tenga que tocar nada para que se note que ya
    // pasaron las 2hs — mismo patrón que `_tickHorario` en `main.dart` para
    // el tema automático. Un minuto alcanza: no hace falta más precisión
    // que esa para una ventana de 2 horas. Sugerencia, no bloqueo (El dueño,
    // 2026-09-15): se puede seguir vendiendo con el aviso visible.
    _tickArqueoIntermedio = Timer.periodic(
      const Duration(minutes: 1),
      (_) => notifyListeners(),
    );
  }

  final AppDatabase db;

  /// Solo para tests: evita que un test dispare una llamada de red real a
  /// Mercado Pago (Fase 12, mismo patrón que `ImpresionControlador`).
  final http.Client? httpClientDePrueba;

  /// Único FocusNode del campo de búsqueda, creado acá (no en el widget)
  /// para que sobreviva a cualquier rebuild de la pantalla. Agregar un
  /// producto (por tap, Alt+tecla o Enter) y cobrar devuelven el foco acá —
  /// es la continuación natural de seguir vendiendo. Un diálogo secundario
  /// (Mixto, Varios, gasto/ingreso rápido, arqueo intermedio, editar un
  /// acceso directo, imprimir) YA NO lo hace (El dueño, 2026-09-16: "dejar de
  /// robar el foco al hacer otra cosa") — ver `acciones_venta.dart` y
  /// `pantalla_venta.dart` para el criterio completo de cuál es cuál.
  final FocusNode focoCampoPrincipal = FocusNode();
  final TextEditingController campoTexto = TextEditingController();

  List<Producto> _catalogo = [];

  /// Artículos de cada promo (id de promo → artículos y cantidades). El stock
  /// de una promo no es una columna: es cuántas alcanzan con el stock de sus
  /// artículos (`stockDePromo`), y se recalcula sobre `_catalogo` cada vez que
  /// ese stock cambia — así la promo aparece o desaparece como cualquier
  /// producto (Regla 8) sin tocar la búsqueda ni la grilla.
  Map<int, List<({int productoId, int cantidad})>> _componentesPromos = {};
  // Precalculados una sola vez en `cargarTodo()` (nunca en
  // `_aplicarStockActualizado`, que solo toca stock, no nombre/código) —
  // evitan recalcular `normalizarTexto` sobre el catálogo entero en cada
  // tecla que se escribe en el campo único (ver `busqueda_productos.dart`).
  Map<int, String> _nombresNormalizados = {};
  Map<int, String> _codigosNormalizados = {};

  /// Categorías configuradas (Configuración → Categorías) — para las pills
  /// de la grilla de productos (rediseño 2026-09-25, segunda pasada).
  List<Categoria> categorias = [];

  /// Ids de producto más vendidos de toda la historia, en orden — la
  /// grilla arranca mostrando esto en vez del catálogo entero (El dueño,
  /// tercera pasada: "me abrumo al ver tantos productos... los 10 mas
  /// vendidos por default").
  List<int> idsMasVendidos = [];

  /// Subconjunto de `_catalogo` que puede mostrarse en la grilla de venta:
  /// activo, con stock (Regla 8, mismo `tieneStock` que ya usa la búsqueda —
  /// una sola fórmula, `data/busqueda_productos.dart`) y sin "Varios" (ya
  /// tiene su propio tile fijo en `TiraAccesosDirectos`, mostrarlo de nuevo
  /// acá confunde). Cacheado, no un getter recalculado en cada rebuild: el
  /// catálogo entero filtrado en cada tecla escrita sería desperdiciar
  /// trabajo real — se recalcula junto con `_catalogo`, nunca por separado.
  List<Producto> catalogoVisible = [];

  void _recalcularCatalogoVisible() {
    catalogoVisible = _catalogo
        .where((p) => p.activo && tieneStock(p) && !p.esVarios)
        .toList();
  }

  /// Solo para lo que sigue viviendo en `configuracion_tabla`: credenciales
  /// de la terminal Point (`mpAccessToken`/`mpTerminalCobroId`). Recargo de
  /// cigarrillos/redondeo/producto de vuelto viven en [configuracionNegocio]
  /// desde la migración v32→v33 (El dueño, 2026-09-19: "que se puedan
  /// modificar las reglas del negocio... desde el celular").
  Configuracion? configuracion;
  ConfiguracionNegocio? configuracionNegocio;
  SesionCaja? sesion;

  /// Null si la sesión abierta todavía no tuvo ningún arqueo intermedio —
  /// en ese caso el contador de 2hs corre desde `sesion.fechaApertura`.
  DateTime? _ultimoArqueoIntermedio;
  late final Timer _tickArqueoIntermedio;
  MedioDePago? medioEfectivo;
  MedioDePago? medioVirtual;
  bool cargando = true;

  List<Producto> coincidencias = [];
  int indicePreseleccionado = 0;

  /// Aviso corto cuando un pesable no se pudo agregar (gramos sin escribir
  /// o en 0, o sin precio por kilo cargado — Regla 7: es un error, no un
  /// cero silencioso, y la pantalla de venta no lo intenta en silencio).
  /// Se limpia solo al volver a escribir o al agregar algo con éxito.
  String? avisoBusqueda;

  /// Aviso cuando se intentó cobrar sin terminar de elegir el medio de pago
  /// (bug real: Enter sin medio no daba ninguna señal, indistinguible de
  /// que la app se colgó — mismo criterio que el acuse de cobro).
  String? avisoCobro;

  List<LineaVenta> carrito = [];
  int? indiceUltimaLinea;

  ComposicionPago? medioElegido;

  /// `true` mientras `cobrar()` tiene un `await registrarVenta(...)` en
  /// vuelo (bug real: sin esto, un doble clic o doble Enter rápido en
  /// "Cobrar" antes de que termine ese `await` disparaba dos ventas y
  /// descontaba stock dos veces — el botón no se deshabilitaba hasta que
  /// `cancelarVenta()` vaciaba `carrito`/`medioElegido` al final).
  bool cobrando = false;

  /// Solo tiene sentido cuando `medioElegido == ComposicionPago.mixto`: la
  /// parte del total que se cobra en efectivo (Regla del layout de venta,
  /// "Mixto abre campo para la parte en efectivo"). Se carga en un diálogo
  /// aparte (dialogo_mixto.dart), no en el campo único.
  int? montoEfectivoMixtoCentavos;

  /// 'qr' | 'debit_card' (Fase 12) — solo tiene sentido con
  /// `medioElegido == virtual` (QR/Débito directo) o `mixto` (canal del
  /// resto). Null en efectivo puro, o en un mixto donde no se cobra por
  /// posnet.
  String? canalElegido;

  /// Descuento sobre el total de la venta (Regla 17, generalizada —
  /// `lib/domain/descuento.dart`): $ o %, elegido por el cajero. El campo
  /// vive antes de elegir medio de pago a propósito — no depende de
  /// `medioElegido`, igual que el carrito.
  TipoDescuento tipoDescuento = TipoDescuento.monto;
  final TextEditingController campoDescuentoCtrl = TextEditingController();

  void elegirTipoDescuento(TipoDescuento tipo) {
    tipoDescuento = tipo;
    notifyListeners();
  }

  /// Mismo parseo que cualquier monto de la app (`parsearARS`,
  /// lib/domain/dinero.dart: acepta "15", "15,5", etc.) — funciona igual
  /// de bien para un porcentaje porque las dos escalas usan el mismo
  /// truco de dos decimales: $15,00 son 1500 centavos, 15,00% son 1500
  /// basis points (`TipoDescuento.porcentaje`, 10000 = 100%). No es una
  /// coincidencia rebuscada, es la misma cuenta con otro nombre.
  int get _valorDescuentoIngresado {
    final texto = campoDescuentoCtrl.text.trim();
    if (texto.isEmpty) return 0;
    try {
      return parsearARS(texto);
    } on FormatException {
      return 0;
    }
  }

  /// Última venta cobrada en esta sesión de pantalla, y su total. Viven acá
  /// (no como estado local de `PantallaVenta`) porque hay DOS caminos para
  /// cobrar — el botón "Cobrar" y Enter con el campo vacío
  /// (`ColumnaBusqueda._onEnter`) — y los dos terminan en `cobrar()`. Un
  /// callback que solo uno de los dos caminos llamara dejaría al otro sin
  /// acuse de cobro ni botón de imprimir habilitado (bug real, encontrado
  /// al escribir el test del acuse: el camino de Enter es el que se usa
  /// siempre en la operación real).
  int? ultimaVentaId;
  int? ultimoTotalCobradoCentavos;

  /// La sesión abierta quedó de un día anterior (se terminó tarde y no se
  /// contó, Regla 5) — no se puede vender bajo ella hasta cerrarla, aunque
  /// el resto de la app (El dueño, 2026-09-06: "bloquea al abrir", mismo
  /// reclamo que la apertura) siga navegable igual que sin sesión.
  bool get sesionVencida =>
      sesion != null && esDeOtroDia(sesion!.fechaApertura);

  /// Arqueo sugerido cada 2hs (turnos por usuario, 2026-09-12): true
  /// muestra el aviso de contar de nuevo (`_AvisoArqueoIntermedio` en
  /// `pantalla_venta.dart`), sin bloquear la venta, cortar la sesión ni
  /// pedir cerrar caja — ver `necesitaArqueoIntermedio` en
  /// `domain/caja.dart`. El dueño, 2026-09-15: dejó de bloquear, es solo una
  /// sugerencia. `sesionVencida` sí sigue bloqueando por su cuenta.
  bool get arqueoIntermedioVencido {
    if (sesion == null || sesionVencida) return false;
    final desde = _ultimoArqueoIntermedio ?? sesion!.fechaApertura;
    return necesitaArqueoIntermedio(desde: desde, ahora: DateTime.now());
  }

  bool get hayTexto => campoTexto.text.trim().isNotEmpty;

  /// Aparece "en lugar del dropdown" (no en un diálogo aparte) cuando hay
  /// texto y ninguna coincidencia — salvo que esa "ninguna coincidencia"
  /// sea en realidad un producto conocido sin stock
  /// (`productoSinStockEncontrado`), que tiene su propio aviso distinto.
  /// Ya no ofrece alta rápida (El dueño, 2026-09-16: se sacó de esta pantalla
  /// — dar de alta un producto nuevo es siempre desde Proveedores), solo el
  /// mensaje "Sin coincidencias".
  bool get sinCoincidencias =>
      hayTexto && coincidencias.isEmpty && productoSinStockEncontrado == null;

  /// Si lo escrito es el código exacto de un producto activo que existe
  /// pero sin stock (por eso no aparece en `coincidencias`, ver
  /// `busqueda_productos.dart`), lo devuelve acá para que la pantalla
  /// avise "ya existe, no tiene stock" en vez de ofrecer alta rápida sobre
  /// algo que no es nuevo (El dueño, 2026-09-06: "que no lo deje escanear
  /// como si fuera nuevo").
  Producto? get productoSinStockEncontrado {
    if (coincidencias.isNotEmpty) return null;
    final consulta = interpretarTexto(campoTexto.text);
    if (consulta.gramos != null) return null;
    final normalizado = normalizarTexto(consulta.texto);
    if (normalizado.isEmpty) return null;
    for (final p in _catalogo) {
      if (p.activo && (_codigosNormalizados[p.id] ?? '') == normalizado) {
        return p;
      }
    }
    return null;
  }

  int get subtotalCentavos => Venta(lineas: carrito).subtotalCentavos;

  /// Busca en el catálogo en memoria, para pintar el nombre en rojo cuando
  /// el stock queda en 0 o negativo (Regla 8) sin ir a buscar a la base.
  Producto? productoPorId(String productoId) {
    final id = int.tryParse(productoId);
    if (id == null) return null;
    for (final p in _catalogo) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// El botón fijo "Varios" (Alt+V) de la grilla de directos: no es uno de
  /// los 6 slots configurables, siempre está.
  Producto? get productoVarios {
    for (final p in _catalogo) {
      if (p.esVarios) return p;
    }
    return null;
  }

  /// El botón fijo de "vuelto" (fase 8): null hasta que se configure un
  /// producto en Configuración — a diferencia de Varios, este SÍ tiene un
  /// precio real en el catálogo, así que agregarlo no necesita preguntar
  /// ningún monto.
  Producto? get productoVuelto {
    final id = configuracionNegocio?.productoVueltoId;
    if (id == null) return null;
    return productoPorId(id.toString());
  }

  /// Null hasta que se elige un medio de pago: antes de eso no hay recargo
  /// ni redondeo que mostrar, solo el subtotal (`subtotalCentavos`).
  ResultadoTotalVenta? get resultado =>
      medioElegido == null ? null : _calcularCon(medioElegido!);

  ResultadoTotalVenta _calcularCon(ComposicionPago medio) {
    final config = configuracionNegocio!;
    final valorDescuento = _valorDescuentoIngresado;
    return calcularTotalVenta(
      venta: Venta(lineas: carrito),
      composicionPago: medio,
      configRecargoCigarrillos: ConfigRecargoCigarrillos(
        primerAtadoCentavos: config.recargoPrimerAtadoCentavos,
        atadoAdicionalCentavos: config.recargoAtadoAdicionalCentavos,
        cigarroSueltoCentavos: config.recargoSueltoCentavos,
      ),
      pasoRedondeoCentavos: config.pasoRedondeoCentavos,
      tipoDescuento: valorDescuento == 0 ? null : tipoDescuento,
      valorDescuento: valorDescuento,
    );
  }

  DateTime? _masVendidosCalculadoEn;
  bool _masVendidosViejo = false;
  static const _vidaMasVendidos = Duration(minutes: 10);

  Future<void> cargarTodo() async {
    _catalogo = await db.select(db.productos).get();
    _componentesPromos = await componentesDePromos(db);
    _recalcularStockDePromos();
    _nombresNormalizados = {
      for (final p in _catalogo) p.id: normalizarTexto(p.nombre),
    };
    _codigosNormalizados = {
      for (final p in _catalogo) p.id: normalizarTexto(p.codigoBarras ?? ''),
    };
    _recalcularCatalogoVisible();
    categorias = await listarCategorias(db);
    // El ranking agrupa todo el historial de ventas: se recalcula cada tanto (o tras vender acá), no en cada recarga de la
    // pantalla (que pasa con cada cambio que llega del celular). Un top 10 que se actualiza en minutos no cambia nada al cobrar.
    final ahora = DateTime.now();
    if (_masVendidosCalculadoEn == null || _masVendidosViejo || ahora.difference(_masVendidosCalculadoEn!) > _vidaMasVendidos) {
      idsMasVendidos = await productosMasVendidosIds(db);
      _masVendidosCalculadoEn = ahora;
      _masVendidosViejo = false;
    }
    configuracion = await db.select(db.configuracionTabla).getSingle();
    configuracionNegocio = await configuracionNegocioActual(db);
    sesion = await sesionAbierta(db);
    await _cargarPestanas();
    _ultimoArqueoIntermedio = sesion == null
        ? null
        : await fechaUltimoArqueoIntermedio(db, sesion!.id);
    medioEfectivo = await (db.select(
      db.mediosDePago,
    )..where((m) => m.esEfectivo.equals(true))).getSingle();
    medioVirtual = await (db.select(
      db.mediosDePago,
    )..where((m) => m.esEfectivo.equals(false))).getSingle();
    cargando = false;
    notifyListeners();
  }

  // ─── Campo único ─────────────────────────────────────────────────────

  void _alCambiarTexto() {
    coincidencias = buscarProductos(
      catalogo: _catalogo,
      textoBuscado: campoTexto.text,
      incluirSinStock: true,
      nombresNormalizados: _nombresNormalizados,
      codigosNormalizados: _codigosNormalizados,
    );
    indicePreseleccionado = 0;
    avisoBusqueda = null;
    notifyListeners();
  }

  /// Flechas del dropdown. No mueve el cursor de texto — el campo nunca
  /// pierde el foco, pero esto es un cambio de estado nuestro, no una edición
  /// del texto.
  void moverSeleccion(int delta) {
    if (coincidencias.isEmpty) return;
    final nuevo = indicePreseleccionado + delta;
    indicePreseleccionado = nuevo.clamp(0, coincidencias.length - 1);
    notifyListeners();
  }

  void agregarSeleccionActual() {
    if (coincidencias.isEmpty) return;
    agregarDesdeBusqueda(coincidencias[indicePreseleccionado]);
  }

  /// Agrega un resultado de la búsqueda. Los agotados se ven atenuados (El dueño, 2026-10-03) pero no se pueden
  /// vender (2026-09-06): avisa en vez de agregar.
  void agregarDesdeBusqueda(Producto producto) {
    if (!tieneStock(producto)) {
      avisoBusqueda = '${producto.nombre}: sin stock, no se puede vender';
      notifyListeners();
      return;
    }
    agregarProducto(producto);
  }

  /// Agrega [producto] al carrito. [montoVariosCentavos] es obligatorio (e
  /// ignorado para cualquier otro producto) cuando `producto.esVarios`.
  ///
  /// Un pesable sin gramos escritos (o en 0) o sin precio por kilo cargado
  /// no se agrega — Regla 7 es explícita en que eso es un error, no un
  /// cero silencioso, y `lineaDesdeProducto` asume que los dos datos están
  /// completos (antes de este chequeo, faltar cualquiera de los dos
  /// crasheaba en vez de avisar).
  void agregarProducto(Producto producto, {int? montoVariosCentavos}) {
    final consulta = interpretarTexto(campoTexto.text);

    if (producto.esPesable) {
      if (consulta.gramos == null || consulta.gramos! <= 0) {
        avisoBusqueda =
            'Escribí los gramos antes del nombre, por ejemplo "200 ${producto.nombre}"';
        notifyListeners();
        return;
      }
      if (producto.precioPorKiloCentavos == null) {
        avisoBusqueda =
            '${producto.nombre} no tiene precio por kilo cargado (Regla 7) — cargalo en Productos antes de venderlo.';
        notifyListeners();
        return;
      }
    }

    final linea = lineaDesdeProducto(
      producto,
      cantidad: consulta.gramos == null ? 1 : null,
      gramos: consulta.gramos,
      montoVariosCentavos: montoVariosCentavos,
    );
    avisoBusqueda = null;
    _agregarLineaAlCarrito(linea);
    _limpiarCampo();
  }

  void _agregarLineaAlCarrito(LineaVenta nueva) {
    // "Varios" nunca se suma con una línea existente: cada monto suelto es
    // distinto, sumarlos ocultaría de qué se trataba cada uno.
    if (!nueva.esVarios) {
      final indiceExistente = carrito.indexWhere(
        (l) => l.productoId == nueva.productoId,
      );
      if (indiceExistente != -1) {
        carrito = List.of(carrito);
        carrito[indiceExistente] = sumarLineasVenta(
          carrito[indiceExistente],
          nueva,
        );
        indiceUltimaLinea = indiceExistente;
        notifyListeners();
        return;
      }
    }
    carrito = [...carrito, nueva];
    indiceUltimaLinea = carrito.length - 1;
    notifyListeners();
  }

  void _limpiarCampo() {
    // Dispara el listener de campoTexto, que ya deja coincidencias vacías e
    // indicePreseleccionado en 0 para un texto vacío.
    campoTexto.clear();
  }

  /// Ícono de tacho de una fila del carrito (El dueño, 2026-09-06: "que sea
  /// con mouse para seleccionar el producto a eliminar" — reemplaza al
  /// `Backspace` de antes, que solo borraba la última línea). Cualquier
  /// línea, no solo la última.
  void eliminarLinea(int index) {
    if (index < 0 || index >= carrito.length) return;
    carrito = [...carrito]..removeAt(index);
    if (indiceUltimaLinea == index) {
      // Se borró justo la línea resaltada — no hay un "último agregado"
      // claro para reemplazarla, se apaga el resaltado.
      indiceUltimaLinea = null;
    } else if (indiceUltimaLinea != null && index < indiceUltimaLinea!) {
      indiceUltimaLinea = indiceUltimaLinea! - 1;
    }
    notifyListeners();
  }

  /// Deshace un `eliminarLinea` (snackbar "Deshacer" de la columna del
  /// carrito): vuelve a poner la línea en su lugar y la resalta como última.
  void restaurarLinea(int index, LineaVenta linea) {
    final i = index.clamp(0, carrito.length);
    carrito = [...carrito]..insert(i, linea);
    indiceUltimaLinea = i;
    notifyListeners();
  }

  void _reemplazarLinea(int index, LineaVenta nueva) {
    carrito = [...carrito];
    carrito[index] = nueva;
    notifyListeners();
  }

  /// Botones "−"/"+" del carrito (El dueño, 2026-09-06) — solo para líneas por
  /// unidad, ajusta de a un producto por vez. En 1, restar saca la línea
  /// entera (mismo criterio que el tacho): restar por debajo de 1 no tiene
  /// sentido.
  void ajustarCantidad(int index, int delta) {
    if (index < 0 || index >= carrito.length) return;
    final linea = carrito[index];
    if (linea is! LineaVentaPorUnidad) return;
    final nuevaCantidad = linea.cantidad + delta;
    if (nuevaCantidad <= 0) {
      eliminarLinea(index);
      return;
    }
    _reemplazarLinea(
      index,
      LineaVentaPorUnidad(
        productoId: linea.productoId,
        nombreProducto: linea.nombreProducto,
        proveedorId: linea.proveedorId,
        cantidad: nuevaCantidad,
        esVarios: linea.esVarios,
        tipoCigarrillo: linea.tipoCigarrillo,
        precioUnitarioCentavos: linea.precioUnitarioCentavos,
        costoUnitarioCentavos: linea.costoUnitarioCentavos,
      ),
    );
  }

  /// Doble clic en la cantidad (El dueño, 2026-09-06): tipear el valor exacto
  /// en vez de tocar "+" muchas veces. 0 o menos saca la línea, mismo
  /// criterio que `ajustarCantidad`.
  void editarCantidadExacta(int index, int nuevaCantidad) {
    if (index < 0 || index >= carrito.length) return;
    final linea = carrito[index];
    if (linea is! LineaVentaPorUnidad) return;
    if (nuevaCantidad <= 0) {
      eliminarLinea(index);
      return;
    }
    _reemplazarLinea(
      index,
      LineaVentaPorUnidad(
        productoId: linea.productoId,
        nombreProducto: linea.nombreProducto,
        proveedorId: linea.proveedorId,
        cantidad: nuevaCantidad,
        esVarios: linea.esVarios,
        tipoCigarrillo: linea.tipoCigarrillo,
        precioUnitarioCentavos: linea.precioUnitarioCentavos,
        costoUnitarioCentavos: linea.costoUnitarioCentavos,
      ),
    );
  }

  /// Doble clic en los gramos de un pesable (El dueño, 2026-09-06): mismo
  /// criterio que `editarCantidadExacta`, sin botones "−"/"+" (sumar de a
  /// un gramo por clic no tiene sentido práctico — decidido con el dueño).
  void editarGramosExacto(int index, int nuevosGramos) {
    if (index < 0 || index >= carrito.length) return;
    final linea = carrito[index];
    if (linea is! LineaVentaPesable) return;
    if (nuevosGramos <= 0) {
      eliminarLinea(index);
      return;
    }
    _reemplazarLinea(
      index,
      LineaVentaPesable(
        productoId: linea.productoId,
        nombreProducto: linea.nombreProducto,
        proveedorId: linea.proveedorId,
        gramos: nuevosGramos,
        precioPorKiloCentavos: linea.precioPorKiloCentavos,
        costoPorKiloCentavos: linea.costoPorKiloCentavos,
      ),
    );
  }

  // ─── Ventas abiertas (pestañas) ──────────────────────────────────────
  //
  // El dueño, 2026-09-29: "que la venta permanezca y que pueda hacer más de 1
  // venta a la vez". La pestaña ACTIVA vive en los campos de siempre
  // (`carrito`, `medioElegido`, el descuento...) — todo el resto de la
  // pantalla sigue leyendo de ahí sin enterarse de que hay más. Las demás
  // esperan en [_pestanas]. Cada cambio de la activa se guarda sola en
  // `ventas_abiertas` (ver [notifyListeners]), así sobrevive a cambiar de
  // pantalla, cerrar la app o un corte de luz. Son borradores: no reservan
  // stock ni tocan la caja hasta cobrar.

  /// El encargue por apartado que la venta activa entrega (null en una venta común). Al cobrar libera lo apartado.
  int? encargueId;

  /// Entregar un encargue: abre una venta con lo apartado a los precios de hoy, en una pestaña aparte si ya había una
  /// venta armada (no se pisa lo que se estaba cobrando). No toca stock ni caja hasta cobrar.
  Future<void> cargarEncargue(int id) async {
    final lineas = await lineasParaEntregar(db, id);
    if (lineas.isEmpty) return;
    // Ya está abierto en alguna pestaña: se va a esa en vez de duplicarlo.
    _pestanas[pestanaActiva].estado = _borradorActivo();
    final existente = _pestanas.indexWhere((p) => p.estado.encargueId == id);
    if (existente != -1) {
      _activar(existente);
      return;
    }
    if (!_borradorActivo().estaVacio) {
      _pestanas.add(_Pestana(const BorradorVenta()));
      _activar(_pestanas.length - 1, notificar: false);
    }
    carrito = lineas;
    encargueId = id;
    indiceUltimaLinea = null;
    notifyListeners();
  }

  final List<_Pestana> _pestanas = [_Pestana(const BorradorVenta())];
  int pestanaActiva = 0;
  int? _sesionIdDePestanas;
  String _firmaGuardada = const BorradorVenta().firma;
  bool _suprimirGuardado = false;
  bool _disposed = false;
  Future<void> _colaGuardado = Future.value();

  int get cantidadPestanas => _pestanas.length;

  /// Hay algo cargado en alguna pestaña (la activa se lee en vivo).
  bool get hayVentaAbierta =>
      carrito.isNotEmpty || _pestanas.any((p) => p.estado.lineas.isNotEmpty);

  /// Lo que muestra cada pestaña: cuántas líneas tiene y su subtotal. La
  /// activa se lee en vivo de los campos, las demás de su borrador.
  List<({int lineas, int subtotalCentavos})> get resumenPestanas => [
    for (var i = 0; i < _pestanas.length; i++)
      (
        lineas: i == pestanaActiva ? carrito.length : _pestanas[i].estado.lineas.length,
        subtotalCentavos: Venta(
          lineas: i == pestanaActiva ? carrito : _pestanas[i].estado.lineas,
        ).subtotalCentavos,
      ),
  ];

  BorradorVenta _borradorActivo() => BorradorVenta(
    id: _pestanas[pestanaActiva].dbId,
    lineas: carrito,
    medio: medioElegido?.name,
    montoEfectivoMixtoCentavos: montoEfectivoMixtoCentavos,
    canal: canalElegido,
    tipoDescuento: tipoDescuento.name,
    textoDescuento: campoDescuentoCtrl.text,
    encargueId: encargueId,
  );

  /// Guarda la pestaña activa si cambió desde la última vez. Corre fuera del
  /// camino de la venta (fire-and-forget, en cola para que dos guardados
  /// nunca se pisen): agregar un producto no espera al disco.
  void _programarGuardado() {
    final sesionId = sesion?.id;
    if (_disposed || _suprimirGuardado || sesionId == null || sesionId != _sesionIdDePestanas) return;
    final borrador = _borradorActivo();
    _pestanas[pestanaActiva].estado = borrador;
    final firma = borrador.firma;
    if (firma == _firmaGuardada) return;
    _firmaGuardada = firma;
    final pestana = _pestanas[pestanaActiva];
    final orden = pestanaActiva;
    _colaGuardado = _colaGuardado.then((_) async {
      try {
        if (pestana.descartada) return;
        if (borrador.estaVacio) {
          final id = pestana.dbId;
          if (id != null) {
            pestana.dbId = null;
            await borrarVentaAbierta(db, id);
          }
          return;
        }
        pestana.dbId = await guardarVentaAbierta(
          db,
          sesionId: sesionId,
          orden: orden,
          borrador: borrador.conId(pestana.dbId),
        );
        // Descartada mientras se escribía (Esc justo después de agregar):
        // no dejar la fila huérfana.
        if (pestana.descartada) {
          final id = pestana.dbId;
          pestana.dbId = null;
          if (id != null) await borrarVentaAbierta(db, id);
        }
      } catch (_) {
        // Un borrador que no se pudo guardar nunca puede frenar la venta.
      }
    });
  }

  @override
  void notifyListeners() {
    _invalidarMixtoSiYaNoCierra();
    super.notifyListeners();
    _programarGuardado();
  }

  /// La parte en efectivo de un mixto se confirma contra el total de ESE
  /// momento. Si después baja el total (se saca un producto, se pone un
  /// descuento) y el efectivo ya lo cubre, la parte por Mercado Pago quedaría
  /// en cero o negativa — bug real de la revisión 2026-10-03: "Cobrar a mano"
  /// grababa un pago de MP negativo. Pasa por acá porque todo cambio del
  /// carrito, del descuento o del medio termina en `notifyListeners`: se borra
  /// el monto y hay que volver a cargarlo (Cobrar reabre el diálogo).
  void _invalidarMixtoSiYaNoCierra() {
    final efectivo = montoEfectivoMixtoCentavos;
    if (medioElegido != ComposicionPago.mixto || efectivo == null || carrito.isEmpty) return;
    if (efectivo < _calcularCon(ComposicionPago.mixto).totalCentavos) return;
    montoEfectivoMixtoCentavos = null;
    avisoCobro = 'El total cambió: volvé a cargar la parte en efectivo (Alt+X)';
  }

  /// Carga las ventas abiertas de la sesión, una sola vez por sesión: el
  /// refresco al volver a Venta (`cargarTodo` se vuelve a llamar) no puede
  /// pisar lo que hay en pantalla.
  Future<void> _cargarPestanas() async {
    final sesionId = sesion?.id;
    if (sesionId == _sesionIdDePestanas) return;
    final guardadas = sesionId == null ? const <BorradorVenta>[] : await cargarVentasAbiertas(db, sesionId);
    _pestanas
      ..clear()
      ..addAll(
        guardadas.isEmpty
            ? [_Pestana(const BorradorVenta())]
            : [for (final b in guardadas) _Pestana(b)],
      );
    _sesionIdDePestanas = sesionId;
    _activar(0, notificar: false);
  }

  void _activar(int indice, {bool notificar = true}) {
    _suprimirGuardado = true;
    try {
      pestanaActiva = indice;
      final e = _pestanas[indice].estado;
      carrito = e.lineas;
      indiceUltimaLinea = null;
      medioElegido = e.medio == null ? null : composicionPagoDesdeTexto(e.medio!);
      montoEfectivoMixtoCentavos = e.montoEfectivoMixtoCentavos;
      canalElegido = e.canal;
      avisoCobro = null;
      tipoDescuento = TipoDescuento.values.byName(e.tipoDescuento);
      campoDescuentoCtrl.text = e.textoDescuento;
      encargueId = e.encargueId;
      _limpiarCampo();
      _firmaGuardada = e.firma;
    } finally {
      _suprimirGuardado = false;
    }
    if (notificar) notifyListeners();
  }

  /// Pasa a otra venta abierta. La que se deja ya está guardada.
  void cambiarAPestana(int indice) {
    if (indice == pestanaActiva || indice < 0 || indice >= _pestanas.length || cobrando) return;
    _pestanas[pestanaActiva].estado = _borradorActivo();
    _activar(indice);
    focoCampoPrincipal.requestFocus();
  }

  /// Abre una venta nueva sin perder la actual. Si la actual está vacía no
  /// hace nada: otra pestaña vacía no serviría para nada.
  void nuevaVenta() {
    if (cobrando || _borradorActivo().estaVacio) return;
    _pestanas[pestanaActiva].estado = _borradorActivo();
    _pestanas.add(_Pestana(const BorradorVenta()));
    _activar(_pestanas.length - 1);
    focoCampoPrincipal.requestFocus();
  }

  /// Foto de la venta activa para poder deshacer su cancelación. Sin id: si
  /// se cerró la pestaña, su fila ya se borró y vuelve a guardarse como nueva.
  BorradorVenta fotoDeLaVentaActiva() => _borradorActivo().conId(null);

  /// Deshace `cancelarVenta`: si la pestaña activa está vacía la rellena, y si
  /// no abre una pestaña nueva con la venta, para no pisar lo que se esté armando.
  void reabrirVenta(BorradorVenta foto) {
    if (cobrando || foto.estaVacio) return;
    if (_borradorActivo().estaVacio) {
      _pestanas[pestanaActiva].estado = foto;
      _activar(pestanaActiva);
    } else {
      _pestanas[pestanaActiva].estado = _borradorActivo();
      _pestanas.add(_Pestana(foto));
      _activar(_pestanas.length - 1);
    }
    _programarGuardado();
    focoCampoPrincipal.requestFocus();
  }

  /// Esc: cancela la venta entera. Con más de una venta abierta, además
  /// cierra su pestaña y pasa a la vecina.
  void cancelarVenta() {
    carrito = [];
    encargueId = null;
    indiceUltimaLinea = null;
    medioElegido = null;
    montoEfectivoMixtoCentavos = null;
    canalElegido = null;
    avisoCobro = null;
    // Un descuento no se arrastra a la venta siguiente — mismo motivo que
    // el medio de pago.
    tipoDescuento = TipoDescuento.monto;
    campoDescuentoCtrl.clear();
    // No alcanza con _limpiarCampo(): si el campo ya estaba vacío,
    // TextEditingController.clear() no cambia nada y su listener no se
    // dispara, así que nadie avisaría que el carrito y el medio se
    // vaciaron. notifyListeners() acá es explícito a propósito.
    _limpiarCampo();
    if (_pestanas.length > 1) {
      // Guarda el vaciado (borra la fila) y saca la pestaña.
      notifyListeners();
      final quitada = _pestanas.removeAt(pestanaActiva);
      quitada.descartada = true;
      _colaGuardado = _colaGuardado.then((_) async {
        final id = quitada.dbId;
        quitada.dbId = null;
        if (id != null) {
          try {
            await borrarVentaAbierta(db, id);
          } catch (e, pila) {
            // Nunca frena la venta, pero un borrador que no se borró vuelve a aparecer: que quede anotado.
            await registrarError('Borrar una venta abierta descartada', e, pila);
          }
        }
      });
      _activar(pestanaActiva.clamp(0, _pestanas.length - 1));
      return;
    }
    notifyListeners();
  }

  // ─── Medio de pago y cobro ───────────────────────────────────────────

  /// Recalcula el total de cero cada vez que se llama: no hay un total
  /// cacheado que invalidar, así que el recargo de cigarrillos aparece o
  /// desaparece del total apenas cambia el medio (Regla 6).
  void elegirMedio(ComposicionPago medio) {
    medioElegido = medio;
    if (medio != ComposicionPago.mixto) montoEfectivoMixtoCentavos = null;
    canalElegido = null;
    avisoCobro = null;
    notifyListeners();
  }

  /// QR o Débito directo (Fase 12, Alt+Q/Alt+D) — a diferencia de
  /// [elegirMedio], siempre es virtual y siempre lleva un canal concreto
  /// de la terminal Point.
  void elegirCanalDirecto(String canal) {
    medioElegido = ComposicionPago.virtual;
    montoEfectivoMixtoCentavos = null;
    canalElegido = canal;
    avisoCobro = null;
    notifyListeners();
  }

  /// Confirma la parte en efectivo de un pago mixto (dialogo_mixto.dart). El
  /// resto hasta el total se asume virtual, con [canalResto] (Fase 12,
  /// Alt+Q/Alt+D/Enter al confirmar el monto — 'qr' por default) como el
  /// canal de la terminal Point para esa parte.
  ///
  /// La composición real se deriva del monto, no del botón que se apretó
  /// (`clasificarComposicion`, domain/medio_pago.dart): si el cliente
  /// termina pagando todo en efectivo o todo virtual, `medioElegido` pasa a
  /// reflejar eso — así el total en pantalla ya sale con el redondeo/
  /// recargo correcto antes de cobrar, en vez de arrastrar un "mixto" que
  /// en la práctica ya no lo es.
  void confirmarMixto(int montoEfectivoCentavos, {String canalResto = 'qr'}) {
    final totalMixto = _calcularCon(ComposicionPago.mixto).totalCentavos;
    final medio = clasificarComposicion(
      montoEfectivoCentavos: montoEfectivoCentavos,
      totalCentavos: totalMixto,
    );
    medioElegido = medio;
    montoEfectivoMixtoCentavos = medio == ComposicionPago.mixto
        ? montoEfectivoCentavos
        : null;
    // Si terminó en puro efectivo (el cliente pagó todo en efectivo), no
    // hay parte virtual que llevar un canal.
    canalElegido = medio == ComposicionPago.efectivo ? null : canalResto;
    avisoCobro = null;
    notifyListeners();
  }

  /// Arma los pagos a partir del medio ya elegido. Null si todavía falta
  /// algo (medio sin elegir, o mixto sin el monto en efectivo confirmado).
  List<PagoARegistrar>? construirPagos() {
    final medio = medioElegido;
    final total = resultado?.totalCentavos;
    if (medio == null || total == null) return null;

    return switch (medio) {
      ComposicionPago.efectivo => [
        PagoARegistrar(
          medioPagoId: medioEfectivo!.id,
          montoCentavos: total,
          esEfectivo: true,
        ),
      ],
      ComposicionPago.virtual => [
        PagoARegistrar(
          medioPagoId: medioVirtual!.id,
          montoCentavos: total,
          esEfectivo: false,
          canal: canalElegido,
        ),
      ],
      // Última defensa: un efectivo que ya cubre el total no deja parte por
      // Mercado Pago (ver `_invalidarMixtoSiYaNoCierra`).
      ComposicionPago.mixto =>
        montoEfectivoMixtoCentavos == null || montoEfectivoMixtoCentavos! >= total
            ? null
            : [
                PagoARegistrar(
                  medioPagoId: medioEfectivo!.id,
                  montoCentavos: montoEfectivoMixtoCentavos!,
                  esEfectivo: true,
                ),
                PagoARegistrar(
                  medioPagoId: medioVirtual!.id,
                  montoCentavos: total - montoEfectivoMixtoCentavos!,
                  canal: canalElegido,
                  esEfectivo: false,
                ),
              ],
    };
  }

  /// Cobra la venta actual con el medio ya elegido (Enter con el campo
  /// vacío, o el botón "Cobrar"). El usuario que abrió la sesión es quien
  /// queda registrado en la venta: todavía no hay un selector de usuario
  /// independiente de la apertura de caja (Regla 18 completa es una
  /// ampliación futura, no de esta fase).
  Future<int?> cobrarActual() async {
    if (sesion == null) return null;
    final medio = medioElegido;
    final pagos = construirPagos();
    if (pagos == null) {
      // Bug real: Enter con el campo vacío y sin medio elegido no daba
      // ninguna señal, indistinguible de que la app se colgó (mismo
      // problema que el acuse de cobro ya resolvió del otro lado). Solo
      // tiene sentido avisarlo si había algo para cobrar — con el carrito
      // vacío, apretar Enter sin querer cobrar nada no es un error.
      if (carrito.isNotEmpty) {
        avisoCobro = medio == ComposicionPago.mixto
            ? 'Falta la parte en efectivo del mixto (Alt+X)'
            : 'Elegí un medio de pago (Alt+E / Alt+Q / Alt+X)';
        notifyListeners();
      }
      return null;
    }
    return cobrar(usuarioId: sesion!.usuarioAbrioId, pagos: pagos);
  }

  Future<int?> cobrar({
    required int usuarioId,
    required List<PagoARegistrar> pagos,
  }) async {
    if (cobrando) return null;
    if (carrito.isEmpty || medioElegido == null || sesion == null) return null;

    cobrando = true;
    notifyListeners();

    try {
      // Capturado ANTES de `cancelarVenta()`, que vacía carrito y
      // medioElegido (de los que depende `resultado`).
      final totalCentavos = resultado!.totalCentavos;

      // El borrador se borra en la misma transacción que graba la venta.
      // Primero se espera el guardado en cola para conocer su id.
      await _colaGuardado;
      final pestanaCobrada = _pestanas[pestanaActiva];
      _masVendidosViejo = true; // vender cambia el ranking: la próxima recarga lo recalcula
      final (ventaId, stockActualizado) = await registrarVenta(
        db,
        venta: Venta(lineas: carrito),
        resultado: resultado!,
        sesionCajaId: sesion!.id,
        usuarioId: usuarioId,
        pagos: pagos,
        ventaAbiertaId: pestanaCobrada.dbId,
        encargueId: encargueId,
      );
      pestanaCobrada.dbId = null;

      // El stock cambió, pero el catálogo entero NO se relee de disco
      // (CLAUDE.md, "prioridad arranque vs. operación"): `registrarVenta` ya
      // devuelve el stock posterior de cada producto vendido, así que
      // alcanza con corregir esas filas en la copia en memoria.
      _aplicarStockActualizado(stockActualizado);
      ultimaVentaId = ventaId;
      ultimoTotalCobradoCentavos = totalCentavos;
      cancelarVenta();
      return ventaId;
    } on SesionCerradaException {
      // La caja se cerró desde otro equipo con esta venta armada: el carrito queda como está y se avisa.
      avisoCobro = 'La caja ya se cerró: la venta no se guardó. Abrí la caja de nuevo para cobrarla.';
      return null;
    } finally {
      // `notifyListeners()` explícito acá (no solo el de `cancelarVenta()`):
      // también tiene que dispararse en el camino de excepción, donde
      // `cancelarVenta()` nunca se llegó a ejecutar y el botón quedaría
      // deshabilitado para siempre si nadie avisa que `cobrando` bajó.
      cobrando = false;
      notifyListeners();
    }
  }

  // ─── Cobro por terminal Point (Fase 12) ──────────────────────────────

  /// Cuánto mandarle a la terminal: el total entero para QR/Débito
  /// directo, o `total − montoEfectivoMixtoCentavos` en un mixto (El dueño,
  /// ESTADO.md: "sobre el total ya compuesto — recargo primero, redondeo
  /// después").
  int get montoParaPosnet {
    final total = resultado!.totalCentavos;
    return medioElegido == ComposicionPago.mixto
        ? total - (montoEfectivoMixtoCentavos ?? 0)
        : total;
  }

  /// Crea la orden de cobro: siembra la fila pendiente ANTES del POST
  /// (para poder reintentar con la misma clave si la respuesta se pierde),
  /// llama a la Orders API, y guarda el id que responde. El diálogo que
  /// llama a esto (`dialogo_cobro_posnet.dart`) es quien hace el polling
  /// después — acá solo se dispara la orden.
  ///
  /// Tira `CobroPosnetException` si falta configurar la terminal de cobro,
  /// o si la API responde con un error — el diálogo decide qué mostrar.
  Future<PasarelaPoint> _pasarelaPoint({bool soloToken = false}) async => elegirPasarelaPoint(
    soloToken: soloToken,
    forzarNube: PreferenciaCobroNube.activo,
    accessToken: configuracion?.mpAccessToken,
    terminalId: configuracion?.mpTerminalCobroId,
    almacen: nubeApp?.almacen,
    cliente: nubeApp?.cliente,
    directa: (token, terminal) => PasarelaPointDirecta(accessToken: token, terminalId: terminal, client: httpClientDePrueba),
  );

  Future<({int ordenPendienteId, String ordenIdMp})>
  iniciarCobroPosnet() async {
    // Directo con el access token de esta PC si está cargado (lo de siempre); si no, por el servidor con la cuenta conectada.
    final pasarela = await _pasarelaPoint();

    final canal = canalElegido!;
    final monto = montoParaPosnet;
    final pendiente = await crearOrdenPendiente(
      db,
      sesionCajaId: sesion!.id,
      canal: canal,
      montoCentavos: monto,
    );
    final creada = await pasarela.crear(
      externalReference: pendiente.externalReference,
      idempotencyKey: pendiente.idempotencyKey,
      montoCentavos: monto,
      canal: canal,
    );
    await marcarOrdenConId(db, id: pendiente.id, ordenIdMp: creada.ordenIdMp);
    return (ordenPendienteId: pendiente.id, ordenIdMp: creada.ordenIdMp);
  }

  /// Un paso de polling: consulta el estado actual de la orden y lo
  /// clasifica (`lib/domain/cobro_posnet.dart`). El diálogo decide cuántas
  /// veces llamar a esto y cuándo darse por vencido (timeout de 60s).
  Future<ResultadoOrdenCobro> consultarEstadoPosnet(String ordenIdMp) async {
    final estado = await (await _pasarelaPoint(soloToken: true)).consultar(ordenIdMp);
    return clasificarEstadoOrden(estado);
  }

  /// El pago se aprobó: recién ahora se graba la venta real (Regla de Fase
  /// 12: la venta se graba después de que el pago se apruebe, nunca
  /// antes) y se cierra el ciclo de la orden pendiente con el `ventaId`
  /// resultante.
  Future<int?> confirmarCobroPosnetAprobado(int ordenPendienteId) async {
    final ventaId = await cobrarActual();
    if (ventaId != null) {
      await marcarOrdenResuelta(
        db,
        id: ordenPendienteId,
        estado: 'aprobada',
        ventaId: ventaId,
      );
    }
    return ventaId;
  }

  /// El pago se rechazó — Mercado Pago ya resolvió la orden por su cuenta,
  /// no hace falta avisarle nada más. Nunca se asume nada más allá de eso:
  /// se cierra el ciclo de la orden pendiente sin venta. El carrito y el
  /// medio elegido siguen intactos: el diálogo ofrece reintentar o degradar
  /// a "cobré a mano" con la misma elección.
  Future<void> resolverCobroPosnetNoAprobado(
    int ordenPendienteId, {
    required String estado,
  }) {
    return marcarOrdenResuelta(db, id: ordenPendienteId, estado: estado);
  }

  /// El dueño canceló desde el diálogo — a diferencia de un rechazo, acá la
  /// orden sigue viva del lado de Mercado Pago y la terminal sigue
  /// esperando el pago hasta que se le avise explícitamente (El dueño:
  /// "cuando cancelo el QR no cancela el dispositivo"). Si ya existe un id
  /// de MP, se le manda el cancel; si la API de cancelación falla, la fila
  /// se deja `'pendiente'` a propósito (no `'cancelada'`) — mismo criterio
  /// que un timeout: no se asume que quedó cancelada si no hay
  /// confirmación, y aparece en el aviso de Cierre para revisar a mano.
  Future<void> cancelarCobroPosnet(
    int ordenPendienteId, {
    String? ordenIdMp,
  }) async {
    if (ordenIdMp != null) {
      await (await _pasarelaPoint(soloToken: true)).cancelar(ordenIdMp);
    }
    await marcarOrdenResuelta(db, id: ordenPendienteId, estado: 'cancelada');
  }

  /// Corrige `_catalogo` en memoria con el stock posterior de cada producto
  /// vendido, sin volver a leer nada de disco. `producto.copyWith` deja
  /// intacto cualquier otro campo (nombre, precio, costo).
  void _aplicarStockActualizado(List<ActualizacionStock> actualizaciones) {
    if (actualizaciones.isEmpty) return;
    final porProducto = {for (final a in actualizaciones) a.productoId: a};
    _catalogo = [
      for (final p in _catalogo)
        if (porProducto[p.id] case final a?)
          p.copyWith(
            stock: a.stock ?? p.stock,
            stockGramos: Value(a.stockGramos ?? p.stockGramos),
          )
        else
          p,
    ];
    _recalcularStockDePromos();
    _recalcularCatalogoVisible();
  }

  /// Pone en `stock` de cada promo del catálogo en memoria cuántas alcanzan
  /// con el stock actual de sus artículos.
  void _recalcularStockDePromos() {
    if (_componentesPromos.isEmpty) return;
    final stockPorId = {for (final p in _catalogo) p.id: p.stock};
    _catalogo = [
      for (final p in _catalogo)
        if (p.esPromo)
          p.copyWith(
            stock: stockDePromo([
              for (final c in _componentesPromos[p.id] ?? const <({int productoId, int cantidad})>[])
                (stock: stockPorId[c.productoId] ?? 0, cantidadPorPromo: c.cantidad),
            ]),
          )
        else
          p,
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    _tickArqueoIntermedio.cancel();
    focoCampoPrincipal.dispose();
    campoTexto.dispose();
    campoDescuentoCtrl.dispose();
    super.dispose();
  }
}

/// Una venta abierta en memoria. [dbId] es su fila en `ventas_abiertas`
/// (null mientras esté vacía o todavía no se guardó); [descartada] avisa a
/// un guardado en vuelo que no deje la fila huérfana.
class _Pestana {
  _Pestana(this.estado) : dbId = estado.id;

  BorradorVenta estado;
  int? dbId;
  bool descartada = false;
}
