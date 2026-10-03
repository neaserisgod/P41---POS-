// Prueba la API completa de la companion app por HTTP real (un cliente
// `http` de afuera del proceso del servidor, como haría el celular) — no
// llamadas directas a los handlers. El spike original (arrancar/responder
// /ping) queda cubierto acá adentro también.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/companion/carrito_venta.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_arqueo_intermedio.dart';
import 'package:la_plazoleta/data/repositorio_carga_historica.dart' show notaCargaHistorica;
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_cobro.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart' show crearCategoria;
import 'package:la_plazoleta/data/repositorio_ticket.dart'
    show configurarMpAccessToken, configurarMpTerminalCobroId, configurarMpTerminalId;
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/domain/venta_json.dart';
import 'package:la_plazoleta/servidor/servidor_companion.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../helpers/base_para_tests.dart';

/// `getApplicationDocumentsDirectory()` (usada por `_archivoApkCompanion` en
/// el servidor, igual que `driftDatabase` para la base real) necesita un
/// canal de plataforma que no existe bajo `flutter test` — se apunta a una
/// carpeta temporal real, para no tocar el Documents real de quien corre
/// los tests.
class _RutaDeDocumentosDePrueba extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _RutaDeDocumentosDePrueba(this.carpeta);
  final String carpeta;

  @override
  Future<String?> getApplicationDocumentsPath() async => carpeta;
}

