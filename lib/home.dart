import 'package:flutter/material.dart';
import 'package:openai_realtime_dart/openai_realtime_dart.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late RealtimeClient client;

  @override
  void initState() {
    client = RealtimeClient(
      apiKey:
          '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',
    );
    // client.updateSession(instructions: 'You are a great, upbeat friend.');
    client.updateSession(voice: 'alloy');
    client.updateSession(
      turnDetection: {'type': 'none'},
      inputAudioTranscription: {'model': 'whisper-1'},
    );

    // Set up event handling
    client.on('conversation.updated', (event) {
      print(event);
      // item is the current item being updated
      // final item = event?['item'];
      // delta can be null or populated
      // final delta = event?['delta'];
      // you can fetch a full list of items at any time
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
      ),
      body: const Center(
        child: Text('This is the home page'),
      ),
    );
  }
}
