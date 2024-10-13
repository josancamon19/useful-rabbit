import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart' show Level;
import 'package:openai_realtime_dart/openai_realtime_dart.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late RealtimeClient client;

  List<Map<String, dynamic>> realtimeEvents = [];
  List<dynamic> items = [];

  late StreamController<Uint8List> _controller;

  final record = FlutterSoundRecorder(logLevel: Level.off);
  Queue<Uint8List> audioQueue = Queue<Uint8List>();

  late FlutterSoundPlayer _player;

  _initiatePlayer() async {
    _player = FlutterSoundPlayer(logLevel: Level.off);
    await _player.openPlayer();
    await _player.setVolume(1.0);
  }

  _initRecording() async {
    // TODO: Check and request permission
    _controller = StreamController<Uint8List>();
    await record.openRecorder();
    await record.startRecorder(
      toStream: _controller.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      bitRate: 16000,
      bufferSize: 8192,
      sampleRate: 24000,
    );

    _controller.stream.listen((buffer) {
      client.appendInputAudio(buffer);
    });
  }

  _initClient() async {
    client = RealtimeClient(
      apiKey:
          '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',
    );

    // Update session with instructions and transcription model
    client.updateSession(
      instructions: 'You are a productive assistant, you speak very little, and answers short every time.',
      inputAudioTranscription: {'model': 'whisper-1'},
      turnDetection: {
        "type": "server_vad",
        "threshold": 0.5,
        "prefix_padding_ms": 300,
        "silence_duration_ms": 200,
      },
    );

    // Set up event handling for 'realtime.event'
    client.on('realtime.event', (realtimeEvent) {
      if (realtimeEvent == null) return;
      if (realtimeEvent['event'] == null) return;
      setState(() {
        final lastEvent = realtimeEvents.isNotEmpty ? realtimeEvents.last : null;
        if (lastEvent != null && lastEvent['event']['type'] == realtimeEvent['event']['type']) {
          lastEvent['count'] = (lastEvent['count'] ?? 0) + 1;
          realtimeEvents[realtimeEvents.length - 1] = lastEvent;
        } else {
          realtimeEvents.add(realtimeEvent);
        }
      });
    });

    client.on('error', (event) => print('Error: $event'));
    client.on('conversation.interrupted', (event) async {
      print('conversation.interrupted $event');
    });

    client.on('conversation.updated', (event) async {
      if (event == null) return;
      final item = event['item'];
      final delta = event['delta'];
      if (delta != null && delta['audio'] != null) {
        // print(delta['audio']);
      }
      if (item['status'] == 'completed' &&
          item['formatted']['audio'] != null &&
          item['formatted']['audio'].length > 0) {
        Uint8List audio = item['formatted']['audio'];
        await _player.startPlayer(
          fromDataBuffer: audio,
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 24000,
        );
        setState(() {
          items.add(item);
        });
      }
    });

    setState(() {
      items = client.conversation.getItems();
    });

    await client.connect();

    // Optionally send an initial message
    client.sendUserMessageContent([
      {'type': 'input_text', 'text': 'Hello!'}
    ]);
  }

  @override
  void initState() {
    super.initState();
    _initClient();
    _initRecording();
    _initiatePlayer();
  }

  @override
  void dispose() {
    client.disconnect();
    client.reset();
    record.stopRecorder();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
      ),
      body: Center(
        child: ListView.builder(
          itemBuilder: (context, index) {
            final item = items[index];
            final transcript = item['content'][0]['transcript'] ?? '';
            if (item == null || transcript.toString().isEmpty) return const SizedBox();
            // print(item);
            return ListTile(
              title: Text(item['object']),
              subtitle: Text(transcript),
            );
          },
          itemCount: items.length,
        ),
        // child: ListView.builder(
        //   itemBuilder: (context, index) {
        //     final item = realtimeEvents[index];
        //     if (item['event']['audio'] != null) item['event']['audio'] = null;
        //     if (item['event']['delta'] != null) item['event']['delta'] = null;
        //     return ListTile(
        //       title: Text('${item['event']['type']} (${item['count'] ?? 1})'),
        //       subtitle: Text(item['event'].toString()),
        //     );
        //   },
        //   itemCount: realtimeEvents.length,
        // ),
      ),
    );
  }
}
