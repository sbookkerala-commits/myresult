import 'app_locale.dart';

/// Popup, snackbar, and warning messages — English / Malayalam / Tamil.
class AppMsg {
  AppMsg._();

  static String _t(String key) {
    final lang = AppLocale.language.value;
    return _bundle[lang]?[key] ?? _bundle[AppLanguage.en]![key] ?? key;
  }

  static String _fmt(String key, Map<String, String> vars) {
    var text = _t(key);
    vars.forEach((k, v) => text = text.replaceAll('{$k}', v));
    return text;
  }

  // Common
  static String get cancel => _t('cancel');
  static String get delete => _t('delete');
  static String get save => _t('save');
  static String get ok => _t('ok');
  static String get close => _t('close');

  // Language
  static String get languageTitle => _t('languageTitle');
  static String get languageChanged => _t('languageChanged');
  static String get menuLanguage => _t('menuLanguage');

  // Login
  static String get accountBlocked => _t('accountBlocked');
  static String cloudLoginFailed(String detail) =>
      _fmt('cloudLoginFailed', {'detail': detail});
  static String get wrongCredentials => _t('wrongCredentials');
  static String loginFailed(Object e) =>
      _fmt('loginFailed', {'error': e.toString()});

  // Users
  static String get userUpdated => _t('userUpdated');
  static String get updateFailed => _t('updateFailed');
  static String get digitLimitsSaved => _t('digitLimitsSaved');
  static String get deleteUserTitle => _t('deleteUserTitle');
  static String deleteUserBody(String username) =>
      _fmt('deleteUserBody', {'username': username});
  static String get userDeleted => _t('userDeleted');
  static String get userDeleteFailed => _t('userDeleteFailed');
  static String get selectRateSet => _t('selectRateSet');
  static String get createUserFailed => _t('createUserFailed');
  static String get userCreated => _t('userCreated');
  static String userCreatedNamed(String name) =>
      _fmt('userCreatedNamed', {'name': name});

  // Prize / rates
  static String get prizeTableSaved => _t('prizeTableSaved');
  static String get ratesSaved => _t('ratesSaved');

  // Results
  static String get manualResultSaved => _t('manualResultSaved');
  static String get noResultToDelete => _t('noResultToDelete');
  static String get deleteResultTitle => _t('deleteResultTitle');
  static String deleteResultBody(String draw, String date) =>
      _fmt('deleteResultBody', {'draw': draw, 'date': date});
  static String get resultDeleted => _t('resultDeleted');
  static String get resultNotPublished => _t('resultNotPublished');
  static String get resultUpdated => _t('resultUpdated');
  static String get partialResultLoaded => _t('partialResultLoaded');
  static String fetchFailed(Object e) =>
      _fmt('fetchFailed', {'error': e.toString()});
  static String get notSignedIn => _t('notSignedIn');
  static String get resultNotReadyOnServer => _t('resultNotReadyOnServer');
  static String get resultUpdatedFromCloud => _t('resultUpdatedFromCloud');
  static String get resultAlreadyComplete => _t('resultAlreadyComplete');
  static String get liveStreamOpenFailed => _t('liveStreamOpenFailed');
  static String get screenshotFailed => _t('screenshotFailed');
  static String get noResultToShare => _t('noResultToShare');
  static String shareFailed(Object e) =>
      _fmt('shareFailed', {'error': e.toString()});
  static String get shareScreenshot => _t('shareScreenshot');
  static String get shareText => _t('shareText');
  static String get manualEntry => _t('manualEntry');
  static String get deleteResultMenu => _t('deleteResultMenu');
  static String get liveStream => _t('liveStream');
  static String get shareMenu => _t('shareMenu');
  static String get bookingClosedStatus => _t('bookingClosedStatus');
  static String get bookingClosedFallback => _t('bookingClosedFallback');

  // Sales / draw
  static String get salesBlocked => _t('salesBlocked');
  static String get noDrawForScheme => _t('noDrawForScheme');

