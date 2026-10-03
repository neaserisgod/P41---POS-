// Revisa los cierres de caja de una base real (El dueño, 2026-09-28: "¿el
// cierre de caja toma y pone los datos correctamente?"). No escribe nada:
// abre una COPIA de la base y, por cada sesión cerrada, compara:
//
// 1. Lo guardado al cerrar contra el mismo cálculo corrido de nuevo hoy
//    (`calcularResumenCierre`) — si difieren, algo cambió después del
//    cierre (una venta editada/anulada, un movimiento sincronizado tarde).
// 2. La cadena de la lata: la lata inicial de cada sesión tiene que ser la
//    final de la anterior (Regla 6).
// 3. Una cuenta independiente, hecha acá con SQL directo, de lo que entró y
//    salió en efectivo y por Mercado Pago — no usa las funciones de la app,
//    así un error en ellas no se esconde detrás de sí mismo.
// 4. Que cada venta no anulada tenga pagos que sumen su total.
//
// Uso (desde la raíz del repo, con la copia ya hecha):
//   $env:BASE_A_REVISAR="C:\ruta\copia.sqlite"; flutter test tool/revisar_cierres_test.dart
// Corre como test para tener el mismo entorno de sqlite que la suite.

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/domain/dinero.dart';

void main() {
  test('revisar cierres', () async {
    final ruta = Platform.environment['BASE_A_REVISAR'];
    if (ruta == null) {
      markTestSkipped('Falta BASE_A_REVISAR');
      return;
    }
    final db = AppDatabase(NativeDatabase(File(ruta)));
    addTearDown(db.close);
    String p(int? c) => c == null ? '—' : formatearARS(c);
    final problemas = <String>[];

    final sesiones = await (db.select(db.sesionesDeCaja)..orderBy([(s) => OrderingTerm.asc(s.fechaApertura)])).get();
    SesionCaja? anterior;
    for (final s in sesiones) {
      final etiqueta = '#${s.id} ${s.fechaApertura.toString().substring(0, 16)}';

      if (anterior != null && anterior.estado == 'CERRADA' && anterior.lataFinalCentavos != null &&
          s.lataInicialCentavos != anterior.lataFinalCentavos) {
        problemas.add('$etiqueta: lata inicial ${p(s.lataInicialCentavos)} ≠ lata final de #${anterior.id} ${p(anterior.lataFinalCentavos)}');
      }
      anterior = s;
      if (s.estado != 'CERRADA') continue;

      // 1. guardado vs recalculado
      final r = await calcularResumenCierre(
        db,
        sesionId: s.id,
        efectivoContadoCentavos: s.efectivoContadoCentavos ?? 0,
        mpContadoCentavos: s.mpContadoCentavos,
        lataContadoCentavos: s.lataContadoCentavos,
      );
      void comparar(String que, int? guardado, int? ahora) {
        if (guardado != ahora) problemas.add('$etiqueta: $que guardado ${p(guardado)}, recalculado ${p(ahora)}');
      }

      comparar('efectivo esperado', s.efectivoEsperadoCentavos, r.efectivoEsperadoCentavos);
      comparar('diferencia efectivo', s.diferenciaCentavos, r.diferenciaCentavos);
      comparar('MP esperado', s.mpEsperadoCentavos, r.mpEsperadoCentavos);
      comparar('lata final', s.lataFinalCentavos, r.lataFinalCentavos);

      // 3. cuenta independiente
      Future<int> sql(String q) async =>
          (await db.customSelect(q, variables: [Variable.withInt(s.id)]).getSingle()).read<int?>('t') ?? 0;
      final ventasEf = await sql('''select sum(p.monto_centavos) t from pagos p join ventas v on v.id=p.venta_id
          join medios_de_pago m on m.id=p.medio_pago_id where v.sesion_caja_id=? and v.anulada_en is null and m.es_efectivo=1''');
      final ventasMp = await sql('''select sum(p.monto_centavos) t from pagos p join ventas v on v.id=p.venta_id
          join medios_de_pago m on m.id=p.medio_pago_id where v.sesion_caja_id=? and v.anulada_en is null and m.es_efectivo=0''');
      String movs(String tipos, String donde) =>
          '''select sum(mc.monto_centavos) t from movimientos_de_caja mc join cajas c on c.id=mc.caja_id
          left join medios_de_pago m on m.id=mc.medio_pago_id where mc.sesion_caja_id=? and mc.tipo in ($tipos) and $donde''';
      const egresos = "'GASTO','PAGO_PROVEEDOR','RETIRO'";
      final salidasCajon = await sql(movs(egresos, 'c.es_lata=0 and (m.es_efectivo is null or m.es_efectivo=1)'));
      final entradasCajon = await sql(movs("'INGRESO'", 'c.es_lata=0 and (m.es_efectivo is null or m.es_efectivo=1)'));
      final salidasMp = await sql(movs(egresos, 'm.es_efectivo=0'));
      final entradasMp = await sql(movs("'INGRESO'", 'm.es_efectivo=0'));

      final d = r.desgloseEfectivo;
      if (d != null) {
        if (d.ventas != ventasEf) problemas.add('$etiqueta: ventas en efectivo según el cierre ${p(d.ventas)}, según los pagos ${p(ventasEf)}');
        if (d.gastos != salidasCajon) problemas.add('$etiqueta: salidas del cajón según el cierre ${p(d.gastos)}, según los movimientos ${p(salidasCajon)}');
        if (d.ingresos != entradasCajon) problemas.add('$etiqueta: ingresos al cajón según el cierre ${p(d.ingresos)}, según los movimientos ${p(entradasCajon)}');
      }
      final mpIndependiente = s.saldoMpInicialCentavos + ventasMp - salidasMp + entradasMp;
      stdout.writeln('$etiqueta  ef esperado ${p(r.efectivoEsperadoCentavos)} contado ${p(s.efectivoContadoCentavos)} dif ${p(r.diferenciaCentavos)}'
          ' | MP esperado ${p(r.mpEsperadoCentavos)} (cuenta aparte ${p(mpIndependiente)}) contado ${p(s.mpContadoCentavos)}'
          ' | lata final ${p(r.lataFinalCentavos)} contada ${p(s.lataContadoCentavos)}');
      if (mpIndependiente != r.mpEsperadoCentavos) {
        problemas.add('$etiqueta: MP esperado ${p(r.mpEsperadoCentavos)}, cuenta aparte ${p(mpIndependiente)}');
      }
    }

    // 4. pagos que no suman el total de la venta
    final descuadradas = await db.customSelect('''select v.id, v.total_centavos t, coalesce(sum(p.monto_centavos),0) pagado
        from ventas v left join pagos p on p.venta_id=v.id where v.anulada_en is null
        group by v.id having pagado != v.total_centavos''').get();
    for (final f in descuadradas) {
      problemas.add('venta #${f.read<int>('id')}: total ${p(f.read<int>('t'))}, pagos ${p(f.read<int>('pagado'))}');
    }

    stdout.writeln('\n${problemas.isEmpty ? 'Sin problemas.' : '${problemas.length} problemas:'}');
    for (final x in problemas) {
      stdout.writeln('- $x');
    }
  });
}
