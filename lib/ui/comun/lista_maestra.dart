// Buscador arriba + filas + estado vacío, en el ancho fijo compartido de
// cualquier pantalla lista+detalle (`Medidas.anchoListaMaestra`). El filtrado
// sigue viviendo en el controlador de cada pantalla (`onBuscar` solo avisa
// el texto tipeado) — esto es puro layout, sin lógica de dominio.

import 'package:flutter/material.dart';

import '../tema/superficie.dart';
import '../tema/tokens.dart';
import 'campo_texto.dart';
import 'estado_vacio.dart';
import '../tema/movimiento.dart';

class ListaMaestra extends StatefulWidget {
  const ListaMaestra({
    super.key,
    this.placeholderBusqueda = 'Buscar',
    this.onBuscar,
    required this.items,
    required this.mensajeVacio,
  });

  final String placeholderBusqueda;

  /// Null si la pantalla no necesita buscador (ej. Proveedores, que ya
  /// filtra por período con `SelectorPeriodo` arriba de esto).
  final ValueChanged<String>? onBuscar;

  /// `FilaLista` ya construidas y ya filtradas por quien llama.
  final List<Widget> items;

  final String mensajeVacio;

  @override
  State<ListaMaestra> createState() => _ListaMaestraState();
}

class _ListaMaestraState extends State<ListaMaestra> {
  final _busquedaCtrl = TextEditingController();

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: Medidas.anchoListaMaestra,
      child: Superficie(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onBuscar != null) ...[
              CampoTexto(
                controller: _busquedaCtrl,
                etiqueta: widget.placeholderBusqueda,
                onChanged: widget.onBuscar,
              ),
              const SizedBox(height: Espaciado.md),
            ],
            Expanded(
              child: widget.items.isEmpty
                  ? EstadoVacio(mensaje: widget.mensajeVacio)
                  : ListView.builder(
                      itemCount: widget.items.length,
                      itemBuilder: (context, i) => entradaEnLista(i, widget.items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
