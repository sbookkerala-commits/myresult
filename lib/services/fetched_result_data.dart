class FetchedResultData {
  final String drawCode;
  final DateTime date;
  final List<String> prizes;
  final List<String> compliments;

  const FetchedResultData({
    required this.drawCode,
    required this.date,
    required this.prizes,
    required this.compliments,
  });
}

class ResultFetchOutcome {
  final String drawCode;
  final bool saved;
  final bool notReady;
  final String? message;

  const ResultFetchOutcome({
    required this.drawCode,
    this.saved = false,
    this.notReady = false,
    this.message,
  });
}
