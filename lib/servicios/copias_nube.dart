// Las copias de la base en la cuenta de Nodo Sur: armar una copia (VACUUM INTO → gzip → hash), subirla,
// y bajar una para restaurar. Toda falla vuelve como un resultado con texto, nunca como excepción hacia la caja:
// un cierre ya hecho no puede parecer fallido porque no haya internet (mismo criterio que el respaldo local).

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../data/database.dart';
import '../domain/respaldo.dart';
import 'cuenta_nube.dart';

/// Lo que se ve de un intento de subir.
sealed class ResultadoSubida {
  const ResultadoSubida();
}

class SubidaOk extends ResultadoSubida {
  const SubidaOk(this.id);
  final int id;
}

class SubidaSinCuenta extends ResultadoSubida {
  const SubidaSinCuenta();
}

class SubidaFallida extends ResultadoSubida {
  const SubidaFallida(this.mensaje, {this.pideVincular = false});
  final String mensaje;

  /// La cuenta ya no vale: la pantalla ofrece "Vincular de nuevo".
  final bool pideVincular;
}

/// Base comprimida lista para subir.
class CopiaArmada {
  const CopiaArmada(this.bytes, this.sha256);
  final List<int> bytes;
  final String sha256;
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Los datos que dan acceso a un servicio o a la caja y que NO viajan en la copia de la nube: el servidor la cifra,
/// pero quien opera el servidor puede descifrarla, y un token de pago no tiene por qué estar ahí. Se vuelven a
/// cargar a mano tras restaurar (el de Mercado Pago en Configuración → Impresión; el del celular, emparejando de nuevo).
const _sentenciaSinSecretos = 'UPDATE configuracion_tabla SET mp_access_token = NULL, companion_token = NULL';

/// Vacía los secretos de una copia ya hecha. `secure_delete` y `VACUUM` después: sin eso el texto viejo queda en las
/// páginas libres del archivo y se podría leer igual.
void _quitarSecretos(String ruta) {
  final base = sqlite.sqlite3.open(ruta);
  try {
    base.execute('PRAGMA secure_delete = ON');
    base.execute(_sentenciaSinSecretos);
    base.execute('VACUUM');
  } finally {
    base.close();
  }
}

/// Copia consistente de la base en uso, comprimida. `VACUUM INTO` es atómico aunque la base esté abierta.
/// Con [sinSecretos] (lo que va a la nube) se vacían los tokens antes de comprimir.
Future<CopiaArmada> armarCopia(AppDatabase db, {required Directory carpetaTemporal, bool sinSecretos = true}) async {
  await carpetaTemporal.create(recursive: true);
  final crudo = File(p.join(carpetaTemporal.path, 'copia_${DateTime.now().microsecondsSinceEpoch}.sqlite'));
  try {
    await db.customStatement('VACUUM INTO ?', [crudo.path]);
    if (sinSecretos) _quitarSecretos(crudo.path);
    final comprimido = gzip.encode(await crudo.readAsBytes());
    return CopiaArmada(comprimido, sha256Hex(comprimido));
  } finally {
    if (await crudo.exists()) await crudo.delete();
  }
}

class ErrorRestauracion implements Exception {
  const ErrorRestauracion(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

/// Una copia ya bajada, verificada y descomprimida, lista para reemplazar la base.
class CopiaParaRestaurar {
  const CopiaParaRestaurar(this.ruta, this.schemaVersion);
  final String ruta;
  final int schemaVersion;
}

class ServicioCopiasNube {
  ServicioCopiasNube({
    required this.db,
    required this.almacen,
    required this.cliente,
    required this.carpetaTemporal,
    required this.versionApp,
    this.leerUltimaSubida,
    this.guardarUltimaSubida,
    this.reloj = DateTime.now,
  });

  final AppDatabase db;
  final AlmacenCuenta almacen;
  final ClienteNube cliente;
  final Directory carpetaTemporal;
  final Future<String> Function() versionApp;
  final Future<DateTime?> Function()? leerUltimaSubida;
  final Future<void> Function(DateTime)? guardarUltimaSubida;
  final DateTime Function() reloj;

  bool _subiendo = false;
  Timer? _timer;

  /// Sube una copia ahora. Nunca tira.
  Future<ResultadoSubida> subirAhora() async {
    if (_subiendo) return const SubidaFallida('Ya se está guardando una copia.');
    final cuenta = await almacen.leer();
    if (cuenta == null) return const SubidaSinCuenta();
    _subiendo = true;
    try {
      final copia = await armarCopia(db, carpetaTemporal: carpetaTemporal);
      final r = await cliente.subir(
        cuenta.token,
        bytes: copia.bytes,
        sha256: copia.sha256,
        schemaVersion: db.schemaVersion,
        appVersion: await versionApp(),
      );
      await guardarUltimaSubida?.call(reloj());
      return SubidaOk(r.id);
    } on ErrorNube catch (e) {
      return SubidaFallida(e.mensaje, pideVincular: e.pideVincularDeNuevo);
    } catch (e) {
      return SubidaFallida('No se pudo guardar la copia: $e');
    } finally {
      _subiendo = false;
    }
  }

  /// Al cerrar caja: sube si hay cuenta. Para la pantalla de cierre el resultado es solo informativo.
  Future<ResultadoSubida> despuesDelCierre() => subirAhora();

  /// Una vez por día (cada [cada] se revisa si pasaron 24 h desde la última subida) mientras la app esté abierta.
  void iniciarCopiaDiaria({Duration cada = const Duration(hours: 1), Duration intervalo = const Duration(hours: 24)}) {
    _timer?.cancel();
    _timer = Timer.periodic(cada, (_) => unawaited(_copiaDiariaSiCorresponde(intervalo)));
  }

  Future<void> _copiaDiariaSiCorresponde(Duration intervalo) async {
    if (await almacen.leer() == null) return;
    final ultima = await leerUltimaSubida?.call();
    if (ultima != null && reloj().difference(ultima) < intervalo) return;
    await subirAhora();
  }

  void detener() => _timer?.cancel();

  /// Avisa al servidor que la PC está viva (versión, sistema, id de instalación). Si trae un token renovado lo
  /// guarda. Devuelve el canal ('beta' para el administrador) o null si no se pudo.
  Future<String?> avisarYRenovar({required String cid, required String sistema}) async {
    final cuenta = await almacen.leer();
    if (cuenta == null) return null;
    try {
      final r = await cliente.avisar(cuenta.token, cid: cid, version: await versionApp(), sistema: sistema);
      if (r.tokenNuevo != null) await almacen.guardar(cuenta.conToken(r.tokenNuevo!));
      return r.canal;
    } catch (_) {
      return null;
    }
  }

  /// Baja la copia [id], comprueba que llegó completa y que no es de una versión más nueva que esta app, y la
  /// deja descomprimida en la carpeta temporal.
  Future<CopiaParaRestaurar> prepararRestauracion(int id) async {
    final cuenta = await almacen.leer();
    if (cuenta == null) throw const ErrorRestauracion('Primero vinculá esta PC a tu cuenta.');
    final baja = await cliente.bajar(cuenta.token, id);
    if (baja.sha256.isEmpty || sha256Hex(baja.bytes) != baja.sha256.toLowerCase()) {
      throw const ErrorRestauracion('La copia llegó dañada. Probá de nuevo.');
    }
    final List<int> crudo;
    try {
      crudo = gzip.decode(baja.bytes);
    } catch (_) {
      throw const ErrorRestauracion('La copia no se pudo abrir.');
    }
    final version = versionDeEsquemaDeArchivo(crudo);
    if (version == null) throw const ErrorRestauracion('La copia no es una base válida.');
    if (version > db.schemaVersion) {
      throw const ErrorRestauracion('Esa copia es de una versión más nueva de la app. Actualizá la app y volvé a probar.');
    }
    await carpetaTemporal.create(recursive: true);
    final archivo = File(p.join(carpetaTemporal.path, 'restaurar_${DateTime.now().microsecondsSinceEpoch}.sqlite'));
    await archivo.writeAsBytes(crudo, flush: true);
    return CopiaParaRestaurar(archivo.path, version);
  }
}
