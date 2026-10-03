// Entrar al celular con la cuenta de cada persona (El dueño, 2026-10-02: "que los empleados directamente logueen con su
// perfil en lugar de seleccionar"). Reemplaza a la lista "¿Quién sos?": nadie elige un perfil en el celular, el perfil es el de
// la cuenta (`perfil_por_cuenta.dart`). Cambiar de perfil queda solo en el POS de escritorio.
//
// Pide internet una sola vez, al entrar; después el celular sigue andando sin conexión con el perfil ya guardado.

import 'package:flutter/material.dart';

import '../servicios/cuenta_nube.dart';
import 'base_local.dart';
import 'bienvenida/pantalla_listo.dart';
import 'bienvenida/vista_entrar_con_google.dart';
import 'configurar/asistente_negocio.dart';
import 'configurar/flujo_negocio.dart';
import 'configurar/negocio_nuevo.dart';
import 'modo_uso.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'perfil_por_cuenta.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'sync_nube_companion.dart';

/// El servicio contra el que se busca o crea el perfil: la PC si está emparejada y contesta, si no la base local (que se
/// sincroniza). Mismo criterio que el resto de la companion.
Future<ServicioCompanion> servicioParaPerfil() async {
  final conexion = await leerConexion();
  return conexion == null ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion())) : resolverServicioCompanion(conexion);
}

/// Para celulares que ya tenían la cuenta vinculada y un perfil elegido de la lista (de antes de este cambio): en segundo plano
/// y sin bloquear nada, vuelve a tomar el perfil de la cuenta. Sin internet, o ante cualquier falla, no toca nada: el celular
/// sigue con el perfil que tenía y la próxima vez que abra con conexión se corrige solo.
Future<void> reconciliarPerfilDeCuenta({SyncNubeCompanion? sync, Future<ServicioCompanion> Function()? servicio}) async {
  try {
    final s = sync ?? await syncNubeDelCelular();
    final cuenta = await s.cuenta();
    if (cuenta == null) return;
    final perfil = await s.cliente.yo(cuenta.token).timeout(const Duration(seconds: 6));
    await resolverPerfilDeCuenta(perfil: perfil, servicio: await (servicio ?? servicioParaPerfil)());
  } catch (_) {
    // silencioso a propósito
  }
}

class PantallaEntrarConCuenta extends StatefulWidget {
  const PantallaEntrarConCuenta({super.key, this.sync, this.servicio, this.alEntrar, this.esNegocioNuevo});

  /// Solo para tests: la sync del celular y el servicio. En la app real salen de `syncNubeDelCelular()` y de la conexión.
  final SyncNubeCompanion? sync;
  final Future<ServicioCompanion> Function()? servicio;

  /// Qué hacer con el perfil ya resuelto; por defecto muestra "Listo", que después abre el menú (o "Configurá tu
  /// negocio", si es el dueño de un negocio nuevo).
  final void Function(BuildContext context)? alEntrar;

  /// Solo para tests: si quien entró es el dueño de un negocio nuevo. En la app real, [_esNegocioNuevo].
  final Future<bool> Function(PerfilDeCuenta perfil)? esNegocioNuevo;

  @override
  State<PantallaEntrarConCuenta> createState() => _PantallaEntrarConCuentaState();
}

class _PantallaEntrarConCuentaState extends State<PantallaEntrarConCuenta> {
  SyncNubeCompanion? _sync;
  bool _trabajando = true;
  String? _error;

  /// El token ya no vale (sacaron a la persona del negocio o revocaron el celular): hay que entrar de nuevo.
  bool _hayQueEntrarDeNuevo = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      _sync = widget.sync ?? await syncNubeDelCelular();
      final cuenta = await _sync!.cuenta();
      if (cuenta != null) {
        await _resolver(cuenta);
        return;
      }
    } catch (e) {
      _error = mensajeDeError(e);
    }
    if (mounted) setState(() => _trabajando = false);
  }

  Future<void> _entrar() async {
    setState(() {
      _trabajando = true;
      _error = null;
      _hayQueEntrarDeNuevo = false;
    });
    try {
      final cuenta = await _sync!.vincular(nombre: nombreDelCelular());
      await _resolver(cuenta);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ErrorNube ? e.mensaje : mensajeDeError(e);
          _trabajando = false;
        });
      }
    }
  }

  Future<void> _resolver(CuentaVinculada cuenta) async {
    if (mounted) setState(() => _trabajando = true);
    try {
      final perfil = await _sync!.cliente.yo(cuenta.token);
      final servicio = await (widget.servicio ?? servicioParaPerfil)();
      await resolverPerfilDeCuenta(perfil: perfil, servicio: servicio);
      if (!mounted) return;
      if (widget.alEntrar != null) {
        widget.alEntrar!(context);
        return;
      }
      final nuevo = await (widget.esNegocioNuevo ?? _esNegocioNuevo)(perfil);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => nuevo
              ? PantallaListo(textoBoton: 'Configurar mi negocio', alSeguir: (context) => abrirAsistenteNegocio(context))
              : const PantallaListo(),
        ),
      );
    } on PerfilDesactivado catch (e) {
      if (mounted) {
        setState(() {
        _error = e.toString();
        _trabajando = false;
      });
      }
    } on ErrorNube catch (e) {
      if (mounted) {
        setState(() {
        _error = e.mensaje;
        _hayQueEntrarDeNuevo = e.pideVincularDeNuevo;
        _trabajando = false;
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        _error = mensajeDeError(e);
        _trabajando = false;
      });
      }
    }
  }

  /// El dueño de un negocio que todavía no tiene nada, usando solo el celular: le toca "Configurá tu negocio". Con la
  /// PC, la configuración vive allá; un empleado o encargado entra a un negocio que ya armó el dueño.
  Future<bool> _esNegocioNuevo(PerfilDeCuenta perfil) async {
    if (perfil.rol != rolDuenio) return false;
    if (await leerModoUso() != ModoUso.soloCelular) return false;
    final db = baseLocalCompanion();
    if (!await esNegocioNuevoTrasSincronizar(sync: _sync!.servicio, db: db)) return false;
    await prepararNegocioNuevo(db);
    await guardarPasosPendientes(PasoNegocio.values.toSet());
    return true;
  }

  Future<void> _reintentar() async {
    final cuenta = await _sync!.cuenta();
    if (cuenta == null) {
      setState(() => _error = null);
      return;
    }
    await _resolver(cuenta);
  }

  @override
  Widget build(BuildContext context) => VistaEntrarConGoogle(
        alEntrar: _entrar,
        trabajando: _trabajando,
        error: _error,
        // Con una cuenta ya vinculada y un error que no es de la sesión, se reintenta sin volver al navegador.
        alReintentar: _error != null && !_hayQueEntrarDeNuevo && _sync != null ? _reintentar : null,
      );
}
