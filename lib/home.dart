import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart' show Level, Logger;
import 'package:openai_realtime_dart/openai_realtime_dart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';


enum DeviceServiceStatus {
  init,
  ready,
  scanning,
  stop,
}

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
  DeviceServiceStatus _status = DeviceServiceStatus.init;

  BluetoothDevice bleDevice=BluetoothDevice.fromId('DF:D5:D9:DF:2D:58');

  late StreamController<Uint8List> _controller;

  final record = FlutterSoundRecorder(logLevel: Level.off);
  Queue<Uint8List> audioQueue = Queue<Uint8List>();

  // final FlutterSoundPlayer _player = FlutterSoundPlayer(logLevel: Level.off);
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
  void enqueueAudioBytes(Uint8List pcmBytes) {
    audioQueue.add(pcmBytes);
    if (audioQueue.length == 1) {
      playNextAudioChunk();
    }
  }



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

  // _initiatePlayer() async {
  //   await _player.openPlayer();
  //   await _player.setVolume(1.0);
  // }

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
      apiKey: '',
    );
    debugPrint('hi');
    // var subscription = FlutterBluePlus.onScanResults.listen((results) {
    //   if (results.isNotEmpty) {
    //     ScanResult r = results.last; // the most recently found device
    //     debugPrint('${r.device.remoteId}: "${r.advertisementData.advName}" found!');
    //   }
    // },
    //   onError: (e) => debugPrint(e),
    // );

      await FlutterBluePlus.turnOn();
    
    
    var discoverSubscription = FlutterBluePlus.onScanResults.listen(
          (results) async {
            if (results.isNotEmpty) {
            // debugPrint('discovered result');
            ScanResult r = results.last; //r is last device
            debugPrint('${r.device.remoteId.str}: "${r.advertisementData.advName}" found!');

            if (r.device.remoteId.str == 'DF:D5:D9:DF:2D:58') {
              // bleDevice = r.device;
              // debugPrint('connecting to device');
              // await r.device.connect();
            }
            }
      },
      onError: (e) {
        debugPrint('bleFindDevices error: $e');
      },
    );
    // DF:D5:D9:DF:2D:58

   
    FlutterBluePlus.cancelWhenScanComplete(discoverSubscription);
    await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;

    await FlutterBluePlus.startScan(
        // withServices:[Guid("180D")], // match any of the specified services
        // withNames:["Bluno"], // *or* any of the specified names
        timeout: Duration(seconds:5));

    bleDevice.connect();

    List<BluetoothService> services = await bleDevice.discoverServices();
    services.forEach((service) {
        // do something with service
    });






    // final String remoteId = "DF:D5:D9:DF:2D:58:";
    // var device = BluetoothDevice.fromId(remoteId);
    // await device.connect();
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

    debugPrint('end ter');

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
        // enqueueAudioBytes(delta['audio']);
      }
      if (item['status'] == 'completed' &&
          item['formatted']['audio'] != null &&
          item['formatted']['audio'].length > 0) {
        print('Completed audio: ${item['content'][0]}');
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
    // _initiatePlayer();
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
        // child: ListView.builder(
        //   itemBuilder: (context, index) {
        //     final item = items[index];
        //     if (item == null) return SizedBox();
        //     return ListTile(
        //       title: Text(item['object']),
        //       subtitle: Text(item['content'][0]['transcript'] ?? ''),
        //     );
        //   },
        //   itemCount: items.length,
        // ),
        child: ListView.builder(
          itemBuilder: (context, index) {
            final item = realtimeEvents[index];
            if (item['event']['audio'] != null) item['event']['audio'] = null;
            if (item['event']['delta'] != null) item['event']['delta'] = null;
            return ListTile(
              title: Text('${item['event']['type']} (${item['count'] ?? 1})'),
              subtitle: Text(item['event'].toString()),
            );
          },
          itemCount: realtimeEvents.length,
        ),
      ),
    );
  }
}
