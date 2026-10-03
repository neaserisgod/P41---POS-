// Índices de las columnas de clave foránea que reciben WHERE/JOIN (auditoría de rendimiento, 2026-10-03): se crean al abrir la
// base, también en una que ya existía, y repetirlos no rompe nada.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';

Future<Set<String>> _indices(AppDatabase db) async =>
    (await db.customSelect("SELECT name FROM sqlite_master WHERE type='index'").get()).map((f) => f.read<String>('name')).toSet();

void main() {
  test('una base nueva trae los índices de las consultas calientes y de las claves foráneas', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final nombres = await _indices(db);
    for (final i in [
      'idx_lineas_de_venta_venta_id',
      'idx_ventas_fecha',
      'idx_lineas_de_venta_producto_id',
      'idx_movimientos_de_stock_producto_id',
      'idx_movimientos_de_stock_venta_id',
      'idx_historial_de_precios_producto_id',
    ]) {
      expect(nombres, contains(i));
    }
  });

  test('si falta uno (base que viene de antes) se crea al abrir, sin tocar los datos', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement('DROP INDEX idx_lineas_de_venta_producto_id');
    expect(await _indices(db), isNot(contains('idx_lineas_de_venta_producto_id')));
    await db.customStatement('CREATE INDEX IF NOT EXISTS idx_lineas_de_venta_producto_id ON lineas_de_venta (producto_id)');
    expect(await _indices(db), contains('idx_lineas_de_venta_producto_id'));
  });
}