  // Bills
  static String get deleteBillTitle => _t('deleteBillTitle');
  static String deleteBillBody(int billNo) =>
      _fmt('deleteBillBody', {'billNo': billNo.toString()});
  static String billDeleted(int billNo) =>
      _fmt('billDeleted', {'billNo': billNo.toString()});
  static String get enterValidBillNo => _t('enterValidBillNo');
  static String billNotFound(int billNo) =>
      _fmt('billNotFound', {'billNo': billNo.toString()});
  static String get deleteReceiptTitle => _t('deleteReceiptTitle');
  static String deleteReceiptBody(int billNo) =>
      _fmt('deleteReceiptBody', {'billNo': billNo.toString()});
  static String get allLinesRemoved => _t('allLinesRemoved');
  static String get editNumber => _t('editNumber');
  static String get deleteLine => _t('deleteLine');
  static String get editRowTitle => _t('editRowTitle');
  static String get numberLabel => _t('numberLabel');
  static String get countLabel => _t('countLabel');
  static String get billNotFoundShort => _t('billNotFoundShort');

  // Booking / clipboard
  static String get clipboardEmpty => _t('clipboardEmpty');
  static String get clipboardFormatError => _t('clipboardFormatError');
  static String entriesAdded(int count) =>
      _fmt('entriesAdded', {'count': count.toString()});
  static String entriesImported(int count) =>
      _fmt('entriesImported', {'count': count.toString()});
  static String digitLimitExceeded(String mode, int max, int used) =>
      _fmt('digitLimitExceeded', {
        'mode': mode,
        'max': max.toString(),
        'used': used.toString(),
      });
  static String amountLimitExceeded(double max, double used) => _fmt(
        'amountLimitExceeded',
        {
          'max': max.toStringAsFixed(0),
          'used': used.toStringAsFixed(0),
        },
      );
  static String schemeDrawNotAllowed(String scheme, String draw) =>
      _fmt('schemeDrawNotAllowed', {'scheme': scheme, 'draw': draw});

  // Save dialogs
  static String get billSavedTitle => _t('billSavedTitle');
  static String billNo(int billNo) =>
      _fmt('billNo', {'billNo': billNo.toString()});
  static String get viewBill => _t('viewBill');
  static String get confirmTitle => _t('confirmTitle');
  static String get confirmSaveBill => _t('confirmSaveBill');
  static String totalCount(int count) =>
      _fmt('totalCount', {'count': count.toString()});
  static String totalAmount(String amount) =>
      _fmt('totalAmount', {'amount': amount});
  static String get billNote => _t('billNote');

  // Draw schedule warnings
  static String bookingClosed(String open, String close) =>
      _fmt('bookingClosed', {'open': open, 'close': close});
  static String get pastDrawReceiptBlocked => _t('pastDrawReceiptBlocked');
  static String get bookingClosedEditBlocked => _t('bookingClosedEditBlocked');

