// Servidor HTTP local para la companion app Android (spike 2026-09-07, ver
// conversación de esa fecha). Corre embebido en el proceso de la app de
// escritorio, escuchando en la red local — el celular es un cliente
// liviano, la única fuente de verdad sigue siendo el SQLite de la PC. Solo
// funciona mientras la app de escritorio está abierta y las dos máquinas
// están en la misma red.
//
// Alcance de esta API, a propósito acotado (El dueño, 2026-09-07: "solo cargar
// cosas básicas aparte de los productos... gastos y esas cosas"): productos
// (listar/alta/edición/ajuste de stock), proveedores y usuarios (para los
// selectores del celular), la sesión de caja abierta (para abrirla o saber
// bajo qué sesión cae un movimiento), gasto rápido, vender de verdad
// ("quiero que la parte de vender use la misma lógica que la app de
// desktop" — buscar con la misma lógica que el campo único de Venta,
// calcular el total, cobrar en efectivo o por QR/Débito e imprimir el
// ticket), y carga histórica (mismo día mismo, "se le pone la fecha,
// después es como si fuesen ventas que no descuentan stock... para saber
// ganancias"). Todo reusando las funciones que ya usa `VentaControlador`/
// `cargarDiaHistoricoDesdeVentas` (Regla 3) — ningún cálculo nuevo vive
// acá. Cierre real agregado 2026-09-19 (El dueño: "que deje cerrar caja desde
// el celular"), mismo molde que el arqueo intermedio de acá abajo — Reportes
// sigue fuera de alcance.
//
// Todas las rutas, salvo `/ping`, exigen el header `X-Companion-Token` con
// el token generado desde Configuración (`repositorio_configuracion.dart`,
// `regenerarTokenCompanion`) — no es autenticación de usuario (la app sigue
// "sin autenticación" para las personas), es la llave que evita que
// cualquier otro dispositivo de la misma WiFi use la API.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../data/busqueda_productos.dart';
import '../data/cobro_posnet.dart';
import '../data/database.dart';
import '../domain/codigo_emparejamiento.dart';
import '../data/notificador_cambios.dart';
import '../data/impresion_posnet.dart';
import '../data/repositorio_arqueo_intermedio.dart';
import '../data/repositorio_carga_historica.dart';
import '../data/repositorio_cierre.dart'
    show
        cantidadVentasDelDia,
        calcularResumenCierre,
        cerrarSesion,
        estadoCajaEnVivo,
        fondoInicialSugeridoCentavos,
        ResumenCierre,
        SesionYaNoAbiertaException,
        VentasAbiertasPendientesException;
import '../data/repositorio_cobro.dart';
import '../data/repositorio_deuda_proveedores.dart';
import '../data/repositorio_configuracion.dart';
import '../data/repositorio_edicion_venta.dart';
import '../data/repositorio_gastos.dart';
import '../data/repositorio_historial.dart' show listarDias;
import '../data/repositorio_ingresos.dart';
import '../data/repositorio_historial_ventas.dart';
import '../data/repositorio_medios_pago.dart';
import '../data/repositorio_productos.dart';
import '../data/repositorio_sincronizacion.dart';
import '../data/repositorio_ticket.dart';
import '../servicios/actualizaciones.dart' show leerVersionApp;
import '../data/repositorio_usuarios.dart';
import '../data/repositorio_encargues.dart';
import '../data/repositorio_pendientes.dart' show cobrarDeuda;
import '../data/repositorio_ventas.dart';
import '../servicios/nube.dart' show nubeApp;
import '../servicios/pasarela_point_nube.dart';
import '../servicios/impresion_posnet_nube.dart';
import '../servicios/preferencia_cobro_nube.dart';
import '../domain/caja.dart' show diferenciaArqueo;
import '../domain/cobro_posnet.dart';
import '../domain/descuento.dart';
import '../domain/edicion_masiva_precios.dart';
import '../domain/edicion_masiva_stock.dart';
import '../domain/medio_pago.dart';
import '../domain/venta.dart';
import '../domain/venta_json.dart';
import '../servicios/marca_actual.dart';

/// Dónde vive el .apk que se ofrece para actualizar la companion app — al
/// lado de la base real (misma carpeta `Documents`, `driftDatabase`), NO
/// empaquetado como asset del build de escritorio: un asset de Flutter es
/// compartido por TODAS las plataformas del proyecto, así que el build de
/// Android terminaba incluyéndose a sí mismo adentro suyo (bug real,
/// encontrado al ver el `.apk` pasar de 25MB a 38MB de la nada). Un archivo
/// suelto en disco no tiene ese problema — se reemplaza con
/// `tool/publicar_actualizacion_companion.sh` cada vez que sale una
/// versión nueva.
Future<File> _archivoApkCompanion() async {
  final documentos = await getApplicationDocumentsDirectory();
  return File(path.join(documentos.path, 'la_plazoleta_companion.apk'));
}

/// La versión del `.apk` publicado — al lado suyo, mismo criterio (un
/// archivo suelto, no un asset). Bug real (El dueño, 2026-09-07: "no hay
/// manera de lanzar actualizaciones sin reiniciar la app desktop"):
/// `/companion/version` comparaba contra `PackageInfo.fromPlatform()` del
/// propio proceso de escritorio, que solo cambia si ese `.exe` se
/// reconstruye Y se reinicia — nada que ver con qué `.apk` está sirviendo
/// de verdad. `tool/publicar_actualizacion_companion.sh` escribe este
/// archivo cada vez que publica, así que el número que ve el celular
/// cambia con la publicación, no con el reinicio del escritorio.
Future<File> _archivoVersionCompanion() async {
  final documentos = await getApplicationDocumentsDirectory();
  return File(path.join(documentos.path, 'la_plazoleta_companion.version'));
}

const int puertoServidorCompanion = 8099;

/// El código de emparejamiento vigente de esta PC (uno solo a la vez, en memoria: si la app se cierra, se pierde y se
/// genera otro).
final codigoEmparejamiento = GestorCodigoEmparejamiento();
const String encabezadoToken = 'X-Companion-Token';

/// Por dónde cobra la PC a la terminal: directo con el access token cargado en Configuración (lo de siempre), o por el
/// servidor de Nodo Sur con la cuenta conectada. Ver `servicios/pasarela_point_nube.dart`.
Future<PasarelaPoint> _pasarelaPoint(AppDatabase db, http.Client? httpClientDePrueba, {bool soloToken = false}) async {
  final config = await db.select(db.configuracionTabla).getSingle();
  return elegirPasarelaPoint(
    soloToken: soloToken,
    forzarNube: PreferenciaCobroNube.activo,
    accessToken: config.mpAccessToken,
    terminalId: config.mpTerminalCobroId,
    almacen: nubeApp?.almacen,
    cliente: nubeApp?.cliente,
    directa: (token, terminal) => PasarelaPointDirecta(accessToken: token, terminalId: terminal, client: httpClientDePrueba),
  );
}

Response _json(Object body, {int status = 200}) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );
}

Response _error(int status, String mensaje) =>
    _json({'error': mensaje}, status: status);

/// Convierte un valor de un body JSON decodificado a `int`, tolerando que
/// `jsonDecode` haya dado un `num`. `null` si el campo no vino.
int? _int(dynamic v) => v == null ? null : (v as num).toInt();

int _intRequerido(Map<String, dynamic> body, String campo) {
  final v = _int(body[campo]);
  if (v == null) throw FormatException('Falta el campo "$campo"');
  return v;
}

String _textoRequerido(Map<String, dynamic> body, String campo) {
  final v = body[campo];
  if (v is! String || v.trim().isEmpty) {
    throw FormatException('Falta el campo "$campo"');
  }
  return v;
}

/// Lista de ids de producto para los endpoints de edición masiva
/// (`/productos/lote/*`) — vacía o ausente es un pedido sin sentido, no un
/// caso válido de "no aplicar nada" (a diferencia de, por ejemplo, un
/// `busqueda` vacío en `/productos`).
List<int> _intListaRequerida(Map<String, dynamic> body, String campo) {
  final v = body[campo];
  if (v is! List || v.isEmpty) {
    throw FormatException('Falta el campo "$campo"');
  }
  return v.map((e) => (e as num).toInt()).toList();
}

Map<String, dynamic> _productoAJson(Producto p) => {
  'id': p.id,
  'nombre': p.nombre,
  'codigoBarras': p.codigoBarras,
  'categoriaId': p.categoriaId,
  'proveedorId': p.proveedorId,
  'esPesable': p.esPesable,
  'tipoCigarrillo': p.tipoCigarrillo,
  'precioCentavos': p.precioCentavos,
  'costoCentavos': p.costoCentavos,
  'precioPorKiloCentavos': p.precioPorKiloCentavos,
  'costoPorKiloCentavos': p.costoPorKiloCentavos,
  'stock': p.stock,
  'stockGramos': p.stockGramos,
  'activo': p.activo,
};

/// Dónde queda el rastro de un 500 real — al lado de la base y del `.apk`
/// publicado (mismo `getApplicationDocumentsDirectory()`), para poder
/// revisarlo sin tener que "agarrar en vivo" el error reabriendo la app en
/// modo debug (2026-09-17: esto costó varias vueltas de ida y vuelta en
/// producción real, con el dueño esperando — un archivo que ya quedó escrito
/// la primera vez que pasa es mucho más rápido de revisar).
Future<File> _archivoErroresCompanion() async {
  final documentos = await getApplicationDocumentsDirectory();
  return File(path.join(documentos.path, 'companion_errores.log'));
}

/// Envuelve un handler que puede tirar `FormatException`/`ArgumentError`
/// (dato inválido del celular, o una validación real del dominio como "un
/// pesable necesita precio por kilo") y los traduce a 400 en vez de que
/// shelf los deje escapar como 500 — un dato mal armado desde el celular es
/// un error del pedido, no una falla del servidor.
///
/// Cualquier OTRA excepción (un bug real, no una validación) sigue dando
/// 500 — pero antes de responder, queda escrita en
/// `_archivoErroresCompanion()` con fecha, ruta y el `stack trace` completo,
/// para poder diagnosticar un error real de producción sin tener que
/// reproducirlo en vivo.
Handler _conManejoDeErrores(Handler handler) {
  return (request) async {
    try {
      return await handler(request);
    } on FormatException catch (e) {
      return _error(400, e.message);
    } on ArgumentError catch (e) {
      return _error(400, e.message.toString());
    } catch (e, stack) {
      try {
        final archivo = await _archivoErroresCompanion();
        await archivo.writeAsString(
          '${DateTime.now().toIso8601String()} '
          '${request.method} ${request.requestedUri.path}\n'
          '$e\n$stack\n\n',
          mode: FileMode.append,
        );
      } catch (_) {
        // si ni siquiera se pudo escribir el log, no hay mucho más para
        // hacer acá — el 500 de abajo sigue respondiendo igual.
      }
      return _error(500, 'Error inesperado en el servidor');
    }
  };
}

