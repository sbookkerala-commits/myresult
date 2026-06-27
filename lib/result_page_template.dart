import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Classic winning-numbers layout (screenshot reference).
const Color kResultClassicHeaderBlue = Color(0xFF1565C0);
const Color kResultClassicSearchGold = Color(0xFFFFD54F);
const Color kWhatsAppBrandGreen = Color(0xFF25D366);

const List<Color> kResultTemplatePrizeColors = [
  Color(0xFF29B61D), // First — green
  Color(0xFF1A68C1), // Second — blue
  Color(0xFF7216A6), // Third — purple
  Color(0xFFCD7125), // Fourth — orange
  Color(0xFF0C3374), // Fifth — navy
];

const List<String> kResultTemplatePrizeLabels = [
  'First',
  'Second',
  'Third',
  'Fourth',
  'Fifth',
];

const List<double> kResultTemplatePrizeFontSizes = [22, 20, 18, 16, 14];

const Color kResultTemplateLiveGreen = Color(0xFF8BC34A);
const Color kResultTemplateLiveGreenDark = Color(0xFF558B2F);
const Color kResultTemplateComplimentPill = Color(0xFFF0F1F3);
const Color kResultTemplateHeadingGrey = Color(0xFF424242);

const int kResultTemplateComplimentRows = 10;
const int kResultTemplateComplimentCols = 3;

int resultTemplateComplimentCellIndex(int row, int col) =>
    col * kResultTemplateComplimentRows + row;

String resultTemplateFormatCompliment(String raw) {
  if (raw.trim().isEmpty || raw.trim() == '---') return '---';
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '---';
  final n = int.tryParse(digits.length > 3 ? digits.substring(0, 3) : digits);
  if (n == null) return '---';
  return n.toString().padLeft(3, '0');
}

String resultDrawCompactTime(String draw) {
  switch (draw.trim()) {
    case 'DEAR 1 PM':
      return '1:00PM';
    case 'LSK 3 PM':
      return '3:00PM';
    case 'DEAR 6 PM':
      return '6:00PM';
    case 'DEAR 8 PM':
      return '8:00PM';
    default:
      return draw.replaceAll(' ', '');
  }
}

String resultDrawSpacedTime(String draw) {
  switch (draw.trim()) {
    case 'DEAR 1 PM':
      return '1:00 PM';
    case 'LSK 3 PM':
      return '3:00 PM';
    case 'DEAR 6 PM':
      return '6:00 PM';
    case 'DEAR 8 PM':
      return '8:00 PM';
    default:
      return draw;
  }
}

String resultDateFieldLabel(DateTime date) {
  final d = date.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

String resultDateIso(DateTime date) {
  final d = date.toLocal();
  return '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Underlined time + date row with optional tap handlers.
class ResultWinningNumbersSearchRow extends StatelessWidget {
  const ResultWinningNumbersSearchRow({
    super.key,
    required this.timeLabel,
    required this.dateLabel,
    this.onTimeTap,
    this.onDateTap,
  });

  final String timeLabel;
  final String dateLabel;
  final VoidCallback? onTimeTap;
  final VoidCallback? onDateTap;

  @override
  Widget build(BuildContext context) {
    Widget field({
      required String label,
      required VoidCallback? onTap,
    }) {
      final decorated = InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.fromLTRB(4, 12, 4, 10),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF757575)),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: kResultClassicHeaderBlue, width: 2),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF212121),
          ),
        ),
      );
      return Expanded(
        child: onTap == null
            ? decorated
            : InkWell(onTap: onTap, child: decorated),
      );
    }

    return Row(
      children: [
        field(label: timeLabel, onTap: onTimeTap),
        const SizedBox(width: 16),
        field(label: dateLabel, onTap: onDateTap),
      ],
    );
  }
}

class ResultWhatsappIcon extends StatelessWidget {
  const ResultWhatsappIcon({
    super.key,
    this.size = 16,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FaIcon(
      FontAwesomeIcons.whatsapp,
      size: size,
      color: color,
    );
  }
}

class ResultResultsTitleBar extends StatelessWidget {
  const ResultResultsTitleBar({
    super.key,
    this.bookingWhatsappPhone = '',
    this.verticalPadding = 10,
  });

