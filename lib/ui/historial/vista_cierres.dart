// Cierres de caja — pestaña de Historial ("Lenguaje de diseño", el dueño
// 2026-09-26, mock `HistorialCierres.dc.html`): la lista de cierres a la
// izquierda (día, lo vendido, a qué hora cerró y si cuadró) y el cierre
// elegido a la derecha, con la cuenta del efectivo a la vista (fondo +
// ventas en efectivo − lo que se fue a la lata − gastos/pagos/retiros =
// lo que debería haber, contra lo contado) y Mercado Pago y la lata al
// costado. Las ventas del día, su edición y el PDF siguen en
// `PantallaDetalleDia` ("Ver las ventas de ese día").

import 'package:flutter/material.dart';

import '../../data/repositorio_historial.dart';
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/estado_vacio.dart';
import '../comun/fechas.dart';
import '../comun/tarjetas.dart';
import '../navegacion/busqueda_contextual.dart' show coincideBusqueda;
import '../tema/acentos.dart';
import '../tema/tema_inverso.dart';
import '../tema/presionable.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import '../tema/movimiento.dart';

class VistaCierres extends StatefulWidget {
  const VistaCierres({super.key, required List<ResumenDia> dias, required this.alAbrirDia, this.busqueda = ''})
      : _todos = dias;

  final List<ResumenDia> _todos;

  /// Buscador de arriba (contextual, 2026-09-28): día ("sábado", "26",
  /// "septiembre") o empleado.
  final String busqueda;

  List<ResumenDia> get dias => [
    for (final d in _todos)
      if (coincideBusqueda('${fechaLarga(d.sesion.fechaApertura)} ${d.sesion.fechaApertura.day}/${d.sesion.fechaApertura.month} ${d.nombreEmpleado}', busqueda)) d,
  ];

  /// Abre `PantallaDetalleDia` (ventas del día, editar, PDF).
  final void Function(int sesionId) alAbrirDia;

  @override
  State<VistaCierres> createState() => _VistaCierresState();
}

class _VistaCierresState extends State<VistaCierres> {
  int _elegido = 0;

  @override
  Widget build(BuildContext context) {
    final dias = widget.dias;
    if (dias.isEmpty) {
      return EstadoVacio(
        mensaje: widget.busqueda.isEmpty ? 'Todavía no hay ningún día cerrado.' : 'Ningún cierre coincide con "${widget.busqueda}"',
      );
    }
    final elegido = _elegido.clamp(0, dias.length - 1);
    final cuadraron = dias.where((d) => d.diferenciaCentavos == 0).length;
    final neta = dias.fold(0, (a, d) => a + d.diferenciaCentavos);
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: Superficie(
            padding: const EdgeInsets.all(Espaciado.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${dias.length} cierre${dias.length == 1 ? '' : 's'}', style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte)),
                          Text('$cuadraron cuadraron · ${dias.length - cuadraron} con diferencia', style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Diferencia neta', style: textTheme.bodySmall),
                        Text(formatearARS(neta), style: textTheme.titleMedium?.copyWith(color: _colorDiferencia(context, neta), fontWeight: Pesos.fuerte).tabular),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: Espaciado.md),
                Expanded(
                  child: ListView.separated(
                    itemCount: dias.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Espaciado.xs),
                    itemBuilder: (context, i) => entradaEnLista(i, _FilaCierre(
                      dia: dias[i],
                      elegida: i == elegido,
                      onTap: () => setState(() => _elegido = i),
                    )),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: Espaciado.lg),
        Expanded(flex: 3, child: _DetalleCierre(dia: dias[elegido], alAbrirDia: widget.alAbrirDia)),
      ],
    );
  }
}

/// Cualquier diferencia distinta de cero es un descuadre, sobre o falte
/// (Regla 10): faltante en rojo, sobrante en el tono de aviso, cero en verde.
Color _colorDiferencia(BuildContext context, int diferencia) {
  if (diferencia == 0) return context.acentosPlazoleta.ganancia;
  return diferencia < 0 ? context.colores.error : context.acentosPlazoleta.alerta;
}

String _estado(int diferencia) =>
    diferencia == 0 ? 'Cuadró' : '${diferencia > 0 ? 'Sobraron' : 'Faltaron'} ${formatearARS(diferencia.abs())}';

class _FilaCierre extends StatelessWidget {
  const _FilaCierre({required this.dia, required this.elegida, required this.onTap});

