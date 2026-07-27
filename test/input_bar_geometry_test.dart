import 'package:agent_ui_kit_providers/agent_ui_kit_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The collapsed composer must be a true capsule: radius exactly half the
/// height. Getting this wrong by even a couple of pixels leaves a flat edge
/// at each end, which reads as a rounded rectangle rather than a pill.
void main() {
  Future<void> pumpBar(WidgetTester tester, ChatInputBar bar) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: bar))),
    );
    await tester.pump();
  }

  Finder barContainer() => find
      .descendant(
        of: find.byType(ChatInputBar),
        matching: find.byType(Container),
      )
      .first;

  double radiusOf(WidgetTester tester) {
    final decoration =
        tester.widget<Container>(barContainer()).decoration! as BoxDecoration;
    return (decoration.borderRadius! as BorderRadius).topLeft.x;
  }

  testWidgets('collapsed bar is an exact capsule', (tester) async {
    await pumpBar(tester, ChatInputBar(onSend: (_) {}));

    final height = tester.getSize(barContainer()).height;
    expect(radiusOf(tester), height / 2);
  });

  testWidgets('attach and voice buttons do not add dead space', (tester) async {
    // The bar with icons is the configuration that regressed: IconButton
    // reserves a 48dp tap target by default, which made the row taller than
    // its contents and left empty space above the field and send button.
    await pumpBar(
      tester,
      ChatInputBar(onSend: (_) {}, onAttach: () {}, onVoice: () {}),
    );

    const padding = EdgeInsets.all(8);
    final height = tester.getSize(barContainer()).height;

    expect(
      height,
      ChatInputBar.collapsedHeight(padding),
      reason: 'icons must not make the bar taller than its controls',
    );
    expect(radiusOf(tester), height / 2);

    for (final icon in [Icons.add_rounded, Icons.mic_none_rounded]) {
      expect(
        tester.getSize(find.widgetWithIcon(IconButton, icon)).height,
        ChatInputBar.controlSize,
      );
    }
  });

  testWidgets('the text field matches the control height on one line',
      (tester) async {
    await pumpBar(tester, ChatInputBar(onSend: (_) {}));

    // A field taller than the buttons is what threw the row out of alignment.
    expect(
      tester.getSize(find.byType(TextField)).height,
      ChatInputBar.controlSize,
    );
  });

  testWidgets('stays a capsule when padding is overridden', (tester) async {
    const padding = EdgeInsets.all(14);
    await pumpBar(
      tester,
      ChatInputBar(onSend: (_) {}, padding: padding),
    );

    final height = tester.getSize(barContainer()).height;
    expect(height, ChatInputBar.collapsedHeight(padding));
    expect(radiusOf(tester), height / 2);
  });

  testWidgets('an explicit borderRadius wins', (tester) async {
    await pumpBar(
      tester,
      ChatInputBar(
        onSend: (_) {},
        borderRadius: BorderRadius.circular(4),
      ),
    );

    expect(radiusOf(tester), 4);
  });
}
