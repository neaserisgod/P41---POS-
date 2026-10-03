// Inicio — pantalla de arranque de la app. Nació como "Dashboard" (El dueño,
// 2026-09-14) y el 2026-09-26 absorbió Equilibrio (menú de 6 secciones).
//
// Distribución del "Lenguaje de diseño" (El dueño, 2026-09-26, mock
// `Dashboard.dc.html`, "medio inspiración" pero "la distribución es la
// idea"), en dos vistas que se eligen arriba a la derecha:
//
// - HOY: fila de cuatro indicadores (vendido, ganancia, tickets y "falta
//   separar" en la tarjeta oscura que lleva a Separaciones); ventas por
//   hora al lado de cómo te pagaron; y abajo más vendidos, stock que avisa
//   y fiados/encargues pendientes — este último en el lugar donde el mock
//   tenía "Reparaciones", que no es de este negocio (El dueño lo sacó).
// - ESTE MES: el contenido de lo que era Equilibrio (`ContenidoEquilibrio`).
//
// Es la raíz de la app (`main.dart`): nadie le pasa `usuarioId`/
// `sesionCajaId`, se resuelven solos, y se recarga al volver de cualquier
// pantalla (`RouteAware`, ver `route_observer.dart`).

import 'package:flutter/material.dart';

import '../navegacion/refresco_por_celular.dart';
import '../../data/database.dart';
import '../../data/repositorio_tablero.dart';
import '../../data/repositorio_ventas.dart' show sesionAbierta;
import '../../domain/dinero.dart';
import '../comun/armazon_gestion.dart';
import '../comun/boton_destacado.dart';
import '../comun/fechas.dart';
import '../comun/grafico_por_hora.dart';
import '../comun/tarjetas.dart';
import '../equilibrio/pantalla_equilibrio.dart';
import '../navegacion/navegacion_gestion.dart';
import '../navegacion/route_observer.dart';
import '../tema/acentos.dart';
import '../tema/iconos.dart';
import '../tema/superficie.dart';
import '../tema/tema_inverso.dart';
import '../tema/tokens.dart';
import '../../domain/modulos.dart';
import '../../servicios/marca_actual.dart';
import '../../servicios/modulos_activos.dart';
import '../comun/dialogo_datos_comercio.dart';
import '../tema/movimiento.dart';

enum _Vista { hoy, mes }

class PantallaDashboard extends StatefulWidget {
  const PantallaDashboard({super.key, required this.db, this.ahora});

  final AppDatabase db;

  /// Solo para tests y capturas: fija "hoy".
  final DateTime? ahora;

  @override
  State<PantallaDashboard> createState() => _PantallaDashboardState();
}

class _PantallaDashboardState extends State<PantallaDashboard> with RouteAware , RefrescoPorCelular{
  @override
  void alCambiarDesdeElCelular() => _cargarTodo();

  bool _cargando = true;
  SesionCaja? _sesion;
  TableroDelDia? _tablero;
  _Vista _vista = _Vista.hoy;

  /// Cambia en cada recarga para rearmar el contenido del mes (su propio
  /// controlador lee la base una vez al montarse).
  int _version = 0;

