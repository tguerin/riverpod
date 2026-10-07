// ignore_for_file: invalid_use_of_internal_member
part of '../core.dart';

/// {@template riverpod.provider_scope}
/// A widget that stores the state of providers.
///
/// All Flutter applications using Riverpod must contain a [ProviderScope] at
/// the root of their widget tree. It is done as followed:
///
/// ```dart
/// void main() {
///   runApp(
///     // Enabled Riverpod for the entire application
///     ProviderScope(
///       child: MyApp(),
///     ),
///   );
/// }
/// ```
///
/// It's optionally possible to specify `overrides` to change the behavior of
/// some providers. This can be useful for testing purposes:
///
/// ```dart
/// testWidgets('Test example', (tester) async {
///   await tester.pumpWidget(
///     ProviderScope(
///       overrides: [
///         // override the behavior of repositoryProvider to provide a fake
///         // implementation for test purposes.
///         repositoryProvider.overrideWithValue(FakeRepository()),
///       ],
///       child: MyApp(),
///     ),
///   );
/// });
/// ```
///
///
/// Similarly, it is possible to insert other [ProviderScope] anywhere inside
/// the widget tree to override the behavior of a provider for only a part of the
/// application:
///
/// ```dart
/// final themeProvider = Provider((ref) => MyTheme.light());
///
/// void main() {
///   runApp(
///     ProviderScope(
///       child: MaterialApp(
///         // Home uses the default behavior for all providers.
///         home: Home(),
///         routes: {
///           // Overrides themeProvider for the /gallery route only
///           '/gallery': (_) => ProviderScope(
///             overrides: [
///               themeProvider.overrideWithValue(MyTheme.dark()),
///             ],
///           ),
///         },
///       ),
///     ),
///   );
/// }
/// ```
///
/// See also:
/// - [ProviderContainer], a Dart-only class that allows manipulating providers
/// - [UncontrolledProviderScope], which exposes a [ProviderContainer] to the widget
///   tree without managing its life-cycles.
/// {@endtemplate}
/// {@category Core}
final class ProviderScope extends StatefulWidget {
  /// {@macro riverpod.provider_scope}
  const ProviderScope({
    super.key,
    this.overrides = const [],
    this.observers,
    this.retry,
    required this.child,
  });

  /// Read the current [ProviderContainer] for a [BuildContext].
  static ProviderContainer containerOf(
    BuildContext context, {
    bool listen = true,
  }) {
    _UncontrolledProviderScope? scope;

    if (listen) {
      scope =
          context //
              .dependOnInheritedWidgetOfExactType<_UncontrolledProviderScope>();
    } else {
      scope =
          context
                  .getElementForInheritedWidgetOfExactType<
                    _UncontrolledProviderScope
                  >()
                  ?.widget
              as _UncontrolledProviderScope?;
    }

    if (scope == null) {
      throw StateError('No ProviderScope found');
    }

    return scope.container;
  }

  /// The retry logic used by providers associated to this container.
  ///
  /// See [ProviderContainer.defaultRetry] for information about the
  /// default retry logic.
  final Retry? retry;

  /// The part of the widget tree that can use Riverpod and has overridden providers.
  final Widget child;

  /// The listeners that subscribes to changes on providers stored on this [ProviderScope].
  final List<ProviderObserver>? observers;

  /// Information on how to override a provider/family.
  ///
  /// Overrides are created using methods such as [Provider.overrideWith]/[Provider.overrideWithValue].
  ///
  /// This can be used for:
  /// - testing, by mocking a provider.
  /// - dependency injection, to avoid having to pass a value to many
  ///   widgets in the widget tree.
  /// - performance optimization: By using this to inject values to widgets
  ///   using `ref` inside of their constructor, widgets may be able to use
  ///   `const` constructors, which can improve performance.
  ///
  /// **Note**: Overrides only apply to this [ProviderScope] and its descendants.
  /// Ancestors of this [ProviderScope] will not be affected by the overrides.
  final List<Override> overrides;

