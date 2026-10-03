// Catálogo de productos (fase 5): listar/buscar/filtrar, alta y edición
// completas, categorías, y el registro de historial de precios — la misma
// regla que usa el importador de CSV (lib/data/importacion_csv.dart), acá
// compartida en vez de escrita dos veces (Regla 3).

import 'package:drift/drift.dart';

import '../domain/edicion_masiva_precios.dart';
import '../domain/edicion_masiva_stock.dart';
import '../domain/ganancia.dart' show precioConGananciaACentena;
import '../domain/pesables.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'normalizacion_texto.dart';

/// Escribe una fila en `historial_de_precios` cuando el precio o costo (por
/// unidad o por kilo) cambia respecto a [anterior]. [anterior] null significa
/// alta nueva — ahí siempre se escribe, es la primera foto del producto.
///
/// Única implementación de "¿esto es un cambio de precio?" (Regla 3): la
/// usan tanto el importador de CSV como la edición manual de acá — antes
/// vivía escrita adentro del importador nada más.
Future<void> registrarCambioDePrecio(
  AppDatabase db, {
  required int productoId,
  required int usuarioId,
  required Producto? anterior,
  required int? precioCentavos,
  required int? costoCentavos,
  required int? precioPorKiloCentavos,
  required int? costoPorKiloCentavos,
}) async {
  final cambio =
      anterior == null ||
      anterior.precioCentavos != precioCentavos ||
      anterior.costoCentavos != costoCentavos ||
      anterior.precioPorKiloCentavos != precioPorKiloCentavos ||
      anterior.costoPorKiloCentavos != costoPorKiloCentavos;
  if (!cambio) return;

  await db
      .into(db.historialDePrecios)
      .insert(
        HistorialDePreciosCompanion.insert(
          productoId: productoId,
          usuarioId: usuarioId,
          precioCentavos: Value(precioCentavos),
          costoCentavos: Value(costoCentavos),
          precioPorKiloCentavos: Value(precioPorKiloCentavos),
          costoPorKiloCentavos: Value(costoPorKiloCentavos),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );
}

/// Categorías fijas para explicar un ajuste manual de stock — dropdown en el
/// detalle de producto, nunca texto libre (decisión de el dueño). El primer
/// valor no está acá: la ausencia de motivo se representa con `null`, no con
/// un string de la lista.
const List<String> motivosAjusteDeStock = [
  'Conteo físico',
  'Rotura / vencimiento',
  'Error de carga',
  'Otro',
];

/// Escribe una fila en `movimientos_de_stock` (tipo `'AJUSTE'`) cuando el
/// stock —en unidades o en gramos, según corresponda— cambia respecto a
/// [anterior]. Mismo patrón que [registrarCambioDePrecio] (Regla 3), para
/// que el conteo físico del stock (Regla 8: "se vuelve confiable recién
/// cuando se hace un conteo físico y se ajusta") deje rastro igual que un
/// cambio de precio.
///
/// A diferencia de los precios, acá no hay "primera foto": el alta de un
/// producto no es una corrección, es el valor inicial, así que esta función
/// solo se llama desde `actualizarProducto`, nunca desde `crearProducto`.
Future<void> registrarAjusteDeStock(
  AppDatabase db, {
  required int productoId,
  required int usuarioId,
  required Producto anterior,
  required int stock,
  int? stockGramos,
  String? motivo,
}) async {
  final cambioUnidades = anterior.stock != stock;
  final cambioGramos = anterior.stockGramos != stockGramos;
  if (!cambioUnidades && !cambioGramos) return;

  await db
      .into(db.movimientosDeStock)
      .insert(
        MovimientosDeStockCompanion.insert(
          productoId: productoId,
          usuarioId: usuarioId,
          tipo: 'AJUSTE',
          stockAnterior: cambioUnidades
              ? Value(anterior.stock)
              : const Value.absent(),
          stockPosterior: cambioUnidades ? Value(stock) : const Value.absent(),
          gramosAnterior: cambioGramos
              ? Value(anterior.stockGramos)
              : const Value.absent(),
          gramosPosterior: cambioGramos
              ? Value(stockGramos)
              : const Value.absent(),
          motivo: Value(motivo),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );
}

/// Alta completa de un producto (a diferencia de la alta rápida de la fase
/// 3, que solo pide nombre y precio para vender ya mismo).
Future<int> crearProducto(
  AppDatabase db, {
  required String nombre,
  String? codigoBarras,
  int? categoriaId,
  int? proveedorId,
  bool esPesable = false,
  String tipoCigarrillo = 'ninguno',
  int? precioCentavos,
  int? costoCentavos,
  int? precioPorKiloCentavos,
  int? costoPorKiloCentavos,
  int stock = 0,
  int? stockGramos,
  int? stockMinimo,
  required int usuarioId,
  bool precioFijo = false,
}) async {
  if (esPesable && precioPorKiloCentavos == null) {
    // Un pesable sin precio por kilo es un error de carga, no un cero
    // silencioso (Regla 7).
    throw ArgumentError('Un producto pesable necesita precio_por_kilo');
  }

  // `codigoBarras` es unique a nivel de esquema — sin este chequeo, un
  // código repetido tira una excepción cruda de sqlite en vez de un error
  // de negocio claro. Bug real, encontrado en la companion (El dueño,
  // 2026-09-07: "no agrega bien o directamente no agrega" al dar de alta
  // desde el celular) — pero la validación va acá, no en cada pantalla que
  // llama a `crearProducto` (Proveedores en escritorio, alta de la
  // companion), para que las dos hereden el mismo chequeo (Regla 3).
  if (codigoBarras != null && codigoBarras.isNotEmpty) {
    final existente = await (db.select(
      db.productos,
    )..where((p) => p.codigoBarras.equals(codigoBarras))).getSingleOrNull();
    if (existente != null) {
      throw ArgumentError(
        'Ya existe un producto con ese código de barras: "${existente.nombre}"'
        '${existente.activo ? '' : ' (dado de baja)'}.',
      );
    }
  }

  final id = await db
      .into(db.productos)
      .insert(
        ProductosCompanion.insert(
          nombre: nombre,
          codigoBarras: Value(codigoBarras),
          categoriaId: Value(categoriaId),
          proveedorId: Value(proveedorId),
          esPesable: Value(esPesable),
          tipoCigarrillo: Value(tipoCigarrillo),
          precioCentavos: Value(precioCentavos),
          costoCentavos: Value(costoCentavos),
          precioPorKiloCentavos: Value(precioPorKiloCentavos),
          costoPorKiloCentavos: Value(costoPorKiloCentavos),
          precioFijo: Value(precioFijo),
          stock: Value(stock),
          stockGramos: Value(stockGramos),
          // Mínimo para el aviso de stock bajo (unidades o gramos según
          // `esPesable`, mismo criterio que `stock`/`stockGramos`).
          stockMinimo: esPesable
              ? const Value.absent()
              : Value(stockMinimo ?? 0),
          stockMinimoGramos: esPesable
              ? Value(stockMinimo)
              : const Value.absent(),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );

  await registrarCambioDePrecio(
    db,
    productoId: id,
    usuarioId: usuarioId,
    anterior: null,
    precioCentavos: precioCentavos,
    costoCentavos: costoCentavos,
    precioPorKiloCentavos: precioPorKiloCentavos,
    costoPorKiloCentavos: costoPorKiloCentavos,
  );

  return id;
}

/// Edición completa. Cambiar `esPesable` está permitido (con confirmación
/// del lado de la pantalla, no acá): un producto puede empezar como unidad y
/// pasar a pesable o viceversa sin romper las ventas ya hechas, que guardan
/// su propia foto en `lineas_de_venta` (Regla 4).
/// Completa el costo de las ventas ya hechas de [productoId] que quedaron
/// SIN costo (El dueño, 2026-09-26: "ya cargué el costo y no aparece nada").
/// Costo-foto (Regla 4) sigue intacto: una línea que ya tenía costo nunca se
/// toca — el motivo de esa regla es que un aumento no reescriba los
/// márgenes viejos, y acá no hay un costo viejo que pisar, solo uno que
/// faltaba ("el costo se completa después", Regla 9). Con eso, esas ventas
/// entran solas en la reposición y la ganancia.
///
/// Un costo $0 no completa nada: cuenta como "sin costo" (no se inventa una
/// ganancia del 100%).
///
/// Cada línea se completa con el costo de su propia forma (por kilo si la
/// línea fue pesable), no con la del producto hoy. `actualizado_en` se pisa
/// para que el cambio viaje por la sincronización.
Future<void> completarCostoDeVentasSinCosto(
  AppDatabase db, {
  required int productoId,
  required int? costoCentavos,
  required int? costoPorKiloCentavos,
}) async {
  final ahora = DateTime.now();
  for (final (pesable, costo) in [
    (false, costoCentavos),
    (true, costoPorKiloCentavos),
  ]) {
    if (costo == null || costo <= 0) continue;
    await (db.update(db.lineasDeVenta)..where(
          (l) =>
              l.productoId.equals(productoId) &
              l.costoUnitarioCentavos.isNull() &
              l.esPesable.equals(pesable),
        ))
        .write(
          LineasDeVentaCompanion(
            costoUnitarioCentavos: Value(costo),
            actualizadoEn: Value(ahora),
          ),
        );
  }
}

/// Carga solo el costo de un producto (por kilo si es pesable), dejando
/// todo lo demás como está — para completar costos desde "Productos sin
/// costo" en Separaciones. Pasa por [actualizarProducto] a propósito
/// (convención 3): así deja el mismo historial de precios y completa las
/// ventas que quedaron sin costo, igual que editar el producto entero.
Future<void> cargarCostoProducto(
  AppDatabase db, {
  required int productoId,
  required int costoCentavos,
  required int usuarioId,
}) async {
  final p = await (db.select(
    db.productos,
  )..where((t) => t.id.equals(productoId))).getSingle();
  await actualizarProducto(
    db,
    id: p.id,
    nombre: p.nombre,
    codigoBarras: p.codigoBarras,
    categoriaId: p.categoriaId,
    proveedorId: p.proveedorId,
    esPesable: p.esPesable,
    tipoCigarrillo: p.tipoCigarrillo,
    precioCentavos: p.precioCentavos,
    costoCentavos: p.esPesable ? p.costoCentavos : costoCentavos,
    precioPorKiloCentavos: p.precioPorKiloCentavos,
    costoPorKiloCentavos: p.esPesable ? costoCentavos : p.costoPorKiloCentavos,
    stock: p.stock,
    stockGramos: p.stockGramos,
    stockMinimo: p.stockMinimo,
    activo: p.activo,
    usuarioId: usuarioId,
  );
}

Future<void> actualizarProducto(
  AppDatabase db, {
  required int id,
  required String nombre,
  String? codigoBarras,
  int? categoriaId,
  int? proveedorId,
  required bool esPesable,
  String tipoCigarrillo = 'ninguno',
  int? precioCentavos,
  int? costoCentavos,
  int? precioPorKiloCentavos,
  int? costoPorKiloCentavos,
  required int stock,
  int? stockGramos,
  int? stockMinimo,
  required bool activo,
  required int usuarioId,
  String? motivoAjusteStock,
  bool? precioFijo,
}) async {
  if (esPesable && precioPorKiloCentavos == null) {
    throw ArgumentError('Un producto pesable necesita precio_por_kilo');
  }

  final anterior = await (db.select(
    db.productos,
  )..where((p) => p.id.equals(id))).getSingle();

  // Precio automático por proveedor (El dueño, 2026-09-29): si cambió el costo y
  // el producto sigue al porcentaje de su proveedor, el precio se recalcula
  // acá — un solo lugar, así lo cubren la edición a mano, el ajuste masivo de
  // costos y "Productos sin costo" (Regla 3).
  final costoAnterior = anterior.esPesable
      ? anterior.costoPorKiloCentavos
      : anterior.costoCentavos;
  final costoNuevo = esPesable ? costoPorKiloCentavos : costoCentavos;
  if (costoNuevo != costoAnterior && !(precioFijo ?? anterior.precioFijo)) {
    final automatico = await _precioAutomatico(
      db,
      proveedorId: proveedorId,
      tipoCigarrillo: tipoCigarrillo,
      esVarios: anterior.esVarios,
      costoCentavos: costoNuevo,
    );
    if (automatico != null) {
      if (esPesable) {
        precioPorKiloCentavos = automatico;
      } else {
        precioCentavos = automatico;
      }
    }
  }

  // Mismo chequeo que `crearProducto` (Regla 3) — cambiar el código a uno
  // que ya usa OTRO producto también viola la restricción unique del
  // esquema. Excluye el propio `id`: dejar el mismo código que ya tenía no
  // es un conflicto.
  if (codigoBarras != null &&
      codigoBarras.isNotEmpty &&
      codigoBarras != anterior.codigoBarras) {
    final existente =
        await (db.select(db.productos)..where(
              (p) =>
                  p.codigoBarras.equals(codigoBarras) & p.id.equals(id).not(),
            ))
            .getSingleOrNull();
    if (existente != null) {
      throw ArgumentError(
        'Ya existe un producto con ese código de barras: "${existente.nombre}"'
        '${existente.activo ? '' : ' (dado de baja)'}.',
      );
    }
  }

  await (db.update(db.productos)..where((p) => p.id.equals(id))).write(
    ProductosCompanion(
      nombre: Value(nombre),
      codigoBarras: Value(codigoBarras),
      categoriaId: Value(categoriaId),
      proveedorId: Value(proveedorId),
      esPesable: Value(esPesable),
      tipoCigarrillo: Value(tipoCigarrillo),
      precioCentavos: Value(precioCentavos),
      costoCentavos: Value(costoCentavos),
      precioPorKiloCentavos: Value(precioPorKiloCentavos),
      costoPorKiloCentavos: Value(costoPorKiloCentavos),
      stock: Value(stock),
      stockGramos: Value(stockGramos),
      // Null = no se tocó el mínimo (llamadores viejos no lo pasan).
      stockMinimo: stockMinimo == null || esPesable
          ? const Value.absent()
          : Value(stockMinimo),
      stockMinimoGramos: stockMinimo == null || !esPesable
          ? const Value.absent()
          : Value(stockMinimo),
      precioFijo: precioFijo == null ? const Value.absent() : Value(precioFijo),
      activo: Value(activo),
      actualizadoEn: Value(DateTime.now()),
    ),
  );

  await registrarCambioDePrecio(
    db,
    productoId: id,
    usuarioId: usuarioId,
    anterior: anterior,
    precioCentavos: precioCentavos,
    costoCentavos: costoCentavos,
    precioPorKiloCentavos: precioPorKiloCentavos,
    costoPorKiloCentavos: costoPorKiloCentavos,
  );
  await completarCostoDeVentasSinCosto(
    db,
    productoId: id,
    costoCentavos: costoCentavos,
    costoPorKiloCentavos: costoPorKiloCentavos,
  );

  await registrarAjusteDeStock(
    db,
    productoId: id,
    usuarioId: usuarioId,
    anterior: anterior,
    stock: stock,
    stockGramos: stockGramos,
    motivo: motivoAjusteStock,
  );
}

/// Edición masiva de precio o costo (El dueño, 2026-09-16: "si quiero subir el
/// precio de 3 productos iguales de distinta variante, hacerlo a la vez" —
/// "maximizar lo que se puede hacer con el ajuste masivo" sumó costo al
/// mismo mecanismo). Producto por producto, reusando [actualizarProducto]
/// entero (Regla 3: un solo camino de escritura) — así el historial de
/// precios y cualquier otro efecto secundario quedan idénticos a editar uno
/// por uno a mano, no una segunda forma de escribir el mismo dato.
///
/// Cada producto ajusta su PROPIO campo según [Producto.esPesable] —
/// `precioCentavos`/`costoCentavos` por unidad, `precioPorKiloCentavos`/
/// `costoPorKiloCentavos` si es pesable — así que una selección mixta
/// (unidades + pesables) no mezcla el sentido del número. El resto de los
/// campos de cada producto queda tal cual estaba.
///
/// Todo en una transacción: si algo falla a mitad de camino (ej. un producto
/// borrado por otra pantalla al mismo tiempo), no queda una edición a medio
/// aplicar sobre la selección.
Future<void> ajustarMontoEnLote(
  AppDatabase db, {
  required List<int> productoIds,
  required CampoMonto campo,
  required TipoAjustePrecio tipo,
  required int valor,
  required int usuarioId,
}) {
  return db.transaction(() async {
    for (final id in productoIds) {
      final anterior = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(id))).getSingle();

      final montoActual = campo == CampoMonto.precio
          ? (anterior.esPesable
                ? anterior.precioPorKiloCentavos
                : anterior.precioCentavos)
          : (anterior.esPesable
                ? anterior.costoPorKiloCentavos
                : anterior.costoCentavos);
      final montoNuevo = aplicarAjustePrecio(
        precioActualCentavos: montoActual ?? 0,
        tipo: tipo,
        valor: valor,
      );
      final ajustaPrecio = campo == CampoMonto.precio;

      await actualizarProducto(
        db,
        id: id,
        nombre: anterior.nombre,
        codigoBarras: anterior.codigoBarras,
        categoriaId: anterior.categoriaId,
        proveedorId: anterior.proveedorId,
        esPesable: anterior.esPesable,
        tipoCigarrillo: anterior.tipoCigarrillo,
        precioCentavos: ajustaPrecio && !anterior.esPesable
            ? montoNuevo
            : anterior.precioCentavos,
        costoCentavos: !ajustaPrecio && !anterior.esPesable
            ? montoNuevo
            : anterior.costoCentavos,
        precioPorKiloCentavos: ajustaPrecio && anterior.esPesable
            ? montoNuevo
            : anterior.precioPorKiloCentavos,
        costoPorKiloCentavos: !ajustaPrecio && anterior.esPesable
            ? montoNuevo
            : anterior.costoPorKiloCentavos,
        stock: anterior.stock,
        stockGramos: anterior.stockGramos,
        activo: anterior.activo,
        usuarioId: usuarioId,
        // Un precio ajustado a mano en lote deja de seguir al porcentaje del
        // proveedor (El dueño, 2026-09-29).
        precioFijo: ajustaPrecio ? true : null,
      );
    }
  });
}

/// Reasigna la categoría de varios productos a la vez — mismo camino de
/// escritura que un cambio manual ([actualizarProducto], Regla 3). `null`
/// vale "sin categoría", igual que en la edición de a uno.
Future<void> asignarCategoriaEnLote(
  AppDatabase db, {
  required List<int> productoIds,
  required int? categoriaId,
  required int usuarioId,
}) {
  return db.transaction(() async {
    for (final id in productoIds) {
      final anterior = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(id))).getSingle();
      await actualizarProducto(
        db,
        id: id,
        nombre: anterior.nombre,
        codigoBarras: anterior.codigoBarras,
        categoriaId: categoriaId,
        proveedorId: anterior.proveedorId,
        esPesable: anterior.esPesable,
        tipoCigarrillo: anterior.tipoCigarrillo,
        precioCentavos: anterior.precioCentavos,
        costoCentavos: anterior.costoCentavos,
        precioPorKiloCentavos: anterior.precioPorKiloCentavos,
        costoPorKiloCentavos: anterior.costoPorKiloCentavos,
        stock: anterior.stock,
        stockGramos: anterior.stockGramos,
        activo: anterior.activo,
        usuarioId: usuarioId,
      );
    }
  });
}

