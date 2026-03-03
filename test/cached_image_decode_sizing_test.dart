import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/services/image_cache_service.dart';
import 'package:portal/widgets/cached_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const imageUrl = 'https://api.vrchat.cloud/api/1/file_decode_size_test/1';
  final imageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7ZkS8AAAAASUVORK5CYII=',
  );

  late ImageCacheService cacheService;
  late Directory tempDirectory;

  setUp(() async {
    ImageCacheService.reset();
    cacheService = ImageCacheService();
    tempDirectory = await Directory.systemTemp.createTemp('portal_decode_');
    await cacheService.setCacheDirectoryForTesting(tempDirectory);
    await cacheService.cacheImage(imageUrl, imageBytes);
  });

  tearDown(() async {
    ImageCacheService.reset();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets('default decode sizing uses DPR capped at 2.0', (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        const CachedImage(imageUrl: imageUrl, width: 56, height: 56),
        dpr: 3.0,
      ),
    );
    await tester.pumpAndSettle();

    final imageWidget = tester.widget<Image>(find.byType(Image));
    expect(imageWidget.image, isA<ResizeImage>());

    final resizedProvider = imageWidget.image as ResizeImage;
    expect(resizedProvider.width, 112);
    expect(resizedProvider.height, 112);
  });

  testWidgets('opt-out disables decode sizing', (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        const CachedImage(
          imageUrl: imageUrl,
          width: 56,
          height: 56,
          enableDecodeSizing: false,
        ),
        dpr: 3.0,
      ),
    );
    await tester.pumpAndSettle();

    final imageWidget = tester.widget<Image>(find.byType(Image));
    expect(imageWidget.image, isNot(isA<ResizeImage>()));
  });

  testWidgets('invalid or missing dimensions skip decode sizing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildHarness(
        const CachedImage(imageUrl: imageUrl, height: 56),
        dpr: 3.0,
      ),
    );
    await tester.pumpAndSettle();
    var imageWidget = tester.widget<Image>(find.byType(Image));
    expect(imageWidget.image, isNot(isA<ResizeImage>()));

    await tester.pumpWidget(
      _buildHarness(const CachedImage(imageUrl: imageUrl, width: 56), dpr: 3.0),
    );
    await tester.pumpAndSettle();
    imageWidget = tester.widget<Image>(find.byType(Image));
    expect(imageWidget.image, isNot(isA<ResizeImage>()));

    await tester.pumpWidget(
      _buildHarness(
        const CachedImage(imageUrl: imageUrl, width: 0, height: 56),
        dpr: 3.0,
      ),
    );
    await tester.pumpAndSettle();
    imageWidget = tester.widget<Image>(find.byType(Image));
    expect(imageWidget.image, isNot(isA<ResizeImage>()));
  });

  testWidgets('loading and fallback wrappers keep tap + background behavior', (
    tester,
  ) async {
    var loadingTaps = 0;
    await tester.pumpWidget(
      _buildHarness(
        CachedImage(
          imageUrl: 'https://api.vrchat.cloud/api/1/file_loading_wrap_test/1',
          width: 40,
          height: 40,
          fallbackBackgroundColor: Colors.orange,
          onTap: () => loadingTaps += 1,
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final loadingContainerFinder = find.ancestor(
      of: find.byType(CircularProgressIndicator),
      matching: find.byType(Container),
    );
    final loadingContainer = tester.widget<Container>(
      loadingContainerFinder.first,
    );
    final loadingDecoration = loadingContainer.decoration! as BoxDecoration;
    expect(loadingDecoration.color, Colors.orange);

    await tester.tap(find.byType(CircularProgressIndicator));
    expect(loadingTaps, 1);

    var fallbackTaps = 0;
    await tester.pumpWidget(
      _buildHarness(
        CachedImage(
          imageUrl: '',
          width: 40,
          height: 40,
          fallbackIcon: Icons.public,
          fallbackBackgroundColor: Colors.orange,
          onTap: () => fallbackTaps += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fallbackContainerFinder = find.ancestor(
      of: find.byIcon(Icons.public),
      matching: find.byType(Container),
    );
    final fallbackContainer = tester.widget<Container>(
      fallbackContainerFinder.first,
    );
    final fallbackDecoration = fallbackContainer.decoration! as BoxDecoration;
    expect(fallbackDecoration.color, Colors.orange);

    await tester.tap(find.byIcon(Icons.public));
    expect(fallbackTaps, 1);
  });

  testWidgets('loaded image remains tappable with shared wrapper', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _buildHarness(
        CachedImage(
          imageUrl: imageUrl,
          width: 40,
          height: 40,
          onTap: () => taps += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(Image));
    expect(taps, 1);
  });

  testWidgets('empty url still renders fallback', (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        const CachedImage(
          imageUrl: '',
          width: 40,
          height: 40,
          fallbackIcon: Icons.public,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.public), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

Widget _buildHarness(Widget child, {double dpr = 1.0}) {
  return ProviderScope(
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(devicePixelRatio: dpr),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}