  @override
  ProviderScopeState createState() => ProviderScopeState();
}

/// Do not use: The [State] of [ProviderScope]
@internal
final class ProviderScopeState extends State<ProviderScope> {
  /// The [ProviderContainer] exposed to [ProviderScope.child].
  @visibleForTesting
  late final ProviderContainer container;
  ProviderContainer? _debugParentOwner;
  var _dirty = false;

  /// The state of the [UncontrolledProviderScope] built by this widget, once
  /// mounted. Set by that state itself.
  _UncontrolledProviderScopeState? _scope;

  @override
  void initState() {
    super.initState();

    final parent = _getParent();
    if (kDebugMode) {
      _debugParentOwner = parent;
    }

    container = ProviderContainer(
      parent: parent,
      overrides: widget.overrides,
      observers: widget.observers,
      retry: widget.retry,
      onError: (err, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: err,
            stack: stack,
            library: 'riverpod',
          ),
        );
      },
    );
  }

  ProviderContainer? _getParent() {
    final scope =
        context
                .getElementForInheritedWidgetOfExactType<
                  _UncontrolledProviderScope
                >()
                ?.widget
            as _UncontrolledProviderScope?;

    return scope?.container;
  }

  @override
  void didUpdateWidget(ProviderScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dirty = true;
  }

  void _debugAssertParentDidNotChange() {
    final parent = _getParent();

    if (parent != _debugParentOwner) {
      throw UnsupportedError(
        'ProviderScope was rebuilt with a different ProviderScope ancestor',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) _debugAssertParentDidNotChange();

    if (_dirty) {
      _dirty = false;
      // The new overrides notify widgets below this scope, which can be
      // marked dirty synchronously while this scope is being built.
      _UncontrolledProviderScopeState._notifyFromBuild(_scope, () {
        container.updateOverrides(widget.overrides);
      });
    }

    return UncontrolledProviderScope(container: container, child: widget.child);
  }

  @override
  void dispose() {
    container.dispose();
    super.dispose();
  }
}

/// {@template riverpod.UncontrolledProviderScope}
/// Expose a [ProviderContainer] to the widget tree.
///
/// This is what makes [Consumer] work.
///
/// **Note**: The [container] will _not_ be disposed when using this widget.
/// It is the caller's responsibility to dispose of it when no longer needed.
/// Alternatively, use [ProviderScope] to automatically manage the lifecycle of
/// the [ProviderContainer].
///
/// {@endtemplate}
/// {@category Core}
class UncontrolledProviderScope extends StatefulWidget {
  /// {@macro riverpod.UncontrolledProviderScope}
  const UncontrolledProviderScope({
    super.key,
    required this.container,
    required this.child,
  });

  /// The [ProviderContainer] exposed to the widget tree.
  final ProviderContainer container;

  /// The part of the widget tree that can use Riverpod.
  final Widget child;

  @override
  State<UncontrolledProviderScope> createState() =>
      _UncontrolledProviderScopeState();
}

