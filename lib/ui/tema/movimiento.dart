// Movimiento de la PC (El dueño, 2026-10-03: "las animaciones son una miseria" — eligió animar todo, también la pantalla
// de venta, "cortas"). Dos piezas que se usan en todos lados para que la app se mueva con un solo idioma:
//
//  * [Entrada]: lo que aparece sube unos px y se funde, una vez, al montarse. En listas, escalonado por posición.
//  * [Pulso]: cuando cambia un valor (el total, una cantidad), un latido mínimo para que el ojo lo note. El texto ya está
//    actualizado desde el primer cuadro: el movimiento acompaña, nunca demora lo que se lee ni lo que se tipea.
//
// Las dos duran menos de un quinto de segundo (`Animaciones.corta`/`media`) y respetan "reducir animaciones" del sistema
// (`MediaQuery.disableAnimations`): ahí aparecen y cambian sin moverse.

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Curva de entrada de Material 3: arranca rápido y se posa suave (la misma de la bienvenida del celular).
const curvaEntrada = Cubic(0.05, 0.7, 0.1, 1);

class Entrada extends StatefulWidget {
  const Entrada({super.key, this.orden = 0, this.desplazamiento = 10, this.escala = 1, required this.child});

  /// Posición en una lista: cada una arranca 30 ms después que la anterior, hasta 8 (después ya no se nota y solo demora).
  final int orden;

  /// Cuántos px sube al aparecer.
  final double desplazamiento;

  /// Escala inicial (1 = sin zoom). Los diálogos entran desde 0,96.
  final double escala;

  final Widget child;

  @override
  State<Entrada> createState() => _EntradaState();
}

class _EntradaState extends State<Entrada> with SingleTickerProviderStateMixin {
  static const _paso = 30;
  late final int _demora = widget.orden.clamp(0, 8) * _paso;
  late final AnimationController _reloj = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _demora) + Animaciones.media,
  );
  late final Animation<double> _k = CurvedAnimation(
    parent: _reloj,
    curve: Interval(_demora / (_demora + Animaciones.media.inMilliseconds), 1, curve: curvaEntrada),
  );
  bool _arrancado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrancado) return;
    _arrancado = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reloj.value = 1;
    } else {
      _reloj.forward();
    }
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _k,
      child: widget.child,
      builder: (context, child) {
        final k = _k.value;
        Widget hijo = Transform.translate(offset: Offset(0, (1 - k) * widget.desplazamiento), child: child);
        if (widget.escala != 1) hijo = Transform.scale(scale: widget.escala + (1 - widget.escala) * k, child: hijo);
        return Opacity(opacity: k.clamp(0.0, 1.0), child: hijo);
      },
    );
  }
}

/// Un latido cuando cambia [valor]: crece a [escala] y vuelve, en `Animaciones.corta`. El primer cuadro ya muestra el
/// contenido nuevo; esto solo lo acompaña.
class Pulso extends StatefulWidget {
  const Pulso({super.key, required this.valor, this.escala = 1.04, this.alineacion = Alignment.center, required this.child});

  final Object? valor;
  final double escala;
  final Alignment alineacion;
  final Widget child;

  @override
  State<Pulso> createState() => _PulsoState();
}

class _PulsoState extends State<Pulso> with SingleTickerProviderStateMixin {
  late final AnimationController _reloj = AnimationController(vsync: this, duration: Animaciones.corta);

  @override
  void didUpdateWidget(Pulso anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.valor != widget.valor && !MediaQuery.disableAnimationsOf(context)) {
      _reloj.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _reloj,
      child: widget.child,
      builder: (context, child) {
        // Sube y baja en el mismo tiempo: 0 → 1 → 0 sobre el reloj.
        final t = _reloj.isAnimating ? 1 - (2 * _reloj.value - 1).abs() : 0.0;
        return Transform.scale(
          scale: 1 + (widget.escala - 1) * Curves.easeOut.transform(t),
          alignment: widget.alineacion,
          child: child,
        );
      },
    );
  }
}

/// Para las filas de una lista: escalonadas solo las primeras 12 (lo que se ve al abrir la pantalla). Las que aparecen
/// al scrollear no se animan: entrar con demora mientras se baja se sentiría lento, no fluido.
Widget entradaEnLista(int indice, Widget fila) => indice < 12 ? Entrada(orden: indice, child: fila) : fila;
