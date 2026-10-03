// Tarjeta de acceso para una grilla de dos columnas — reemplaza la fila
// "ícono + texto + flecha" (patrón de lista de configuración, genérico en
// cualquier app) en las pantallas que son sobre todo un menú de accesos
// (Gestión, Más) — El dueño, 2026-09-18, tras ver que la primera pasada de
// remake "se ve exactamente igual": una grilla de tarjetas de color, como ya
// tiene "Inicio", en vez de una lista de filas iguales, cambia la
// composición real de la pantalla, no solo el color.

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import 'chip_icono.dart';
import 'presionable.dart';
import 'superficie.dart';

class TarjetaAccion extends StatelessWidget {
  const TarjetaAccion({
    super.key,
    required this.icono,
    required this.color,
    required this.titulo,
    required this.onTap,
    this.subtitulo,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String? subtitulo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Superficie(
      padding: EdgeInsets.zero,
      child: Presionable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Espaciado.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ChipIcono(
                icono: icono,
                color: onTap == null ? context.colores.textoTenue : color,
                tamanio: 44,
                resplandor: onTap != null,
              ),
              const SizedBox(height: Espaciado.md),
              Text(titulo, style: Theme.of(context).textTheme.titleSmall),
              if (subtitulo != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitulo!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Arma una grilla de dos columnas a partir de [tarjetas] — mismo patrón que
/// "Uso diario" en Inicio, reutilizado acá para no repetir el cálculo de
/// filas/huecos en cada pantalla que lo necesite.
class GrillaAcciones extends StatelessWidget {
  const GrillaAcciones({super.key, required this.tarjetas});

  final List<Widget> tarjetas;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < tarjetas.length; i += 2) ...[
          if (i > 0) const SizedBox(height: Espaciado.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tarjetas[i]),
                const SizedBox(width: Espaciado.md),
                if (i + 1 < tarjetas.length) Expanded(child: tarjetas[i + 1]) else const Spacer(),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