/// Reasigna el proveedor de varios productos a la vez — mismo criterio que
/// [asignarCategoriaEnLote]. `null` vale "sin proveedor".
Future<void> asignarProveedorEnLote(
  AppDatabase db, {
  required List<int> productoIds,
  required int? proveedorId,
  required int usuarioId,
}) {
  return db.transaction(() async {
    for (final id in productoIds) {
      final anterior = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(id))).getSingle();
      await actualizarProducto(
        db,
        id: id,
        nombre: anterior.nombre,
        codigoBarras: anterior.codigoBarras,
        categoriaId: anterior.categoriaId,
        proveedorId: proveedorId,
        esPesable: anterior.esPesable,
        tipoCigarrillo: anterior.tipoCigarrillo,
        precioCentavos: anterior.precioCentavos,
        costoCentavos: anterior.costoCentavos,
        precioPorKiloCentavos: anterior.precioPorKiloCentavos,
        costoPorKiloCentavos: anterior.costoPorKiloCentavos,
        stock: anterior.stock,
        stockGramos: anterior.stockGramos,
        activo: anterior.activo,
        usuarioId: usuarioId,
      );
    }
  });
}

/// Nunca hay borrado real de un producto (rompería `lineas_de_venta`
/// históricas): la única acción es activar o desactivar.
Future<void> cambiarActivo(
  AppDatabase db, {
  required int id,
  required bool activo,
}) {
  return (db.update(db.productos)..where((p) => p.id.equals(id))).write(
    // `actualizadoEn` es lo que hace que el cambio viaje al celular y a los otros equipos (sin esto no se sincroniza).
    ProductosCompanion(activo: Value(activo), actualizadoEn: Value(DateTime.now())),
  );
}

