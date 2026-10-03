// Conteo de stock del celular (mock completo, 2026-10-02): lo que no se puede
// romper es que un campo vacío NO toca el stock, que lo cargado se guarda como
// valor contado con su rastro ("Conteo físico") y que cambiar de proveedor o de
// filtro no hace perder lo ya cargado.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_conteo_stock.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/chip_seleccionable.dart';
import 'package:la_plazoleta/companion/tema/superficie.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

/// Las cargas hablan con una base real (drift): hace falta dejar correr el
/// reloj de verdad entre cuadros, no solo bombear los de test.
Future<void> _asentar(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  }
  await t.pump();
}

class _Escenario {
  _Escenario(this.db, this.puerto, this.proveedores);
  final AppDatabase db;
  final PuertoLocal puerto;
  final List<int> proveedores;
}

Future<_Escenario> _preparar(WidgetTester t) async {
  tester(t);
  SharedPreferences.setMockInitialValues({'companion_usuario_id': 1, 'companion_usuario_nombre': 'Dueño'});
  final db = (await t.runAsync(() async => baseDeTest()))!;
  usarBaseLocalDeTest(db);
  final puerto = PuertoLocal(baseLocalCompanion());
  final provs = (await t.runAsync(() => puerto.proveedores()))!;
  return _Escenario(db, puerto, [provs[0].id, provs[1].id]);
}

// Un celular parado: el viewport por defecto (800×600) no representa la pantalla real (TRAMPAS.md).
void tester(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> _abrir(WidgetTester t) async {
  await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: const PantallaConteoStock()));
  await _asentar(t);
}

Finder _fila(String nombre) => find.ancestor(of: find.text(nombre), matching: find.byType(Superficie)).first;

Finder _masDe(String nombre) => find.descendant(of: _fila(nombre), matching: find.byTooltip('Uno más'));

Finder _menosDe(String nombre) => find.descendant(of: _fila(nombre), matching: find.byTooltip('Uno menos'));

Future<int> _stockDe(WidgetTester t, AppDatabase db, int id) async =>
    (await t.runAsync(() => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle()))!.stock;

void main() {
  testWidgets('lo que no se toca no cambia; lo tocado guarda el valor contado con su rastro', (t) async {
    final e = await _preparar(t);
    final cerveza = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 12, proveedorId: e.proveedores[0], usuarioId: 1)))!;
    final agua = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Agua', esPesable: false, stock: 30, proveedorId: e.proveedores[0], usuarioId: 1)))!;
    await _abrir(t);

    await t.tap(_masDe('Cerveza'));
    await t.pump();
    expect(find.text('Guardar conteo (1)'), findsOneWidget);

    await t.tap(find.text('Guardar conteo (1)'));
    await _asentar(t);

    expect(await _stockDe(t, e.db, cerveza), 13, reason: 'partió del stock del sistema (12) y sumó uno');
    expect(await _stockDe(t, e.db, agua), 30, reason: 'el agua no se tocó: su stock queda como estaba');
    final movimientos = (await t.runAsync(() => (e.db.select(e.db.movimientosDeStock)..where((m) => m.productoId.equals(cerveza))).get()))!;
    expect(movimientos.last.motivo, 'Conteo físico');
    final delAgua = (await t.runAsync(() => (e.db.select(e.db.movimientosDeStock)..where((m) => m.productoId.equals(agua))).get()))!;
    expect(delAgua.where((m) => m.motivo == 'Conteo físico'), isEmpty, reason: 'sin tocar, no deja ningún movimiento de conteo');
    expect(find.text('Guardar conteo (1)'), findsNothing, reason: 'tras guardar se limpia lo cargado');
  });

  testWidgets('sin nada cargado el botón de guardar está deshabilitado', (t) async {
    final e = await _preparar(t);
    await t.runAsync(() => e.puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 12, proveedorId: e.proveedores[0], usuarioId: 1));
    await _abrir(t);

    final boton = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar conteo'));
    expect(boton.onPressed, isNull);
  });

  testWidgets('el menos no baja de cero', (t) async {
    final e = await _preparar(t);
    final id = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 1, proveedorId: e.proveedores[0], usuarioId: 1)))!;
    await _abrir(t);

    await t.tap(_menosDe('Cerveza'));
    await t.tap(_menosDe('Cerveza'));
    await t.tap(_menosDe('Cerveza'));
    await t.pump();
    await t.tap(find.text('Guardar conteo (1)'));
    await _asentar(t);

    expect(await _stockDe(t, e.db, id), 0);
  });

  testWidgets('cambiar de proveedor no pierde lo ya cargado y se guarda todo junto', (t) async {
    final e = await _preparar(t);
    final cerveza = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 12, proveedorId: e.proveedores[1], usuarioId: 1)))!;
    final pan = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Pan', esPesable: false, stock: 5, proveedorId: e.proveedores[0], usuarioId: 1)))!;
    await _abrir(t);

    await t.tap(_masDe('Cerveza'));
    await t.pump();

    // Se mira solo al proveedor del pan (el primer chip, a la vista): la cerveza sale de la vista pero su conteo sigue cargado.
    final nombreProv2 = (await t.runAsync(() => e.puerto.proveedores()))!.firstWhere((p) => p.id == e.proveedores[0]).nombre;
    await t.tap(find.widgetWithText(ChipSeleccionable, nombreProv2).first);
    await t.pump();
    expect(find.text('Cerveza'), findsNothing);
    expect(find.text('Guardar conteo (1)'), findsOneWidget);

    await t.tap(_masDe('Pan'));
    await t.pump();
    expect(find.text('Guardar conteo (2)'), findsOneWidget);

    await t.tap(find.text('Guardar conteo (2)'));
    await _asentar(t);
    expect(await _stockDe(t, e.db, cerveza), 13);
    expect(await _stockDe(t, e.db, pan), 6);
  });

  testWidgets('el filtro "Sin stock" muestra solo lo agotado', (t) async {
    final e = await _preparar(t);
    await t.runAsync(() => e.puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 12, proveedorId: e.proveedores[0], usuarioId: 1));
    await t.runAsync(() => e.puerto.crearProducto(nombre: 'Yerba', esPesable: false, stock: 0, proveedorId: e.proveedores[0], usuarioId: 1));
    await _abrir(t);
    expect(find.text('Cerveza'), findsOneWidget);
    expect(find.text('Yerba'), findsOneWidget);

    await t.tap(find.widgetWithText(ChipSeleccionable, 'Sin stock'));
    await t.pump();

    expect(find.text('Cerveza'), findsNothing);
    expect(find.text('Yerba'), findsOneWidget);
  });

  testWidgets('un pesable se cuenta en gramos y guarda gramos', (t) async {
    final e = await _preparar(t);
    final id = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Jamón', esPesable: true, precioPorKiloCentavos: 1000000, stockGramos: 3200, proveedorId: e.proveedores[0], usuarioId: 1)))!;
    await _abrir(t);

    expect(find.descendant(of: _fila('Jamón'), matching: find.byTooltip('Uno más')), findsNothing, reason: 'los pesables no llevan −/+');
    await t.enterText(find.descendant(of: _fila('Jamón'), matching: find.byType(TextField)), '2750');
    await t.pump();
    await t.tap(find.text('Guardar conteo (1)'));
    await _asentar(t);

    final guardado = (await t.runAsync(() => (e.db.select(e.db.productos)..where((p) => p.id.equals(id))).getSingle()))!;
    expect(guardado.stockGramos, 2750);
  });
}