final class _UncontrolledProviderScopeState
    extends State<UncontrolledProviderScope>
    implements Vsync {
  /// How many scopes are currently notifying widgets from their own build:
  /// running their scheduler task, or applying new overrides.
  static var _notifyingDepth = 0;

  /// The innermost scope currently notifying widgets from its own build.
  ///
  /// Flutter accepts marking descendants of the widget being built as dirty.
  /// So while a scope notifies from its build, `setState`/`markNeedsBuild`
  /// can be called synchronously on anything below that scope even though a
  /// frame is being built. Anything else has to wait for the end of the
  /// frame: a widget or scope above a nested scope whose refresh wrote a root
  /// provider, another scope exposing the same container, ...
  static _UncontrolledProviderScopeState? _notifyingScope;

  /// Runs [notify], which notifies widgets from within the build of [scope].
  static void _notifyFromBuild(
    _UncontrolledProviderScopeState? scope,
    void Function() notify,
  ) {
    final previousScope = _notifyingScope;
    _notifyingDepth++;
    _notifyingScope = scope;
    try {
      notify();
    } finally {
      _notifyingDepth--;
      _notifyingScope = previousScope;
    }
  }

  /// Whether `setState`/`markNeedsBuild` can be called right now on an element
  /// whose nearest scope is [nearest] (`null` if it has none).
  static bool _canMarkDirtySynchronously(
    _UncontrolledProviderScopeState? nearest,
  ) {
    if (!_isFlutterBuildingFrame()) return true;

    final notifying = _notifyingScope;
    return notifying != null && nearest != null && nearest._isBelow(notifying);
  }

  /// The nearest [UncontrolledProviderScope] above [context], if any.
  static _UncontrolledProviderScopeState? _nearestScopeOf(
    BuildContext context,
  ) {
    final element = context
        .getElementForInheritedWidgetOfExactType<_UncontrolledProviderScope>();
    return (element?.widget as _UncontrolledProviderScope?)?.scope;
  }

  /// The nearest [UncontrolledProviderScope] above this one, if any.
  _UncontrolledProviderScopeState? _parentScope;

  /// The [ProviderScope] that built this widget, if any.
  ProviderScopeState? _owner;

  Task? _task;
  Timer? _vsyncTimer;
  Timer? _vsyncTimOutTimer;
  void Function()? _cancelAsyncTask;

  @override
  void initState() {
    super.initState();
    _updateAncestors();

    if (kDebugMode) debugCanModifyProviders ??= _debugCanModifyProviders;
    assert(
      !widget.container.scheduler.flutterVsyncs.contains(this),
      'Sync already added',
    );
    widget.container.scheduler.flutterVsyncs.add(this);
  }

  @override
  void activate() {
    super.activate();
    _updateAncestors();
  }

  void _updateAncestors() {
    _parentScope = _nearestScopeOf(context);

    // When built by a ProviderScope, that scope is the direct parent.
    Element? parent;
    context.visitAncestorElements((element) {
      parent = element;
      return false;
    });
    final parentState = switch (parent) {
      final StatefulElement element => element.state,
      _ => null,
    };
    final owner = parentState is ProviderScopeState ? parentState : null;
    if (owner != _owner) {
      _detachFromOwner();
      _owner = owner;
      owner?._scope = this;
    }
  }

  void _detachFromOwner() {
    final owner = _owner;
    if (owner != null && identical(owner._scope, this)) owner._scope = null;
    _owner = null;
  }

  /// Whether this scope is [scope] or nested below it.
  bool _isBelow(_UncontrolledProviderScopeState scope) {
    _UncontrolledProviderScopeState? current = this;
    while (current != null) {
      if (identical(current, scope)) return true;
      current = current._parentScope;
    }
    return false;
  }

  @override
  void reassemble() {
    super.reassemble();
    if (kDebugMode) {
      widget.container.debugReassemble();
    }
  }

  void _callTask() {
    if (!mounted) return;

    _cancelAsyncTask?.call();
    _cancelAsyncTask = null;
    _vsyncTimOutTimer?.cancel();
    _vsyncTimOutTimer = null;
    _vsyncTimer?.cancel();
    _vsyncTimer = null;

    final task = _task;
    _task = null;
    if (task == null) return;

    _notifyFromBuild(this, task.call);
  }

  void _debugAssertCanScheduleTask(Task task) {
    assert(
      _task == null
          // Checks for race conditions where a task has been completed in a different scope.
          // If so, it then becomes possible for another task to be scheduled
          // before this scoped had the opportunity to run its task.
          ||
          _task!.completed,
      'Only one task can be scheduled at a time',
    );
    assert(mounted, 'Cannot schedule a task on an unmounted element');
  }

  @override
  void Function()? scheduleRefresh(Task task) {
    _debugAssertCanScheduleTask(task);
    _cancelAsyncTask?.call();
    _cancelAsyncTask = null;

    if (_canMarkDirtySynchronously(this)) {
      setState(() {
        _task = task;
      });
    } else {
      // The refresh was requested while Flutter is building the widget tree,
      // and this scope is not below the scope notifying from its build, if
      // any: `ref.invalidate` from a widget's build or initState, a listener
      // invalidating a provider, a stale provider flushed by `ref.watch`
      // during a build, a nested scope's refresh writing a root provider...
      // Calling setState now would throw in debug mode and, in release mode,
      // leave this scope flagged dirty without ever rebuilding it again (see
      // [_isFlutterBuildingFrame]). Rebuild once the frame is done instead,
      // which runs the task on the next frame.
      _task = task;
      if (kDebugMode && _notifyingDepth == 0) {
        _debugReportRefreshScheduledDuringBuild();
      }
      _rebuildAfterFrame(() {
        if (mounted && _task != null) setState(() {});
      });
    }

    _vsyncTimer?.cancel();
    _vsyncTimer = Timer(Duration.zero, () {
      _vsyncTimer = null;
      if (_task == null) return;
      if (mounted) setState(() {});

      _vsyncTimOutTimer?.cancel();
      _vsyncTimOutTimer = Timer(Duration.zero, () {
        _vsyncTimOutTimer = null;
        _callTask();
      });
    });

    return () {
      _vsyncTimer?.cancel();
      _vsyncTimer = null;
      _vsyncTimOutTimer?.cancel();
      _vsyncTimOutTimer = null;
    };
  }

  @override
  void Function()? scheduleDispose(Task task) {
    _debugAssertCanScheduleTask(task);
    _task = task;

    var canceled = false;
    _cancelAsyncTask?.call();
    _cancelAsyncTask = () => canceled = true;
    Future.microtask(() {
      if (canceled) return;
      _callTask();
    });

    return () {
      canceled = true;
      if (identical(_task, task)) {
        _task = null;
        _cancelAsyncTask = null;
      }
    };
  }

  void _debugReportRefreshScheduledDuringBuild() {
    final toRefresh = widget.container.scheduler.stateToRefresh;
    final provider = toRefresh.isEmpty ? null : toRefresh.last.origin;
    final building = ConsumerStatefulElement._debugBuildingElement;

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError.fromParts([
          ErrorSummary(
            'A provider refresh was requested while the widget tree was building.',
          ),
          ErrorDescription(
            '${provider ?? 'A provider'} was invalidated while Flutter was '
            'building widgets, outside of a ProviderScope refresh. '
            'This typically happens when a widget invalidates or modifies a '
            'provider from build/initState/didChangeDependencies, or when a '
            'stale provider read during a widget build invalidates its '
            'dependents.',
          ),
          if (building != null)
            building.describeElement('The widget currently being built was'),
          ErrorHint(
            'Riverpod deferred the refresh to the next frame instead of '
            'rebuilding the ProviderScope synchronously, which Flutter would '
            'reject. The stack trace points to the code that requested it.',
          ),
        ]),
        stack: StackTrace.current,
        library: 'riverpod',
        context: ErrorDescription('while scheduling a provider refresh'),
      ),
    );
  }

  void _debugCanModifyProviders() {
    if (!kDebugMode) {
      throw StateError(
        'debugCanModifyProviders should not be called outside of debug mode',
      );
    }
    // While a scope notifies from its build, listeners and observers may
    // legitimately modify providers: whatever they notify outside of that
    // scope is deferred to the next frame.
    if (_notifyingDepth > 0) return;

    try {
      setState(() {});
    } catch (err) {
      // Report rather than throw. The modification is applied either way in
      // release mode, and the widgets it notifies are rebuilt on the next
      // frame. Throwing here would stop the notification instead, leaving the
      // provider updated but its watchers stale, which release mode never
      // does.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError.fromParts([
            ErrorSummary(
              'Tried to modify a provider while the widget tree was building.',
            ),
            ErrorDescription('''
If you are encountering this error, chances are you tried to modify a provider
in a widget life-cycle, such as but not limited to:
- build
- initState
- dispose
- didUpdateWidget
- didChangeDependencies

Modifying a provider inside those life-cycles is discouraged, as it leads to
an inconsistent UI state for one frame: the widgets watching the provider are
rebuilt on the next frame only.


To fix this problem, you have one of two solutions:
- (preferred) Move the logic for modifying your provider outside of a widget
  life-cycle. For example, maybe you could update your provider inside a button's
  onPressed instead.

- Delay your modification, such as by encapsulating the modification
  in a `Future(() {...})`.
  This will perform your update after the widget tree is done building.
'''),
          ]),
          stack: StackTrace.current,
          library: 'riverpod',
          context: ErrorDescription('while modifying a provider'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _callTask();

    return _UncontrolledProviderScope(
      container: widget.container,
      scope: this,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _cancelAsyncTask?.call();
    _cancelAsyncTask = null;
    _vsyncTimer?.cancel();
    _vsyncTimer = null;
    _vsyncTimOutTimer?.cancel();
    _vsyncTimOutTimer = null;
    if (kDebugMode && debugCanModifyProviders == _debugCanModifyProviders) {
      debugCanModifyProviders = null;
    }

    _detachFromOwner();
    widget.container.scheduler.flutterVsyncs.remove(this);

    // The scheduler handed its pending task to this scope. Without this, the
    // task would never run and the scheduler would ignore every later request,
    // when the container outlives its scope (a scope rebuilt with a new key,
    // ...). Run it as soon as possible instead. Another scope exposing the
    // same container may run it first, and the container may be disposed in
    // the meantime: the task handles both.
    final task = _task;
    _task = null;
    if (task != null && !task.completed) {
      scheduleMicrotask(task.call);
    }

    super.dispose();
  }
}

