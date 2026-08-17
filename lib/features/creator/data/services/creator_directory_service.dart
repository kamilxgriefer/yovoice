import 'package:cloud_functions/cloud_functions.dart';

import 'package:yovoice/features/creator/data/models/creator_search_result.dart';

typedef CreatorSearchInvoker =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data);

class CreatorDirectoryService {
  CreatorDirectoryService({
    FirebaseFunctions? functions,
    CreatorSearchInvoker? searchInvoker,
  }) : _functionsOverride = functions,
       _searchInvoker = searchInvoker;

  final FirebaseFunctions? _functionsOverride;
  final CreatorSearchInvoker? _searchInvoker;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<List<CreatorSearchResult>> searchCreators(
    String query, {
    int limit = 20,
    Set<CreatorDirectoryAccountType> accountTypes = const {
      CreatorDirectoryAccountType.creator,
      CreatorDirectoryAccountType.official,
    },
  }) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const <CreatorSearchResult>[];

    final payload = <String, dynamic>{
      'query': normalized,
      'limit': limit.clamp(1, 20),
      'accountTypes': accountTypes.map((type) => type.name).toList(),
    };

    try {
      final injected = _searchInvoker;
      final response = injected != null
          ? await injected(payload)
          : Map<String, dynamic>.from(
              (await _functions
                          .httpsCallable('searchPublicProfiles')
                          .call(payload))
                      .data
                  as Map,
            );
      return (response['profiles'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) {
            try {
              return CreatorSearchResult.fromMap(
                Map<String, dynamic>.from(item),
              );
            } on FormatException {
              return null;
            }
          })
          .whereType<CreatorSearchResult>()
          .toList(growable: false);
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'Creator search is unavailable.');
    }
  }
}
