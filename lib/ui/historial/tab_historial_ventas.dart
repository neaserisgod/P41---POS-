// Historial de ventas, filtrable — pestaña de Historial desde 2026-09-26
// (antes vivía en Reportes). Nació en Reportes (El dueño, 2026-09-07: "que sea
// filtrable... tipo mercado pago... que también sirva para un control
// manual en caso de desconfiar de los números"). Mismo repositorio que la
// pantalla equivalente del celular (Regla 3).
//
// Distribución del "Lenguaje de diseño" (El dueño, 2026-09-26, mock
// `HistorialVentas.dc.html`): filtros arriba (período, medio, búsqueda),
// la lista de ventas agrupada por día a la izquierda con lo vendido, los
// tickets y el promedio, y la venta elegida a la derecha con sus líneas, el
// total, la ganancia y las acciones (reimprimir, editar, anular).
//
// Anular (El dueño, 2026-09-13): solo mientras la sesión de esa venta siga
// abierta, revirtiendo stock y caja sin borrar la fila (`anularVenta`) —
// Regla 6, nunca se pierde el rastro.

import 'package:flutter/material.dart';

import '../navegacion/refresco_por_celular.dart';
import '../../data/database.dart';
import '../../data/linea_venta_reconstruccion.dart';
import '../../data/repositorio_edicion_venta.dart';
import '../../data/repositorio_historial.dart' show lineasDeVenta;
import '../../data/repositorio_historial_ventas.dart';
import '../../domain/dinero.dart';
import '../../domain/equilibrio.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/fechas.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../impresion/dialogo_imprimir_ticket.dart';
import '../navegacion/busqueda_contextual.dart' show coincideBusqueda;
import '../tema/acentos.dart';
import '../tema/tema_inverso.dart';
import '../tema/presionable.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import 'pantalla_editor_venta.dart';
import 'periodo_historial.dart';
import '../tema/esqueleto.dart';
import '../tema/movimiento.dart';

extension on MedioVentaHistorial {
  String get etiqueta => switch (this) {
    MedioVentaHistorial.efectivo => 'Efectivo',
    MedioVentaHistorial.qr => 'QR',
    MedioVentaHistorial.debitCard => 'Débito',
    MedioVentaHistorial.mixto => 'Mixto',
  };

  Color color(BuildContext context) {
    final a = context.acentosPlazoleta;
    return switch (this) {
      MedioVentaHistorial.efectivo => a.dinero,
      MedioVentaHistorial.qr => a.qr,
      MedioVentaHistorial.debitCard => a.debito,
      MedioVentaHistorial.mixto => a.mixto,
    };
  }
}

class TabHistorialVentas extends StatefulWidget {
  const TabHistorialVentas({super.key, required this.db, required this.usuarioId, this.busqueda = ''});

  final AppDatabase db;
  final int usuarioId;

  /// Lo escrito en el buscador de arriba (contextual, 2026-09-28): número de
  /// venta o producto. Antes era un campo propio de esta pestaña.
  final String busqueda;

  @override
  State<TabHistorialVentas> createState() => _TabHistorialVentasState();
}

