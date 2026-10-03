// "Cuenta y sincronización" en la companion: con quién está sincronizando este celular ahora (la PC por wifi,
// internet, o nadie) y la cuenta de Nodo Sur que hace falta para sincronizar por internet.
//
// Es lo único que hay que tocar para trabajar sin la PC: vincular la cuenta una vez. Después el celular pasa solo
// a internet si la PC no contesta (`conmutador_sync.dart`) y vuelve a la PC cuando contesta.

import 'package:flutter/material.dart';

import '../servicios/cuenta_nube.dart';
import '../servicios/sync_nube.dart';
import '../ui/comun/estado_mercado_pago.dart';
import '../ui/tema/iconos.dart';
import '../ui/tema/tokens.dart';
import 'conmutador_sync.dart';
import 'sync_nube_companion.dart';
import 'tema/fila_dato_companion.dart';
import 'tema/piezas_companion.dart';
import 'tema/superficie.dart';
import 'tema/hoja_vidrio.dart';

class PantallaCuentaCompanion extends StatefulWidget {
  const PantallaCuentaCompanion({super.key, required this.sync, this.alContinuar});

  /// La sync del celular (en la app real, `syncNubeDelCelular()`).
  final SyncNubeCompanion sync;

  /// Al elegir "solo celular" por primera vez la pantalla se ofrece como un paso más (vincular ahora o después):
  /// con esto aparece el botón para seguir.
  final void Function(BuildContext context)? alContinuar;

  @override
  State<PantallaCuentaCompanion> createState() => _PantallaCuentaCompanionState();
}

class _PantallaCuentaCompanionState extends State<PantallaCuentaCompanion> {
  CuentaVinculada? _cuenta;
  bool _cargando = true;
  bool _ocupado = false;
  String? _mensaje;

  SyncNubeCompanion get _sync => widget.sync;

  @override
  void initState() {
    super.initState();
    _leerCuenta();
  }

  Future<void> _leerCuenta() async {
    final cuenta = await _sync.cuenta();
    if (!mounted) return;
    setState(() {
      _cuenta = cuenta;
      _cargando = false;
    });
  }

  Future<void> _vincular() async {
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    try {
      await _sync.vincular(nombre: nombreDelCelular());
      await _leerCuenta();
    } on ErrorNube catch (e) {
      if (mounted) setState(() => _mensaje = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _mensaje = 'No se pudo vincular: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _desvincular() async {
    final confirmar = await confirmarAccionDestructiva(
      context,
      titulo: '¿Desvincular este celular?',
      contenido: 'Sin la cuenta no podrá sincronizar por internet. Lo que ya tiene guardado en el celular no se borra.',
      textoConfirmar: 'Desvincular',
    );
    if (!confirmar) return;
    await _sync.desvincular();
    await _leerCuenta();
  }

  Future<void> _sincronizarAhora() async {
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    final r = await _sync.servicio.sincronizar();
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _mensaje = textoDeResultado(r);
    });
  }

  Future<void> _volverABajarTodo() async {
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    final r = await _sync.servicio.volverABajarTodo();
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _mensaje = textoDeResultado(r);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.alContinuar == null ? AppBar(scrolledUnderElevation: 0) : null,
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(Espaciado.xl, 0, Espaciado.xl, Espaciado.xl),
                children: [
                  const EncabezadoCompanion(
                    rotulo: 'Gestión',
                    titulo: 'Cuenta y sincronización',
                    padding: EdgeInsets.fromLTRB(0, Espaciado.lg, 0, Espaciado.lg),
                  ),
                  ValueListenableBuilder<ModoSync>(
                    valueListenable: _sync.conmutador.modo,
                    builder: (context, modo, _) => _TarjetaModo(modo: modo, hayCuenta: _cuenta != null),
                  ),
                  if (_cuenta != null)
                    ValueListenableBuilder<int>(
                      valueListenable: _sync.servicio.alCambiarEstado,
                      builder: (context, _, _) {
                        final vista = vistaDeSync(_sync.servicio.ultimo);
                        // "Todavía no hubo una vuelta" no es una novedad para mostrar: se ve recién con un resultado.
                        if (_sync.servicio.ultimo == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: Espaciado.md),
                          child: _EstadoSync(vista: vista, ocupado: _ocupado, alVolverABajar: _volverABajarTodo),
                        );
                      },
                    ),
                  const SizedBox(height: Espaciado.lg),
                  Superficie(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        FilaDatoCompanion(
                          etiqueta: 'Cuenta de Nodo Sur',
                          valor: _cuenta?.email ?? 'Sin vincular',
                          destacado: _cuenta == null,
                        ),
                        if (_cuenta != null)
                          FilaDatoCompanion(etiqueta: 'Este celular', valor: _cuenta!.nombreDispositivo),
                      ],
                    ),
                  ),
                  const SizedBox(height: Espaciado.lg),
                  if (_mensaje != null) ...[
                    Text(_mensaje!, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: Espaciado.md),
                  ],
                  if (_cuenta == null)
                    FilledButton(
                      onPressed: _ocupado ? null : _vincular,
                      child: _ocupado
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Vincular con Nodo Sur'),
                    )
                  else ...[
                    FilledButton(
                      onPressed: _ocupado ? null : _sincronizarAhora,
                      child: const Text('Sincronizar ahora'),
                    ),
                    const SizedBox(height: Espaciado.sm),
                    TextButton(
                      onPressed: _ocupado ? null : _desvincular,
                      child: Text('Desvincular', style: TextStyle(color: context.colores.error)),
                    ),
                  ],
                  if (widget.alContinuar != null) ...[
                    const SizedBox(height: Espaciado.lg),
                    OutlinedButton(
                      onPressed: _ocupado ? null : () => widget.alContinuar!(context),
                      child: Text(_cuenta == null ? 'Vincular más tarde' : 'Continuar'),
                    ),
                  ],
                  if (_cuenta case final cuenta?) ...[
                    const SizedBox(height: Espaciado.lg),
                    Superficie(child: EstadoMercadoPago(leer: () => _sync.cliente.estadoMp(cuenta.token))),
                  ],
                  const SizedBox(height: Espaciado.xl),
                  Text(
                    'Con la PC prendida, el celular sincroniza con ella. Si la PC se apaga o queda fuera del wifi, '
                    'pasa solo a internet; cuando la PC vuelve, vuelve a ella.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
    );
  }
}

