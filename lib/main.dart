import 'package:app/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MaterialApp(
    home: HomePage(),
    title: 'Useful Rabbit',
  ));
}
