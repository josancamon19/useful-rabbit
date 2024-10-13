import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:openai_realtime_dart/openai_realtime_dart.dart';
import 'package:record/record.dart';

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

  final record = AudioRecorder();

  _initRecording() async {
    // Check and request permission if needed
    if (await record.hasPermission()) {
      final stream = await record.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 24000,
        numChannels: 1,
      ));
      stream.listen((data) {
        client.appendInputAudio(data);
      });
    }

    // Stop recording...
    //     final path = await record.stop();
    // ... or cancel it (and implicitly remove file/blob).
    //     await record.cancel();
  }

  _initClient() async {
    client = RealtimeClient(
      apiKey:
          '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', // Replace with your actual API key
    );

    // Update session with instructions and transcription model
    client.updateSession(
      instructions: 'You are a great, upbeat friend.',
      inputAudioTranscription: {'model': 'whisper-1'},
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
    client.on('conversation.interrupted', (_) async {
      // Implement interruption handling if necessary
    });

    // Handle 'conversation.updated' events
    client.on('conversation.updated', (event) async {
      if (event == null) return;

      final item = event['item'];
      final delta = event['delta'];
      final conversationItems = client.conversation.getItems();
      if (delta != null && delta['audio'] != null) {
        // Handle audio data if needed
      }
      if (item['status'] == 'completed' &&
          item['formatted']['audio'] != null &&
          item['formatted']['audio'].length > 0) {
        // Decode and handle audio file if needed
      }
      setState(() {
        items = conversationItems;
      });
    });

    setState(() {
      items = client.conversation.getItems();
    });

    await client.connect();

    // Optionally send an initial message
    client.sendUserMessageContent([
      {'type': 'input_text', 'text': 'Hello!'}
    ]);
    _initRecording();
  }

  @override
  void initState() {
    super.initState();
    _initClient();
  }

  @override
  void dispose() {
    client.reset();
    record.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // You can display the items or events here as needed
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
      ),
      body: Center(
        child: ListView.builder(
          itemBuilder: (context, index) {
            final item = realtimeEvents[index];
            return ListTile(
              title: Text(item['event']['event_id']),
              subtitle: Text(item['event']['type']),
            );
          },
          itemCount: realtimeEvents.length,
        ),
      ),
    );
  }
}
