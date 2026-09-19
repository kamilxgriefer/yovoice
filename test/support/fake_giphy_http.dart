import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A GIPHY API double for the client-side search path (ADR-213).
///
/// It answers `/v1/gifs/trending`, `/v1/gifs/search` and `/v1/randomid` from
/// fixtures and records every request, so a test can prove what was (and was
/// not) sent to GIPHY. Analytics beacons land in [pings]. Nothing here touches
/// the network, and the "key" a test passes is a placeholder string, never a
/// real credential.
class FakeGiphyHttp {
  FakeGiphyHttp({this.status = 200, List<Map<String, Object?>>? items})
    : items = items ?? defaultItems();

  int status;
  final List<Map<String, Object?>> items;
  final List<Uri> requests = <Uri>[];
  final List<Uri> pings = <Uri>[];
  int randomIdCalls = 0;

  late final http.Client client = MockClient((request) async {
    final url = request.url;
    if (url.host != 'api.giphy.com') {
      pings.add(url);
      return http.Response('', 200);
    }
    requests.add(url);
    if (status != 200) return http.Response('{}', status);
    if (url.path == '/v1/randomid') {
      randomIdCalls += 1;
      return http.Response(
        jsonEncode({
          'data': {'random_id': 'install-random-1'},
        }),
        200,
      );
    }
    final offset = int.tryParse(url.queryParameters['offset'] ?? '') ?? 0;
    return http.Response(
      jsonEncode({
        'data': items,
        'pagination': {
          'offset': offset,
          'count': items.length,
          'total_count': items.length,
        },
      }),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  });

  List<Uri> get searches =>
      requests.where((url) => url.path.startsWith('/v1/gifs/')).toList();

  static Map<String, Object?> item(
    String id, {
    String rating = 'g',
    String title = 'Happy dance GIF',
    String? preview,
  }) => <String, Object?>{
    'id': id,
    'title': title,
    'rating': rating,
    'images': {
      'fixed_height': {
        'url': 'https://media2.giphy.com/media/$id/200h.gif',
        'width': '300',
        'height': '200',
      },
      'fixed_height_small': {
        'url': preview ?? 'https://media2.giphy.com/media/$id/100h.gif',
        'width': '150',
        'height': '100',
      },
    },
    'analytics': {
      'onload': {
        'url':
            'https://giphy-analytics.giphy.com/v2/pingback_simple?p=$id&action_type=SEEN',
      },
      'onclick': {
        'url':
            'https://giphy-analytics.giphy.com/v2/pingback_simple?p=$id&action_type=CLICK',
      },
      'onsent': {
        'url':
            'https://giphy-analytics.giphy.com/v2/pingback_simple?p=$id&action_type=SENT',
      },
    },
  };

  static List<Map<String, Object?>> defaultItems() => <Map<String, Object?>>[
    item('giphyOne01'),
    item('giphyTwo02', title: 'Thumbs up GIF by Someone'),
  ];
}
