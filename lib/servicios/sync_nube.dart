// Sincronización entre dispositivos a través de la nube de Nodo Sur: la PC (y
// después los celulares) suben sus cambios como lotes y bajan los de los
// demás. Cada cambio local dispara una vuelta; además hay un latido para
// enterarse de lo que subieron otros (El dueño, 2026-10-01: "cada modificación
// lanza una sync"; "si apago la PC el sistema tiene que seguir funcionando").
//
// Nunca tira una excepción hacia quien llama: una vuelta fallida es un
// resultado con texto, y la caja sigue como si nada. Sin internet no se
// pierde nada — lo que no subió se vuelve a calcular desde la base en la
// próxima vuelta.
//
// Primero BAJA y después SUBE: un dispositivo que vuelve de estar apagado
// aplica antes lo que se perdió, y lo suyo llega último (y gana) en vez de
// pisar a ciegas lo que otro hizo mientras tanto.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../data/registro_sync_nube.dart';
import 'cuenta_nube.dart';
import 'registro_errores.dart';

/// Dónde se guarda el registro de la sync. Fuera de la base, junto al token de
/// la cuenta: restaurar una copia no tiene que dejar un registro que diga que
/// filas que ya no están "ya se subieron".
abstract class AlmacenEstadoSync {
  Future<EstadoSyncNube> leer();
  Future<void> guardar(EstadoSyncNube estado);
  Future<void> borrar();
}

class AlmacenEstadoSyncEnMemoria implements AlmacenEstadoSync {
  Map<String, dynamic>? _json;

  @override
  Future<EstadoSyncNube> leer() async => EstadoSyncNube.desdeJson(_json);

  @override
  Future<void> guardar(EstadoSyncNube estado) async => _json = jsonDecode(jsonEncode(estado.toJson())) as Map<String, dynamic>;

  @override
  Future<void> borrar() async => _json = null;
}

class AlmacenEstadoSyncEnArchivo implements AlmacenEstadoSync {
  AlmacenEstadoSyncEnArchivo(this.carpeta);
  final String carpeta;

  File get _archivo => File(p.join(carpeta, 'nodosur_sync.json'));

  @override
  Future<EstadoSyncNube> leer() async {
    try {
      return EstadoSyncNube.desdeJson(jsonDecode(await _archivo.readAsString()));
    } catch (_) {
      return EstadoSyncNube();
    }
  }

  @override
  Future<void> guardar(EstadoSyncNube estado) async {
    await Directory(carpeta).create(recursive: true);
    // Temporal + renombrar: un corte a mitad de camino no deja el registro a medias.
    final tmp = File('${_archivo.path}.tmp');
    await tmp.writeAsString(jsonEncode(estado.toJson()), flush: true);
    await tmp.rename(_archivo.path);
  }

  @override
  Future<void> borrar() async {
    try {
      if (await _archivo.exists()) await _archivo.delete();
    } catch (e, pila) {
      await registrarError('Borrar el registro de la sync', e, pila);
    }
  }
}

sealed class ResultadoSyncNube {
  const ResultadoSyncNube();
}

class SyncNubeOk extends ResultadoSyncNube {
  const SyncNubeOk({required this.bajadas, required this.subidas});

  /// Filas aplicadas que venían de otros dispositivos.
  final int bajadas;

  /// Filas propias que se mandaron.
  final int subidas;
}

class SyncNubeSinCuenta extends ResultadoSyncNube {
  const SyncNubeSinCuenta();
}

/// El servidor ya no guarda lo que este dispositivo se perdió: hay que ponerse
/// al día desde una copia de seguridad.
class SyncNubeExpirada extends ResultadoSyncNube {
  const SyncNubeExpirada();
}

class SyncNubeFallida extends ResultadoSyncNube {
  const SyncNubeFallida(this.mensaje, {this.pideVincular = false, this.sinRed = false});
  final String mensaje;
  final bool pideVincular;

  /// No hay conexión (no es un error de la cuenta): se reintenta sola.
  final bool sinRed;
}

