// Historial → Movimientos (El dueño, 2026-09-28: "revisá si hay un apartado
// para ver los movimientos, los movimientos de caja y eso" — no había).
// Gastos, ingresos, pagos a proveedores y retiros, uno por uno: cuándo, de
// qué caja, por qué medio, quién. Las ventas no, ya tienen su pestaña.
// Solo lectura: un movimiento de caja es un registro, no se edita.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_movimientos_caja.dart';
import '../../domain/dinero.dart';
import '../comun/estado_vacio.dart';
import '../comun/fechas.dart';
import '../comun/tarjetas.dart';
import '../navegacion/busqueda_contextual.dart' show coincideBusqueda;
import '../navegacion/refresco_por_celular.dart';
import '../tema/acentos.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import 'periodo_historial.dart';
import '../tema/esqueleto.dart';
import '../tema/movimiento.dart';

String etiquetaTipoMovimiento(String tipo) => switch (tipo) {
  'GASTO' => 'Gasto',
  'INGRESO' => 'Ingreso',
  'PAGO_PROVEEDOR' => 'Pago a proveedor',
  'RETIRO' => 'Retiro',
  _ => tipo,
};

class TabHistorialMovimientos extends StatefulWidget {
  const TabHistorialMovimientos({super.key, required this.db, this.busqueda = ''});

  final AppDatabase db;

  /// Buscador de arriba: motivo, proveedor o quién lo hizo.
  final String busqueda;

  @override
  State<TabHistorialMovimientos> createState() => _TabHistorialMovimientosState();
}

class _TabHistorialMovimientosState extends State<TabHistorialMovimientos> with RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _cargar();

  PeriodoHistorial _periodo = PeriodoHistorial.hoy;
  String? _tipo;
  List<MovimientoDeCaja>? _movimientos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final rango = _periodo.rango();
    final lista = await movimientosDeCaja(widget.db, desde: rango.desde, hasta: rango.hasta);
    if (mounted) setState(() => _movimientos = lista);
  }

  void _elegirPeriodo(PeriodoHistorial p) {
    if (p == _periodo) return;
    setState(() {
      _periodo = p;
      _movimientos = null;
    });
    _cargar();
  }

  List<MovimientoDeCaja> get _visibles => [
    for (final m in _movimientos ?? const <MovimientoDeCaja>[])
      if ((_tipo == null || m.tipo == _tipo) &&
          (widget.busqueda.isEmpty ||
              coincideBusqueda('${m.nota ?? ''} ${m.proveedor ?? ''} ${m.usuario} ${etiquetaTipoMovimiento(m.tipo)}', widget.busqueda)))
        m,
  ];

  @override
  Widget build(BuildContext context) {
    final lista = _movimientos;
    final visibles = _visibles;
    final salio = visibles.where((m) => m.esSalida).fold(0, (a, m) => a + m.montoCentavos);
    final entro = visibles.where((m) => !m.esSalida).fold(0, (a, m) => a + m.montoCentavos);
    final porMp = visibles.where((m) => m.esSalida && m.esMercadoPago).fold(0, (a, m) => a + m.montoCentavos);
    final deLata = visibles.where((m) => m.esSalida && m.esLata).fold(0, (a, m) => a + m.montoCentavos);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Espaciado.md,
          runSpacing: Espaciado.sm,
          children: [
            GrupoPildoras<PeriodoHistorial>(
              opciones: [for (final p in PeriodoHistorial.values) (p, p.etiqueta)],
              elegida: _periodo,
              onElegir: _elegirPeriodo,
            ),
            GrupoPildoras<String?>(
              opciones: [(null, 'Todos'), for (final t in tiposMovimientoVisible) (t, etiquetaTipoMovimiento(t))],
              elegida: _tipo,
              onElegir: (t) => setState(() => _tipo = t),
            ),
          ],
        ),
        const SizedBox(height: Espaciado.lg),
        SizedBox(
          height: 128,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TarjetaIndicador(
                  etiqueta: 'Salió',
                  valor: formatearARS(salio),
                  nota: 'Gastos, pagos y retiros',
                  destacada: true,
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: TarjetaIndicador(etiqueta: 'Entró', valor: formatearARS(entro), nota: 'Ingresos', tonoValor: entro > 0 ? Tono.ganancia : null),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(child: TarjetaIndicador(etiqueta: 'Salió por Mercado Pago', valor: formatearARS(porMp), nota: 'No sale del cajón')),
              const SizedBox(width: Espaciado.md),
              Expanded(child: TarjetaIndicador(etiqueta: 'Salió de la lata', valor: formatearARS(deLata), nota: 'Cigarrillos')),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.lg),
        Expanded(
          child: lista == null
              ? const EsqueletoLista()
              : visibles.isEmpty
              ? const EstadoVacio(mensaje: 'Sin movimientos en este período')
              : Superficie(padding: EdgeInsets.zero, child: _Lista(movimientos: visibles)),
        ),
      ],
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.movimientos});

  final List<MovimientoDeCaja> movimientos;

  @override
  Widget build(BuildContext context) {
    // Filas planas: encabezado de día + sus movimientos (vienen del más nuevo
    // al más viejo), para poder usar ListView.builder.
    final filas = <Object>[];
    DateTime? dia;
    for (final m in movimientos) {
      final d = DateTime(m.fecha.year, m.fecha.month, m.fecha.day);
      if (d != dia) {
        filas.add(d);
        dia = d;
      }
      filas.add(m);
    }
    final textTheme = Theme.of(context).textTheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
      itemCount: filas.length,
      itemBuilder: (context, i) => entradaEnLista(i, Builder(builder: (context) {
        final f = filas[i];
        if (f is DateTime) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.md, Espaciado.xl, Espaciado.xs),
            child: Text(fechaLarga(f), style: textTheme.labelLarge?.copyWith(color: context.colores.textoSecundario)),
          );
        }
        return _Fila(m: f as MovimientoDeCaja);
      })),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.m});

  final MovimientoDeCaja m;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final acentos = context.acentosPlazoleta;
    final colores = context.colores;
    final caja = m.esLata ? 'Lata' : 'Cajón';
    final medio = m.esMercadoPago ? 'Mercado Pago' : 'efectivo';
    final titulo = m.nota ?? (m.proveedor != null ? '${etiquetaTipoMovimiento(m.tipo)} · ${m.proveedor}' : etiquetaTipoMovimiento(m.tipo));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl, vertical: Espaciado.sm),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(horaCorta(m.fecha), style: textTheme.bodyMedium?.tabular)),
          SizedBox(
            width: 150,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Insignia(
                texto: etiquetaTipoMovimiento(m.tipo),
                tono: switch (m.tipo) {
                  'INGRESO' => Tono.ganancia,
                  'RETIRO' => Tono.acento,
                  'PAGO_PROVEEDOR' => Tono.neutro,
                  _ => Tono.alerta,
                },
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleSmall),
                Text('$caja · $medio · ${m.usuario}', style: textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            '${m.esSalida ? '−' : '+'} ${formatearARS(m.montoCentavos)}',
            style: textTheme.titleMedium?.copyWith(color: m.esSalida ? colores.textoPrimario : acentos.ganancia, fontWeight: Pesos.fuerte).tabular,
          ),
        ],
      ),
    );
  }
}
