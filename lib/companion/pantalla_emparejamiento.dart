// Conectar el celular con la PC del local (El dueño, 2026-10-03: "no me gusta la pantalla de emparejamiento... que
// empareje por un código numérico de una sola vez"). Ya no hay QR ni datos para copiar:
//
// 1. Si el celular está con la cuenta de Nodo Sur y la PC de su sucursal avisó dónde está (`/api/device/pc-local`), se
//    conecta solo.
// 2. Si no, busca la PC en el wifi (`buscar_pc.dart`) y pide el código de 6 números que muestra la PC en
//    Configuración → Celular (`/emparejar`, de un solo uso).
// 3. Si no la encuentra (otra red, la PC apagada), se puede escribir la dirección que muestra la PC, más el código.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servidor/servidor_companion.dart' show puertoServidorCompanion;
import '../ui/tema/tokens.dart';
import 'buscar_pc.dart';
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'modo_uso.dart';
import 'pantalla_entrar_con_cuenta.dart';
import 'sync_nube_companion.dart';
import 'tema/error_en_linea.dart';
import 'tema/piezas_companion.dart';
import 'tema/superficie.dart';

/// La PC que avisó al sitio, si el celular tiene cuenta. Null si no hay cuenta, no hay PC o no hay internet.
typedef BuscarPcDeLaCuenta = Future<DatosConexion?> Function();

Future<DatosConexion?> pcDeLaCuentaPorDefecto() async {
  try {
    final sync = await syncNubeDelCelular();
    final cuenta = await sync.almacen.leer();
    if (cuenta == null) return null;
    final pc = await sync.cliente.pcLocal(cuenta.token);
    return pc == null ? null : DatosConexion(ip: pc.ip, puerto: pc.puerto, token: pc.llave);
  } catch (_) {
    return null;
  }
}

enum _Paso { buscando, codigo, noEncontrada, aMano }

class PantallaEmparejamiento extends StatefulWidget {
  const PantallaEmparejamiento({
    super.key,
    this.pcDeLaCuenta = pcDeLaCuentaPorDefecto,
    this.buscarEnElWifi = buscarPcEnElWifi,
    this.probar = ClienteCompanion.ping,
    this.canjear = ClienteCompanion.emparejarConCodigo,
    this.alConectar,
  });

  final BuscarPcDeLaCuenta pcDeLaCuenta;
  final Future<String?> Function() buscarEnElWifi;
  final Future<bool> Function(String ip, int puerto) probar;
  final Future<DatosConexion> Function(String ip, int puerto, String codigo) canjear;

  /// Solo para tests: qué hacer al conectar (por defecto, guardar y seguir a la cuenta).
  final Future<void> Function(DatosConexion)? alConectar;

  @override
  State<PantallaEmparejamiento> createState() => _PantallaEmparejamientoState();
}

class _PantallaEmparejamientoState extends State<PantallaEmparejamiento> {
  _Paso _paso = _Paso.buscando;
  String? _ipPc;
  String? _error;
  bool _enviando = false;

  final _codigoCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() {
      _paso = _Paso.buscando;
      _error = null;
    });
    final deLaCuenta = await widget.pcDeLaCuenta();
    if (!mounted) return;
    if (deLaCuenta != null && await widget.probar(deLaCuenta.ip, deLaCuenta.puerto)) {
      await _conectado(deLaCuenta);
      return;
    }
    final ip = await widget.buscarEnElWifi();
    if (!mounted) return;
    setState(() {
      _ipPc = ip;
      _paso = ip == null ? _Paso.noEncontrada : _Paso.codigo;
    });
  }

  Future<void> _enviarCodigo() async {
    final codigo = _codigoCtrl.text.replaceAll(RegExp(r'\D'), '');
    final ip = _paso == _Paso.aMano ? _ipCtrl.text.trim() : _ipPc;
    if (ip == null || ip.isEmpty) {
      setState(() => _error = 'Escribí la dirección que muestra la PC.');
      return;
    }
    if (codigo.length != 6) {
      setState(() => _error = 'El código tiene 6 números.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final datos = await widget.canjear(ip, puertoServidorCompanion, codigo);
      if (mounted) await _conectado(datos);
    } on ErrorCompanion catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _conectado(DatosConexion datos) async {
    if (widget.alConectar != null) {
      await widget.alConectar!(datos);
      return;
    }
    await guardarConexion(datos);
    await guardarModoUso(ModoUso.pcYCelular);
    if (!mounted) return;
    // Sin nada por debajo: ni el menú viejo ni la pantalla de elegir modo tienen sentido después de emparejar.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PantallaEntrarConCuenta()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (titulo, bajada) = switch (_paso) {
      _Paso.buscando => ('Conectar con la PC', 'Buscando la PC del local en este wifi…'),
      _Paso.codigo => ('Escribí el código', 'Está en la PC: Configuración → Equipos y cuenta → Celular.'),
      _Paso.noEncontrada => ('No encontramos la PC', 'Revisá que esté prendida, con la app abierta y en el mismo wifi.'),
      _Paso.aMano => ('Conectar a mano', 'Escribí la dirección y el código que muestra la PC en Configuración → Celular.'),
    };
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EncabezadoCompanion(
              titulo: titulo,
              bajada: bajada,
              padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.xl, Espaciado.xl, Espaciado.lg),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                child: KeyedSubtree(key: ValueKey(_paso), child: _cuerpo(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo(BuildContext context) {
    return switch (_paso) {
      _Paso.buscando => const Center(child: CircularProgressIndicator()),
      _Paso.codigo => _formulario(context, conDireccion: false),
      _Paso.aMano => _formulario(context, conDireccion: true),
      _Paso.noEncontrada => Padding(
        padding: const EdgeInsets.all(Espaciado.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(onPressed: _buscar, child: const Text('Buscar de nuevo')),
            const SizedBox(height: Espaciado.sm),
            OutlinedButton(onPressed: () => setState(() => _paso = _Paso.aMano), child: const Text('Escribir la dirección a mano')),
          ],
        ),
      ),
    };
  }

  Widget _formulario(BuildContext context, {required bool conDireccion}) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Espaciado.xl, 0, Espaciado.xl, Espaciado.xl),
      children: [
        if (conDireccion) ...[
          Superficie(
            child: TextField(
              key: const Key('emparejar_ip'),
              controller: _ipCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Dirección de la PC (ej. 192.168.0.23)'),
            ),
          ),
          const SizedBox(height: Espaciado.md),
        ] else if (_ipPc != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Espaciado.md),
            child: Text('PC encontrada en $_ipPc', style: textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario)),
          ),
        TextField(
          key: const Key('emparejar_codigo'),
          controller: _codigoCtrl,
          autofocus: !conDireccion,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: textTheme.displaySmall?.copyWith(letterSpacing: 10, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(hintText: '000000', counterText: ''),
          onSubmitted: (_) => _enviarCodigo(),
        ),
        if (_error != null) ...[const SizedBox(height: Espaciado.md), ErrorEnLinea(_error!)],
        const SizedBox(height: Espaciado.lg),
        FilledButton(
          key: const Key('emparejar_conectar'),
          onPressed: _enviando ? null : _enviarCodigo,
          child: _enviando
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Conectar'),
        ),
        const SizedBox(height: Espaciado.sm),
        TextButton(
          onPressed: _enviando ? null : (conDireccion ? _buscar : () => setState(() => _paso = _Paso.aMano)),
          child: Text(conDireccion ? 'Buscar la PC de nuevo' : 'Es otra PC: escribir la dirección'),
        ),
      ],
    );
  }
}
