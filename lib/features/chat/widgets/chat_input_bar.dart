import 'package:flutter/material.dart';

import '../../../core/chat/voice_recorder_service.dart';
import '../../../core/theme/criptivo_theme.dart';
import 'attach_preview_strip.dart';
import 'voice_record_button.dart';

class ChatInputBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final showMic =
        !hasText && pending == null && recorder != null && onVoiceRecorded != null;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending != null)
            AttachPreviewStrip(
              attachment: pending!,
              onClear: onClearPending,
              busy: busy,
            ),
          Container(
            margin: EdgeInsets.fromLTRB(10, 0, 10, showEmojiPicker ? 4 : 10),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: CriptivoColors.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: CriptivoColors.neon.withValues(alpha: 0.2),
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
                IconButton(
                  onPressed: busy ? null : onAttach,
                  color: CriptivoColors.neon,
                  icon: busy
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
                  onPressed: busy ? null : onToggleEmoji,
                  color: showEmojiPicker
                      ? CriptivoColors.neon
                      : CriptivoColors.textSecondary,
                  icon: Icon(
                    showEmojiPicker
                        ? Icons.keyboard_rounded
                        : Icons.emoji_emotions_outlined,
                  ),
                ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !busy,
                      onChanged: onChanged,
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
                      maxLines: 6, // разширява се при обем
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (showMic)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, right: 4),
                    child: VoiceRecordButton(
                      recorder: recorder!,
                      enabled: !busy,
                      onRecorded: onVoiceRecorded!,
                    ),
                  )
                else
                  Material(
                    color: busy
                        ? CriptivoColors.surfaceLight
                        : CriptivoColors.neon,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: busy ? null : onSend,
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