/// Sync instantánea por wifi (2026-09-28): todo pedido del celular que
/// modifica algo (no GET) y salió bien avisa a [notificadorCambios] — así
/// las pantallas de la PC se refrescan solas, y el aviso le llega también
/// al celular por `/companion/eventos` (para que baje lo que él mismo u otro
/// dispositivo cambió).
Middleware _avisoDeCambios() {
  return (Handler innerHandler) {
    return (Request request) async {
      final respuesta = await innerHandler(request);
      if (request.method != 'GET' && respuesta.statusCode < 400) {
        notificadorCambios?.cambioDelCelular();
      }
      return respuesta;
    };
  };
}

/// Compara dos llaves sin cortar en la primera diferencia (revisión 2026-10-03): con `!=` el tiempo de respuesta
/// dependía de cuántos caracteres coincidían, y desde el wifi del local se podía ir adivinando la llave de a uno.
bool mismosTextosEnTiempoConstante(String? a, String b) {
  if (a == null) return false;
  final x = utf8.encode(a), y = utf8.encode(b);
  var diferencia = x.length ^ y.length;
  for (var i = 0; i < y.length; i++) {
    diferencia |= (i < x.length ? x[i] : 0) ^ y[i];
  }
  return diferencia == 0;
}

/// Exige `X-Companion-Token` en todas las rutas salvo `/ping` (que existe
/// para que el celular pueda confirmar que encontró la PC antes incluso de
/// tener un token — el paso previo al emparejamiento).
Middleware _autenticacion(AppDatabase db) {
  return (Handler innerHandler) {
    return (Request request) async {
      // `/companion/apk` también queda sin token (El dueño, 2026-09-07: "que
      // en la app escaneando el QR lo ponga para descargar") — un celular
      // nuevo, sin la companion instalada todavía, no tiene forma de
      // mandar el header (escanea la URL con la cámara común, que solo
      // sabe abrir un link en el navegador). El .apk en sí no es un dato
      // sensible — es el mismo binario que cualquiera podría instalar
      // igual una vez emparejado — el token sigue protegiendo todo lo
      // demás (productos, ventas, gastos...).
      // `/emparejar` también: es justamente cómo un celular nuevo consigue el token, con el código de 6 números.
      if (request.url.path == 'ping' || request.url.path == 'companion/apk' || request.url.path == 'emparejar') {
        return innerHandler(request);
      }

      final tokenPedido = request.headers[encabezadoToken];
      final tokenReal = await tokenCompanionActual(db);
      if (tokenReal == null || !mismosTextosEnTiempoConstante(tokenPedido, tokenReal)) {
        return _error(401, 'Token inválido o sin emparejar');
      }
      return innerHandler(request);
    };
  };
}

