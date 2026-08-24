import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// CLAUDE AI THEME PALETTE
// ============================================================================
const Color clBg = Color(0xFF1B1A17);
const Color clSidebar = Color(0xFF22211C);
const Color clSurface = Color(0xFF2B2923);
const Color clSurfaceHover = Color(0xFF343129);
const Color clBorder = Color(0xFF3D3A31);
const Color clAccent = Color(0xFFD97757);
const Color clTextMain = Color(0xFFF4F0E8);
const Color clTextMuted = Color(0xFFA5A096);
const Color clTextDim = Color(0xFF706C62);
const Color clUserBubble = Color(0xFF2E2C25);

// --- GLOBALS ---
Process? backendProcess;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appDir = File(Platform.resolvedExecutable).parent.path;

  try {
    // String backendPath = r"backend-ai\main.py";
    String backendPath = '$appDir\\student_backend\\student_backend.exe';

    // Launch backend
    backendProcess = await Process.start(backendPath, []);
    debugPrint(
      "Backend started from: $backendPath (PID: ${backendProcess?.pid})",
    );

    // ==========================================
    // LISTEN TO PYTHON ERRORS AND LOGS
    // ==========================================
    backendProcess?.stdout.transform(utf8.decoder).listen((data) {
      debugPrint("PYTHON LOG: $data");
    });

    backendProcess?.stderr.transform(utf8.decoder).listen((data) {
      debugPrint(
        "PYTHON ERROR: $data",
      ); // This will show you exactly why it crashes!
    });
  } catch (e) {
    debugPrint("Failed to start backend: $e");
  }

  // Initialize Window Manager
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 840),
    minimumSize: Size(960, 640),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const StudentAIApp());
}

// ============================================================================
// DATA MODELS (WITH JSON SERIALIZATION FOR LOCAL SAVING)
// ============================================================================
class SourceSnippet {
  final String source;
  final String text;
  SourceSnippet({required this.source, required this.text});

  Map<String, dynamic> toJson() => {'source': source, 'text': text};
  factory SourceSnippet.fromJson(Map<String, dynamic> json) => SourceSnippet(
    source: json['source'] ?? 'Unknown Document',
    text: json['text'] ?? '',
  );
}

class Message {
  final String role;
  final String text;
  final List<SourceSnippet> sources;

  Message({required this.role, required this.text, this.sources = const []});

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'sources': sources.map((s) => s.toJson()).toList(),
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    role: json['role'],
    text: json['text'],
    sources:
        (json['sources'] as List?)
            ?.map((s) => SourceSnippet.fromJson(s))
            .toList() ??
        [],
  );
}

class ChatSession {
  final String id;
  String title;
  bool isCustomNamed;
  List<String> documents;
  List<Message> messages;

  ChatSession({
    required this.id,
    required this.title,
    this.isCustomNamed = false,
    List<String>? documents,
    List<Message>? messages,
  }) : documents = documents != null ? List<String>.from(documents) : [],
       messages = messages != null ? List<Message>.from(messages) : [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isCustomNamed': isCustomNamed,
    'documents': documents,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'],
    title: json['title'],
    isCustomNamed: json['isCustomNamed'] ?? false,
    documents: json['documents'] != null
        ? List<String>.from(json['documents'])
        : [],
    messages:
        (json['messages'] as List?)?.map((m) => Message.fromJson(m)).toList() ??
        [],
  );
}

class VectorPoint {
  final double x, y, z;
  final String source, snippet;
  VectorPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.source,
    required this.snippet,
  });
  factory VectorPoint.fromJson(Map<String, dynamic> json) => VectorPoint(
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    z: (json['z'] as num).toDouble(),
    source: json['source'] ?? 'Unknown',
    snippet: json['snippet'] ?? '',
  );
}

