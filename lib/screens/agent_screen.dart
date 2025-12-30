import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as sdk;
import 'package:livekit_components/livekit_components.dart' as components;
import 'package:provider/provider.dart';

import '../controllers/app_ctrl.dart';
import '../support/agent_selector.dart';
import '../widgets/agent_layout_switcher.dart';
import '../widgets/camera_toggle_button.dart';
import '../widgets/message_bar.dart';

class AgentTrackView extends StatefulWidget {
  const AgentTrackView({super.key});

  @override
  State<AgentTrackView> createState() => _AgentTrackViewState();
}

class _AgentTrackViewState extends State<AgentTrackView> {
  sdk.EventsListener<sdk.RoomEvent>? _roomListener;

  @override
  void dispose() {
    _roomListener?.dispose();
    super.dispose();
  }

  void _setupRoomListener(sdk.Room room) {
    _roomListener?.dispose();
    _roomListener = room.createListener();
    
    // Listen for track published and subscribed events
    _roomListener!
      ..on<sdk.TrackPublishedEvent>((event) {
        print('AgentTrackView: TrackPublishedEvent from ${event.participant.identity}');
        if (mounted) setState(() {});
      })
      ..on<sdk.TrackSubscribedEvent>((event) {
        print('AgentTrackView: TrackSubscribedEvent from ${event.participant.identity}, track: ${event.track.sid}');
        if (mounted) setState(() {});
      })
      ..on<sdk.ParticipantConnectedEvent>((event) {
        print('AgentTrackView: ParticipantConnectedEvent: ${event.participant.identity}');
        if (mounted) setState(() {});
      });
  }

  @override
  Widget build(BuildContext context) => AgentParticipantSelector(
        builder: (ctx, agentParticipant) {
          if (agentParticipant == null) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 50),
              alignment: Alignment.center,
              child: const Text('Waiting for agent...'),
            );
          }

          // Get the room to find the avatar agent
          final roomContext = components.RoomContext.of(ctx);
          if (roomContext == null) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 50),
              alignment: Alignment.center,
              child: const Text('Waiting for room...'),
            );
          }
          
          final room = roomContext.room;
          
          // Set up listener if not already done
          if (_roomListener == null) {
            _setupRoomListener(room);
          }
          
          // Find the avatar agent that publishes on behalf of the main agent
          sdk.Participant? avatarAgent;
          try {
            avatarAgent = room.remoteParticipants.values.firstWhere(
              (p) => p.attributes['lk.publish_on_behalf'] == agentParticipant.identity,
            );
            print('AgentTrackView: Found avatar agent: ${avatarAgent.identity}');
          } catch (e) {
            // If no avatar agent found, use the agent participant itself
            avatarAgent = agentParticipant;
            print('AgentTrackView: No avatar agent found, using main agent: ${avatarAgent.identity}');
          }
          
          // Check for video track first, then audio
          final videoPublication = avatarAgent.trackPublications.values
              .where((pub) => pub.kind == sdk.TrackType.VIDEO)
              .firstOrNull;
          
          print('AgentTrackView: videoPublication found: ${videoPublication != null}, track: ${videoPublication?.track}, subscribed: ${videoPublication?.subscribed}, muted: ${videoPublication?.muted}');
          
          final hasVideo = videoPublication?.track != null && 
                           videoPublication!.subscribed == true &&
                           videoPublication.track is sdk.VideoTrack;
          
          print('AgentTrackView: hasVideo=$hasVideo, building widget');
          
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 50),
            alignment: Alignment.center,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 350),
              child: hasVideo
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: sdk.VideoTrackRenderer(
                        videoPublication!.track as sdk.VideoTrack,
                        fit: sdk.VideoViewFit.contain,
                      ),
                    )
                  : const components.AudioVisualizerWidget(
                      options: components.AudioVisualizerWidgetOptions(
                        barCount: 5,
                        width: 32,
                        minHeight: 32,
                        maxHeight: 320,
                      ),
                    ),
            ),
          );
        },
      );
}

class FrontView extends StatelessWidget {
  final AgentScreenState screenState;

  const FrontView({
    super.key,
    required this.screenState,
  });