  final String bookingWhatsappPhone;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final phone = bookingWhatsappPhone.trim();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: verticalPadding,
        horizontal: 12,
      ),
      color: kWhatsAppBrandGreen,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Booking Whatsapp',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          const ResultWhatsappIcon(size: 18),
          if (phone.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                phone,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ResultWinningNumbersSearchButton extends StatelessWidget {
  const ResultWinningNumbersSearchButton({
    super.key,
    required this.onPressed,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 34,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: kResultClassicHeaderBlue,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          disabledBackgroundColor: kResultClassicHeaderBlue,
          side: const BorderSide(color: kResultClassicSearchGold, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: EdgeInsets.zero,
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'SEARCH',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.6,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

/// Legacy toolbar — kept for compatibility; prefer search row on result page.
class ResultPageToolbar extends StatelessWidget {
  const ResultPageToolbar({
    super.key,
    required this.dateLine,
    required this.accentColor,
    this.onLiveResult,
    this.onChangeDate,
    this.liveActive = false,
    this.showLiveButton = true,
  });

  final String dateLine;
  final Color accentColor;
  final VoidCallback? onLiveResult;
  final VoidCallback? onChangeDate;
  final bool liveActive;
  final bool showLiveButton;

  @override
  Widget build(BuildContext context) {
    return ResultWinningNumbersSearchRow(
      timeLabel: 'LIVE',
      dateLabel: dateLine,
      onTimeTap: showLiveButton ? onLiveResult : null,
      onDateTap: onChangeDate,
    );
  }
}

class ResultTemplatePrizeBand extends StatelessWidget {
  const ResultTemplatePrizeBand({
    super.key,
    required this.prizeIndex,
    required this.value,
    required this.numberFontSize,
    this.relaxedLayout = false,
  });

  final int prizeIndex;
  final String value;
  final double numberFontSize;
  final bool relaxedLayout;

  @override
  Widget build(BuildContext context) {
    final bg = kResultTemplatePrizeColors[prizeIndex];
    final label = kResultTemplatePrizeLabels[prizeIndex];
    final display = value.trim().isEmpty ? '---' : value.trim();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const Text(
            ':',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          Expanded(
            child: Text(
              display,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: numberFontSize.clamp(14.0, 24.0),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ResultTemplatePrizeBandField extends StatelessWidget {
  const ResultTemplatePrizeBandField({
    super.key,
    required this.prizeIndex,
    required this.controller,
    required this.focusNode,
    required this.numberFontSize,
    required this.inputFormatters,
    this.onTap,
    this.onChanged,
  });

  final int prizeIndex;
  final TextEditingController controller;
  final FocusNode focusNode;
  final double numberFontSize;
  final List<TextInputFormatter> inputFormatters;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final bg = kResultTemplatePrizeColors[prizeIndex];
    final label = kResultTemplatePrizeLabels[prizeIndex];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const Text(
            ':',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: inputFormatters,
              onTap: onTap,
              onChanged: onChanged,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: numberFontSize.clamp(14.0, 24.0),
                color: Colors.white,
                letterSpacing: 0.5,
              ),
              cursorColor: Colors.white,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: '---',
                hintStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildResultTemplateComplimentsGrid({
  required double fontSize,
  required List<String> values,
  List<TextEditingController>? controllers,
  List<FocusNode>? focusNodes,
  int focusFieldOffset = 0,
  void Function(int storageIndex, String value)? onFieldChanged,
  void Function(TextEditingController controller)? onFieldTap,
  List<TextInputFormatter>? inputFormatters,
}) {
  final editing = controllers != null;
  final formatters = inputFormatters ??
      [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ];

  return LayoutBuilder(
    builder: (context, constraints) {
      const crossGap = 8.0;
      const mainGap = 2.0;
      final cellH =
          (constraints.maxHeight - mainGap * 9) / kResultTemplateComplimentRows;
      final fontLo = fontSize < 10.0 ? fontSize : 10.0;
      final fontHi = fontSize > 14.0 ? fontSize : 14.0;
      final resolvedFontSize =
          cellH > 0 ? (cellH * 0.74).clamp(fontLo, fontHi) : fontSize;

      Widget cellContent(int storageIndex, String display) {
        if (editing) {
          return TextField(
            controller: controllers![storageIndex],
            focusNode: focusNodes?[focusFieldOffset + storageIndex],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            textInputAction: storageIndex == 29
                ? TextInputAction.done
                : TextInputAction.next,
            inputFormatters: formatters,
            onTap: () => onFieldTap?.call(controllers[storageIndex]),
            onChanged: (v) => onFieldChanged?.call(storageIndex, v),
            style: TextStyle(
              fontSize: resolvedFontSize,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF212121),
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: '---',
            ),
          );
        }
        return Text(
          display,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: resolvedFontSize,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF212121),
          ),
        );
      }

      return Column(
        children: List.generate(kResultTemplateComplimentRows, (row) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: row < kResultTemplateComplimentRows - 1 ? mainGap : 0,
              ),
              child: Row(
                children: List.generate(kResultTemplateComplimentCols, (col) {
                  final storageIndex =
                      resultTemplateComplimentCellIndex(row, col);
                  final raw = storageIndex < values.length
                      ? values[storageIndex]
                      : '---';
                  final display = resultTemplateFormatCompliment(raw);

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: col < kResultTemplateComplimentCols - 1
                            ? crossGap
                            : 0,
                      ),
                      child: Center(child: cellContent(storageIndex, display)),
                    ),
                  );
                }),
              ),
            ),
          );
        }),
      );
    },
  );
}

class ResultTemplateComplimentsCard extends StatelessWidget {
  const ResultTemplateComplimentsCard({
    super.key,
    required this.grid,
    this.headingFontSize = 13,
    this.showEndMarker = true,
  });

  final Widget grid;
  final double headingFontSize;
  final bool showEndMarker;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade500, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'COMPLIMENTS',
                  style: TextStyle(
                    fontSize: headingFontSize,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w800,
                    color: kResultTemplateHeadingGrey,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade500, height: 1)),
            ],
          ),
        ),
        Expanded(child: grid),
        if (showEndMarker)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              '---End---',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: headingFontSize,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
      ],
    );
  }
}