/// Activa o desactiva varios productos a la vez — mismo camino que
/// [cambiarActivo] uno por uno, en una sola transacción.
Future<void> cambiarActivoEnLote(
  AppDatabase db, {
  required List<int> productoIds,
  required bool activo,
}) {
  return db.transaction(() async {
    for (final id in productoIds) {
      await cambiarActivo(db, id: id, activo: activo);
    }
  });
}

Future<List<HistorialDePrecio>> historialDelProducto(
  AppDatabase db,
  int productoId,
) {
  return (db.select(db.historialDePrecios)
        ..where((h) => h.productoId.equals(productoId))
        // `fecha` es de resolución de un segundo (CURRENT_TIMESTAMP de
        // SQLite): dos cambios en el mismo segundo empatan ahí. `id` como
        // desempate garantiza el orden real aunque el reloj no alcance a
        // distinguirlos — pasa seguido en los tests, y podría pasarle a
        // alguien corrigiendo un precio dos veces muy rápido.
        ..orderBy([
          (h) => OrderingTerm.desc(h.fecha),
          (h) => OrderingTerm.desc(h.id),
        ]))
      .get();
}

/// Lista para la columna izquierda de la pantalla de productos. "Varios"
/// nunca aparece acá: no es un producto editable, es la pieza estructural
/// de la Regla 5.
///
/// Los cuatro `sin*` (El dueño, 2026-09-19: "filtrar por productos sin
/// proveedor, sin costo, etcétera" — pulido de catálogo desde la companion)
/// son filtros de higiene de datos, no de negocio: cada uno mira una sola
/// columna nullable de `Productos`. Se pueden combinar entre sí y con
/// [categoriaId]/[proveedorId]/[busqueda] (se van sumando como AND), aunque
/// la pantalla que los usa hoy ofrece uno solo por vez. `sinCosto` mira
/// `costoPorKiloCentavos` o `costoCentavos` según `esPesable` — mismo
/// criterio exacto que `productosSinCostoOrdenadosPorVenta` más abajo
/// (Regla 3: una sola definición de "sin costo").
Future<List<Producto>> listarProductos(
  AppDatabase db, {
  String? busqueda,
  int? categoriaId,
  int? proveedorId,
  bool soloActivos = true,
  bool sinProveedor = false,
  bool sinCosto = false,
  bool sinCategoria = false,
  bool sinCodigoBarras = false,
}) async {
  // Las promos no son un producto editable con costo y stock propios: tienen su
  // propio creador y no van al celular ni a las listas de gestión.
  final query = db.select(db.productos)..where((p) => p.esVarios.equals(false) & p.esPromo.equals(false));
  if (soloActivos) query.where((p) => p.activo.equals(true));
  if (categoriaId != null) {
    query.where((p) => p.categoriaId.equals(categoriaId));
  }
  if (proveedorId != null) {
    query.where((p) => p.proveedorId.equals(proveedorId));
  }
  if (sinProveedor) query.where((p) => p.proveedorId.isNull());
  if (sinCosto) {
    query.where(
      (p) =>
          (p.esPesable.equals(true) & p.costoPorKiloCentavos.isNull()) |
          (p.esPesable.equals(false) & p.costoCentavos.isNull()),
    );
  }
  if (sinCategoria) query.where((p) => p.categoriaId.isNull());
  if (sinCodigoBarras) query.where((p) => p.codigoBarras.isNull());

  final productos = await query.get();

  if (busqueda == null || busqueda.trim().isEmpty) return productos;
  final normalizado = normalizarTexto(busqueda);
  return productos
      .where((p) => normalizarTexto(p.nombre).contains(normalizado))
      .toList();
}

