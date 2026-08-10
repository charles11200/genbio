import 'package:flutter_test/flutter_test.dart';

import 'package:genbio/main.dart';

void main() {
  testWidgets('Home screen shows the app title', (WidgetTester tester) async {
    await tester.pumpWidget(const GenBioReviewApp());

    expect(find.text('BioQuest'), findsOneWidget);
  });
}
