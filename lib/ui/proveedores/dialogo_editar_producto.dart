// Alta o edición completa de un producto — absorbe lo que antes era la
// pantalla Productos entera (fase 13, corrección post-aprobación del kit:
// "editar cualquier cosa = Modal").
//
// Distribución del "Lenguaje de diseño" (El dueño, 2026-09-26, modal de
// `Proveedores.dc.html`): nombre; proveedor y código de barras lado a lado;
// un bloque de precio con costo y precio de venta, cuánto se gana por
// unidad y "Precio rápido" (+30/+40/+50% sobre el costo — un botón que se
// toca a propósito, nunca un autocompletado: Regla 14); stock actual y
// stock mínimo con −/+ y el aviso si quedó por debajo; y después lo que se
// toca poco (categoría, pesable, cigarrillo, activo, historial).

import 'package:flutter/material.dart';

import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../data/database.dart';
import '../../data/repositorio_productos.dart';
import '../../domain/dinero.dart';
import '../../domain/ganancia.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'proveedores_controlador.dart';
import '../tema/iconos.dart';

/// [productoId] null da de alta un producto nuevo. [proveedorIdPreseleccionado]
/// solo se usa en el alta, para que "+ Nuevo producto" desde el detalle de un
/// proveedor puntual ya venga con ese proveedor elegido.
Future<void> mostrarDialogoEditarProducto(
  BuildContext context, {
  required ProveedoresControlador controlador,
  int? productoId,
  int? proveedorIdPreseleccionado,
}) async {
  Producto? producto;
  List<HistorialDePrecio> historial = const [];
  if (productoId != null) {
    producto = await (controlador.db.select(
      controlador.db.productos,
    )..where((p) => p.id.equals(productoId))).getSingle();
    historial = await historialDelProducto(controlador.db, productoId);
  }
  if (!context.mounted) return;

  await mostrarModal<void>(
    context,
    builder: (context) => _DialogoEditarProducto(
      controlador: controlador,
      producto: producto,
      historial: historial,
      proveedorIdPreseleccionado: proveedorIdPreseleccionado,
    ),
  );
}

class _DialogoEditarProducto extends StatefulWidget {
  const _DialogoEditarProducto({
    required this.controlador,
    required this.producto,
    required this.historial,
    required this.proveedorIdPreseleccionado,
  });

  final ProveedoresControlador controlador;

  /// null cuando se está dando de alta un producto nuevo.
  final Producto? producto;
  final List<HistorialDePrecio> historial;
  final int? proveedorIdPreseleccionado;

  @override
  State<_DialogoEditarProducto> createState() => _DialogoEditarProductoState();
}

class _DialogoEditarProductoState extends State<_DialogoEditarProducto> {
  late final _nombreCtrl = TextEditingController(
    text: widget.producto?.nombre ?? '',
  );
  late final _codigoCtrl = TextEditingController(
    text: widget.producto?.codigoBarras ?? '',
  );
  late final _precioCtrl = TextEditingController(
    text: widget.producto?.precioCentavos == null
        ? ''
        : formatearARS(widget.producto!.precioCentavos!).replaceAll('\$', ''),
  );
  late final _costoCtrl = TextEditingController(
    text: widget.producto?.costoCentavos == null
        ? ''
        : formatearARS(widget.producto!.costoCentavos!).replaceAll('\$', ''),
  );
  late final _precioPorKiloCtrl = TextEditingController(
    text: widget.producto?.precioPorKiloCentavos == null
        ? ''
        : formatearARS(
            widget.producto!.precioPorKiloCentavos!,
          ).replaceAll('\$', ''),
  );
  late final _costoPorKiloCtrl = TextEditingController(
    text: widget.producto?.costoPorKiloCentavos == null
        ? ''
        : formatearARS(
            widget.producto!.costoPorKiloCentavos!,
          ).replaceAll('\$', ''),
  );
  late final _stockCtrl = TextEditingController(
    text: widget.producto == null ? '0' : widget.producto!.stock.toString(),
  );
  late final _stockGramosCtrl = TextEditingController(
    text: widget.producto?.stockGramos == null
        ? '0'
        : widget.producto!.stockGramos.toString(),
  );