/// Match exacto de código de barras, para el escáner de la companion app
/// (2026-09-07) — a diferencia de `listarProductos`, que solo busca por
/// nombre. `null` si no hay ningún producto activo con ese código, el mismo
/// caso que en la venta ofrece "dar de alta" en vez de una lista vacía.
Future<Producto?> productoPorCodigoBarras(AppDatabase db, String codigo) async {
  final normalizado = normalizarTexto(codigo);
  if (normalizado.isEmpty) return null;
  final productos = await (db.select(
    db.productos,
  )..where((p) => p.activo.equals(true))).get();
  for (final p in productos) {
    if (normalizarTexto(p.codigoBarras ?? '') == normalizado) return p;
  }
  return null;
}

class ProductoSinCosto {
  final Producto producto;
  final int totalVendidoCentavos;
  const ProductoSinCosto({
    required this.producto,
    required this.totalVendidoCentavos,
  });
}

/// Productos activos sin costo cargado (ni por unidad ni por kilo, según
/// corresponda), ordenados por cuánto se vendió de cada uno: el mismo
/// indicador que el cierre de caja resume como "vendido sin costo" (Regla
/// 5), acá desglosado producto por producto para saber cuál completar
/// primero — el que más pesa en la reposición que no se está calculando.
Future<List<ProductoSinCosto>> productosSinCostoOrdenadosPorVenta(
  AppDatabase db,
) async {
  final productos = await (db.select(
    db.productos,
  )..where((p) => p.activo.equals(true) & p.esVarios.equals(false))).get();

  final sinCosto = productos.where(
    (p) =>
        p.esPesable ? p.costoPorKiloCentavos == null : p.costoCentavos == null,
  );

  final resultado = <ProductoSinCosto>[];
  for (final producto in sinCosto) {
    final lineas = await (db.select(
      db.lineasDeVenta,
    )..where((l) => l.productoId.equals(producto.id))).get();

    final totalVendido = lineas.fold<int>(0, (acumulado, linea) {
      final subtotal = linea.esPesable
          ? subtotalPesable(
              montoPorKiloCentavos: linea.precioUnitarioCentavos,
              gramos: linea.gramos!,
            )
          : linea.precioUnitarioCentavos * (linea.cantidad ?? 1);
      return acumulado + subtotal;
    });

    resultado.add(
      ProductoSinCosto(producto: producto, totalVendidoCentavos: totalVendido),
    );
  }

  resultado.sort(
    (a, b) => b.totalVendidoCentavos.compareTo(a.totalVendidoCentavos),
  );
  return resultado;
}

