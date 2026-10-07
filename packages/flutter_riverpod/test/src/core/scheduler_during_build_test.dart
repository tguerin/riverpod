import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../utils.dart';
import 'provider_subscription_test.dart';

/// The non-fatal error reported in debug mode when a provider refresh had to
/// be deferred because it was requested while Flutter was building.
TypeMatcher<FlutterError> isDeferredRefreshReport() {
  return isA<FlutterError>().having(
    (e) => e.message,
    'message',
    contains(
      'A provider refresh was requested while the widget tree was building.',
    ),
  );
}

/// The non-fatal error reported in debug mode when the rebuild of a widget had
/// to be deferred because a provider notified it while Flutter was building.
TypeMatcher<FlutterError> isDeferredRebuildReport() {
  return isA<FlutterError>().having(
    (e) => e.message,
    'message',
    contains(
      'A provider notified a widget while the widget tree was building.',
    ),
  );
}

void main() {
  group('provider refresh requested while Flutter is building', () {
    testWidgets(
      'invalidating a provider from a widget build neither throws nor strands '
      'the scope; watchers render the new value on the next frame',
      (tester) async {
        // Port of the flutter-poker test `provider_refresh_scheduled_during_build_test.dart`.
        var buildCount = 0;
        final derived = Provider<int>((ref) => ++buildCount);
        final refreshWhileBuilding =
            NotifierProvider<DeferredNotifier<bool>, bool>(
              () => DeferredNotifier((ref, self) => false),
            );

        await tester.pumpWidget(
          ProviderScope(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      return Text('derived:${ref.watch(derived)}');
                    },
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      if (ref.watch(refreshWhileBuilding)) {
                        ref.invalidate(derived);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        final container = tester.container();
        expect(find.text('derived:1'), findsOneWidget);

        container.read(refreshWhileBuilding.notifier).state = true;
        await tester.pump();
        // Flutter's "setState() or markNeedsBuild() called during build" is
        // not thrown anymore. In debug mode, the deferral is reported so that
        // the code requesting a refresh during a build can be found.
        expect(tester.takeException(), isDeferredRefreshReport());
        expect(find.text('derived:1'), findsOneWidget);

        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('derived:2'), findsOneWidget);

        // The scope is still functional afterwards: a refresh requested
        // outside of a build is applied on the next frame, without report.
        container.invalidate(derived);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('derived:3'), findsOneWidget);
      },
    );

    testWidgets(
      'invalidating a provider from initState of a widget inserted by a '
      'rebuild neither throws nor strands the scope',
      (tester) async {
        var buildCount = 0;
        final derived = Provider<int>((ref) => ++buildCount);
        final showChild = NotifierProvider<DeferredNotifier<bool>, bool>(
          () => DeferredNotifier((ref, self) => false),
        );

        await tester.pumpWidget(
          ProviderScope(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      return Text('derived:${ref.watch(derived)}');
                    },
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      if (!ref.watch(showChild)) return const SizedBox.shrink();
                      return _InvalidateOnInit(derived);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        final container = tester.container();
        expect(find.text('derived:1'), findsOneWidget);

        // The Consumer is rebuilt from the dirty list, so the ProviderScope
        // is not below the widget being built when initState runs.
        container.read(showChild.notifier).state = true;
        await tester.pump();
        expect(tester.takeException(), isDeferredRefreshReport());

        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('derived:2'), findsOneWidget);
      },
    );

    testWidgetsWithStubbedFlutterErrors(
      'a stale provider flushed by ref.watch during a widget build defers '
      'the rebuild of its other watchers, and the refreshes requested by its '
      'listeners, to the next frame',
      (tester, errors) async {
        var derivedBuildCount = 0;
        var targetBuildCount = 0;
        final trigger = NotifierProvider<DeferredNotifier<bool>, bool>(
          () => DeferredNotifier((ref, self) => false),
        );
        final derived = Provider<int>((ref) => ++derivedBuildCount);
        final target = NotifierProvider<DeferredNotifier<int>, int>(
          () => DeferredNotifier((ref, self) => ++targetBuildCount),
        );

        await tester.pumpWidget(
          ProviderScope(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  // Built first: already built when `derived` is flushed below.
                  Consumer(
                    builder: (context, ref, _) {
                      return Text('derived:${ref.watch(derived)}');
                    },
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      return Text('target:${ref.watch(target)}');
                    },
                  ),
                  // Not rebuilt during the frame: its listener survives the
                  // flush below and invalidates `target` from it.
                  Consumer(
                    builder: (context, ref, _) {
                      ref.listen(derived, (_, _) => ref.invalidate(target));
                      return const SizedBox.shrink();
                    },
                  ),
                  // Makes `derived` stale in the middle of the frame.
                  Consumer(
                    builder: (context, ref, _) {
                      if (ref.watch(trigger)) ref.invalidate(derived);
                      return const SizedBox.shrink();
                    },
                  ),
                  // Deeper, so built after the previous Consumer: reads the
                  // stale `derived`, which flushes it during the build.
                  SizedBox(
                    child: Consumer(
                      builder: (context, ref, _) {
                        if (ref.watch(trigger)) ref.watch(derived);
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final container = tester.container();
        expect(find.text('derived:1'), findsOneWidget);
        expect(find.text('target:1'), findsOneWidget);

        container.read(trigger.notifier).state = true;
        await tester.pump();
        expect(errors, [isDeferredRefreshReport(), isDeferredRebuildReport()]);
        errors.clear();
        expect(find.text('derived:1'), findsOneWidget);
        expect(find.text('target:1'), findsOneWidget);

        await tester.pump();
        expect(errors, isEmpty);
        expect(find.text('derived:2'), findsOneWidget);
        expect(find.text('target:2'), findsOneWidget);

        // Neither the scope nor the watchers are stranded afterwards.
        container.invalidate(derived);
        await tester.pump();
        expect(errors, isEmpty);
        expect(find.text('derived:3'), findsOneWidget);
      },
    );

    testWidgets(
      'a refresh requested while a scope runs its task is applied in the '
      'same frame, without report',
      (tester) async {
        // Nested scopes have their own scheduler. A root provider refreshed
        // by the root scope's task invalidates the scoped provider watching
        // it, which schedules a refresh on the nested scope while the root
        // scope is building.
        var rootBuildCount = 0;
        final root = Provider<int>((ref) => ++rootBuildCount);
        final scoped = Provider<int>((ref) => throw UnimplementedError());

        await tester.pumpWidget(
          ProviderScope(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ProviderScope(
                overrides: [scoped.overrideWith((ref) => ref.watch(root) * 10)],
                child: Consumer(
                  builder: (context, ref, _) {
                    return Text('scoped:${ref.watch(scoped)}');
                  },
                ),
              ),
            ),
          ),
        );
        expect(find.text('scoped:10'), findsOneWidget);

        final rootContainer = ProviderScope.containerOf(
          tester.element(find.byType(Directionality)),
          listen: false,
        );
        rootContainer.invalidate(root);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('scoped:20'), findsOneWidget);
      },
    );

    testWidgetsWithStubbedFlutterErrors(
      'a listener writing a root provider during a nested scope refresh '
      'defers the widgets and scope above that scope to the next frame, '
      'without report',
      (tester, errors) async {
        var count = 0;
        final scopedSource = NotifierProvider<DeferredNotifier<int>, int>(
          () => DeferredNotifier((ref, self) => 0),
        );
        final scopedDerived = Provider<int>(
          (ref) => throw UnimplementedError(),
        );
        final target = NotifierProvider<DeferredNotifier<int>, int>(
          () => DeferredNotifier((ref, self) => 0),
        );
        // A root provider deriving from `target`: its refresh goes through
        // the root scope, which is above the nested scope being refreshed.
        final targetTimesTwo = Provider<int>((ref) => ref.watch(target) * 2);

        late ProviderContainer nested;
        await tester.pumpWidget(
          ProviderScope(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  // Already built and outside of the nested scope.
                  Consumer(
                    builder: (context, ref, _) {
                      return Text('target:${ref.watch(target)}');
                    },
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      return Text('x2:${ref.watch(targetTimesTwo)}');
                    },
                  ),
                  ProviderScope(
                    overrides: [
                      scopedSource.overrideWith(
                        () => DeferredNotifier((ref, self) => 100),
                      ),
                      scopedDerived.overrideWith(
                        (ref) => ref.watch(scopedSource) * 10 + (++count),
                      ),
                    ],
                    child: Consumer(
                      builder: (context, ref, _) {
                        nested = ProviderScope.containerOf(
                          context,
                          listen: false,
                        );
                        ref.listen(scopedDerived, (_, next) {
                          ref.read(target.notifier).state = next;
                        });
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final root = tester.container(of: find.text('target:0'));
        expect(find.text('x2:0'), findsOneWidget);

        nested.read(scopedSource.notifier).state = 5;
        await tester.pump();
        expect(errors, isEmpty);
        expect(root.read(target), 52);

        await tester.pump();
        expect(errors, isEmpty);
        expect(find.text('target:52'), findsOneWidget);
        expect(find.text('x2:104'), findsOneWidget);

        // Neither the widgets nor the root scope are stranded afterwards.
        root.read(target.notifier).state = 7;
        await tester.pump();
        expect(errors, isEmpty);
        expect(find.text('target:7'), findsOneWidget);
        expect(find.text('x2:14'), findsOneWidget);
      },
    );
  });

  group('scheduler', () {
    testWidgets(
      'a scope disposed while a refresh is pending hands the task over, so '
      'the container keeps refreshing once a scope is mounted again',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        var count = 0;
        final provider = Provider<int>((ref) => ++count);

        Widget app() {
          return UncontrolledProviderScope(
            container: container,
            child: Consumer(
              builder: (context, ref, _) {
                return Text(
                  'p:${ref.watch(provider)}',
                  textDirection: TextDirection.ltr,
                );
              },
            ),
          );
        }

        await tester.pumpWidget(app());
        expect(find.text('p:1'), findsOneWidget);

        // Refresh pending, and the scope is unmounted before running it.
        container.invalidate(provider);
        await tester.pumpWidget(const SizedBox());

        await tester.pumpWidget(app());
        expect(find.text('p:2'), findsOneWidget);

        container.invalidate(provider);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('p:3'), findsOneWidget);
      },
    );

    testWidgets(
      'a refresh requested while the scheduler disposes providers is applied '
      'in the same task',
      (tester) async {
        var count = 0;
        final watched = Provider<int>((ref) => ++count);
        late ProviderContainer container;
        final disposable = Provider.autoDispose<int>((ref) {
          ref.onDispose(() => container.invalidate(watched));
          return 0;
        });

        await tester.pumpWidget(
          ProviderScope(
            child: Consumer(
              builder: (context, ref, _) {
                return Text(
                  'watched:${ref.watch(watched)}',
                  textDirection: TextDirection.ltr,
                );
              },
            ),
          ),
        );
        container = tester.container();
        expect(find.text('watched:1'), findsOneWidget);

        final sub = container.listen(disposable, (_, _) {});
        await tester.pump();
        sub.close();
        // The dispose task runs in a microtask, which the test binding flushes
        // after deciding whether this pump runs a frame: the frame requested
        // by the refreshed widget runs on the next pump.
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('watched:2'), findsOneWidget);
      },
    );
  });
}

class _InvalidateOnInit extends ConsumerStatefulWidget {
  const _InvalidateOnInit(this.provider);

  final Provider<int> provider;

  @override
  ConsumerState<_InvalidateOnInit> createState() => _InvalidateOnInitState();
}

class _InvalidateOnInitState extends ConsumerState<_InvalidateOnInit> {
  @override
  void initState() {
    super.initState();
    ref.invalidate(widget.provider);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