  /// El aviso de "Datos de tu comercio" se ofrece una vez por apertura de la app.
  bool _preguntoComercio = false;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pedirDatosDelComercio());
  }

  Future<void> _pedirDatosDelComercio() async {
    if (_preguntoComercio) return;
    _preguntoComercio = true;
    final marca = await marcaDeBase(widget.db);
    if (marca.configurada || !mounted) return;
    await mostrarDialogoDatosComercio(context, widget.db);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute<dynamic>);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// Cualquier pantalla de la que se vuelve (Venta, Separaciones...) pudo
  /// cambiar ventas, stock o fijos — se recarga sola.
  @override
  void didPopNext() => _cargarTodo();

  Future<void> _cargarTodo() async {
    final sesion = await sesionAbierta(widget.db);
    final tablero = await tableroDelDia(widget.db, ahora: widget.ahora);
    if (!mounted) return;
    setState(() {
      _sesion = sesion;
      _tablero = tablero;
      _version++;
      _cargando = false;
    });
  }

  void _ir(String clave) {
    final sesion = _sesion;
    navegarASeccionDeGestion(
      context,
      clave,
      db: widget.db,
      usuarioId: sesion?.usuarioAbrioId ?? 0,
      sesionCajaId: sesion?.id,
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ModulosNegocio>(
    valueListenable: modulosActuales,
    builder: (context, modulos, _) => _construir(context, modulos),
  );

  Widget _construir(BuildContext context, ModulosNegocio modulos) {
    if (_cargando) return const SizedBox.shrink();
    final sesion = _sesion;
    final hoy = widget.ahora ?? DateTime.now();
    // Sin el módulo de equilibrio no hay vista mensual: queda solo "Hoy".
    final verMes = modulos.estaActivo(Modulo.equilibrio) && _vista == _Vista.mes;

    return PantallaGestion(
      db: widget.db,
      claveActiva: 'dashboard',
      usuarioId: sesion?.usuarioAbrioId ?? 0,
      sesionCajaId: sesion?.id,
      titulo: 'Inicio',
      subtitulo: !verMes
          ? 'Hoy · ${fechaLarga(hoy)}${sesion == null ? ' · caja cerrada' : ''}'
          : 'Este mes · ${mesLargo(hoy)}',
      accion: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (modulos.estaActivo(Modulo.equilibrio)) ...[
            GrupoPildoras<_Vista>(
              opciones: const [(_Vista.hoy, 'Hoy'), (_Vista.mes, 'Este mes')],
              elegida: _vista,
              oscura: true,
              onElegir: (v) => setState(() => _vista = v),
            ),
            const SizedBox(width: Espaciado.md),
          ],
          BotonDestacado(texto: 'Ir a Venta', icono: IconosPlazoleta.pointOfSaleOutlined, onTap: () => _ir('venta')),
        ],
      ),
      child: !verMes
          ? _VistaHoy(tablero: _tablero!, alTocarSeparar: () => _ir('separaciones'), hoy: hoy, conPendientes: modulos.estaActivo(Modulo.fiado))
          : SingleChildScrollView(
              child: ContenidoEquilibrio(
                key: ValueKey(_version),
                db: widget.db,
                usuarioId: sesion?.usuarioAbrioId ?? 0,
                sesionCajaId: sesion?.id,
              ),
            ),
    );
  }
}

String _plata(int centavos) => formatearARS(centavos);

String _porcentaje(double fraccion) => '${(fraccion * 100).round()}%';

class _VistaHoy extends StatelessWidget {
  const _VistaHoy({required this.tablero, required this.alTocarSeparar, required this.hoy, required this.conPendientes});

  /// Falso sin el módulo de fiado: no hay tarjeta de fiados y encargues.
  final bool conPendientes;

  final TableroDelDia tablero;
  final VoidCallback alTocarSeparar;
  final DateTime hoy;

  @override
  Widget build(BuildContext context) {
    // Por debajo de este alto (1366×768 con la navbar) las tres tarjetas de
    // abajo no entran con aire: la pantalla scrollea entera en vez de
    // aplastarlas.
    return LayoutBuilder(
      builder: (context, restricciones) {
        final entra = restricciones.maxHeight >= 700;
        final abajo = _FilaDeAbajo(tablero: tablero, conPendientes: conPendientes);
        final contenido = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: entra ? 400 : 390,
              child: _FilaIndicadores(tablero: tablero, alTocarSeparar: alTocarSeparar, hoy: hoy),
            ),
            const SizedBox(height: Espaciado.lg),
            if (entra) Expanded(child: abajo) else SizedBox(height: 320, child: abajo),
          ],
        );
        return entra ? contenido : SingleChildScrollView(child: contenido);
      },
    );
  }
}

class _FilaIndicadores extends StatelessWidget {
  const _FilaIndicadores({required this.tablero, required this.alTocarSeparar, required this.hoy});

  final TableroDelDia tablero;
  final VoidCallback alTocarSeparar;
  final DateTime hoy;