  /// Mínimo para el aviso de stock bajo — unidades, o gramos si es pesable
  /// (mismo criterio que el stock).
  late final _minimoCtrl = TextEditingController(
    text: () {
      final p = widget.producto;
      if (p == null) return '0';
      return '${(p.esPesable ? p.stockMinimoGramos : p.stockMinimo) ?? 0}';
    }(),
  );

  late bool _esPesable = widget.producto?.esPesable ?? false;
  late int? _categoriaId = widget.producto?.categoriaId;
  late int? _proveedorId =
      widget.producto?.proveedorId ?? widget.proveedorIdPreseleccionado;
  late String _tipoCigarrillo = widget.producto?.tipoCigarrillo ?? 'ninguno';
  late bool _activo = widget.producto?.activo ?? true;

  /// true = el precio se cargó a mano y el porcentaje del proveedor no lo toca
  /// (El dueño, 2026-09-29). Solo importa si el proveedor tiene porcentaje.
  late bool _fijo = widget.producto?.precioFijo ?? false;
  String? _motivoAjusteStock;
  String? _error;

  bool get _esNuevo => widget.producto == null;

  int? _parsearONulo(String texto) {
    if (texto.trim().isEmpty) return null;
    try {
      return parsearARS(texto);
    } on FormatException {
      return null;
    }
  }

  TextEditingController get _ctrlPrecio =>
      _esPesable ? _precioPorKiloCtrl : _precioCtrl;
  TextEditingController get _ctrlCosto =>
      _esPesable ? _costoPorKiloCtrl : _costoCtrl;
  TextEditingController get _ctrlStock =>
      _esPesable ? _stockGramosCtrl : _stockCtrl;

  /// "Ganás $x por unidad · 38%" o "El precio no cubre el costo"; null si
  /// falta costo o precio (un costo $0 no cuenta, Regla 4).
  ({String texto, bool cubre})? get _gananciaEnVivo {
    final precio = _parsearONulo(_ctrlPrecio.text);
    final costo = _parsearONulo(_ctrlCosto.text);
    if (precio == null || costo == null || costo <= 0) return null;
    if (precio <= costo) {
      return (texto: 'El precio no cubre el costo', cubre: false);
    }
    final bp = gananciaBpDesdeCostoYPrecio(costo, precio);
    return (
      texto:
          'Ganás ${formatearARS(precio - costo)} ${_esPesable ? 'por kilo' : 'por unidad'} · ${(bp / 100).round()}%',
      cubre: true,
    );
  }

  /// Porcentaje del proveedor elegido en el diálogo (basis points), o null si
  /// no tiene. Los cigarrillos nunca lo usan (Regla 6).
  int? get _gananciaBp {
    if (_tipoCigarrillo != 'ninguno') return null;
    for (final r in widget.controlador.resumenes) {
      if (r.proveedor.id == _proveedorId) return r.proveedor.markupBp;
    }
    return null;
  }

  /// El producto puede tener precio automático (su proveedor tiene %).
  bool get _aplicaAutomatico => _gananciaBp != null;

  /// Y hoy lo tiene: el precio sale del costo, no se tipea.
  bool get _esAutomatico => _aplicaAutomatico && !_fijo;

  /// Precio con la ganancia del proveedor, redondeado a la próxima
  /// centena (`precioConGananciaACentena`, Regla 3: mismo cálculo que al aplicar
  /// el porcentaje desde Proveedores). Solo en modo automático y con costo.
  void _recalcularPrecioAutomatico() {
    if (!_esAutomatico) return;
    final costo = _parsearONulo(_ctrlCosto.text);
    if (costo == null || costo <= 0) return;
    _ctrlPrecio.text = formatearARS(
      precioConGananciaACentena(costo, _gananciaBp!),
    ).replaceAll('\$', '');
  }