Router _armarRouter(AppDatabase db, {http.Client? httpClientDePrueba}) {
  final router = Router();

  router.get('/ping', (Request request) {
    return _json({'ok': true, 'app': 'la_plazoleta', 'mensaje': 'pong'});
  });

  // Emparejar con el código de 6 números que muestra Configuración → Celular (El dueño, 2026-10-03): el celular lo
  // manda y, si es el vigente, recibe la llave de esta PC. De un solo uso, vence en 5 minutos y se anula a los 5
  // intentos fallidos (`GestorCodigoEmparejamiento`).
  router.post('/emparejar', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final codigo = body['codigo'];
    if (codigo is! String || !RegExp(r'^\d{6}$').hasMatch(codigo.trim())) return _error(400, 'El código tiene 6 números');
    return switch (codigoEmparejamiento.canjear(codigo)) {
      ResultadoCanje.ok => _json({
        'token': await tokenCompanionActual(db) ?? await regenerarTokenCompanion(db),
        'puerto': puertoServidorCompanion,
      }),
      ResultadoCanje.incorrecto => _error(401, 'Código incorrecto. Revisalo en la PC y probá de nuevo.'),
      ResultadoCanje.vencido => _error(410, 'El código venció. Generá otro en la PC.'),
      ResultadoCanje.anulado => _error(429, 'Demasiados intentos: el código se anuló. Generá otro en la PC.'),
      ResultadoCanje.sinCodigo => _error(404, 'No hay un código activo. Generá uno en la PC (Configuración → Celular).'),
    };
  });

  // Aviso instantáneo al celular (2026-09-28, "100% fluida la sync por
  // wifi"): una conexión que queda abierta (Server-Sent Events) y manda una
  // línea cada vez que cambia algo en la base de la PC — el celular, al
  // recibirla, baja los cambios con `/sync/cambios` y refresca la pantalla.
  // Un latido cada 15 s mantiene viva la conexión en el wifi y le permite
  // al celular darse cuenta rápido si la PC se fue.
  router.get('/companion/eventos', (Request request) {
    final notificador = notificadorCambios;
    if (notificador == null) return _error(503, 'Avisos no disponibles');
    late final StreamController<List<int>> salida;
    StreamSubscription<int>? sub;
    Timer? latido;
    void enviar(String texto) {
      if (!salida.isClosed) salida.add(utf8.encode(texto));
    }

    salida = StreamController<List<int>>(
      onListen: () {
        enviar('retry: 1000\ndata: {"version":${notificador.version}}\n\n');
        sub = notificador.cambiosDeLaBase.listen((v) => enviar('data: {"version":$v}\n\n'));
        latido = Timer.periodic(const Duration(seconds: 15), (_) => enviar(': latido\n\n'));
      },
      onCancel: () {
        sub?.cancel();
        latido?.cancel();
      },
    );
    return Response.ok(
      salida.stream,
      headers: {'content-type': 'text/event-stream', 'cache-control': 'no-cache', 'connection': 'keep-alive'},
      // Sin esto shelf junta la respuesta en un buffer y el aviso no sale
      // hasta que se llena: cada línea tiene que irse en el momento.
      context: {'shelf.io.buffer_output': false},
    );
  });

  // Sistema de actualización (El dueño, 2026-09-07: "para poder probar sin
  // tener que pasar la apk a cada rato"): el celular compara su propia
  // versión (`PackageInfo.fromPlatform()` del lado Android) contra esta —
  // son la misma `pubspec.yaml`, un solo número de versión para las dos
  // plataformas — y si difiere, ofrece descargar/instalar la que sirve acá.
  router.get('/companion/version', (Request request) async {
    final archivoVersion = await _archivoVersionCompanion();
    if (await archivoVersion.exists()) {
      final partes = (await archivoVersion.readAsString()).trim().split('+');
      if (partes.length == 2) {
        return _json({'version': partes[0], 'buildNumber': partes[1]});
      }
    }
    // Sin ningún .apk publicado todavía por el script (o el archivo vino
    // corrupto) — se cae a la versión de la propia app de escritorio, como
    // al principio de este sistema.
    // `separarVersion`: en Windows `ProductVersion` es "1.0.0.2098" (lo que
    // necesita el actualizador) y `PackageInfo` lo devuelve sin separar.
    final v = await leerVersionApp();
    return _json({'version': v.nombre, 'buildNumber': v.build});
  });

  router.get('/companion/apk', (Request request) async {
    final archivo = await _archivoApkCompanion();
    if (!await archivo.exists()) {
      return _error(404, 'Todavía no hay ningún .apk publicado en esta PC');
    }
    return Response.ok(
      archivo.openRead(),
      headers: {'content-type': 'application/vnd.android.package-archive'},
    );
  });

  // ─── Encargues por apartado (El dueño, 2026-10-02) ───────────────────
  router.get('/encargues', (Request request) async {
    final lista = await listarEnarguesPendientes(db);
    return _json([
      for (final e in lista)
        {
          'id': e.id,
          'nombreCliente': e.nombreCliente,
          'desdeMs': e.desde.millisecondsSinceEpoch,
          'lineas': [for (final l in e.lineas) l.texto],
        },
    ]);
  });

  router.post('/encargues', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    try {
      final id = await crearEncargueApartando(
        db,
        nombreCliente: _textoRequerido(body, 'nombreCliente'),
        lineas: [
          for (final l in body['lineas'] as List)
            LineaEncargueNueva(
              productoId: (l as Map)['productoId'] as int,
              cantidad: l['cantidad'] as int?,
              gramos: l['gramos'] as int?,
            ),
        ],
        usuarioId: _intRequerido(body, 'usuarioId'),
      );
      return _json({'id': id}, status: 201);
    } on EncargueSinStock catch (e) {
      return _error(409, 'No alcanza el stock de ${e.nombreProducto}.');
    } on ArgumentError catch (e) {
      return _error(400, '${e.message}');
    }
  });

  router.post('/encargues/<id>/cancelar', (Request request, String id) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await cancelarEncargue(db, int.parse(id), usuarioId: _intRequerido(body, 'usuarioId'));
    return _json({'ok': true});
  });

  // Entregar y anotar deuda (2026-10-03: el fiado se unificó con los encargues) y cobrar esa deuda.
  router.post('/encargues/<id>/deuda', (Request request, String id) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final total = await entregarEncargueADeuda(db, int.parse(id), usuarioId: _intRequerido(body, 'usuarioId'));
    if (total == null) return _error(409, 'Ese encargue ya no está pendiente.');
    return _json({'totalCentavos': total});
  });

  router.get('/deudas', (Request request) async {
    final lista = await listarDeudas(db);
    return _json([
      for (final d in lista)
        {
          'id': d.id,
          'nombreCliente': d.nombreCliente,
          'detalle': d.detalle,
          'montoCentavos': d.montoCentavos,
          'desdeMs': d.desde.millisecondsSinceEpoch,
        },
    ]);
  });

  router.post('/deudas/<id>/cobrar', (Request request, String id) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    try {
      final ventaId = await cobrarDeuda(
        db,
        pendienteId: int.parse(id),
        sesionCajaId: _intRequerido(body, 'sesionCajaId'),
        usuarioId: _intRequerido(body, 'usuarioId'),
        efectivo: body['efectivo'] as bool? ?? true,
      );
      return _json({'ventaId': ventaId});
    } on SesionCerradaException {
      return _error(409, 'La caja ya se cerró, este cobro no se guardó');
    }
  });

  router.get('/encargues/<id>/lineas', (Request request, String id) async {
    final lineas = await lineasParaEntregar(db, int.parse(id));
    return _json([for (final l in lineas) lineaVentaAJson(l)]);
  });

  router.get('/usuarios', (Request request) async {
    final usuarios = await db.select(db.usuarios).get();
    return _json([
      for (final u in usuarios) {'id': u.id, 'nombre': u.nombre, 'activo': u.activo},
    ]);
  });

  // Alta/edición de usuarios desde Configuración en la companion (El dueño,
  // 2026-09-19) — Regla 18, sin autenticación real.
  router.post('/usuarios', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final id = await crearUsuario(db, _textoRequerido(body, 'nombre'));
    return _json({'id': id}, status: 201);
  });

  router.put('/usuarios/<id>', (Request request, String id) async {
    final usuarioId = int.tryParse(id);
    if (usuarioId == null) return _error(400, 'Id de usuario inválido');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final nombre = body['nombre'] as String?;
    if (nombre != null) await renombrarUsuario(db, usuarioId, nombre);
    final activo = body['activo'] as bool?;
    if (activo != null) {
      await (activo ? activarUsuario(db, usuarioId) : desactivarUsuario(db, usuarioId));
    }
    return _json({'ok': true});
  });

  router.get('/proveedores', (Request request) async {
    final proveedores = await listarProveedores(db);
    return _json([
      for (final p in proveedores)
        {'id': p.id, 'codigo': p.codigo, 'nombre': p.nombre},
    ]);
  });

  // Cuenta corriente con proveedores: la tabla `movimientos_deuda` no se
  // sincroniza al celular, así que el saldo y el pago pasan siempre por acá.
  router.get('/proveedores/saldos', (Request request) async {
    final saldos = await saldosDeuda(db);
    return _json({for (final e in saldos.entries) '${e.key}': e.value});
  });

  router.post('/proveedores/<id>/pagos', (Request request, String id) async {
    final proveedorId = int.tryParse(id);
    if (proveedorId == null) return _error(400, 'Proveedor inválido');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final origen = OrigenPagoDeuda.desde(_textoRequerido(body, 'origen'));
    final sesionCajaId = _int(body['sesionCajaId']);
    try {
      // Un pago que sale de una caja necesita una sesión abierta; sin esto un
      // pago que llega justo después de un cierre se grabaría en una sesión
      // ya cerrada (mismo criterio que `/gastos`).
      if (origen != OrigenPagoDeuda.fuera && sesionCajaId != null) {
        await verificarSesionAbierta(db, sesionCajaId);
      }
      final movimientoId = await pagarDeuda(
        db,
        proveedorId: proveedorId,
        montoCentavos: _intRequerido(body, 'montoCentavos'),
        origen: origen,
        nota: body['nota'] as String?,
        usuarioId: _intRequerido(body, 'usuarioId'),
        sesionCajaId: sesionCajaId,
      );
      return _json({'id': movimientoId}, status: 201);
    } on SesionCerradaException {
      return _error(409, 'La caja ya se cerró, este pago no se guardó');
    } on SinCajaAbiertaException {
      return _error(409, 'Hace falta una caja abierta para pagar desde la caja');
    }
  });

  // Para el desplegable del alta/edición completa de producto en la
  // companion (fase del escáner central, 2026-09-17) — solo lectura, nunca
  // crea una categoría nueva desde el celular.
  router.get('/categorias', (Request request) async {
    final categorias = await listarCategorias(db);
    return _json([
      for (final c in categorias)
        {'id': c.id, 'nombre': c.nombre, 'markupDefaultBp': c.markupDefaultBp},
    ]);
  });

  // Markup de referencia desde Configuración en la companion (El dueño,
  // 2026-09-19) — Regla 14, puramente informativo. Nunca crea una
  // categoría nueva, solo edita el % de una que ya existe.
  router.put('/categorias/<id>/markup', (Request request, String id) async {
    final categoriaId = int.tryParse(id);
    if (categoriaId == null) return _error(400, 'Id de categoría inválido');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await actualizarMarkupCategoria(
      db,
      categoriaId: categoriaId,
      markupBp: _intRequerido(body, 'markupBp'),
    );
    return _json({'ok': true});
  });

  // Medios de pago desde Configuración en la companion (El dueño, 2026-09-19)
  // — solo renombrar/activar/desactivar los 2 que ya existen (Regla 2/6),
  // sin alta de medios nuevos a propósito.
  router.get('/medios-pago', (Request request) async {
    final medios = await listarMediosDePago(db);
    return _json([
      for (final m in medios)
        {'id': m.id, 'nombre': m.nombre, 'esEfectivo': m.esEfectivo, 'activo': m.activo},
    ]);
  });

  router.put('/medios-pago/<id>', (Request request, String id) async {
    final medioId = int.tryParse(id);
    if (medioId == null) return _error(400, 'Id de medio de pago inválido');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final nombre = body['nombre'] as String?;
    if (nombre != null) await renombrarMedioDePago(db, medioId, nombre);
    final activo = body['activo'] as bool?;
    if (activo != null) {
      await (activo ? activarMedioDePago(db, medioId) : desactivarMedioDePago(db, medioId));
    }
    return _json({'ok': true});
  });

  // Recargo de cigarrillos + redondeo + producto de vuelto, desde
  // Configuración en la companion (El dueño, 2026-09-19: "que se puedan
  // modificar las reglas del negocio... desde el celular") — mismas
  // funciones que ya usa la Configuración del escritorio (Regla 3).
  router.get('/configuracion', (Request request) async {
    final c = await configuracionNegocioActual(db);
    return _json({
      'recargoPrimerAtadoCentavos': c.recargoPrimerAtadoCentavos,
      'recargoAtadoAdicionalCentavos': c.recargoAtadoAdicionalCentavos,
      'recargoSueltoCentavos': c.recargoSueltoCentavos,
      'pasoRedondeoCentavos': c.pasoRedondeoCentavos,
      'productoVueltoId': ?c.productoVueltoId,
    });
  });

  router.put('/configuracion/recargo-cigarrillos', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await configurarRecargoCigarrillos(
      db,
      primerAtadoCentavos: _intRequerido(body, 'primerAtadoCentavos'),
      atadoAdicionalCentavos: _intRequerido(body, 'atadoAdicionalCentavos'),
      sueltoCentavos: _intRequerido(body, 'sueltoCentavos'),
    );
    return _json({'ok': true});
  });

  router.put('/configuracion/redondeo', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await configurarPasoRedondeo(db, _intRequerido(body, 'montoCentavos'));
    return _json({'ok': true});
  });

  router.put('/configuracion/producto-vuelto', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await configurarProductoVuelto(db, _int(body['productoId']));
    return _json({'ok': true});
  });

  router.get('/productos', (Request request) async {
    final parametros = request.url.queryParameters;
    final busqueda = parametros['busqueda'];
    final proveedorIdTexto = parametros['proveedorId'];
    bool esVerdadero(String clave) => parametros[clave] == 'true';
    final productos = await listarProductos(
      db,
      busqueda: busqueda,
      proveedorId: proveedorIdTexto == null
          ? null
          : int.tryParse(proveedorIdTexto),
      // Filtros de higiene de catálogo (El dueño, 2026-09-19: "filtrar por
      // productos sin proveedor, sin costo, etcétera" desde la companion).
      sinProveedor: esVerdadero('sinProveedor'),
      sinCosto: esVerdadero('sinCosto'),
      sinCategoria: esVerdadero('sinCategoria'),
      sinCodigoBarras: esVerdadero('sinCodigoBarras'),
    );
    return _json([for (final p in productos) _productoAJson(p)]);
  });

  // El dueño, 2026-09-07: "yo debería poder revisar los productos sin stock
  // desde la app Android para ajustarlos" — todos los proveedores juntos,
  // mismo criterio que ya usa "Stock por proveedor" en el escritorio
  // (`productoAgotado`/`ordenarAgotadosPrimero`, Regla 3: ninguna fórmula
  // nueva). Ordenados alfabético — los tres devuelven agotados nada más,
  // así que la mitad "agotados primero" de esa función no cambia nada acá.
  router.get('/productos/sin-stock', (Request request) async {
    final productos = await listarProductos(db);
    final agotados = ordenarAgotadosPrimero(
      productos.where(productoAgotado).toList(),
    );
    return _json([for (final p in agotados) _productoAJson(p)]);
  });

  // Historial de ventas, filtrable (El dueño, 2026-09-07: "hagamos la
  // sección de reportes... con el historial de ventas, lo mismo para
  // desktop, que sea filtrable... tipo mercado pago").
  router.get('/historial/ventas', (Request request) async {
    final desdeTexto = request.url.queryParameters['desde'];
    final hastaTexto = request.url.queryParameters['hasta'];
    if (desdeTexto == null || hastaTexto == null) {
      return _error(400, 'Faltan "desde" y/o "hasta"');
    }
    final medioTexto = request.url.queryParameters['medio'];
    final medio = medioTexto == null
        ? null
        : MedioVentaHistorial.values
              .where((m) => m.name == medioTexto)
              .firstOrNull;
    if (medioTexto != null && medio == null) {
      return _error(
        400,
        '"medio" tiene que ser uno de: ${MedioVentaHistorial.values.map((m) => m.name).join(', ')}',
      );
    }
    final ventas = await historialDeVentas(
      db,
      desde: DateTime.parse(desdeTexto),
      hasta: DateTime.parse(hastaTexto),
      filtroMedio: medio,
    );
    return _json([
      for (final v in ventas)
        {
          'ventaId': v.ventaId,
          'fecha': v.fecha.toIso8601String(),
          'totalCentavos': v.totalCentavos,
          'medio': v.medio.name,
          'detalle': v.detalle,
          'anulada': v.anulada,
          'sesionAbierta': v.sesionAbierta,
          'numero': v.numero,
        },
    ]);
  });

  // Cierres reales (El dueño, 2026-09-13: "quiero la pantalla nueva de
  // cierres con caché offline" — poder verlos aunque el celular esté
  // fuera del local, con la última copia guardada) — mismo `listarDias`
  // que ya usa el Historial de escritorio (Regla 3), excluyendo los días
  // de carga histórica (`notaCargaHistorica`): esos nunca tuvieron un
  // arqueo real, mezclarlos acá confundiría "cerré la caja" con "cargué un
  // día pasado como dato". `limite` (default 30) evita mandar años de
  // historial de una sola vez a un celular con datos móviles limitados.
  router.get('/sesiones/cerradas', (Request request) async {
    final limiteTexto = request.url.queryParameters['limite'];
    final limite = int.tryParse(limiteTexto ?? '') ?? 30;
    final dias = await listarDias(db);
    final reales = dias.where((d) => d.sesion.nota != notaCargaHistorica).take(limite);
    return _json([
      for (final d in reales)
        {
          'sesionId': d.sesion.id,
          'fechaApertura': d.sesion.fechaApertura.toIso8601String(),
          'fechaCierre': ?d.sesion.fechaCierre?.toIso8601String(),
          'nombreEmpleado': d.nombreEmpleado,
          'totalVendidoCentavos': d.totalVendidoCentavos,
          'efectivoContadoCentavos': ?d.sesion.efectivoContadoCentavos,
          'efectivoEsperadoCentavos': ?d.sesion.efectivoEsperadoCentavos,
          'diferenciaCentavos': ?d.sesion.diferenciaCentavos,
          'mpContadoCentavos': ?d.sesion.mpContadoCentavos,
          'mpEsperadoCentavos': ?d.sesion.mpEsperadoCentavos,
          'mpDiferenciaCentavos': ?d.sesion.mpDiferenciaCentavos,
          'lataContadoCentavos': ?d.sesion.lataContadoCentavos,
          'lataFinalCentavos': ?d.sesion.lataFinalCentavos,
          'lataDiferenciaCentavos': ?d.sesion.lataDiferenciaCentavos,
        },
    ]);
  });

  // Anular una venta ya cobrada (El dueño, 2026-09-13: eliminar una venta
  // desde el celular) — solo mientras la sesión de caja de esa venta siga
  // abierta (`anularVenta` tira `ArgumentError` si no, que
  // `_conManejoDeErrores` ya convierte en 400 con el mensaje tal cual).
  router.post('/ventas/<ventaId>/anular', (Request request, String ventaId) async {
    final id = int.tryParse(ventaId);
    if (id == null) return _error(400, 'Id de venta inválido');
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await anularVenta(
      db,
      ventaId: id,
      usuarioId: _intRequerido(body, 'usuarioId'),
      motivo: _textoRequerido(body, 'motivo'),
    );
    return _json({'ok': true});
  });

  router.get('/productos/codigo/<codigo>', (
    Request request,
    String codigo,
  ) async {
    final producto = await productoPorCodigoBarras(db, codigo);
    if (producto == null) {
      return _error(404, 'No hay ningún producto con ese código');
    }
    return _json(_productoAJson(producto));
  });

  router.post('/productos', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final id = await crearProducto(
      db,
      nombre: _textoRequerido(body, 'nombre'),
      codigoBarras: body['codigoBarras'] as String?,
      categoriaId: _int(body['categoriaId']),
      proveedorId: _int(body['proveedorId']),
      esPesable: body['esPesable'] as bool? ?? false,
      tipoCigarrillo: body['tipoCigarrillo'] as String? ?? 'ninguno',
      precioCentavos: _int(body['precioCentavos']),
      costoCentavos: _int(body['costoCentavos']),
      precioPorKiloCentavos: _int(body['precioPorKiloCentavos']),
      costoPorKiloCentavos: _int(body['costoPorKiloCentavos']),
      stock: _int(body['stock']) ?? 0,
      stockGramos: _int(body['stockGramos']),
      usuarioId: _intRequerido(body, 'usuarioId'),
    );
    return _json({'id': id}, status: 201);
  });

  // Editor masivo (El dueño, 2026-09-19: "editor masivo, ya sea de precios
  // costo stock etc etc" — mismo mecanismo que ya usaba "Proveedores" en el
  // escritorio, `dialogo_edicion_masiva.dart`, ahora también disponible
  // desde la companion). Cada ruta reusa el mismo repositorio en lote que
  // ya existía o se agregó junto con esto (`ajustarStockEnLote`) — ningún
  // cálculo nuevo vive acá (Regla 3). Sin `/productos/lote/activo`: la
  // companion la sacó (El dueño, misma fecha: "las opciones que da no se
  // correlacionan con el editor como tal" — activar/desactivar en lote no
  // correspondía a ningún caso real desde el celular), pero el escritorio
  // la sigue usando (`cambiarActivoEnLote`, `data/repositorio_productos.dart`)
  // así que la función en sí no se tocó.
  //
  // Registradas ANTES de `/productos/<id>/stock` a propósito:
  // `shelf_router` prueba las rutas en el orden en que se agregan, y
  // `<id>` matchea cualquier segmento — con el orden al revés,
  // `/productos/lote/stock` caía en `/productos/<id>/stock` con `id` =
  // "lote" (bug real, encontrado por el test de este mismo archivo:
  // devolvía 400 "Id de producto inválido" en vez de aplicar el ajuste).
  router.post('/productos/lote/monto', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await ajustarMontoEnLote(
      db,
      productoIds: _intListaRequerida(body, 'productoIds'),
      campo: CampoMonto.values.byName(_textoRequerido(body, 'campo')),
      tipo: TipoAjustePrecio.values.byName(_textoRequerido(body, 'tipo')),
      valor: _intRequerido(body, 'valor'),
      usuarioId: _intRequerido(body, 'usuarioId'),
    );
    return _json({'ok': true});
  });

  router.post('/productos/lote/stock', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await ajustarStockEnLote(
      db,
      productoIds: _intListaRequerida(body, 'productoIds'),
      tipo: TipoAjusteStock.values.byName(_textoRequerido(body, 'tipo')),
      valor: _intRequerido(body, 'valor'),
      usuarioId: _intRequerido(body, 'usuarioId'),
      motivo: body['motivo'] as String? ?? 'Ajuste masivo',
    );
    return _json({'ok': true});
  });

  router.post('/productos/lote/categoria', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await asignarCategoriaEnLote(
      db,
      productoIds: _intListaRequerida(body, 'productoIds'),
      categoriaId: _int(body['categoriaId']),
      usuarioId: _intRequerido(body, 'usuarioId'),
    );
    return _json({'ok': true});
  });

  router.post('/productos/lote/proveedor', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await asignarProveedorEnLote(
      db,
      productoIds: _intListaRequerida(body, 'productoIds'),
      proveedorId: _int(body['proveedorId']),
      usuarioId: _intRequerido(body, 'usuarioId'),
    );
    return _json({'ok': true});
  });

  router.put('/productos/<id>', (Request request, String id) async {
    final productoId = int.tryParse(id);
    if (productoId == null) return _error(400, 'Id de producto inválido');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await actualizarProducto(
      db,
      id: productoId,
      nombre: _textoRequerido(body, 'nombre'),
      codigoBarras: body['codigoBarras'] as String?,
      categoriaId: _int(body['categoriaId']),
      proveedorId: _int(body['proveedorId']),
      esPesable: body['esPesable'] as bool? ?? false,
      tipoCigarrillo: body['tipoCigarrillo'] as String? ?? 'ninguno',
      precioCentavos: _int(body['precioCentavos']),
      costoCentavos: _int(body['costoCentavos']),
      precioPorKiloCentavos: _int(body['precioPorKiloCentavos']),
      costoPorKiloCentavos: _int(body['costoPorKiloCentavos']),
      stock: _intRequerido(body, 'stock'),
      stockGramos: _int(body['stockGramos']),
      activo: body['activo'] as bool? ?? true,
      usuarioId: _intRequerido(body, 'usuarioId'),
      motivoAjusteStock: body['motivoAjusteStock'] as String?,
    );
    return _json({'ok': true});
  });

  router.post('/productos/<id>/stock', (Request request, String id) async {
    final productoId = int.tryParse(id);
    if (productoId == null) return _error(400, 'Id de producto inválido');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await ajustarStockRapido(
      db,
      productoId: productoId,
      usuarioId: _intRequerido(body, 'usuarioId'),
      stock: _intRequerido(body, 'stock'),
      stockGramos: _int(body['stockGramos']),
      motivo: body['motivo'] as String?,
    );
    return _json({'ok': true});
  });

  router.get('/sesion', (Request request) async {
    final sesion = await sesionAbierta(db);
    if (sesion == null) {
      final sugerido = await fondoInicialSugeridoCentavos(db);
      final lataQueSeArrastra = await lataQueSeArrastraCentavos(db);
      return _json({
        'abierta': false,
        'fondoInicialSugeridoCentavos': ?sugerido,
        'lataQueSeArrastraCentavos': lataQueSeArrastra,
      });
    }
    // `fechaUltimoArqueoIntermedio` es lo que el celular necesita para
    // saber, sin abrir ninguna pantalla, si el arqueo obligatorio de 2hs ya
    // venció (El dueño, 2026-09-13: "el bloqueo cada 2hs sincronizado con la
    // app desktop") — comparte la misma tabla `arqueos_intermedios` que ya
    // usa el escritorio, así que un arqueo hecho de un lado resetea la
    // cuenta del otro sin nada más que consultarlo de nuevo.
    final futuroUltimoArqueo = fechaUltimoArqueoIntermedio(db, sesion.id);
    final futuroArqueos = arqueosDelTurno(db, sesion.id);
    final futuroUsuario = (db.select(
      db.usuarios,
    )..where((u) => u.id.equals(sesion.usuarioAbrioId))).getSingleOrNull();
    final ultimoArqueo = await futuroUltimoArqueo;
    final usuario = await futuroUsuario;
    final ultimo = (await futuroArqueos).lastOrNull;
    return _json({
      'abierta': true,
      'ultimoArqueoEfectivoCentavos': ?ultimo?.efectivoContadoCentavos,
      'ultimoArqueoMpCentavos': ?ultimo?.mpContadoCentavos,
      'id': sesion.id,
      'fechaApertura': sesion.fechaApertura.toIso8601String(),
      'usuarioAbrioId': sesion.usuarioAbrioId,
      'usuarioAbrioNombre': ?usuario?.nombre,
      'origenDispositivo': ?sesion.origenDispositivo,
      'fechaUltimoArqueoIntermedio': ?ultimoArqueo?.toIso8601String(),
    });
  });

  // Arqueo obligatorio cada 2hs desde el celular (El dueño, 2026-09-13) — dos
  // pasos como el cierre real y como el mismo diálogo de escritorio
  // (`dialogo_arqueo_intermedio.dart`): "calcular" recalcula en vivo
  // mientras se tipea (sin guardar nada todavía), "confirmar" recién ahí
  // guarda. La lata NO usa `calcularResumenCierre` para su esperado —
  // mismo motivo que ya corrigió el bug real del escritorio
  // (`lataEsperadaIntermedia`, `repositorio_arqueo_intermedio.dart`): a las
  // 2hs todavía no se separó nada, esa función asume que sí.
  router.post('/sesion/arqueo-intermedio/calcular', (Request request) async {
    final sesion = await sesionAbierta(db);
    if (sesion == null) return _error(409, 'No hay caja abierta');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final efectivoContado = _intRequerido(body, 'efectivoContadoCentavos');
    final mpContado = _int(body['mpContadoCentavos']);
    final lataContado = _int(body['lataContadoCentavos']);

    final futuroResumen = calcularResumenCierre(
      db,
      sesionId: sesion.id,
      efectivoContadoCentavos: efectivoContado,
      mpContadoCentavos: mpContado,
    );
    final futuroLataEsperada = lataEsperadaIntermedia(db, sesion.id);
    final resumen = await futuroResumen;
    final lataEsperada = await futuroLataEsperada;

    return _json({
      'efectivoEsperadoCentavos': resumen.efectivoEsperadoCentavos,
      'diferenciaCentavos': resumen.diferenciaCentavos,
      'mpEsperadoCentavos': resumen.mpEsperadoCentavos,
      'mpDiferenciaCentavos': ?resumen.mpDiferenciaCentavos,
      'lataEsperadoCentavos': lataEsperada,
      'lataDiferenciaCentavos': ?(lataContado == null
          ? null
          : diferenciaArqueo(contadoCentavos: lataContado, esperadoCentavos: lataEsperada)),
    });
  });

  router.post('/sesion/arqueo-intermedio/confirmar', (Request request) async {
    final sesion = await sesionAbierta(db);
    if (sesion == null) return _error(409, 'No hay caja abierta');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await registrarArqueoIntermedio(
      db,
      sesionId: sesion.id,
      usuarioId: _intRequerido(body, 'usuarioId'),
      efectivoContadoCentavos: _intRequerido(body, 'efectivoContadoCentavos'),
      mpContadoCentavos: _intRequerido(body, 'mpContadoCentavos'),
      lataContadoCentavos: _intRequerido(body, 'lataContadoCentavos'),
    );
    return _json({'ok': true});
  });

  // Cierre real desde el celular (El dueño, 2026-09-19: "que deje cerrar caja
  // desde el celular") — mismo molde de dos pasos que el arqueo intermedio
  // de arriba, pero con `calcularResumenCierre`/`cerrarSesion` (Regla 3: la
  // misma función que usa `CierreControlador` en el escritorio, ningún
  // cálculo nuevo). El desglose por proveedor ("lo que se debe separar")
  // reusa `resumenDiaHistorico` tal cual — ya resuelve nombres y calcula
  // costo real/ganancia por proveedor, mismo `_resumenDiaAJson` que ya usa
  // "¿Cómo vamos?" (Regla 3).
  router.post('/sesion/cerrar/calcular', (Request request) async {
    final sesion = await sesionAbierta(db);
    if (sesion == null) return _error(409, 'No hay caja abierta');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final efectivoContado = _intRequerido(body, 'efectivoContadoCentavos');
    final mpContado = _int(body['mpContadoCentavos']);
    final lataContado = _int(body['lataContadoCentavos']);

    final futuroResumen = calcularResumenCierre(
      db,
      sesionId: sesion.id,
      efectivoContadoCentavos: efectivoContado,
      mpContadoCentavos: mpContado,
      lataContadoCentavos: lataContado,
    );
    final futuroResumenDia = resumenDiaHistorico(db, sesion.id);
    final resumen = await futuroResumen;
    final resumenDia = await futuroResumenDia;

    return _json(_resumenCierreAJson(resumen, resumenDia));
  });

  router.post('/sesion/cerrar/confirmar', (Request request) async {
    final sesion = await sesionAbierta(db);
    if (sesion == null) return _error(409, 'No hay caja abierta');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    try {
      await cerrarSesion(
        db,
        sesionId: sesion.id,
        usuarioId: _intRequerido(body, 'usuarioId'),
        efectivoContadoCentavos: _intRequerido(body, 'efectivoContadoCentavos'),
        mpContadoCentavos: _intRequerido(body, 'mpContadoCentavos'),
        lataContadoCentavos: _intRequerido(body, 'lataContadoCentavos'),
        nota: body['nota'] as String?,
      );
      return _json({'ok': true});
    } on VentasAbiertasPendientesException {
      return _error(409, 'Hay ventas armadas sin cobrar en la PC: cobralas o descartalas antes de cerrar');
    } on SesionYaNoAbiertaException {
      // El dueño, 2026-09-19: "aislar los usuarios para que no se pisen" — se
      // cerró desde otro lado entre el último /calcular y este /confirmar.
      return _error(409, 'La caja ya se cerró desde otro lado mientras tanto');
    }
  });

  // Detalle completo de un cierre YA cerrado (El dueño, 2026-09-19: rework de
  // "Cierres" en la companion, con el desglose por proveedor) — mismo
  // cálculo que `_ContenidoCerrado` del escritorio (`pantalla_cierre.dart`):
  // `calcularResumenCierre` no exige que la sesión esté ABIERTA, así que
  // recalcularlo con los conteos YA GUARDADOS en la fila (no se piden de
  // nuevo) da exactamente el mismo desglose que se vio al cerrar, sin haber
  // guardado nada de esto aparte (Regla 3: nunca un cálculo cacheado que
  // pueda desalinearse del real).
  router.get('/sesiones/cerradas/<sesionId>/detalle', (
    Request request,
    String sesionId,
  ) async {
    final id = int.tryParse(sesionId);
    if (id == null) return _error(400, 'Id de sesión inválido');
    final sesion = await (db.select(
      db.sesionesDeCaja,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (sesion == null || sesion.estado != 'CERRADA') {
      return _error(404, 'No hay ningún cierre real con ese id');
    }
    final futuroResumen = calcularResumenCierre(
      db,
      sesionId: id,
      efectivoContadoCentavos: sesion.efectivoContadoCentavos ?? 0,
      mpContadoCentavos: sesion.mpContadoCentavos,
      lataContadoCentavos: sesion.lataContadoCentavos,
    );
    final futuroResumenDia = resumenDiaHistorico(db, id);
    final resumen = await futuroResumen;
    final resumenDia = await futuroResumenDia;
    return _json({
      ..._resumenCierreAJson(resumen, resumenDia),
      'nota': ?sesion.nota,
      'efectivoContadoCentavos': ?sesion.efectivoContadoCentavos,
      'mpContadoCentavos': ?sesion.mpContadoCentavos,
      'lataContadoCentavos': ?sesion.lataContadoCentavos,
    });
  });

  // "¿Cómo vamos?" en cualquier momento del día (El dueño, 2026-09-07: "un
  // botón de arqueo también para saber que tal vamos en cualquier momento
  // sin tener que contar a mano las ventas del día") — mismas fórmulas del
  // cierre real (`estadoCajaEnVivo`, `repositorio_cierre.dart`) y el mismo
  // resumen por medio/proveedor que ya usa la carga histórica
  // (`resumenDiaHistorico`, Regla 3), pero sin pedir ningún conteo: no hay
  // diferencia de arqueo ni separación de cigarrillos acá, eso sigue
  // siendo exclusivo del cierre de verdad (Regla 10).
  router.get('/caja/estado', (Request request) async {
    final sesion = await sesionAbierta(db);
    if (sesion == null) return _error(409, 'No hay caja abierta');
    // Las tres son independientes entre sí — se lanzan juntas en vez de
    // esperarse en serie.
    final futuroEstado = estadoCajaEnVivo(db, sesion.id);
    final futuroResumen = resumenDiaHistorico(db, sesion.id);
    final futuroCantidadVentas = cantidadVentasDelDia(db, sesion.id);
    final estado = await futuroEstado;
    final resumen = await futuroResumen;
    final cantidadVentas = await futuroCantidadVentas;
    return _json({
      'sesionId': sesion.id,
      'fechaApertura': sesion.fechaApertura.toIso8601String(),
      'efectivoEsperadoCentavos': estado.efectivoEsperadoCentavos,
      'mpEsperadoCentavos': estado.mpEsperadoCentavos,
      'redondeoAcumuladoCentavos': estado.redondeoAcumuladoCentavos,
      'lataInicialCentavos': estado.lataInicialCentavos,
      'cantidadVentas': cantidadVentas,
      ..._resumenDiaAJson(resumen),
    });
  });

  // Apertura de emergencia desde el celular (El dueño, 2026-09-07: "como
  // comparten la misma bd no podemos abrirla desde la app"): mismo
  // `abrirSesion` que usa `dialogo_apertura_caja.dart` en el escritorio
  // (Regla 3) — nace solo dentro del flujo de Gasto rápido cuando la caja
  // está cerrada, no es un acceso de menú aparte todavía. Sin el aviso de
  // "para separar" que sí tiene la apertura de escritorio: es información
  // de arranque normal del día, no algo que pinte en un desbloqueo puntual.
  router.post('/sesion/abrir', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    try {
      final id = await abrirSesion(
        db,
        usuarioId: _intRequerido(body, 'usuarioId'),
        fondoInicialCentavos: _intRequerido(body, 'fondoInicialCentavos'),
      );
      return _json({'id': id}, status: 201);
    } on SesionYaAbiertaException catch (e) {
      // Bloqueo directo (El dueño, 2026-09-19: "aislar los usuarios para que
      // no se pisen") — el segundo dispositivo se entera de quién y desde
      // cuándo, en vez de abrir en silencio con otros montos.
      final usuario = await (db.select(
        db.usuarios,
      )..where((u) => u.id.equals(e.sesion.usuarioAbrioId))).getSingleOrNull();
      final nombre = usuario?.nombre ?? 'otro usuario';
      final apertura = e.sesion.fechaApertura;
      final hora =
          '${apertura.hour.toString().padLeft(2, '0')}:${apertura.minute.toString().padLeft(2, '0')}';
      return _error(409, 'Ya la abrió $nombre a las $hora');
    }
  });

  router.post('/gastos', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final medioTexto = _textoRequerido(body, 'medio');
    final medio = MedioGasto.values
        .where((m) => m.name == medioTexto)
        .firstOrNull;
    if (medio == null) {
      throw FormatException(
        '"medio" tiene que ser uno de: ${MedioGasto.values.map((m) => m.name).join(', ')}',
      );
    }
    try {
      final movimientoId = await registrarGastoRapido(
        db,
        sesionCajaId: _intRequerido(body, 'sesionCajaId'),
        usuarioId: _intRequerido(body, 'usuarioId'),
        montoCentavos: _intRequerido(body, 'montoCentavos'),
        medio: medio,
        motivo: body['motivo'] as String?,
      );
      return _json({'id': movimientoId}, status: 201);
    } on SesionCerradaException {
      // El dueño, 2026-09-19: "aislar los usuarios para que no se pisen" — un
      // gasto que llega justo después de un cierre no se grabó contra una
      // sesión cerrada sin que nadie se entere.
      return _error(409, 'La caja ya se cerró, este gasto no se guardó');
    }
  });

  // "Ingreso rápido" (El dueño, 2026-09-13: "un botón de ingreso de dinero,
  // evidentemente siguiendo con las cajas que hay") — espejo exacto de
  // `/gastos`, mismas tres cajas (`MedioGasto`, reusado), tipo 'INGRESO'.
  router.post('/ingresos', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final medioTexto = _textoRequerido(body, 'medio');
    final medio = MedioGasto.values
        .where((m) => m.name == medioTexto)
        .firstOrNull;
    if (medio == null) {
      throw FormatException(
        '"medio" tiene que ser uno de: ${MedioGasto.values.map((m) => m.name).join(', ')}',
      );
    }
    try {
      final movimientoId = await registrarIngresoRapido(
        db,
        sesionCajaId: _intRequerido(body, 'sesionCajaId'),
        usuarioId: _intRequerido(body, 'usuarioId'),
        montoCentavos: _intRequerido(body, 'montoCentavos'),
        medio: medio,
        motivo: body['motivo'] as String?,
      );
      return _json({'id': movimientoId}, status: 201);
    } on SesionCerradaException {
      return _error(409, 'La caja ya se cerró, este ingreso no se guardó');
    }
  });

  // ─── Vender (El dueño, 2026-09-07: "que la parte de vender use la misma
  // lógica que la app de desktop") ─────────────────────────────────────
  //
  // El carrito vive en el celular como una lista de `LineaVenta` (mismo
  // tipo del dominio, serializado por `lineaVentaAJson`/`lineaVentaDesdeJson`
  // — ver `domain/venta_json.dart`), armada con lo que ya devolvió
  // `/ventas/buscar`: el precio y el costo quedan "congelados" en el momento
  // en que se tocó el producto (Regla 2, costo-foto), no al calcular o
  // cobrar. Nada de lo de acá recalcula una fórmula nueva — todo pasa por
  // las mismas funciones que ya usa `VentaControlador` (Regla 3). Sin
  // Mixto ni descuento en esta primera versión (decisión de el dueño,
  // 2026-09-07): Efectivo, QR y Débito alcanzan para arrancar.

  router.get('/ventas/buscar', (Request request) async {
    final texto = request.url.queryParameters['texto'] ?? '';
    // `exigirStock=false` para la carga histórica (El dueño: "no descuentan
    // stock... para saber ganancias") — un producto vendido en su momento
    // puede estar en 0 hoy por cualquier otro motivo, mismo criterio que
    // `repositorio_carga_historica.dart` del escritorio.
    final exigirStock = request.url.queryParameters['exigirStock'] != 'false';
    final catalogo = await db.select(db.productos).get();
    final consulta = interpretarTexto(texto);
    // "Varios" no entra en esta primera versión (decisión de el dueño) — sin
    // este filtro aparecería igual, porque `tieneStock` lo trata como que
    // siempre tiene stock.
    final resultados = buscarProductos(
      catalogo: catalogo,
      textoBuscado: texto,
      exigirStock: exigirStock,
    ).where((p) => !p.esVarios).toList();
    return _json({
      'gramos': ?consulta.gramos,
      'resultados': [for (final p in resultados) _productoAJson(p)],
    });
  });

  router.post('/ventas/calcular', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final (tipoDescuento, valorDescuento) = _descuentoDesdeBody(body);
    final resultado = await calcularResultadoVenta(
      db,
      lineas: _lineasDesdeBody(body),
      medio: composicionPagoDesdeTexto(_textoRequerido(body, 'medio')),
      tipoDescuento: tipoDescuento,
      valorDescuento: valorDescuento,
    );
    return _json(_resultadoAJson(resultado));
  });

  // Efectivo (sin posnet) — QR/Débito pasan por el ciclo de tres pasos de
  // abajo, nunca por acá.
  // `canal` es opcional acá: solo tiene sentido con medio virtual "cobrado
  // a mano" (El dueño, 2026-09-07: el pago no pasó por el ciclo de Point,
  // pero sigue siendo QR/Débito para el dato informativo del medio) — con
  // efectivo nunca viaja.
  router.post('/ventas/cobrar', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final (tipoDescuento, valorDescuento) = _descuentoDesdeBody(body);
    // Si el celular no recibió la respuesta y vuelve a mandar el mismo cobro (misma clave), se devuelve la venta ya grabada.
    final clave = body['claveCobro'] as String?;
    final yaCobrada = clave == null ? null : _cobrosRecientes.buscar(clave);
    if (yaCobrada != null) {
      return _json({'ventaId': yaCobrada.ventaId, 'totalCentavos': yaCobrada.totalCentavos});
    }
    final ({int ventaId, int totalCentavos}) resultado;
    try {
      resultado = await registrarVentaSegunMedio(
        db,
        lineas: _lineasDesdeBody(body),
        medio: composicionPagoDesdeTexto(_textoRequerido(body, 'medio')),
        canal: body['canal'] as String?,
        sesionCajaId: _intRequerido(body, 'sesionCajaId'),
        usuarioId: _intRequerido(body, 'usuarioId'),
        tipoDescuento: tipoDescuento,
        valorDescuento: valorDescuento,
        encargueId: body['encargueId'] as int?,
      );
    } on SesionCerradaException {
      return _error(409, 'La caja ya se cerró, esta venta no se guardó');
    }
    if (clave != null) _cobrosRecientes.guardar(clave, resultado);
    return _json({
      'ventaId': resultado.ventaId,
      'totalCentavos': resultado.totalCentavos,
    }, status: 201);
  });

  // Cobro por terminal Point — mismo ciclo de tres pasos que
  // `dialogo_cobro_posnet.dart` del escritorio: iniciar, el celular hace su
  // propio polling sobre `estado/<id>` (mismo ritmo,
  // `intervaloPollingCobroPosnet`/`timeoutPollingCobroPosnet`), y recién
  // graba la venta cuando confirma que se aprobó.
  router.post('/ventas/posnet/iniciar', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    // Directo con el access token de la PC si está cargado (lo de siempre); si no, por el servidor con la cuenta conectada.
    final PasarelaPoint pasarela;
    try {
      pasarela = await _pasarelaPoint(db, httpClientDePrueba);
    } on CobroPosnetException catch (e) {
      return _error(400, e.mensaje);
    }

    final canal = _textoRequerido(body, 'canal');
    final (tipoDescuento, valorDescuento) = _descuentoDesdeBody(body);
    final resultado = await calcularResultadoVenta(
      db,
      lineas: _lineasDesdeBody(body),
      medio: ComposicionPago.virtual,
      tipoDescuento: tipoDescuento,
      valorDescuento: valorDescuento,
    );
    final pendiente = await crearOrdenPendiente(
      db,
      sesionCajaId: _intRequerido(body, 'sesionCajaId'),
      canal: canal,
      montoCentavos: resultado.totalCentavos,
    );
    try {
      final creada = await pasarela.crear(
        externalReference: pendiente.externalReference,
        idempotencyKey: pendiente.idempotencyKey,
        montoCentavos: resultado.totalCentavos,
        canal: canal,
      );
      await marcarOrdenConId(db, id: pendiente.id, ordenIdMp: creada.ordenIdMp);
      return _json({
        'ordenPendienteId': pendiente.id,
        'ordenIdMp': creada.ordenIdMp,
        'totalCentavos': resultado.totalCentavos,
      }, status: 201);
    } on CobroPosnetException catch (e) {
      return _error(502, e.mensaje);
    }
  });

  router.get('/ventas/posnet/estado/<ordenIdMp>', (
    Request request,
    String ordenIdMp,
  ) async {
    try {
      final estado = await (await _pasarelaPoint(db, httpClientDePrueba, soloToken: true)).consultar(ordenIdMp);
      return _json({'estado': clasificarEstadoOrden(estado).name});
    } on CobroPosnetException catch (e) {
      return _error(502, e.mensaje);
    }
  });

  // El pago se aprobó: recién acá se graba la venta real (misma regla que
  // `VentaControlador.confirmarCobroPosnetAprobado` — nunca antes).
  router.post('/ventas/posnet/confirmar', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    // El descuento tiene que viajar de nuevo acá, con el mismo valor que
    // se usó en `/ventas/posnet/iniciar` — esta ruta recalcula el total
    // desde cero (`registrarVentaSegunMedio`), no reusa el de la orden.
    final (tipoDescuento, valorDescuento) = _descuentoDesdeBody(body);
    final ({int ventaId, int totalCentavos}) resultado;
    try {
      resultado = await registrarVentaSegunMedio(
        db,
        lineas: _lineasDesdeBody(body),
        medio: ComposicionPago.virtual,
        canal: _textoRequerido(body, 'canal'),
        sesionCajaId: _intRequerido(body, 'sesionCajaId'),
        usuarioId: _intRequerido(body, 'usuarioId'),
        tipoDescuento: tipoDescuento,
        valorDescuento: valorDescuento,
        encargueId: body['encargueId'] as int?,
      );
    } on SesionCerradaException {
      // El pago ya se cobró en la terminal: la orden queda SIN resolver a propósito, así el cierre avisa que hay un cobro
      // por QR/Débito sin venta y se revisa a mano (`ordenesSinResolverDeSesion`).
      return _error(409, 'El pago se aprobó pero la caja ya estaba cerrada: la venta no se guardó. Revisalo en Mercado Pago');
    }
    await marcarOrdenResuelta(
      db,
      id: _intRequerido(body, 'ordenPendienteId'),
      estado: 'aprobada',
      ventaId: resultado.ventaId,
    );
    return _json({
      'ventaId': resultado.ventaId,
      'totalCentavos': resultado.totalCentavos,
    }, status: 201);
  });

  // El pago se rechazó — Mercado Pago ya resolvió la orden por su cuenta,
  // esto solo cierra el ciclo de la orden pendiente sin venta.
  router.post('/ventas/posnet/no-aprobado', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await marcarOrdenResuelta(
      db,
      id: _intRequerido(body, 'ordenPendienteId'),
      estado: _textoRequerido(body, 'estado'),
    );
    return _json({'ok': true});
  });

  // Cancelado desde el celular — mismo criterio que
  // `VentaControlador.cancelarCobroPosnet`: si `cancelarOrdenCobro` falla,
  // la fila se deja tal cual (sigue 'pendiente'), nunca se asume una
  // cancelación que Mercado Pago no confirmó.
  router.post('/ventas/posnet/cancelar', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final ordenIdMp = body['ordenIdMp'] as String?;
    if (ordenIdMp != null) {
      try {
        await (await _pasarelaPoint(db, httpClientDePrueba, soloToken: true)).cancelar(ordenIdMp);
      } on CobroPosnetException catch (e) {
        return _error(502, e.mensaje);
      }
    }
    await marcarOrdenResuelta(
      db,
      id: _intRequerido(body, 'ordenPendienteId'),
      estado: 'cancelada',
    );
    return _json({'ok': true});
  });

  // Desglose de una venta para el historial del celular (El dueño,
  // 2026-09-13: "en las ventas se pueda ver un desglose") — mismo `Ticket`
  // que ya arma `ticketDeVenta` para imprimir (Regla 3, una sola fuente):
  // líneas con cantidad/gramos y subtotal, más recargo/descuento/redondeo.
  router.get('/ventas/<id>/detalle', (Request request, String id) async {
    final ventaId = int.tryParse(id);
    if (ventaId == null) return _error(400, 'Id de venta inválido');
    final ticket = await ticketDeVenta(db, ventaId);
    return _json({
      'fecha': ticket.fecha.toIso8601String(),
      'vendedor': ticket.vendedor,
      'lineas': [
        for (final l in ticket.lineas)
          {
            'nombreProducto': l.nombreProducto,
            'cantidad': l.cantidad,
            'gramos': l.gramos,
            'subtotalCentavos': l.subtotalCentavos,
          },
      ],
      'recargoCigarrillosCentavos': ticket.desglose.recargoCigarrillosCentavos,
      'descuentoCentavos': ticket.desglose.descuentoCentavos,
      'redondeoCentavos': ticket.desglose.redondeoCentavos,
      'totalCentavos': ticket.totalCentavos,
    });
  });

  // Botón manual de ticket, mismo camino que "Enviar a posnet" del diálogo
  // de Impresión (`dialogo_imprimir_ticket.dart`) — la terminal de imprimir
  // (`mpTerminalId`) es la que ya se usa en el escritorio, no la de cobro.
  router.post('/ventas/<id>/imprimir', (Request request, String id) async {
    final ventaId = int.tryParse(id);
    if (ventaId == null) return _error(400, 'Id de venta inválido');
    final config = await db.select(db.configuracionTabla).getSingle();
    try {
      final ticket = await ticketDeVenta(db, ventaId);
      await imprimirTicketPosnet(
        accessToken: config.mpAccessToken,
        terminalId: config.mpTerminalId,
        terminalCobroId: config.mpTerminalCobroId,
        forzarNube: PreferenciaCobroNube.activo,
        almacen: nubeApp?.almacen,
        cliente: nubeApp?.cliente,
        ticket: ticket,
        encabezadoNegocio: (await marcaDeBase(db)).encabezadoTicketEfectivo,
        client: httpClientDePrueba,
      );
      return _json({'ok': true});
    } on ImpresionPosnetException catch (e) {
      return _error(502, e.mensaje);
    }
  });

  // Carga histórica desde el celular (El dueño, 2026-09-07: "se le pone la
  // fecha, después es como si fuesen ventas que no descuentan stock...
  // para saber ganancias") — el celular junta las ventas del día en
  // memoria (nada se graba hasta este único POST, mismo criterio que
  // `CargaHistoricaControlador` del escritorio) y acá se arman con las
  // mismas `calcularTotalVenta`/`_pagosDesdeMedio` de siempre antes de
  // pasarle todo junto a `cargarDiaHistoricoDesdeVentas` (Regla 3: la
  // transacción — sesión + cada venta + cierre automático — es la misma
  // función que ya usa la pantalla de escritorio, no una nueva).
  router.post('/historico/dia', (Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final fecha = DateTime.parse(_textoRequerido(body, 'fecha'));
    final usuarioId = _intRequerido(body, 'usuarioId');
    final pendientes = await _pendientesHistoricosDesdeBody(
      db,
      body['ventas'] as List,
    );

    final sesionId = await cargarDiaHistoricoDesdeVentas(
      db,
      fecha: fecha,
      usuarioId: usuarioId,
      ventas: pendientes,
    );
    return _json({'sesionId': sesionId}, status: 201);
  });

  // Ver y editar días ya cargados (El dueño, 2026-09-07: "dejame verlos y
  // editarlos porque le erré y lo cerré sin completarlo").
  router.get('/historico/dias', (Request request) async {
    final dias = await listarDiasHistoricos(db);
    return _json([
      for (final d in dias)
        {
          'sesionId': d.sesionId,
          'fecha': d.fecha.toIso8601String(),
          'totalCentavos': d.totalCentavos,
          'cantidadVentas': d.cantidadVentas,
        },
    ]);
  });

  router.get('/historico/dias/<sesionId>', (
    Request request,
    String sesionId,
  ) async {
    final id = int.tryParse(sesionId);
    if (id == null) return _error(400, 'Id de sesión inválido');
    final ventas = await ventasDeDiaHistorico(db, id);
    return _json([
      for (final v in ventas)
        {
          'ventaId': v.ventaId,
          'totalCentavos': v.totalCentavos,
          'medioResumen': v.medioResumen,
          'detalle': v.detalle,
        },
    ]);
  });

  // Resumen del día (El dueño, 2026-09-07: "necesitaría un resumen de lo
  // vendido por medio de pago, por proveedor, y la separación teórica")
  // — reusa `reposicionDelDia`/`efectivoDeVentasDelDia`/
  // `pagosNoEfectivoDelDia`, las mismas que ya usa "Reportes" del
  // escritorio (Regla 3).
  router.get('/historico/dias/<sesionId>/resumen', (
    Request request,
    String sesionId,
  ) async {
    final id = int.tryParse(sesionId);
    if (id == null) return _error(400, 'Id de sesión inválido');
    final resumen = await resumenDiaHistorico(db, id);
    return _json(_resumenDiaAJson(resumen));
  });

  router.post('/historico/dias/<sesionId>/agregar', (
    Request request,
    String sesionId,
  ) async {
    final id = int.tryParse(sesionId);
    if (id == null) return _error(400, 'Id de sesión inválido');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final pendientes = await _pendientesHistoricosDesdeBody(
      db,
      body['ventas'] as List,
    );
    await agregarVentasADiaHistorico(
      db,
      sesionId: id,
      usuarioId: _intRequerido(body, 'usuarioId'),
      ventas: pendientes,
    );
    return _json({'ok': true});
  });

  router.delete('/historico/dias/<sesionId>/ventas/<ventaId>', (
    Request request,
    String sesionId,
    String ventaId,
  ) async {
    final id = int.tryParse(ventaId);
    if (id == null) return _error(400, 'Id de venta inválido');
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    await eliminarVentaHistorica(
      db,
      ventaId: id,
      usuarioId: _intRequerido(body, 'usuarioId'),
    );
    return _json({'ok': true});
  });

  router.delete('/historico/dias/<sesionId>', (
    Request request,
    String sesionId,
  ) async {
    final id = int.tryParse(sesionId);
    if (id == null) return _error(400, 'Id de sesión inválido');
    await eliminarDiaHistorico(db, sesionId: id);
    return _json({'ok': true});
  });

  // ─── Sincronización fila por fila (fase 2 del rediseño "companion sin
  // depender del escritorio") — ver `lib/data/repositorio_sincronizacion.dart`
  // para el mecanismo completo. Acá solo se traduce HTTP↔función: la PC no
  // sabe ni le importa si quien pide `/sync/cambios` es el celular
  // sincronizando o al revés (`aplicarCambios` es simétrica), así que estos
  // dos endpoints son los únicos que la PC necesita exponer.
  router.get('/sync/cambios', (Request request) async {
    final tabla = request.url.queryParameters['tabla'];
    final desdeTexto = request.url.queryParameters['desde'];
    if (tabla == null || desdeTexto == null) {
      return _error(400, 'Faltan "tabla" y/o "desde"');
    }
    final desde = int.tryParse(desdeTexto);
    if (desde == null) return _error(400, '"desde" tiene que ser un entero');
    final filas = await cambiosDesde(db, tabla: tabla, desde: desde);
    return _json({'filas': filas, 'cursor': cursorMaximo(tabla, filas)});
  });

  router.post('/sync/cambios', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final tabla = body['tabla'] as String?;
    final filas = body['filas'] as List?;
    if (tabla == null || filas == null) {
      return _error(400, 'Faltan "tabla" y/o "filas"');
    }
    final noAplicadas = await aplicarCambios(
      db,
      tabla: tabla,
      filas: [for (final f in filas) Map<String, dynamic>.from(f as Map)],
    );
    // Alguna fila quedó sin aplicar (típicamente fuera de orden real: su
    // referencia todavía no existe en esta base) — error para que quien
    // empujó no avance su cursor y reintente la tanda entera más tarde
    // (`aplicarCambios` es idempotente, reintentar de más no duplica nada).
    if (noAplicadas.isNotEmpty) {
      return _error(409, '${noAplicadas.length} fila(s) de "$tabla" fuera de orden, reintentar');
    }
    return _json({'ok': true});
  });

  return router;
}

