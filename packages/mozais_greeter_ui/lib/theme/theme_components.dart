import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import '../feature/greeter/greeter_commands.dart';
import '../feature/greeter/greeter_slots.dart';

/// Runtime bindings a theme component may use to render a greeter region.
///
/// The context exposes typed display slots and UI callbacks, not the feature
/// that owns application state or the scene document that selects components.
class GreeterThemeContext {
  const GreeterThemeContext({
    required this.serviceSlots,
    required this.authPromptSlots,
    required this.accountPickerSlots,
    required this.sessionPickerSlots,
    required this.powerSlots,
    required this.tokens,
    required this.credentialController,
    required this.credentialFocusNode,
    required this.onDispatch,
    required this.onRespond,
  });

  final ValueListenable<ServiceSlots> serviceSlots;
  final ValueListenable<AuthPromptSlots> authPromptSlots;
  final ValueListenable<AccountPickerSlots> accountPickerSlots;
  final ValueListenable<SessionPickerSlots> sessionPickerSlots;
  final ValueListenable<PowerSlots> powerSlots;
  final ThemeTokens tokens;
  final TextEditingController credentialController;
  final FocusNode credentialFocusNode;
  final ValueChanged<GreeterCommand> onDispatch;
  final VoidCallback onRespond;
}

/// Component set selected by a theme for its scene nodes.
abstract interface class GreeterThemeComponents {
  Widget build(BuildContext context, SceneNode node);
}

typedef GreeterThemeComponentsFactory = GreeterThemeComponents Function(
  GreeterThemeContext context,
);