  String get _porcentajeTexto {
    final bp = _gananciaBp!;
    return '${bp % 100 == 0 ? bp ~/ 100 : (bp / 100).toStringAsFixed(1)}%';
  }

  bool get _debajoDelMinimo {
    final minimo = int.tryParse(_minimoCtrl.text) ?? 0;
    return minimo > 0 && (int.tryParse(_ctrlStock.text) ?? 0) < minimo;
  }

  void _sumar(TextEditingController ctrl, int delta) {
    final nuevo = (int.tryParse(ctrl.text) ?? 0) + delta;
    setState(
      () => ctrl.text = '${nuevo < 0 && ctrl == _minimoCtrl ? 0 : nuevo}',
    );
  }

  Future<void> _cambiarEsPesable(bool nuevoValor) async {
    if (!_esNuevo) {
      final confirmado = await mostrarModal<bool>(
        context,
        builder: (context) => Modal(
          titulo: '¿Cambiar el tipo de producto?',
          contenido: Text(
            nuevoValor
                ? 'Va a pasar a cargarse por peso (gramos) en vez de por unidad.'
                : 'Va a pasar a cargarse por unidad en vez de por peso.',
          ),
          botones: [
            BotonSecundario(
              texto: 'Cancelar',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            BotonPrimario(
              texto: 'Cambiar',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (confirmado != true) return;
    }
    setState(() => _esPesable = nuevoValor);
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Falta el nombre');
      return;
    }

    final int? precio;
    final int? costo;
    final int? precioPorKilo;
    final int? costoPorKilo;
    try {
      if (_esPesable) {
        if (_precioPorKiloCtrl.text.trim().isEmpty) {
          setState(
            () => _error = 'Un pesable necesita precio por kilo (Regla 7)',
          );
          return;
        }
        precioPorKilo = parsearARS(_precioPorKiloCtrl.text);
        costoPorKilo = _costoPorKiloCtrl.text.trim().isEmpty
            ? null
            : parsearARS(_costoPorKiloCtrl.text);
        precio = null;
        costo = null;
      } else {
        if (_precioCtrl.text.trim().isEmpty) {
          setState(() => _error = 'Falta el precio');
          return;
        }
        precio = parsearARS(_precioCtrl.text);
        costo = _costoCtrl.text.trim().isEmpty
            ? null
            : parsearARS(_costoCtrl.text);
        precioPorKilo = null;
        costoPorKilo = null;
      }
    } on FormatException {
      setState(() => _error = 'Revisá los montos');
      return;
    }

    setState(() => _error = null);
    final db = widget.controlador.db;

    try {
      if (_esNuevo) {
        await crearProducto(
          db,
          nombre: nombre,
          codigoBarras: _codigoCtrl.text.trim().isEmpty
              ? null
              : _codigoCtrl.text.trim(),
          categoriaId: _categoriaId,
          proveedorId: _proveedorId,
          esPesable: _esPesable,
          tipoCigarrillo: _tipoCigarrillo,
          precioCentavos: precio,
          costoCentavos: costo,
          precioPorKiloCentavos: precioPorKilo,
          costoPorKiloCentavos: costoPorKilo,
          stock: int.tryParse(_stockCtrl.text) ?? 0,
          stockGramos: int.tryParse(_stockGramosCtrl.text),
          stockMinimo: int.tryParse(_minimoCtrl.text),
          usuarioId: widget.controlador.usuarioId,
          precioFijo: _fijo,
        );
      } else {
        await actualizarProducto(
          db,
          id: widget.producto!.id,
          nombre: nombre,
          codigoBarras: _codigoCtrl.text.trim().isEmpty
              ? null
              : _codigoCtrl.text.trim(),
          categoriaId: _categoriaId,
          proveedorId: _proveedorId,
          esPesable: _esPesable,
          tipoCigarrillo: _tipoCigarrillo,
          precioCentavos: precio,
          costoCentavos: costo,
          precioPorKiloCentavos: precioPorKilo,
          costoPorKiloCentavos: costoPorKilo,
          stock: int.tryParse(_stockCtrl.text) ?? 0,
          stockGramos: int.tryParse(_stockGramosCtrl.text),
          stockMinimo: int.tryParse(_minimoCtrl.text),
          activo: _activo,
          usuarioId: widget.controlador.usuarioId,
          motivoAjusteStock: _motivoAjusteStock,
          precioFijo: _aplicaAutomatico ? _fijo : null,
        );
      }
    } on ArgumentError catch (e) {
      // Código de barras duplicado (`repositorio_productos.dart`) — antes
      // de este chequeo esto tiraba una excepción cruda de sqlite sin
      // capturar, acá directo.
      setState(() => _error = e.message.toString());
      return;
    }

    await widget.controlador.recargarSeleccionActual();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _crearCategoria() async {
    final nombreCtrl = TextEditingController();
    final nombre = await mostrarModal<String>(
      context,
      builder: (context) => Modal(
        titulo: 'Nueva categoría',
        contenido: CampoTexto(controller: nombreCtrl, autofocus: true),
        botones: [
          BotonSecundario(
            texto: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(),
          ),
          BotonPrimario(
            texto: 'Crear',
            onPressed: () => Navigator.of(context).pop(nombreCtrl.text.trim()),
          ),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty) return;
    if (!mounted) return;
    final id = await widget.controlador.agregarCategoria(nombre);
    if (!mounted) return;
    setState(() => _categoriaId = id);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _codigoCtrl.dispose();
    _precioCtrl.dispose();
    _costoCtrl.dispose();
    _precioPorKiloCtrl.dispose();
    _costoPorKiloCtrl.dispose();
    _stockCtrl.dispose();
    _stockGramosCtrl.dispose();
    _minimoCtrl.dispose();
    super.dispose();
  }

  String _lineaHistorial(HistorialDePrecio h) {
    final fecha =
        '${h.fecha.day.toString().padLeft(2, '0')}/'
        '${h.fecha.month.toString().padLeft(2, '0')}/${h.fecha.year}';
    final partes = <String>[];
    if (h.precioCentavos != null) {
      partes.add('precio ${formatearARS(h.precioCentavos!)}');
    }
    if (h.costoCentavos != null) {
      partes.add('costo ${formatearARS(h.costoCentavos!)}');
    }
    if (h.precioPorKiloCentavos != null) {
      partes.add('precio/kg ${formatearARS(h.precioPorKiloCentavos!)}');
    }
    if (h.costoPorKiloCentavos != null) {
      partes.add('costo/kg ${formatearARS(h.costoPorKiloCentavos!)}');
    }
    return '$fecha — ${partes.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final proveedoresActivos = widget.controlador.resumenes
        .map((r) => r.proveedor)
        .toList();
    final textTheme = Theme.of(context).textTheme;
    final ganancia = _gananciaEnVivo;
    final unidad = _esPesable ? 'g' : 'u.';

    return Modal(
      titulo: _esNuevo ? 'Nuevo producto' : 'Editar producto',
      contenido: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 760),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CampoTexto(
                key: const Key('campo_nombre'),
                controller: _nombreCtrl,
                etiqueta: 'Nombre',
                autofocus: true,
              ),
              const SizedBox(height: Espaciado.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _selector<int?>(
                      context,
                      etiqueta: 'Proveedor',
                      valor: _proveedorId,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Sin proveedor'),
                        ),
                        for (final prov in proveedoresActivos)
                          DropdownMenuItem(
                            value: prov.id,
                            child: Text(prov.nombre),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _proveedorId = v;
                        _recalcularPrecioAutomatico();
                      }),
                    ),
                  ),
                  const SizedBox(width: Espaciado.md),
                  Expanded(
                    child: CampoTexto(
                      key: const Key('campo_codigo_barras'),
                      controller: _codigoCtrl,
                      etiqueta: 'Código de barras (opcional)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Espaciado.lg),
              // Bloque de precio: lo que más se toca, junto y a la vista.
              BloqueSuave(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: CampoPlata(
                            key: Key(
                              _esPesable ? 'campo_costo_kilo' : 'campo_costo',
                            ),
                            controller: _ctrlCosto,
                            etiqueta: _esPesable
                                ? 'Costo por kilo (opcional)'
                                : 'Costo (opcional)',
                            onChanged: (_) =>
                                setState(_recalcularPrecioAutomatico),
                            sobreElFondo: true,
                          ),
                        ),
                        const SizedBox(width: Espaciado.md),
                        Expanded(
                          child: CampoPlata(
                            key: Key(
                              _esPesable ? 'campo_precio_kilo' : 'campo_precio',
                            ),
                            controller: _ctrlPrecio,
                            etiqueta: _esPesable
                                ? 'Precio por kilo'
                                : 'Precio de venta',
                            // Tipear el precio a mano lo deja fijo: el
                            // porcentaje del proveedor deja de tocarlo.
                            onChanged: (_) => setState(() {
                              if (_aplicaAutomatico) _fijo = true;
                            }),
                            sobreElFondo: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Espaciado.md),
                    Wrap(
                      spacing: Espaciado.sm,
                      runSpacing: Espaciado.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Insignia(
                          texto: ganancia?.texto ?? 'Ganancia: sin costo cargado',
                          tono: ganancia == null
                              ? Tono.neutro
                              : (ganancia.cubre ? Tono.ganancia : Tono.error),
                        ),
                        if (_aplicaAutomatico)
                          FilterChip(
                            key: const Key('chip_precio_fijo'),
                            label: Text(
                              _fijo
                                  ? 'Precio fijo (a mano)'
                                  : 'Automático: $_porcentajeTexto de ganancia, a la centena',
                            ),
                            selected: _fijo,
                            onSelected: (fijo) => setState(() {
                              _fijo = fijo;
                              _recalcularPrecioAutomatico();
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espaciado.lg),
              Row(
                children: [
                  Expanded(
                    child: _Pasos(
                      llave: Key(
                        _esPesable ? 'campo_stock_gramos' : 'campo_stock',
                      ),
                      etiqueta: _esPesable ? 'Stock (gramos)' : 'Stock actual',
                      controller: _ctrlStock,
                      paso: _esPesable ? 100 : 1,
                      unidad: unidad,
                      alSumar: _sumar,
                    ),
                  ),
                  const SizedBox(width: Espaciado.md),
                  Expanded(
                    child: _Pasos(
                      llave: const Key('campo_stock_minimo'),
                      etiqueta: _esPesable
                          ? 'Stock mínimo (gramos)'
                          : 'Stock mínimo',
                      controller: _minimoCtrl,
                      paso: _esPesable ? 100 : 1,
                      unidad: unidad,
                      alSumar: _sumar,
                    ),
                  ),
                ],
              ),
              if (_debajoDelMinimo) ...[
                const SizedBox(height: Espaciado.sm),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Insignia(
                    texto:
                        'Está por debajo del mínimo: aparece en "Stock bajo" de Inicio y Proveedores',
                    tono: Tono.alerta,
                  ),
                ),
              ],
              if (!_esNuevo) ...[
                const SizedBox(height: Espaciado.md),
                _selector<String?>(
                  context,
                  etiqueta: 'Motivo del ajuste de stock (opcional)',
                  valor: _motivoAjusteStock,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Sin especificar'),
                    ),
                    for (final motivo in motivosAjusteDeStock)
                      DropdownMenuItem(value: motivo, child: Text(motivo)),
                  ],
                  onChanged: (v) => setState(() => _motivoAjusteStock = v),
                ),
              ],
              const SizedBox(height: Espaciado.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _selector<int?>(
                      context,
                      etiqueta: 'Categoría',
                      valor: _categoriaId,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Sin categoría'),
                        ),
                        for (final cat in widget.controlador.categorias)
                          DropdownMenuItem(
                            value: cat.id,
                            child: Text(cat.nombre),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoriaId = v),
                    ),
                  ),
                  IconButton(
                    onPressed: _crearCategoria,
                    icon: const Icon(IconosPlazoleta.add),
                    tooltip: 'Nueva categoría',
                  ),
                  // Sin el módulo de caja aparte no se ofrece, salvo que este producto ya sea un cigarrillo
                  // (para poder corregirlo).
                  if (moduloActivo(Modulo.cajaAparte) || _tipoCigarrillo != 'ninguno') ...[
                  const SizedBox(width: Espaciado.sm),
                  Expanded(
                    child: _selector<String>(
                      context,
                      etiqueta: 'Cigarrillo',
                      valor: _tipoCigarrillo,
                      items: const [
                        DropdownMenuItem(
                          value: 'ninguno',
                          child: Text('No es cigarrillo'),
                        ),
                        DropdownMenuItem(
                          value: 'atado',
                          child: Text('Cigarrillo — atado'),
                        ),
                        DropdownMenuItem(
                          value: 'suelto',
                          child: Text('Cigarrillo — suelto'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _tipoCigarrillo = v ?? 'ninguno'),
                    ),
                  ),
                  ],
                ],
              ),
              const SizedBox(height: Espaciado.sm),
              // Sin el módulo de pesables no se ofrece, salvo que este producto ya sea pesable.
              if (moduloActivo(Modulo.pesables) || _esPesable)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Es pesable (se carga por gramos)'),
                  value: _esPesable,
                  onChanged: (v) => _cambiarEsPesable(v),
                ),
              if (!_esNuevo)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  value: _activo,
                  onChanged: (v) => setState(() => _activo = v ?? true),
                ),
              if (_error != null) ...[
                const SizedBox(height: Espaciado.sm),
                Text(_error!, style: TextStyle(color: context.colores.error)),
              ],
              if (!_esNuevo && widget.historial.isNotEmpty) ...[
                const SizedBox(height: Espaciado.lg),
                Text('Historial de precios', style: textTheme.labelMedium),
                const SizedBox(height: Espaciado.xs),
                for (final h in widget.historial)
                  Text(_lineaHistorial(h), style: textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
      botones: [
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BotonPrimario(
          texto: _esNuevo ? 'Crear' : 'Guardar cambios',
          onPressed: _guardar,
        ),
      ],
    );
  }

  /// Mismo criterio de fondo/radio que `CampoTexto` (`colores.fondo`, un
  /// paso contra el `Bloque` que lo contiene) — el kit todavía no tiene una
  /// pieza de selección propia (paso 1, "Qué es configurable y qué no").
  Widget _selector<T>(
    BuildContext context, {
    required String etiqueta,
    required T valor,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: Espaciado.xs),
        Container(
          height: Medidas.alturaControl,
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.md),
          decoration: BoxDecoration(
            color: context.colores.fondo,
            borderRadius: BorderRadius.circular(radioControlEscritorio),
          ),
          child: DropdownButton<T>(
            value: valor,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Campo numérico con − y + a los costados (stock actual y mínimo).
class _Pasos extends StatelessWidget {
  const _Pasos({
    required this.llave,
    required this.etiqueta,
    required this.controller,
    required this.paso,
    required this.unidad,
    required this.alSumar,
  });

  final Key llave;
  final String etiqueta;
  final TextEditingController controller;
  final int paso;
  final String unidad;
  final void Function(TextEditingController, int) alSumar;

  @override
  Widget build(BuildContext context) {
    return CampoTexto(
      key: llave,
      controller: controller,
      etiqueta: etiqueta,
      keyboardType: TextInputType.number,
      prefixIcon: IconButton(
        tooltip: 'Restar $paso $unidad',
        icon: const Icon(IconosPlazoleta.remove),
        onPressed: () => alSumar(controller, -paso),
      ),
      suffixIcon: IconButton(
        tooltip: 'Sumar $paso $unidad',
        icon: const Icon(IconosPlazoleta.add),
        onPressed: () => alSumar(controller, paso),
      ),
    );
  }
}
