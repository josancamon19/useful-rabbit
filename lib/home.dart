import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart' show Level;
import 'package:openai_realtime_dart/openai_realtime_dart.dart';

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

  List<Map<String, dynamic>> realtimeEvents = [];
  List<dynamic> items = [];
  DeviceServiceStatus _status = DeviceServiceStatus.init;

  BluetoothDevice bleDevice = BluetoothDevice.fromId('DF:D5:D9:DF:2D:58');

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
  StreamSubscription? _micStream;
  StreamSubscription? _buttonStream;
  
String buttonDataStreamCharacteristicUuid = '23ba7924-0000-1000-7450-346eac492e92';
String buttonTriggerCharacteristicUuid = '23ba7925-0000-1000-7450-346eac492e92';

String friendServiceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
String audioDataStreamCharacteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';
String audioCodecCharacteristicUuid = '19b10002-e8f2-537e-4f6c-d104768a1214';
BluetoothService? buttonService;
BluetoothService? audioService;
  _initBleConnection() async {
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
          // debugPrint('${r.device.remoteId.str}: "${r.advertisementData.advName}" found!');

    //       if (r.device.remoteId.str == 'DF:D5:D9:DF:2D:58') {
    //         // bleDevice = r.device;
    //         // debugPrint('connecting to device');
    //         // await r.device.connect();
    //       }
    //     }
    //   },
    //   onError: (e) {
    //     debugPrint('bleFindDevices error: $e');
    //   },
    // );
    // // DF:D5:D9:DF:2D:58

    // FlutterBluePlus.cancelWhenScanComplete(discoverSubscription);
    // await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;

    await FlutterBluePlus.startScan(
        // withServices:[Guid("180D")], // match any of the specified services
        // withNames:["Bluno"], // *or* any of the specified names
        timeout: const Duration(seconds: 5));

    await bleDevice.connect();


    if (bleDevice.isConnected)
    {
      debugPrint('Connected to device');
    }

    List<BluetoothService> services = await bleDevice.discoverServices();
    services.forEach((service) {
      debugPrint(service.uuid.str128.toLowerCase());
    });

    // final buttonService = await getServiceByUuid('DF:D5:D9:DF:2D:58', buttonDataStreamCharacteristicUuid);
    buttonService = services.firstWhere((service) => service.uuid.str128.toLowerCase() == buttonDataStreamCharacteristicUuid);
    // audioService = services.firstWhere((service) => service.uuid.str128.toLowerCase() == friendServiceUuid);
    if (buttonService == null) {
        debugPrint('Button error');
        return null;
      }
    else {
      debugPrint('Button service found');
    }

      // if (audioService == null) {
      //   debugPrint('Audio error');
      //   return null;
      // }
      // else {
      //   debugPrint('Audio service found');
      // }

  var buttonCharacteristic = buttonService!.characteristics.firstWhere(
    (characteristic) => characteristic.uuid.str128.toLowerCase() == buttonTriggerCharacteristicUuid.toLowerCase(),
  );

   _buttonStream = buttonCharacteristic!.lastValueStream.listen((event) {
    debugPrint('Button pressed');
   });




   //audio
    // var audioDataStreamCharacteristic = getCharacteristic(_friendService!, audioDataStreamCharacteristicUuid);
  }

  _initClient() async {
    client = RealtimeClient(apiKey: dotenv.env['OPENAI_API_KEY']);
    // addBasicMemoryToolToClient(client);

    client.updateSession(
      instructions: '''
      System settings:
      Tool use: enabled.
      
      Instructions: You are a productive assistant, you speak very little, and answers short every time.
      Personality: Be short and concise.
      ''',
      inputAudioTranscription: {'model': 'whisper-1'},
      toolChoice: 'auto',
      // turnDetection: {
      //   "type": "server_vad",
      //   "threshold": 0.5,
      //   "prefix_padding_ms": 300,
      //   "silence_duration_ms": 200,
      // },
    );
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
        return {'ok': '24 degrees celcius, sunny, no rain'};
      },
    );
    // Set up event handling for 'realtime.event'
    client.on('realtime.event', (realtimeEvent) {
      if (realtimeEvent == null) return;
      if (realtimeEvent['event'] == null) return;
      // TODO: user events not received
      setState(() {
        final lastEvent = realtimeEvents.isNotEmpty ? realtimeEvents.last : null;
        if (lastEvent != null && lastEvent['event']['type'] == realtimeEvent['event']['type']) {
          lastEvent['count'] = (lastEvent['count'] ?? 0) + 1;
          realtimeEvents[realtimeEvents.length - 1] = lastEvent;
        } else {
          realtimeEvents.add(realtimeEvent);
          print('realtime.event: $realtimeEvent');
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
      if (item['role'] != 'user' &&
          item['status'] == 'completed' &&
          item['formatted']['audio'] != null &&
          item['formatted']['audio'].length > 0) {
        // print('Received: ${item}');
        Uint8List audio = item['formatted']['audio'];
        // print('Audio completed: ${audio.length} bytes');
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
    _initBleConnection();
    _initClient();
    // _initRecording();
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

  void _onLongPressStart(LongPressStartDetails details) {
    setState(() {
      isPressed = true;
    });
    _player.stopPlayer();
    _initRecording(); // Start recording
  }

  void _onLongPressEnd(LongPressEndDetails details) async {
    setState(() {
      isPressed = false;
    });
    await record.stopRecorder();
    client.createResponse();
  }

  bool isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: ListView.builder(
                itemBuilder: (context, index) {
                  final item = items[index];
                  final transcript = item['content'][0]['transcript'] ?? '';
                  if (item == null || transcript.toString().isEmpty) return const SizedBox();
                  return ListTile(
                    title: Text(item['object']),
                    subtitle: Text(transcript),
                  );
                },
                itemCount: items.length,
              ),
            ),
            GestureDetector(
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isPressed ? 120 : 100,
                height: isPressed ? 120 : 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey, // Grey color for the button
                  boxShadow: isPressed
                      ? [BoxShadow(color: Colors.grey.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)]
                      : [],
                ),
                child: const Center(
                  child: Icon(
                    Icons.mic,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