/// Whether Flutter is building, laying out or painting a frame.
///
/// During that phase, `setState`/`markNeedsBuild` on an element that is not
/// below the widget currently being built throws in debug mode. In release
/// mode, the element is flagged dirty but the current build pass does not
/// visit it again: it is dropped from the dirty list at the end of the pass
/// while still flagged dirty, so every later `markNeedsBuild` returns early
/// and the element never rebuilds again.
bool _isFlutterBuildingFrame() {
  return SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;
}

/// Runs [rebuild] once the current frame is done, and schedules a new frame.
void _rebuildAfterFrame(void Function() rebuild) {
  SchedulerBinding.instance.addPostFrameCallback((_) => rebuild());
  SchedulerBinding.instance.scheduleFrame();
}

final class _UncontrolledProviderScope extends InheritedWidget {
  const _UncontrolledProviderScope({
    super.key,
    required this.container,
    required this.scope,
    required super.child,
  });

  final ProviderContainer container;

  /// The state exposing [container]. Constant for a given element.
  final _UncontrolledProviderScopeState scope;
  @override
  bool updateShouldNotify(_UncontrolledProviderScope oldWidget) {
    return container != oldWidget.container;
  }
}

/// Widget testing helpers for flutter_riverpod.
@visibleForTesting
extension RiverpodWidgetTesterX on flutter_test.WidgetTester {
  /// Finds the [ProviderContainer] in the widget tree.
  ///
  /// If [of] is provided, searches for the container within the context of
  /// the specified finder.
  @visibleForTesting
  ProviderContainer container({flutter_test.Finder? of}) {
    if (of != null) {
      final element = this.element(of);
      return ProviderScope.containerOf(element, listen: false);
    }

    final scope = widget(flutter_test.find.byType(UncontrolledProviderScope));
    return (scope as UncontrolledProviderScope).container;
  }
}
