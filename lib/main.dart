import 'package:app/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;

void main() async {
  await dotenv.load(fileName: ".env");
  initOpus(await opus_flutter.load());
  runApp(const MaterialApp(
    home: HomePage(),
    title: 'Useful Rabbit',
  ));
}
