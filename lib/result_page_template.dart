import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reference layout: pastel prize bands, LIVE RESULT bar, pill compliments grid.
const List<Color> kResultTemplatePrizeColors = [
  Color(0xFFC2F4DF), // 1st — green
  Color(0xFFB8D9F5), // 2nd — blue
  Color(0xFFD8C3EF), // 3rd — purple
  Color(0xFFFFD4A8), // 4th — orange
  Color(0xFFFFDAEA), // 5th — pink
];

const List<String> kResultTemplatePrizeLabels = [
  '1ST PRIZE',
  '2ND PRIZE',
  '3RD PRIZE',
  '4TH PRIZE',
  '5TH PRIZE',
];

const List<double> kResultTemplatePrizeFontSizes = [22, 20, 18, 16, 14];

const Color kResultTemplateLiveGreen = Color(0xFF8BC34A);
const Color kResultTemplateLiveGreenDark = Color(0xFF558B2F);
const Color kResultTemplateComplimentPill = Color(0xFFF0F1F3);
const Color kResultTemplateHeadingGrey = Color(0xFF424242);

const int kResultTemplateComplimentRows = 10;
const int kResultTemplateComplimentCols = 3;

/// Column-down storage: col1 (0–9), col2 (10–19), col3 (20–29).
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

/// LIVE RESULT + date bar (reference screenshot).
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLiveButton) ...[
          Expanded(
            flex: 11,
            child: Material(
              color: liveActive
                  ? kResultTemplateLiveGreen
                  : kResultTemplateLiveGreen.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: onLiveResult,
                borderRadius: BorderRadius.circular(10),
                child: const Center(
                  child: Text(
                    'LIVE RESULT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          flex: showLiveButton ? 13 : 1,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onChangeDate,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          dateLine,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      'CHANGE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Single prize band — label centered above number.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final bandH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : numberFontSize * 2.4;
        final labelCap = relaxedLayout ? 18.0 : 12.0;
        final numFactor = relaxedLayout ? 0.58 : 0.48;
        final labelSize = (bandH * 0.24).clamp(8.0, labelCap);
        final numLo = numberFontSize < 10.0 ? numberFontSize : 10.0;
        final numHi = numberFontSize > 10.0 ? numberFontSize : 10.0;
        final numSize = (bandH * numFactor).clamp(numLo, numHi);
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.vertical(
              top: prizeIndex == 0 ? const Radius.circular(12) : Radius.zero,
              bottom: prizeIndex == 4 ? const Radius.circular(12) : Radius.zero,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: labelSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: const Color(0xFF1A1A1A).withValues(alpha: 0.72),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: numSize,
                    color: const Color(0xFF1A1A1A),
                    letterSpacing: 1,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Editable prize band for manual entry.
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
        borderRadius: BorderRadius.vertical(
          top: prizeIndex == 0 ? const Radius.circular(12) : Radius.zero,
          bottom: prizeIndex == 4 ? const Radius.circular(12) : Radius.zero,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: (numberFontSize * 0.42).clamp(9.0, 12.0),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: const Color(0xFF1A1A1A).withValues(alpha: 0.72),
            ),
          ),
          TextField(
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
              fontSize: numberFontSize,
              color: const Color(0xFF1A1A1A),
              letterSpacing: 1,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: '---',
            ),
          ),
        ],
      ),
    );
  }
}

/// 3×10 pill grid — visual row-major, storage column-down; fits available height.
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
      const hPad = 6.0;
      const vPad = 2.0;
      const crossGap = 4.0;
      const mainGap = 3.0;
      final cellH =
          (constraints.maxHeight - vPad * 2 - mainGap * 9) / kResultTemplateComplimentRows;
      final fontLo = fontSize < 9.0 ? fontSize : 9.0;
      final fontHi = fontSize > 9.0 ? fontSize : 9.0;
      final resolvedFontSize = cellH > 0
          ? (cellH * 0.52).clamp(fontLo, fontHi)
          : fontSize;

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
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A1A),
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
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A1A1A),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
        child: Column(
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
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: kResultTemplateComplimentPill,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: cellContent(storageIndex, display),
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
    },
  );
}

/// White card with COMPLIMENTS heading.
class ResultTemplateComplimentsCard extends StatelessWidget {
  const ResultTemplateComplimentsCard({
    super.key,
    required this.grid,
    this.headingFontSize = 12,
  });

  final Widget grid;
  final double headingFontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Text(
              'COMPLIMENTS',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: headingFontSize,
                letterSpacing: 0.6,
                fontWeight: FontWeight.bold,
                color: kResultTemplateHeadingGrey,
              ),
            ),
          ),
          Expanded(child: grid),
        ],
      ),
    );
  }
}

/// Share screenshot card — sized to phone width so messaging apps don't shrink it.
class ResultShareCaptureCard extends StatelessWidget {
  const ResultShareCaptureCard({
    super.key,
    required this.width,
    required this.height,
    required this.drawTitle,
    required this.dateLine,
    required this.themeGradient,
    required this.prizes,
    required this.compliments,
  });

  final double width;
  final double height;
  final String drawTitle;
  final String dateLine;
  final List<Color> themeGradient;
  final List<String> prizes;
  final List<String> compliments;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: const Color(0xFFFFF8E8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalH = constraints.maxHeight;
            final headerH = (totalH * 0.07).clamp(44.0, 56.0);
            const gapLabel = 4.0;
            final contentH = totalH - headerH - gapLabel;
            final prizeH = contentH * 0.44;
            final complimentsH = contentH - prizeH - gapLabel;
            final rowH = prizeH / 5;
            final complimentFont =
                (complimentsH / 10 * 0.48).clamp(11.0, 15.0);
            final headerTitleSize = (headerH * 0.38).clamp(16.0, 22.0);
            final headerDateSize = (headerH * 0.30).clamp(13.0, 17.0);
            final headingFont = (complimentFont + 2).clamp(13.0, 17.0);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: headerH,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: themeGradient,
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          drawTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: headerTitleSize,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateLine,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: headerDateSize,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: gapLabel),
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
                SizedBox(height: gapLabel),
                SizedBox(
                  height: complimentsH,
                  child: ResultTemplateComplimentsCard(
                    headingFontSize: headingFont,
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

/// Cream gradient behind prizes + compliments.
class ResultPageTemplateBackground extends StatelessWidget {
  const ResultPageTemplateBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFFFF6EE),
            Color(0xFFFFF0E4),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}