/// Cómo se le cuenta a la persona el estado de la sync, igual en la PC y en el celular (Regla 3: un solo lugar).
/// Solo hay tres tonos: todo bien, esperando (se arregla solo) y algo que tiene que tocar ella.
enum TonoSync { bien, espera, atencion }

class VistaSync {
  const VistaSync(this.tono, this.titulo, this.detalle, {this.puedeVolverABajar = false, this.pideVincular = false});
  final TonoSync tono;
  final String titulo;
  final String detalle;

  /// Se ofrece "Volver a bajar todo": el dispositivo quedó atrás de lo que guarda la nube.
  final bool puedeVolverABajar;

  /// Hay que volver a vincular la cuenta (el permiso de este dispositivo ya no vale).
  final bool pideVincular;
}

VistaSync vistaDeSync(ResultadoSyncNube? r) => switch (r) {
  null => const VistaSync(TonoSync.espera, 'Sincronizando…', 'Todavía no hubo una vuelta en esta sesión.'),
  SyncNubeOk(:final bajadas, :final subidas) => VistaSync(
    TonoSync.bien,
    'Al día',
    bajadas == 0 && subidas == 0 ? 'No hay nada pendiente.' : 'Recibió $bajadas y mandó $subidas cambios.',
  ),
  SyncNubeSinCuenta() => const VistaSync(TonoSync.atencion, 'Sin cuenta', 'Vinculá la cuenta para sincronizar por internet.', pideVincular: true),
  SyncNubeExpirada() => const VistaSync(
    TonoSync.atencion,
    'Quedó atrás de la nube',
    'Pasó mucho tiempo sin sincronizar. Podés bajar todo de nuevo: lo que cargaste acá y no estaba en la nube se conserva; si algo editado acá también cambió en otro dispositivo, queda la versión de la nube.',
    puedeVolverABajar: true,
  ),
  SyncNubeFallida(sinRed: true) => const VistaSync(
    TonoSync.espera,
    'Sin conexión',
    'Los cambios quedan guardados acá y se mandan solos cuando vuelva internet.',
  ),
  SyncNubeFallida(:final mensaje, pideVincular: true) => VistaSync(TonoSync.atencion, 'Hay que volver a vincular', mensaje, pideVincular: true),
  SyncNubeFallida(:final mensaje) => VistaSync(TonoSync.espera, 'No se pudo sincronizar', '$mensaje Se reintenta solo.'),
};

class ServicioSyncNube {
  ServicioSyncNube({
    required this.db,
    required this.almacenCuenta,
    required this.cliente,
    required this.almacenEstado,
    this.alAplicarBajada,
  });

  final AppDatabase db;
  final AlmacenCuenta almacenCuenta;
  final ClienteNube cliente;
  final AlmacenEstadoSync almacenEstado;

  /// Se llama cuando se aplicó algo que vino de otro dispositivo, para que las pantallas se refresquen.
  final void Function()? alAplicarBajada;

  /// Último resultado: lo que muestra la pantalla de dispositivos ("sin conexión", "al día").
  ResultadoSyncNube? get ultimo => _ultimo;
  set ultimo(ResultadoSyncNube? r) {
    _ultimo = r;
    alCambiarEstado.value++;
  }

  ResultadoSyncNube? _ultimo;

  /// Cambia con cada resultado nuevo, para que las pantallas muestren el estado sin tener que consultarlo.
  final ValueNotifier<int> alCambiarEstado = ValueNotifier(0);

  /// Hay una conexión de avisos abierta: mientras la haya no se consulta nada por las dudas.
  bool escuchando = false;

  bool _enCurso = false;

  /// Hay una vuelta corriendo. Quien necesita el resultado de una vuelta completa (decidir si un negocio es nuevo)
  /// espera a que termine, porque [sincronizar] encima de otra devuelve al instante el resultado anterior.
  bool get enCurso => _enCurso;
  bool _otraVez = false;
  bool _activa = false;
  int _generacion = 0;
  StreamSubscription<void>? _cambios;
  StreamSubscription<void>? _avisos;
  Completer<void>? _corteDeAvisos;
  Timer? _esperaSubida;
  Timer? _esperaBajada;
  Timer? _esperaReintento;