/// true si el producto está agotado o en negativo — el stock informa,
/// nunca bloquea (Regla 8), así que "agotado" incluye lo que ya bajó de
/// cero. Mira `stockGramos` para un pesable, `stock` para el resto.
bool productoAgotado(Producto p) =>
    (p.esPesable ? p.stockGramos ?? 0 : p.stock) <= 0;

/// Para la pantalla de stock por proveedor (Regla 8, conteo físico
/// recorriendo la góndola): los agotados o negativos primero, para que
/// sean lo primero que se corrige, alfabético dentro de cada grupo para
/// encontrar un producto puntual sin tener que recorrer toda la lista.
List<Producto> ordenarAgotadosPrimero(List<Producto> productos) {
  final ordenados = [...productos];
  ordenados.sort((a, b) {
    final agotadoA = productoAgotado(a);
    final agotadoB = productoAgotado(b);
    if (agotadoA != agotadoB) return agotadoA ? -1 : 1;
    return normalizarTexto(a.nombre).compareTo(normalizarTexto(b.nombre));
  });
  return ordenados;
}

/// Ajuste rápido de stock desde la pantalla de "Stock por proveedor": a
/// diferencia de `actualizarProducto`, no toca precio/nombre/costo — solo
/// el stock, y deja el mismo rastro en `movimientos_de_stock` (Regla 8).
Future<void> ajustarStockRapido(
  AppDatabase db, {
  required int productoId,
  required int usuarioId,
  required int stock,
  int? stockGramos,
  String? motivo,
}) async {
  final anterior = await (db.select(
    db.productos,
  )..where((p) => p.id.equals(productoId))).getSingle();

  await (db.update(db.productos)..where((p) => p.id.equals(productoId))).write(
    ProductosCompanion(
      stock: Value(stock),
      stockGramos: Value(stockGramos),
      actualizadoEn: Value(DateTime.now()),
    ),
  );

  await registrarAjusteDeStock(
    db,
    productoId: productoId,
    usuarioId: usuarioId,
    anterior: anterior,
    stock: stock,
    stockGramos: stockGramos,
    motivo: motivo,
  );
}

