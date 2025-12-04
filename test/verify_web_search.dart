import 'package:flux_origin/services/web_search_service.dart';

void main() async {
  final service = WebSearchService();

  print('--- Testing WebSearchService ---');

  // Test 1: English Lookup
  print('\nTest 1: Lookup "Apple" in English (en)');
  final resultEn = await service.lookupTerm('Apple', 'en');
  print(
      'Result (EN): ${resultEn != null ? "${resultEn.substring(0, 100)}..." : "null"}');

  // Test 2: Vietnamese Lookup
  print('\nTest 2: Lookup "Táo" in Vietnamese (vi)');
  final resultVi = await service.lookupTerm('Táo', 'vi');
  print(
      'Result (VI): ${resultVi != null ? "${resultVi.substring(0, 100)}..." : "null"}');

  // Test 3: Chinese Lookup (if possible)
  print('\nTest 3: Lookup "苹果" in Chinese (zh)');
  final resultZh = await service.lookupTerm('苹果', 'zh');
  print(
      'Result (ZH): ${resultZh != null ? "${resultZh.substring(0, 100)}..." : "null"}');

  print('\n--- Verification Complete ---');
}