  @override
  Widget build(BuildContext context) => components.MediaDeviceContextBuilder(
        builder: (context, roomCtx, mediaDeviceCtx) => Row(
          spacing: 20,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Flexible(
              flex: 2,
              fit: FlexFit.tight,
              child: AgentTrackView(),
            ),
            if (screenState == AgentScreenState.transcription && mediaDeviceCtx.cameraOpened)
              Flexible(
                fit: FlexFit.tight,
                child: AnimatedOpacity(
                  opacity: (screenState == AgentScreenState.transcription && mediaDeviceCtx.cameraOpened) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(15)),
                    child: components.ParticipantSelector(
                      filter: (identifier) => identifier.isVideo && identifier.isLocal,
                      builder: (context, identifier) => components.VideoTrackWidget(
                        fit: sdk.VideoViewFit.cover,
                        noTrackBuilder: (ctx) => Container(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class AgentScreen extends StatelessWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext ctx) => Material(
        child: Selector<AppCtrl, AgentLayoutState>(
          selector: (ctx, appCtrl) => AgentLayoutState(
            isTranscriptionVisible: appCtrl.agentScreenState == AgentScreenState.transcription,
            isCameraVisible: appCtrl.isUserCameEnabled,
            isScreenshareVisible: appCtrl.isScreenshareEnabled,
          ),
          builder: (ctx, agentLayoutState, child) => AgentLayoutSwitcher(
            layoutState: agentLayoutState,
            // agentViewBuilder: (ctx) => AgentTrackView(),
            buildAgentView: (ctx) => const AgentTrackView(),
            buildCameraView: (ctx) => Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
              ),
              child: components.MediaDeviceContextBuilder(
                builder: (context, roomCtx, mediaDeviceCtx) => components.ParticipantSelector(
                  filter: (identifier) => identifier.isVideo && identifier.isLocal,
                  builder: (context, identifier) => Stack(
                    children: [
                      components.VideoTrackWidget(
                        fit: sdk.VideoViewFit.cover,
                        noTrackBuilder: (ctx) => Container(),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: CameraToggleButton(
                          onTap: () => mediaDeviceCtx.toggleCameraPosition(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            buildScreenShareView: (ctx) => Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
              ),
              child: components.ParticipantSelector(
                filter: (identifier) => identifier.source == sdk.TrackSource.screenShareVideo && identifier.isLocal,
                builder: (context, identifier) => components.VideoTrackWidget(
                  fit: sdk.VideoViewFit.contain,
                  noTrackBuilder: (ctx) => Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                    ),
                    child: const Text('Screen Share'),
                  ),
                ),
              ),
            ),
            transcriptionsBuilder: (ctx) => Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => ctx.read<AppCtrl>().messageFocusNode.unfocus(),
                    child: Consumer<sdk.Session>(
                      builder: (context, session, _) {
                        if (session.messages.isEmpty) {
                          return _AgentListeningPlaceholder(canListen: session.agent.canListen);
                        }
                        return components.ChatScrollView(
                          session: session,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          physics: const BouncingScrollPhysics(),
                          messageBuilder: (context, message) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _MessageBubble(message: message),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding:
                      EdgeInsets.only(left: 16, right: 16, bottom: max(0, MediaQuery.of(ctx).viewInsets.bottom - 80)),
                  child: Selector<AppCtrl, bool>(
                    selector: (ctx, appCtx) => appCtx.isSendButtonEnabled,
                    builder: (ctx, isSendEnabled, child) => MessageBar(
                      focusNode: ctx.read<AppCtrl>().messageFocusNode,
                      isSendEnabled: isSendEnabled,
                      controller: ctx.read<AppCtrl>().messageCtrl,
                      onSendTap: () => ctx.read<AppCtrl>().sendMessage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final sdk.ReceivedMessage message;

  bool get _isUserMessage => message.content is sdk.UserInput || message.content is sdk.UserTranscript;

  @override
  Widget build(BuildContext context) {
    final text = message.content.text.trim();
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final bool isUser = _isUserMessage;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final colorScheme = Theme.of(context).colorScheme;
    final background = isUser ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final foreground = isUser ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentListeningPlaceholder extends StatelessWidget {
  const _AgentListeningPlaceholder({required this.canListen});

  final bool canListen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq, size: 32, color: colorScheme.primary.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            'Agent is listening',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (!canListen)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Start a conversation to see messages here.',
                style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