/// Ajuste masivo de stock (El dueño, 2026-09-19: "editor masivo, ya sea de
/// precios costo stock etc etc") — mismo criterio que [ajustarMontoEnLote]:
/// producto por producto, reusando [ajustarStockRapido] entero (Regla 3 y
/// Regla 6/8: cada producto deja su propio movimiento en
/// `movimientos_de_stock`, un ajuste masivo no es una excepción). Cada
/// producto ajusta su PROPIO campo según `esPesable` — `stockGramos` si es
/// pesable, `stock` si no — así que una selección mixta no mezcla unidades
/// con gramos.
Future<void> ajustarStockEnLote(
  AppDatabase db, {
  required List<int> productoIds,
  required TipoAjusteStock tipo,
  required int valor,
  required int usuarioId,
  String motivo = 'Ajuste masivo',
}) {
  return db.transaction(() async {
    for (final id in productoIds) {
      final anterior = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(id))).getSingle();

      final actual = anterior.esPesable
          ? (anterior.stockGramos ?? 0)
          : anterior.stock;
      final nuevo = aplicarAjusteStock(
        actual: actual,
        tipo: tipo,
        valor: valor,
      );

      await ajustarStockRapido(
        db,
        productoId: id,
        usuarioId: usuarioId,
        stock: anterior.esPesable ? anterior.stock : nuevo,
        stockGramos: anterior.esPesable ? nuevo : null,
        motivo: motivo,
      );
    }
  });
}

