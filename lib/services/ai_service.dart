import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

class AIService {
  static const String _baseUrl = 'http://127.0.0.1:11434/api/chat';
  static const String _model = 'qwen2.5:7b'; // Default model, can be changed

  static const Map<String, String> _prompts = {
    "KIEMHIEP":
        "Bạn là dịch giả kiếm hiệp lão luyện. Dùng từ Hán Việt (huynh, đệ, tại hạ...), văn phong hào hùng, cổ trang. Chiêu thức giữ nguyên âm Hán Việt.",
    "NGONTINH":
        "Bạn là dịch giả ngôn tình. Văn phong lãng mạn, nhẹ nhàng, ướt át. Xưng hô Anh - Em hoặc Chàng - Nàng tùy ngữ cảnh.",
    "KINHDOANH":
        "Bạn là chuyên gia kinh tế. Dịch văn phong trang trọng, chuyên nghiệp, dùng thuật ngữ chính xác.",
    "KHAC":
        "Bạn là một dịch giả chuyên nghiệp. Hãy dịch trôi chảy, tự nhiên, sát nghĩa gốc."
  };

  Future<String> detectGenre(String sample) async {
    final response = await _chatCompletion(
      messages: [
        {
          "role": "user",
          "content":
              "Bạn là một trợ lý phân loại văn học.\nHãy đọc đoạn văn bản mẫu dưới đây và xác định thể loại chính của nó.\nChỉ trả về DUY NHẤT một từ khóa trong danh sách sau: [KIEMHIEP, NGONTINH, KINHDOANH, KHOAHOC, KHAC].\nTuyệt đối không giải thích gì thêm.\n\nVăn bản mẫu:\n$sample"
        }
      ],
    );

    final genre = response.trim().toUpperCase();
    // Basic validation to ensure we got a valid key, otherwise default to KHAC
    if (_prompts.containsKey(genre)) {
      return _prompts[genre]!;
    }
    // Try to find the keyword if the AI was chatty
    for (final key in _prompts.keys) {
      if (genre.contains(key)) {
        return _prompts[key]!;
      }
    }
    return _prompts["KHAC"]!;
  }

  Future<String> generateGlossary(String sample) async {
    final response = await _chatCompletion(messages: [
      {
        "role": "user",
        "content":
            "Hãy phân tích đoạn văn sau và liệt kê các Tên Riêng (Nhân vật, Địa danh, Môn phái, Chiêu thức) quan trọng nhất để làm Từ Điển dịch thuật.\n\nĐịnh dạng trả về: CSV (Original Name,Vietnamese Name)\nTuyệt đối KHÔNG thêm Header.\nNếu tên có dấu phẩy hoặc ký tự đặc biệt, hãy đặt trong dấu ngoặc kép.\n\nVí dụ:\nHarry Potter,Harry Potter\n\"Robert, Jr.\",Robert Con\nAzure Dragon Sect,Thanh Long Môn\nLi Feng,Lý Phong\n\nTuyệt đối không giải thích gì thêm.\n\nNội dung:\n$sample"
      }
    ], options: {
      "num_predict": 3000
    });
    return response.trim();
  }

  Future<String> translateChunk(
      String chunk, String systemPrompt, String glossaryCsv) async {
    // Parse CSV to formatted string
    String formattedGlossary = "";
    try {
      final List<List<dynamic>> rows = const CsvToListConverter().convert(
        glossaryCsv,
        eol: '\n',
        shouldParseNumbers: false,
      );

      final StringBuffer buffer = StringBuffer();
      for (final row in rows) {
        if (row.length >= 2) {
          final original = row[0].toString().trim();
          final vietnamese = row[1].toString().trim();
          final definition = row.length > 2 ? row[2].toString().trim() : "";

          if (original.isNotEmpty && vietnamese.isNotEmpty) {
            buffer.write("- Term: $original\n");
            buffer.write("  Vietnamese: $vietnamese\n");
            if (definition.isNotEmpty) {
              buffer.write("  Context/Definition: $definition\n");
            }
          }
        }
      }
      formattedGlossary = buffer.toString().trim();
    } catch (e) {
      formattedGlossary = glossaryCsv; // Fallback
    }

    final fullSystemPrompt =
        "$systemPrompt\n\n### BẮT BUỘC TUÂN THỦ TỪ ĐIỂN (GLOSSARY):\n$formattedGlossary\n\n### YÊU CẦU DỊCH THUẬT NÂNG CAO:\n1. Dịch CHI TIẾT từng câu, tuyệt đối KHÔNG được tóm tắt hay bỏ sót ý.\n2. Giữ nguyên sắc thái biểu cảm, các thán từ, mô tả nội tâm của nhân vật.\n3. Nếu gặp thơ ca hoặc câu đối, hãy dịch sao cho vần điệu hoặc giữ nguyên Hán Việt nếu cần.\n4. Văn phong phải trôi chảy, tự nhiên như người bản xứ viết.";

    return await _chatCompletion(messages: [
      {"role": "system", "content": fullSystemPrompt},
      {
        "role": "user",
        "content": "Dịch đoạn văn bản sau sang tiếng Việt:\n\n$chunk"
      }
    ], options: {
      "timeout":
          28800000 // 8 hours, though http client timeout handles this mostly
    });
  }

  Future<String> _chatCompletion(
      {required List<Map<String, String>> messages,
      Map<String, dynamic>? options}) async {
    try {
      final body = {
        "model": _model,
        "messages": messages,
        "stream": false,
        if (options != null) "options": options,
      };

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        return json['message']['content'] ?? "";
      } else {
        throw Exception(
            "Ollama API Error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      throw Exception("Failed to connect to Ollama: $e");
    }
  }

  Future<List<String>> getInstalledModels() async {
    try {
      final response =
          await http.get(Uri.parse('http://127.0.0.1:11434/api/tags'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> models = data['models'];
        return models.map<String>((m) => m['name'] as String).toList();
      } else {
        print('Failed to load models: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error getting installed models: $e');
      return [];
    }
  }

  Future<bool> pullModel(
      String modelName, Function(double progress) onProgress) async {
    try {
      final request =
          http.Request('POST', Uri.parse('http://127.0.0.1:11434/api/pull'));
      request.body = jsonEncode({"name": modelName, "stream": true});
      request.headers.addAll({"Content-Type": "application/json"});

      final response = await request.send();

      if (response.statusCode == 200) {
        await response.stream.transform(utf8.decoder).listen((chunk) {
          // Ollama sends multiple JSON objects in one chunk sometimes, or split across chunks
          // We need to handle this robustly. For now, simple line splitting.
          final lines =
              chunk.split('\n').where((line) => line.trim().isNotEmpty);
          for (final line in lines) {
            try {
              final data = jsonDecode(line);
              if (data.containsKey('completed') && data.containsKey('total')) {
                final completed = data['completed'];
                final total = data['total'];
                if (total > 0) {
                  onProgress(completed / total);
                }
              } else if (data['status'] == 'success') {
                onProgress(1.0);
              }
            } catch (e) {
              // Ignore parse errors for partial chunks
            }
          }
        }).asFuture();
        return true;
      } else {
        print('Failed to pull model: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error pulling model: $e');
      return false;
    }
  }
}