  @override
  Widget build(BuildContext context) {
    final t = tablero;
    final antes = t.vendidoMismoDiaSemanaPasadaCentavos;
    final dia = diasSemana[hoy.weekday - 1];
    String? notaVendido;
    var tonoVendido = Tono.neutro;
    if (antes > 0 && t.vendidoCentavos > 0) {
      final variacion = (t.vendidoCentavos - antes) / antes;
      notaVendido = '${variacion >= 0 ? '+' : '−'}${_porcentaje(variacion.abs())} vs. el $dia pasado';
      tonoVendido = variacion >= 0 ? Tono.ganancia : Tono.error;
    } else if (antes > 0) {
      notaVendido = 'El $dia pasado: ${_plata(antes)}';
    }

    final margen = t.margen;
    final notaGanancia = t.vendidoSinCostoCentavos > 0
        ? '${margen == null ? '' : 'Ganancia ${_porcentaje(margen)} · '}sin costo ${_plata(t.vendidoSinCostoCentavos)}'
        : (margen == null ? null : 'Ganancia ${_porcentaje(margen)}');

    final notaSeparar = t.proveedoresConAlgoQueSeparar == 0
        ? 'Nada que separar todavía'
        : t.proveedoresPendientes == 0
        ? 'Todo separado'
        : '${t.proveedoresPendientes} de ${t.proveedoresConAlgoQueSeparar} proveedores pendientes';

    // Rediseño "antigravity": lo vendido hoy pasa a ser la pieza grande de la
    // pantalla (bloque negro, cifra enorme y liviana) y el resto de los
    // indicadores se apilan a su lado como tarjetas chicas.
    final chicas = [
      TarjetaIndicador(
        etiqueta: 'Ganancia hoy',
        valor: _plata(t.gananciaCentavos),
        tonoValor: Tono.ganancia,
        nota: notaGanancia,
      ),
      TarjetaIndicador(
        etiqueta: 'Tickets',
        valor: '${t.tickets}',
        nota: t.tickets == 0 ? null : 'Promedio ${_plata(t.vendidoCentavos ~/ t.tickets)}',
      ),
      TarjetaIndicador(
        etiqueta: 'Falta separar',
        valor: _plata(t.faltaSepararCentavos),
        nota: notaSeparar,
        destacada: true,
        onTap: alTocarSeparar,
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          // Las tarjetas entran escalonadas (2026-10-03): lo vendido primero, después las chicas y la fila de abajo.
          child: Entrada(
            child: _HeroVendido(
              valor: _plata(t.vendidoCentavos),
              nota: notaVendido,
              tono: tonoVendido,
              porHora: t.porHora,
            ),
          ),
        ),
        const SizedBox(width: Espaciado.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < chicas.length; i++) ...[
                if (i > 0) const SizedBox(height: Espaciado.md),
                Expanded(child: Entrada(orden: i + 1, child: chicas[i])),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Lo vendido hoy, en grande: bloque negro con la cifra liviana y apretada
/// de la web de Nodo Sur, y la variación contra el mismo día de la semana
/// pasada en una pastilla.
class _HeroVendido extends StatelessWidget {
  const _HeroVendido({required this.valor, required this.nota, required this.tono, required this.porHora});

  final Map<int, int> porHora;
  final String valor;
  final String? nota;
  final Tono tono;

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final sobre = acentos.textoSobreColor;
    final (fondoNota, textoNota) = switch (tono) {
      Tono.ganancia => (acentos.gananciaSuave, acentos.ganancia),
      Tono.error => (acentos.alertaSuave, acentos.alerta),
      _ => (sobre.withValues(alpha: 0.14), sobre),
    };
    return Superficie(
      degrade: acentos.gradienteAcento,
      padding: const EdgeInsets.all(Espaciado.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Vendido hoy', style: textTheme.titleSmall?.copyWith(color: sobre.withValues(alpha: 0.72))),
          const SizedBox(height: Espaciado.lg),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              maxLines: 1,
              style: textTheme.displayLarge!.copyWith(fontSize: 72, color: sobre, letterSpacing: -3.6, height: 1),
            ),
          ),
          const SizedBox(height: Espaciado.lg),
          if (nota != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Espaciado.md + 2, vertical: Espaciado.xs + 2),
              decoration: BoxDecoration(color: fondoNota, borderRadius: BorderRadius.circular(999)),
              child: Text(nota!, style: textTheme.labelLarge?.copyWith(color: textoNota)),
            ),
          const Spacer(),
          // Las ventas por hora, dentro del mismo bloque (igual que el mock).
          TemaInverso(
            activo: true,
            invertirAcento: true,
            colorSobre: sobre,
            child: Builder(
              builder: (context) => DefaultTextStyle.merge(
                style: TextStyle(color: context.colores.textoPrimario),
                child: GraficoPorHora(porHora: porHora, altura: 120),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComoTePagaron extends StatelessWidget {
  const _ComoTePagaron({required this.tablero});

  final TableroDelDia tablero;

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentosPlazoleta;
    final t = tablero;
    final total = t.efectivoCentavos + t.mpCentavos;
    String pct(int v) => total == 0 ? '' : ' · ${_porcentaje(v / total)}';
    return TarjetaSeccion(
      titulo: 'Cómo te pagaron',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BarraDividida(
            tramos: [
              (color: acentos.dinero, valor: t.efectivoCentavos),
              (color: acentos.qr, valor: t.mpCentavos),
            ],
          ),
          const SizedBox(height: Espaciado.lg),
          FilaMedio(color: acentos.dinero, etiqueta: 'Efectivo${pct(t.efectivoCentavos)}', monto: _plata(t.efectivoCentavos)),
          const SizedBox(height: Espaciado.sm + 2),
          FilaMedio(color: acentos.qr, etiqueta: 'Mercado Pago${pct(t.mpCentavos)}', monto: _plata(t.mpCentavos)),
        ],
      ),
    );
  }
}

class _FilaDeAbajo extends StatelessWidget {
  const _FilaDeAbajo({required this.tablero, required this.conPendientes});

  final TableroDelDia tablero;
  final bool conPendientes;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: Entrada(orden: 4, child: _ComoTePagaron(tablero: tablero))),
        const SizedBox(width: Espaciado.lg),
        Expanded(child: Entrada(orden: 5, child: _MasVendidos(tablero: tablero))),
        const SizedBox(width: Espaciado.lg),
        Expanded(child: Entrada(orden: 6, child: _StockBajo(tablero: tablero))),
        if (conPendientes) ...[
          const SizedBox(width: Espaciado.lg),
          Expanded(child: Entrada(orden: 7, child: _Pendientes(tablero: tablero))),
        ],
      ],
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(texto, style: Theme.of(context).textTheme.bodySmall);
}

/// Tarjeta de abajo con lista propia que scrollea si no entra.
class _TarjetaConLista extends StatelessWidget {
  const _TarjetaConLista({required this.titulo, this.insignia, required this.cantidad, required this.item, required this.vacio, this.separacion = Espaciado.sm});

  final String titulo;
  final Widget? insignia;
  final int cantidad;
  final Widget Function(int) item;
  final String vacio;
  final double separacion;

  @override
  Widget build(BuildContext context) {
    return TarjetaSeccion(
      titulo: titulo,
      insignia: insignia,
      child: Expanded(
        child: cantidad == 0
            ? Align(alignment: Alignment.topLeft, child: _Vacio(vacio))
            : ListView.separated(
                itemCount: cantidad,
                separatorBuilder: (_, _) => SizedBox(height: separacion),
                itemBuilder: (_, i) => item(i),
              ),
      ),
    );
  }
}

class _MasVendidos extends StatelessWidget {
  const _MasVendidos({required this.tablero});

  final TableroDelDia tablero;

  @override
  Widget build(BuildContext context) {
    final lista = tablero.masVendidos;
    final primero = lista.isEmpty ? 1 : lista.first.vendidoCentavos;
    return _TarjetaConLista(
      titulo: 'Más vendidos hoy',
      cantidad: lista.length,
      vacio: 'Todavía no se vendió nada hoy.',
      separacion: Espaciado.md + 2,
      item: (i) {
        final p = lista[i];
        return FilaRanking(
          nombre: p.nombre,
          valor: p.esPesable ? '${p.gramos} g' : '${p.cantidad} u.',
          proporcion: p.vendidoCentavos / primero,
        );
      },
    );
  }
}

class _StockBajo extends StatelessWidget {
  const _StockBajo({required this.tablero});

  final TableroDelDia tablero;

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentosPlazoleta;
    final colores = context.colores;
    final lista = tablero.stockBajo;
    return _TarjetaConLista(
      titulo: 'Stock bajo',
      insignia: lista.isEmpty
          ? null
          : Insignia(texto: '${lista.length} producto${lista.length == 1 ? '' : 's'}', tono: Tono.alerta),
      cantidad: lista.length,
      vacio: 'Nada por debajo del mínimo.',
      item: (i) {
        final p = lista[i];
        final agotado = p.stock <= 0;
        return FilaSuave(
          titulo: p.nombre,
          subtitulo: p.proveedor ?? 'Sin proveedor',
          icono: IconosPlazoleta.inventory2Outlined,
          derecha: Text(
            agotado ? 'Sin stock' : 'Quedan ${p.stock}${p.esPesable ? ' g' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: agotado ? colores.error : acentos.alerta,
              fontWeight: Pesos.fuerte,
            ),
          ),
        );
      },
    );
  }
}

class _Pendientes extends StatelessWidget {
  const _Pendientes({required this.tablero});

  final TableroDelDia tablero;

  @override
  Widget build(BuildContext context) {
    final lista = tablero.pendientes;
    final fiado = lista.where((p) => p.esFiado).fold(0, (a, p) => a + (p.montoCentavos ?? 0));
    return _TarjetaConLista(
      titulo: 'Encargues y deudas',
      insignia: fiado > 0 ? Insignia(texto: 'Te deben ${_plata(fiado)}', tono: Tono.alerta) : null,
      cantidad: lista.length,
      vacio: 'No hay encargues ni deudas pendientes.',
      item: (i) {
        final p = lista[i];
        return FilaSuave(
          titulo: p.quien,
          subtitulo: [p.esFiado ? 'Deuda' : 'Encargue', ?p.detalle, 'desde el ${p.desde.day}/${p.desde.month}'].join(' · '),
          derecha: p.montoCentavos == null
              ? null
              : Text(_plata(p.montoCentavos!), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte).tabular),
        );
      },
    );
  }
}
