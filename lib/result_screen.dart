import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'main.dart'
    show ResultStore, ResultSnapshot, sortedComplimentsColumnMajor, formatComplimentDisplay;

int _complimentCellIndex(int row, int col) => col * 10 + row;

Color getResultThemeColor(String time) {
  switch (time) {
    case "DEAR 1PM":
      return const Color(0xFFE91E63);
    case "LSK 3PM":
      return const Color(0xFF2196F3);
    case "DEAR 6PM":
      return const Color(0xFF4CAF50);
    case "DEAR 8PM":
      return const Color(0xFF673AB7);
    default:
      return const Color(0xFF607D8B);
  }
}

String _drawCodeFromTime(String time) {
  switch (time) {
    case "DEAR 1PM":
      return "DEAR1";
    case "LSK 3PM":
      return "LSK3";
    case "DEAR 6PM":
      return "DEAR6";
    case "DEAR 8PM":
      return "DEAR8";
    default:
      return "";
  }
}

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  String selectedTime = "DEAR 1PM";
  String selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final ScreenshotController _screenshotController = ScreenshotController();
  bool isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  void _checkAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => isAdmin = prefs.getBool('isAdmin') ?? false);
  }

  ({List<String> prizes, List<String> compliments}) _loadResult() {
    final code = _drawCodeFromTime(selectedTime);
    final date = DateTime.parse(selectedDate);
    final snapshot = ResultStore.get(code, date);
    if (snapshot == null) {
      return (
        prizes: List.filled(5, "---"),
        compliments: List.filled(30, "---"),
      );
    }
    final p = List<String>.filled(5, "---");
    final c = List<String>.filled(30, "---");
    for (int i = 0; i < 5 && i < snapshot.prizes.length; i++) {
      p[i] = snapshot.prizes[i];
    }
    for (int i = 0; i < 30 && i < snapshot.compliments.length; i++) {
      c[i] = snapshot.compliments[i];
    }
    final sorted = sortedComplimentsColumnMajor(c);
    return (prizes: p, compliments: sorted);
  }

  @override
  Widget build(BuildContext context) {
    Color themeColor = getResultThemeColor(selectedTime);
    return ValueListenableBuilder<Map<String, ResultSnapshot>>(
      valueListenable: ResultStore.results,
      builder: (context, _, __) {
        final data = _loadResult();
        final p = data.prizes;
        final c = data.compliments;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: themeColor,
            foregroundColor: Colors.white,
            title: DropdownButton<String>(
              value: selectedTime,
              dropdownColor: themeColor,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              underline: Container(),
              items: ["DEAR 1PM", "LSK 3PM", "DEAR 6PM", "DEAR 8PM"]
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => selectedTime = v!),
            ),
            actions: [
              IconButton(
                  onPressed: _shareScreenshot, icon: const Icon(Icons.share)),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(children: [
              const SizedBox(height: 10),
              Screenshot(
                controller: _screenshotController,
                child: Container(
                  color: Colors.white,
                  child: Column(
                    children: [
                      _buildHeader(themeColor),
                      const Divider(height: 1, indent: 15, endIndent: 15),
                      const SizedBox(height: 8),
                      _buildPrizeRow("1", p[0], const Color(0xFFC2F4DF), 22, 0),
                      _buildPrizeRow("2", p[1], const Color(0xFFFFECE8), 20, 1),
                      _buildPrizeRow("3", p[2], const Color(0xFFFFDAEA), 18, 2),
                      _buildPrizeRow("4", p[3], const Color(0xFFF9CBF5), 16, 3),
                      _buildPrizeRow("5", p[4], const Color(0xFFD8C3EF), 14, 4),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFF9E9E9E),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 8),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Color(0xFF9E9E9E),
                                    width: 0.8,
                                  ),
                                ),
                              ),
                              child: const Text(
                                "COMPLIMENTS",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            _buildComplimentsRows(c),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildHeader(Color themeColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 8, 15, 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  DateFormat('dd-MM-yyyy').format(DateTime.parse(selectedDate)),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900)),
              Text("$selectedTime RESULT",
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: themeColor)),
            ],
          ),
          TextButton.icon(
            onPressed: () async {
              DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.parse(selectedDate),
                  firstDate: DateTime(2023),
                  lastDate: DateTime(2030));
              if (picked != null) {
                setState(() =>
                    selectedDate = DateFormat('yyyy-MM-dd').format(picked));
              }
            },
            icon: const Icon(Icons.calendar_month),
            label: const Text("HISTORY"),
          )
        ],
      ),
    );
  }

  Widget _buildPrizeRow(String position, String value, Color color,
      double numberFontSize, int prizeIndex) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: color,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              position,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: Colors.black.withValues(alpha: 0.75),
              ),
            ),
          ),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: numberFontSize),
          ),
        ],
      ),
    );
  }

  Widget _buildComplimentsRows(List<String> c) {
    return SizedBox(
      height: 320,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(3, (col) {
          return Expanded(
            child: Container(
              decoration: col < 2
                  ? const BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Color(0xFF9E9E9E),
                          width: 0.8,
                        ),
                      ),
                    )
                  : null,
              child: Column(
                children: List.generate(10, (row) {
                  final index = _complimentCellIndex(row, col);
                  final value = index < c.length ? c[index] : "---";
                  final display = formatComplimentDisplay(value);
                  return Expanded(
                    child: Center(
                      child: Text(
                        display,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          );
        }),
      ),
    );
  }

  Future<void> _shareScreenshot() async {
    final image = await _screenshotController.capture();
    if (image == null) return;
    final directory = await getApplicationDocumentsDirectory();
    final file =
        await File('${directory.path}/result.png').writeAsBytes(image);
    await Share.shareXFiles([XFile(file.path)],
        text: '$selectedTime Result - $selectedDate');
  }
}