// ============================================================================
// APP ROOT
// ============================================================================
class StudentAIApp extends StatelessWidget {
  const StudentAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student RAG Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: clBg,
        cardColor: clSidebar,
        dividerColor: clBorder,
        textTheme: GoogleFonts.spaceGroteskTextTheme(
          ThemeData.dark().textTheme,
        ).apply(bodyColor: clTextMain, displayColor: clTextMain),
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: Color(0xFF4A463B),
          cursorColor: clAccent,
          selectionHandleColor: clAccent,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ============================================================================
// 1. ANIMATED SPLASH SCREEN (NOW WITH CUSTOM LOGO)
// ============================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));
    _scaleAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();

    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const DashboardScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 700),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: clBg,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // CUSTOM LOGO RENDERED HERE
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: clSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: clBorder),
                    boxShadow: [
                      BoxShadow(
                        color: clAccent.withOpacity(0.18),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Image.asset('assets/logo.png', width: 64, height: 64),
                ),
                const SizedBox(height: 28),
                Text(
                  "StudentRAG",
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: clTextMain,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Local Knowledge Intelligence & Document RAG",
                  style: TextStyle(
                    fontSize: 14,
                    color: clTextMuted,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 2. MAIN DASHBOARD SCREEN
// ============================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this); // 2. Start listening
    _loadSavedChats();
    _fetchOllamaModels();
  }

  @override
  void dispose() {
    windowManager.removeListener(this); // 3. Stop listening
    super.dispose();
  }

  // 4. Override the native close event
  @override
  void onWindowClose() {
    backendProcess?.kill(); // Kill the server
    super.onWindowClose();
  }

  List<ChatSession> chats = [];
  late String activeChatId;
  bool isAppLoaded = false;

  final TextEditingController _msgController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController =
      ScrollController(); // AUTO-SCROLL CONTROLLER
  String _searchQuery = "";

  bool isTyping = false;
  bool isUploading = false;
  bool isSidebarVisible = true; // NEW: Tracks sidebar state

  // double _sidebarWidth = 270.0;
  // bool _isDraggingSidebar = false;

  List<String> availableModels = [];
  String? selectedModel;
  bool isLoadingModels = true;

  // --- PRE-BUILT SUGGESTIONS ---
  final List<String> _suggestions = [
    "Summarize the attached documents",
    "Explain the core concepts simply",
    "Extract the key dates and formulas",
    "Generate practice study questions",
    "Compare the main arguments",
    "Find definitions for key terms",
    "Format the main points into a table",
    "Check the document for limitations",
  ];
  //------------------------------------------------------------------------------------------------------
  //------------------------------------------------------------------------------------------------------
  //------------------------------------------------------------------------------------------------------
  Future<void> _generateAITitle(
    ChatSession session,
    String firstMessage,
  ) async {
    if (selectedModel == null || selectedModel == 'Ollama not running') return;

    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:11434/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': selectedModel,
          'prompt':
              'Generate a concise 3 to 5 word title for a conversation that begins with this question: "$firstMessage". Return ONLY the title with no quotation marks, labels, or extra text.',
          'stream': false,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String generatedTitle = (data['response'] as String? ?? '').trim();
        generatedTitle = generatedTitle
            .replaceAll('"', '')
            .replaceAll('\n', ' ');

        if (generatedTitle.isNotEmpty && mounted) {
          setState(() {
            session.title = generatedTitle;
            session.isCustomNamed = true;
          });
          _saveChats();
        }
      }
    } catch (e) {
      debugPrint("Failed to generate AI title: $e");
    }
  }

  // --- LOCAL PERSISTENCE LOGIC ---
  Future<void> _loadSavedChats() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedData = prefs.getString('saved_chats');

    if (savedData != null) {
      final List<dynamic> decoded = jsonDecode(savedData);
      chats = decoded.map((c) => ChatSession.fromJson(c)).toList();
    }

    // ALWAYS start with a fresh chat on app open to show the Welcome Screen
    _createNewChat(save: false);

    setState(() => isAppLoaded = true);
    _scrollToBottom();
  }

  Future<void> _saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(chats.map((c) => c.toJson()).toList());
    await prefs.setString('saved_chats', encoded);
    await prefs.setString('active_chat_id', activeChatId);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- API: FETCH OLLAMA MODELS ---
  Future<void> _fetchOllamaModels() async {
    // 1. Reset state so the UI shows "Scanning models..." again
    setState(() => isLoadingModels = true);

    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:11434/api/tags'),
      );
      if (response.statusCode == 200) {
        setState(() {
          availableModels = (jsonDecode(response.body)['models'] as List)
              .map((m) => m['name'].toString())
              .toList();

          // Ensure we don't overwrite the selected model if it still exists
          if (availableModels.isNotEmpty &&
              !availableModels.contains(selectedModel)) {
            selectedModel = availableModels.first;
          } else if (availableModels.isNotEmpty &&
              selectedModel == 'Ollama not running') {
            selectedModel = availableModels.first;
          }

          isLoadingModels = false;
        });
      }
    } catch (e) {
      setState(() {
        availableModels = ['Ollama not running'];
        selectedModel = 'Ollama not running';
        isLoadingModels = false;
      });
    }
  }
  // // --- API: FETCH OLLAMA MODELS ---
  // Future<void> _fetchOllamaModels() async {
  //   try {
  //     final response = await http.get(
  //       Uri.parse('http://127.0.0.1:11434/api/tags'),
  //     );
  //     if (response.statusCode == 200) {
  //       setState(() {
  //         availableModels = (jsonDecode(response.body)['models'] as List)
  //             .map((m) => m['name'].toString())
  //             .toList();
  //         if (availableModels.isNotEmpty) selectedModel = availableModels.first;
  //         isLoadingModels = false;
  //       });
  //     }
  //   } catch (e) {
  //     setState(() {
  //       availableModels = ['Ollama not running'];
  //       selectedModel = 'Ollama not running';
  //       isLoadingModels = false;
  //     });
  //   }
  // }

  String _generateId() => "chat_${math.Random().nextInt(1000000)}";

  void _createNewChat({bool save = true}) {
    final newChat = ChatSession(
      id: _generateId(),
      title: 'New Conversation',
      messages: [
        Message(
          role: 'system',
          text: 'How can I assist your study session today?',
        ),
      ],
    );
    setState(() {
      chats.insert(0, newChat);
      activeChatId = newChat.id;
    });
    if (save) _saveChats();
  }

  ChatSession get activeChat => chats.firstWhere((c) => c.id == activeChatId);

  String _formatDocTitle(String fileName) => fileName
      .replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')
      .replaceAll(RegExp(r'[_-]'), ' ')
      .trim();

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "Copied to clipboard!",
          style: TextStyle(color: Color(0xFFF4F0E8)),
        ),
        backgroundColor: clSurface,
        behavior: SnackBarBehavior.floating,
        width: 180,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: clBorder),
        ),
      ),
    );
  }

  void _clearMemory() {
    setState(() {
      activeChat.messages.removeWhere((m) => m.role != 'system');
      activeChat.messages.add(
        Message(
          role: 'system',
          text: 'Memory cleared. Context window refreshed.',
        ),
      );
    });
    _saveChats();
  }

  Future<void> _exportChat() async {
    String content =
        "# ${activeChat.title}\n\n*Exported from StudentRAG Assistant*\n\n---\n\n";
    for (var msg in activeChat.messages) {
      if (msg.role == 'system') continue;
      content +=
          "${msg.role == 'user' ? '### 👤 You' : '### 🤖 StudentRAG'}\n\n${msg.text}\n\n";
      if (msg.sources.isNotEmpty) {
        content += "> **Sources Cited:**\n";
        for (var s in msg.sources)
          content += "> - *${s.source}*: \"${s.text.replaceAll('\n', ' ')}\"\n";
        content += "\n";
      }
    }
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export MD',
        fileName:
            '${activeChat.title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.md',
        type: FileType.custom,
        allowedExtensions: ['md'],
      );
      if (outputFile != null) {
        await File(outputFile).writeAsString(content);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                "Chat exported!",
                style: TextStyle(color: Color(0xFFF4F0E8)),
              ),
              backgroundColor: clSurface,
            ),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Export failed: $e")));
    }
  }

  void _showRenameDialog(ChatSession chat) {
    final renameController = TextEditingController(text: chat.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: clSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: clBorder),
        ),
        title: const Text(
          "Rename Conversation",
          style: TextStyle(color: clTextMain, fontSize: 16),
        ),
        content: TextField(
          controller: renameController,
          autofocus: true,
          style: const TextStyle(color: clTextMain),
          decoration: const InputDecoration(
            hintText: "Enter title...",
            hintStyle: TextStyle(color: clTextDim),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(
                //-------------------------------------------------
                Radius.circular(10),
              ), //-------------------------------------------------
              borderSide: BorderSide(color: clAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: clTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: clAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (renameController.text.trim().isNotEmpty)
                setState(() {
                  chat.title = renameController.text.trim();
                  chat.isCustomNamed = true;
                });
              _saveChats();
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _deleteChat(ChatSession chat) {
    if (chats.length <= 1) {
      _createNewChat();
      setState(() => chats.remove(chat));
    } else {
      setState(() {
        int index = chats.indexOf(chat);
        chats.remove(chat);
        if (activeChatId == chat.id)
          activeChatId = chats[math.max(0, index - 1)].id;
      });
    }
    _saveChats();
  }

  Future<void> _openVectorGraph() async {
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8008/visualize/${activeChat.id}'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> pointsList =
            jsonDecode(response.body)['points'] ?? [];
        final points = pointsList.map((p) => VectorPoint.fromJson(p)).toList();
        if (!mounted) return;
        if (points.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                "No vectors found! Upload a document first.",
                style: TextStyle(color: Color(0xFFF4F0E8)),
              ),
              backgroundColor: clSurface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: clBorder),
              ),
            ),
          );
          return;
        }
        showDialog(
          context: context,
          builder: (context) =>
              VectorGraphDialog(points: points, chatTitle: activeChat.title),
        );
      }
    } catch (e) {
      String errorMsg = "Failed to load graph: $e";
      // Check if the error is because the backend hasn't finished booting yet
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection refused')) {
        errorMsg =
            "⏳ The AI backend is still warming up. Please wait a few seconds and try again.";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg, style: const TextStyle(color: clBg)),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _uploadDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'pptx', 'txt', 'md'],
      allowMultiple: true,
    );
    if (result == null) return;
    setState(() => isUploading = true);
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:8008/upload'),
      )..fields['chat_id'] = activeChat.id;
      for (var file in result.files) {
        if (file.bytes != null)
          request.files.add(
            http.MultipartFile.fromBytes(
              'files',
              file.bytes!,
              filename: file.name,
            ),
          );
        else if (file.path != null)
          request.files.add(
            await http.MultipartFile.fromPath('files', file.path!),
          );
      }
      var response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 200) {
        setState(() {
          for (var file in result.files) {
            if (!activeChat.documents.contains(file.name)) {
              activeChat.documents.add(file.name);
            }
          }
        });
        _saveChats();
      }
    } finally {
      setState(() => isUploading = false);
    }
  }

  Future<void> _removeDocument(String filename) async {
    setState(() => activeChat.documents.remove(filename));
    _saveChats();
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8008/remove_document'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chat_id': activeChat.id, 'filename': filename}),
      );
      if (response.statusCode != 200) {
        setState(() => activeChat.documents.add(filename));
        _saveChats();
      }
    } catch (e) {
      setState(() => activeChat.documents.add(filename));
      _saveChats();
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final bool shouldGenerateTitle = !activeChat.isCustomNamed;

    List<Map<String, String>> historyPayload = activeChat.messages
        .where((m) => m.role != 'system')
        .map(
          (m) => {"role": m.role == 'user' ? 'human' : 'ai', "content": m.text},
        )
        .toList();
    _msgController.clear();
    setState(() {
      activeChat.messages.add(Message(role: 'user', text: text));
      if (shouldGenerateTitle) {
        activeChat.title = text.length > 25
            ? "${text.substring(0, 22)}..."
            : text;
      }
      isTyping = true;
    });
    _saveChats();
    _scrollToBottom();

    if (shouldGenerateTitle) {
      _generateAITitle(activeChat, text);
    }
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8008/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query': text,
          'chat_id': activeChat.id,
          'chat_history': historyPayload,
          'model': selectedModel,
          'attached_files': activeChat.documents,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<SourceSnippet> retrievedSources =
            (data['sources'] as List<dynamic>?)
                ?.map((s) => SourceSnippet.fromJson(s))
                .toList() ??
            [];
        setState(
          () => activeChat.messages.add(
            Message(
              role: 'ai',
              text: data['answer'] ?? "No response",
              sources: retrievedSources,
            ),
          ),
        );
      } else {
        setState(
          () => activeChat.messages.add(
            Message(role: 'ai', text: '⚠️ Error from backend server.'),
          ),
        );
      }
    } catch (e) {
      String fallbackText = '⚠️ Could not connect to Python backend.';
      // Friendly message if they chat too fast
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection refused')) {
        fallbackText =
            '⏳ The AI backend is still warming up. Please wait a few seconds and try sending again.';
      }

      setState(
        () => activeChat.messages.add(Message(role: 'ai', text: fallbackText)),
      );
    } finally {
      setState(() => isTyping = false);
      _saveChats();
      _scrollToBottom(); // Scroll when AI replies
    }
  }

  @override
  // --- WELCOME SCREEN UI ---
  Widget _buildWelcomeScreen() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: clSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: clBorder),
                  boxShadow: [
                    BoxShadow(
                      color: clAccent.withOpacity(0.1),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Image.asset('assets/logo.png', width: 48, height: 48),
              ),
              const SizedBox(height: 24),
              Text(
                "What can I help you with?",
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: clTextMain,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: _suggestions.map((prompt) {
                  return InkWell(
                    onTap: () {
                      _msgController.text = prompt;
                      _sendMessage(); // Instantly trigger the message!
                    },
                    borderRadius: BorderRadius.circular(12),
                    hoverColor: clSurfaceHover,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: clSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: clBorder),
                      ),
                      child: Text(
                        prompt,
                        style: const TextStyle(
                          color: clTextMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget build(BuildContext context) {
    if (!isAppLoaded)
      return const Scaffold(
        backgroundColor: clBg,
        body: Center(child: CircularProgressIndicator(color: clAccent)),
      );

    final filteredChats = chats
        .where(
          (c) => c.title.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    return Scaffold(
      backgroundColor: clBg,
      body: Column(
        children: [
          // ==================================================================
          // TITLE BAR WITH CUSTOM LOGO
          // ==================================================================
          GestureDetector(
            onPanStart: (details) => windowManager.startDragging(),
            child: Container(
              height: 52,
              decoration: const BoxDecoration(
                color: clSidebar,
                border: Border(bottom: BorderSide(color: clBorder, width: 1)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 270,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          // ==========================================
                          // NEW: Sidebar Toggle Button
                          // ==========================================
                          IconButton(
                            icon: const Icon(
                              Icons.menu,
                              color: clTextMuted,
                              size: 18,
                            ),
                            splashRadius: 16,
                            onPressed: () {
                              setState(
                                () => isSidebarVisible = !isSidebarVisible,
                              );
                            },
                          ),
                          const SizedBox(width: 4),

                          // CUSTOM LOGO RENDERED HERE
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: clSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: clBorder),
                            ),
                            child: Image.asset(
                              'assets/logo.png',
                              width: 18,
                              height: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "StudentRAG",
                            style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: clTextMain,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            activeChat.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: clTextMain,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Builder(
                          builder: (context) {
                            double fillRatio =
                                (activeChat.messages.fold(
                                          0,
                                          (sum, m) => sum + m.text.length,
                                        ) /
                                        32000.0)
                                    .clamp(0.0, 1.0);
                            Color meterColor = fillRatio > 0.85
                                ? Colors.redAccent
                                : fillRatio > 0.6
                                ? Colors.orangeAccent
                                : clTextMuted;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: clSurface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: clBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 60,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: fillRatio,
                                        backgroundColor: clBorder,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              meterColor,
                                            ),
                                        minHeight: 3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "${(fillRatio * 100).toInt()}% load",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: meterColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.download_outlined,
                      color: clTextMuted,
                      size: 18,
                    ),
                    tooltip: "Export MD",
                    onPressed: _exportChat,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.cleaning_services_outlined,
                      color: clTextMuted,
                      size: 18,
                    ),
                    tooltip: "Clear Memory",
                    onPressed: _clearMemory,
                  ),
                  const SizedBox(width: 4),
                  // ==========================================
                  // STYLED CLAUDE MODEL SELECTOR DROPDOWN
                  // ==========================================
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: clSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: clBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedModel,
                        dropdownColor: clSidebar,
                        borderRadius: BorderRadius.circular(
                          10,
                        ), // Rounds the popup menu corners
                        elevation: 6,
                        icon: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: clTextMuted,
                          ),
                        ),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: clTextMain,
                        ),
                        onChanged:
                            (isLoadingModels ||
                                availableModels.contains('Ollama not running'))
                            ? null
                            : (String? v) {
                                if (v != null)
                                  setState(() => selectedModel = v);
                              },
                        items: availableModels.map<DropdownMenuItem<String>>((
                          String v,
                        ) {
                          final isSelected = v == selectedModel;
                          return DropdownMenuItem<String>(
                            value: v,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.bolt_rounded,
                                  size: 14,
                                  color: isSelected ? clAccent : clTextDim,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isLoadingModels ? "Scanning models..." : v,
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected ? clAccent : clTextMain,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4), // ADD THIS
                  // ADD THIS NEW REFRESH BUTTON
                  IconButton(
                    icon: const Icon(
                      Icons.refresh,
                      color: clTextMuted,
                      size: 16,
                    ),
                    tooltip: "Refresh Models",
                    splashRadius: 16,
                    onPressed: _fetchOllamaModels,
                  ),

                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(
                      Icons.scatter_plot,
                      color: clAccent,
                      size: 20,
                    ),
                    tooltip: "3D Vector Graph",
                    onPressed: _openVectorGraph,
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.remove,
                          size: 14,
                          color: clTextMuted,
                        ),
                        splashRadius: 16,
                        onPressed: () => windowManager.minimize(),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.crop_square,
                          size: 13,
                          color: clTextMuted,
                        ),
                        splashRadius: 16,
                        onPressed: () async {
                          await windowManager.isMaximized()
                              ? windowManager.unmaximize()
                              : windowManager.maximize();
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 14,
                          color: clTextMuted,
                        ),
                        splashRadius: 16,
                        hoverColor: Colors.redAccent,
                        onPressed: () {
                          // KILL BACKEND BEFORE CLOSING
                          backendProcess?.kill();
                          windowManager.close();
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // ==================================================================
          // MAIN BODY
          // ==================================================================
          Expanded(
            child: Row(
              children: [
                // SIDEBAR

                // ==========================================
                // ANIMATED SIDEBAR
                // ==========================================
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  width: isSidebarVisible ? 270 : 0,
                  color: clSidebar,
                  clipBehavior: Clip.hardEdge,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      width: 270,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: _createNewChat,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: clSurface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: clBorder),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.add, size: 16, color: clAccent),
                                    SizedBox(width: 10),
                                    Text(
                                      "New Chat",
                                      style: TextStyle(
                                        color: clTextMain,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              height: 34,
                              decoration: BoxDecoration(
                                color: clSurface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: clBorder),
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: clTextMain,
                                ),
                                decoration: InputDecoration(
                                  hintText: "Search conversations...",
                                  hintStyle: const TextStyle(
                                    color: clTextDim,
                                    fontSize: 12,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 14,
                                    color: clTextDim,
                                  ),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.clear,
                                            size: 12,
                                            color: clTextDim,
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = "");
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.only(top: 2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "Conversations",
                              style: TextStyle(
                                color: clTextMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: filteredChats.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.only(top: 16),
                                      child: Center(
                                        child: Text(
                                          "No chats found",
                                          style: TextStyle(
                                            color: clTextDim,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: filteredChats.length,
                                      itemBuilder: (context, index) {
                                        final chat = filteredChats[index];
                                        final isActive =
                                            chat.id == activeChatId;
                                        return _ConversationTile(
                                          chat: chat,
                                          isActive: isActive,
                                          onTap: () {
                                            setState(
                                              () => activeChatId = chat.id,
                                            );
                                            _saveChats();
                                            _scrollToBottom();
                                          },
                                          onRename: () =>
                                              _showRenameDialog(chat),
                                          onDelete: () => _deleteChat(chat),
                                        );
                                      },
                                    ),
                            ),
                            const Divider(color: clBorder),
                            const SizedBox(height: 4),
                            const Text(
                              "Attached Documents",
                              style: TextStyle(
                                color: clTextMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 90,
                              child: activeChat.documents.isEmpty
                                  ? const Text(
                                      "No documents attached",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: clTextDim,
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: activeChat.documents.length,
                                      itemBuilder: (context, idx) {
                                        final docName =
                                            activeChat.documents[idx];
                                        return Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 4,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: clSurface,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(color: clBorder),
                                          ),
                                          child: Row(
                                            children: [
                                              const Text(
                                                "📄 ",
                                                style: TextStyle(fontSize: 10),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  docName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: clTextMain,
                                                  ),
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () =>
                                                    _removeDocument(docName),
                                                child: const Icon(
                                                  Icons.close,
                                                  size: 12,
                                                  color: clTextDim,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            ElevatedButton.icon(
                              onPressed: isUploading ? null : _uploadDocument,
                              icon: isUploading
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: clAccent,
                                      ),
                                    )
                                  : const Icon(Icons.attach_file, size: 14),
                              label: Text(
                                isUploading
                                    ? "Processing..."
                                    : "Attach Documents",
                                style: const TextStyle(fontSize: 12),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: clSurface,
                                foregroundColor: clTextMain,
                                minimumSize: const Size(double.infinity, 36),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: clBorder),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // CHAT STREAM WITH MARKDOWN RENDERING
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        // ==========================================
                        // NEW LOGIC: SHOW WELCOME SCREEN IF EMPTY
                        // ==========================================
                        child: activeChat.messages.length <= 1
                            ? _buildWelcomeScreen()
                            : SelectionArea(
                                child: ListView.builder(
                                  controller:
                                      _scrollController, // CONTROLLING THE SCROLL
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 64,
                                    vertical: 24,
                                  ),
                                  itemCount:
                                      activeChat.messages.length +
                                      (isTyping ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == activeChat.messages.length)
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          "StudentRAG is thinking...",
                                          style: TextStyle(
                                            color: clTextDim,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      );
                                    final msg = activeChat.messages[index];
                                    final isUser = msg.role == 'user';

                                    if (msg.role == 'system')
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 24,
                                        ),
                                        child: Text(
                                          msg.text,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: clTextMuted,
                                          ),
                                        ),
                                      );

                                    return Align(
                                      alignment: isUser
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        padding: const EdgeInsets.all(18),
                                        constraints: const BoxConstraints(
                                          maxWidth: 720,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isUser
                                              ? clUserBubble
                                              : clSurface,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(color: clBorder),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // MARKDOWN RENDERER
                                            MarkdownBody(
                                              data: msg.text,
                                              styleSheet: MarkdownStyleSheet(
                                                p: const TextStyle(
                                                  color: clTextMain,
                                                  height: 1.55,
                                                  fontSize: 14,
                                                ),
                                                code: const TextStyle(
                                                  color: clAccent,
                                                  backgroundColor: clBg,
                                                  fontFamily: 'Consolas',
                                                ),
                                                codeblockDecoration:
                                                    BoxDecoration(
                                                      color: clBg,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      border: Border.all(
                                                        color: clBorder,
                                                      ),
                                                    ),
                                                h1: const TextStyle(
                                                  color: clTextMain,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 20,
                                                ),
                                                h2: const TextStyle(
                                                  color: clTextMain,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                ),
                                                listBullet: const TextStyle(
                                                  color: clAccent,
                                                ),
                                              ),
                                            ),
                                            if (msg.sources.isNotEmpty) ...[
                                              const SizedBox(height: 16),
                                              const Text(
                                                "Context Sources:",
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: clTextMuted,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: msg.sources.map((s) {
                                                  return Tooltip(
                                                    message: s.text,
                                                    padding:
                                                        const EdgeInsets.all(
                                                          12,
                                                        ),
                                                    textStyle: const TextStyle(
                                                      fontSize: 12,
                                                      color: clTextMain,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: clBg,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      border: Border.all(
                                                        color: clBorder,
                                                      ),
                                                    ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: clBg,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        border: Border.all(
                                                          color: clBorder,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        "📄 ${s.source}",
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          color: clAccent,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            Align(
                                              alignment: Alignment.bottomRight,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.copy,
                                                  size: 14,
                                                  color: clTextDim,
                                                ),
                                                splashRadius: 14,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                tooltip: "Copy message",
                                                onPressed: () =>
                                                    _copyToClipboard(msg.text),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(64, 0, 64, 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: clSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: clBorder),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _msgController,
                                  style: const TextStyle(
                                    color: clTextMain,
                                    fontSize: 14,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: "Message StudentRAG...",
                                    hintStyle: TextStyle(color: clTextDim),
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_upward,
                                  color: clTextMain,
                                  size: 18,
                                ),
                                onPressed: _sendMessage,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. 3D VECTOR GRAPH (WITH PRE-POPULATED INTERACTIVE LEGEND)
// ============================================================================
class VectorGraphDialog extends StatefulWidget {
  final List<VectorPoint> points;
  final String chatTitle;
  const VectorGraphDialog({
    super.key,
    required this.points,
    required this.chatTitle,
  });
  @override
  State<VectorGraphDialog> createState() => _VectorGraphDialogState();
}

class _VectorGraphDialogState extends State<VectorGraphDialog> {
  double rotX = 0.4;
  double rotY = 0.6;
  double zoom = 190.0;
  String? selectedSourceFilter;
  final Map<String, Color> _sourceColors = {};
  final List<Color> _palette = [
    const Color(0xFF89B4FA),
    const Color(0xFFD97757),
    const Color(0xFFA6E3A1),
    const Color(0xFFFAB387),
    const Color(0xFFCBA6F7),
    const Color(0xFF94E2D5),
    const Color(0xFFF38BA8),
  ];

  @override
  void initState() {
    super.initState();
    for (var pt in widget.points)
      if (!_sourceColors.containsKey(pt.source))
        _sourceColors[pt.source] =
            _palette[_sourceColors.length % _palette.length];
  }

  Color _getColorForSource(String source) => _sourceColors[source] ?? clAccent;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: clBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: clBorder),
      ),
      child: Container(
        width: 880,
        height: 640,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "3D Vector Space (${widget.points.length} Chunks)",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: clTextMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "Drag to rotate • Click a legend item to filter dots",
                      style: TextStyle(fontSize: 12, color: clTextMuted),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: clTextDim),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: clSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: clBorder),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: _sourceColors.entries.map((e) {
                  final isSelected =
                      selectedSourceFilter == null ||
                      selectedSourceFilter == e.key;
                  final count = widget.points
                      .where((p) => p.source == e.key)
                      .length;
                  return InkWell(
                    onTap: () => setState(
                      () => selectedSourceFilter = selectedSourceFilter == e.key
                          ? null
                          : e.key,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? e.value
                                  : e.value.withOpacity(0.2),
                              shape: BoxShape.circle,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: e.value.withOpacity(0.4),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "${e.key} ($count)",
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? clTextMain : clTextDim,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: GestureDetector(
                onPanUpdate: (details) => setState(() {
                  rotY += details.delta.dx * 0.01;
                  rotX -= details.delta.dy * 0.01;
                }),
                child: Container(
                  decoration: BoxDecoration(
                    color: clSidebar,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: clBorder),
                  ),
                  child: CustomPaint(
                    painter: Vector3DPainter(
                      points: selectedSourceFilter == null
                          ? widget.points
                          : widget.points
                                .where((p) => p.source == selectedSourceFilter)
                                .toList(),
                      rotX: rotX,
                      rotY: rotY,
                      zoom: zoom,
                      getColor: _getColorForSource,
                    ),
                    child: Container(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Vector3DPainter extends CustomPainter {
  final List<VectorPoint> points;
  final double rotX, rotY, zoom;
  final Color Function(String) getColor;
  Vector3DPainter({
    required this.points,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.getColor,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final projectedPoints = points.map((p) {
      double x1 = p.x,
          y1 = p.y * math.cos(rotX) - p.z * math.sin(rotX),
          z1 = p.y * math.sin(rotX) + p.z * math.cos(rotX);
      double x2 = x1 * math.cos(rotY) + z1 * math.sin(rotY),
          y2 = y1,
          z2 = -x1 * math.sin(rotY) + z1 * math.cos(rotY);
      double depth = 1.0 + (z2 * 0.35);
      return {
        'offset': Offset(
          center.dx + (x2 * zoom * depth),
          center.dy - (y2 * zoom * depth),
        ),
        'depth': z2,
        'color': getColor(p.source),
      };
    }).toList();
    projectedPoints.sort(
      (a, b) => (a['depth'] as double).compareTo(b['depth'] as double),
    );
    for (var pt in projectedPoints) {
      canvas.drawCircle(
        pt['offset'] as Offset,
        6,
        Paint()
          ..color = (pt['color'] as Color).withOpacity(0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        pt['offset'] as Offset,
        3.5,
        Paint()..color = pt['color'] as Color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant Vector3DPainter oldDelegate) => true;
}

class _ConversationTile extends StatefulWidget {
  final ChatSession chat;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.chat,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: widget.isActive ? clSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: widget.isActive ? Border.all(color: clBorder) : null,
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ),
          title: Tooltip(
            message: widget.chat.title,
            waitDuration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: const TextStyle(fontSize: 12, color: clTextMain),
            decoration: BoxDecoration(
              color: clBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: clBorder),
            ),
            child: Text(
              widget.chat.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: widget.isActive ? clTextMain : clTextMuted,
                fontSize: 13,
                fontWeight: widget.isActive
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
          trailing: PopupMenuButton<String>(
            icon: Icon(
              Icons.more_horiz,
              size: 16,
              // The fix: Make it visible if it's active OR currently being hovered
              color: widget.isActive || isHovered
                  ? clTextMuted
                  : Colors.transparent,
            ),
            color: clSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: clBorder),
            ),
            onSelected: (val) {
              if (val == 'rename') widget.onRename();
              if (val == 'delete') widget.onDelete();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Text(
                  "✏️ Rename",
                  style: TextStyle(fontSize: 12, color: clTextMain),
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  "🗑️ Delete",
                  style: TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ),
            ],
          ),
          onTap: widget.onTap,
        ),
      ),
    );
  }
}
