// Franja "modo local" — en su origen (El dueño, 2026-09-17: "no detecta la
// caja abierta... por dios, hacelo de una vez bien"), avisaba que
// `resolverServicioCompanion` había caído al fallback offline
// (`servicio_companion_offline.dart`) sin decir nada, indistinguible de
// "está cargando/lento".
//
// Con el emparejamiento con la PC vuelto opcional (El dueño, 2026-09-18: "no
// debería tener que escanear ya, es innecesario"), ese fallback offline
// pasó a ser el modo NORMAL de un celular que nunca emparejó nada — no es
// una falla que avisar, es cómo se usa la companion como POS aparte. El
// aviso ahora exige [pcEmparejada]: solo aparece cuando SÍ hay una PC
// configurada y no contestó justo ahora (eso sigue siendo información útil
// — algo cambió), nunca cuando la companion simplemente nunca tuvo PC.
//
// Rediseñada (El dueño, 2026-09-17: "remake desde 0") con el lenguaje nuevo de
// la companion — tarjeta redondeada con tinte del acento, no una franja
// pegada al borde de la pantalla.

import 'package:flutter/material.dart';

import '../ui/tema/tokens.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';

class AvisoModoLocal extends StatelessWidget {
  const AvisoModoLocal({super.key, required this.servicio, required this.pcEmparejada});

  final ServicioCompanion? servicio;

  /// true si `leerConexion()` devolvió una PC configurada — el aviso solo
  /// tiene sentido cuando esa PC no contestó, nunca cuando esta companion
  /// simplemente nunca emparejó ninguna (su modo normal hoy).
  final bool pcEmparejada;

  @override
  Widget build(BuildContext context) {
    if (!pcEmparejada || servicio is! ServicioCompanionOffline) {
      return const SizedBox.shrink();
    }
    final colores = context.colores;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.lg, Espaciado.lg, 0),
      child: Superficie(
        relleno: colores.textoTenue.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(
          horizontal: Espaciado.lg,
          vertical: Espaciado.md,
        ),
        child: Row(
          children: [
            Icon(IconosPlazoleta.cloudOff, size: 20, color: colores.textoSecundario),
            const SizedBox(width: Espaciado.sm),
            Expanded(
              child: Text(
                'La PC emparejada no contestó — vendiendo con la copia local, se sincroniza solo cuando vuelva a estar disponible.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
