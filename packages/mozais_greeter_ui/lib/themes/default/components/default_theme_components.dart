import 'package:flutter/material.dart';
import 'package:mozais_scene/mozais_scene.dart';

import '../../../feature/greeter/greeter_commands.dart';
import '../../../feature/greeter/greeter_slots.dart';
import '../../../theme/theme_components.dart';
import '../../../scene/scene_region.dart';
import 'account_components.dart';
import 'authentication_components.dart';
import 'session_component.dart';
import 'status_component.dart';
import 'system_components.dart';

class DefaultThemeComponents implements GreeterThemeComponents {
  const DefaultThemeComponents(this.host);

  final GreeterThemeContext host;

  @override
  Widget build(BuildContext context, SceneNode node) {
    return switch (node.componentId) {
      'dateTime' => ThemeClock(isTime: node.properties['variant'] == 'time'),
      'powerActions' => SceneRegion<PowerSlots>(
        valueListenable: host.powerSlots,
        builder: (context, power) => PowerActions(
          power: power,
          onAction: (action) {
            host.onDispatch(RequestPowerActionCommand(action));
          },
        ),
      ),
      'glassPanel' => ThemePanel(
        tokens: host.tokens,
        child: const SizedBox.expand(),
      ),
      'avatar' => SceneRegion<AccountPickerSlots>(
        valueListenable: host.accountPickerSlots,
        builder: (context, account) => AccountAvatar(
          account: account,
          tokens: host.tokens,
          onSelect: (user) {
            host.onDispatch(SelectUserCommand(user));
          },
        ),
      ),
      'accountName' => SceneRegion<AccountPickerSlots>(
        valueListenable: host.accountPickerSlots,
        builder: (context, account) => AccountName(account: account),
      ),
      'sessionPicker' => SceneRegion<SessionPickerSlots>(
        valueListenable: host.sessionPickerSlots,
        builder: (context, session) => SessionPicker(
          session: session,
          onSelect: (value) {
            host.onDispatch(SelectSessionCommand(value));
          },
          onRetry: () {
            host.onDispatch(const RetrySessionCatalogCommand());
          },
        ),
      ),
      'credentialField' => SceneRegion<AuthPromptSlots>(
        valueListenable: host.authPromptSlots,
        builder: (context, auth) => CredentialField(
          auth: auth,
          controller: host.credentialController,
          focusNode: host.credentialFocusNode,
        ),
      ),
      'primaryAction' => SceneRegion<AuthPromptSlots>(
        valueListenable: host.authPromptSlots,
        builder: (context, auth) => PrimaryAction(
          auth: auth,
          onRespond: host.onRespond,
          onRetry: (recovery) {
            host.onDispatch(recoveryCommand(recovery));
          },
        ),
      ),
      'status' => ListenableBuilder(
        listenable: Listenable.merge([
          host.serviceSlots,
          host.authPromptSlots,
          host.sessionPickerSlots,
        ]),
        builder: (context, child) => GreeterStatusLine(
          service: host.serviceSlots.value,
          auth: host.authPromptSlots.value,
          session: host.sessionPickerSlots.value,
        ),
      ),
      'background' ||
      'accountPicker' ||
      'secondaryAction' ||
      'decoration' => const SizedBox.shrink(),
      _ => const SizedBox.shrink(),
    };
  }
}
