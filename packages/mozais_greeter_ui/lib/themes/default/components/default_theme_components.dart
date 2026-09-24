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
    return switch (node.kind) {
      SceneNodeKind.dateTime => ThemeClock(
        isTime: node.properties['variant'] == 'time',
      ),
      SceneNodeKind.powerActions => SceneRegion<PowerSlots>(
        valueListenable: host.powerSlots,
        builder: (context, power) => PowerActions(
          power: power,
          onAction: (action) {
            host.onDispatch(RequestPowerActionCommand(action));
          },
        ),
      ),
      SceneNodeKind.glassPanel => ThemePanel(
        tokens: host.tokens,
        child: const SizedBox.expand(),
      ),
      SceneNodeKind.avatar => SceneRegion<AccountPickerSlots>(
        valueListenable: host.accountPickerSlots,
        builder: (context, account) => AccountAvatar(
          account: account,
          tokens: host.tokens,
          onSelect: (user) {
            host.onDispatch(SelectUserCommand(user));
          },
        ),
      ),
      SceneNodeKind.accountName => SceneRegion<AccountPickerSlots>(
        valueListenable: host.accountPickerSlots,
        builder: (context, account) => AccountName(account: account),
      ),
      SceneNodeKind.sessionPicker => SceneRegion<SessionPickerSlots>(
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
      SceneNodeKind.credentialField => SceneRegion<AuthPromptSlots>(
        valueListenable: host.authPromptSlots,
        builder: (context, auth) => CredentialField(
          auth: auth,
          controller: host.credentialController,
          focusNode: host.credentialFocusNode,
        ),
      ),
      SceneNodeKind.primaryAction => SceneRegion<AuthPromptSlots>(
        valueListenable: host.authPromptSlots,
        builder: (context, auth) => PrimaryAction(
          auth: auth,
          onRespond: host.onRespond,
          onRetry: (recovery) {
            host.onDispatch(recoveryCommand(recovery));
          },
        ),
      ),
      SceneNodeKind.status => ListenableBuilder(
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
      SceneNodeKind.background ||
      SceneNodeKind.accountPicker ||
      SceneNodeKind.secondaryAction ||
      SceneNodeKind.decoration => const SizedBox.shrink(),
    };
  }
}