/// Descuento sobre el total (Regla 17 generalizada) desde el body de una
/// request — `tipoDescuento` ausente o `null` significa "sin descuento",
/// mismo criterio que `VentaControlador._calcularCon` del escritorio
/// (`valorDescuento == 0 ? null : tipoDescuento`).
(TipoDescuento?, int) _descuentoDesdeBody(Map<String, dynamic> body) {
  final texto = body['tipoDescuento'] as String?;
  if (texto == null) return (null, 0);
  final tipo = switch (texto) {
    'monto' => TipoDescuento.monto,
    'porcentaje' => TipoDescuento.porcentaje,
    _ => throw FormatException(
      '"tipoDescuento" tiene que ser "monto" o "porcentaje"',
    ),
  };
  return (tipo, _int(body['valorDescuento']) ?? 0);
}

Map<String, dynamic> _resumenDiaAJson(ResumenDiaHistorico resumen) => {
  'totalCentavos': resumen.totalCentavos,
  'efectivoCentavos': resumen.efectivoCentavos,
  'mercadoPagoCentavos': resumen.mercadoPagoCentavos,
  'cigarrillosListaCentavos': resumen.cigarrillosListaCentavos,
  'vendidoSinCostoCentavos': resumen.vendidoSinCostoCentavos,
  'productosSinDatos': [
    for (final p in resumen.productosSinDatos)
      {
        'productoId': ?p.productoId,
        'nombreProducto': p.nombreProducto,
        'vendidoCentavos': p.vendidoCentavos,
        'sinProveedor': p.sinProveedor,
        'sinCosto': p.sinCosto,
      },
  ],
  'porProveedor': [
    for (final p in resumen.porProveedor)
      {
        'proveedorId': p.proveedorId,
        'nombreProveedor': p.nombreProveedor,
        'vendidoCentavos': p.vendidoCentavos,
        'costoRealCentavos': p.costoRealCentavos,
        'gananciaCentavos': p.gananciaCentavos,
      },
  ],
};