  /// Una vuelta completa (bajar, subir). Si ya hay una corriendo, anota que hace falta otra al terminar.
  Future<ResultadoSyncNube> sincronizar() async {
    if (_enCurso) {
      _otraVez = true;
      return ultimo ?? const SyncNubeOk(bajadas: 0, subidas: 0);
    }
    _enCurso = true;
    try {
      ResultadoSyncNube r;
      do {
        _otraVez = false;
        r = await _unaVuelta();
      } while (_otraVez && r is SyncNubeOk);
      return ultimo = r;
    } finally {
      _enCurso = false;
    }
  }

  Future<ResultadoSyncNube> _unaVuelta() async {
    final cuenta = await almacenCuenta.leer();
    if (cuenta == null) return const SyncNubeSinCuenta();
    try {
      final estado = await almacenEstado.leer();
      final bajadas = await _bajar(cuenta.token, estado);
      if (estado.necesitaCopia) return const SyncNubeExpirada();
      final subidas = await _subir(cuenta.token, estado);
      if (bajadas > 0) alAplicarBajada?.call();
      return SyncNubeOk(bajadas: bajadas, subidas: subidas);
    } on ErrorNube catch (e) {
      return SyncNubeFallida(e.mensaje, pideVincular: e.pideVincularDeNuevo, sinRed: e.codigo == 'sin_red');
    } catch (e) {
      return SyncNubeFallida('No se pudo sincronizar: $e');
    }
  }

  Future<int> _bajar(String token, EstadoSyncNube estado) async {
    var aplicadas = 0;
    var mas = true;
    while (mas) {
      final antes = estado.cursorBajada;
      final r = await cliente.bajarLotes(token, desde: antes);
      if (r.expirada) {
        estado.necesitaCopia = true;
        await almacenEstado.guardar(estado);
        return aplicadas;
      }
      aplicadas += await aplicarLotesBajados(db, estado, [
        for (final l in r.lotes) LoteBajado(seq: l.seq, deviceId: l.deviceId, creadoEn: l.creadoEn, bytes: l.bytes),
      ]);
      if (r.hasta > estado.cursorBajada) estado.cursorBajada = r.hasta;
      await almacenEstado.guardar(estado);
      // Una página puede traer solo lotes propios (no se devuelven) y aun así haber más: se sigue con el cursor
      // nuevo. Si el cursor no avanzó no hay nada que seguir pidiendo.
      mas = r.mas && estado.cursorBajada > antes;
    }
    return aplicadas;
  }

  Future<int> _subir(String token, EstadoSyncNube estado) async {
    final plan = await prepararSubidas(db, estado);
    avanzarSinSubir(estado, plan);
    var subidas = 0;
    try {
      for (final lote in plan.lotes) {
        await cliente.subirLote(token, loteId: lote.id, bytes: lote.bytes, sha256: lote.sha256);
        confirmarSubida(estado, plan, lote);
        subidas += lote.entradas.length;
        await almacenEstado.guardar(estado); // por lote: un corte a la mitad no repite lo que ya llegó
      }
    } finally {
      await almacenEstado.guardar(estado);
    }
    return subidas;
  }

