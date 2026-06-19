import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'main.dart' show ResultStore, ResultSnapshot;

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
    return (prizes: p, compliments: c);
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
                      _buildPrizeRow(
                          "1st Prize", p[0], const Color(0xFFC8E6C9)),
                      _buildPrizeRow(
                          "2nd Prize", p[1], const Color(0xFFBBDEFB)),
                      _buildPrizeRow(
                          "3rd Prize", p[2], const Color(0xFFFFF9C4)),
                      _buildPrizeRow(
                          "4th Prize", p[3], const Color(0xFFE1BEE7)),
                      _buildPrizeRow(
                          "5th Prize", p[4], const Color(0xFFFFE0B2)),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text("COMPLIMENTS",
                            style: TextStyle(
                                color: Color(0xFF555555),
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                      _buildComplimentsGrid(c),
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

  Widget _buildPrizeRow(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        ],
      ),
    );
  }

  Widget _buildComplimentsGrid(List<String> c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 3.8,
          mainAxisSpacing: 3,
          crossAxisSpacing: 6,
        ),
        itemCount: c.length,
        itemBuilder: (context, i) => Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300)),
          child: Text(c[i],
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
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
