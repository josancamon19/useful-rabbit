import 'dart:convert';

import 'package:http/http.dart' as http;

//  // Map<String, dynamic> memoryKv = {};
//   // Map<String, dynamic> marker = {};
//   // Map<String, dynamic> coords = {};
// // Add the 'set_memory' tool
void addBasicMemoryToolToClient(client) {
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
      print(params);
// final key = params['key'];
// final value = params['value'];
// setState(() {
//   memoryKv[key] = value;
// });
      return {'ok': true};
    },
  );
}
//
// // Add the 'get_weather' tool
// client.addTool(
// {
// 'name': 'get_weather',
// 'description': 'Retrieves the weather for a given lat, lng coordinate pair. Specify a label for the location.',
// 'parameters': {
// 'type': 'object',
// 'properties': {
// 'lat': {
// 'type': 'number',
// 'description': 'Latitude',
// },
// 'lng': {
// 'type': 'number',
// 'description': 'Longitude',
// },
// 'location': {
// 'type': 'string',
// 'description': 'Name of the location',
// },
// },
// 'required': ['lat', 'lng', 'location'],
// },
// },
// (params) async {
// print('get_weather params: $params');
// // final lat = params['lat'];
// // final lng = params['lng'];
// // final location = params['location'];
// // setState(() {
// //   marker = {
// //     'lat': lat,
// //     'lng': lng,
// //     'location': location,
// //   };
// //   coords = {
// //     'lat': lat,
// //     'lng': lng,
// //     'location': location,
// //   };
// // });
// // final result = await http.get(Uri.parse(
// //   'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current_weather=true',
// // ));
// // final jsonData = jsonDecode(result.body);
// // final temperature = {
// //   'value': jsonData['current_weather']['temperature'],
// //   'units': '°C',
// // };
// // final windSpeed = {
// //   'value': jsonData['current_weather']['windspeed'],
// //   'units': 'km/h',
// // };
// // setState(() {
// //   marker = {
// //     'lat': lat,
// //     'lng': lng,
// //     'location': location,
// //     'temperature': temperature,
// //     'wind_speed': windSpeed,
// //   };
// // });
// // return jsonData;
// return {'ok': true};
// },
// );

Future<bool> addItemsOnAmazonToCart(List<String> items) async {
  String url = 'https://camel-lucky-reliably.ngrok-free.app/buy';
  final response = await http.post(Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(items));
  if (response.statusCode == 200) {
    return jsonDecode(response.body)['message'] == 'Success';
  }
  return false;
}
