import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/message_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MessageBannerRoot(child: CrazeChatApp()));
}