  static const Map<AppLanguage, Map<String, String>> _bundle = {
    AppLanguage.en: {
      'cancel': 'Cancel',
      'delete': 'Delete',
      'save': 'Save',
      'ok': 'OK',
      'close': 'Close',
      'languageTitle': 'Select Language',
      'languageChanged': 'Language updated',
      'menuLanguage': 'Language',
      'accountBlocked':
          'Your account is blocked. Please contact admin.',
      'cloudLoginFailed': 'Cloud login failed: {detail}',
      'wrongCredentials': 'Wrong username or password',
      'loginFailed': 'Login failed: {error}',
      'userUpdated': 'User updated',
      'updateFailed': 'Update failed',
      'digitLimitsSaved': 'Digit count limits saved',
      'deleteUserTitle': 'Delete user?',
      'deleteUserBody': 'Delete {username}? This cannot be undone.',
      'userDeleted': 'User deleted',
      'userDeleteFailed':
          'Failed: cannot delete yourself, last ADMIN, or user missing',
      'selectRateSet': 'Please select a Price List / Rate Set',
      'createUserFailed':
          'Failed: check duplicate/empty fields or permissions',
      'userCreated': 'User created successfully',
      'userCreatedNamed': '{name} created — now in List Users',
      'prizeTableSaved':
          'Prize table saved for all draws (DEAR1/LSK3/DEAR6/DEAR8)',
      'ratesSaved': 'Rates saved for all draws (DEAR1/LSK3/DEAR6/DEAR8)',
      'manualResultSaved': 'Manual saved (2nd–5th & compliments locked)',
      'noResultToDelete': 'No saved result to delete',
      'deleteResultTitle': 'Delete result?',
      'deleteResultBody':
          'Delete {draw} result for {date}? This cannot be undone.',
      'resultDeleted': 'Result deleted',
      'resultNotPublished': 'Result not published yet',
      'resultUpdated': 'Result updated',
      'partialResultLoaded': 'Partial result loaded',
      'fetchFailed': 'Fetch failed: {error}',
      'notSignedIn': 'Not signed in',
      'resultNotReadyOnServer': 'Result not ready on server yet',
      'resultUpdatedFromCloud': 'Result updated from cloud',
      'resultAlreadyComplete': 'Result already complete',
      'liveStreamOpenFailed': 'Could not open live stream',
      'screenshotFailed': 'Could not capture screenshot',
      'noResultToShare': 'No result to share',
      'shareFailed': 'Share failed: {error}',
      'shareScreenshot': 'Screenshot',
      'shareText': 'Text message',
      'manualEntry': 'Manual entry',
      'deleteResultMenu': 'Delete result',
      'liveStream': 'Live stream',
      'shareMenu': 'Share',
      'bookingClosedStatus': 'Booking closed',
      'bookingClosedFallback': 'Booking closed',
      'salesBlocked': 'Sales blocked for this user. Contact admin.',
      'noDrawForScheme': 'No draw available for your scheme',
      'deleteBillTitle': 'Delete Bill?',
      'deleteBillBody':
          'Bill {billNo} and all lines will be permanently deleted.',
      'billDeleted': 'Bill {billNo} deleted',
      'enterValidBillNo': 'Enter a valid bill number',
      'billNotFound': 'Bill {billNo} not found',
      'deleteReceiptTitle': 'Delete receipt?',
      'deleteReceiptBody':
          'Bill {billNo} and all lines will be permanently deleted.',
      'allLinesRemoved':
          'All lines removed. Delete receipt to remove bill.',
      'editNumber': 'Edit Number',
      'deleteLine': 'Delete Line',
      'editRowTitle': 'Edit Row',
      'numberLabel': 'Number',
      'countLabel': 'Count',
      'billNotFoundShort': 'Bill not found',
      'clipboardEmpty': 'No data in clipboard',
      'clipboardFormatError': 'Could not understand number/count format',
      'entriesAdded': '{count} entries added',
      'entriesImported': '{count} entries imported',
      'digitLimitExceeded':
          '{mode}-digit count limit exceeded (max {max} · used {used})',
      'amountLimitExceeded':
          'Amount limit exceeded (max {max} · used {used})',
      'schemeDrawNotAllowed':
          'Scheme {scheme} does not allow booking for {draw}',
      'billSavedTitle': 'Your Bill Successfully Saved!',
      'billNo': 'Bill NO - {billNo}',
      'viewBill': 'VIEW BILL',
      'confirmTitle': 'Confirm ?',
      'confirmSaveBill': 'Are you sure to save bill?',
      'totalCount': 'Total Count : {count}',
      'totalAmount': 'Total Amount: {amount}',
      'billNote': 'Bill Note',
      'bookingClosed': 'Booking closed · Open {open} – {close}',
      'pastDrawReceiptBlocked':
          'Cannot edit or delete past draw receipts',
      'bookingClosedEditBlocked':
          'Booking closed — edit and delete are not allowed',
    },
    AppLanguage.ml: {
      'cancel': 'റദ്ദാക്കുക',
      'delete': 'ഇല്ലാതാക്കുക',
      'save': 'സംരക്ഷിക്കുക',
      'ok': 'ശരി',
      'close': 'അടയ്ക്കുക',
      'languageTitle': 'ഭാഷ തിരഞ്ഞെടുക്കുക',
      'languageChanged': 'ഭാഷ മാറ്റി',
      'menuLanguage': 'ഭാഷ',
      'accountBlocked':
          'നിങ്ങളുടെ അക്കൗണ്ട് ബ്ലോക്ക് ചെയ്തിരിക്കുന്നു. അഡ്മിനെ ബന്ധപ്പെടുക.',
      'cloudLoginFailed': 'ക്ലൗഡ് ലോഗിൻ പരാജയപ്പെട്ടു: {detail}',
      'wrongCredentials':
          'ഉപയോക്താവപ്പുറം അല്ലെങ്കിൽ പാസ്‌വേഡ് തെറ്റാണ്',
      'loginFailed': 'ലോഗിൻ പരാജയപ്പെട്ടു: {error}',
      'userUpdated': 'ഉപയോക്താവ് അപ്ഡേറ്റ് ചെയ്തു',
      'updateFailed': 'അപ്ഡേറ്റ് പരാജയപ്പെട്ടു',
      'digitLimitsSaved': 'അക്കം പരിധി സംരക്ഷിച്ചു',
      'deleteUserTitle': 'ഉപയോക്താവിനെ ഇല്ലാതാക്കണോ?',
      'deleteUserBody':
          '{username} ഇല്ലാതാക്കണോ? ഇത് പഴയപടിയാക്കാൻ കഴിയില്ല.',
      'userDeleted': 'ഉപയോക്താവ് ഇല്ലാതാക്കി',
      'userDeleteFailed':
          'പരാജയം: നിങ്ങളെ/അവസാന ADMIN-നെ ഇല്ലാതാക്കാൻ കഴിയില്ല, അല്ലെങ്കിൽ ഉപയോക്താവ് ഇല്ല',
      'selectRateSet': 'പ്രൈസ് ലിസ്റ്റ് / റേറ്റ് സെറ്റ് തിരഞ്ഞെടുക്കുക',
      'createUserFailed':
          'പരാജയം: ഡ്യൂപ്ലിക്കേറ്റ്/ശൂന്യം അല്ലെങ്കിൽ അനുവാദമില്ല',
      'userCreated': 'ഉപയോക്താവ് വിജയകരമായി സൃഷ്ടിച്ചു',
      'userCreatedNamed': '{name} സൃഷ്ടിച്ചു — ലിസ്റ്റിൽ കാണാം',
      'prizeTableSaved':
          'എല്ലാ ഡ്രോകൾക്കും പ്രൈസ് ടേബിൾ സംരക്ഷിച്ചു (DEAR1/LSK3/DEAR6/DEAR8)',
      'ratesSaved':
          'എല്ലാ ഡ്രോകൾക്കും റേറ്റ് സംരക്ഷിച്ചു (DEAR1/LSK3/DEAR6/DEAR8)',
      'manualResultSaved':
          'മാനുവൽ സംരക്ഷിച്ചു (2–5 & കോംപ്ലിമെന്റ് ലോക്ക്)',
      'noResultToDelete': 'ഇല്ലാതാക്കാൻ ഫലം ഇല്ല',
      'deleteResultTitle': 'ഫലം ഇല്ലാതാക്കണോ?',
      'deleteResultBody':
          '{draw} ഫലം ({date}) ഇല്ലാതാക്കണോ? ഇത് പഴയപടിയാക്കാൻ കഴിയില്ല.',
      'resultDeleted': 'ഫലം ഇല്ലാതാക്കി',
      'resultNotPublished': 'ഫലം ഇനിയും പ്രസിദ്ധീകരിച്ചിട്ടില്ല',
      'resultUpdated': 'ഫലം അപ്ഡേറ്റ് ചെയ്തു',
      'partialResultLoaded': 'ഭാഗിക ഫലം ലോഡ് ചെയ്തു',
      'fetchFailed': 'ലോഡ് പരാജയപ്പെട്ടു: {error}',
      'notSignedIn': 'ലോഗിൻ ചെയ്തിട്ടില്ല',
      'resultNotReadyOnServer': 'സർവറിൽ ഫലം തയ്യാറല്ല',
      'resultUpdatedFromCloud': 'ക്ലൗഡിൽ നിന്ന് ഫലം അപ്ഡേറ്റ് ചെയ്തു',
      'resultAlreadyComplete': 'ഫലം ഇതിനകം പൂർണ്ണമാണ്',
      'liveStreamOpenFailed': 'ലൈവ് സ്ട്രീം തുറക്കാൻ കഴിഞ്ഞില്ല',
      'screenshotFailed': 'സ്ക്രീൻഷോട്ട് എടുക്കാൻ കഴിഞ്ഞില്ല',
      'noResultToShare': 'പങ്കിടാൻ ഫലം ഇല്ല',
      'shareFailed': 'പങ്കിടൽ പരാജയപ്പെട്ടു: {error}',
      'shareScreenshot': 'സ്ക്രീൻഷോട്ട്',
      'shareText': 'ടെക്സ്റ്റ് സന്ദേശം',
      'manualEntry': 'മാനുവൽ എൻട്രി',
      'deleteResultMenu': 'ഫലം ഇല്ലാതാക്കുക',
      'liveStream': 'ലൈവ് സ്ട്രീം',
      'shareMenu': 'പങ്കിടുക',
      'bookingClosedStatus': 'ബുക്കിങ് അടച്ചു',
      'bookingClosedFallback': 'ബുക്കിങ് അടച്ചു',
      'salesBlocked':
          'ഈ ഉപയോക്താവിന് സേൽസ് ബ്ലോക്ക്. അഡ്മിനെ ബന്ധപ്പെടുക.',
      'noDrawForScheme': 'നിങ്ങളുടെ സ്കീമിന് ഡ്രോ ലഭ്യമല്ല',
      'deleteBillTitle': 'ബിൽ ഇല്ലാതാക്കണോ?',
      'deleteBillBody':
          'ബിൽ {billNo}-ന്റെ എല്ലാ വരികളും ശാശ്വതമായി ഇല്ലാതാകും.',
      'billDeleted': 'ബിൽ {billNo} ഇല്ലാതാക്കി',
      'enterValidBillNo': 'ശരിയായ ബിൽ നമ്പർ നൽകുക',
      'billNotFound': 'ബിൽ {billNo} കണ്ടെത്തിയില്ല',
      'deleteReceiptTitle': 'റസീറ്റ് ഇല്ലാതാക്കണോ?',
      'deleteReceiptBody':
          'ബിൽ {billNo}-ന്റെ എല്ലാ വരികളും ശാശ്വതമായി ഇല്ലാതാകും.',
      'allLinesRemoved':
          'എല്ലാ വരികളും നീക്കി. ബിൽ ഇല്ലാതാക്കാൻ റസീറ്റ് ഡിലീറ്റ് ചെയ്യുക',
      'editNumber': 'നമ്പർ എഡിറ്റ്',
      'deleteLine': 'വരി ഇല്ലാതാക്കുക',
      'editRowTitle': 'വരി എഡിറ്റ്',
      'numberLabel': 'നമ്പർ',
      'countLabel': 'എണ്ണം',
      'billNotFoundShort': 'ബിൽ കണ്ടെത്തിയില്ല',
      'clipboardEmpty': 'ക്ലിപ്പ്ബോർഡിൽ ഡാറ്റ ഇല്ല',
      'clipboardFormatError': 'നമ്പർ/എണ്ണം ഫോർമാറ്റ് മനസ്സിലായില്ല',
      'entriesAdded': '{count} എൻട്രികൾ ചേർത്തു',
      'entriesImported': '{count} എൻട്രികൾ ഇറക്കുമതി ചെയ്തു',
      'digitLimitExceeded':
          '{mode}-അക്കം പരിധി കവിഞ്ഞു (പരമാവധി {max} · ഉപയോഗിച്ചത് {used})',
      'amountLimitExceeded':
          'തുക പരിധി കവിഞ്ഞു (പരമാവധി {max} · ഉപയോഗിച്ചത് {used})',
      'schemeDrawNotAllowed':
          'സ്കീം {scheme} ഡ്രോ {draw} ബുക്കിങ് അനുവദിക്കില്ല',
      'billSavedTitle': 'നിങ്ങളുടെ ബിൽ വിജയകരമായി സംരക്ഷിച്ചു!',
      'billNo': 'ബിൽ നമ്പർ - {billNo}',
      'viewBill': 'ബിൽ കാണുക',
      'confirmTitle': 'സ്ഥിരീകരിക്കണോ?',
      'confirmSaveBill': 'ബിൽ സംരക്ഷിക്കണമെന്ന് ഉറപ്പാണോ?',
      'totalCount': 'മൊത്തം എണ്ണം : {count}',
      'totalAmount': 'മൊത്തം തുക: {amount}',
      'billNote': 'ബിൽ നോട്ട്',
      'bookingClosed': 'ബുക്കിങ് അടച്ചു · തുറക്കുന്നത് {open} – {close}',
      'pastDrawReceiptBlocked':
          'കഴിഞ്ഞ ഡ്രോ റസീറ്റുകൾ എഡിറ്റ്/ഡിലീറ്റ് ചെയ്യാൻ പറ്റില്ല',
      'bookingClosedEditBlocked':
          'ബുക്കിങ് അടച്ചു — എഡിറ്റ്/ഡിലീറ്റ് അനുവദനീയമല്ല',
    },
    AppLanguage.ta: {
      'cancel': 'ரத்து செய்',
      'delete': 'நீக்கு',
      'save': 'சேமி',
      'ok': 'சரி',
      'close': 'மூடு',
      'languageTitle': 'மொழியைத் தேர்ந்தெடுக்கவும்',
      'languageChanged': 'மொழி மாற்றப்பட்டது',
      'menuLanguage': 'மொழி',
      'accountBlocked':
          'உங்கள் கணக்கு தடுக்கப்பட்டுள்ளது. நிர்வாகியை தொடர்பு கொள்ளவும்.',
      'cloudLoginFailed': 'க்ளவுட் உள்நுழைவு தோல்வி: {detail}',
      'wrongCredentials': 'பயனர்பெயர் அல்லது கடவுச்சொல் தவறு',
      'loginFailed': 'உள்நுழைவு தோல்வி: {error}',
      'userUpdated': 'பயனர் புதுப்பிக்கப்பட்டது',
      'updateFailed': 'புதுப்பிப்பு தோல்வி',
      'digitLimitsSaved': 'எண் வரம்பு சேமிக்கப்பட்டது',
      'deleteUserTitle': 'பயனரை நீக்கவா?',
      'deleteUserBody':
          '{username} நீக்கவா? இதை மீட்டெடுக்க முடியாது.',
      'userDeleted': 'பயனர் நீக்கப்பட்டது',
      'userDeleteFailed':
          'தோல்வி: உங்களை/கடைசி ADMIN-ஐ நீக்க முடியாது, அல்லது பயனர் இல்லை',
      'selectRateSet': 'விலை பட்டியல் / ரேட் செட் தேர்ந்தெடுக்கவும்',
      'createUserFailed':
          'தோல்வி: நகல்/வெற்று புலங்கள் அல்லது அனுமதி சரிபார்க்கவும்',
      'userCreated': 'பயனர் வெற்றிகரமாக உருவாக்கப்பட்டது',
      'userCreatedNamed': '{name} உருவாக்கப்பட்டது — பட்டியலில் உள்ளது',
      'prizeTableSaved':
          'அனைத்து டிராக்களுக்கும் பரிசு அட்டவணை சேமிக்கப்பட்டது',
      'ratesSaved': 'அனைத்து டிராக்களுக்கும் ரேட் சேமிக்கப்பட்டது',
      'manualResultSaved':
          'கைமுறை சேமிக்கப்பட்டது (2–5 & compliments பூட்டப்பட்டது)',
      'noResultToDelete': 'நீக்க முடிஞ்ச முடிவு இல்லை',
      'deleteResultTitle': 'முடிவை நீக்கவா?',
      'deleteResultBody':
          '{draw} முடிவு ({date}) நீக்கவா? இதை மீட்டெடுக்க முடியாது.',
      'resultDeleted': 'முடிவு நீக்கப்பட்டது',
      'resultNotPublished': 'முடிவு இன்னும் வெளியிடப்படவில்லை',
      'resultUpdated': 'முடிவு புதுப்பிக்கப்பட்டது',
      'partialResultLoaded': 'பகுதி முடிவு ஏற்றப்பட்டது',
      'fetchFailed': 'ஏற்றுதல் தோல்வி: {error}',
      'notSignedIn': 'உள்நுழையவில்லை',
      'resultNotReadyOnServer': 'சர்வரில் முடிவு தயாராகவில்லை',
      'resultUpdatedFromCloud': 'க்ளவுடிலிருந்து முடிவு புதுப்பிக்கப்பட்டது',
      'resultAlreadyComplete': 'முடிவு ஏற்கனவே முழுமையாக உள்ளது',
      'liveStreamOpenFailed': 'நேரலை ஸ்ட்ரீம் திறக்க முடியவில்லை',
      'screenshotFailed': 'ஸ்கிரீன்ஷாட் எடுக்க முடியவில்லை',
      'noResultToShare': 'பகிர முடிவு இல்லை',
      'shareFailed': 'பகிர்தல் தோல்வி: {error}',
      'shareScreenshot': 'ஸ்கிரீன்ஷாட்',
      'shareText': 'உரை செய்தி',
      'manualEntry': 'கைமுறை நுழைவு',
      'deleteResultMenu': 'முடிவை நீக்கு',
      'liveStream': 'நேரலை',
      'shareMenu': 'பகிர்',
      'bookingClosedStatus': 'புக்கிங் மூடப்பட்டது',
      'bookingClosedFallback': 'புக்கிங் மூடப்பட்டது',
      'salesBlocked':
          'இந்த பயனருக்கு விற்பனை தடுக்கப்பட்டுள்ளது. நிர்வாகியை தொடர்பு கொள்ளவும்.',
      'noDrawForScheme': 'உங்கள் திட்டத்திற்கு டிரா இல்லை',
      'deleteBillTitle': 'பில் நீக்கவா?',
      'deleteBillBody':
          'பில் {billNo} மற்றும் அனைத்து வரிகளும் நிரந்தரமாக நீக்கப்படும்.',
      'billDeleted': 'பில் {billNo} நீக்கப்பட்டது',
      'enterValidBillNo': 'சரியான பில் எண்ணை உள்ளிடவும்',
      'billNotFound': 'பில் {billNo} கிடைக்கவில்லை',
      'deleteReceiptTitle': 'ரசீது நீக்கவா?',
      'deleteReceiptBody':
          'பில் {billNo} மற்றும் அனைத்து வரிகளும் நிரந்தரமாக நீக்கப்படும்.',
      'allLinesRemoved':
          'அனைத்து வரிகளும் நீக்கப்பட்டன. பில்லை நீக்க ரசீதை நீக்கவும்',
      'editNumber': 'எண்ணை திருத்து',
      'deleteLine': 'வரி நீக்கு',
      'editRowTitle': 'வரி திருத்து',
      'numberLabel': 'எண்',
      'countLabel': 'எண்ணிக்கை',
      'billNotFoundShort': 'பில் கிடைக்கவில்லை',
      'clipboardEmpty': 'கிளிப்ப்போர்டில் தரவு இல்லை',
      'clipboardFormatError': 'எண்/எண்ணிக்கை வடிவம் புரியவில்லை',
      'entriesAdded': '{count} நுழைவுகள் சேர்க்கப்பட்டன',
      'entriesImported': '{count} நுழைவுகள் இறக்குமதி செய்யப்பட்டன',
      'digitLimitExceeded':
          '{mode}-இலக்க எண்ணிக்கை வரம்பு மீறியது (அதிகபட்சம் {max} · பயன்படுத்தியது {used})',
      'amountLimitExceeded':
          'தொகை வரம்பு மீறியது (அதிகபட்சம் {max} · பயன்படுத்தியது {used})',
      'schemeDrawNotAllowed':
          'திட்டம் {scheme} டிரா {draw} புக்கிங் அனுமதிக்கவில்லை',
      'billSavedTitle': 'உங்கள் பில் வெற்றிகரமாக சேமிக்கப்பட்டது!',
      'billNo': 'பில் எண் - {billNo}',
      'viewBill': 'பில் பார்',
      'confirmTitle': 'உறுதிப்படுத்தவா?',
      'confirmSaveBill': 'பில் சேமிக்க வேண்டுமா?',
      'totalCount': 'மொத்த எண்ணிக்கை : {count}',
      'totalAmount': 'மொத்த தொகை: {amount}',
      'billNote': 'பில் குறிப்பு',
      'bookingClosed': 'புக்கிங் மூடப்பட்டது · திறக்கும் நேரம் {open} – {close}',
      'pastDrawReceiptBlocked':
          'கடந்த டிரா ரசீதுகளை திருத்த/நீக்க முடியாது',
      'bookingClosedEditBlocked':
          'புக்கிங் மூடப்பட்டது — திருத்த/நீக்க அனுமதி இல்லை',
    },
  };
}
