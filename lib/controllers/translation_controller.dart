import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as path;
import '../models/translation_progress.dart';
import '../services/ai_service.dart';
import '../services/web_search_service.dart';
import '../utils/text_processor.dart';

class TranslationController {
  final AIService _aiService = AIService();
  final WebSearchService _webSearchService = WebSearchService();

  /// Processes the file with resume capability.
  /// [onUpdate] callback returns status message and progress (0.0 to 1.0).
  Future<void> processFile({
    required String filePath,
    required String outputDir,
    required String dictionaryDir,
    required Function(String status, double progress) onUpdate,
  }) async {
    final String progressPath = "$filePath.flux_progress.json";
    TranslationProgress? progress =
        await TranslationProgress.loadFromFile(progressPath);

    // --- 1. INITIALIZATION OR RESUME ---
    if (progress != null) {
      onUpdate("Đã tìm thấy bản lưu cũ. Đang khôi phục tiến độ...", 0.0);
      await Future.delayed(Duration(seconds: 1)); // UX delay
    } else {
      onUpdate("Đang đọc file gốc...", 0.0);
      final File file = File(filePath);
      if (!await file.exists())
        throw Exception("File không tồn tại: $filePath");

      final String content = await file.readAsString();
      final String fileName = path.basenameWithoutExtension(filePath);

      onUpdate("Đang phân tích và chia nhỏ văn bản...", 0.1);
      final List<String> chunks = TextProcessor.smartSplit(content);
      final String sample = TextProcessor.createSample(content);

      onUpdate("AI đang đọc thử để xác định thể loại...", 0.2);
      final String systemPrompt = await _aiService.detectGenre(sample);

      onUpdate("AI đang tạo từ điển tên riêng...", 0.3);
      final String glossaryCsv = await _aiService.generateGlossary(sample);

      // Smart Merge: Merge AI glossary with existing user CSV
      final glossaryFile =
          File(path.join(dictionaryDir, "${fileName}_glossary.csv"));

      try {
        final String mergedCsv = await _smartMergeGlossary(
          aiGeneratedCsv: glossaryCsv,
          existingFile: glossaryFile,
        );

        // Save merged glossary as CSV
        await glossaryFile.writeAsString(mergedCsv);
      } catch (e) {
        print("Error saving glossary: $e");
        // Non-critical error, continue
      }

      // Enrich Glossary: Lookup definitions
      onUpdate("Đang tra cứu thuật ngữ (RAG)...", 0.35);
      final String enrichedGlossaryCsv = await _enrichGlossary(
        glossaryFile: glossaryFile,
        onUpdate: onUpdate,
      );

      // Prepare glossary for translation (Pass CSV directly to AIService)
      final String glossary = enrichedGlossaryCsv;

      // Create output path in outputDir
      final String ext = path.extension(filePath);
      final String outputPath =
          path.join(outputDir, "${fileName}_translated$ext");

      progress = TranslationProgress(
        sourcePath: filePath,
        outputPath: outputPath,
        glossary: glossary,
        systemPrompt: systemPrompt,
        rawChunks: chunks,
        translatedChunks: List<String?>.filled(chunks.length, null),
        currentIndex: 0,
        lastUpdated: DateTime.now(),
      );

      await progress.saveToFile(progressPath);
    }

    // --- 2. TRANSLATION LOOP ---
    final int total = progress.rawChunks.length;

    for (int i = progress.currentIndex; i < total; i++) {
      final double percent = (i / total);
      onUpdate("Đang dịch đoạn ${i + 1}/$total...", percent);

      try {
        final String chunk = progress.rawChunks[i];
        final String translated = await _aiService.translateChunk(
            chunk, progress.systemPrompt, progress.glossary);

        progress.translatedChunks[i] = translated;
        progress.currentIndex = i + 1;

        // CRITICAL: Save after every chunk
        await progress.saveToFile(progressPath);
      } catch (e) {
        onUpdate("Lỗi khi dịch đoạn ${i + 1}: $e. Đang thử lại...", percent);
        // Simple retry logic: decrement i to retry this chunk next loop
        // Or just throw to stop and let user resume later.
        // For now, let's throw so the loop stops and user can resume.
        throw Exception("Lỗi dịch thuật tại đoạn ${i + 1}: $e");
      }
    }

    // --- 3. FINALIZE ---
    onUpdate("Đang ghép file kết quả...", 1.0);
    final StringBuffer finalContent = StringBuffer();
    for (final chunk in progress.translatedChunks) {
      if (chunk != null) {
        finalContent.write(chunk);
        finalContent.write("\n\n");
      }
    }

    final File outFile = File(progress.outputPath);
    await outFile.writeAsString(finalContent.toString());

    // Cleanup progress file
    final File progressFile = File(progressPath);
    if (await progressFile.exists()) {
      await progressFile.delete();
    }

    onUpdate("Hoàn tất! File đã lưu tại: ${progress.outputPath}", 1.0);
  }

