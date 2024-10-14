import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:app/tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart' show Level;
import 'package:openai_realtime_dart/openai_realtime_dart.dart';
import 'package:opus_dart/opus_dart.dart';

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

  BluetoothDevice bleDevice =
      BluetoothDevice.fromId(dotenv.env['BT_DEVICE_ID']!);

  late StreamController<Food> _controller;

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
    _controller = StreamController<Food>();
    await record.openRecorder();
    await record.startRecorder(
      toStream: _controller.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      bitRate: 16000,
      bufferSize: 8192,
      sampleRate: 24000,
    );
    _controller.stream.listen((Food buffer) {
      Uint8List data = (buffer as FoodData).data!;
      client.appendInputAudio(data);
    });
  }

  StreamSubscription? _micStream;
  StreamSubscription? _buttonStream;

  String buttonDataStreamCharacteristicUuid =
      '23ba7924-0000-1000-7450-346eac492e92';
  String buttonTriggerCharacteristicUuid =
      '23ba7925-0000-1000-7450-346eac492e92';

  String friendServiceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
  String audioDataStreamCharacteristicUuid =
      '19b10001-e8f2-537e-4f6c-d104768a1214';
  String audioCodecCharacteristicUuid = '19b10002-e8f2-537e-4f6c-d104768a1214';
  String audioSpeakerCharacteristicUuid =
      '19b10003-e8f2-537e-4f6c-d104768a1214';

  BluetoothService? buttonService;
  BluetoothService? audioService;
  BluetoothCharacteristic? speakerCharacteristic;
  bool buttonPressed = false;

  final SimpleOpusDecoder opusDecoder =
      SimpleOpusDecoder(sampleRate: 16000, channels: 1);
  List<List<int>> frames = [];

  _initBleConnection() async {
    await FlutterBluePlus.turnOn();

    await FlutterBluePlus.startScan(timeout: Duration(seconds: 5));

    await bleDevice.connect();
    await bleDevice.requestMtu(512);
    if (bleDevice.isConnected) {
      debugPrint('Connected to device');
    }

    List<BluetoothService> services = await bleDevice.discoverServices();
    services.forEach((service) {
      debugPrint(service.uuid.str128.toLowerCase());
    });

    // final buttonService = await getServiceByUuid('DF:D5:D9:DF:2D:58', buttonDataStreamCharacteristicUuid);
    buttonService = services.firstWhere((service) =>
        service.uuid.str128.toLowerCase() ==
        buttonDataStreamCharacteristicUuid);
    audioService = services.firstWhere(
        (service) => service.uuid.str128.toLowerCase() == friendServiceUuid);
    if (buttonService == null) {
      debugPrint('Button error');
      return null;
    } else {
      debugPrint('Button service found');
    }

    var buttonCharacteristic = buttonService!.characteristics.firstWhere(
      (characteristic) =>
          characteristic.uuid.str128.toLowerCase() ==
          buttonTriggerCharacteristicUuid.toLowerCase(),
    );

    await buttonCharacteristic.setNotifyValue(true);

    _buttonStream = buttonCharacteristic!.lastValueStream.listen((event) {
      if (event.isNotEmpty) {
        debugPrint(event[0].toString());

        if (event[0] == 3) {
          debugPrint('Button long pressed');
          buttonPressed = true;
          debugPrint('Button pressed: $buttonPressed');
        } else if (event[0] == 5) {
          debugPrint('Button release');
          buttonPressed = false;
          debugPrint('Button pressed: $buttonPressed');
        }
      }
    });

    if (audioService == null) {
      debugPrint('Audio error');
      return null;
    } else {
      debugPrint('Audio service found');
    }

    var audioCharacteristic = audioService!.characteristics.firstWhere(
      (characteristic) =>
          characteristic.uuid.str128.toLowerCase() ==
          audioDataStreamCharacteristicUuid.toLowerCase(),
    );
    await audioCharacteristic.setNotifyValue(true);

    _micStream = audioCharacteristic!.lastValueStream.listen((event) {
      if (event.isNotEmpty) {
        if (buttonPressed) {
          List<int> content = event.sublist(3);
          List<int> decoded =
              opusDecoder.decode(input: Uint8List.fromList(content));
          print(decoded);
          // frames.add(decoded);
        }
      }
    });

    speakerCharacteristic = audioService!.characteristics.firstWhere(
      (characteristic) =>
          characteristic.uuid.str128.toLowerCase() ==
          audioSpeakerCharacteristicUuid.toLowerCase(),
    );
    await speakerCharacteristic!.setNotifyValue(true);
    if (speakerCharacteristic == null) {
      debugPrint('Speaker error');
    } else {
      debugPrint('Speaker service found');
    }
    //audio
    // var audioDataStreamCharacteristic = getCharacteristic(_friendService!, audioDataStreamCharacteristicUuid);
    _initClient();
  }

  _initClient() async {
    client = RealtimeClient(apiKey: dotenv.env['OPENAI_API_KEY']);

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
    client.addTool({
      'name': 'add_item_to_cart',
      'description':
          'Function to use for adding items to the amazon shopping cart.',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Name of the item to add to the cart',
          },
        },
        'required': ['name'],
      },
    }, (params) async {
      if (params['name'] == null) return {'ok': false};
      bool response = await addItemsOnAmazonToCart([params['name']]);
      return {'ok': response};
    });
    // Set up event handling for 'realtime.event'
    client.on('realtime.event', (realtimeEvent) {
      if (realtimeEvent == null) return;
      if (realtimeEvent['event'] == null) return;

      setState(() {
        final lastEvent =
            realtimeEvents.isNotEmpty ? realtimeEvents.last : null;
        if (lastEvent != null &&
            lastEvent['event']['type'] == realtimeEvent['event']['type']) {
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
        // Create a new list to store the downsampled audio
        int newLength = ((audio.length / 6).floor()) *
            2; // We're taking two bytes every 6 bytes

        Uint8List downSampledAudio = Uint8List(newLength);

        // Loop through the original audio, picking every 0,1 pair, 6,7 pair, etc.
        for (int i = 0, j = 0; i < newLength; i += 2, j += 6) {
          downSampledAudio[i] = audio[j]; // Copy byte 0
          downSampledAudio[i + 1] = audio[j + 1]; // Copy byte 1
        }
        int chunkSize = 400;

        for (int i = 0; i < downSampledAudio.length; i += chunkSize) {
          // Determine the end of the current chunk, ensuring it doesn't exceed the array length
          int end = (i + chunkSize < downSampledAudio.length)
              ? i + chunkSize
              : downSampledAudio.length;

          // Extract the current chunk
          Uint8List chunk = downSampledAudio.sublist(i, end);
          print('Chunk size: ${chunk.length}');
          await speakerCharacteristic!.write(chunk);
        }
        await speakerCharacteristic!.write(Uint8List(0));

        // await _player.startPlayer(
        //   fromDataBuffer: audio,
        //   codec: Codec.pcm16,
        //   numChannels: 1,
        //   sampleRate: 24000,
        // );

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
      {'type': 'input_text', 'text': 'Hey!'},
    ]);
  }

  @override
  void initState() {
    super.initState();
    _initBleConnection();
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
                  if (item == null || transcript.toString().isEmpty)
                    return const SizedBox();
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
                      ? [
                          BoxShadow(
                              color: Colors.grey.withOpacity(0.5),
                              blurRadius: 20,
                              spreadRadius: 5)
                        ]
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
