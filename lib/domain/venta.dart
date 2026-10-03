// La representación de una venta con la que trabaja el dominio.
//
// No es la tabla de base de datos (eso es fase 2): es lo mínimo que las
// funciones puras de este directorio necesitan para calcular el total. El
// esquema de datos sale de reflejar esto, no al revés.
//
// El medio de pago NO es un campo de [Venta] a propósito: se elige recién al
// cobrar (Alt+E / Alt+Q / Alt+X), y el mismo carrito puede recalcularse con
// distintos medios antes de confirmar (Regla 6: el recargo "aparece o
// desaparece" en el momento). Guardarlo en la venta invitaría a cachear un
// total que ya no vale.

import 'descuento.dart';
import 'medio_pago.dart';
import 'pesables.dart';
import 'recargo_cigarrillos.dart';
import 'redondeo.dart';

enum TipoCigarrillo {
  /// No es cigarrillo: almacén, fiambre, "Varios".
  ninguno,

  /// Atado completo. Es lo único que cuenta para el recargo (Regla 6).
  atado,

  /// Suelto. También lleva recargo por pago virtual, por cigarro (El dueño,
  /// 2026-09-10; antes no llevaba): ver `recargo_cigarrillos.dart`.
  suelto,
}

/// El valor crudo de `productos.tipoCigarrillo` (una columna de texto, no un
/// enum de esquema) a su equivalente de dominio. Extraída de
/// `repositorio_ventas.dart` (spike companion app, 2026-09-07): tanto
/// `lineaDesdeProducto` (escritorio, desde una fila de drift) como el
/// celular (desde `ProductoCompanion`, sin abrir ninguna base) arman una
/// `LineaVenta` a partir de este mismo texto — Regla 3, un solo lugar para
/// el mapeo, aunque las dos fuentes de datos sean distintas.
TipoCigarrillo tipoCigarrilloDesde(String valor) => switch (valor) {
  'atado' => TipoCigarrillo.atado,
  'suelto' => TipoCigarrillo.suelto,
  _ => TipoCigarrillo.ninguno,
};

/// Una línea de venta. Sellada en dos formas — [LineaVentaPorUnidad] y
/// [LineaVentaPesable] — a propósito (Regla 4): así el compilador impide
/// tratar una línea pesable como si fuera "precio × cantidad de unidades",
/// que es exactamente el error que la Regla 7 pide evitar.
sealed class LineaVenta {
  const LineaVenta();

  String get productoId;
  String get nombreProducto;
  String? get proveedorId;
  bool get esVarios;
  TipoCigarrillo get tipoCigarrillo;

  /// Subtotal de la línea, siempre calculado por el helper único que le
  /// corresponde a su tipo (nunca "precio × cantidad" escrito a mano).
  int get subtotalCentavos;

  /// Costo-foto total de la línea (Regla 4). Null cuando no había costo
  /// cargado al momento de la venta: "Varios" nunca lo tiene (Regla 5), y un
  /// producto recién dado de alta por escaneo tampoco hasta completarlo
  /// (Regla 9). En los dos casos es un dato ausente, no un cero — tratarlo
  /// como 0 mentiría en la ganancia y en la reposición.
  int? get costoLineaCentavos;
}

/// Producto vendido por unidad: almacén común, cigarrillos y "Varios".
class LineaVentaPorUnidad extends LineaVenta {
  @override
  final String productoId;
  @override
  final String nombreProducto;
  @override
  final String? proveedorId;
  @override
  final bool esVarios;
  @override
  final TipoCigarrillo tipoCigarrillo;

  final int cantidad;

  /// Foto del precio al momento de la venta (Regla 4).
  final int precioUnitarioCentavos;

  /// Foto del costo al momento de la venta. Ver [LineaVenta.costoLineaCentavos].
  final int? costoUnitarioCentavos;

  const LineaVentaPorUnidad({
    required this.productoId,
    required this.nombreProducto,
    required this.proveedorId,
    required this.cantidad,
    this.esVarios = false,
    this.tipoCigarrillo = TipoCigarrillo.ninguno,
    required this.precioUnitarioCentavos,
    this.costoUnitarioCentavos,
  });

  @override
  int get subtotalCentavos => precioUnitarioCentavos * cantidad;

  @override
  int? get costoLineaCentavos =>
      costoUnitarioCentavos == null ? null : costoUnitarioCentavos! * cantidad;
}

/// Producto pesable (fiambres, Fiambrería): se carga en gramos, nunca en
/// cantidad de unidades (Regla 7).
class LineaVentaPesable extends LineaVenta {
  @override
  final String productoId;
  @override
  final String nombreProducto;
  @override
  final String? proveedorId;

  final int gramos;

  /// Foto del precio por kilo. Nunca null: un pesable sin precio cargado es
  /// un error, no un cero silencioso (Regla 7).
  final int precioPorKiloCentavos;

  /// Foto del costo por kilo. Ver [LineaVenta.costoLineaCentavos].
  final int? costoPorKiloCentavos;

  const LineaVentaPesable({
    required this.productoId,
    required this.nombreProducto,
    required this.proveedorId,
    required this.gramos,
    required this.precioPorKiloCentavos,
    this.costoPorKiloCentavos,
  });

  // Un pesable nunca es "Varios" ni cigarrillo: son categorías que no se
  // superponen en este negocio.
  @override
  bool get esVarios => false;
  @override
  TipoCigarrillo get tipoCigarrillo => TipoCigarrillo.ninguno;