class _TabHistorialVentasState extends State<TabHistorialVentas> with RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _cargar();

  PeriodoHistorial _periodo = PeriodoHistorial.hoy;
  MedioVentaHistorial? _filtroMedio;
  List<VentaDelHistorial>? _ventas;
  int? _elegida;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final rango = _periodo.rango();
    final ventas = await historialDeVentas(widget.db, desde: rango.desde, hasta: rango.hasta, filtroMedio: _filtroMedio);
    if (!mounted) return;
    setState(() {
      _ventas = ventas;
      if (_elegida == null || !ventas.any((v) => v.ventaId == _elegida)) {
        _elegida = ventas.isEmpty ? null : ventas.first.ventaId;
      }
    });
  }

  void _elegirPeriodo(PeriodoHistorial p) {
    if (p == _periodo) return;
    setState(() {
      _periodo = p;
      _ventas = null;
    });
    _cargar();
  }

  void _elegirMedio(MedioVentaHistorial? m) {
    if (m == _filtroMedio) return;
    setState(() {
      _filtroMedio = m;
      _ventas = null;
    });
    _cargar();
  }

  /// Número de venta o producto: se filtra sobre lo ya cargado, sin volver
  /// a la base (el período ya acota la lista).
  List<VentaDelHistorial> get _visibles {
    final ventas = _ventas ?? const [];
    final q = widget.busqueda;
    if (q.isEmpty) return ventas;
    return ventas.where((v) => '${v.ventaId}' == q.replaceAll('#', '') || coincideBusqueda(v.detalle, q)).toList();
  }

  Future<void> _confirmarYAnular(VentaDelHistorial v) async {
    final motivoCtrl = TextEditingController();
    final motivo = await mostrarModal<String>(
      context,
      builder: (context) => Modal(
        titulo: '¿Anular la venta de ${formatearARS(v.totalCentavos)}?',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Se repone el stock y se revierte la caja. La venta sigue viéndose acá, marcada como anulada.'),
            const SizedBox(height: Espaciado.md),
            CampoTexto(etiqueta: 'Motivo', controller: motivoCtrl, autofocus: true),
          ],
        ),
        botones: [
          BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
          BotonPrimario(texto: 'Anular', onPressed: () => Navigator.of(context).pop(motivoCtrl.text.trim())),
        ],
      ),
    );
    motivoCtrl.dispose();
    if (motivo == null || motivo.isEmpty) return;
    try {
      await anularVenta(widget.db, ventaId: v.ventaId, usuarioId: widget.usuarioId, motivo: motivo);
      _cargar();
    } on ArgumentError catch (e) {
      // "sesión ya cerrada" / "ya está anulada" — un límite de negocio, no
      // un bug.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message.toString())));
      }
    }
  }

  Future<void> _editar(VentaDelHistorial v) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PantallaEditorVenta(db: widget.db, ventaId: v.ventaId, usuarioId: widget.usuarioId)),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final ventas = _ventas;
    final visibles = _visibles;
    final elegida = visibles.where((v) => v.ventaId == _elegida).firstOrNull ?? visibles.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Espaciado.md,
          runSpacing: Espaciado.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GrupoPildoras<PeriodoHistorial>(
              opciones: [for (final p in PeriodoHistorial.values) (p, p.etiqueta)],
              elegida: _periodo,
              onElegir: _elegirPeriodo,
            ),
            GrupoPildoras<MedioVentaHistorial?>(
              opciones: [(null, 'Todos'), for (final m in MedioVentaHistorial.values) (m, m.etiqueta)],
              elegida: _filtroMedio,
              onElegir: _elegirMedio,
            ),
          ],
        ),
        const SizedBox(height: Espaciado.lg),
        Expanded(
          child: ventas == null
              ? const EsqueletoLista()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _ListaVentas(ventas: visibles, elegida: elegida?.ventaId, alElegir: (id) => setState(() => _elegida = id))),
                    const SizedBox(width: Espaciado.lg),
                    Expanded(
                      flex: 2,
                      child: elegida == null
                          ? Superficie(child: Center(child: Text('Elegí una venta para ver su detalle', style: Theme.of(context).textTheme.bodySmall)))
                          : _DetalleVenta(
                              key: ValueKey(elegida.ventaId),
                              db: widget.db,
                              venta: elegida,
                              alAnular: () => _confirmarYAnular(elegida),
                              alEditar: () => _editar(elegida),
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ListaVentas extends StatelessWidget {
  const _ListaVentas({required this.ventas, required this.elegida, required this.alElegir});

  final List<VentaDelHistorial> ventas;
  final int? elegida;
  final void Function(int) alElegir;

  @override
  Widget build(BuildContext context) {
    // Una venta anulada no suma: su plata ya se revirtió de la caja.
    final validas = ventas.where((v) => !v.anulada).toList();
    final total = validas.fold(0, (a, v) => a + v.totalCentavos);

    // Filas planas: encabezado de día + ventas de ese día (vienen de más
    // nueva a más vieja).
    final filas = <Object>[];
    DateTime? diaActual;
    for (final v in ventas) {
      final dia = DateTime(v.fecha.year, v.fecha.month, v.fecha.day);
      if (dia != diaActual) {
        diaActual = dia;
        filas.add(dia);
      }
      filas.add(v);
    }

    return Superficie(
      padding: const EdgeInsets.all(Espaciado.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: CajaCifra(etiqueta: 'Vendido', valor: formatearARS(total))),
              const SizedBox(width: Espaciado.md),
              Expanded(child: CajaCifra(etiqueta: 'Ventas', valor: '${validas.length}')),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: CajaCifra(etiqueta: 'Promedio', valor: validas.isEmpty ? '—' : formatearARS(total ~/ validas.length)),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          Expanded(
            child: ventas.isEmpty
                ? Center(child: Text('Sin ventas en este período', style: Theme.of(context).textTheme.bodySmall))
                : ListView.builder(
                    itemCount: filas.length,
                    itemBuilder: (context, i) => entradaEnLista(i, Builder(builder: (context) {
                      final f = filas[i];
                      if (f is DateTime) {
                        final delDia = ventas.where((v) => !v.anulada && DateUtils.isSameDay(v.fecha, f)).fold(0, (a, v) => a + v.totalCentavos);
                        return _EncabezadoDia(fecha: f, total: delDia);
                      }
                      final v = f as VentaDelHistorial;
                      return _FilaVenta(venta: v, elegida: v.ventaId == elegida, onTap: () => alElegir(v.ventaId));
                    })),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EncabezadoDia extends StatelessWidget {
  const _EncabezadoDia({required this.fecha, required this.total});

  final DateTime fecha;
  final int total;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: Pesos.fuerte);
    final dia = fechaLarga(fecha);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.sm, Espaciado.md, Espaciado.sm, Espaciado.xs),
      child: Row(
        children: [
          Expanded(child: Text(dia[0].toUpperCase() + dia.substring(1), style: estilo)),
          Text(formatearARS(total), style: estilo?.tabular),
        ],
      ),
    );
  }
}

class _FilaVenta extends StatelessWidget {
  const _FilaVenta({required this.venta, required this.elegida, required this.onTap});

  final VentaDelHistorial venta;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inv = coloresDeFila(context, elegida);
    final colores = inv.colores;
    final textTheme = inv.textTheme;
    final v = venta;
    final apagado = v.anulada ? colores.textoTenue : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Espaciado.sm),
      child: Presionable(
      radio: 26,
      onTap: onTap,
      color: elegida ? colores.acento : colores.fondo,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
        child: Row(
          children: [
            SizedBox(width: 48, child: Text(horaCorta(v.fecha), style: textTheme.bodySmall?.tabular)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Venta ${v.etiqueta}', style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte, color: apagado)),
                  Text(v.detalle, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
                ],
              ),
            ),
            if (v.anulada) ...[const SizedBox(width: Espaciado.sm), const Insignia(texto: 'Anulada', tono: Tono.error)],
            const SizedBox(width: Espaciado.sm),
            PuntoColor(color: v.medio.color(context), tamanio: 8),
            const SizedBox(width: Espaciado.xs),
            SizedBox(width: 56, child: Text(v.medio.etiqueta, style: textTheme.bodySmall)),
            SizedBox(
              width: 96,
              child: Text(
                formatearARS(v.totalCentavos),
                textAlign: TextAlign.right,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: Pesos.fuerte,
                  color: apagado,
                  decoration: v.anulada ? TextDecoration.lineThrough : null,
                ).tabular,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _DetalleVenta extends StatefulWidget {
  const _DetalleVenta({super.key, required this.db, required this.venta, required this.alAnular, required this.alEditar});

  final AppDatabase db;
  final VentaDelHistorial venta;
  final VoidCallback alAnular;
  final VoidCallback alEditar;

  @override
  State<_DetalleVenta> createState() => _DetalleVentaState();
}

class _DetalleVentaState extends State<_DetalleVenta> {
  List<FilaLineaVenta>? _lineas;
  FilaVenta? _fila;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final db = widget.db;
    final lineas = await lineasDeVenta(db, widget.venta.ventaId);
    final fila = await (db.select(db.ventas)..where((v) => v.id.equals(widget.venta.ventaId))).getSingle();
    if (mounted) {
      setState(() {
        _lineas = lineas;
        _fila = fila;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lineas = _lineas;
    final fila = _fila;
    final v = widget.venta;
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    if (lineas == null || fila == null) return const Superficie(child: SizedBox.expand());

    final ganancia = calcularGananciaBruta(lineas: lineas.map((l) => lineaParaReposicionDesde(l, venta: fila)).toList());
    final articulos = lineas.fold(0, (a, l) => a + (l.esPesable ? 1 : (l.cantidad ?? 1)));

    Widget ajuste(String etiqueta, int monto) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Expanded(child: Text(etiqueta, style: textTheme.bodySmall)),
              Text(formatearARS(monto), style: textTheme.bodySmall?.tabular),
            ],
          ),
        );

    return Superficie(
      padding: const EdgeInsets.all(Espaciado.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Venta ${v.etiqueta}', style: textTheme.titleLarge),
                    Text(
                      '${fechaLarga(v.fecha)} · ${horaCorta(v.fecha)} · $articulos artículo${articulos == 1 ? '' : 's'}${fila.editadaEn != null ? ' · editada' : ''}',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (v.anulada) ...[const Insignia(texto: 'Venta anulada', tono: Tono.error), const SizedBox(width: Espaciado.sm)],
              FilaMedioCompacta(color: v.medio.color(context), etiqueta: v.medio.etiqueta),
            ],
          ),
          const SizedBox(height: Espaciado.lg),
          Expanded(
            child: ListView.separated(
              itemCount: lineas.length,
              separatorBuilder: (_, _) => Divider(height: Espaciado.md, color: colores.fondo),
              itemBuilder: (context, i) {
                final l = lineas[i];
                final sub = lineaParaReposicionDesde(l).precioLineaCentavos;
                return Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(l.esPesable ? '${l.gramos} g' : '${l.cantidad ?? 1} ×', style: textTheme.bodySmall?.tabular),
                    ),
                    Expanded(child: Text(l.nombreProductoFoto, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    SizedBox(
                      width: 96,
                      child: Text(
                        '${formatearARS(l.precioUnitarioCentavos)}${l.esPesable ? '/kg' : ''}',
                        textAlign: TextAlign.right,
                        style: textTheme.bodySmall?.tabular,
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(formatearARS(sub), textAlign: TextAlign.right, style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte).tabular),
                    ),
                  ],
                );
              },
            ),
          ),
          if (fila.recargoCigarrillosCentavos != 0) ajuste('Recargo de cigarrillos', fila.recargoCigarrillosCentavos),
          if (fila.descuentoCentavos != 0) ajuste('Descuento', -fila.descuentoCentavos),
          if (fila.redondeoCentavos != 0) ajuste('Redondeo', fila.redondeoCentavos),
          const SizedBox(height: Espaciado.md),
          Row(
            children: [
              Expanded(child: TarjetaIndicador(etiqueta: 'Total', valor: formatearARS(v.totalCentavos), destacada: true)),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: CajaCifra(
                  etiqueta: ganancia.vendidoSinCostoCentavos > 0 ? 'Ganancia (hay productos sin costo)' : 'Ganancia de la venta',
                  valor: formatearARS(ganancia.gananciaBrutaCentavos),
                  tono: Tono.ganancia,
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.lg),
          Row(
            children: [
              if (!v.anulada && v.sesionAbierta) BotonSecundario(texto: 'Anular venta', onPressed: widget.alAnular),
              const Spacer(),
              if (!v.anulada) ...[BotonSecundario(texto: 'Editar', onPressed: widget.alEditar), const SizedBox(width: Espaciado.sm)],
              BotonSecundario(
                texto: 'Reimprimir',
                onPressed: () => mostrarDialogoImprimirTicket(context, db: widget.db, ventaId: v.ventaId),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
