// El perfil del celular sale de la cuenta (2026-10-02): se reutiliza el del mismo nombre, o se crea; nunca se elige de una lista.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/emparejamiento.dart';
import 'package:la_plazoleta/companion/pantalla_entrar_con_cuenta.dart';
import 'package:la_plazoleta/companion/perfil_por_cuenta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/sync_nube_companion.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/sync_nube.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

Future<void> _asentar(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  }
  await t.pump();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('resolverPerfilDeCuenta', () {
    late AppDatabase db;
    late PuertoLocal puerto;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = baseDeTest();
      puerto = PuertoLocal(db);
    });
    tearDown(() => db.close());

    test('reutiliza el perfil del mismo nombre, sin importar mayúsculas ni acentos, y lo deja guardado', () async {
      final id = await puerto.crearUsuarioNuevo('María Gómez');
      final u = await resolverPerfilDeCuenta(perfil: const PerfilDeCuenta(email: 'm@x.com', nombre: 'maria gomez', rol: 'employee'), servicio: puerto);
      expect(u.id, id);
      expect((await leerUsuario())!.id, id);
      expect((await puerto.usuarios()).where((x) => x.nombre.toLowerCase().contains('mar')), hasLength(1), reason: 'no duplicó el perfil');
    });

    test('si no existe lo crea con el nombre de la cuenta', () async {
      final antes = (await puerto.usuarios()).length;
      final u = await resolverPerfilDeCuenta(perfil: const PerfilDeCuenta(email: 'nuevo@x.com', nombre: 'Lucas Pérez'), servicio: puerto);
      expect((await puerto.usuarios()).length, antes + 1);
      expect(u.nombre, 'Lucas Pérez');
      expect((await leerUsuario())!.nombre, 'Lucas Pérez');
    });

    test('una cuenta sin nombre usa la parte del mail antes de la @', () async {
      final u = await resolverPerfilDeCuenta(perfil: const PerfilDeCuenta(email: 'sinnombre@x.com', nombre: '  '), servicio: puerto);
      expect(u.nombre, 'sinnombre');
    });

    test('un perfil desactivado por el dueño no se reactiva solo: se avisa y no se guarda nada', () async {
      final id = await puerto.crearUsuarioNuevo('Marta');
      await puerto.alternarActivoUsuarioExistente(id, false);
      await expectLater(
        resolverPerfilDeCuenta(perfil: const PerfilDeCuenta(email: 'marta@x.com', nombre: 'Marta'), servicio: puerto),
        throwsA(isA<PerfilDesactivado>()),
      );
      expect(await leerUsuario(), isNull);
    });
  });

  group('PantallaEntrarConCuenta', () {
    late AppDatabase db;
    late PuertoLocal puerto;
    var entro = false;

    setUp(() {
      entro = false;
      SharedPreferences.setMockInitialValues({});
    });

    Future<SyncNubeCompanion> armar(WidgetTester t, {required bool vinculada, required Future<http.Response> Function(http.Request) servidor}) async {
      db = (await t.runAsync(() async => baseDeTest()))!;
      usarBaseLocalDeTest(db);
      puerto = PuertoLocal(db);
      final almacen = AlmacenCuentaEnMemoria();
      if (vinculada) {
        await almacen.guardar(const CuentaVinculada(token: 'tok', email: 'marta@x.com', idDispositivo: 'd', nombreDispositivo: 'Celular', vence: 99));
      }
      final sync = armarSyncNubeCompanion(
        almacen: almacen,
        almacenEstado: AlmacenEstadoSyncEnMemoria(),
        cliente: ClienteNube(http: MockClient(servidor)),
        abrirNavegador: (_) async {},
        db: db,
      );
      addTearDown(() {
        sync.servicio.detener();
        sync.conmutador.cerrar();
        db.close();
      });
      return sync;
    }

    Future<void> abrir(WidgetTester t, SyncNubeCompanion sync) async {
      t.view.physicalSize = const Size(400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
        theme: TemaCompanion.claro,
        home: PantallaEntrarConCuenta(sync: sync, servicio: () async => puerto, alEntrar: (_) => entro = true),
      ));
      await _asentar(t);
    }

    http.Response yoOk() => http.Response('{"email":"marta@x.com","name":"Marta Gómez","role":"employee","orgId":1,"branchId":2}', 200, headers: {'content-type': 'application/json'});

    testWidgets('con la cuenta ya vinculada entra solo: toma el perfil de la cuenta y no muestra ninguna lista', (t) async {
      final sync = await armar(t, vinculada: true, servidor: (r) async => yoOk());
      await abrir(t, sync);
      expect(entro, isTrue);
      expect((await t.runAsync(() => leerUsuario()))!.nombre, 'Marta Gómez');
      expect(find.text('¿Quién sos?'), findsNothing);
    });

    testWidgets('sin cuenta pide entrar con ella: no hay selector de perfil y no se entra', (t) async {
      final sync = await armar(t, vinculada: false, servidor: (r) async => fail('no tenía que llamar a nada'));
      await abrir(t, sync);
      expect(find.byKey(const Key('entrar_con_cuenta')), findsOneWidget);
      expect(find.text('¿Quién sos?'), findsNothing);
      expect(entro, isFalse);
    });

    testWidgets('si la sacaron del negocio (401) lo dice y ofrece entrar de nuevo, sin dejarla pasar', (t) async {
      final sync = await armar(t, vinculada: true, servidor: (r) async => http.Response('{"error":"no_device"}', 401));
      await abrir(t, sync);
      expect(entro, isFalse);
      expect(find.byKey(const Key('entrar_error')), findsOneWidget);
      expect(find.byKey(const Key('entrar_con_cuenta')), findsOneWidget);
      expect(find.byKey(const Key('entrar_reintentar')), findsNothing, reason: 'reintentar con el mismo token no sirve');
    });

    testWidgets('un perfil desactivado en el POS no entra y lo explica', (t) async {
      final sync = await armar(t, vinculada: true, servidor: (r) async => yoOk());
      final id = (await t.runAsync(() => puerto.crearUsuarioNuevo('Marta Gómez')))!;
      await t.runAsync(() => puerto.alternarActivoUsuarioExistente(id, false));
      await abrir(t, sync);
      expect(entro, isFalse);
      expect(find.textContaining('desactivado'), findsOneWidget);
    });
  });
}