  /// Smart Merge: Merges AI-generated CSV with existing user CSV
  /// Keeps user edits, adds new AI entries
  Future<String> _smartMergeGlossary({
    required String aiGeneratedCsv,
    required File existingFile,
  }) async {
    // Parse AI-generated CSV
    final List<List<dynamic>> aiRows = const CsvToListConverter().convert(
      aiGeneratedCsv,
      eol: '\n',
      shouldParseNumbers: false,
    );

    // Create a map from AI data: Original Name -> Vietnamese Name
    final Map<String, String> aiMap = {};
    for (final row in aiRows) {
      if (row.length >= 2) {
        final original = row[0].toString().trim();
        final vietnamese = row[1].toString().trim();
        if (original.isNotEmpty) {
          aiMap[original] = vietnamese;
        }
      }
    }

    // If existing file exists, load and preserve user edits
    if (await existingFile.exists()) {
      final String existingContent = await existingFile.readAsString();
      final List<List<dynamic>> existingRows =
          const CsvToListConverter().convert(
        existingContent,
        eol: '\n',
        shouldParseNumbers: false,
      );

      // User edits take priority
      final Map<String, String> userMap = {};
      for (final row in existingRows) {
        if (row.length >= 2) {
          final original = row[0].toString().trim();
          final vietnamese = row[1].toString().trim();
          if (original.isNotEmpty) {
            userMap[original] = vietnamese;
          }
        }
      }

      // Merge: User edits + New AI entries
      final Map<String, String> mergedMap = {...aiMap};
      mergedMap.addAll(userMap); // User edits override AI

      // Convert back to CSV
      final List<List<String>> csvData =
          mergedMap.entries.map((e) => [e.key, e.value]).toList();

      return const ListToCsvConverter().convert(csvData, eol: '\n');
    } else {
      // No existing file, use AI-generated CSV as-is
      final List<List<String>> csvData =
          aiMap.entries.map((e) => [e.key, e.value]).toList();

      return const ListToCsvConverter().convert(csvData, eol: '\n');
    }
  }

  /// Enriches the glossary by looking up definitions for terms
  Future<String> _enrichGlossary({
    required File glossaryFile,
    required Function(String, double) onUpdate,
  }) async {
    if (!await glossaryFile.exists()) return "";

    final String content = await glossaryFile.readAsString();
    List<List<dynamic>> rows = const CsvToListConverter().convert(
      content,
      eol: '\n',
      shouldParseNumbers: false,
    );

    bool isModified = false;
    final int totalRows = rows.length;

    for (int i = 0; i < totalRows; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      // Ensure row has at least 3 columns
      while (row.length < 3) {
        row.add(""); // Add empty definition
        isModified = true;
      }

      final String original = row[0].toString().trim();
      // final String vietnamese = row[1].toString().trim();
      String definition = row[2].toString().trim();

      // If definition is empty, lookup
      if (definition.isEmpty && original.isNotEmpty) {
        onUpdate("Đang tra cứu: $original...", 0.35 + (0.05 * (i / totalRows)));

        final String? result = await _webSearchService.lookupTerm(original);
        if (result != null) {
          row[2] = result;
          isModified = true;
        }

        // Delay to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    final String newCsv = const ListToCsvConverter().convert(rows, eol: '\n');

    if (isModified) {
      await glossaryFile.writeAsString(newCsv);
    }

    return newCsv;
  }
}