/// Combina `ResumenCierre` (arqueo/cigarrillos/redondeo/reserva) con
/// `ResumenDiaHistorico` (desglose por proveedor) en un solo JSON — usado
/// tanto por `/sesion/cerrar/calcular` (vista previa en vivo) como por
/// `/sesiones/cerradas/<id>/detalle` (un cierre ya guardado), Regla 3: la
/// misma forma de "cómo se ve un cierre" en los dos casos.
Map<String, dynamic> _resumenCierreAJson(ResumenCierre resumen, ResumenDiaHistorico resumenDia) => {
  'efectivoEsperadoCentavos': resumen.efectivoEsperadoCentavos,
  'diferenciaCentavos': resumen.diferenciaCentavos,
  'mpEsperadoCentavos': resumen.mpEsperadoCentavos,
  'mpDiferenciaCentavos': ?resumen.mpDiferenciaCentavos,
  'lataFinalCentavos': resumen.lataFinalCentavos,
  'lataDiferenciaCentavos': ?resumen.lataDiferenciaCentavos,
  'separadoCentavos': resumen.separacionCigarrillos.separadoCentavos,
  'pendienteCentavos': resumen.separacionCigarrillos.pendienteCentavos,
  'esSeparacionParcial': resumen.separacionCigarrillos.esSeparacionParcial,
  'redondeoAcumuladoCentavos': resumen.redondeoAcumuladoCentavos,
  'reservaDiariaFijosCentavos': ?resumen.reservaDiariaFijosCentavos,
  ..._resumenDiaAJson(resumenDia),
};

