import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import 'theme_components.dart';

/// A theme-owned scene and the components used to render its nodes.
///
/// [ThemeBundle] contains visual runtime tokens and renderer registrations;
/// the authored scene and its component set stay owned by this theme.
class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.document,
    required this.bundle,
    required this.components,
  });

  final String id;
  final SceneDocument document;
  final ThemeBundle bundle;
  final GreeterThemeComponentsFactory components;

  ThemeTokens get tokens => bundle.tokens;

  ThemeData get materialTheme => bundle.materialTheme;

  ThemeDefinition copyWith({
    String? id,
    SceneDocument? document,
    ThemeBundle? bundle,
  }) {
    return ThemeDefinition(
      id: id ?? this.id,
      document: document ?? this.document,
      bundle: bundle ?? this.bundle,
      components: components,
    );
  }
}
