import 'package:flutter/foundation.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

/// Holds the complete node being edited during one transient gesture.
///
/// Each node gets its own listenable so a frame of geometry updates only
/// rebuilds the layer for the active node.
class SceneNodeDraft {
  final Map<String, ValueNotifier<SceneNode?>> _nodeNotifiers = {};
  SceneNode? _node;

  SceneNode? get node => _node;

  ValueListenable<SceneNode?> getNodeListenable(String nodeId) {
    return _nodeNotifiers.putIfAbsent(
      nodeId,
      () => ValueNotifier<SceneNode?>(_node?.id == nodeId ? _node : null),
    );
  }

  void begin(SceneNode node) {
    _setNode(node);
  }

  void update(SceneNode node) {
    if (_node?.id != node.id) {
      return;
    }
    _setNode(node);
  }

  void clear() {
    final previous = _node;
    if (previous == null) {
      return;
    }
    _node = null;
    _nodeNotifiers[previous.id]?.value = null;
  }

  void _setNode(SceneNode node) {
    final previous = _node;
    _node = node;
    if (previous != null && previous.id != node.id) {
      _nodeNotifiers[previous.id]?.value = null;
    }
    _nodeNotifiers[node.id]?.value = node;
  }

  void dispose() {
    for (final notifier in _nodeNotifiers.values) {
      notifier.dispose();
    }
    _nodeNotifiers.clear();
  }
}
