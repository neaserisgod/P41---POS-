// Tablero del día en el Inicio del celular ("Lenguaje de diseño", el dueño
// 2026-09-26, mock `MovilDashboard.dc.html`): los mismos datos que el Inicio
// de la PC (`tableroDelDia`, Regla 3), leídos de la base local — que se
// sincroniza sola con la PC — en una columna: cuatro indicadores en 2×2, la
// tarjeta oscura de "Falta separar" que lleva a Separaciones, ventas por
// hora, cómo te pagaron, más vendidos, stock bajo y fiados/encargues (en el
// lugar de "Reparaciones" del mock, que no es de este negocio).

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repositorio_tablero.dart';
import '../domain/dinero.dart';
import '../ui/comun/fechas.dart';
import '../ui/comun/grafico_por_hora.dart';
import '../ui/comun/tarjetas.dart';
import 'tema/piezas_companion.dart';
import '../ui/tema/acentos.dart';
import '../ui/tema/iconos.dart';
import '../ui/tema/tokens.dart';
import 'cambios_companion.dart';

class TableroCompanion extends StatefulWidget {
  const TableroCompanion({super.key, required this.db, required this.alTocarSeparar});

  final AppDatabase db;
  final VoidCallback alTocarSeparar;

  @override
  State<TableroCompanion> createState() => TableroCompanionState();
}

class TableroCompanionState extends State<TableroCompanion> {
  TableroDelDia? _tablero;
  StreamSubscription<void>? _avisos;

  @override
  void initState() {
    super.initState();
    recargar();
    // Llegó algo nuevo (por wifi o Supabase): se relee solo.
    _avisos = avisosCambiosCompanion.listen((_) => recargar());
  }

  @override
  void dispose() {
    _avisos?.cancel();
    super.dispose();
  }

  /// Público: el Inicio lo llama al tirar para actualizar y al volver de
  /// otra pantalla.
  Future<void> recargar() async {
    final t = await tableroDelDia(widget.db);
    if (mounted) setState(() => _tablero = t);
  }

  @override
  Widget build(BuildContext context) {
    final t = _tablero;
    if (t == null) return const SizedBox.shrink();
    final acentos = context.acentosPlazoleta;
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final hoy = DateTime.now();
    final total = t.efectivoCentavos + t.mpCentavos;
    String pct(int v) => total == 0 ? '' : ' · ${(v * 100 / total).round()}%';
    final margen = t.margen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EtiquetaSeccion('Hoy · ${fechaLarga(hoy)} · ${horaCorta(hoy)}'),
        const SizedBox(height: Espaciado.lg),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatearARS(t.vendidoCentavos),
            maxLines: 1,
            style: textTheme.displayLarge?.copyWith(color: colores.textoPrimario).tabular,
          ),
        ),
        Text('Vendido', style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario)),
        const SizedBox(height: Espaciado.xl),
        FilaCifras(
          cifras: [
            CifraGrande(
              etiqueta: 'Ganancia',
              valor: formatearARS(t.gananciaCentavos),
              tono: Tono.ganancia,
              nota: margen == null ? null : '${(margen * 100).round()}%',
            ),
            CifraGrande(etiqueta: 'Tickets', valor: '${t.tickets}'),
            CifraGrande(
              etiqueta: 'Ticket prom.',
              valor: t.tickets == 0 ? '—' : formatearARS(t.vendidoCentavos ~/ t.tickets),
            ),
          ],
        ),
        const SizedBox(height: Espaciado.xl),
        BloqueHero(
          onTap: widget.alTocarSeparar,
          minAlto: 148,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.proveedoresConAlgoQueSeparar == 0
                          ? 'Falta separar'
                          : 'Falta separar · ${t.proveedoresPendientes} de ${t.proveedoresConAlgoQueSeparar}',
                      style: textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.72)),
                    ),
                    const SizedBox(height: Espaciado.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatearARS(t.faltaSepararCentavos),
                        maxLines: 1,
                        style: textTheme.headlineLarge?.copyWith(color: Colors.white).tabular,
                      ),
                    ),
                    if (t.proveedoresConAlgoQueSeparar > 0 && t.proveedoresPendientes == 0)
                      Text('Todo separado', style: textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.72))),
                  ],
                ),
              ),
              const SizedBox(width: Espaciado.lg),
              const BotonFlecha(),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.md),
        SeccionCompanion(titulo: 'Ventas por hora', child: GraficoPorHora(porHora: t.porHora, altura: 140)),
        const SizedBox(height: Espaciado.md),
        SeccionCompanion(
          titulo: 'Cómo te pagaron',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BarraDividida(tramos: [(color: acentos.dinero, valor: t.efectivoCentavos), (color: acentos.qr, valor: t.mpCentavos)]),
              const SizedBox(height: Espaciado.md),
              FilaMedio(color: acentos.dinero, etiqueta: 'Efectivo${pct(t.efectivoCentavos)}', monto: formatearARS(t.efectivoCentavos)),
              const SizedBox(height: Espaciado.sm),
              FilaMedio(color: acentos.qr, etiqueta: 'Mercado Pago${pct(t.mpCentavos)}', monto: formatearARS(t.mpCentavos)),
            ],
          ),
        ),
        if (t.masVendidos.isNotEmpty) ...[
          const SizedBox(height: Espaciado.md),
          SeccionCompanion(
            titulo: 'Más vendidos hoy',
            child: Column(
              children: [
                for (final p in t.masVendidos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espaciado.md),
                    child: FilaRanking(
                      nombre: p.nombre,
                      valor: p.esPesable ? '${p.gramos} g' : '${p.cantidad} u.',
                      proporcion: p.vendidoCentavos / t.masVendidos.first.vendidoCentavos,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (t.stockBajo.isNotEmpty) ...[
          const SizedBox(height: Espaciado.md),
          SeccionCompanion(
            titulo: 'Stock bajo',
            derecha: Insignia(texto: '${t.stockBajo.length}', tono: Tono.alerta),
            child: Column(
              children: [
                for (final p in t.stockBajo.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espaciado.sm),
                    child: FilaSuave(
                      titulo: p.nombre,
                      subtitulo: p.proveedor ?? 'Sin proveedor',
                      icono: IconosPlazoleta.inventory2Outlined,
                      derecha: Text(
                        p.stock <= 0 ? 'Sin stock' : 'Quedan ${p.stock}${p.esPesable ? ' g' : ''}',
                        style: textTheme.bodySmall?.copyWith(
                          color: p.stock <= 0 ? colores.error : acentos.alerta,
                          fontWeight: Pesos.fuerte,
                        ),
                      ),
                    ),
                  ),
                if (t.stockBajo.length > 8)
                  Text('y ${t.stockBajo.length - 8} más', style: textTheme.bodySmall),
              ],
            ),
          ),
        ],
        if (t.pendientes.isNotEmpty) ...[
          const SizedBox(height: Espaciado.md),
          SeccionCompanion(
            titulo: 'Encargues y deudas',
            child: Column(
              children: [
                for (final p in t.pendientes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espaciado.sm),
                    child: FilaSuave(
                      titulo: p.quien,
                      subtitulo: [p.esFiado ? 'Deuda' : 'Encargue', ?p.detalle].join(' · '),
                      derecha: p.montoCentavos == null
                          ? null
                          : Text(formatearARS(p.montoCentavos!), style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte).tabular),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