  /// Arranca la sync automática (El dueño, 2026-10-01: "que baje los cambios solo cuando los detecte, hay que
  /// economizar lo más posible el uso de Cloudflare"):
  ///  - Subir: con cada cambio local de [cambiosLocales], agrupados [agruparCambios] para que una ráfaga (una venta
  ///    escribe varias tablas) sea una sola subida.
  ///  - Bajar: no se consulta por tiempo. Se abre una conexión de avisos y recién cuando otro dispositivo sube algo
  ///    llega el aviso y se baja. Mientras la conexión esté abierta no hay NINGÚN pedido por las dudas.
  ///  - Si no se puede escuchar (sin internet, o el servidor sin aviso en vivo) se reintenta cada vez más espaciado
  ///    ([reintentos], el último se repite) y en cada intento se consulta una vez, por si se perdió algo.
  void iniciar({
    required Stream<void> cambiosLocales,
    Duration agruparCambios = const Duration(seconds: 1),
    Duration agruparAvisos = const Duration(milliseconds: 300),
    List<Duration> reintentos = const [
      Duration(seconds: 5),
      Duration(seconds: 20),
      Duration(minutes: 1),
      Duration(minutes: 5),
    ],
    Duration sinCuenta = const Duration(minutes: 1),
  }) {
    detener();
    _activa = true;
    final generacion = ++_generacion;
    _cambios = cambiosLocales.listen((_) {
      _esperaSubida?.cancel();
      _esperaSubida = Timer(agruparCambios, () => unawaited(sincronizar()));
    });
    unawaited(_bucleDeAvisos(generacion, agruparAvisos, reintentos, sinCuenta));
  }

  Future<void> _bucleDeAvisos(int generacion, Duration agruparAvisos, List<Duration> reintentos, Duration sinCuenta) async {
    var intento = 0;
    bool vigente() => _activa && generacion == _generacion;
    while (vigente()) {
      final cuenta = await almacenCuenta.leer();
      if (!vigente()) return;
      if (cuenta == null) {
        // Sin cuenta no hay red que gastar: se mira el archivo de vez en cuando por si se vincula.
        await _dormir(sinCuenta);
        continue;
      }
      try {
        final avisos = await cliente.escuchar(cuenta.token);
        if (!vigente()) return;
        escuchando = true;
        intento = 0;
        final corte = _corteDeAvisos = Completer<void>();
        _avisos = avisos.listen(
          (_) {
            _esperaBajada?.cancel();
            _esperaBajada = Timer(agruparAvisos, () => unawaited(sincronizar()));
          },
          onDone: () => corte.isCompleted ? null : corte.complete(),
          onError: (_) => corte.isCompleted ? null : corte.complete(),
        );
        // Ponerse al día de lo que pasó mientras no se escuchaba (arranque, reconexión).
        unawaited(sincronizar());
        await corte.future;
      } catch (_) {
        // sin conexión o sin aviso en vivo: se sigue abajo
      }
      escuchando = false;
      await _avisos?.cancel();
      _avisos = null;
      if (!vigente()) return;
      // Mientras no se pueda escuchar: una consulta por intento, cada vez más espaciada.
      unawaited(sincronizar());
      await _dormir(reintentos[intento < reintentos.length ? intento : reintentos.length - 1]);
      intento++;
    }
  }

  Completer<void>? _sueno;

  Future<void> _dormir(Duration d) {
    final c = _sueno = Completer<void>();
    _esperaReintento = Timer(d, () => c.isCompleted ? null : c.complete());
    return c.future;
  }

  void detener() {
    _activa = false;
    _generacion++;
    _cambios?.cancel();
    _avisos?.cancel();
    _esperaSubida?.cancel();
    _esperaBajada?.cancel();
    _esperaReintento?.cancel();
    if (_corteDeAvisos?.isCompleted == false) _corteDeAvisos!.complete();
    if (_sueno?.isCompleted == false) _sueno!.complete(); // que el bucle termine, no que quede colgado
    _cambios = null;
    _avisos = null;
    escuchando = false;
  }

  /// Olvida el registro: la próxima vuelta baja todo desde el principio. Para después de restaurar una copia.
  Future<void> reiniciar() => almacenEstado.borrar();

  /// Salida de "quedaste atrás de lo que guarda la nube": se olvida el registro y se baja todo de nuevo. Se conserva
  /// lo que solo existe acá (filas nuevas, y el stock y la caja, que viajan como movimientos y se suman); una fila que
  /// existe también en la nube queda con la versión de la nube ("gana el último en llegar"). No hace falta restaurar
  /// una copia, que el celular ni puede.
  Future<ResultadoSyncNube> volverABajarTodo() async {
    await reiniciar();
    return sincronizar();
  }
}