Map<String, dynamic> _resultadoAJson(ResultadoTotalVenta r) => {
  'subtotalCentavos': r.subtotalCentavos,
  'recargoCigarrillosCentavos': r.recargoCigarrillosCentavos,
  'descuentoCentavos': r.descuentoCentavos,
  'redondeoCentavos': r.redondeoCentavos,
  'totalCentavos': r.totalCentavos,
};

List<LineaVenta> _lineasDesdeBody(Map<String, dynamic> body) {
  final lineas = body['lineas'] as List;
  return lineas.cast<Map<String, dynamic>>().map(lineaVentaDesdeJson).toList();
}

/// Arma la lista de `VentaHistoricaPendiente` a partir del `ventas` del
/// body — lo comparten crear un día nuevo (`/historico/dia`) y agregar a
/// uno ya cargado (`/historico/dias/<id>/agregar`), Regla 3.
Future<List<VentaHistoricaPendiente>> _pendientesHistoricosDesdeBody(
  AppDatabase db,
  List ventasBody,
) async {
  // `configuracion_negocio_tabla` (1 fila) y los dos `mediosDePago` (2 filas
  // en total) se resuelven una sola vez para TODAS las ventas del día, no
  // una vez por venta — un día cargado desde el celular con 50-100 ventas
  // eran hasta 300 consultas SQLite chicas evitables dentro de una sola
  // request HTTP.
  final config = await configuracionNegocioActual(db);
  final medioEfectivo = await (db.select(
    db.mediosDePago,
  )..where((m) => m.esEfectivo.equals(true))).getSingle();
  final medioVirtual = await (db.select(
    db.mediosDePago,
  )..where((m) => m.esEfectivo.equals(false))).getSingle();

  final pendientes = <VentaHistoricaPendiente>[];
  for (final ventaBody in ventasBody.cast<Map<String, dynamic>>()) {
    final lineas = _lineasDesdeBody(ventaBody);
    final medio = composicionPagoDesdeTexto(_textoRequerido(ventaBody, 'medio'));
    final resultado = await calcularResultadoVenta(
      db,
      lineas: lineas,
      medio: medio,
      configuracionNegocio: config,
    );
    final pagos = await pagosSegunMedio(
      db,
      medio: medio,
      totalCentavos: resultado.totalCentavos,
      montoEfectivoMixtoCentavos: _int(ventaBody['montoEfectivoMixtoCentavos']),
      medioEfectivoResuelto: medioEfectivo,
      medioVirtualResuelto: medioVirtual,
    );
    pendientes.add(
      VentaHistoricaPendiente(
        venta: Venta(lineas: lineas),
        resultado: resultado,
        pagos: pagos,
      ),
    );
  }
  return pendientes;
}

