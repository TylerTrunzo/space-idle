import 'package:material_ui/material_ui.dart';

/// A list built lazily, row by row as it scrolls into view, that keeps a
/// keyed row's state when the row moves: a pending confirm on a building
/// stays with that building when a row above it goes.
///
/// A plain `ListView.builder` matches its rows by position when the list
/// changes; this one looks a keyed row up by its key
/// (`findChildIndexCallback`).
class LazyList extends StatelessWidget {
  /// Creates the list of [items].
  const LazyList({
    super.key,
    required this.items,
    this.controller,
    this.padding,
  });

  /// The rows, in order; only those on screen (and the list's cache
  /// extent) are built.
  final List<Widget> items;

  /// The scroll controller, such as a sheet's.
  final ScrollController? controller;

  /// Padding around the rows.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final index = <Key, int>{for (final (i, w) in items.indexed) ?w.key: i};
    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: items.length,
      itemBuilder: (context, i) => items[i],
      findChildIndexCallback: (key) => index[key],
    );
  }
}