  @override
  int get subtotalCentavos => subtotalPesable(
    montoPorKiloCentavos: precioPorKiloCentavos,
    gramos: gramos,
  );

  @override
  int? get costoLineaCentavos => costoPorKiloCentavos == null
      ? null
      : subtotalPesable(
          montoPorKiloCentavos: costoPorKiloCentavos!,
          gramos: gramos,
        );
}

/// Suma dos líneas del mismo producto en una sola (El dueño: agregar el mismo
/// código dos veces sube la cantidad de la línea existente, no crea una
/// segunda). Extraída de `VentaControlador._sumarLineas` (spike companion
/// app, 2026-09-07) para que el carrito del celular haga exactamente lo
/// mismo que el del escritorio al tocar un producto repetido (Regla 3).
///
/// Un mismo `productoId` no puede ser pesable en una línea y por unidad en
/// otra — el catálogo no deja que un producto cambie de tipo.
LineaVenta sumarLineasVenta(LineaVenta actual, LineaVenta nueva) {
  if (actual is LineaVentaPorUnidad && nueva is LineaVentaPorUnidad) {
    return LineaVentaPorUnidad(
      productoId: actual.productoId,
      nombreProducto: actual.nombreProducto,
      proveedorId: actual.proveedorId,
      cantidad: actual.cantidad + nueva.cantidad,
      esVarios: actual.esVarios,
      tipoCigarrillo: actual.tipoCigarrillo,
      precioUnitarioCentavos: actual.precioUnitarioCentavos,
      costoUnitarioCentavos: actual.costoUnitarioCentavos,
    );
  }
  if (actual is LineaVentaPesable && nueva is LineaVentaPesable) {
    return LineaVentaPesable(
      productoId: actual.productoId,
      nombreProducto: actual.nombreProducto,
      proveedorId: actual.proveedorId,
      gramos: actual.gramos + nueva.gramos,
      precioPorKiloCentavos: actual.precioPorKiloCentavos,
      costoPorKiloCentavos: actual.costoPorKiloCentavos,
    );
  }
  throw StateError('Línea pesable y por unidad con el mismo productoId');
}

/// El carrito de una venta: sus líneas, sin medio de pago todavía.
class Venta {
  final List<LineaVenta> lineas;

  const Venta({required this.lineas});

  int get subtotalCentavos =>
      lineas.fold(0, (acumulado, linea) => acumulado + linea.subtotalCentavos);

  int get cantidadAtadosCigarrillos => lineas
      .whereType<LineaVentaPorUnidad>()
      .where((linea) => linea.tipoCigarrillo == TipoCigarrillo.atado)
      .fold(0, (acumulado, linea) => acumulado + linea.cantidad);

  int get cantidadSueltosCigarrillos => lineas
      .whereType<LineaVentaPorUnidad>()
      .where((linea) => linea.tipoCigarrillo == TipoCigarrillo.suelto)
      .fold(0, (acumulado, linea) => acumulado + linea.cantidad);
}

class ResultadoTotalVenta {
  final int subtotalCentavos;
  final int recargoCigarrillosCentavos;
  final int descuentoCentavos;
  final int redondeoCentavos;
  final int totalCentavos;

  const ResultadoTotalVenta({
    required this.subtotalCentavos,
    required this.recargoCigarrillosCentavos,
    this.descuentoCentavos = 0,
    required this.redondeoCentavos,
    required this.totalCentavos,
  });
}

/// Calcula el total a cobrar de [venta] para un [composicionPago] dado.
///
/// Orden fijo, tal como lo describe la Regla 6: el recargo de cigarrillos se
/// suma primero; el descuento (Regla 17, `descuento.dart`) se resta después,
/// sobre el total que ya incluye el recargo; el redondeo se aplica último,
/// sobre lo que queda después del descuento — así el monto final que paga el
/// cliente en efectivo sigue siendo un número redondo, en vez de que un
/// descuento posterior al redondeo lo rompa. Invertir cualquiera de estos
/// pasos cambia el resultado cuando los montos no son múltiplos exactos entre sí.
ResultadoTotalVenta calcularTotalVenta({
  required Venta venta,
  required ComposicionPago composicionPago,
  required ConfigRecargoCigarrillos configRecargoCigarrillos,
  required int pasoRedondeoCentavos,
  TipoDescuento? tipoDescuento,
  int valorDescuento = 0,
}) {
  final subtotal = venta.subtotalCentavos;

  final recargo = recargoCigarrillos(
    cantidadAtados: venta.cantidadAtadosCigarrillos,
    cantidadSueltos: venta.cantidadSueltosCigarrillos,
    composicionPago: composicionPago,
    config: configRecargoCigarrillos,
  );

  final totalConRecargo = subtotal + recargo;
  final descuento = tipoDescuento == null
      ? 0
      : calcularDescuento(
          baseCentavos: totalConRecargo,
          tipo: tipoDescuento,
          valor: valorDescuento,
        );

  final resultadoRedondeo = redondeoDeVenta(
    totalCentavos: totalConRecargo - descuento,
    composicionPago: composicionPago,
    pasoCentavos: pasoRedondeoCentavos,
  );

  return ResultadoTotalVenta(
    subtotalCentavos: subtotal,
    recargoCigarrillosCentavos: recargo,
    descuentoCentavos: descuento,
    redondeoCentavos: resultadoRedondeo.montoRedondeoCentavos,
    totalCentavos: resultadoRedondeo.totalCentavos,
  );
}