void main() {
  test('la llave del celular se compara sin cortar en la primera diferencia, y da lo mismo que ==', () {
    expect(mismosTextosEnTiempoConstante('abc123', 'abc123'), isTrue);
    expect(mismosTextosEnTiempoConstante('abc124', 'abc123'), isFalse);
    expect(mismosTextosEnTiempoConstante('abc12', 'abc123'), isFalse);
    expect(mismosTextosEnTiempoConstante('abc1234', 'abc123'), isFalse);
    expect(mismosTextosEnTiempoConstante('', 'abc123'), isFalse);
    expect(mismosTextosEnTiempoConstante(null, 'abc123'), isFalse);
  });

  // Los endpoints /companion/* usan plugins de plataforma (PackageInfo,
  // path_provider) que necesitan el binding inicializado — `testWidgets()`
  // lo trae solo, `test()` no. Ese binding trae de regalo un
  // `HttpOverrides` que hace fallar CUALQUIER HTTP real con 400 (para que
  // los widget tests no dependan de la red sin querer) — acá se saca a
  // propósito, porque estos tests SÍ hacen HTTP real contra el propio
  // servidor.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late AppDatabase db;
  late int puerto;
  late String token;
  late int usuarioId;
  late Directory carpetaDocumentosDePrueba;

  Uri url(String path) => Uri.parse('http://127.0.0.1:$puerto$path');
  Map<String, String> headers({bool conToken = true}) => {
    'content-type': 'application/json',
    if (conToken) encabezadoToken: token,
  };

  setUp(() async {
    // `/companion/version` usa PackageInfo.fromPlatform(), que en un test
    // (sin canal de plataforma real) necesita este mock — ver
    // `package_info_plus`'s docs.
    PackageInfo.setMockInitialValues(
      appName: 'la_plazoleta',
      packageName: 'com.example.la_plazoleta',
      version: '1.0.0',
      buildNumber: '2',
      buildSignature: '',
    );
    // `/companion/apk` busca el archivo en el Documents "real" — para no
    // tocar el del que corre los tests, se apunta a una carpeta temporal.
    carpetaDocumentosDePrueba = await Directory.systemTemp.createTemp('companion_test_');
    addTearDown(() => carpetaDocumentosDePrueba.delete(recursive: true));
    PathProviderPlatform.instance = _RutaDeDocumentosDePrueba(carpetaDocumentosDePrueba.path);
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    token = await regenerarTokenCompanion(db);
    final server = await iniciarServidorCompanion(db, puerto: 0);
    puerto = server.port;
    addTearDown(server.close);
  });
  tearDown(() => db.close());

  test('/emparejar: el código de la PC da la llave una sola vez, sin token; uno incorrecto o sin código, no', () async {
    Future<http.Response> emparejar(String codigo) =>
        http.post(url('/emparejar'), headers: headers(conToken: false), body: jsonEncode({'codigo': codigo}));
    codigoEmparejamiento.anular();
    expect((await emparejar('123456')).statusCode, 404, reason: 'sin código generado');
    final codigo = codigoEmparejamiento.generar();
    final malo = codigo == '000000' ? '111111' : '000000';
    final rIncorrecto = await emparejar(malo);
    expect(rIncorrecto.statusCode, 401);
    expect((jsonDecode(rIncorrecto.body) as Map)['error'], contains('incorrecto'));
    final r = await emparejar(codigo);
    expect(r.statusCode, 200);
    expect((jsonDecode(r.body) as Map)['token'], await tokenCompanionActual(db));
    expect((await emparejar(codigo)).statusCode, 404, reason: 'de un solo uso');
    expect((await emparejar('12')).statusCode, 400);
    final datos = await ClienteCompanion.emparejarConCodigo('127.0.0.1', puerto, codigoEmparejamiento.generar());
    expect(datos.token, await tokenCompanionActual(db));
  });

  test('/ping responde sin necesitar token', () async {
    final respuesta = await http.get(url('/ping'));
    expect(respuesta.statusCode, 200);
  });

  test('cualquier otra ruta sin token (o con uno incorrecto) da 401', () async {
    final sinToken = await http.get(url('/productos'), headers: headers(conToken: false));
    expect(sinToken.statusCode, 401);

    final tokenMalo = await http.get(url('/productos'), headers: {...headers(), encabezadoToken: 'otro'});
    expect(tokenMalo.statusCode, 401);
  });

  test('/usuarios lista los usuarios de la base', () async {
    final respuesta = await http.get(url('/usuarios'), headers: headers());
    final lista = jsonDecode(respuesta.body) as List;
    final bruno = lista.cast<Map<String, dynamic>>().firstWhere((u) => u['id'] == usuarioId);
    expect(bruno['nombre'], 'Dueño');
  });

  test('/proveedores lista el catálogo real de proveedores', () async {
    final respuesta = await http.get(url('/proveedores'), headers: headers());
    final lista = jsonDecode(respuesta.body) as List;
    expect(lista, isNotEmpty);
    expect((lista.first as Map)['codigo'], isNotNull);
  });

  test('alta de producto por POST, y aparece en el listado', () async {
    final alta = await http.post(
      url('/productos'),
      headers: headers(),
      body: jsonEncode({'nombre': 'Fernet', 'precioCentavos': 500000, 'usuarioId': usuarioId}),
    );
    expect(alta.statusCode, 201);
    final id = (jsonDecode(alta.body) as Map)['id'] as int;

    final listado = await http.get(url('/productos'), headers: headers());
    final productos = jsonDecode(listado.body) as List;
    final creado = productos.cast<Map<String, dynamic>>().firstWhere((p) => p['id'] == id);
    expect(creado['nombre'], 'Fernet');
    expect(creado['precioCentavos'], 500000);
  });

  // El dueño, 2026-09-19: "filtrar por productos sin proveedor, sin costo,
  // etcétera" desde la companion — el filtro en sí ya está probado a fondo
  // en `repositorio_productos_test.dart` (`listarProductos`); esto prueba
  // nada más que el endpoint reenvía el query param correcto, que es lo que
  // de verdad conecta al celular con ese filtro.
  test('/productos?sinCosto=true reenvía el filtro a listarProductos', () async {
    await http.post(
      url('/productos'),
      headers: headers(),
      body: jsonEncode({'nombre': 'Con costo', 'precioCentavos': 100000, 'costoCentavos': 50000, 'usuarioId': usuarioId}),
    );
    await http.post(
      url('/productos'),
      headers: headers(),
      body: jsonEncode({'nombre': 'Sin costo', 'precioCentavos': 100000, 'usuarioId': usuarioId}),
    );

    final respuesta = await http.get(url('/productos?sinCosto=true'), headers: headers());
    final productos = jsonDecode(respuesta.body) as List;
    expect(productos.cast<Map<String, dynamic>>().map((p) => p['nombre']), ['Sin costo']);
  });

  // Editor masivo (El dueño, 2026-09-19: "editor masivo, ya sea de precios
  // costo stock etc etc") — cada fórmula ya está probada a fondo en
  // `repositorio_productos_test.dart`; esto prueba nada más que cada
  // endpoint reenvía bien los parámetros al repositorio en lote.
  group('/productos/lote/*', () {
    Future<int> crear(String nombre, {int? precioCentavos, int stock = 0}) async {
      final r = await http.post(
        url('/productos'),
        headers: headers(),
        body: jsonEncode({
          'nombre': nombre,
          'precioCentavos': precioCentavos ?? 100000,
          'stock': stock,
          'usuarioId': usuarioId,
        }),
      );
      return (jsonDecode(r.body) as Map)['id'] as int;
    }

    test('/productos/lote/monto ajusta precio o costo de varios productos', () async {
      final id1 = await crear('A', precioCentavos: 100000);
      final id2 = await crear('B', precioCentavos: 200000);

      final respuesta = await http.post(
        url('/productos/lote/monto'),
        headers: headers(),
        body: jsonEncode({
          'productoIds': [id1, id2],
          'campo': 'precio',
          'tipo': 'nuevoFijo',
          'valor': 150000,
          'usuarioId': usuarioId,
        }),
      );
      expect(respuesta.statusCode, 200);

      final listado = jsonDecode((await http.get(url('/productos'), headers: headers())).body) as List;
      final productos = listado.cast<Map<String, dynamic>>();
      expect(productos.firstWhere((p) => p['id'] == id1)['precioCentavos'], 150000);
      expect(productos.firstWhere((p) => p['id'] == id2)['precioCentavos'], 150000);
    });

    test('/productos/lote/stock suma unidades a varios productos', () async {
      final id1 = await crear('C', stock: 10);
      final id2 = await crear('D', stock: 5);

      final respuesta = await http.post(
        url('/productos/lote/stock'),
        headers: headers(),
        body: jsonEncode({
          'productoIds': [id1, id2],
          'tipo': 'sumar',
          'valor': 3,
          'usuarioId': usuarioId,
        }),
      );
      expect(respuesta.statusCode, 200);

      final listado = jsonDecode((await http.get(url('/productos'), headers: headers())).body) as List;
      final productos = listado.cast<Map<String, dynamic>>();
      expect(productos.firstWhere((p) => p['id'] == id1)['stock'], 13);
      expect(productos.firstWhere((p) => p['id'] == id2)['stock'], 8);
    });

    test('/productos/lote/categoria reasigna la categoría de varios productos', () async {
      final categoriaId = await crearCategoria(db, 'Nueva');
      final id1 = await crear('E');

      final respuesta = await http.post(
        url('/productos/lote/categoria'),
        headers: headers(),
        body: jsonEncode({
          'productoIds': [id1],
          'categoriaId': categoriaId,
          'usuarioId': usuarioId,
        }),
      );
      expect(respuesta.statusCode, 200);

      final listado = jsonDecode((await http.get(url('/productos'), headers: headers())).body) as List;
      final producto = listado.cast<Map<String, dynamic>>().firstWhere((p) => p['id'] == id1);
      expect(producto['categoriaId'], categoriaId);
    });

    test('un tipo de ajuste desconocido da 400, no un 500 crudo', () async {
      final id1 = await crear('G');

      final respuesta = await http.post(
        url('/productos/lote/stock'),
        headers: headers(),
        body: jsonEncode({
          'productoIds': [id1],
          'tipo': 'porcentaje', // no existe para stock
          'valor': 10,
          'usuarioId': usuarioId,
        }),
      );
      expect(respuesta.statusCode, 400);
    });

    test('sin productoIds da 400, no un 500 crudo', () async {
      final respuesta = await http.post(
        url('/productos/lote/proveedor'),
        headers: headers(),
        body: jsonEncode({'proveedorId': null, 'usuarioId': usuarioId}),
      );
      expect(respuesta.statusCode, 400);
    });
  });

  test(
    'alta con un código de barras repetido da 400 con mensaje claro, no un 500 crudo (Dueño, 2026-09-07: "no agrega")',
    () async {
      await http.post(
        url('/productos'),
        headers: headers(),
        body: jsonEncode({
          'nombre': 'Fernet',
          'codigoBarras': '7790001',
          'precioCentavos': 500000,
          'usuarioId': usuarioId,
        }),
      );

      final segundoIntento = await http.post(
        url('/productos'),
        headers: headers(),
        body: jsonEncode({
          'nombre': 'Otro producto',
          'codigoBarras': '7790001',
          'precioCentavos': 100000,
          'usuarioId': usuarioId,
        }),
      );

      expect(segundoIntento.statusCode, 400);
      final cuerpo = jsonDecode(segundoIntento.body) as Map<String, dynamic>;
      expect(cuerpo['error'], contains('Fernet'));
    },
  );

  test('/productos/codigo/<codigo> encuentra por código de barras exacto (escáner)', () async {
    await http.post(
      url('/productos'),
      headers: headers(),
      body: jsonEncode({
        'nombre': 'Fernet',
        'codigoBarras': '7791234567890',
        'precioCentavos': 500000,
        'usuarioId': usuarioId,
      }),
    );

    final respuesta = await http.get(url('/productos/codigo/7791234567890'), headers: headers());
    expect(respuesta.statusCode, 200);
    expect((jsonDecode(respuesta.body) as Map)['nombre'], 'Fernet');
  });

  test('/productos/codigo/<codigo> sin match da 404', () async {
    final respuesta = await http.get(url('/productos/codigo/0000000000000'), headers: headers());
    expect(respuesta.statusCode, 404);
  });

  test('alta de un pesable sin precio por kilo da 400, no 500', () async {
    final alta = await http.post(
      url('/productos'),
      headers: headers(),
      body: jsonEncode({'nombre': 'Jamón', 'esPesable': true, 'usuarioId': usuarioId}),
    );
    expect(alta.statusCode, 400);
  });

  test('editar precio por PUT queda reflejado, y deja rastro en historial de precios', () async {
    final alta = await http.post(
      url('/productos'),
      headers: headers(),
      body: jsonEncode({'nombre': 'Fernet', 'precioCentavos': 500000, 'usuarioId': usuarioId}),
    );
    final id = (jsonDecode(alta.body) as Map)['id'] as int;

    final edicion = await http.put(
      url('/productos/$id'),
      headers: headers(),
      body: jsonEncode({
        'nombre': 'Fernet 1L',
        'precioCentavos': 550000,
        'stock': 0,
        'usuarioId': usuarioId,
      }),
    );
    expect(edicion.statusCode, 200);

    final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
    expect(producto.nombre, 'Fernet 1L');
    expect(producto.precioCentavos, 550000);

    final historial = await (db.select(db.historialDePrecios)..where((h) => h.productoId.equals(id))).get();
    expect(historial, hasLength(2)); // alta + edición
  });

  test('conteo de stock por POST /productos/<id>/stock deja rastro en movimientos_de_stock', () async {
    final alta = await http.post(
      url('/productos'),
      headers: headers(),
      body: jsonEncode({'nombre': 'Fernet', 'precioCentavos': 500000, 'stock': 5, 'usuarioId': usuarioId}),
    );
    final id = (jsonDecode(alta.body) as Map)['id'] as int;

    final ajuste = await http.post(
      url('/productos/$id/stock'),
      headers: headers(),
      body: jsonEncode({'stock': 12, 'motivo': 'Conteo físico', 'usuarioId': usuarioId}),
    );
    expect(ajuste.statusCode, 200);

    final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
    expect(producto.stock, 12);
    final movimientos = await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).get();
    expect(movimientos, hasLength(1));
    expect(movimientos.single.tipo, 'AJUSTE');
  });

  test(
    '/productos/sin-stock trae los agotados de todos los proveedores, no los que tienen stock (Dueño, 2026-09-07)',
    () async {
      await db.into(db.productos).insert(
        ProductosCompanion.insert(nombre: 'Con stock', precioCentavos: const Value(1000), stock: const Value(5)),
      );
      await db.into(db.productos).insert(
        ProductosCompanion.insert(nombre: 'Agotado', precioCentavos: const Value(1000), stock: const Value(0)),
      );
      await db.into(db.productos).insert(
        ProductosCompanion.insert(nombre: 'Negativo', precioCentavos: const Value(1000), stock: const Value(-2)),
      );
      await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Pesable sin stock',
          esPesable: const Value(true),
          precioPorKiloCentavos: const Value(800000),
          stockGramos: const Value(0),
        ),
      );

      final respuesta = await http.get(url('/productos/sin-stock'), headers: headers());
      final resultados = (jsonDecode(respuesta.body) as List).cast<Map<String, dynamic>>();
      expect(
        resultados.map((p) => p['nombre']),
        ['Agotado', 'Negativo', 'Pesable sin stock'], // alfabético, "Con stock" no entra
      );
    },
  );

  test('/sesion informa si hay una sesión de caja abierta', () async {
    final antes = await http.get(url('/sesion'), headers: headers());
    expect((jsonDecode(antes.body) as Map)['abierta'], isFalse);

    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 15000000);

    final despues = await http.get(url('/sesion'), headers: headers());
    final cuerpo = jsonDecode(despues.body) as Map;
    expect(cuerpo['abierta'], isTrue);
    expect(cuerpo['id'], sesionId);
  });

  test(
    '/sesion trae "fechaUltimoArqueoIntermedio" para que el celular sepa si el bloqueo de 2hs venció '
    '(Dueño, 2026-09-13: "sincronizado con la app desktop")',
    () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      final sinArqueoTodavia = await http.get(url('/sesion'), headers: headers());
      expect(jsonDecode(sinArqueoTodavia.body), isNot(contains('fechaUltimoArqueoIntermedio')));

      await registrarArqueoIntermedio(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );

      final conArqueo = await http.get(url('/sesion'), headers: headers());
      expect(jsonDecode(conArqueo.body), contains('fechaUltimoArqueoIntermedio'));
    },
  );

  test('/sesion sin caja abierta trae el fondo inicial sugerido, si hay uno', () async {
    final sinSugerencia = await http.get(url('/sesion'), headers: headers());
    expect(jsonDecode(sinSugerencia.body), isNot(contains('fondoInicialSugeridoCentavos')));

    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await cerrarSesion(
      db,
      sesionId: sesionId,
      usuarioId: usuarioId,
      efectivoContadoCentavos: 250000,
      mpContadoCentavos: 0,
      lataContadoCentavos: 0,
    );

    final conSugerencia = await http.get(url('/sesion'), headers: headers());
    final cuerpo = jsonDecode(conSugerencia.body) as Map;
    expect(cuerpo['abierta'], isFalse);
    expect(cuerpo['fondoInicialSugeridoCentavos'], 250000);
  });

  test('POST /sesion/abrir abre la caja igual que el diálogo de escritorio', () async {
    final respuesta = await http.post(
      url('/sesion/abrir'),
      headers: headers(),
      body: jsonEncode({'usuarioId': usuarioId, 'fondoInicialCentavos': 30000}),
    );
    expect(respuesta.statusCode, 201);
    final id = (jsonDecode(respuesta.body) as Map)['id'] as int;

    final sesion = await sesionAbierta(db);
    expect(sesion?.id, id);
    expect(sesion?.fondoInicialCentavos, 30000);
  });

  test(
    'POST /sesion/abrir con una ya abierta: 409, avisa quién la abrió, no crea otra',
    () async {
      // El dueño, 2026-09-19: "aislar los usuarios para que no se pisen" — ya
      // no es idempotente en silencio: el segundo dispositivo se entera de
      // que ya está abierta en vez de que se ignoren sus montos sin avisar.
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 10000);

      final respuesta = await http.post(
        url('/sesion/abrir'),
        headers: headers(),
        body: jsonEncode({'usuarioId': usuarioId, 'fondoInicialCentavos': 99999}),
      );
      expect(respuesta.statusCode, 409);
      final mensaje = (jsonDecode(respuesta.body) as Map)['error'] as String;
      expect(mensaje, contains('Dueño'));

      final sesion = await sesionAbierta(db);
      expect(sesion?.id, sesionId);
      expect(sesion?.fondoInicialCentavos, 10000);
    },
  );

  group(
    'arqueo obligatorio cada 2hs desde el celular (Dueño, 2026-09-13: "el bloqueo sincronizado con la app desktop")',
    () {
      test(
        '/calcular la lata NO asume separado lo vendido hoy — misma corrección que el escritorio '
        '(REGLAS-NEGOCIO.md §6: la separación es solo al cierre; el detalle de que ignora '
        'ventas de cigarrillos ya está probado en repositorio_arqueo_intermedio_test.dart)',
        () async {
          await abrirSesion(
            db,
            usuarioId: usuarioId,
            fondoInicialCentavos: 100000,
            lataInicialCentavos: 500000,
          );

          final respuesta = await http.post(
            url('/sesion/arqueo-intermedio/calcular'),
            headers: headers(),
            body: jsonEncode({
              'efectivoContadoCentavos': 100000,
              'lataContadoCentavos': 500000,
            }),
          );

          expect(respuesta.statusCode, 200);
          final j = jsonDecode(respuesta.body) as Map<String, dynamic>;
          expect(j['lataEsperadoCentavos'], 500000);
          expect(j['lataDiferenciaCentavos'], 0);
        },
      );

      test('/confirmar guarda el arqueo — el próximo GET /sesion ya trae la fecha nueva', () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

        final respuesta = await http.post(
          url('/sesion/arqueo-intermedio/confirmar'),
          headers: headers(),
          body: jsonEncode({
            'usuarioId': usuarioId,
            'efectivoContadoCentavos': 0,
            'mpContadoCentavos': 0,
            'lataContadoCentavos': 0,
          }),
        );
        expect(respuesta.statusCode, 200);

        final fila = (await db.select(db.arqueosIntermedios).get()).single;
        expect(fila.sesionCajaId, sesionId);

        final sesion = await http.get(url('/sesion'), headers: headers());
        expect(jsonDecode(sesion.body), contains('fechaUltimoArqueoIntermedio'));
      });

      test('sin caja abierta, /calcular y /confirmar dan 409', () async {
        final calcular = await http.post(
          url('/sesion/arqueo-intermedio/calcular'),
          headers: headers(),
          body: jsonEncode({'efectivoContadoCentavos': 0}),
        );
        expect(calcular.statusCode, 409);

        final confirmar = await http.post(
          url('/sesion/arqueo-intermedio/confirmar'),
          headers: headers(),
          body: jsonEncode({
            'usuarioId': usuarioId,
            'efectivoContadoCentavos': 0,
            'mpContadoCentavos': 0,
            'lataContadoCentavos': 0,
          }),
        );
        expect(confirmar.statusCode, 409);
      });
    },
  );

  group(
    'cerrar caja desde el celular (Dueño, 2026-09-19: "que deje cerrar caja desde el celular")',
    () {
      test('/sesion/cerrar/calcular trae el resumen completo, incluido el desglose por proveedor', () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 100000);
        final proveedorId = await db.into(db.proveedores).insert(
          ProveedoresCompanion.insert(codigo: 'ZI', nombre: 'Fiambres test 4'),
        );
        final medioEfectivoId =
            (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
        final cajaNormalId =
            (await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle()).id;
        final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            subtotalCentavos: 100000,
            totalCentavos: 100000,
          ),
        );
        await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Jamón',
            cantidad: const Value(1),
            precioUnitarioCentavos: 100000,
            proveedorIdFoto: Value(proveedorId),
            costoUnitarioCentavos: const Value(60000),
          ),
        );
        await db.into(db.pagos).insert(
          PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivoId, montoCentavos: 100000),
        );
        await db.into(db.movimientosDeCaja).insert(
          MovimientosDeCajaCompanion.insert(
            sesionCajaId: sesionId,
            cajaId: cajaNormalId,
            usuarioId: usuarioId,
            tipo: 'VENTA',
            montoCentavos: 100000,
            ventaId: Value(ventaId),
          ),
        );

        final respuesta = await http.post(
          url('/sesion/cerrar/calcular'),
          headers: headers(),
          body: jsonEncode({'efectivoContadoCentavos': 200000}),
        );
        expect(respuesta.statusCode, 200);
        final j = jsonDecode(respuesta.body) as Map<String, dynamic>;
        expect(j['efectivoEsperadoCentavos'], 200000);
        expect(j['diferenciaCentavos'], 0);
        final porProveedor = (j['porProveedor'] as List).cast<Map<String, dynamic>>();
        expect(porProveedor, hasLength(1));
        expect(porProveedor.single['nombreProveedor'], 'Fiambres test 4');
        expect(porProveedor.single['costoRealCentavos'], 60000);
        expect(porProveedor.single['gananciaCentavos'], 40000);
      });

      test('/sesion/cerrar/confirmar cierra la sesión de verdad', () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

        final respuesta = await http.post(
          url('/sesion/cerrar/confirmar'),
          headers: headers(),
          body: jsonEncode({
            'usuarioId': usuarioId,
            'efectivoContadoCentavos': 0,
            'mpContadoCentavos': 0,
            'lataContadoCentavos': 0,
          }),
        );
        expect(respuesta.statusCode, 200);

        final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
        expect(sesion.estado, 'CERRADA');
        expect(await sesionAbierta(db), isNull);
      });

      test(
        'GET /sesiones/cerradas/<id>/detalle recalcula con los conteos ya guardados, incluida la nota',
        () async {
          final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 100000);
          await cerrarSesion(
            db,
            sesionId: sesionId,
            usuarioId: usuarioId,
            efectivoContadoCentavos: 100000,
            mpContadoCentavos: 0,
            lataContadoCentavos: 0,
            nota: 'Turno tranquilo',
          );

          final respuesta = await http.get(
            url('/sesiones/cerradas/$sesionId/detalle'),
            headers: headers(),
          );
          expect(respuesta.statusCode, 200);
          final j = jsonDecode(respuesta.body) as Map<String, dynamic>;
          expect(j['efectivoEsperadoCentavos'], 100000);
          expect(j['diferenciaCentavos'], 0);
          expect(j['nota'], 'Turno tranquilo');
        },
      );

      test('GET /sesiones/cerradas/<id>/detalle contra una sesión todavía ABIERTA da 404', () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

        final respuesta = await http.get(
          url('/sesiones/cerradas/$sesionId/detalle'),
          headers: headers(),
        );
        expect(respuesta.statusCode, 404);
      });

      test('/sesion/cerrar/confirmar contra una sesión ya cerrada da 409', () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        await cerrarSesion(
          db,
          sesionId: sesionId,
          usuarioId: usuarioId,
          efectivoContadoCentavos: 0,
          mpContadoCentavos: 0,
          lataContadoCentavos: 0,
        );

        // Nadie tiene la caja abierta a esta altura — el propio endpoint ya
        // da 409 por "No hay caja abierta", el mismo resultado práctico
        // que si hubiera chocado con un cierre concurrente.
        final respuesta = await http.post(
          url('/sesion/cerrar/confirmar'),
          headers: headers(),
          body: jsonEncode({
            'usuarioId': usuarioId,
            'efectivoContadoCentavos': 0,
            'mpContadoCentavos': 0,
            'lataContadoCentavos': 0,
          }),
        );
        expect(respuesta.statusCode, 409);
      });

      test('sin caja abierta, /calcular y /confirmar dan 409', () async {
        final calcular = await http.post(
          url('/sesion/cerrar/calcular'),
          headers: headers(),
          body: jsonEncode({'efectivoContadoCentavos': 0}),
        );
        expect(calcular.statusCode, 409);

        final confirmar = await http.post(
          url('/sesion/cerrar/confirmar'),
          headers: headers(),
          body: jsonEncode({
            'usuarioId': usuarioId,
            'efectivoContadoCentavos': 0,
            'mpContadoCentavos': 0,
            'lataContadoCentavos': 0,
          }),
        );
        expect(confirmar.statusCode, 409);
      });
    },
  );

  test('gasto rápido por POST /gastos mueve la caja correspondiente', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

    final respuesta = await http.post(
      url('/gastos'),
      headers: headers(),
      body: jsonEncode({
        'sesionCajaId': sesionId,
        'usuarioId': usuarioId,
        'montoCentavos': 50000,
        'medio': 'cajonNormal',
        'motivo': 'Bolsas',
      }),
    );
    expect(respuesta.statusCode, 201);

    final movimientos = await (db.select(db.movimientosDeCaja)..where((m) => m.sesionCajaId.equals(sesionId))).get();
    expect(movimientos, hasLength(1));
    expect(movimientos.single.tipo, 'GASTO');
    expect(movimientos.single.montoCentavos, 50000);
  });

  group('cuenta corriente con proveedores', () {
    late int proveedorId;

    setUp(() async {
      proveedorId = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'PP', nombre: 'Proveedor test'));
    });

    Future<http.Response> pagar(Map<String, Object?> body) =>
        http.post(url('/proveedores/$proveedorId/pagos'), headers: headers(), body: jsonEncode(body));

    test('pagar sin deuda cargada anota el cargo "Pago sin deuda previa", el pago y el gasto de caja', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      final respuesta = await pagar({
        'sesionCajaId': sesionId,
        'usuarioId': usuarioId,
        'montoCentavos': 80000,
        'origen': 'cajon',
      });
      expect(respuesta.statusCode, 201);

      final saldos = await http.get(url('/proveedores/saldos'), headers: headers());
      expect(jsonDecode(saldos.body), {'$proveedorId': 0});

      final caja = await (db.select(db.movimientosDeCaja)..where((m) => m.sesionCajaId.equals(sesionId))).get();
      expect(caja.single.tipo, 'PAGO_PROVEEDOR');
      expect(caja.single.proveedorId, proveedorId);
      expect(caja.single.montoCentavos, 80000);
    });

    test('pagar con la caja ya CERRADA da 409 y no graba nada', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );

      final respuesta = await pagar({
        'sesionCajaId': sesionId,
        'usuarioId': usuarioId,
        'montoCentavos': 80000,
        'origen': 'cajon',
      });
      expect(respuesta.statusCode, 409);
      expect(await db.select(db.movimientosDeuda).get(), isEmpty);
      expect(await db.select(db.movimientosDeCaja).get(), isEmpty);
    });

    test('pagar desde una caja sin mandar sesión da 409', () async {
      final respuesta = await pagar({'usuarioId': usuarioId, 'montoCentavos': 80000, 'origen': 'cajon'});
      expect(respuesta.statusCode, 409);
    });

    test('pagar "fuera de la caja" no toca la caja', () async {
      final respuesta = await pagar({'usuarioId': usuarioId, 'montoCentavos': 80000, 'origen': 'fuera'});
      expect(respuesta.statusCode, 201);
      expect(await db.select(db.movimientosDeCaja).get(), isEmpty);
    });

    test('un monto en cero da 400', () async {
      final respuesta = await pagar({'usuarioId': usuarioId, 'montoCentavos': 0, 'origen': 'fuera'});
      expect(respuesta.statusCode, 400);
    });
  });

  test('/gastos con un "medio" inválido da 400', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

    final respuesta = await http.post(
      url('/gastos'),
      headers: headers(),
      body: jsonEncode({
        'sesionCajaId': sesionId,
        'usuarioId': usuarioId,
        'montoCentavos': 50000,
        'medio': 'bitcoin',
      }),
    );
    expect(respuesta.statusCode, 400);
  });

  test('/gastos contra una sesión ya CERRADA da 409, no graba nada', () async {
    // El dueño, 2026-09-19: "aislar los usuarios para que no se pisen" — un
    // gasto que llega justo después de un cierre (desde otro dispositivo)
    // no debe grabarse contra una sesión ya cerrada.
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await cerrarSesion(
      db,
      sesionId: sesionId,
      usuarioId: usuarioId,
      efectivoContadoCentavos: 0,
      mpContadoCentavos: 0,
      lataContadoCentavos: 0,
    );

    final respuesta = await http.post(
      url('/gastos'),
      headers: headers(),
      body: jsonEncode({
        'sesionCajaId': sesionId,
        'usuarioId': usuarioId,
        'montoCentavos': 50000,
        'medio': 'cajonNormal',
      }),
    );
    expect(respuesta.statusCode, 409);
    expect(await db.select(db.movimientosDeCaja).get(), isEmpty);
  });

  test(
    '"Ingreso rápido" por POST /ingresos mueve la caja correspondiente '
    '(Dueño, 2026-09-13: "un botón de ingreso de dinero, siguiendo con las cajas que hay")',
    () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      final respuesta = await http.post(
        url('/ingresos'),
        headers: headers(),
        body: jsonEncode({
          'sesionCajaId': sesionId,
          'usuarioId': usuarioId,
          'montoCentavos': 80000,
          'medio': 'lata',
          'motivo': 'Aporte para vuelto',
        }),
      );
      expect(respuesta.statusCode, 201);

      final movimientos = await (db.select(db.movimientosDeCaja)..where((m) => m.sesionCajaId.equals(sesionId))).get();
      expect(movimientos, hasLength(1));
      expect(movimientos.single.tipo, 'INGRESO');
      expect(movimientos.single.montoCentavos, 80000);
    },
  );

  test('/ingresos contra una sesión ya CERRADA da 409, no graba nada', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await cerrarSesion(
      db,
      sesionId: sesionId,
      usuarioId: usuarioId,
      efectivoContadoCentavos: 0,
      mpContadoCentavos: 0,
      lataContadoCentavos: 0,
    );

    final respuesta = await http.post(
      url('/ingresos'),
      headers: headers(),
      body: jsonEncode({
        'sesionCajaId': sesionId,
        'usuarioId': usuarioId,
        'montoCentavos': 50000,
        'medio': 'cajonNormal',
      }),
    );
    expect(respuesta.statusCode, 409);
    expect(await db.select(db.movimientosDeCaja).get(), isEmpty);
  });

  test('/ingresos con un "medio" inválido da 400', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

    final respuesta = await http.post(
      url('/ingresos'),
      headers: headers(),
      body: jsonEncode({
        'sesionCajaId': sesionId,
        'usuarioId': usuarioId,
        'montoCentavos': 50000,
        'medio': 'bitcoin',
      }),
    );
    expect(respuesta.statusCode, 400);
  });

  group('vender desde el celular', () {
    Future<int> insertarProducto({
      required String nombre,
      int? precioCentavos,
      int? costoCentavos,
      int? proveedorId,
      int stock = 20,
      bool esPesable = false,
      int? precioPorKiloCentavos,
      int? stockGramos,
      bool esVarios = false,
      String tipoCigarrillo = 'ninguno',
    }) {
      return db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: nombre,
          precioCentavos: Value(precioCentavos),
          costoCentavos: Value(costoCentavos),
          proveedorId: Value(proveedorId),
          stock: Value(stock),
          esPesable: Value(esPesable),
          precioPorKiloCentavos: Value(precioPorKiloCentavos),
          stockGramos: Value(stockGramos),
          esVarios: Value(esVarios),
          tipoCigarrillo: Value(tipoCigarrillo),
        ),
      );
    }

    Map<String, dynamic> lineaCoca(int productoId, {int cantidad = 1}) => lineaVentaAJson(
      LineaVentaPorUnidad(
        productoId: '$productoId',
        nombreProducto: 'Coca-Cola 500ml',
        proveedorId: null,
        cantidad: cantidad,
        precioUnitarioCentavos: 112000,
        costoUnitarioCentavos: 80000,
      ),
    );

    group('/ventas/buscar', () {
      test('sin stock, no aparece (Regla 8)', () async {
        await insertarProducto(nombre: 'Sin stock', precioCentavos: 1000, stock: 0);
        final conStockId = await insertarProducto(nombre: 'Con stock', precioCentavos: 1000);

        final respuesta = await http.get(url('/ventas/buscar?texto=stock'), headers: headers());
        final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
        final resultados = (cuerpo['resultados'] as List).cast<Map<String, dynamic>>();
        expect(resultados.map((p) => p['id']), [conStockId]);
      });

      test('"200 queso" separa los gramos y filtra a pesables', () async {
        await insertarProducto(
          nombre: 'Queso barra',
          esPesable: true,
          precioPorKiloCentavos: 800000,
          stockGramos: 5000,
        );
        await insertarProducto(nombre: 'Queso en fetas (no pesable)', precioCentavos: 1000);

        final respuesta = await http.get(
          url('/ventas/buscar?texto=200 queso'),
          headers: headers(),
        );
        final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
        expect(cuerpo['gramos'], 200);
        final resultados = (cuerpo['resultados'] as List).cast<Map<String, dynamic>>();
        expect(resultados, hasLength(1));
        expect(resultados.single['nombre'], 'Queso barra');
      });

      test('nunca devuelve "Varios" (fuera de alcance de esta versión)', () async {
        await insertarProducto(nombre: 'Varios', precioCentavos: 0, esVarios: true);

        final respuesta = await http.get(url('/ventas/buscar?texto=varios'), headers: headers());
        final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
        expect(cuerpo['resultados'], isEmpty);
      });
    });

    group('/ventas/calcular', () {
      test('el recargo de cigarrillos aparece con QR y desaparece en efectivo (Regla 6)', () async {
        final marlboroId = await insertarProducto(
          nombre: 'Marlboro',
          precioCentavos: 500000,
          tipoCigarrillo: 'atado',
        );
        final linea = lineaVentaAJson(
          LineaVentaPorUnidad(
            productoId: '$marlboroId',
            nombreProducto: 'Marlboro',
            proveedorId: null,
            cantidad: 1,
            tipoCigarrillo: TipoCigarrillo.atado,
            precioUnitarioCentavos: 500000,
          ),
        );

        final conQr = await http.post(
          url('/ventas/calcular'),
          headers: headers(),
          body: jsonEncode({'lineas': [linea], 'medio': 'virtual'}),
        );
        final conEfectivo = await http.post(
          url('/ventas/calcular'),
          headers: headers(),
          body: jsonEncode({'lineas': [linea], 'medio': 'efectivo'}),
        );

        expect((jsonDecode(conQr.body) as Map)['recargoCigarrillosCentavos'], greaterThan(0));
        expect((jsonDecode(conEfectivo.body) as Map)['recargoCigarrillosCentavos'], 0);
      });

      test(
        'round trip completo con el cliente real de la companion (Dueño, 2026-09-07: '
        '"revisa que la apk no agrega los recargos automáticos") — buscar, armar la línea '
        'como la arma el celular, y calcular',
        () async {
          await insertarProducto(nombre: 'Marlboro', precioCentavos: 500000, tipoCigarrillo: 'atado');
          final cliente = ClienteCompanion(DatosConexion(ip: '127.0.0.1', puerto: puerto, token: token));

          final busqueda = await cliente.buscarVenta('marlboro');
          expect(busqueda.resultados, hasLength(1));
          final resultado = lineaDesdeResultadoBusqueda(busqueda.resultados.single);
          expect(resultado.error, isNull);

          final totalQr = await cliente.calcularVenta(lineas: [resultado.linea!], medio: 'virtual');
          final totalEfectivo = await cliente.calcularVenta(lineas: [resultado.linea!], medio: 'efectivo');

          expect(totalQr.recargoCigarrillosCentavos, greaterThan(0));
          expect(totalEfectivo.recargoCigarrillosCentavos, 0);
        },
      );

      test('un "medio" inválido da 400', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final respuesta = await http.post(
          url('/ventas/calcular'),
          headers: headers(),
          body: jsonEncode({'lineas': [lineaCoca(cocaId)], 'medio': 'bitcoin'}),
        );
        expect(respuesta.statusCode, 400);
      });

      test(
        'aplica descuento por monto sobre el total (Regla 17 generalizada, Dueño 2026-09-10: '
        '"el carrito del celular no tiene para descuento")',
        () async {
          final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
          final respuesta = await http.post(
            url('/ventas/calcular'),
            headers: headers(),
            body: jsonEncode({
              'lineas': [lineaCoca(cocaId)],
              'medio': 'efectivo',
              'tipoDescuento': 'monto',
              'valorDescuento': 12000,
            }),
          );
          final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
          expect(cuerpo['descuentoCentavos'], 12000);
          // 112000 - 12000 = 100000, ya redondo, sin redondeo adicional.
          expect(cuerpo['totalCentavos'], 100000);
        },
      );

      test('aplica descuento por porcentaje sobre el total (subtotal + recargo, antes del redondeo)', () async {
        // `lineaCoca` manda siempre precioUnitarioCentavos: 112000 (línea
        // armada a mano, no lee lo que se le pasó a `insertarProducto`) —
        // el precio de acá tiene que coincidir con ese para que el test
        // pruebe lo que dice probar.
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final respuesta = await http.post(
          url('/ventas/calcular'),
          headers: headers(),
          body: jsonEncode({
            'lineas': [lineaCoca(cocaId)],
            'medio': 'efectivo',
            'tipoDescuento': 'porcentaje',
            'valorDescuento': 1000, // 10,00% (10000 = 100%)
          }),
        );
        final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
        // 10% de 112000 = 11200.
        expect(cuerpo['descuentoCentavos'], 11200);
        // 112000 - 11200 = 100800, redondea hacia arriba al paso de $100
        // (`pasoRedondeoCentavos` default = 10000) -> 110000.
        expect(cuerpo['totalCentavos'], 110000);
      });

      test('sin "tipoDescuento", no hay descuento (compatibilidad con clientes viejos)', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final respuesta = await http.post(
          url('/ventas/calcular'),
          headers: headers(),
          body: jsonEncode({'lineas': [lineaCoca(cocaId)], 'medio': 'efectivo'}),
        );
        final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
        expect(cuerpo['descuentoCentavos'], 0);
        // 112000 redondea hacia arriba al paso de $100 -> 120000.
        expect(cuerpo['totalCentavos'], 120000);
      });
    });

    group('encargues por apartado', () {
      test('apartar por HTTP baja el stock; el listado, las líneas y la entrega por /ventas/cobrar liberan lo apartado', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

        final alta = await http.post(
          url('/encargues'),
          headers: headers(),
          body: jsonEncode({
            'nombreCliente': 'María',
            'usuarioId': usuarioId,
            'lineas': [
              {'productoId': cocaId, 'cantidad': 3},
            ],
          }),
        );
        expect(alta.statusCode, 201);
        final id = (jsonDecode(alta.body) as Map)['id'] as int;
        expect((await (db.select(db.productos)..where((p) => p.id.equals(cocaId))).getSingle()).stock, 17);

        final lista = jsonDecode((await http.get(url('/encargues'), headers: headers())).body) as List;
        expect((lista.single as Map)['nombreCliente'], 'María');
        expect((lista.single as Map)['lineas'], ['3 × Coca-Cola 500ml']);

        final lineas = jsonDecode((await http.get(url('/encargues/$id/lineas'), headers: headers())).body) as List;
        final cobro = await http.post(
          url('/ventas/cobrar'),
          headers: headers(),
          body: jsonEncode({'lineas': lineas, 'medio': 'efectivo', 'sesionCajaId': sesionId, 'usuarioId': usuarioId, 'encargueId': id}),
        );
        expect(cobro.statusCode, 201);
        expect((await (db.select(db.productos)..where((p) => p.id.equals(cocaId))).getSingle()).stock, 17, reason: '20 - 3, una sola vez');
        expect(jsonDecode((await http.get(url('/encargues'), headers: headers())).body), isEmpty);
      });

      test('sin stock suficiente responde 409 con el producto y no aparta nada', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final alta = await http.post(
          url('/encargues'),
          headers: headers(),
          body: jsonEncode({
            'nombreCliente': 'María',
            'usuarioId': usuarioId,
            'lineas': [
              {'productoId': cocaId, 'cantidad': 999},
            ],
          }),
        );
        expect(alta.statusCode, 409);
        expect(jsonDecode(alta.body)['error'] ?? alta.body, contains('Coca-Cola 500ml'));
        expect((await (db.select(db.productos)..where((p) => p.id.equals(cocaId))).getSingle()).stock, 20);
      });

      test('cancelar devuelve el stock', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final alta = await http.post(
          url('/encargues'),
          headers: headers(),
          body: jsonEncode({
            'nombreCliente': 'María',
            'usuarioId': usuarioId,
            'lineas': [
              {'productoId': cocaId, 'cantidad': 3},
            ],
          }),
        );
        final id = (jsonDecode(alta.body) as Map)['id'] as int;
        final r = await http.post(url('/encargues/$id/cancelar'), headers: headers(), body: jsonEncode({'usuarioId': usuarioId}));
        expect(r.statusCode, 200);
        expect((await (db.select(db.productos)..where((p) => p.id.equals(cocaId))).getSingle()).stock, 20);
      });
    });

    group('deudas (encargue entregado sin cobrar)', () {
      test('entregar y anotar deuda, listarla y cobrarla en efectivo como una venta', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final alta = await http.post(
          url('/encargues'),
          headers: headers(),
          body: jsonEncode({
            'nombreCliente': 'María',
            'usuarioId': usuarioId,
            'lineas': [
              {'productoId': cocaId, 'cantidad': 3},
            ],
          }),
        );
        final id = (jsonDecode(alta.body) as Map)['id'] as int;

        final entrega = await http.post(url('/encargues/$id/deuda'), headers: headers(), body: jsonEncode({'usuarioId': usuarioId}));
        expect(entrega.statusCode, 200);
        expect((jsonDecode(entrega.body) as Map)['totalCentavos'], 336000);
        // Dos veces seguidas no duplica la deuda.
        final otra = await http.post(url('/encargues/$id/deuda'), headers: headers(), body: jsonEncode({'usuarioId': usuarioId}));
        expect(otra.statusCode, 409);

        final deudas = jsonDecode((await http.get(url('/deudas'), headers: headers())).body) as List;
        expect((deudas.single as Map)['nombreCliente'], 'María');
        expect((deudas.single as Map)['montoCentavos'], 336000);

        final cobro = await http.post(
          url('/deudas/$id/cobrar'),
          headers: headers(),
          body: jsonEncode({'usuarioId': usuarioId, 'sesionCajaId': sesionId, 'efectivo': true}),
        );
        expect(cobro.statusCode, 200);
        expect(jsonDecode((await http.get(url('/deudas'), headers: headers())).body), isEmpty);
        expect(await db.select(db.ventas).get(), hasLength(1));
      });
    });

    group('/ventas/cobrar (efectivo, sin posnet)', () {
      test('registra la venta y descuenta el stock', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

        final respuesta = await http.post(
          url('/ventas/cobrar'),
          headers: headers(),
          body: jsonEncode({
            'lineas': [lineaCoca(cocaId, cantidad: 2)],
            'medio': 'efectivo',
            'sesionCajaId': sesionId,
            'usuarioId': usuarioId,
          }),
        );
        expect(respuesta.statusCode, 201);
        final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
        expect(cuerpo['ventaId'], isNotNull);
        // Subtotal 224000 (2 × 112000) redondea hacia arriba a los $100 en
        // efectivo (Regla 5) -> 230000.
        expect(cuerpo['totalCentavos'], 230000);

        final producto = await (db.select(db.productos)..where((p) => p.id.equals(cocaId))).getSingle();
        expect(producto.stock, 18); // 20 - 2
      });

      test('contra una caja ya cerrada responde 409 y no graba nada (Fase 0.1)', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        await (db.update(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId)))
            .write(const SesionesDeCajaCompanion(estado: Value('CERRADA')));

        final respuesta = await http.post(
          url('/ventas/cobrar'),
          headers: headers(),
          body: jsonEncode({
            'lineas': [lineaCoca(cocaId)],
            'medio': 'efectivo',
            'sesionCajaId': sesionId,
            'usuarioId': usuarioId,
          }),
        );

        expect(respuesta.statusCode, 409);
        expect(await db.select(db.ventas).get(), isEmpty);
        expect((await (db.select(db.productos)..where((p) => p.id.equals(cocaId))).getSingle()).stock, 20);
      });

      test('el mismo cobro con la misma claveCobro devuelve la venta ya grabada, sin duplicar (Fase 0.2)', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final cuerpo = jsonEncode({
          'lineas': [lineaCoca(cocaId)],
          'medio': 'efectivo',
          'sesionCajaId': sesionId,
          'usuarioId': usuarioId,
          'claveCobro': 'intento-1',
        });

        final primera = await http.post(url('/ventas/cobrar'), headers: headers(), body: cuerpo);
        final repetida = await http.post(url('/ventas/cobrar'), headers: headers(), body: cuerpo);

        expect(primera.statusCode, 201);
        expect(repetida.statusCode, 200);
        expect((jsonDecode(repetida.body) as Map)['ventaId'], (jsonDecode(primera.body) as Map)['ventaId']);
        expect(await db.select(db.ventas).get(), hasLength(1));
        expect((await (db.select(db.productos)..where((p) => p.id.equals(cocaId))).getSingle()).stock, 19);
      });

      test('el descuento se aplica al registrar la venta, no solo al calcular', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

        final respuesta = await http.post(
          url('/ventas/cobrar'),
          headers: headers(),
          body: jsonEncode({
            'lineas': [lineaCoca(cocaId)],
            'medio': 'efectivo',
            'sesionCajaId': sesionId,
            'usuarioId': usuarioId,
            'tipoDescuento': 'monto',
            'valorDescuento': 20000,
          }),
        );
        expect(respuesta.statusCode, 201);
        final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
        // 112000 - 20000 = 92000, redondea hacia arriba al paso de $100
        // (`pasoRedondeoCentavos` default = 10000) -> 100000.
        expect(cuerpo['totalCentavos'], 100000);

        final venta = await (db.select(db.ventas)..where((v) => v.id.equals(cuerpo['ventaId'] as int))).getSingle();
        expect(venta.descuentoCentavos, 20000);
        expect(venta.totalCentavos, 100000);
      });

      test(
        '"cobrar a mano" (medio virtual con canal, sin pasar por Point) — Dueño: '
        '"para cargar las ventas de hoy y seguir cargando mientras tanto"',
        () async {
          final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
          final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

          final respuesta = await http.post(
            url('/ventas/cobrar'),
            headers: headers(),
            body: jsonEncode({
              'lineas': [lineaCoca(cocaId)],
              'medio': 'virtual',
              'canal': 'qr',
              'sesionCajaId': sesionId,
              'usuarioId': usuarioId,
            }),
          );
          expect(respuesta.statusCode, 201);
          final ventaId = (jsonDecode(respuesta.body) as Map)['ventaId'] as int;

          final pago = await (db.select(db.pagos)..where((p) => p.ventaId.equals(ventaId))).getSingle();
          expect(pago.canal, 'qr');
        },
      );
    });

    group(
      'GET /caja/estado — "arqueo" en vivo (Dueño, 2026-09-07: "saber que tal vamos '
      'en cualquier momento sin tener que contar a mano las ventas del día")',
      () {
        test('sin caja abierta, da 409', () async {
          final respuesta = await http.get(url('/caja/estado'), headers: headers());
          expect(respuesta.statusCode, 409);
        });

        test('efectivo/MP esperados y resumen por proveedor, sin pedir ningún contado', () async {
          final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 100000);
          final proveedorId = await db.into(db.proveedores).insert(
            ProveedoresCompanion.insert(codigo: 'CC', nombre: 'Coca-Cola Distribuidora'),
          );
          final cocaId = await insertarProducto(
            nombre: 'Coca-Cola 500ml',
            precioCentavos: 112000,
            costoCentavos: 80000,
            proveedorId: proveedorId,
          );
          // `lineaCoca` (de más arriba) hardcodea `proveedorId: null` — para
          // que entre en "por proveedor" hace falta una línea propia con el
          // proveedor de verdad (Regla 5, separación teórica por proveedor).
          final linea = lineaVentaAJson(
            LineaVentaPorUnidad(
              productoId: '$cocaId',
              nombreProducto: 'Coca-Cola 500ml',
              proveedorId: '$proveedorId',
              cantidad: 1,
              precioUnitarioCentavos: 112000,
              costoUnitarioCentavos: 80000,
            ),
          );

          await http.post(
            url('/ventas/cobrar'),
            headers: headers(),
            body: jsonEncode({
              'lineas': [linea],
              'medio': 'efectivo',
              'sesionCajaId': sesionId,
              'usuarioId': usuarioId,
            }),
          );

          final respuesta = await http.get(url('/caja/estado'), headers: headers());
          expect(respuesta.statusCode, 200);
          final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
          expect(cuerpo['sesionId'], sesionId);
          expect(cuerpo['cantidadVentas'], 1);
          // Subtotal 112000 redondea hacia arriba a los $100 en efectivo (Regla
          // 2) -> 120000 cobrados de verdad (el redondeo de 8000 ya está adentro,
          // no se suma de nuevo) -> 100000 + 120000 = 220000.
          expect(cuerpo['efectivoEsperadoCentavos'], 220000);
          expect(cuerpo['mpEsperadoCentavos'], 0);
          expect(cuerpo['totalCentavos'], 120000);
          final porProveedor = (cuerpo['porProveedor'] as List).cast<Map<String, dynamic>>();
          expect(porProveedor.single['nombreProveedor'], 'Coca-Cola Distribuidora');
          expect(porProveedor.single['costoRealCentavos'], 80000); // separación teórica, Regla 5
        });
      },
    );

    Future<int> servidorConMock(MockClient mock) async {
      final server = await iniciarServidorCompanion(db, puerto: 0, httpClientDePrueba: mock);
      addTearDown(server.close);
      return server.port;
    }

    group('cobro por terminal Point', () {
      MockClient clienteConEstado(String estadoConsulta) {
        return MockClient((request) async {
          if (request.method == 'POST' && request.url.path.contains('/orders') && !request.url.path.contains('cancel')) {
            return http.Response(jsonEncode({'id': 'orden-mp-1', 'status': 'created'}), 201);
          }
          return http.Response(jsonEncode({'id': 'orden-mp-1', 'status': estadoConsulta}), 200);
        });
      }

      test('/ventas/posnet/iniciar sin configurar la terminal da 400', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

        final respuesta = await http.post(
          url('/ventas/posnet/iniciar'),
          headers: headers(),
          body: jsonEncode({
            'lineas': [lineaCoca(cocaId)],
            'canal': 'qr',
            'sesionCajaId': sesionId,
          }),
        );
        expect(respuesta.statusCode, 400);
      });

      test('ciclo completo aprobado: iniciar, consultar estado y confirmar graban la venta', () async {
        await configurarMpAccessToken(db, 'TOKEN123');
        await configurarMpTerminalCobroId(db, 'N950NCC503383252');
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final puertoMock = await servidorConMock(clienteConEstado('processed'));
        Uri urlMock(String path) => Uri.parse('http://127.0.0.1:$puertoMock$path');

        final iniciado = await http.post(
          urlMock('/ventas/posnet/iniciar'),
          headers: headers(),
          body: jsonEncode({
            'lineas': [lineaCoca(cocaId)],
            'canal': 'qr',
            'sesionCajaId': sesionId,
          }),
        );
        expect(iniciado.statusCode, 201);
        final datosIniciado = jsonDecode(iniciado.body) as Map<String, dynamic>;

        final estado = await http.get(
          urlMock('/ventas/posnet/estado/${datosIniciado['ordenIdMp']}'),
          headers: headers(),
        );
        expect((jsonDecode(estado.body) as Map)['estado'], 'aprobada');

        final confirmado = await http.post(
          urlMock('/ventas/posnet/confirmar'),
          headers: headers(),
          body: jsonEncode({
            'lineas': [lineaCoca(cocaId)],
            'canal': 'qr',
            'sesionCajaId': sesionId,
            'usuarioId': usuarioId,
            'ordenPendienteId': datosIniciado['ordenPendienteId'],
          }),
        );
        expect(confirmado.statusCode, 201);
        final ventaId = (jsonDecode(confirmado.body) as Map)['ventaId'] as int;

        final orden = await (db.select(
          db.ordenesCobroPendientes,
        )..where((o) => o.id.equals(datosIniciado['ordenPendienteId'] as int))).getSingle();
        expect(orden.estado, 'aprobada');
        expect(orden.ventaId, ventaId);
      });

      test('rechazado: /ventas/posnet/no-aprobado cierra el ciclo sin venta', () async {
        await configurarMpAccessToken(db, 'TOKEN123');
        await configurarMpTerminalCobroId(db, 'N950NCC503383252');
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final pendiente = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 112000);

        final respuesta = await http.post(
          url('/ventas/posnet/no-aprobado'),
          headers: headers(),
          body: jsonEncode({'ordenPendienteId': pendiente.id, 'estado': 'rechazada'}),
        );
        expect(respuesta.statusCode, 200);

        final orden = await (db.select(db.ordenesCobroPendientes)..where((o) => o.id.equals(pendiente.id))).getSingle();
        expect(orden.estado, 'rechazada');
        expect(orden.ventaId, isNull);
      });

      test('cancelado: si Mercado Pago acepta el cancel, queda \'cancelada\'', () async {
        await configurarMpAccessToken(db, 'TOKEN123');
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final pendiente = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 112000);
        final puertoMock = await servidorConMock(
          MockClient((request) async => http.Response('{}', 200)),
        );
        Uri urlMock(String path) => Uri.parse('http://127.0.0.1:$puertoMock$path');

        final respuesta = await http.post(
          urlMock('/ventas/posnet/cancelar'),
          headers: headers(),
          body: jsonEncode({'ordenPendienteId': pendiente.id, 'ordenIdMp': 'orden-mp-1'}),
        );
        expect(respuesta.statusCode, 200);

        final orden = await (db.select(db.ordenesCobroPendientes)..where((o) => o.id.equals(pendiente.id))).getSingle();
        expect(orden.estado, 'cancelada');
      });

      test(
        'cancelado: si Mercado Pago ya no deja cancelar (409), la fila queda \'pendiente\' (nunca se asume)',
        () async {
          await configurarMpAccessToken(db, 'TOKEN123');
          final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
          final pendiente = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 112000);
          final puertoMock = await servidorConMock(
            MockClient(
              (request) async => http.Response(
                jsonEncode({
                  'errors': [
                    {'code': 'cannot_cancel_order', 'message': 'no se puede cancelar'},
                  ],
                }),
                409,
              ),
            ),
          );
          Uri urlMock(String path) => Uri.parse('http://127.0.0.1:$puertoMock$path');

          final respuesta = await http.post(
            urlMock('/ventas/posnet/cancelar'),
            headers: headers(),
            body: jsonEncode({'ordenPendienteId': pendiente.id, 'ordenIdMp': 'orden-mp-1'}),
          );
          expect(respuesta.statusCode, 502);

          final orden = await (db.select(db.ordenesCobroPendientes)..where((o) => o.id.equals(pendiente.id))).getSingle();
          expect(orden.estado, 'pendiente');
        },
      );
    });

    group('GET /ventas/<id>/detalle (Dueño, 2026-09-13: "poder ver un desglose de la venta")', () {
      test('trae líneas, desglose y total — mismo Ticket que la impresión', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final (ventaId, _) = await registrarVenta(
          db,
          venta: Venta(
            lineas: [
              LineaVentaPorUnidad(
                productoId: '$cocaId',
                nombreProducto: 'Coca-Cola 500ml',
                proveedorId: null,
                cantidad: 2,
                precioUnitarioCentavos: 112000,
              ),
            ],
          ),
          resultado: const ResultadoTotalVenta(
            subtotalCentavos: 224000,
            recargoCigarrillosCentavos: 0,
            redondeoCentavos: 500,
            totalCentavos: 224500,
          ),
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [],
        );

        final respuesta = await http.get(url('/ventas/$ventaId/detalle'), headers: headers());

        expect(respuesta.statusCode, 200);
        final j = jsonDecode(respuesta.body) as Map<String, dynamic>;
        expect(j['vendedor'], 'Dueño');
        final lineas = (j['lineas'] as List).cast<Map<String, dynamic>>();
        expect(lineas.single['nombreProducto'], 'Coca-Cola 500ml');
        expect(lineas.single['cantidad'], 2);
        expect(lineas.single['subtotalCentavos'], 224000);
        expect(j['redondeoCentavos'], 500);
        expect(j['totalCentavos'], 224500);
      });

      test('id inválido da 400, no 500', () async {
        final respuesta = await http.get(url('/ventas/nope/detalle'), headers: headers());
        expect(respuesta.statusCode, 400);
      });
    });

    group('/ventas/<id>/imprimir', () {
      test('sin configurar la terminal de impresión avisa qué hacer (sin token local ni cuenta vinculada)', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final (ventaId, _) = await registrarVenta(
          db,
          venta: Venta(
            lineas: [
              LineaVentaPorUnidad(
                productoId: '$cocaId',
                nombreProducto: 'Coca-Cola 500ml',
                proveedorId: null,
                cantidad: 1,
                precioUnitarioCentavos: 112000,
              ),
            ],
          ),
          resultado: const ResultadoTotalVenta(
            subtotalCentavos: 112000,
            recargoCigarrillosCentavos: 0,
            redondeoCentavos: 0,
            totalCentavos: 112000,
          ),
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [],
        );

        final respuesta = await http.post(url('/ventas/$ventaId/imprimir'), headers: headers());
        expect(respuesta.statusCode, 502);
        expect(respuesta.body, contains('horsepos.com/negocio'));
      });

      test('enviada la configuración, manda el ticket a la terminal', () async {
        await configurarMpAccessToken(db, 'TOKEN123');
        await configurarMpTerminalId(db, 'N950NCC503383252');
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final (ventaId, _) = await registrarVenta(
          db,
          venta: Venta(
            lineas: [
              LineaVentaPorUnidad(
                productoId: '$cocaId',
                nombreProducto: 'Coca-Cola 500ml',
                proveedorId: null,
                cantidad: 1,
                precioUnitarioCentavos: 112000,
              ),
            ],
          ),
          resultado: const ResultadoTotalVenta(
            subtotalCentavos: 112000,
            recargoCigarrillosCentavos: 0,
            redondeoCentavos: 0,
            totalCentavos: 112000,
          ),
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [],
        );
        var seLlamo = false;
        final puertoMock = await servidorConMock(
          MockClient((request) async {
            seLlamo = true;
            return http.Response('{}', 200);
          }),
        );
        Uri urlMock(String path) => Uri.parse('http://127.0.0.1:$puertoMock$path');

        final respuesta = await http.post(urlMock('/ventas/$ventaId/imprimir'), headers: headers());
        expect(respuesta.statusCode, 200);
        expect(seLlamo, isTrue);
      });
    });

    group('/ventas/buscar con exigirStock=false (carga histórica)', () {
      test('sin exigirStock, un producto en 0 igual aparece', () async {
        await insertarProducto(nombre: 'Vendido en su momento', precioCentavos: 1000, stock: 0);

        final conFiltro = await http.get(url('/ventas/buscar?texto=vendido'), headers: headers());
        expect((jsonDecode(conFiltro.body) as Map)['resultados'], isEmpty);

        final sinFiltro = await http.get(
          url('/ventas/buscar?texto=vendido&exigirStock=false'),
          headers: headers(),
        );
        expect((jsonDecode(sinFiltro.body) as Map)['resultados'], hasLength(1));
      });
    });

    group('carga histórica (Dueño, 2026-09-07: "se le pone la fecha... no descuentan stock")', () {
      test(
        'round trip completo con el cliente real (Dueño: "revisa que la apk no agrega los recargos '
        'automáticos... revisa que esté bien en carrito y en el histórico") — el recargo de '
        'cigarrillos por Mercado Pago queda en el total grabado',
        () async {
          await insertarProducto(nombre: 'Marlboro', precioCentavos: 500000, tipoCigarrillo: 'atado');
          final cliente = ClienteCompanion(DatosConexion(ip: '127.0.0.1', puerto: puerto, token: token));

          final busqueda = await cliente.buscarVenta('marlboro', exigirStock: false);
          final resultado = lineaDesdeResultadoBusqueda(busqueda.resultados.single);

          final sesionId = await cliente.guardarDiaHistorico(
            fecha: DateTime(2026, 8, 15),
            usuarioId: usuarioId,
            ventas: [
              VentaHistoricaPendienteCompanion(lineas: [resultado.linea!], medio: 'virtual'),
            ],
          );

          final venta = await (db.select(
            db.ventas,
          )..where((v) => v.sesionCajaId.equals(sesionId))).getSingle();
          expect(venta.recargoCigarrillosCentavos, greaterThan(0));
          expect(venta.totalCentavos, venta.subtotalCentavos + venta.recargoCigarrillosCentavos);
        },
      );

      test('graba las ventas del día bajo esa fecha, sin tocar el stock actual', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000, stock: 3);
        final fecha = DateTime(2026, 8, 15, 14, 30);

        final respuesta = await http.post(
          url('/historico/dia'),
          headers: headers(),
          body: jsonEncode({
            'fecha': fecha.toIso8601String(),
            'usuarioId': usuarioId,
            'ventas': [
              {
                'lineas': [lineaCoca(cocaId, cantidad: 2)],
                'medio': 'efectivo',
              },
              {
                'lineas': [lineaCoca(cocaId)],
                'medio': 'virtual',
              },
            ],
          }),
        );
        expect(respuesta.statusCode, 201);
        final sesionId = (jsonDecode(respuesta.body) as Map)['sesionId'] as int;

        final sesion = await (db.select(
          db.sesionesDeCaja,
        )..where((s) => s.id.equals(sesionId))).getSingle();
        expect(sesion.estado, 'CERRADA'); // se cierra sola, con arqueo automático
        expect(sesion.fechaApertura, fecha);
        expect(sesion.diferenciaCentavos, 0);

        final ventas = await (db.select(
          db.ventas,
        )..where((v) => v.sesionCajaId.equals(sesionId))).get();
        expect(ventas, hasLength(2));

        // El stock del producto sigue como estaba: esta mercadería ya se
        // descontó en su momento (Convención de la carga histórica).
        final producto = await (db.select(db.productos)..where((p) => p.id.equals(cocaId))).getSingle();
        expect(producto.stock, 3);
      });

      test('una venta mixta reparte el pago entre efectivo y virtual', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);

        final respuesta = await http.post(
          url('/historico/dia'),
          headers: headers(),
          body: jsonEncode({
            'fecha': DateTime(2026, 8, 15).toIso8601String(),
            'usuarioId': usuarioId,
            'ventas': [
              {
                'lineas': [lineaCoca(cocaId)],
                'medio': 'mixto',
                'montoEfectivoMixtoCentavos': 50000,
              },
            ],
          }),
        );
        expect(respuesta.statusCode, 201);
        final sesionId = (jsonDecode(respuesta.body) as Map)['sesionId'] as int;

        final ventaId =
            (await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(sesionId))).getSingle()).id;
        final pagos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(ventaId))).get();
        expect(pagos, hasLength(2));
        // Subtotal 112000 con una parte en efectivo redondea hacia arriba a
        // los $100 (Regla 5) -> 120000; el efectivo se respeta tal cual se
        // cargó, el resto (virtual) es lo que falta hasta el total.
        expect(pagos.map((p) => p.montoCentavos), containsAll([50000, 70000]));
      });

      test('un "medio" inválido en cualquier venta del día no graba nada (todo o nada)', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final antes = await (db.select(db.sesionesDeCaja)).get();

        final respuesta = await http.post(
          url('/historico/dia'),
          headers: headers(),
          body: jsonEncode({
            'fecha': DateTime(2026, 8, 15).toIso8601String(),
            'usuarioId': usuarioId,
            'ventas': [
              {
                'lineas': [lineaCoca(cocaId)],
                'medio': 'invalido',
              },
            ],
          }),
        );

        expect(respuesta.statusCode, 400);
        final despues = await (db.select(db.sesionesDeCaja)).get();
        expect(despues.length, antes.length); // ninguna sesión nueva quedó a medio armar
      });
    });

    group('ver y editar días históricos (Dueño, 2026-09-07: "dejame verlos y editarlos")', () {
      Future<int> cargarDiaDeEjemplo({required int cocaId, int cantidad = 1}) async {
        final respuesta = await http.post(
          url('/historico/dia'),
          headers: headers(),
          body: jsonEncode({
            'fecha': DateTime(2026, 8, 15).toIso8601String(),
            'usuarioId': usuarioId,
            'ventas': [
              {
                'lineas': [lineaCoca(cocaId, cantidad: cantidad)],
                'medio': 'efectivo',
              },
            ],
          }),
        );
        return (jsonDecode(respuesta.body) as Map)['sesionId'] as int;
      }

      test('/historico/dias lista solo los días cargados así, no cualquier sesión', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await cargarDiaDeEjemplo(cocaId: cocaId);
        await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0); // sesión real, no histórica

        final respuesta = await http.get(url('/historico/dias'), headers: headers());
        final dias = (jsonDecode(respuesta.body) as List).cast<Map<String, dynamic>>();
        expect(dias, hasLength(1));
        expect(dias.single['sesionId'], sesionId);
        expect(dias.single['cantidadVentas'], 1);
      });

      test(
        '/historico/dias/<id>/resumen agrupa por medio de pago y por proveedor '
        '(Dueño, 2026-09-07: "un resumen de lo vendido por medio de pago, por proveedor, y la separación teórica")',
        () async {
          final proveedorId =
              (await (db.select(db.proveedores)..where((p) => p.codigo.equals('F'))).getSingle()).id;
          final fernetId = await insertarProducto(
            nombre: 'Fernet Branca',
            precioCentavos: 1200000,
            costoCentavos: 800000,
            proveedorId: proveedorId,
          );
          final lineaFernet = lineaVentaAJson(
            LineaVentaPorUnidad(
              productoId: '$fernetId',
              nombreProducto: 'Fernet Branca',
              proveedorId: '$proveedorId',
              cantidad: 1,
              precioUnitarioCentavos: 1200000,
              costoUnitarioCentavos: 800000,
            ),
          );

          final carga = await http.post(
            url('/historico/dia'),
            headers: headers(),
            body: jsonEncode({
              'fecha': DateTime(2026, 8, 15).toIso8601String(),
              'usuarioId': usuarioId,
              'ventas': [
                {
                  'lineas': [lineaFernet],
                  'medio': 'efectivo',
                },
                {
                  'lineas': [lineaFernet],
                  'medio': 'virtual',
                },
              ],
            }),
          );
          final sesionId = (jsonDecode(carga.body) as Map)['sesionId'] as int;

          final respuesta = await http.get(url('/historico/dias/$sesionId/resumen'), headers: headers());
          final resumen = jsonDecode(respuesta.body) as Map<String, dynamic>;

          expect(resumen['totalCentavos'], 2400000);
          expect(resumen['efectivoCentavos'], 1200000);
          expect(resumen['mercadoPagoCentavos'], 1200000);

          final porProveedor = (resumen['porProveedor'] as List).cast<Map<String, dynamic>>();
          expect(porProveedor, hasLength(1));
          expect(porProveedor.single['proveedorId'], proveedorId);
          expect(porProveedor.single['vendidoCentavos'], 2400000);
          expect(porProveedor.single['costoRealCentavos'], 1600000); // separación teórica (Regla 5)
          expect(porProveedor.single['gananciaCentavos'], 800000);
          expect(resumen['cigarrillosListaCentavos'], 0);
          expect(resumen['productosSinDatos'], isEmpty);
        },
      );

      test(
        '/historico/dias/<id>/resumen muestra los cigarrillos aparte y el detalle de lo '
        'sin proveedor/costo (Dueño, 2026-09-07: "el arqueo muestra solamente una fracción... '
        'decime que no tiene costo o proveedor")',
        () async {
          final marlboroId = await insertarProducto(
            nombre: 'Marlboro',
            precioCentavos: 500000,
            tipoCigarrillo: 'atado',
          );
          final lineaMarlboro = lineaVentaAJson(
            LineaVentaPorUnidad(
              productoId: '$marlboroId',
              nombreProducto: 'Marlboro',
              proveedorId: null,
              cantidad: 1,
              tipoCigarrillo: TipoCigarrillo.atado,
              precioUnitarioCentavos: 500000,
            ),
          );
          final sinDatosId = await insertarProducto(nombre: 'Producto nuevo', precioCentavos: 300000);
          final lineaSinDatos = lineaVentaAJson(
            LineaVentaPorUnidad(
              productoId: '$sinDatosId',
              nombreProducto: 'Producto nuevo',
              proveedorId: null,
              cantidad: 1,
              precioUnitarioCentavos: 300000,
            ),
          );

          final carga = await http.post(
            url('/historico/dia'),
            headers: headers(),
            body: jsonEncode({
              'fecha': DateTime(2026, 8, 16).toIso8601String(),
              'usuarioId': usuarioId,
              'ventas': [
                {
                  'lineas': [lineaMarlboro],
                  'medio': 'efectivo',
                },
                {
                  'lineas': [lineaSinDatos],
                  'medio': 'efectivo',
                },
              ],
            }),
          );
          final sesionId = (jsonDecode(carga.body) as Map)['sesionId'] as int;

          final respuesta = await http.get(url('/historico/dias/$sesionId/resumen'), headers: headers());
          final resumen = jsonDecode(respuesta.body) as Map<String, dynamic>;

          // El cigarrillo nunca entra a "por proveedor" (Regla 6) — acá tiene
          // que aparecer aparte, a precio de lista.
          expect(resumen['cigarrillosListaCentavos'], 500000);
          expect(resumen['porProveedor'], isEmpty);

          final productosSinDatos = (resumen['productosSinDatos'] as List).cast<Map<String, dynamic>>();
          expect(productosSinDatos, hasLength(1)); // el cigarrillo no cuenta acá tampoco
          expect(productosSinDatos.single['nombreProducto'], 'Producto nuevo');
          expect(productosSinDatos.single['vendidoCentavos'], 300000);
          expect(productosSinDatos.single['sinProveedor'], isTrue);
          expect(productosSinDatos.single['sinCosto'], isTrue);
        },
      );

      test('/historico/dias/<id> trae el detalle de sus ventas', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await cargarDiaDeEjemplo(cocaId: cocaId, cantidad: 2);

        final respuesta = await http.get(url('/historico/dias/$sesionId'), headers: headers());
        final ventas = (jsonDecode(respuesta.body) as List).cast<Map<String, dynamic>>();
        expect(ventas, hasLength(1));
        expect(ventas.single['medioResumen'], 'efectivo');
        expect(ventas.single['detalle'], contains('Coca-Cola 500ml x2'));
      });

      test('agregar más ventas a un día ya cargado (sin crear una sesión nueva)', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await cargarDiaDeEjemplo(cocaId: cocaId);

        final respuesta = await http.post(
          url('/historico/dias/$sesionId/agregar'),
          headers: headers(),
          body: jsonEncode({
            'usuarioId': usuarioId,
            'ventas': [
              {
                'lineas': [lineaCoca(cocaId, cantidad: 3)],
                'medio': 'virtual',
              },
            ],
          }),
        );
        expect(respuesta.statusCode, 200);

        final ventas = await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(sesionId))).get();
        expect(ventas, hasLength(2));
        final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
        expect(sesion.diferenciaCentavos, 0); // el resumen se recalculó, sigue en cero
      });

      test('borrar una venta puntual del día no toca el stock y recalcula el resumen', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000, stock: 5);
        final sesionId = await cargarDiaDeEjemplo(cocaId: cocaId);
        final ventaId =
            (await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(sesionId))).getSingle()).id;

        final respuesta = await http.delete(
          url('/historico/dias/$sesionId/ventas/$ventaId'),
          headers: headers(),
          body: jsonEncode({'usuarioId': usuarioId}),
        );
        expect(respuesta.statusCode, 200);

        final ventas = await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(sesionId))).get();
        expect(ventas, isEmpty);
        final producto = await (db.select(db.productos)..where((p) => p.id.equals(cocaId))).getSingle();
        expect(producto.stock, 5); // nunca lo tocó, no hay nada que revertir
        final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
        expect(sesion.diferenciaCentavos, 0);
      });

      test('borrar el día completo saca la sesión y todas sus ventas', () async {
        final cocaId = await insertarProducto(nombre: 'Coca-Cola 500ml', precioCentavos: 112000);
        final sesionId = await cargarDiaDeEjemplo(cocaId: cocaId);

        final respuesta = await http.delete(url('/historico/dias/$sesionId'), headers: headers());
        expect(respuesta.statusCode, 200);

        final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingleOrNull();
        expect(sesion, isNull);
      });
    });
  });

  test('/companion/version sin ningún .apk publicado por el script, se cae a la versión de la app de escritorio', () async {
    final respuesta = await http.get(url('/companion/version'), headers: headers());
    expect(respuesta.statusCode, 200);
    final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
    expect(cuerpo['version'], '1.0.0');
    expect(cuerpo['buildNumber'], '2');
  });

  test(
    '/companion/version con el archivo publicado por el script, ignora la versión de la app de escritorio '
    '(Dueño, 2026-09-07: "no hay manera de lanzar actualizaciones sin reiniciar la app desktop")',
    () async {
      final archivo = File('${carpetaDocumentosDePrueba.path}/la_plazoleta_companion.version');
      await archivo.writeAsString('1.0.0+2020');

      final respuesta = await http.get(url('/companion/version'), headers: headers());
      final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
      expect(cuerpo['version'], '1.0.0');
      expect(cuerpo['buildNumber'], '2020');
    },
  );

  test('/companion/apk sirve el .apk publicado, si hay uno', () async {
    final archivo = File('${carpetaDocumentosDePrueba.path}/la_plazoleta_companion.apk');
    await archivo.writeAsBytes([0x50, 0x4B, 0x03, 0x04]); // encabezado real de un .zip/.apk

    final respuesta = await http.get(url('/companion/apk'), headers: headers());

    expect(respuesta.statusCode, 200);
    expect(respuesta.headers['content-type'], 'application/vnd.android.package-archive');
    expect(respuesta.bodyBytes, [0x50, 0x4B, 0x03, 0x04]);
  });

  test('/companion/apk sin ningún .apk publicado todavía da 404, no 500', () async {
    final respuesta = await http.get(url('/companion/apk'), headers: headers());
    expect(respuesta.statusCode, 404);
  });

  test(
    '/companion/apk anda SIN token (Dueño, 2026-09-07: "escaneando el QR lo ponga para descargar") '
    '— un celular nuevo sin la companion instalada no tiene forma de mandar el header',
    () async {
      final archivo = File('${carpetaDocumentosDePrueba.path}/la_plazoleta_companion.apk');
      await archivo.writeAsBytes([0x50, 0x4B, 0x03, 0x04]);

      final respuesta = await http.get(url('/companion/apk'), headers: headers(conToken: false));

      expect(respuesta.statusCode, 200);
      expect(respuesta.bodyBytes, [0x50, 0x4B, 0x03, 0x04]);
    },
  );

  group(
    'GET /historial/ventas (Dueño, 2026-09-07: "hagamos la sección de reportes... con el '
    'historial de ventas... que sea filtrable")',
    () {
      Future<int> crearVenta({required DateTime fecha, required int totalCentavos, required int medioPagoId}) async {
        // Una sola sesión para las ventas fabricadas de este grupo (no le
        // importa a qué sesión queden atadas) — desde que `abrirSesion`
        // bloquea en vez de unirse en silencio (El dueño, 2026-09-19), un
        // segundo llamado con una ya abierta tira, así que se reusa la
        // existente si la hay.
        final sesionId = (await sesionAbierta(db))?.id ??
            await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            fecha: Value(fecha),
            subtotalCentavos: totalCentavos,
            totalCentavos: totalCentavos,
          ),
        );
        await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Coca-Cola 500ml',
            cantidad: const Value(1),
            precioUnitarioCentavos: totalCentavos,
          ),
        );
        await db.into(db.pagos).insert(
          PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioPagoId, montoCentavos: totalCentavos),
        );
        return ventaId;
      }

      test('filtra por rango de fechas', () async {
        final medioEfectivoId =
            (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
        await crearVenta(fecha: DateTime(2026, 8, 1), totalCentavos: 10000, medioPagoId: medioEfectivoId);
        await crearVenta(fecha: DateTime(2026, 8, 15), totalCentavos: 20000, medioPagoId: medioEfectivoId);

        final respuesta = await http.get(
          url('/historial/ventas?desde=2026-08-15T00:00:00&hasta=2026-08-16T00:00:00'),
          headers: headers(),
        );
        expect(respuesta.statusCode, 200);
        final ventas = (jsonDecode(respuesta.body) as List).cast<Map<String, dynamic>>();
        expect(ventas, hasLength(1));
        expect(ventas.single['totalCentavos'], 20000);
        expect(ventas.single['medio'], 'efectivo');
        expect(ventas.single['detalle'], 'Coca-Cola 500ml x1');
      });

      test('sin "desde"/"hasta" da 400', () async {
        final respuesta = await http.get(url('/historial/ventas'), headers: headers());
        expect(respuesta.statusCode, 400);
      });

      test('"medio" inválido da 400', () async {
        final respuesta = await http.get(
          url('/historial/ventas?desde=2026-08-15T00:00:00&hasta=2026-08-16T00:00:00&medio=bitcoin'),
          headers: headers(),
        );
        expect(respuesta.statusCode, 400);
      });

      test('trae "anulada" y "sesionAbierta" para que el celular sepa si puede eliminarla', () async {
        final medioEfectivoId =
            (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
        await crearVenta(fecha: DateTime(2026, 8, 20), totalCentavos: 10000, medioPagoId: medioEfectivoId);

        final respuesta = await http.get(
          url('/historial/ventas?desde=2026-08-20T00:00:00&hasta=2026-08-21T00:00:00'),
          headers: headers(),
        );
        final venta = (jsonDecode(respuesta.body) as List).cast<Map<String, dynamic>>().single;
        expect(venta['anulada'], isFalse);
        expect(venta['sesionAbierta'], isTrue); // crearVenta no cierra la sesión que abre
      });
    },
  );

  group('POST /ventas/<id>/anular (Dueño, 2026-09-13: eliminar una venta desde el celular)', () {
    Future<int> crearVentaConStock({required int stockInicial}) async {
      final productoId = await db.into(db.productos).insert(
        ProductosCompanion.insert(nombre: 'Coca-Cola', precioCentavos: const Value(112000), stock: Value(stockInicial)),
      );
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      final medioEfectivoId =
          (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
      final venta = Venta(lineas: [lineaDesdeProducto((await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle()), cantidad: 2)]);
      final resultado = calcularTotalVenta(
        venta: venta,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 0, atadoAdicionalCentavos: 0),
        pasoRedondeoCentavos: 100,
      );
      final (ventaId, _) = await registrarVenta(
        db,
        venta: venta,
        resultado: resultado,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        pagos: [PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultado.totalCentavos, esEfectivo: true)],
      );
      return ventaId;
    }

    test('revierte el stock y marca la venta como anulada', () async {
      final ventaId = await crearVentaConStock(stockInicial: 20);

      final respuesta = await http.post(
        url('/ventas/$ventaId/anular'),
        headers: headers(),
        body: jsonEncode({'usuarioId': usuarioId, 'motivo': 'El cliente se arrepintió'}),
      );

      expect(respuesta.statusCode, 200);
      final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
      expect(venta.anuladaEn, isNotNull);
      expect(venta.motivoAnulacion, 'El cliente se arrepintió');
    });

    test('sin "motivo" da 400, no 500', () async {
      final ventaId = await crearVentaConStock(stockInicial: 20);

      final respuesta = await http.post(
        url('/ventas/$ventaId/anular'),
        headers: headers(),
        body: jsonEncode({'usuarioId': usuarioId}),
      );

      expect(respuesta.statusCode, 400);
    });

    test('con la sesión ya cerrada da 400, no 500 (evita descuadrar un cierre ya arqueado)', () async {
      final ventaId = await crearVentaConStock(stockInicial: 20);
      final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
      await cerrarSesion(
        db,
        sesionId: venta.sesionCajaId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );

      final respuesta = await http.post(
        url('/ventas/$ventaId/anular'),
        headers: headers(),
        body: jsonEncode({'usuarioId': usuarioId, 'motivo': 'Tarde'}),
      );

      expect(respuesta.statusCode, 400);
    });
  });

  group(
    'GET /sesiones/cerradas (Dueño, 2026-09-13: "quiero la pantalla nueva de cierres con caché offline")',
    () {
      test('trae una sesión real cerrada con su arqueo completo', () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 100000);
        await cerrarSesion(
          db,
          sesionId: sesionId,
          usuarioId: usuarioId,
          efectivoContadoCentavos: 100000,
          mpContadoCentavos: 0,
          lataContadoCentavos: 0,
        );

        final respuesta = await http.get(url('/sesiones/cerradas'), headers: headers());
        expect(respuesta.statusCode, 200);
        final dias = (jsonDecode(respuesta.body) as List).cast<Map<String, dynamic>>();
        expect(dias, hasLength(1));
        expect(dias.single['sesionId'], sesionId);
        expect(dias.single['nombreEmpleado'], 'Dueño');
        expect(dias.single['efectivoContadoCentavos'], 100000);
        expect(dias.single['efectivoEsperadoCentavos'], 100000);
        expect(dias.single['diferenciaCentavos'], 0);
      });

      test('excluye los días de carga histórica — nunca tuvieron un arqueo real', () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        await cerrarSesion(
          db,
          sesionId: sesionId,
          usuarioId: usuarioId,
          efectivoContadoCentavos: 0,
          mpContadoCentavos: 0,
          lataContadoCentavos: 0,
          nota: notaCargaHistorica,
        );

        final respuesta = await http.get(url('/sesiones/cerradas'), headers: headers());
        expect(jsonDecode(respuesta.body), isEmpty);
      });

      test('no trae la sesión todavía abierta', () async {
        await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

        final respuesta = await http.get(url('/sesiones/cerradas'), headers: headers());
        expect(jsonDecode(respuesta.body), isEmpty);
      });
    },
  );

  test('escucha en 0.0.0.0, no solo en localhost (necesario para que el celular lo alcance)', () async {
    final server = await iniciarServidorCompanion(db, puerto: 0);
    addTearDown(server.close);
    expect(server.address.address, anyOf('0.0.0.0', '::'));
  });

  test('direccionesIpLocales devuelve al menos una IP que no es loopback', () async {
    final direcciones = await direccionesIpLocales();
    for (final d in direcciones) {
      expect(d, isNot('127.0.0.1'));
    }
  });

  group('ipRecomendada', () {
    test('vacía da null', () {
      expect(ipRecomendada([]), isNull);
    });

    test('prefiere un rango privado (192.168.x.x) sobre uno que no lo es', () {
      expect(ipRecomendada(['203.0.113.5', '192.168.1.4']), '192.168.1.4');
    });

    test('reconoce los tres rangos privados (10.x, 172.16-31.x, 192.168.x)', () {
      expect(ipRecomendada(['10.0.0.5']), '10.0.0.5');
      expect(ipRecomendada(['172.20.1.1']), '172.20.1.1');
      expect(ipRecomendada(['172.40.1.1']), '172.40.1.1'); // fuera de 16-31: no es "privada" para esta heurística
    });

    test('sin ninguna privada, devuelve la primera igual', () {
      expect(ipRecomendada(['203.0.113.5', '198.51.100.9']), '203.0.113.5');
    });
  });

  group('/sync/cambios', () {
    test('GET exige "tabla" y "desde"', () async {
      final sinNada = await http.get(url('/sync/cambios'), headers: headers());
      expect(sinNada.statusCode, 400);

      final sinDesde = await http.get(url('/sync/cambios?tabla=categorias'), headers: headers());
      expect(sinDesde.statusCode, 400);
    });

    test('GET con una tabla no sincronizable da 400, no un 500 crudo', () async {
      // `cajas` sigue afuera de `tablasSincronizables` a propósito (2 filas
      // fijas, nunca las crea un dispositivo distinto — `usuarios` SÍ entró
      // a partir de la migración v31→v32, ya no sirve como ejemplo acá).
      final respuesta = await http.get(
        url('/sync/cambios?tabla=cajas&desde=0'),
        headers: headers(),
      );
      expect(respuesta.statusCode, 400);
    });

    test('GET trae solo filas con identidad de sincronización, y el cursor sube', () async {
      final id = await crearCategoria(db, 'Fiambres importados');

      final respuesta = await http.get(
        url('/sync/cambios?tabla=categorias&desde=0'),
        headers: headers(),
      );
      expect(respuesta.statusCode, 200);
      final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
      final filas = (cuerpo['filas'] as List).cast<Map<String, dynamic>>();

      // Las 11 categorías fijas del seed (Regla 14) no tienen global_id
      // todavía — solo la que se acaba de crear entra en la respuesta.
      expect(filas.length, 1);
      expect(filas.single['id'], id);
      expect(filas.single['nombre'], 'Fiambres importados');
      expect(filas.single['global_id'], isNotNull);
      expect(cuerpo['cursor'], greaterThan(0));
    });

    test('POST aplica filas entrantes — misma fila dos veces no duplica', () async {
      final id = await crearCategoria(db, 'Fiambres importados');
      final pull = await http.get(
        url('/sync/cambios?tabla=categorias&desde=0'),
        headers: headers(),
      );
      final filas = (jsonDecode(pull.body) as Map)['filas'] as List;
      final globalId = (filas.single as Map)['global_id'] as String;

      // Simula el celular mandando de vuelta la misma foto que acaba de
      // recibir (ej. tras un pull-to-refresh sin haber cambiado nada) — no
      // tiene que insertar una fila nueva, ya existe por `global_id`.
      final post = await http.post(
        url('/sync/cambios'),
        headers: headers(),
        body: jsonEncode({'tabla': 'categorias', 'filas': filas}),
      );
      expect(post.statusCode, 200);

      final categorias = await (db.select(
        db.categorias,
      )..where((c) => c.globalId.equals(globalId))).get();
      expect(categorias.length, 1);
      expect(categorias.single.id, id);
    });

    test('POST con una tabla desconocida da 400', () async {
      final respuesta = await http.post(
        url('/sync/cambios'),
        headers: headers(),
        body: jsonEncode({
          'tabla': 'tabla_inventada',
          'filas': [],
        }),
      );
      expect(respuesta.statusCode, 400);
    });

    test('sin token da 401, igual que cualquier otra ruta', () async {
      final respuesta = await http.get(
        url('/sync/cambios?tabla=categorias&desde=0'),
        headers: headers(conToken: false),
      );
      expect(respuesta.statusCode, 401);
    });
  });

  group(
    'Configuración desde la companion (Dueño, 2026-09-19: "que se puedan modificar las reglas del negocio... desde el celular")',
    () {
      test('GET /configuracion trae los defaults de fábrica recién sembrados', () async {
        final respuesta = await http.get(url('/configuracion'), headers: headers());
        expect(respuesta.statusCode, 200);
        final j = jsonDecode(respuesta.body) as Map<String, dynamic>;
        expect(j['recargoPrimerAtadoCentavos'], 30000);
        expect(j['pasoRedondeoCentavos'], 10000);
        expect(j.containsKey('productoVueltoId'), isFalse); // null se omite
      });

      test('PUT /configuracion/recargo-cigarrillos actualiza los tres montos', () async {
        final respuesta = await http.put(
          url('/configuracion/recargo-cigarrillos'),
          headers: headers(),
          body: jsonEncode({
            'primerAtadoCentavos': 40000,
            'atadoAdicionalCentavos': 15000,
            'sueltoCentavos': 6000,
          }),
        );
        expect(respuesta.statusCode, 200);
        final fila = await db.select(db.configuracionNegocioTabla).getSingle();
        expect(fila.recargoPrimerAtadoCentavos, 40000);
        expect(fila.recargoSueltoCentavos, 6000);
      });

      test('PUT /configuracion/redondeo y /producto-vuelto actualizan cada uno el suyo', () async {
        final productoId = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Caramelo', precioCentavos: const Value(500)),
        );

        await http.put(
          url('/configuracion/redondeo'),
          headers: headers(),
          body: jsonEncode({'montoCentavos': 5000}),
        );
        await http.put(
          url('/configuracion/producto-vuelto'),
          headers: headers(),
          body: jsonEncode({'productoId': productoId}),
        );

        final fila = await db.select(db.configuracionNegocioTabla).getSingle();
        expect(fila.pasoRedondeoCentavos, 5000);
        expect(fila.productoVueltoId, productoId);
      });

      test('PUT /categorias/<id>/markup actualiza solo esa categoría (Regla 14, informativo)', () async {
        final categoria = (await db.select(db.categorias).get()).first;

        final respuesta = await http.put(
          url('/categorias/${categoria.id}/markup'),
          headers: headers(),
          body: jsonEncode({'markupBp': 8000}),
        );
        expect(respuesta.statusCode, 200);
        final actualizada = await (db.select(
          db.categorias,
        )..where((c) => c.id.equals(categoria.id))).getSingle();
        expect(actualizada.markupDefaultBp, 8000);
      });

      test('GET /medios-pago trae los dos medios fijos', () async {
        final respuesta = await http.get(url('/medios-pago'), headers: headers());
        expect(respuesta.statusCode, 200);
        final medios = (jsonDecode(respuesta.body) as List).cast<Map<String, dynamic>>();
        expect(medios, hasLength(2));
        expect(medios.any((m) => m['nombre'] == 'Efectivo' && m['esEfectivo'] == true), isTrue);
      });

      test('PUT /medios-pago/<id> renombra y desactiva — sin alta de medios nuevos', () async {
        final efectivo = await (db.select(
          db.mediosDePago,
        )..where((m) => m.esEfectivo.equals(true))).getSingle();

        await http.put(
          url('/medios-pago/${efectivo.id}'),
          headers: headers(),
          body: jsonEncode({'nombre': 'Contado'}),
        );
        await http.put(
          url('/medios-pago/${efectivo.id}'),
          headers: headers(),
          body: jsonEncode({'activo': false}),
        );

        final actualizado = await (db.select(
          db.mediosDePago,
        )..where((m) => m.id.equals(efectivo.id))).getSingle();
        expect(actualizado.nombre, 'Contado');
        expect(actualizado.activo, isFalse);
      });

      test('POST /usuarios da de alta, PUT /usuarios/<id> renombra y desactiva', () async {
        final alta = await http.post(
          url('/usuarios'),
          headers: headers(),
          body: jsonEncode({'nombre': 'Ayuda finde'}),
        );
        expect(alta.statusCode, 201);
        final nuevoId = (jsonDecode(alta.body) as Map<String, dynamic>)['id'] as int;

        await http.put(
          url('/usuarios/$nuevoId'),
          headers: headers(),
          body: jsonEncode({'nombre': 'Ayuda fin de semana'}),
        );
        await http.put(
          url('/usuarios/$nuevoId'),
          headers: headers(),
          body: jsonEncode({'activo': false}),
        );

        final fila = await (db.select(db.usuarios)..where((u) => u.id.equals(nuevoId))).getSingle();
        expect(fila.nombre, 'Ayuda fin de semana');
        expect(fila.activo, isFalse);

        final listado = await http.get(url('/usuarios'), headers: headers());
        final usuarios = (jsonDecode(listado.body) as List).cast<Map<String, dynamic>>();
        final usuarioEnJson = usuarios.firstWhere((u) => u['id'] == nuevoId);
        expect(usuarioEnJson['activo'], isFalse);
      });
    },
  );
}
