/// One chat message (user or assistant).
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  /// 'user' or 'assistant'
  final String role;
  String text;
  final DateTime time;

  bool get isUser => role == 'user';

  Map<String, dynamic> toApiMap() => {'role': role, 'content': text};
}
