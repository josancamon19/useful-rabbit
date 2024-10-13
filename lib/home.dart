import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart' show Level;
import 'package:openai_realtime_dart/openai_realtime_dart.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late RealtimeClient client;
  Map<String, dynamic> memoryKv = {};
  Map<String, dynamic> marker = {};
  Map<String, dynamic> coords = {};
  List<Map<String, dynamic>> realtimeEvents = [];
  List<dynamic> items = [];

  late StreamController<Uint8List> _controller;

  final record = FlutterSoundRecorder(logLevel: Level.off);
  Queue<Uint8List> audioQueue = Queue<Uint8List>();

  final FlutterSoundPlayer _player = FlutterSoundPlayer(logLevel: Level.off);
// Add audio bytes to the queue in order of arrival
//   void enqueueAudioBytes(Uint8List pcmBytes) async{
//     await _player.startPlayer(
//       fromDataBuffer: pcmBytes,
//       codec: Codec.pcm16,
//       numChannels: 1,
//       sampleRate: 24000,
//     );
//     // audioQueue.add(pcmBytes);
//     // if (audioQueue.length == 1) {
//     //   playNextAudioChunk();
//     // }
//   }

  // void playNextAudioChunk() async {
  //   if (audioQueue.isNotEmpty) {
  //     Uint8List nextChunk = audioQueue.removeFirst();
  //     await playAudioChunk(nextChunk);
  //     if (audioQueue.isNotEmpty) {
  //       playNextAudioChunk();
  //     }
  //   }
  // }
  //
  // Future<void> playAudioChunk(Uint8List pcmBytes) async {
  //   if (!_player.isOpen()) return;
  //   print('Playing audio chunk ${pcmBytes}');
  //   await _player.startPlayer(
  //     fromDataBuffer: pcmBytes,
  //     codec: Codec.pcm16,
  //     numChannels: 1,
  //     sampleRate: 24000,
  //   );
  // }

  _initiatePlayer() async {
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
    List<int> queue = [];
    _controller.stream.listen((buffer) {
      // send queue only when it reaches 1 second of audio
      client.appendInputAudio(buffer);
      // queue.addAll(buffer);
      // if (queue.length >= 24000) {
      //   print('Sending audio chunk ${queue.length} bytes');
      //   queue.clear();
      // }
      // if (client.sessionCreated) {
      //   client.appendInputAudio(buffer);
      // }
    });
  }

  _initClient() async {
    client = RealtimeClient(
      apiKey:
          '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',
    );

    // Update session with instructions and transcription model
    client.updateSession(
      instructions: 'You are a great, upbeat friend.',
      inputAudioTranscription: {'model': 'whisper-1'},
      turnDetection: {
        "type": "server_vad",
        "threshold": 0.5,
        "prefix_padding_ms": 300,
        "silence_duration_ms": 200,
      },
    );

    // Add the 'set_memory' tool
    client.addTool(
      {
        'name': 'set_memory',
        'description': 'Saves important data about the user into memory.',
        'parameters': {
          'type': 'object',
          'properties': {
            'key': {
              'type': 'string',
              'description': 'The key of the memory value. Always use lowercase and underscores, no other characters.',
            },
            'value': {
              'type': 'string',
              'description': 'Value can be anything represented as a string',
            },
          },
          'required': ['key', 'value'],
        },
      },
      (params) async {
        final key = params['key'];
        final value = params['value'];
        setState(() {
          memoryKv[key] = value;
        });
        return {'ok': true};
      },
    );

    // Add the 'get_weather' tool
    client.addTool(
      {
        'name': 'get_weather',
        'description': 'Retrieves the weather for a given lat, lng coordinate pair. Specify a label for the location.',
        'parameters': {
          'type': 'object',
          'properties': {
            'lat': {
              'type': 'number',
              'description': 'Latitude',
            },
            'lng': {
              'type': 'number',
              'description': 'Longitude',
            },
            'location': {
              'type': 'string',
              'description': 'Name of the location',
            },
          },
          'required': ['lat', 'lng', 'location'],
        },
      },
      (params) async {
        print('get_weather params: $params');
        final lat = params['lat'];
        final lng = params['lng'];
        final location = params['location'];
        setState(() {
          marker = {
            'lat': lat,
            'lng': lng,
            'location': location,
          };
          coords = {
            'lat': lat,
            'lng': lng,
            'location': location,
          };
        });
        final result = await http.get(Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current_weather=true',
        ));
        final jsonData = jsonDecode(result.body);
        final temperature = {
          'value': jsonData['current_weather']['temperature'],
          'units': '°C',
        };
        final windSpeed = {
          'value': jsonData['current_weather']['windspeed'],
          'units': 'km/h',
        };
        setState(() {
          marker = {
            'lat': lat,
            'lng': lng,
            'location': location,
            'temperature': temperature,
            'wind_speed': windSpeed,
          };
        });
        return jsonData;
      },
    );

    // Set up event handling for 'realtime.event'
    client.on('realtime.event', (realtimeEvent) {
      if (realtimeEvent == null) return;
      if (realtimeEvent['event'] == null) return;
      if (realtimeEvent['event']['type'] == 'input_audio_buffer.append') {
        String base64 = realtimeEvent['event']['audio'];
        Uint8List bytes = base64Decode(base64);
        // print('Realtime event: $bytes');
      }
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

    // Handle 'error' events
    client.on('error', (event) => print('Error: $event'));

    // Handle 'conversation.interrupted' events
    client.on('conversation.interrupted', (event) async {
      print('conversation.interrupted $event');
      // Implement interruption handling if necessary
    });

    // Handle 'conversation.updated' events
    client.on('conversation.updated', (event) async {
      if (event == null) return;
      // print('Conversation updated: $event');
      final item = event['item'];
      final delta = event['delta'];
      // final conversationItems = client.conversation.getItems();
      if (delta != null && delta['audio'] != null) {
        // print(delta['audio']);
      }
      if (item['status'] == 'completed' &&
          item['formatted']['audio'] != null &&
          item['formatted']['audio'].length > 0) {
        print('Completed audio: ${item['content'][0]}');
        Uint8List audio = item['formatted']['audio'];
        await _player.startPlayer(
          fromDataBuffer: audio,
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 24000,
        );
        print(audio.runtimeType);
        print(audio);
        setState(() {
          items.add(item);
        });
      }
      // setState(() {
      //   items = conversationItems;
      // });
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
