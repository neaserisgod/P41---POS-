
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/domain/marca.dart';
import 'package:la_plazoleta/servicios/marca_actual.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    marcaActual.value = const MarcaNegocio();
  });
  tearDown(() async {
    marcaActual.value = const MarcaNegocio();
    await db.close();
  });

  Future<void> esperarA(bool Function() condicion) async {
    for (var i = 0; i < 200 && !condicion(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  group('marcaDeBase', () {
    test('una base nueva todavía no tiene comercio cargado', () async {
      final marca = await marcaDeBase(db);
      expect(marca.configurada, isFalse);
      expect(marca.nombre, nombreProducto);
    });

    test('lee el nombre y el encabezado guardados', () async {
      await configurarNombreComercio(db, 'Kiosco Del Centro');
      await configurarEncabezadoTicket(db, 'Kiosco Del Centro\nSan Martín 123');
      final marca = await marcaDeBase(db);
      expect(marca.nombre, 'Kiosco Del Centro');
      expect(marca.encabezadoTicket, 'Kiosco Del Centro\nSan Martín 123');
    });

    test('sin fila de configuración (celular antes de sincronizar) no rompe: usa el nombre del producto', () async {
      await db.delete(db.configuracionNegocioTabla).go();
      final marca = await marcaDeBase(db);
      expect(marca.nombre, nombreProducto);
    });
  });

  group('seguirMarca — la marca visible acompaña a la configuración', () {
    test('toma lo que ya estaba guardado al arrancar', () async {
      await configurarNombreComercio(db, 'Mi comercio');
      final sub = seguirMarca(db);
      addTearDown(sub.cancel);
      await esperarA(() => marcaActual.value.configurada);
      expect(marcaActual.value.nombre, 'Mi comercio');
    });

    test('se actualiza sola cuando cambia el nombre (también si el cambio llega por sincronización)', () async {
      final sub = seguirMarca(db);
      addTearDown(sub.cancel);
      await configurarNombreComercio(db, 'Primero');
      await esperarA(() => marcaActual.value.nombre == 'Primero');
      expect(marcaActual.value.nombre, 'Primero');

      await configurarNombreComercio(db, 'Segundo');
      await esperarA(() => marcaActual.value.nombre == 'Segundo');
      expect(marcaActual.value.nombre, 'Segundo');
    });

    test('si se vacía el nombre vuelve al del producto', () async {
      await configurarNombreComercio(db, 'Mi comercio');
      final sub = seguirMarca(db);
      addTearDown(sub.cancel);
      await esperarA(() => marcaActual.value.configurada);
      await configurarNombreComercio(db, '');
      await esperarA(() => !marcaActual.value.configurada);
      expect(marcaActual.value.nombre, nombreProducto);
    });

    test('un cambio que no toca la marca no avisa a nadie', () async {
      final sub = seguirMarca(db);
      addTearDown(sub.cancel);
      await esperarA(() => false); // deja pasar la primera lectura
      var avisos = 0;
      void contar() => avisos++;
      marcaActual.addListener(contar);
      addTearDown(() => marcaActual.removeListener(contar));
      await configurarPasoRedondeo(db, 5000);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(avisos, 0);
    });

    test('al cancelar la suscripción deja de seguir', () async {
      final sub = seguirMarca(db);
      await sub.cancel();
      await configurarNombreComercio(db, 'Nadie lo escucha');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(marcaActual.value.configurada, isFalse);
    });
  });
}
