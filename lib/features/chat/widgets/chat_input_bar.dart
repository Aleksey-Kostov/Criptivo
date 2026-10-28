import 'package:flutter/material.dart';

import '../../../core/chat/voice_recorder_service.dart';
import '../../../core/theme/criptivo_theme.dart';
import 'attach_preview_strip.dart';
import 'voice_record_button.dart';

class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool showEmojiPicker;
  final bool hasText;
  final PendingAttachment? pending;
  final VoiceRecorderService? recorder;

  final VoidCallback onAttach;
  final VoidCallback onToggleEmoji;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final VoidCallback onClearPending;
  final Future<void> Function(VoiceRecording recording)? onVoiceRecorded;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.showEmojiPicker,
    required this.hasText,
    required this.onAttach,
    required this.onToggleEmoji,
    required this.onSend,
    required this.onChanged,
    required this.onClearPending,
    this.pending,
    this.recorder,
    this.onVoiceRecorded,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _micKey = GlobalKey<VoiceRecordButtonState>();
  bool _voiceRecording = false;

  bool get _showMic =>
      !widget.hasText &&
      widget.pending == null &&
      widget.recorder != null &&
      widget.onVoiceRecorded != null;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.pending != null && !_voiceRecording)
            AttachPreviewStrip(
              attachment: widget.pending!,
              onClear: widget.onClearPending,
              busy: widget.busy,
            ),

          // Пълна лента: timer + hint + Delete/Send при lock
          if (_voiceRecording)
            VoiceRecordingStrip(
              micState: _micKey.currentState,
              onCancel: () => _micKey.currentState?.finish(cancel: true),
              onSend: () => _micKey.currentState?.finish(cancel: false),
            ),

          Container(
            margin: EdgeInsets.fromLTRB(
              10,
              0,
              10,
              widget.showEmojiPicker ? 4 : 10,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: CriptivoColors.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: _voiceRecording
                    ? CriptivoColors.neon.withValues(alpha: 0.45)
                    : CriptivoColors.neon.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!_voiceRecording) ...[
                  IconButton(
                    onPressed: widget.busy ? null : widget.onAttach,
                    color: CriptivoColors.neon,
                    icon: widget.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: CriptivoColors.neon,
                            ),
                          )
                        : const Icon(Icons.attach_file_rounded),
                  ),
                  IconButton(
                    onPressed: widget.busy ? null : widget.onToggleEmoji,
                    color: widget.showEmojiPicker
                        ? CriptivoColors.neon
                        : CriptivoColors.textSecondary,
                    icon: Icon(
                      widget.showEmojiPicker
                          ? Icons.keyboard_rounded
                          : Icons.emoji_emotions_outlined,
                    ),
                  ),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 140),
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        enabled: !widget.busy,
                        onChanged: widget.onChanged,
                        style: const TextStyle(
                          color: CriptivoColors.textPrimary,
                          fontSize: 15,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Съобщение...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                        ),
                        minLines: 1,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                      ),
                    ),
                  ),
                ] else
                  const Expanded(child: SizedBox.shrink()),

                const SizedBox(width: 4),

                if (_showMic)
                  VoiceRecordButton(
                    key: _micKey,
                    recorder: widget.recorder!,
                    enabled: !widget.busy,
                    onRecorded: widget.onVoiceRecorded!,
                    onRecordingChanged: (v) {
                      if (mounted) setState(() => _voiceRecording = v);
                    },
                  )
                else if (!_voiceRecording)
                  Material(
                    color: widget.busy
                        ? CriptivoColors.surfaceLight
                        : CriptivoColors.neon,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.busy ? null : widget.onSend,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
