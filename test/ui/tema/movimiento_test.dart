import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/tema/movimiento.dart';

double _opacidad(WidgetTester tester) => tester.widget<Opacity>(find.byType(Opacity).first).opacity;

Widget _app(Widget hijo, {bool reducir = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducir),
        child: Scaffold(body: hijo),
      ),
    );

void main() {
  testWidgets('Entrada arranca invisible y termina entera, en menos de un quinto de segundo', (tester) async {
    await tester.pumpWidget(_app(const Entrada(child: Text('hola'))));
    expect(_opacidad(tester), lessThan(0.1));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_opacidad(tester), 1);
    expect(find.text('hola'), findsOneWidget);
  });

  testWidgets('con "reducir animaciones" aparece entera desde el primer cuadro', (tester) async {
    await tester.pumpWidget(_app(const Entrada(orden: 5, child: Text('hola')), reducir: true));
    expect(_opacidad(tester), 1);
  });

  testWidgets('en una lista, solo las primeras 12 filas se animan', (tester) async {
    expect(entradaEnLista(3, const Text('a')), isA<Entrada>());
    expect(entradaEnLista(12, const Text('a')), isA<Text>());
  });

  testWidgets('Pulso muestra el valor nuevo desde el primer cuadro y vuelve a su tamaño', (tester) async {
    Widget total(String t) => _app(Pulso(valor: t, child: Text(t)));
    await tester.pumpWidget(total(r'$1.000'));
    await tester.pumpWidget(total(r'$2.000'));
    expect(find.text(r'$2.000'), findsOneWidget);
    expect(find.text(r'$1.000'), findsNothing);
    await tester.pumpAndSettle();
    final escala = tester.widget<Transform>(find.ancestor(of: find.text(r'$2.000'), matching: find.byType(Transform)).first);
    expect(escala.transform.getMaxScaleOnAxis(), closeTo(1, 0.0001));
  });
}
