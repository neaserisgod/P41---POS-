// Lectura de los cobros reales por el sitio: lo que manda y cómo interpreta la respuesta.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/conciliacion_mp_nube.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';

void main() {
  test('pide el rango en segundos con el token del equipo y arma los cobros', () async {
    late Uri pedido;
    late String? auth;
    final cliente = ClienteNube(http: MockClient((r) async {
      pedido = r.url;
      auth = r.headers['Authorization'];
      return http.Response(jsonEncode({
        'cobros': [
          {'id': '1', 'estado': 'approved', 'fecha': 1790874005, 'montoCentavos': 360000, 'devueltoCentavos': 0, 'comisionCentavos': 7200, 'netoCentavos': 352800, 'medio': 'account_money'},
        ],
        'truncado': false,
      }), 200);
    }));
    final almacen = AlmacenCuentaEnMemoria();
    await almacen.guardar(const CuentaVinculada(token: 'tk', email: 'a@b.com', idDispositivo: 'd', nombreDispositivo: 'Caja', vence: 99));
    final r = await leerCobrosMpDeCuenta(almacen, cliente)(DateTime.fromMillisecondsSinceEpoch(1790874000000), DateTime.fromMillisecondsSinceEpoch(1790917200000));
    expect(pedido.path, '/api/mp/cobros');
    expect(pedido.queryParameters, {'desde': '1790874000', 'hasta': '1790917200'});
    expect(auth, 'Bearer tk');
    expect(r.cobros.single.netoCentavos, 352800);
    expect(r.cobros.single.fecha, DateTime.fromMillisecondsSinceEpoch(1790874005000));
    expect(r.cobros.single.cobrado, isTrue);
  });

  test('sin cuenta vinculada o con Mercado Pago sin conectar, lo dice claro', () async {
    final cliente = ClienteNube(http: MockClient((r) async => http.Response(jsonEncode({'error': 'mp_no_conectado'}), 409)));
    final sinCuenta = leerCobrosMpDeCuenta(AlmacenCuentaEnMemoria(), cliente);
    await expectLater(sinCuenta(DateTime(2026), DateTime(2026, 2)), throwsA(isA<ErrorNube>().having((e) => e.mensaje, 'mensaje', contains('Vinculá'))));
    final almacen = AlmacenCuentaEnMemoria();
    await almacen.guardar(const CuentaVinculada(token: 'tk', email: 'a@b.com', idDispositivo: 'd', nombreDispositivo: 'Caja', vence: 99));
    await expectLater(leerCobrosMpDeCuenta(almacen, cliente)(DateTime(2026), DateTime(2026, 2)), throwsA(isA<ErrorNube>().having((e) => e.mensaje, 'mensaje', contains('no está conectado'))));
  });
}