/// Arranca el servidor en `0.0.0.0:[puerto]` (no solo `localhost`, para que
/// se pueda alcanzar desde el celular) y devuelve el `HttpServer` ya
/// escuchando, para poder cerrarlo (`server.close()`) desde quien lo llamó
/// (`main.dart`, al cerrar la app).
Future<HttpServer> iniciarServidorCompanion(
  AppDatabase db, {
  int puerto = puertoServidorCompanion,
  http.Client? httpClientDePrueba,
}) {
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_autenticacion(db))
      .addMiddleware(_avisoDeCambios())
      .addMiddleware(_conManejoDeErrores)
      .addHandler(
        _armarRouter(db, httpClientDePrueba: httpClientDePrueba).call,
      );
  return shelf_io.serve(handler, InternetAddress.anyIPv4, puerto);
}

/// De una lista de IPs candidatas, la más probable de ser "la de la WiFi
/// del local" — prefiere los rangos privados típicos de una red casera/de
/// oficina (192.168.x.x, 10.x.x.x, 172.16-31.x.x) sobre cualquier otra cosa
/// que una interfaz de red pueda traer (VPN, virtual, etc.). `null` si la
/// lista viene vacía (sin red conectada).
String? ipRecomendada(List<String> ips) {
  if (ips.isEmpty) return null;
  bool esPrivada(String ip) {
    final octetos = ip.split('.').map(int.tryParse).toList();
    if (octetos.length != 4 || octetos.any((o) => o == null)) return false;
    final a = octetos[0]!;
    final b = octetos[1]!;
    return a == 192 && b == 168 || a == 10 || (a == 172 && b >= 16 && b <= 31);
  }

  return ips.firstWhere(esPrivada, orElse: () => ips.first);
}

