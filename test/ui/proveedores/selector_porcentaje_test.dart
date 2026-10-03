import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/proveedores/lista_proveedores.dart';
import 'package:la_plazoleta/ui/proveedores/pantalla_proveedores.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

import '../../capturas/capturador.dart';
import '../../helpers/base_para_tests.dart';

/// Porcentaje de ganancia por proveedor (El dueño, 2026-09-29).
void main() {
  late AppDatabase db;
  late int usuarioId;
  late int proveedorId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    proveedorId = await (db.select(db.proveedores)..where((p) => p.codigo.equals('S'))).getSingle().then((p) => p.id);
    await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Yerba',
            proveedorId: Value(proveedorId),
            costoCentavos: const Value(103000),
            precioCentavos: const Value(140000),
            stock: const Value(5),
          ),
        );
    await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Marlboro',
            proveedorId: Value(proveedorId),
            tipoCigarrillo: const Value('atado'),
            costoCentavos: const Value(400000),
            precioCentavos: const Value(500000),
            stock: const Value(5),
          ),
        );
  });
  tearDown(() => db.close());

  testWidgets('elegir el porcentaje no cambia precios; "Aplicar" sí, y muestra qué cambia', (tester) async {
    final llave = await montarPantallaParaCaptura(
      tester,
      pantalla: PantallaProveedores(db: db, usuarioId: usuarioId, sesionCajaId: null),
      tema: TemaPlazoleta.claro,
    );
    final lista = find.byType(ListaProveedores);
    await tester.tap(find.descendant(of: lista, matching: find.text('Distribuidora')).first);
    await tester.pumpAndSettle();

    expect(find.text('Ganancia sobre el precio'), findsOneWidget);
    expect(find.text('Aplicar a los precios'), findsNothing);

    await tester.tap(find.text('30%'));
    await tester.pumpAndSettle();
    var yerba = await tester.runAsync(() => (db.select(db.productos)..where((p) => p.nombre.equals('Yerba'))).getSingle());
    expect(yerba!.precioCentavos, 140000, reason: 'elegir el % solo lo guarda');
    expect(find.text('Aplicar a los precios'), findsOneWidget);

    await tester.tap(find.text('Aplicar a los precios'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cambia el precio de 1 producto'), findsOneWidget);
    expect(find.text('Yerba'), findsWidgets);
    await guardarCaptura(tester, llave, 'proveedores-aplicar-porcentaje');

    await tester.tap(find.text('Aplicar').last);
    await tester.pumpAndSettle();

    yerba = await tester.runAsync(() => (db.select(db.productos)..where((p) => p.nombre.equals('Yerba'))).getSingle());
    expect(yerba!.precioCentavos, 150000); // $1.030 / 0,7 = $1.471,43 → $1.500
    final marlboro = await tester.runAsync(() => (db.select(db.productos)..where((p) => p.nombre.equals('Marlboro'))).getSingle());
    expect(marlboro!.precioCentavos, 500000, reason: 'los cigarros no se tocan');
  });

  testWidgets('Distribuidora de Cigarrillos (todo cigarros) no muestra el selector', (tester) async {
    await montarPantallaParaCaptura(
      tester,
      pantalla: PantallaProveedores(db: db, usuarioId: usuarioId, sesionCajaId: null),
      tema: TemaPlazoleta.claro,
    );
    await tester.tap(find.descendant(of: find.byType(ListaProveedores), matching: find.text('Distribuidora de Cigarrillos')));
    await tester.pumpAndSettle();
    expect(find.text('Ganancia sobre el precio'), findsNothing);
  });
}