Future<List<Categoria>> listarCategorias(AppDatabase db) =>
    db.select(db.categorias).get();

Future<int> crearCategoria(AppDatabase db, String nombre) {
  return db
      .into(db.categorias)
      .insert(
        CategoriasCompanion.insert(
          nombre: nombre,
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

/// Markup de referencia por categoría (fase 8) — puramente informativo,
/// nunca se usa para calcular ni completar un precio (Regla 14).
Future<void> actualizarMarkupCategoria(
  AppDatabase db, {
  required int categoriaId,
  required int markupBp,
}) {
  return (db.update(
    db.categorias,
  )..where((c) => c.id.equals(categoriaId))).write(
    CategoriasCompanion(
      markupDefaultBp: Value(markupBp),
      actualizadoEn: Value(DateTime.now()),
    ),
  );
}

Future<List<Proveedor>> listarProveedores(AppDatabase db) =>
    db.select(db.proveedores).get();

// ─── Precio automático por proveedor ─────────────────────────────────────
//
// El dueño, 2026-09-29: "un selector de porcentaje por proveedor + redondeo
// para arriba a la próxima centena, exceptuando los cigarros". El precio de
// un producto con costo sale de `precioConGananciaACentena` (domain/ganancia.dart)
// con el porcentaje de su proveedor — salvo cigarrillos, "Varios" y los
// productos marcados con precio fijo.

/// El precio que le toca a un producto según el porcentaje de su proveedor,
/// o null si no le corresponde uno automático (sin proveedor, proveedor sin
/// porcentaje, cigarrillo, "Varios" o sin costo cargado).
Future<int?> _precioAutomatico(
  AppDatabase db, {
  required int? proveedorId,
  required String tipoCigarrillo,
  required bool esVarios,
  required int? costoCentavos,
}) async {
  if (proveedorId == null || tipoCigarrillo != 'ninguno' || esVarios) {
    return null;
  }
  if (costoCentavos == null || costoCentavos <= 0) return null;
  final proveedor = await (db.select(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).getSingleOrNull();
  final bp = proveedor?.markupBp;
  if (bp == null) return null;
  return precioConGananciaACentena(costoCentavos, bp);
}

/// Fija (o saca, con null) el porcentaje de ganancia de un proveedor. No toca
/// ningún precio: eso es [aplicarPorcentajeDeProveedor].
Future<void> guardarPorcentajeProveedor(
  AppDatabase db, {
  required int proveedorId,
  required int? gananciaBp,
}) {
  return (db.update(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).write(
    ProveedoresCompanion(
      markupBp: Value(gananciaBp),
      actualizadoEn: Value(DateTime.now()),
    ),
  );
}

/// Un precio que cambiaría al aplicar el porcentaje del proveedor.
class CambioDePrecioPropuesto {
  const CambioDePrecioPropuesto({
    required this.producto,
    required this.precioActualCentavos,
    required this.precioNuevoCentavos,
  });

  final Producto producto;
  final int? precioActualCentavos;
  final int precioNuevoCentavos;
}

/// Los productos activos de [proveedorId] cuyo precio cambiaría al aplicar su
/// porcentaje: con costo, sin precio fijo, que no sean cigarrillos ni
/// "Varios", y cuyo precio de hoy sea distinto del calculado.
Future<List<CambioDePrecioPropuesto>> cambiosPorPorcentaje(
  AppDatabase db,
  int proveedorId,
) async {
  final productos =
      await (db.select(db.productos)..where(
            (p) =>
                p.proveedorId.equals(proveedorId) &
                p.activo.equals(true) &
                p.precioFijo.equals(false),
          ))
          .get();
  final cambios = <CambioDePrecioPropuesto>[];
  for (final p in productos) {
    final nuevo = await _precioAutomatico(
      db,
      proveedorId: proveedorId,
      tipoCigarrillo: p.tipoCigarrillo,
      esVarios: p.esVarios,
      costoCentavos: p.esPesable ? p.costoPorKiloCentavos : p.costoCentavos,
    );
    if (nuevo == null) continue;
    final actual = p.esPesable ? p.precioPorKiloCentavos : p.precioCentavos;
    if (actual == nuevo) continue;
    cambios.add(
      CambioDePrecioPropuesto(
        producto: p,
        precioActualCentavos: actual,
        precioNuevoCentavos: nuevo,
      ),
    );
  }
  return cambios;
}

/// Recalcula los precios de [proveedorId] con su porcentaje. Pasa por
/// [actualizarProducto] (Regla 3): deja el mismo historial de precios que
/// editar cada producto a mano. Devuelve cuántos cambiaron. Todo en una
/// transacción: o se aplican todos o ninguno.
Future<int> aplicarPorcentajeDeProveedor(
  AppDatabase db, {
  required int proveedorId,
  required int usuarioId,
}) {
  return db.transaction(() async {
    final cambios = await cambiosPorPorcentaje(db, proveedorId);
    for (final c in cambios) {
      final p = c.producto;
      await actualizarProducto(
        db,
        id: p.id,
        nombre: p.nombre,
        codigoBarras: p.codigoBarras,
        categoriaId: p.categoriaId,
        proveedorId: p.proveedorId,
        esPesable: p.esPesable,
        tipoCigarrillo: p.tipoCigarrillo,
        precioCentavos: p.esPesable ? p.precioCentavos : c.precioNuevoCentavos,
        costoCentavos: p.costoCentavos,
        precioPorKiloCentavos: p.esPesable
            ? c.precioNuevoCentavos
            : p.precioPorKiloCentavos,
        costoPorKiloCentavos: p.costoPorKiloCentavos,
        stock: p.stock,
        stockGramos: p.stockGramos,
        activo: p.activo,
        usuarioId: usuarioId,
      );
    }
    return cambios.length;
  });
}

/// El precio automático de un producto que todavía no está guardado (alta o
/// edición en el diálogo): mismo cálculo que usa [actualizarProducto].
Future<int?> precioAutomaticoParaProducto(
  AppDatabase db, {
  required int? proveedorId,
  required String tipoCigarrillo,
  required int? costoCentavos,
}) => _precioAutomatico(
  db,
  proveedorId: proveedorId,
  tipoCigarrillo: tipoCigarrillo,
  esVarios: false,
  costoCentavos: costoCentavos,
);