/// Direcciones IPv4 de la PC en su red local (excluye loopback) — es lo que
/// se muestra en el QR de emparejamiento para que el celular sepa a qué IP
/// conectarse. Puede haber más de una si la máquina tiene varias interfaces
/// de red (WiFi + Ethernet, por ejemplo).
Future<List<String>> direccionesIpLocales() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  return [
    for (final interfaz in interfaces)
      for (final direccion in interfaz.addresses) direccion.address,
  ];
}


/// Los últimos cobros por clave de intento (`claveCobro`): vive en memoria porque solo sirve para el reintento inmediato
/// de un celular que no recibió la respuesta; pasados unos minutos una clave repetida ya no es un reintento.
final _cobrosRecientes = _CobrosRecientes();

class _CobrosRecientes {
  static const _vida = Duration(minutes: 10);
  static const _maximo = 200;
  final _datos = <String, ({int ventaId, int totalCentavos, DateTime en})>{};

  ({int ventaId, int totalCentavos})? buscar(String clave) {
    final d = _datos[clave];
    if (d == null) return null;
    if (DateTime.now().difference(d.en) > _vida) {
      _datos.remove(clave);
      return null;
    }
    return (ventaId: d.ventaId, totalCentavos: d.totalCentavos);
  }

  void guardar(String clave, ({int ventaId, int totalCentavos}) r) {
    if (_datos.length >= _maximo) _datos.remove(_datos.keys.first);
    _datos[clave] = (ventaId: r.ventaId, totalCentavos: r.totalCentavos, en: DateTime.now());
  }
}
