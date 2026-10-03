// Qué módulos tiene prendidos el comercio, siempre al día con la configuración.
//
// Mismo esquema que `marca_actual.dart`: un aviso global que las pantallas
// escuchan sin recibir la base, alimentado por `seguirModulos` desde la base (un
// cambio hecho en Configuración, o llegado por sincronización, se ve al toque).
// Mientras no se lee la base, todo está activo: así funciona la app hoy y vender
// nunca se frena por esto.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/database.dart';
import '../domain/modulos.dart';

final ValueNotifier<ModulosNegocio> modulosActuales = ValueNotifier(ModulosNegocio.todosActivos);

/// Atajo para el código que no es una pantalla.
bool moduloActivo(Modulo modulo) => modulosActuales.value.estaActivo(modulo);

/// Mantiene [modulosActuales] igual a lo guardado en la base mientras no se cancele.
StreamSubscription<ModulosNegocio> seguirModulos(AppDatabase db) {
  return db
      .select(db.configuracionNegocioTabla)
      .watchSingleOrNull()
      .map((f) => f == null ? ModulosNegocio.todosActivos : ModulosNegocio.desdeTexto(f.modulosDesactivados))
      .listen((m) => modulosActuales.value = m);
}

/// Muestra [hijo] solo si [modulo] está activo; si no, no ocupa lugar.
class SiModulo extends StatelessWidget {
  const SiModulo(this.modulo, {super.key, required this.hijo});

  final Modulo modulo;
  final Widget hijo;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ModulosNegocio>(
    valueListenable: modulosActuales,
    builder: (context, modulos, _) => modulos.estaActivo(modulo) ? hijo : const SizedBox.shrink(),
  );
}
