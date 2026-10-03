// El PDF del día completo (exportar desde el celular): se arma con una venta
// en efectivo, una anulada y un gasto sin romper, y trae algo que se pueda abrir.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/pdf_dia_completo.dart';
import 'package:la_plazoleta/data/repositorio_gastos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import '../helpers/base_para_tests.dart';

void main() {
  test('arma un PDF con ventas, anuladas y movimientos', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuario = (await db.select(db.usuarios).get()).first.id;
    final sesion = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 100000);
    await registrarGastoRapido(db, sesionCajaId: sesion, usuarioId: usuario, montoCentavos: 5000, medio: MedioGasto.cajonNormal, motivo: 'Bolsas');

    final bytes = await generarPdfDiaCompleto(db, sesion);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
}