class ResultShareCaptureCard extends StatelessWidget {
  const ResultShareCaptureCard({
    super.key,
    required this.width,
    required this.height,
    required this.timeLabel,
    required this.dateLabel,
    required this.bookingWhatsappPhone,
    this.showBookingWhatsappBar = true,
    required this.prizes,
    required this.compliments,
  });

  final double width;
  final double height;
  final String timeLabel;
  final String dateLabel;
  final String bookingWhatsappPhone;
  final bool showBookingWhatsappBar;
  final List<String> prizes;
  final List<String> compliments;

  static const double _prizeFraction = 0.37;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.white,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const topPad = 10.0;
            const gapAfterSearch = 10.0;
            const gapAfterButton = 10.0;
            const gapAfterTitle = 4.0;
            const gapLabel = 4.0;
            const searchRowH = 52.0;
            const searchBtnH = 34.0;
            const titleBarH = 44.0;

            final bookingBarH =
                showBookingWhatsappBar ? titleBarH + gapAfterTitle : 0.0;
            final topSectionH = topPad +
                searchRowH +
                gapAfterSearch +
                searchBtnH +
                gapAfterButton +
                bookingBarH;
            final contentH =
                (constraints.maxHeight - topSectionH).clamp(0.0, double.infinity);
            final prizeH = contentH * _prizeFraction;
            final complimentsH =
                (contentH - prizeH - gapLabel).clamp(0.0, double.infinity);
            final rowH = prizeH > 0 ? prizeH / 5 : 0.0;
            final complimentFont =
                complimentsH > 0 ? (complimentsH / 10 * 0.52).clamp(10.0, 14.0) : 13.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: topPad),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ResultWinningNumbersSearchRow(
                    timeLabel: timeLabel,
                    dateLabel: dateLabel,
                  ),
                ),
                const SizedBox(height: gapAfterSearch),
                const Center(
                  child: ResultWinningNumbersSearchButton(onPressed: null),
                ),
                const SizedBox(height: gapAfterButton),
                if (showBookingWhatsappBar) ...[
                  ResultResultsTitleBar(
                    bookingWhatsappPhone: bookingWhatsappPhone,
                  ),
                  const SizedBox(height: gapAfterTitle),
                ],
                SizedBox(
                  height: prizeH,
                  child: Column(
                    children: List.generate(5, (i) {
                      return SizedBox(
                        height: rowH,
                        child: ResultTemplatePrizeBand(
                          prizeIndex: i,
                          value: i < prizes.length ? prizes[i] : '---',
                          numberFontSize: kResultTemplatePrizeFontSizes[i],
                          relaxedLayout: true,
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: gapLabel),
                SizedBox(
                  height: complimentsH,
                  child: ResultTemplateComplimentsCard(
                    headingFontSize: (complimentFont + 2).clamp(12.0, 16.0),
                    grid: buildResultTemplateComplimentsGrid(
                      fontSize: complimentFont,
                      values: compliments,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ResultPageTemplateBackground extends StatelessWidget {
  const ResultPageTemplateBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: child,
    );
  }
}