  final ResumenDia dia;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inv = coloresDeFila(context, elegida);
    final colores = inv.colores;
    final textTheme = inv.textTheme;
    final apertura = dia.sesion.fechaApertura;
    final cierre = dia.sesion.fechaCierre;
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
            _ChipDia(fecha: apertura),
            const SizedBox(width: Espaciado.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatearARS(dia.totalVendidoCentavos), style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte).tabular),
                  // Hora y empleado, no solo la fecha (El dueño, 31/08/2026): un
                  // turno es una sesión completa, puede haber más de una el
                  // mismo día.
                  Text(
                    '${horaCorta(apertura)}${cierre == null ? '' : ' a ${horaCorta(cierre)}'} · ${dia.nombreEmpleado}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Espaciado.sm),
            Text(
              _estado(dia.diferenciaCentavos),
              key: const Key('estado_cierre'),
              style: textTheme.bodySmall?.copyWith(color: _colorDiferencia(context, dia.diferenciaCentavos), fontWeight: Pesos.fuerte),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _ChipDia extends StatelessWidget {
  const _ChipDia({required this.fecha});

  final DateTime fecha;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(diasSemana[fecha.weekday - 1].substring(0, 3), style: textTheme.labelSmall?.copyWith(color: colores.textoSecundario)),
          Text('${fecha.day}', style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte, height: 1.1)),
        ],
      ),
    );
  }
}

class _DetalleCierre extends StatelessWidget {
  const _DetalleCierre({required this.dia, required this.alAbrirDia});

  final ResumenDia dia;
  final void Function(int sesionId) alAbrirDia;

  @override
  Widget build(BuildContext context) {
    final s = dia.sesion;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final esperado = s.efectivoEsperadoCentavos ?? 0;
    final lata = s.lataSeparadoCentavos ?? 0;
    // Lo que no es fondo, ventas en efectivo ni lata: gastos, pagos a
    // proveedores, retiros e ingresos del turno — la diferencia que
    // completa la cuenta hasta lo esperado que calculó el cierre.
    final otros = esperado - (s.fondoInicialCentavos + dia.efectivoCentavos - lata);

    Widget fila(String etiqueta, int monto, {bool fuerte = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(etiqueta, style: fuerte ? textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte) : textTheme.bodyMedium)),
              Text(
                formatearARS(monto),
                style: (fuerte ? textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte) : textTheme.bodyMedium)?.copyWith(color: color).tabular,
              ),
            ],
          ),
        );

    return Superficie(
      padding: const EdgeInsets.all(Espaciado.xl),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cierre del ${fechaLarga(s.fechaApertura)}', style: textTheme.titleLarge),
                      Text(
                        'Abrió ${horaCorta(s.fechaApertura)}${s.fechaCierre == null ? '' : ' · cerró ${horaCorta(s.fechaCierre!)}'} · ${dia.nombreEmpleado}',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Insignia(
                  texto: _estado(dia.diferenciaCentavos),
                  tono: dia.diferenciaCentavos == 0 ? Tono.ganancia : (dia.diferenciaCentavos < 0 ? Tono.error : Tono.alerta),
                ),
              ],
            ),
            const SizedBox(height: Espaciado.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TarjetaSeccion(
                    titulo: 'Efectivo en el cajón',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        fila('Fondo para el vuelto', s.fondoInicialCentavos),
                        fila('+ Ventas en efectivo', dia.efectivoCentavos),
                        if (lata != 0) fila('− A la lata (cigarrillos)', -lata),
                        if (otros != 0) fila('± Gastos, pagos y retiros', otros),
                        const Divider(),
                        fila('= Debería haber', esperado, fuerte: true),
                        fila('Contado al cerrar', s.efectivoContadoCentavos ?? 0),
                        const Divider(),
                        fila('Diferencia', dia.diferenciaCentavos, fuerte: true, color: _colorDiferencia(context, dia.diferenciaCentavos)),
                        if ((s.nota ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: Espaciado.sm),
                          Text('Nota del cierre: “${s.nota!.trim()}”', style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Espaciado.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TarjetaIndicador(etiqueta: 'Vendido en el turno', valor: formatearARS(dia.totalVendidoCentavos), destacada: true),
                      const SizedBox(height: Espaciado.md),
                      FilaMedio(color: acentos.dinero, etiqueta: 'Efectivo', monto: formatearARS(dia.efectivoCentavos)),
                      const SizedBox(height: Espaciado.sm),
                      FilaMedio(color: acentos.qr, etiqueta: 'Mercado Pago', monto: formatearARS(dia.mpCentavos)),
                      if ((s.mpContadoCentavos ?? 0) > 0) ...[
                        const SizedBox(height: Espaciado.xs),
                        Text(
                          'MP contado ${formatearARS(s.mpContadoCentavos!)} · diferencia ${formatearARS(s.mpDiferenciaCentavos ?? 0)}',
                          style: textTheme.bodySmall,
                        ),
                      ] else if ((s.mpEsperadoCentavos ?? 0) > 0) ...[
                        const SizedBox(height: Espaciado.xs),
                        Text('El saldo de Mercado Pago no se contó en este cierre', style: textTheme.bodySmall?.copyWith(color: acentos.alerta)),
                      ],
                      if (dia.cigarrillosCentavos > 0) ...[
                        const SizedBox(height: Espaciado.sm),
                        FilaMedio(color: context.colores.textoSecundario, etiqueta: 'Cigarrillos (a la lata)', monto: formatearARS(dia.cigarrillosCentavos)),
                      ],
                      const SizedBox(height: Espaciado.lg),
                      BotonSecundario(texto: 'Ver las ventas de ese día', onPressed: () => alAbrirDia(s.id)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