/// El texto que se muestra tras una vuelta manual.
String textoDeResultado(ResultadoSyncNube r) => switch (r) {
  SyncNubeOk(:final bajadas, :final subidas) =>
    bajadas == 0 && subidas == 0 ? 'Todo al día.' : 'Listo: recibió $bajadas y mandó $subidas cambios.',
  SyncNubeSinCuenta() => 'Primero vinculá el celular a tu cuenta.',
  SyncNubeExpirada() => vistaDeSync(r).detalle,
  SyncNubeFallida(:final mensaje, :final sinRed) => sinRed ? 'Sin conexión a internet.' : mensaje,
};

/// Lo que está pasando con la sync, en una frase, y la salida cuando algo la traba (Regla: nunca un callejón sin salida).
class _EstadoSync extends StatelessWidget {
  const _EstadoSync({required this.vista, required this.ocupado, required this.alVolverABajar});

  final VistaSync vista;
  final bool ocupado;
  final VoidCallback alVolverABajar;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final color = switch (vista.tono) {
      TonoSync.bien => colores.acento,
      TonoSync.espera => colores.textoSecundario,
      TonoSync.atencion => colores.error,
    };
    return Superficie(
      key: const Key('estado_sync'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: Espaciado.sm),
              Expanded(child: Text(vista.titulo, style: textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Espaciado.xs),
          Text(vista.detalle, style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario)),
          if (vista.puedeVolverABajar) ...[
            const SizedBox(height: Espaciado.md),
            OutlinedButton(
              key: const Key('volver_a_bajar_todo'),
              onPressed: ocupado ? null : alVolverABajar,
              child: const Text('Volver a bajar todo'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TarjetaModo extends StatelessWidget {
  const _TarjetaModo({required this.modo, required this.hayCuenta});

  final ModoSync modo;
  final bool hayCuenta;

  @override
  Widget build(BuildContext context) {
    final (titulo, detalle, icono) = switch (modo) {
      ModoSync.pc => ('Con la PC', 'Sincronizando por wifi.', IconosPlazoleta.cloudSync),
      ModoSync.nube => ('Por internet', 'La PC no contesta: sincronizando con la nube.', IconosPlazoleta.cloudUploadOutlined),
      ModoSync.local => (
        'Solo en este celular',
        hayCuenta ? 'Esperando para sincronizar.' : 'Vinculá tu cuenta para sincronizar por internet.',
        IconosPlazoleta.cloudOff,
      ),
    };
    final textTheme = Theme.of(context).textTheme;
    // El bloque negro del rediseño: lo más importante de la pantalla (con quién se sincroniza ahora).
    return BloqueHero(
      animar: false,
      minAlto: 112,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ahora', style: textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.72))),
                Text(titulo, style: textTheme.headlineMedium?.copyWith(color: Colors.white)),
                const SizedBox(height: 2),
                Text(detalle, style: textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.72))),
              ],
            ),
          ),
          const SizedBox(width: Espaciado.md),
          BotonFlecha(icono: icono, tamanio: 48),
        ],
      ),
    );
  }
}

/// La pantalla con la sync real del celular: la arma la primera vez que se abre.
class PantallaCuentaDelCelular extends StatelessWidget {
  const PantallaCuentaDelCelular({super.key, this.alContinuar});

  final void Function(BuildContext context)? alContinuar;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SyncNubeCompanion>(
      future: syncNubeDelCelular(),
      builder: (context, snap) => snap.hasData
          ? PantallaCuentaCompanion(sync: snap.data!, alContinuar: alContinuar)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
