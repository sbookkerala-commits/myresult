/// Official live stream URLs for result page LIVE button.
class LotteryLiveLinks {
  /// Nagaland State Lotteries — Dear 1 PM / 6 PM / 8 PM (official embed channel).
  static const dearYoutubeChannelId = 'UC1hMx2A4ah-Gx_mj0ckfmag';

  static Uri liveUriForDraw(String drawCode) {
    switch (drawCode.trim().toUpperCase()) {
      case 'LSK3':
        return Uri.parse(
          'https://www.keralalotteries.net/p/kerala-lottery-videos.html',
        );
      default:
        return Uri.parse(
          'https://www.youtube.com/channel/$dearYoutubeChannelId/live',
        );
    }
  }
}
