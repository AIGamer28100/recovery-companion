import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';

/// Placeholder-only system instruction for this feasibility spike. This is
/// deliberately NOT the production clinical instruction used by
/// `lib/features/live_session/data/gemini_live_repository.dart` -- that file
/// is out of scope and is never imported here. A real on-device deployment
/// would need real clinical prompt engineering; this string exists only to
/// exercise the pipeline end to end.
const String kSpikeSystemInstruction =
    'You are a calm supportive companion. Respond briefly and warmly.';

/// Model identity for the on-device spike: Gemma 4 E2B, instruction-tuned,
/// packaged as a `.litertlm` bundle by the official `litert-community` org
/// on Hugging Face. Verified during this spike (2026-07-26):
///  - Repo: https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
///  - File `gemma-4-E2B-it.litertlm` is 2,588,147,712 bytes (~2.41GB).
///  - Public, unauthenticated download (HTTP 302 redirect to a public CDN
///    URL with no auth challenge) -- unlike Gemma3n/EmbeddingGemma, Gemma 4
///    is NOT a gated model on Hugging Face.
///  - flutter_gemma's own `example/lib/models/model.dart` lists this exact
///    URL with `needsAuth: false`, confirming the above independently.
const String kGemma4E2BModelUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
const String kGemma4E2BFilename = 'gemma-4-E2B-it.litertlm';

/// Thin wrapper around the `flutter_gemma` "Modern API" for this spike:
/// install the model once, then hold a single multimodal chat session that
/// accepts text, audio, or image turns and returns plain text.
///
/// Isolated from `lib/features/live_session/` -- this talks to
/// `flutter_gemma` (on-device LiteRT-LM), never Firebase AI Logic / Gemini
/// Live.
class SpikeGemmaService {
  InferenceModel? _model;
  InferenceChat? _chat;

  bool get isModelLoaded => _chat != null;

  /// Installs the Gemma 4 E2B `.litertlm` bundle from Hugging Face if it
  /// isn't already present on disk, reporting 0-100 progress.
  Future<void> installModelIfNeeded({
    void Function(int percent)? onProgress,
  }) async {
    final alreadyInstalled = await FlutterGemma.isModelInstalled(
      kGemma4E2BFilename,
    );
    if (alreadyInstalled) {
      return;
    }
    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(kGemma4E2BModelUrl).withProgress((progress) {
      onProgress?.call(progress);
    }).install();
  }

  /// Loads the installed model into memory and opens a multimodal chat
  /// session with the spike's placeholder system instruction. Safe to call
  /// repeatedly; it's a no-op once a chat session exists.
  Future<void> ensureChatReady() async {
    if (_chat != null) return;

    _model = await FlutterGemma.getActiveModel(
      maxTokens: 2048,
      preferredBackend: PreferredBackend.gpu,
      supportImage: true,
      supportAudio: true,
    );

    _chat = await _model!.createChat(
      modelType: ModelType.gemma4,
      supportImage: true,
      supportAudio: true,
      systemInstruction: kSpikeSystemInstruction,
      temperature: 0.9,
      topK: 40,
    );
  }

  Future<String> sendText(String text) async {
    final chat = _chat;
    if (chat == null) {
      throw StateError('Call ensureChatReady() before sending messages.');
    }
    await chat.addQueryChunk(Message.text(text: text, isUser: true));
    final response = await chat.generateChatResponse();
    return response is TextResponse ? response.token : '';
  }

  /// Sends a single WAV-encoded audio turn (16kHz mono PCM16, see
  /// `wav_encoder.dart`) and returns the model's text reply.
  Future<String> sendAudio(Uint8List wavBytes) async {
    final chat = _chat;
    if (chat == null) {
      throw StateError('Call ensureChatReady() before sending messages.');
    }
    await chat.addQueryChunk(
      Message.withAudio(text: '', audioBytes: wavBytes, isUser: true),
    );
    final response = await chat.generateChatResponse();
    return response is TextResponse ? response.token : '';
  }

  /// Sends a single camera frame (JPEG/PNG bytes) with a short prompt asking
  /// for a description, and returns the model's text reply.
  Future<String> sendImage(
    Uint8List imageBytes, {
    String prompt = 'Briefly describe what you see in this image.',
  }) async {
    final chat = _chat;
    if (chat == null) {
      throw StateError('Call ensureChatReady() before sending messages.');
    }
    await chat.addQueryChunk(
      Message.withImages(text: prompt, imageBytes: [imageBytes], isUser: true),
    );
    final response = await chat.generateChatResponse();
    return response is TextResponse ? response.token : '';
  }

  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    _chat = null;
  }
}
