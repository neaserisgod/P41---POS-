import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/proveedores/dialogo_cuenta_corriente.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

import '../../capturas/capturador.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late Proveedor proveedor;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 5000000);
    final id = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'ZM', nombre: 'Fiambrería'));
    proveedor = await (db.select(db.proveedores)..where((p) => p.id.equals(id))).getSingle();
  });
  tearDown(() => db.close());

  Future<GlobalKey> abrir(WidgetTester tester) async {
    final llave = await montarPantallaParaCaptura(
      tester,
      pantalla: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => mostrarDialogoCuentaCorriente(
                context,
                db: db,
                proveedor: proveedor,
                usuarioId: usuarioId,
                sesionCajaId: sesionId,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
      tema: TemaPlazoleta.claro,
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return llave;
  }

  testWidgets('cargar una deuda y pagar una parte desde el cajón', (tester) async {
    final llave = await abrir(tester);
    expect(find.text('Sin deuda'), findsOneWidget);

    await tester.tap(find.text('Cargar deuda').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo_monto_deuda')), '30.000');
    await tester.enterText(find.byKey(const Key('campo_nota_deuda')), 'Remito 4471');
    await tester.tap(find.text('Cargar deuda').last);
    await tester.pumpAndSettle();

    expect(find.text('Le debés'), findsOneWidget);
    expect(find.text('Remito 4471'), findsOneWidget);
    expect(find.text(r'$30.000'), findsWidgets);

    await tester.tap(find.text('Pagar').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo_monto_pago_deuda')), '12.000');
    await tester.pumpAndSettle();
    expect(find.textContaining(r'seguís debiendo $18.000'), findsOneWidget);
    await tester.tap(find.text('Registrar pago'));
    await tester.pumpAndSettle();

    expect(await tester.runAsync(() => saldoDeuda(db, proveedor.id)), 1800000);
    await guardarCaptura(tester, llave, 'proveedores-cuenta-corriente');

    // Quedó registrado con dueño en la caja.
    final movs = await tester.runAsync(() => (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('PAGO_PROVEEDOR'))).get());
    expect(movs!.single.proveedorId, proveedor.id);
    expect(movs.single.montoCentavos, 1200000);
  });

  testWidgets('un pago mayor a la deuda se acepta: baja la deuda a cero y anota el resto', (tester) async {
    await db.transaction(() async {
      await cargarDeuda(db, proveedorId: proveedor.id, montoCentavos: 500000, fecha: DateTime(2026, 9, 20), usuarioId: usuarioId);
    });
    await abrir(tester);
    await tester.tap(find.text('Pagar').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo_monto_pago_deuda')), '6.000');
    await tester.tap(find.text('Registrar pago'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => saldoDeuda(db, proveedor.id)), 0);
  });
}
