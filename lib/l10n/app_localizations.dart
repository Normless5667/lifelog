import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Life Assistant'**
  String get appTitle;

  /// No description provided for @tabToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get tabToday;

  /// No description provided for @tabSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get tabSchedule;

  /// No description provided for @tabDiet.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get tabDiet;

  /// No description provided for @tabWorkout.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get tabWorkout;

  /// No description provided for @tabAi.
  ///
  /// In en, this message translates to:
  /// **'AI Coach'**
  String get tabAi;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get commonGotIt;

  /// No description provided for @commonSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get commonSkip;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get commonToday;

  /// No description provided for @commonYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get commonYesterday;

  /// No description provided for @commonTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get commonTomorrow;

  /// No description provided for @commonErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonErrorTitle;

  /// No description provided for @commonGoSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get commonGoSettings;

  /// No description provided for @commonSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully'**
  String get commonSavedToast;

  /// No description provided for @commonDeleteRecordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this record?'**
  String get commonDeleteRecordConfirm;

  /// No description provided for @commonAtLeastOneField.
  ///
  /// In en, this message translates to:
  /// **'Please fill in at least one field'**
  String get commonAtLeastOneField;

  /// No description provided for @commonInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid number'**
  String get commonInvalidNumber;

  /// No description provided for @commonRangeError.
  ///
  /// In en, this message translates to:
  /// **'Range {min}-{max}'**
  String commonRangeError(int min, int max);

  /// No description provided for @weekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySun;

  /// No description provided for @mealBreakfast.
  ///
  /// In en, this message translates to:
  /// **'Breakfast'**
  String get mealBreakfast;

  /// No description provided for @mealLunch.
  ///
  /// In en, this message translates to:
  /// **'Lunch'**
  String get mealLunch;

  /// No description provided for @mealDinner.
  ///
  /// In en, this message translates to:
  /// **'Dinner'**
  String get mealDinner;

  /// No description provided for @mealSnack.
  ///
  /// In en, this message translates to:
  /// **'Snack'**
  String get mealSnack;

  /// No description provided for @homeQuickRecord.
  ///
  /// In en, this message translates to:
  /// **'Quick Log'**
  String get homeQuickRecord;

  /// No description provided for @homeQuickDiet.
  ///
  /// In en, this message translates to:
  /// **'Log a Meal / Scan Food'**
  String get homeQuickDiet;

  /// No description provided for @homeQuickWorkout.
  ///
  /// In en, this message translates to:
  /// **'Start Workout / Log Cardio'**
  String get homeQuickWorkout;

  /// No description provided for @homeQuickWeight.
  ///
  /// In en, this message translates to:
  /// **'Log Today\'s Weight'**
  String get homeQuickWeight;

  /// No description provided for @homeQuickBus.
  ///
  /// In en, this message translates to:
  /// **'Bus Board & Switch Stop'**
  String get homeQuickBus;

  /// No description provided for @homeHeroSnapMeal.
  ///
  /// In en, this message translates to:
  /// **'Scan Food'**
  String get homeHeroSnapMeal;

  /// No description provided for @homeHeroStartWorkout.
  ///
  /// In en, this message translates to:
  /// **'Start Workout'**
  String get homeHeroStartWorkout;

  /// No description provided for @homeHeroLogWeight.
  ///
  /// In en, this message translates to:
  /// **'Log Weight'**
  String get homeHeroLogWeight;

  /// No description provided for @homeHeroAiCoach.
  ///
  /// In en, this message translates to:
  /// **'AI Plan'**
  String get homeHeroAiCoach;

  /// No description provided for @homeQuickLogHint.
  ///
  /// In en, this message translates to:
  /// **'Type what you ate (e.g. beef noodle soup with an egg)…'**
  String get homeQuickLogHint;

  /// No description provided for @homeAiQuickLog.
  ///
  /// In en, this message translates to:
  /// **'AI Quick Log'**
  String get homeAiQuickLog;

  /// No description provided for @homeStreakDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0-day streak} =1{1-day streak} other{{count}-day streak}}'**
  String homeStreakDays(int count);

  /// No description provided for @homeStreakKeepGoing.
  ///
  /// In en, this message translates to:
  /// **'Keep up the great momentum!'**
  String get homeStreakKeepGoing;

  /// No description provided for @homeStreakStartHint.
  ///
  /// In en, this message translates to:
  /// **'Log a meal or workout to start your streak'**
  String get homeStreakStartHint;

  /// No description provided for @homeProfilePromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete Your Fitness Profile'**
  String get homeProfilePromptTitle;

  /// No description provided for @homeProfilePromptSub.
  ///
  /// In en, this message translates to:
  /// **'Take 30s to set height, goal & equipment for dynamic TDEE'**
  String get homeProfilePromptSub;

  /// No description provided for @homeTodayClassesWeek.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Classes · Week {week}'**
  String homeTodayClassesWeek(int week);

  /// No description provided for @homeTodayClasses.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Classes'**
  String get homeTodayClasses;

  /// No description provided for @homeAllSchedule.
  ///
  /// In en, this message translates to:
  /// **'Full Schedule'**
  String get homeAllSchedule;

  /// No description provided for @homeNoClassesToday.
  ///
  /// In en, this message translates to:
  /// **'No classes today — rest up or hit a workout!'**
  String get homeNoClassesToday;

  /// No description provided for @homeTodayWorkoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Workout & Cardio'**
  String get homeTodayWorkoutTitle;

  /// No description provided for @homeGoWorkout.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get homeGoWorkout;

  /// No description provided for @homeNoWorkoutToday.
  ///
  /// In en, this message translates to:
  /// **'No strength or cardio logged today'**
  String get homeNoWorkoutToday;

  /// No description provided for @homeNoWorkoutSub.
  ///
  /// In en, this message translates to:
  /// **'Workout burn automatically increases your daily calorie budget'**
  String get homeNoWorkoutSub;

  /// No description provided for @homeStartWorkoutBtn.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get homeStartWorkoutBtn;

  /// No description provided for @homeStrengthSummary.
  ///
  /// In en, this message translates to:
  /// **'Strength {count}x ({sets} sets)'**
  String homeStrengthSummary(int count, int sets);

  /// No description provided for @homeCardioSummary.
  ///
  /// In en, this message translates to:
  /// **'Cardio {mins} min'**
  String homeCardioSummary(String mins);

  /// No description provided for @homeWorkoutBurnSummary.
  ///
  /// In en, this message translates to:
  /// **'Total activity burn +{kcal} kcal'**
  String homeWorkoutBurnSummary(String kcal);

  /// No description provided for @homeBodyStatus.
  ///
  /// In en, this message translates to:
  /// **'Body Status'**
  String get homeBodyStatus;

  /// No description provided for @homeWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Weight {weight} kg'**
  String homeWeightLabel(String weight);

  /// No description provided for @homeWeightNotLogged.
  ///
  /// In en, this message translates to:
  /// **'Weight not logged yet'**
  String get homeWeightNotLogged;

  /// No description provided for @homeBodyTargetSub.
  ///
  /// In en, this message translates to:
  /// **'Goal: {goal} · Target {kcal} kcal/d · P {protein}g'**
  String homeBodyTargetSub(String goal, String kcal, String protein);

  /// No description provided for @homeLogBodyBtn.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get homeLogBodyBtn;

  /// No description provided for @homeAiCoachBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask Your AI Coach'**
  String get homeAiCoachBannerTitle;

  /// No description provided for @homeAiCoachBannerSub.
  ///
  /// In en, this message translates to:
  /// **'Meal advice, workout splits & weekly review based on your logs'**
  String get homeAiCoachBannerSub;

  /// No description provided for @stepTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Steps: {steps} / {goal}'**
  String stepTitle(int steps, int goal);

  /// No description provided for @stepUnsupported.
  ///
  /// In en, this message translates to:
  /// **'No hardware step sensor on this device (log walking/running in Workout)'**
  String get stepUnsupported;

  /// No description provided for @stepPermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Grant Physical Activity permission to read the hardware pedometer'**
  String get stepPermissionNeeded;

  /// No description provided for @stepBurnedSummary.
  ///
  /// In en, this message translates to:
  /// **'Step burn +{kcal} kcal (added to today\'s calorie budget)'**
  String stepBurnedSummary(String kcal);

  /// No description provided for @stepAuthorize.
  ///
  /// In en, this message translates to:
  /// **'Grant Access'**
  String get stepAuthorize;

  /// No description provided for @weatherClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get weatherClear;

  /// No description provided for @weatherCloudy.
  ///
  /// In en, this message translates to:
  /// **'Cloudy'**
  String get weatherCloudy;

  /// No description provided for @weatherFoggy.
  ///
  /// In en, this message translates to:
  /// **'Foggy'**
  String get weatherFoggy;

  /// No description provided for @weatherRainy.
  ///
  /// In en, this message translates to:
  /// **'Rainy'**
  String get weatherRainy;

  /// No description provided for @weatherSnowy.
  ///
  /// In en, this message translates to:
  /// **'Snowy'**
  String get weatherSnowy;

  /// No description provided for @weatherShowers.
  ///
  /// In en, this message translates to:
  /// **'Showers'**
  String get weatherShowers;

  /// No description provided for @weatherThunderstorm.
  ///
  /// In en, this message translates to:
  /// **'Thunderstorm'**
  String get weatherThunderstorm;

  /// No description provided for @weatherTipRain.
  ///
  /// In en, this message translates to:
  /// **'Bring an umbrella'**
  String get weatherTipRain;

  /// No description provided for @weatherTipHot.
  ///
  /// In en, this message translates to:
  /// **'Stay hydrated'**
  String get weatherTipHot;

  /// No description provided for @weatherTipGreat.
  ///
  /// In en, this message translates to:
  /// **'Great for outdoor activity'**
  String get weatherTipGreat;

  /// No description provided for @weatherCompactSub.
  ///
  /// In en, this message translates to:
  /// **'{min}~{max}°C · Precip {precip}% · {tip}'**
  String weatherCompactSub(String min, String max, String precip, String tip);

  /// No description provided for @weatherSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Weather Location & City (Proxy-Safe)'**
  String get weatherSheetTitle;

  /// No description provided for @weatherAutoLocate.
  ///
  /// In en, this message translates to:
  /// **'Auto GPS Location (6h cache)'**
  String get weatherAutoLocate;

  /// No description provided for @weatherSearchCity.
  ///
  /// In en, this message translates to:
  /// **'More Cities in Settings'**
  String get weatherSearchCity;

  /// No description provided for @dietRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get dietRemaining;

  /// No description provided for @dietExceeded.
  ///
  /// In en, this message translates to:
  /// **'Over by'**
  String get dietExceeded;

  /// No description provided for @dietConsumedTarget.
  ///
  /// In en, this message translates to:
  /// **'Consumed {consumed} / Target {target} kcal'**
  String dietConsumedTarget(String consumed, String target);

  /// No description provided for @dietEstimatedHint.
  ///
  /// In en, this message translates to:
  /// **'(Default estimate — tap weight icon to set profile)'**
  String get dietEstimatedHint;

  /// No description provided for @dietProtein.
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get dietProtein;

  /// No description provided for @dietCarbs.
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get dietCarbs;

  /// No description provided for @dietFat.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get dietFat;

  /// No description provided for @dietBmr.
  ///
  /// In en, this message translates to:
  /// **'BMR'**
  String get dietBmr;

  /// No description provided for @dietTrainingBurn.
  ///
  /// In en, this message translates to:
  /// **'Workout Burn'**
  String get dietTrainingBurn;

  /// No description provided for @dietTodayIntake.
  ///
  /// In en, this message translates to:
  /// **'Consumed'**
  String get dietTodayIntake;

  /// No description provided for @dietSurplus.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get dietSurplus;

  /// No description provided for @dietScanFood.
  ///
  /// In en, this message translates to:
  /// **'Scan Food'**
  String get dietScanFood;

  /// No description provided for @dietPickGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get dietPickGallery;

  /// No description provided for @dietAiTextEstimate.
  ///
  /// In en, this message translates to:
  /// **'AI Text'**
  String get dietAiTextEstimate;

  /// No description provided for @dietManualAdd.
  ///
  /// In en, this message translates to:
  /// **'Log Meal'**
  String get dietManualAdd;

  /// No description provided for @dietEmptyMealHint.
  ///
  /// In en, this message translates to:
  /// **'No {meal} logged yet — tap to add or scan food above'**
  String dietEmptyMealHint(String meal);

  /// No description provided for @dietDeleteMealConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String dietDeleteMealConfirm(String name);

  /// No description provided for @dietAiAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'AI is analyzing food & calories…'**
  String get dietAiAnalyzing;

  /// No description provided for @dietCameraError.
  ///
  /// In en, this message translates to:
  /// **'Unable to open camera/gallery: {error}'**
  String dietCameraError(String error);

  /// No description provided for @dietPhotoHintTitle.
  ///
  /// In en, this message translates to:
  /// **'Analyze Food Photo with AI'**
  String get dietPhotoHintTitle;

  /// No description provided for @dietPhotoHintLabel.
  ///
  /// In en, this message translates to:
  /// **'Optional notes'**
  String get dietPhotoHintLabel;

  /// No description provided for @dietPhotoHintPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. half bowl of rice, skinless chicken leg, less oil'**
  String get dietPhotoHintPlaceholder;

  /// No description provided for @dietStartAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get dietStartAnalyze;

  /// No description provided for @dietTextEstimateTitle.
  ///
  /// In en, this message translates to:
  /// **'Estimate Calories from Text'**
  String get dietTextEstimateTitle;

  /// No description provided for @dietTextEstimateHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what you ate, e.g.:\nA bowl of beef noodle soup with a braised egg'**
  String get dietTextEstimateHint;

  /// No description provided for @dietEstimateBtn.
  ///
  /// In en, this message translates to:
  /// **'Estimate'**
  String get dietEstimateBtn;

  /// No description provided for @foodConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Estimate (Editable)'**
  String get foodConfirmTitle;

  /// No description provided for @foodConfirmName.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get foodConfirmName;

  /// No description provided for @foodConfirmAmount.
  ///
  /// In en, this message translates to:
  /// **'Portion'**
  String get foodConfirmAmount;

  /// No description provided for @foodConfirmKcal.
  ///
  /// In en, this message translates to:
  /// **'Calories kcal'**
  String get foodConfirmKcal;

  /// No description provided for @foodConfirmProtein.
  ///
  /// In en, this message translates to:
  /// **'Protein g'**
  String get foodConfirmProtein;

  /// No description provided for @foodConfirmCarbs.
  ///
  /// In en, this message translates to:
  /// **'Carbs g'**
  String get foodConfirmCarbs;

  /// No description provided for @foodConfirmFat.
  ///
  /// In en, this message translates to:
  /// **'Fat g'**
  String get foodConfirmFat;

  /// No description provided for @foodConfirmSaveBtn.
  ///
  /// In en, this message translates to:
  /// **'Add to Today\'s Diet'**
  String get foodConfirmSaveBtn;

  /// No description provided for @mealEditAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Log a Meal'**
  String get mealEditAddTitle;

  /// No description provided for @mealEditUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Meal'**
  String get mealEditUpdateTitle;

  /// No description provided for @mealEditTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Meal'**
  String get mealEditTypeLabel;

  /// No description provided for @mealEditNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Food Name *'**
  String get mealEditNameLabel;

  /// No description provided for @mealEditNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a food name'**
  String get mealEditNameRequired;

  /// No description provided for @mealEditAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Portion (e.g. 1 bowl / 200g)'**
  String get mealEditAmountLabel;

  /// No description provided for @mealEditKcalLabel.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get mealEditKcalLabel;

  /// No description provided for @busHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Bus · {stop}'**
  String busHomeTitle(String stop);

  /// No description provided for @busHomeNextCountdown.
  ///
  /// In en, this message translates to:
  /// **'{dir} · Next {time} (in {mins} min)'**
  String busHomeNextCountdown(String dir, String time, int mins);

  /// No description provided for @busHomeEndedToday.
  ///
  /// In en, this message translates to:
  /// **'Service ended today (First bus tomorrow {time})'**
  String busHomeEndedToday(String time);

  /// No description provided for @busHomeWeekend.
  ///
  /// In en, this message translates to:
  /// **'Weekend (Runs Mon–Fri only)'**
  String get busHomeWeekend;

  /// No description provided for @busBoardTitle.
  ///
  /// In en, this message translates to:
  /// **'Live Bus Board'**
  String get busBoardTitle;

  /// No description provided for @busStopReminderSettings.
  ///
  /// In en, this message translates to:
  /// **'Stop & Reminder Settings'**
  String get busStopReminderSettings;

  /// No description provided for @busRouteActions.
  ///
  /// In en, this message translates to:
  /// **'Route Actions'**
  String get busRouteActions;

  /// No description provided for @busMenuSwitchImport.
  ///
  /// In en, this message translates to:
  /// **'Switch / Import Route'**
  String get busMenuSwitchImport;

  /// No description provided for @busMenuShareJson.
  ///
  /// In en, this message translates to:
  /// **'Share Route JSON'**
  String get busMenuShareJson;

  /// No description provided for @busMenuDownloadTemplate.
  ///
  /// In en, this message translates to:
  /// **'Download JSON Template'**
  String get busMenuDownloadTemplate;

  /// No description provided for @busSwitchImportBtn.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get busSwitchImportBtn;

  /// No description provided for @busMyFavStopLabel.
  ///
  /// In en, this message translates to:
  /// **'My Stop: '**
  String get busMyFavStopLabel;

  /// No description provided for @busReminderBadgeOn.
  ///
  /// In en, this message translates to:
  /// **'Remind {mins}m prior'**
  String busReminderBadgeOn(int mins);

  /// No description provided for @busReminderBadgeOff.
  ///
  /// In en, this message translates to:
  /// **'Reminder off'**
  String get busReminderBadgeOff;

  /// No description provided for @busVibrationSwitchTitle.
  ///
  /// In en, this message translates to:
  /// **'Arrival Vibration Reminder (Mon–Fri)'**
  String get busVibrationSwitchTitle;

  /// No description provided for @busRemindBeforeLabel.
  ///
  /// In en, this message translates to:
  /// **'Remind Before'**
  String get busRemindBeforeLabel;

  /// No description provided for @busRemindMinsOption.
  ///
  /// In en, this message translates to:
  /// **'{mins} min before'**
  String busRemindMinsOption(int mins);

  /// No description provided for @busOutboundSegment.
  ///
  /// In en, this message translates to:
  /// **'Outbound → BUV'**
  String get busOutboundSegment;

  /// No description provided for @busInboundSegment.
  ///
  /// In en, this message translates to:
  /// **'Inbound ← Home'**
  String get busInboundSegment;

  /// No description provided for @busWeekendBanner.
  ///
  /// In en, this message translates to:
  /// **'Weekend today (runs Mon–Fri only) — showing weekday schedule preview'**
  String get busWeekendBanner;

  /// No description provided for @busEndedTodayBanner.
  ///
  /// In en, this message translates to:
  /// **'All trips ended for today · First bus tomorrow {time} ({stop})'**
  String busEndedTodayBanner(String time, String stop);

  /// No description provided for @busStatusImminent.
  ///
  /// In en, this message translates to:
  /// **'Arriving ≤5m'**
  String get busStatusImminent;

  /// No description provided for @busStatusSoon.
  ///
  /// In en, this message translates to:
  /// **'Approaching'**
  String get busStatusSoon;

  /// No description provided for @busStatusUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get busStatusUpcoming;

  /// No description provided for @busStatusDeparted.
  ///
  /// In en, this message translates to:
  /// **'Departed'**
  String get busStatusDeparted;

  /// No description provided for @busStatusEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended Today'**
  String get busStatusEnded;

  /// No description provided for @busNextBadge.
  ///
  /// In en, this message translates to:
  /// **'NEXT'**
  String get busNextBadge;

  /// No description provided for @busDepartedAtStop.
  ///
  /// In en, this message translates to:
  /// **'Passed {stop} at {time}'**
  String busDepartedAtStop(String stop, String time);

  /// No description provided for @busCountdownHoursMinsSecs.
  ///
  /// In en, this message translates to:
  /// **'In {hours}h {mins}m {secs}s'**
  String busCountdownHoursMinsSecs(int hours, String mins, String secs);

  /// No description provided for @busCountdownMinsSecs.
  ///
  /// In en, this message translates to:
  /// **'In {mins}m {secs}s'**
  String busCountdownMinsSecs(String mins, String secs);

  /// No description provided for @busEnRoute.
  ///
  /// In en, this message translates to:
  /// **'En Route'**
  String get busEnRoute;

  /// No description provided for @busWaitingDepart.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get busWaitingDepart;

  /// No description provided for @busArrivingSoon.
  ///
  /// In en, this message translates to:
  /// **'Arriving'**
  String get busArrivingSoon;

  /// No description provided for @busProgressStart.
  ///
  /// In en, this message translates to:
  /// **'Start {time}'**
  String busProgressStart(String time);

  /// No description provided for @busProgressPrev.
  ///
  /// In en, this message translates to:
  /// **'Prev {time}'**
  String busProgressPrev(String time);

  /// No description provided for @busProgressNow.
  ///
  /// In en, this message translates to:
  /// **'Now {time}'**
  String busProgressNow(String time);

  /// No description provided for @busProgressTarget.
  ///
  /// In en, this message translates to:
  /// **'Stop {time}'**
  String busProgressTarget(String time);

  /// No description provided for @busYourFavStopTag.
  ///
  /// In en, this message translates to:
  /// **'← Your Stop'**
  String get busYourFavStopTag;

  /// No description provided for @busFooterTipTitle.
  ///
  /// In en, this message translates to:
  /// **'Tip: Tap any stop inside a card to set it as your favorite stop'**
  String get busFooterTipTitle;

  /// No description provided for @busFooterTipSub.
  ///
  /// In en, this message translates to:
  /// **'Sorted by upcoming departure. ≤5 min alerts with red-orange breathing glow; departed buses sink to the bottom.'**
  String get busFooterTipSub;

  /// No description provided for @busFavStopToast.
  ///
  /// In en, this message translates to:
  /// **'Favorite stop updated to {stop}'**
  String busFavStopToast(String stop);

  /// No description provided for @busSwitchedRouteToast.
  ///
  /// In en, this message translates to:
  /// **'Switched route to: {name}'**
  String busSwitchedRouteToast(String name);

  /// No description provided for @busImportedRouteToast.
  ///
  /// In en, this message translates to:
  /// **'Imported & activated route: {name}'**
  String busImportedRouteToast(String name);

  /// No description provided for @busValidationFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Route Validation Failed'**
  String get busValidationFailedTitle;

  /// No description provided for @busSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch or Manage Bus Routes'**
  String get busSheetTitle;

  /// No description provided for @busDownloadTemplateBtn.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get busDownloadTemplateBtn;

  /// No description provided for @busBadgeBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get busBadgeBuiltin;

  /// No description provided for @busBadgeImported.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get busBadgeImported;

  /// No description provided for @busBadgeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get busBadgeCustom;

  /// No description provided for @busStopsCountSub.
  ///
  /// In en, this message translates to:
  /// **'Outbound {outCount} stops · Inbound {inCount} stops'**
  String busStopsCountSub(int outCount, int inCount);

  /// No description provided for @busDeleteRouteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete route \"{name}\"?'**
  String busDeleteRouteConfirm(String name);

  /// No description provided for @busManualCreateBtn.
  ///
  /// In en, this message translates to:
  /// **'Create Route'**
  String get busManualCreateBtn;

  /// No description provided for @busImportJsonBtn.
  ///
  /// In en, this message translates to:
  /// **'Import JSON'**
  String get busImportJsonBtn;

  /// No description provided for @busCustomDialogCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Custom Bus Route'**
  String get busCustomDialogCreateTitle;

  /// No description provided for @busCustomDialogEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Bus Route'**
  String get busCustomDialogEditTitle;

  /// No description provided for @busCustomRouteNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Route Name *'**
  String get busCustomRouteNameLabel;

  /// No description provided for @busCustomSchoolLabel.
  ///
  /// In en, this message translates to:
  /// **'School / Organization (Optional)'**
  String get busCustomSchoolLabel;

  /// No description provided for @busCustomOutboundHint.
  ///
  /// In en, this message translates to:
  /// **'Outbound stops & times (one per line: Stop Name: 07:30, 09:30)'**
  String get busCustomOutboundHint;

  /// No description provided for @busCustomInboundHint.
  ///
  /// In en, this message translates to:
  /// **'Inbound stops & times (one per line: Stop Name: 12:00, 17:30)'**
  String get busCustomInboundHint;

  /// No description provided for @busCustomValidateSaveBtn.
  ///
  /// In en, this message translates to:
  /// **'Validate & Save'**
  String get busCustomValidateSaveBtn;

  /// No description provided for @scheduleWeekTitle.
  ///
  /// In en, this message translates to:
  /// **'Week {week}'**
  String scheduleWeekTitle(int week);

  /// No description provided for @scheduleCurrentWeek.
  ///
  /// In en, this message translates to:
  /// **'Current Week'**
  String get scheduleCurrentWeek;

  /// No description provided for @scheduleBackToCurrent.
  ///
  /// In en, this message translates to:
  /// **'Tap for Current Week'**
  String get scheduleBackToCurrent;

  /// No description provided for @scheduleImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Schedule'**
  String get scheduleImportTitle;

  /// No description provided for @scheduleImportSub.
  ///
  /// In en, this message translates to:
  /// **'Import from screenshot, camera photo, or pasted course text'**
  String get scheduleImportSub;

  /// No description provided for @scheduleImportPresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Load Default BUV Schedule'**
  String get scheduleImportPresetTitle;

  /// No description provided for @scheduleImportPresetSub.
  ///
  /// In en, this message translates to:
  /// **'Database Principles / Machine Learning / UX Design (Mon–Fri)'**
  String get scheduleImportPresetSub;

  /// No description provided for @scheduleImportGalleryTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick Schedule Screenshot (AI)'**
  String get scheduleImportGalleryTitle;

  /// No description provided for @scheduleImportGallerySub.
  ///
  /// In en, this message translates to:
  /// **'Extract all courses automatically from a timetable screenshot'**
  String get scheduleImportGallerySub;

  /// No description provided for @scheduleImportCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan Schedule with Camera'**
  String get scheduleImportCameraTitle;

  /// No description provided for @scheduleImportCameraSub.
  ///
  /// In en, this message translates to:
  /// **'Take a photo of your screen or printed schedule'**
  String get scheduleImportCameraSub;

  /// No description provided for @scheduleImportTextTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste Course Text / JSON'**
  String get scheduleImportTextTitle;

  /// No description provided for @scheduleImportTextSub.
  ///
  /// In en, this message translates to:
  /// **'Paste course list text and let AI parse it'**
  String get scheduleImportTextSub;

  /// No description provided for @schedulePasteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste Schedule Text'**
  String get schedulePasteDialogTitle;

  /// No description provided for @schedulePasteDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Paste course text from your school portal, e.g.:\nDatabase Principles Mon 1-3 Weeks 1-16 E.3-8'**
  String get schedulePasteDialogHint;

  /// No description provided for @scheduleAiParseBtn.
  ///
  /// In en, this message translates to:
  /// **'AI Parse'**
  String get scheduleAiParseBtn;

  /// No description provided for @scheduleAiParsing.
  ///
  /// In en, this message translates to:
  /// **'AI is extracting all courses…'**
  String get scheduleAiParsing;

  /// No description provided for @scheduleConfirmImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Found {count} courses (select to import)'**
  String scheduleConfirmImportTitle(int count);

  /// No description provided for @scheduleReplaceAllSwitch.
  ///
  /// In en, this message translates to:
  /// **'Clear existing courses before importing'**
  String get scheduleReplaceAllSwitch;

  /// No description provided for @scheduleWeekEvery.
  ///
  /// In en, this message translates to:
  /// **'Every week'**
  String get scheduleWeekEvery;

  /// No description provided for @scheduleWeekOdd.
  ///
  /// In en, this message translates to:
  /// **'Odd weeks'**
  String get scheduleWeekOdd;

  /// No description provided for @scheduleWeekEven.
  ///
  /// In en, this message translates to:
  /// **'Even weeks'**
  String get scheduleWeekEven;

  /// No description provided for @scheduleCourseImportSub.
  ///
  /// In en, this message translates to:
  /// **'{weekday} Sec {start}-{end} · Wk {startWeek}-{endWeek} ({weekType})'**
  String scheduleCourseImportSub(
    String weekday,
    int start,
    int end,
    int startWeek,
    int endWeek,
    String weekType,
  );

  /// No description provided for @scheduleConfirmImportBtn.
  ///
  /// In en, this message translates to:
  /// **'Confirm Import'**
  String get scheduleConfirmImportBtn;

  /// No description provided for @scheduleImportedToast.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} courses'**
  String scheduleImportedToast(int count);

  /// No description provided for @scheduleSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule & Class Reminders'**
  String get scheduleSettingsTitle;

  /// No description provided for @scheduleColorOsWarnTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Permission May Be Restricted'**
  String get scheduleColorOsWarnTitle;

  /// No description provided for @scheduleColorOsWarnSub.
  ///
  /// In en, this message translates to:
  /// **'Open system notification settings and enable High Importance, Banner & Vibration for class reminders.'**
  String get scheduleColorOsWarnSub;

  /// No description provided for @scheduleOpenChannelSettingsBtn.
  ///
  /// In en, this message translates to:
  /// **'Enable High Priority & Vibration'**
  String get scheduleOpenChannelSettingsBtn;

  /// No description provided for @scheduleEnableReminderSwitch.
  ///
  /// In en, this message translates to:
  /// **'Pre-Class Vibration & Banner Alert'**
  String get scheduleEnableReminderSwitch;

  /// No description provided for @scheduleEnableReminderSub.
  ///
  /// In en, this message translates to:
  /// **'Hardware alarm vibration + heads-up notification before class'**
  String get scheduleEnableReminderSub;

  /// No description provided for @scheduleDiagnoseBtn.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get scheduleDiagnoseBtn;

  /// No description provided for @scheduleSysNotifBtn.
  ///
  /// In en, this message translates to:
  /// **'System Settings'**
  String get scheduleSysNotifBtn;

  /// No description provided for @scheduleTestVibBtn.
  ///
  /// In en, this message translates to:
  /// **'Test Vibration'**
  String get scheduleTestVibBtn;

  /// No description provided for @scheduleTestVibToast.
  ///
  /// In en, this message translates to:
  /// **'Triggered strong vibration test alert!'**
  String get scheduleTestVibToast;

  /// No description provided for @scheduleUseSysClockSwitch.
  ///
  /// In en, this message translates to:
  /// **'Also Set System Clock Alarm (Optional)'**
  String get scheduleUseSysClockSwitch;

  /// No description provided for @scheduleUseSysClockSub.
  ///
  /// In en, this message translates to:
  /// **'Creates an alarm in the phone\'s built-in Clock app for 100% reliability'**
  String get scheduleUseSysClockSub;

  /// No description provided for @scheduleWriteNextAlarmBtn.
  ///
  /// In en, this message translates to:
  /// **'Add Next Class to System Clock'**
  String get scheduleWriteNextAlarmBtn;

  /// No description provided for @scheduleWriteNextAlarmToast.
  ///
  /// In en, this message translates to:
  /// **'System alarm set for next class: {info}'**
  String scheduleWriteNextAlarmToast(String info);

  /// No description provided for @scheduleNoUpcomingClassToast.
  ///
  /// In en, this message translates to:
  /// **'No upcoming classes in the next 7 days'**
  String get scheduleNoUpcomingClassToast;

  /// No description provided for @scheduleFirstWeekMonLabel.
  ///
  /// In en, this message translates to:
  /// **'Monday of Week 1'**
  String get scheduleFirstWeekMonLabel;

  /// No description provided for @schedulePickSemesterStartHelp.
  ///
  /// In en, this message translates to:
  /// **'Pick any day in Week 1 of the semester'**
  String get schedulePickSemesterStartHelp;

  /// No description provided for @scheduleSectionsPerDayLabel.
  ///
  /// In en, this message translates to:
  /// **'Periods per Day'**
  String get scheduleSectionsPerDayLabel;

  /// No description provided for @scheduleSectionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} periods'**
  String scheduleSectionsCount(int count);

  /// No description provided for @scheduleAddCourseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add Course'**
  String get scheduleAddCourseTooltip;

  /// No description provided for @scheduleRainBanner.
  ///
  /// In en, this message translates to:
  /// **'Rain expected today ({precip}% precip) — remember to bring an umbrella!'**
  String scheduleRainBanner(String precip);

  /// No description provided for @scheduleEmptyTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap any cell to add, or '**
  String get scheduleEmptyTapHint;

  /// No description provided for @scheduleEmptyImportBtn.
  ///
  /// In en, this message translates to:
  /// **'Import from Screenshot / Text'**
  String get scheduleEmptyImportBtn;

  /// No description provided for @scheduleMonthHeader.
  ///
  /// In en, this message translates to:
  /// **'M{month}'**
  String scheduleMonthHeader(int month);

  /// No description provided for @scheduleCourseDetailSection.
  ///
  /// In en, this message translates to:
  /// **'{weekday} {timeRange} (Period {start}-{end})'**
  String scheduleCourseDetailSection(
    String weekday,
    String timeRange,
    int start,
    int end,
  );

  /// No description provided for @scheduleCourseDetailWeeks.
  ///
  /// In en, this message translates to:
  /// **'Weeks {startWeek}-{endWeek} · {weekType}'**
  String scheduleCourseDetailWeeks(int startWeek, int endWeek, String weekType);

  /// No description provided for @scheduleDeleteCourseConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete course \"{name}\"?'**
  String scheduleDeleteCourseConfirm(String name);

  /// No description provided for @courseEditAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Course'**
  String get courseEditAddTitle;

  /// No description provided for @courseEditUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Course'**
  String get courseEditUpdateTitle;

  /// No description provided for @courseEditNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Course Name *'**
  String get courseEditNameLabel;

  /// No description provided for @courseEditNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter course name'**
  String get courseEditNameRequired;

  /// No description provided for @courseEditLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Classroom'**
  String get courseEditLocationLabel;

  /// No description provided for @courseEditTeacherLabel.
  ///
  /// In en, this message translates to:
  /// **'Instructor'**
  String get courseEditTeacherLabel;

  /// No description provided for @courseEditWeekdayTitle.
  ///
  /// In en, this message translates to:
  /// **'Day of Week'**
  String get courseEditWeekdayTitle;

  /// No description provided for @courseEditSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Periods & Time'**
  String get courseEditSectionTitle;

  /// No description provided for @courseEditStartSection.
  ///
  /// In en, this message translates to:
  /// **'Start Period'**
  String get courseEditStartSection;

  /// No description provided for @courseEditEndSection.
  ///
  /// In en, this message translates to:
  /// **'End Period'**
  String get courseEditEndSection;

  /// No description provided for @courseEditSectionItem.
  ///
  /// In en, this message translates to:
  /// **'Period {num} ({time})'**
  String courseEditSectionItem(int num, String time);

  /// No description provided for @courseEditSectionOrderError.
  ///
  /// In en, this message translates to:
  /// **'End period cannot be earlier than start period'**
  String get courseEditSectionOrderError;

  /// No description provided for @courseEditWeeksTitle.
  ///
  /// In en, this message translates to:
  /// **'Week Range & Frequency'**
  String get courseEditWeeksTitle;

  /// No description provided for @courseEditWeeksSummary.
  ///
  /// In en, this message translates to:
  /// **'Weeks {start} - {end} · {timeRange}'**
  String courseEditWeeksSummary(int start, int end, String timeRange);

  /// No description provided for @courseEditColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Course Color'**
  String get courseEditColorTitle;

  /// No description provided for @courseEditSaveBtn.
  ///
  /// In en, this message translates to:
  /// **'Save Course'**
  String get courseEditSaveBtn;

  /// No description provided for @workoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Workout & Cardio'**
  String get workoutTitle;

  /// No description provided for @workoutExerciseLibBtn.
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get workoutExerciseLibBtn;

  /// No description provided for @workoutStartStrengthBtn.
  ///
  /// In en, this message translates to:
  /// **'Start Strength'**
  String get workoutStartStrengthBtn;

  /// No description provided for @workoutLogCardioBtn.
  ///
  /// In en, this message translates to:
  /// **'Log Cardio'**
  String get workoutLogCardioBtn;

  /// No description provided for @workoutTabStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength (Sets & Timer)'**
  String get workoutTabStrength;

  /// No description provided for @workoutTabCardio.
  ///
  /// In en, this message translates to:
  /// **'Cardio (MET Burn)'**
  String get workoutTabCardio;

  /// No description provided for @workoutActivePlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Active Plan: {name}'**
  String workoutActivePlanTitle(String name);

  /// No description provided for @workoutTapSplitHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a split to start'**
  String get workoutTapSplitHint;

  /// No description provided for @workoutPlanSplitChip.
  ///
  /// In en, this message translates to:
  /// **'{day} · {focus} ({count} exercises)'**
  String workoutPlanSplitChip(String day, String focus, int count);

  /// No description provided for @workoutVolumeChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Strength Volume (kg)'**
  String get workoutVolumeChartTitle;

  /// No description provided for @workoutHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Strength Sessions'**
  String get workoutHistoryTitle;

  /// No description provided for @workoutEmptyStrengthHint.
  ///
  /// In en, this message translates to:
  /// **'No strength workouts logged yet\nTap below to start a timed session, or ask AI Coach for a custom split'**
  String get workoutEmptyStrengthHint;

  /// No description provided for @workoutEmptyStrengthBtn.
  ///
  /// In en, this message translates to:
  /// **'Start First Workout'**
  String get workoutEmptyStrengthBtn;

  /// No description provided for @workoutEmptySessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty Session'**
  String get workoutEmptySessionTitle;

  /// No description provided for @workoutSessionDuration.
  ///
  /// In en, this message translates to:
  /// **'{mins} min'**
  String workoutSessionDuration(int mins);

  /// No description provided for @workoutSessionSets.
  ///
  /// In en, this message translates to:
  /// **'{sets} working sets'**
  String workoutSessionSets(int sets);

  /// No description provided for @workoutSessionVolume.
  ///
  /// In en, this message translates to:
  /// **'Vol {volume} kg'**
  String workoutSessionVolume(String volume);

  /// No description provided for @workoutSessionBurn.
  ///
  /// In en, this message translates to:
  /// **'~{kcal} kcal'**
  String workoutSessionBurn(String kcal);

  /// No description provided for @workoutDeleteSessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this workout session?'**
  String get workoutDeleteSessionConfirm;

  /// No description provided for @workoutEmptyCardioHint.
  ///
  /// In en, this message translates to:
  /// **'No cardio sessions logged yet\nLog walking, running, cycling, swimming or jump rope with automatic MET calorie burn'**
  String get workoutEmptyCardioHint;

  /// No description provided for @workoutEmptyCardioBtn.
  ///
  /// In en, this message translates to:
  /// **'Add Cardio Session'**
  String get workoutEmptyCardioBtn;

  /// No description provided for @workoutCardioItemTitle.
  ///
  /// In en, this message translates to:
  /// **'{type} · {mins} min'**
  String workoutCardioItemTitle(String type, String mins);

  /// No description provided for @workoutDeleteCardioConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this cardio record?'**
  String get workoutDeleteCardioConfirm;

  /// No description provided for @workoutCardioSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Cardio logged: ~{kcal} kcal burned (added to today\'s calorie budget)'**
  String workoutCardioSavedToast(String kcal);

  /// No description provided for @cardioDialogAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Log Cardio'**
  String get cardioDialogAddTitle;

  /// No description provided for @cardioDialogEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Cardio'**
  String get cardioDialogEditTitle;

  /// No description provided for @cardioTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Cardio Type'**
  String get cardioTypeLabel;

  /// No description provided for @cardioDurationLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration *'**
  String get cardioDurationLabel;

  /// No description provided for @cardioMinutesSuffix.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get cardioMinutesSuffix;

  /// No description provided for @cardioDistanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance (Opt)'**
  String get cardioDistanceLabel;

  /// No description provided for @cardioEstBurnLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated Burn ({weight}kg × MET {met})'**
  String cardioEstBurnLabel(String weight, String met);

  /// No description provided for @cardioDurationRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a duration greater than 0'**
  String get cardioDurationRequired;

  /// No description provided for @cardioTypeWalk.
  ///
  /// In en, this message translates to:
  /// **'Walking'**
  String get cardioTypeWalk;

  /// No description provided for @cardioTypeBriskWalk.
  ///
  /// In en, this message translates to:
  /// **'Brisk Walk'**
  String get cardioTypeBriskWalk;

  /// No description provided for @cardioTypeJog.
  ///
  /// In en, this message translates to:
  /// **'Jogging'**
  String get cardioTypeJog;

  /// No description provided for @cardioTypeRun.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get cardioTypeRun;

  /// No description provided for @cardioTypeCycle.
  ///
  /// In en, this message translates to:
  /// **'Cycling'**
  String get cardioTypeCycle;

  /// No description provided for @cardioTypeSwim.
  ///
  /// In en, this message translates to:
  /// **'Swimming'**
  String get cardioTypeSwim;

  /// No description provided for @cardioTypeJumpRope.
  ///
  /// In en, this message translates to:
  /// **'Jump Rope'**
  String get cardioTypeJumpRope;

  /// No description provided for @cardioTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get cardioTypeOther;

  /// No description provided for @sessionHeaderStats.
  ///
  /// In en, this message translates to:
  /// **'{sets} sets · {volume} kg'**
  String sessionHeaderStats(int sets, String volume);

  /// No description provided for @sessionFinishBtn.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get sessionFinishBtn;

  /// No description provided for @sessionAddExerciseBtn.
  ///
  /// In en, this message translates to:
  /// **'Add Exercise'**
  String get sessionAddExerciseBtn;

  /// No description provided for @sessionEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Workout timer is running!\nTap below to add exercises, and tap ✓ on each set to start the rest timer'**
  String get sessionEmptyHint;

  /// No description provided for @sessionSelectExerciseBtn.
  ///
  /// In en, this message translates to:
  /// **'Select Exercise'**
  String get sessionSelectExerciseBtn;

  /// No description provided for @sessionRestActive.
  ///
  /// In en, this message translates to:
  /// **'Rest Timer: {clock}{paused}'**
  String sessionRestActive(String clock, String paused);

  /// No description provided for @sessionRestPausedTag.
  ///
  /// In en, this message translates to:
  /// **' (Paused)'**
  String get sessionRestPausedTag;

  /// No description provided for @sessionRestResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get sessionRestResume;

  /// No description provided for @sessionRestPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get sessionRestPause;

  /// No description provided for @sessionRestSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get sessionRestSkip;

  /// No description provided for @sessionRestDurationLabel.
  ///
  /// In en, this message translates to:
  /// **'Rest Timer:'**
  String get sessionRestDurationLabel;

  /// No description provided for @sessionRestStartNow.
  ///
  /// In en, this message translates to:
  /// **'Start Rest Timer'**
  String get sessionRestStartNow;

  /// No description provided for @sessionRestFinishedToast.
  ///
  /// In en, this message translates to:
  /// **'Rest finished! Time for your next set'**
  String get sessionRestFinishedToast;

  /// No description provided for @sessionPlanTargetHint.
  ///
  /// In en, this message translates to:
  /// **'Target: {sets} sets × {reps}{weightHint}'**
  String sessionPlanTargetHint(int sets, String reps, String weightHint);

  /// No description provided for @sessionLastCardioHint.
  ///
  /// In en, this message translates to:
  /// **'Last: {records}'**
  String sessionLastCardioHint(String records);

  /// No description provided for @sessionLastStrengthHint.
  ///
  /// In en, this message translates to:
  /// **'Last: {records}'**
  String sessionLastStrengthHint(String records);

  /// No description provided for @sessionWarmupTag.
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get sessionWarmupTag;

  /// No description provided for @sessionCardioDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get sessionCardioDuration;

  /// No description provided for @sessionCardioMins.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get sessionCardioMins;

  /// No description provided for @sessionStrengthWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get sessionStrengthWeight;

  /// No description provided for @sessionCardioSteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get sessionCardioSteps;

  /// No description provided for @sessionCardioStepsUnit.
  ///
  /// In en, this message translates to:
  /// **'steps'**
  String get sessionCardioStepsUnit;

  /// No description provided for @sessionStrengthReps.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get sessionStrengthReps;

  /// No description provided for @sessionStrengthRepsUnit.
  ///
  /// In en, this message translates to:
  /// **'reps'**
  String get sessionStrengthRepsUnit;

  /// No description provided for @sessionCompleteSetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Complete set & start rest timer'**
  String get sessionCompleteSetTooltip;

  /// No description provided for @sessionAddCardioRow.
  ///
  /// In en, this message translates to:
  /// **'Add another interval'**
  String get sessionAddCardioRow;

  /// No description provided for @sessionAddStrengthRow.
  ///
  /// In en, this message translates to:
  /// **'Add Set (tap ✓ to start rest timer)'**
  String get sessionAddStrengthRow;

  /// No description provided for @sessionFinishedToast.
  ///
  /// In en, this message translates to:
  /// **'Workout complete! {mins} min · {sets} sets · Vol {volume} kg · ~{kcal} kcal'**
  String sessionFinishedToast(int mins, int sets, String volume, String kcal);

  /// No description provided for @exerciseSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Exercise'**
  String get exerciseSelectTitle;

  /// No description provided for @exerciseLibTitle.
  ///
  /// In en, this message translates to:
  /// **'Exercise Library'**
  String get exerciseLibTitle;

  /// No description provided for @exerciseAddCustomBtn.
  ///
  /// In en, this message translates to:
  /// **'Custom Exercise'**
  String get exerciseAddCustomBtn;

  /// No description provided for @exerciseCustomDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Custom Exercise'**
  String get exerciseCustomDialogTitle;

  /// No description provided for @exerciseCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Muscle Group'**
  String get exerciseCategoryLabel;

  /// No description provided for @exerciseNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Exercise Name'**
  String get exerciseNameLabel;

  /// No description provided for @exerciseCustomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{category} · Custom'**
  String exerciseCustomSubtitle(String category);

  /// No description provided for @exercisePresetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{category} Training'**
  String exercisePresetSubtitle(String category);

  /// No description provided for @exerciseDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete custom exercise \"{name}\"?'**
  String exerciseDeleteConfirm(String name);

  /// No description provided for @catChest.
  ///
  /// In en, this message translates to:
  /// **'Chest'**
  String get catChest;

  /// No description provided for @catBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get catBack;

  /// No description provided for @catLegs.
  ///
  /// In en, this message translates to:
  /// **'Legs'**
  String get catLegs;

  /// No description provided for @catShoulders.
  ///
  /// In en, this message translates to:
  /// **'Shoulders'**
  String get catShoulders;

  /// No description provided for @catArms.
  ///
  /// In en, this message translates to:
  /// **'Arms'**
  String get catArms;

  /// No description provided for @catCore.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get catCore;

  /// No description provided for @catCardio.
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get catCardio;

  /// No description provided for @catOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get catOther;

  /// No description provided for @bodyTitle.
  ///
  /// In en, this message translates to:
  /// **'Body Metrics'**
  String get bodyTitle;

  /// No description provided for @bodyProfileBtn.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get bodyProfileBtn;

  /// No description provided for @bodyLogWeightBtn.
  ///
  /// In en, this message translates to:
  /// **'Log Weight'**
  String get bodyLogWeightBtn;

  /// No description provided for @bodyNoProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Fitness Profile Incomplete'**
  String get bodyNoProfileTitle;

  /// No description provided for @bodyNoProfileSub.
  ///
  /// In en, this message translates to:
  /// **'Tap Profile at the top right for accurate BMR & TDEE calculation'**
  String get bodyNoProfileSub;

  /// No description provided for @bodyWeightTrendTitle.
  ///
  /// In en, this message translates to:
  /// **'Weight Trend'**
  String get bodyWeightTrendTitle;

  /// No description provided for @bodyEmptyChartHint.
  ///
  /// In en, this message translates to:
  /// **'Log your first weight entry to see the trend chart'**
  String get bodyEmptyChartHint;

  /// No description provided for @bodyEmptyChartBtn.
  ///
  /// In en, this message translates to:
  /// **'Log Weight Now'**
  String get bodyEmptyChartBtn;

  /// No description provided for @bodyHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get bodyHistoryTitle;

  /// No description provided for @bodyEmptyHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'No body metrics logged yet\nMorning fasting weight is the most consistent'**
  String get bodyEmptyHistoryHint;

  /// No description provided for @bodyEmptyHistoryBtn.
  ///
  /// In en, this message translates to:
  /// **'Log Today\'s Weight'**
  String get bodyEmptyHistoryBtn;

  /// No description provided for @bodyFatTag.
  ///
  /// In en, this message translates to:
  /// **'Body Fat {fat}%'**
  String bodyFatTag(String fat);

  /// No description provided for @bodyWaistTag.
  ///
  /// In en, this message translates to:
  /// **'Waist {waist} cm'**
  String bodyWaistTag(String waist);

  /// No description provided for @bodyStatWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight kg'**
  String get bodyStatWeight;

  /// No description provided for @bodyStatBmr.
  ///
  /// In en, this message translates to:
  /// **'BMR'**
  String get bodyStatBmr;

  /// No description provided for @bodyStatTdee.
  ///
  /// In en, this message translates to:
  /// **'TDEE'**
  String get bodyStatTdee;

  /// No description provided for @bodyStatTargetKcal.
  ///
  /// In en, this message translates to:
  /// **'Target kcal'**
  String get bodyStatTargetKcal;

  /// No description provided for @bodyStatGoal.
  ///
  /// In en, this message translates to:
  /// **'Current Goal'**
  String get bodyStatGoal;

  /// No description provided for @bodyChartTargetLine.
  ///
  /// In en, this message translates to:
  /// **'Goal {weight}kg'**
  String bodyChartTargetLine(String weight);

  /// No description provided for @bodyDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Log Body Metrics'**
  String get bodyDialogTitle;

  /// No description provided for @bodyWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get bodyWeightLabel;

  /// No description provided for @bodyFatLabel.
  ///
  /// In en, this message translates to:
  /// **'Body Fat (Optional)'**
  String get bodyFatLabel;

  /// No description provided for @bodyWaistLabel.
  ///
  /// In en, this message translates to:
  /// **'Waist (Optional)'**
  String get bodyWaistLabel;

  /// No description provided for @bmiUnderweight.
  ///
  /// In en, this message translates to:
  /// **'Underweight'**
  String get bmiUnderweight;

  /// No description provided for @bmiNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get bmiNormal;

  /// No description provided for @bmiOverweight.
  ///
  /// In en, this message translates to:
  /// **'Overweight'**
  String get bmiOverweight;

  /// No description provided for @bmiObese.
  ///
  /// In en, this message translates to:
  /// **'Obese'**
  String get bmiObese;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Body & Training Profile'**
  String get profileTitle;

  /// No description provided for @profileGenderSection.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get profileGenderSection;

  /// No description provided for @profileMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get profileMale;

  /// No description provided for @profileFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get profileFemale;

  /// No description provided for @profileAgeHeightSection.
  ///
  /// In en, this message translates to:
  /// **'Age & Height'**
  String get profileAgeHeightSection;

  /// No description provided for @profileAgeLabel.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get profileAgeLabel;

  /// No description provided for @profileAgeUnit.
  ///
  /// In en, this message translates to:
  /// **'yrs'**
  String get profileAgeUnit;

  /// No description provided for @profileHeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get profileHeightLabel;

  /// No description provided for @profileActivityGoalSection.
  ///
  /// In en, this message translates to:
  /// **'Activity Level & Goal'**
  String get profileActivityGoalSection;

  /// No description provided for @profileActivityLabel.
  ///
  /// In en, this message translates to:
  /// **'Daily Non-Exercise Activity Level'**
  String get profileActivityLabel;

  /// No description provided for @profileTargetWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Target Weight (Opt, shown on weight chart)'**
  String get profileTargetWeightLabel;

  /// No description provided for @profileTrainingConditionSection.
  ///
  /// In en, this message translates to:
  /// **'Training Setup (Used by AI Coach)'**
  String get profileTrainingConditionSection;

  /// No description provided for @profileExperienceLabel.
  ///
  /// In en, this message translates to:
  /// **'Training Experience'**
  String get profileExperienceLabel;

  /// No description provided for @profileWeeklyDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Days / Week'**
  String get profileWeeklyDaysLabel;

  /// No description provided for @profileWeeklyDaysItem.
  ///
  /// In en, this message translates to:
  /// **'{days} days/wk'**
  String profileWeeklyDaysItem(int days);

  /// No description provided for @profileSessionMinsLabel.
  ///
  /// In en, this message translates to:
  /// **'Session Length'**
  String get profileSessionMinsLabel;

  /// No description provided for @profileSessionMinsItem.
  ///
  /// In en, this message translates to:
  /// **'{mins} min'**
  String profileSessionMinsItem(int mins);

  /// No description provided for @profileEquipmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Available Equipment'**
  String get profileEquipmentLabel;

  /// No description provided for @profileInjuriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Injuries or Limitations (Optional)'**
  String get profileInjuriesLabel;

  /// No description provided for @profileInjuriesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. knee discomfort, lower back issue, none'**
  String get profileInjuriesHint;

  /// No description provided for @profileSaveBtn.
  ///
  /// In en, this message translates to:
  /// **'Save Profile'**
  String get profileSaveBtn;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalize Your Health & Training'**
  String get onboardingTitle;

  /// No description provided for @onboardingIntro.
  ///
  /// In en, this message translates to:
  /// **'Take 30 seconds to fill in your basics. We\'ll calculate your dynamic calorie budget and include your setup when chatting with AI Coach.'**
  String get onboardingIntro;

  /// No description provided for @onboardingStep1.
  ///
  /// In en, this message translates to:
  /// **'1. Basic Body Metrics'**
  String get onboardingStep1;

  /// No description provided for @onboardingCurrentWeight.
  ///
  /// In en, this message translates to:
  /// **'Current Weight'**
  String get onboardingCurrentWeight;

  /// No description provided for @onboardingTargetWeight.
  ///
  /// In en, this message translates to:
  /// **'Target Weight (Opt)'**
  String get onboardingTargetWeight;

  /// No description provided for @onboardingStep2.
  ///
  /// In en, this message translates to:
  /// **'2. Goal & Daily Activity'**
  String get onboardingStep2;

  /// No description provided for @onboardingStep3.
  ///
  /// In en, this message translates to:
  /// **'3. Experience & Equipment'**
  String get onboardingStep3;

  /// No description provided for @onboardingFinishBtn.
  ///
  /// In en, this message translates to:
  /// **'Complete & Initialize Plan'**
  String get onboardingFinishBtn;

  /// No description provided for @onboardingSavedToast.
  ///
  /// In en, this message translates to:
  /// **'Profile saved! TDEE and AI Coach context initialized.'**
  String get onboardingSavedToast;

  /// No description provided for @goalLose.
  ///
  /// In en, this message translates to:
  /// **'Fat Loss'**
  String get goalLose;

  /// No description provided for @goalMaintain.
  ///
  /// In en, this message translates to:
  /// **'Maintain'**
  String get goalMaintain;

  /// No description provided for @goalGain.
  ///
  /// In en, this message translates to:
  /// **'Muscle Gain'**
  String get goalGain;

  /// No description provided for @goalFitness.
  ///
  /// In en, this message translates to:
  /// **'Fitness & Conditioning'**
  String get goalFitness;

  /// No description provided for @actSedentary.
  ///
  /// In en, this message translates to:
  /// **'Sedentary (Desk job, little exercise)'**
  String get actSedentary;

  /// No description provided for @actLight.
  ///
  /// In en, this message translates to:
  /// **'Lightly Active (1–3 days/wk)'**
  String get actLight;

  /// No description provided for @actModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderately Active (3–5 days/wk)'**
  String get actModerate;

  /// No description provided for @actHigh.
  ///
  /// In en, this message translates to:
  /// **'Very Active (6–7 days/wk)'**
  String get actHigh;

  /// No description provided for @actExtreme.
  ///
  /// In en, this message translates to:
  /// **'Extra Active (Physical job / 2x daily)'**
  String get actExtreme;

  /// No description provided for @expNone.
  ///
  /// In en, this message translates to:
  /// **'Complete Beginner'**
  String get expNone;

  /// No description provided for @expBeginner.
  ///
  /// In en, this message translates to:
  /// **'Under 6 Months'**
  String get expBeginner;

  /// No description provided for @expIntermediate.
  ///
  /// In en, this message translates to:
  /// **'1–3 Years'**
  String get expIntermediate;

  /// No description provided for @expAdvanced.
  ///
  /// In en, this message translates to:
  /// **'3+ Years'**
  String get expAdvanced;

  /// No description provided for @equipBodyweight.
  ///
  /// In en, this message translates to:
  /// **'Bodyweight Only'**
  String get equipBodyweight;

  /// No description provided for @equipDumbbell.
  ///
  /// In en, this message translates to:
  /// **'Dumbbells'**
  String get equipDumbbell;

  /// No description provided for @equipBarbell.
  ///
  /// In en, this message translates to:
  /// **'Barbell & Rack'**
  String get equipBarbell;

  /// No description provided for @equipGym.
  ///
  /// In en, this message translates to:
  /// **'Full Commercial Gym'**
  String get equipGym;

  /// No description provided for @aiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Health Coach'**
  String get aiTitle;

  /// No description provided for @aiClearChatTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear Chat'**
  String get aiClearChatTooltip;

  /// No description provided for @aiClearChatConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all chat history?'**
  String get aiClearChatConfirm;

  /// No description provided for @aiSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'AI Settings'**
  String get aiSettingsTooltip;

  /// No description provided for @aiQuickGeneratePlan.
  ///
  /// In en, this message translates to:
  /// **'Generate Workout Plan (Importable)'**
  String get aiQuickGeneratePlan;

  /// No description provided for @aiQuickTodaySummary.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Review'**
  String get aiQuickTodaySummary;

  /// No description provided for @aiQuickWeekSummary.
  ///
  /// In en, this message translates to:
  /// **'Weekly Review'**
  String get aiQuickWeekSummary;

  /// No description provided for @aiQuickNextMeal.
  ///
  /// In en, this message translates to:
  /// **'What to Eat Next'**
  String get aiQuickNextMeal;

  /// No description provided for @aiPromptGeneratePlan.
  ///
  /// In en, this message translates to:
  /// **'Please design a weekly workout split based on my profile (goal, experience, weekly days, session duration, equipment, injuries) and free slots in my class schedule, and include the importable JSON workout plan block at the end.'**
  String get aiPromptGeneratePlan;

  /// No description provided for @aiPromptTodaySummary.
  ///
  /// In en, this message translates to:
  /// **'Please review my meals and workouts logged today, and suggest what I should eat for my next meal.'**
  String get aiPromptTodaySummary;

  /// No description provided for @aiPromptWeekSummary.
  ///
  /// In en, this message translates to:
  /// **'Please summarize my calorie intake, macros, and training over the last 7 days, highlighting strengths and areas to improve.'**
  String get aiPromptWeekSummary;

  /// No description provided for @aiPromptNextMeal.
  ///
  /// In en, this message translates to:
  /// **'Based on my remaining calories and macro targets today, recommend 2-3 practical meal options.'**
  String get aiPromptNextMeal;

  /// No description provided for @aiEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'AI Coach automatically reads your profile, meals, workouts & class schedule\nTap \"Generate Workout Plan\" above to create a custom split and import it in one tap'**
  String get aiEmptyHint;

  /// No description provided for @aiEmptyActionBtn.
  ///
  /// In en, this message translates to:
  /// **'Generate My Custom Plan'**
  String get aiEmptyActionBtn;

  /// No description provided for @aiImportPlanBtn.
  ///
  /// In en, this message translates to:
  /// **'Import to Workout Plan ({name})'**
  String aiImportPlanBtn(String name);

  /// No description provided for @aiPlanImportedToast.
  ///
  /// In en, this message translates to:
  /// **'Imported \"{name}\"! Open the Workout tab and tap any split to start training'**
  String aiPlanImportedToast(String name);

  /// No description provided for @aiInputHint.
  ///
  /// In en, this message translates to:
  /// **'Ask about nutrition, workouts, or say \"Build me a workout plan\"…'**
  String get aiInputHint;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance, Font & Language'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get settingsThemeMode;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get settingsFontSize;

  /// No description provided for @settingsFontSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get settingsFontSmall;

  /// No description provided for @settingsFontMedium.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get settingsFontMedium;

  /// No description provided for @settingsFontLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get settingsFontLarge;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLangSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLangSystem;

  /// No description provided for @settingsLangZh.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get settingsLangZh;

  /// No description provided for @settingsLangEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLangEn;

  /// No description provided for @settingsWeatherSection.
  ///
  /// In en, this message translates to:
  /// **'Weather City & Location'**
  String get settingsWeatherSection;

  /// No description provided for @settingsWeatherModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Current: Auto GPS Location (6h cache, IP fallback)'**
  String get settingsWeatherModeAuto;

  /// No description provided for @settingsWeatherModeManual.
  ///
  /// In en, this message translates to:
  /// **'Current: Locked City · {city}'**
  String settingsWeatherModeManual(String city);

  /// No description provided for @settingsWeatherProxyHint.
  ///
  /// In en, this message translates to:
  /// **'If using a VPN/proxy without GPS, pick your city below to lock accurate local weather:'**
  String get settingsWeatherProxyHint;

  /// No description provided for @settingsWeatherAutoChip.
  ///
  /// In en, this message translates to:
  /// **'Auto GPS'**
  String get settingsWeatherAutoChip;

  /// No description provided for @settingsWeatherAutoToast.
  ///
  /// In en, this message translates to:
  /// **'Switched to Auto GPS location and refreshed weather'**
  String get settingsWeatherAutoToast;

  /// No description provided for @settingsWeatherLockedToast.
  ///
  /// In en, this message translates to:
  /// **'Locked weather city to: {city}'**
  String settingsWeatherLockedToast(String city);

  /// No description provided for @settingsWeatherCustomLabel.
  ///
  /// In en, this message translates to:
  /// **'Search Custom City'**
  String get settingsWeatherCustomLabel;

  /// No description provided for @settingsWeatherCustomHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Ho Chi Minh City / Hanoi / London'**
  String get settingsWeatherCustomHint;

  /// No description provided for @settingsWeatherSetBtn.
  ///
  /// In en, this message translates to:
  /// **'Set City'**
  String get settingsWeatherSetBtn;

  /// No description provided for @settingsChatAiSection.
  ///
  /// In en, this message translates to:
  /// **'Chat AI Model (DeepSeek / OpenAI)'**
  String get settingsChatAiSection;

  /// No description provided for @settingsChatAiHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a provider preset below or enter a Base URL. Your API Key is stored encrypted on device.'**
  String get settingsChatAiHint;

  /// No description provided for @settingsPresetDeepseek.
  ///
  /// In en, this message translates to:
  /// **'DeepSeek (Default)'**
  String get settingsPresetDeepseek;

  /// No description provided for @settingsPresetOpenai.
  ///
  /// In en, this message translates to:
  /// **'OpenAI'**
  String get settingsPresetOpenai;

  /// No description provided for @settingsPresetQwen.
  ///
  /// In en, this message translates to:
  /// **'Qwen (DashScope)'**
  String get settingsPresetQwen;

  /// No description provided for @settingsBaseUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Base URL (e.g. deepseek or full URL)'**
  String get settingsBaseUrlLabel;

  /// No description provided for @settingsApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get settingsApiKeyLabel;

  /// No description provided for @settingsModelNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Model Name'**
  String get settingsModelNameLabel;

  /// No description provided for @settingsTestingBtn.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get settingsTestingBtn;

  /// No description provided for @settingsTestConnectionBtn.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get settingsTestConnectionBtn;

  /// No description provided for @settingsTestSuccessToast.
  ///
  /// In en, this message translates to:
  /// **'Connected: {reply}'**
  String settingsTestSuccessToast(String reply);

  /// No description provided for @settingsVisionSection.
  ///
  /// In en, this message translates to:
  /// **'Food Scanner Vision Model'**
  String get settingsVisionSection;

  /// No description provided for @settingsVisionSameSwitch.
  ///
  /// In en, this message translates to:
  /// **'Share configuration with Chat AI model'**
  String get settingsVisionSameSwitch;

  /// No description provided for @settingsVisionSameSub.
  ///
  /// In en, this message translates to:
  /// **'Turn off to select a dedicated vision model (e.g. Qwen-VL / GPT-4o mini) if your chat model doesn\'t support images'**
  String get settingsVisionSameSub;

  /// No description provided for @settingsVisionBaseUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Vision Base URL'**
  String get settingsVisionBaseUrlLabel;

  /// No description provided for @settingsVisionApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Vision API Key'**
  String get settingsVisionApiKeyLabel;

  /// No description provided for @settingsVisionModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Vision Model Name'**
  String get settingsVisionModelLabel;

  /// No description provided for @settingsTestVisionBtn.
  ///
  /// In en, this message translates to:
  /// **'Test Vision API'**
  String get settingsTestVisionBtn;

  /// No description provided for @settingsSaveAiBtn.
  ///
  /// In en, this message translates to:
  /// **'Save AI Configuration'**
  String get settingsSaveAiBtn;

  /// No description provided for @settingsSystemDataSection.
  ///
  /// In en, this message translates to:
  /// **'Notifications & Data Backup'**
  String get settingsSystemDataSection;

  /// No description provided for @settingsDiagTileTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification & Vibration Diagnostics'**
  String get settingsDiagTileTitle;

  /// No description provided for @settingsDiagTileSub.
  ///
  /// In en, this message translates to:
  /// **'Fix silent notifications, enable high-priority banners & alarms'**
  String get settingsDiagTileSub;

  /// No description provided for @settingsExportJsonTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Full Backup (JSON)'**
  String get settingsExportJsonTitle;

  /// No description provided for @settingsExportJsonSub.
  ///
  /// In en, this message translates to:
  /// **'Includes schedule, meals, workouts, cardio & body metrics'**
  String get settingsExportJsonSub;

  /// No description provided for @settingsExportCsvTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Spreadsheets (CSV)'**
  String get settingsExportCsvTitle;

  /// No description provided for @settingsExportCsvSub.
  ///
  /// In en, this message translates to:
  /// **'View meals, weight & cardio history in Excel or Sheets'**
  String get settingsExportCsvSub;

  /// No description provided for @settingsAboutTileTitle.
  ///
  /// In en, this message translates to:
  /// **'About Life Assistant'**
  String get settingsAboutTileTitle;

  /// No description provided for @settingsAboutTileSub.
  ///
  /// In en, this message translates to:
  /// **'Version v1.5.0 · Co-developed with DaFeiYu'**
  String get settingsAboutTileSub;

  /// No description provided for @diagTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification & Vibration Diagnostics'**
  String get diagTitle;

  /// No description provided for @diagRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Re-check'**
  String get diagRefreshTooltip;

  /// No description provided for @diagStatusGood.
  ///
  /// In en, this message translates to:
  /// **'Notifications & Strong Vibration Ready'**
  String get diagStatusGood;

  /// No description provided for @diagStatusWarn.
  ///
  /// In en, this message translates to:
  /// **'Notifications or Vibration May Be Restricted'**
  String get diagStatusWarn;

  /// No description provided for @diagDeviceChannelSub.
  ///
  /// In en, this message translates to:
  /// **'Device: {device}\nChannel: {channelName} ({channelId})'**
  String diagDeviceChannelSub(
    String device,
    String channelName,
    String channelId,
  );

  /// No description provided for @diagSectionPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permission & Channel Status'**
  String get diagSectionPermissions;

  /// No description provided for @diagAppNotifTitle.
  ///
  /// In en, this message translates to:
  /// **'App Notifications (areNotificationsEnabled)'**
  String get diagAppNotifTitle;

  /// No description provided for @diagAppNotifOn.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get diagAppNotifOn;

  /// No description provided for @diagAppNotifOff.
  ///
  /// In en, this message translates to:
  /// **'Disabled — you won\'t receive class or bus reminders'**
  String get diagAppNotifOff;

  /// No description provided for @diagImportanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Channel Importance'**
  String get diagImportanceTitle;

  /// No description provided for @diagImp0.
  ///
  /// In en, this message translates to:
  /// **'0 - Disabled (NONE)'**
  String get diagImp0;

  /// No description provided for @diagImp1.
  ///
  /// In en, this message translates to:
  /// **'1 - Min (Silent, no banner)'**
  String get diagImp1;

  /// No description provided for @diagImp2.
  ///
  /// In en, this message translates to:
  /// **'2 - Low (Downgraded to silent notification)'**
  String get diagImp2;

  /// No description provided for @diagImp3.
  ///
  /// In en, this message translates to:
  /// **'3 - Default (May not pop up banner)'**
  String get diagImp3;

  /// No description provided for @diagImpHigh.
  ///
  /// In en, this message translates to:
  /// **'{imp} - High/Max (Banner + Vibration enabled)'**
  String diagImpHigh(int imp);

  /// No description provided for @diagVibrateTitle.
  ///
  /// In en, this message translates to:
  /// **'Channel Vibration (shouldVibrate)'**
  String get diagVibrateTitle;

  /// No description provided for @diagVibrateOn.
  ///
  /// In en, this message translates to:
  /// **'Allowed (+ hardware alarm vibration backup)'**
  String get diagVibrateOn;

  /// No description provided for @diagVibrateOff.
  ///
  /// In en, this message translates to:
  /// **'Channel vibration disabled — tap below to enable'**
  String get diagVibrateOff;

  /// No description provided for @diagSoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Sound'**
  String get diagSoundTitle;

  /// No description provided for @diagSoundOn.
  ///
  /// In en, this message translates to:
  /// **'Sound configured'**
  String get diagSoundOn;

  /// No description provided for @diagSoundOff.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get diagSoundOff;

  /// No description provided for @diagExactAlarmTitle.
  ///
  /// In en, this message translates to:
  /// **'Exact Alarm Permission (canScheduleExactAlarms)'**
  String get diagExactAlarmTitle;

  /// No description provided for @diagExactAlarmOn.
  ///
  /// In en, this message translates to:
  /// **'Authorized for exact timing'**
  String get diagExactAlarmOn;

  /// No description provided for @diagExactAlarmOff.
  ///
  /// In en, this message translates to:
  /// **'Not authorized — reminders may be delayed'**
  String get diagExactAlarmOff;

  /// No description provided for @diagSectionColorOs.
  ///
  /// In en, this message translates to:
  /// **'ColorOS / Android Quick Fix'**
  String get diagSectionColorOs;

  /// No description provided for @diagColorOsGuide.
  ///
  /// In en, this message translates to:
  /// **'If notifications don\'t pop up or vibrate on OPPO / ColorOS devices, tap the buttons below to allow notifications and set the channel to High Importance with Banner & Vibration enabled:'**
  String get diagColorOsGuide;

  /// No description provided for @diagBtn1AppNotif.
  ///
  /// In en, this message translates to:
  /// **'1. Open App Notification Settings'**
  String get diagBtn1AppNotif;

  /// No description provided for @diagBtn2Channel.
  ///
  /// In en, this message translates to:
  /// **'2. Open Reminder Channel Settings'**
  String get diagBtn2Channel;

  /// No description provided for @diagBtn3Test.
  ///
  /// In en, this message translates to:
  /// **'3. Send Full-Screen Banner + Vibration Test'**
  String get diagBtn3Test;

  /// No description provided for @diagTestSentToast.
  ///
  /// In en, this message translates to:
  /// **'Test alert sent (with alarm vibration + sound + banner)'**
  String get diagTestSentToast;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About · Life Assistant'**
  String get aboutTitle;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version v1.6.0 (Build 7)'**
  String get aboutVersion;

  /// No description provided for @aboutBadge.
  ///
  /// In en, this message translates to:
  /// **'Co-developed & supervised by DaFeiYu · With you every day'**
  String get aboutBadge;

  /// No description provided for @aboutDesc.
  ///
  /// In en, this message translates to:
  /// **'All-in-one personal assistant featuring class schedules, live shuttle bus timeline (built-in BUV + custom/JSON import), GPS weather, AI food calorie scan, strength & MET cardio tracking, pedometer, and DeepSeek AI coach.'**
  String get aboutDesc;

  /// No description provided for @batteryDiagTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery & Performance Diagnostics'**
  String get batteryDiagTitle;

  /// No description provided for @batteryDiagTileSub.
  ///
  /// In en, this message translates to:
  /// **'7-day foreground/background time, timer activity, GPS, DB writes & widget syncs'**
  String get batteryDiagTileSub;

  /// No description provided for @batteryDiagResetBtn.
  ///
  /// In en, this message translates to:
  /// **'Reset Stats'**
  String get batteryDiagResetBtn;

  /// No description provided for @batteryDiagResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset all rolling 7-day battery diagnostic counters?'**
  String get batteryDiagResetConfirm;

  /// No description provided for @batteryDiagResetToast.
  ///
  /// In en, this message translates to:
  /// **'Battery diagnostic counters reset'**
  String get batteryDiagResetToast;

  /// No description provided for @batteryDiagSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Last 24h & Active Resource Monitor'**
  String get batteryDiagSummaryTitle;

  /// No description provided for @batteryDiagActiveTimers.
  ///
  /// In en, this message translates to:
  /// **'Active Periodic Timers right now: {count}'**
  String batteryDiagActiveTimers(int count);

  /// No description provided for @batteryDiagFgTime.
  ///
  /// In en, this message translates to:
  /// **'Foreground'**
  String get batteryDiagFgTime;

  /// No description provided for @batteryDiagBgTime.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get batteryDiagBgTime;

  /// No description provided for @batteryDiagTimerTime.
  ///
  /// In en, this message translates to:
  /// **'Timer Active'**
  String get batteryDiagTimerTime;

  /// No description provided for @batteryDiagGpsCalls.
  ///
  /// In en, this message translates to:
  /// **'GPS Calls'**
  String get batteryDiagGpsCalls;

  /// No description provided for @batteryDiagDbWrites.
  ///
  /// In en, this message translates to:
  /// **'DB Writes'**
  String get batteryDiagDbWrites;

  /// No description provided for @batteryDiagWidgetSyncs.
  ///
  /// In en, this message translates to:
  /// **'Widget Syncs'**
  String get batteryDiagWidgetSyncs;

  /// No description provided for @batteryDiagHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Rolling 7-Day Telemetry (Stored in kv)'**
  String get batteryDiagHistoryTitle;

  /// No description provided for @batteryDiagDaySub.
  ///
  /// In en, this message translates to:
  /// **'FG {fg} · BG {bg} · Timer {timer}\nGPS {gps} · DB Writes {db} · Widget {widget}'**
  String batteryDiagDaySub(
    String fg,
    String bg,
    String timer,
    int gps,
    int db,
    int widget,
  );

  /// No description provided for @batteryDiagTipTitle.
  ///
  /// In en, this message translates to:
  /// **'Power Saving Optimizations Active'**
  String get batteryDiagTipTitle;

  /// No description provided for @batteryDiagTipSub.
  ///
  /// In en, this message translates to:
  /// **'• AppWidget updatePeriodMillis=0 (event-driven push only)\n• Pedometer sensor unregistered in background & throttled to 30s\n• Bus & workout timers auto-pause when screen is invisible or backgrounded\n• GPS permission requested at most once, coordinates cached for 6h'**
  String get batteryDiagTipSub;

  /// No description provided for @widgetGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Widget to Home Screen'**
  String get widgetGuideTitle;

  /// No description provided for @widgetGuideTileSub.
  ///
  /// In en, this message translates to:
  /// **'View today\'s classes, remaining calories & steps right on your home screen'**
  String get widgetGuideTileSub;

  /// No description provided for @widgetGuideHeader.
  ///
  /// In en, this message translates to:
  /// **'Pin \"Life Assistant\" to Your Home Screen'**
  String get widgetGuideHeader;

  /// No description provided for @widgetGuideDesc.
  ///
  /// In en, this message translates to:
  /// **'See your daily schedule, remaining calorie budget, and live step count at a glance without opening the app.'**
  String get widgetGuideDesc;

  /// No description provided for @widgetGuideStep1.
  ///
  /// In en, this message translates to:
  /// **'1. Tap \"Add to Home Screen\" below (supported on Android 8.0+ launchers).'**
  String get widgetGuideStep1;

  /// No description provided for @widgetGuideStep2.
  ///
  /// In en, this message translates to:
  /// **'2. Or long-press an empty area on your phone\'s home screen → tap \"Widgets\".'**
  String get widgetGuideStep2;

  /// No description provided for @widgetGuideStep3.
  ///
  /// In en, this message translates to:
  /// **'3. Find \"Life Assistant\" and drag the 4×2 card onto your home screen.'**
  String get widgetGuideStep3;

  /// No description provided for @widgetGuidePinBtn.
  ///
  /// In en, this message translates to:
  /// **'Add to Home Screen Now'**
  String get widgetGuidePinBtn;

  /// No description provided for @widgetGuidePinSuccess.
  ///
  /// In en, this message translates to:
  /// **'System widget prompt opened — confirm on your home screen!'**
  String get widgetGuidePinSuccess;

  /// No description provided for @widgetGuidePinFallback.
  ///
  /// In en, this message translates to:
  /// **'Please long-press your home screen → Widgets → Life Assistant to add it.'**
  String get widgetGuidePinFallback;

  /// No description provided for @busOriginLabel.
  ///
  /// In en, this message translates to:
  /// **'Origin'**
  String get busOriginLabel;

  /// No description provided for @busDestinationLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get busDestinationLabel;

  /// No description provided for @busSwapStopsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Swap Origin & Destination'**
  String get busSwapStopsTooltip;

  /// No description provided for @busSameStopError.
  ///
  /// In en, this message translates to:
  /// **'Origin and destination cannot be the same stop'**
  String get busSameStopError;

  /// No description provided for @busAutoSwitchedDirToast.
  ///
  /// In en, this message translates to:
  /// **'Auto-switched direction to match {origin} → {dest}'**
  String busAutoSwitchedDirToast(String origin, String dest);

  /// No description provided for @busNoMoreTripsToday.
  ///
  /// In en, this message translates to:
  /// **'No more trips today'**
  String get busNoMoreTripsToday;

  /// No description provided for @busNoMoreTripsSub.
  ///
  /// In en, this message translates to:
  /// **'All buses for this segment have departed today · First bus tomorrow at {time}'**
  String busNoMoreTripsSub(String time);

  /// No description provided for @busTimelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Live Route Timeline ({slot})'**
  String busTimelineTitle(String slot);

  /// No description provided for @busStopPassedTag.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get busStopPassedTag;

  /// No description provided for @busStopCurrentTag.
  ///
  /// In en, this message translates to:
  /// **'Current Stop'**
  String get busStopCurrentTag;

  /// No description provided for @busStopInMinutesTag.
  ///
  /// In en, this message translates to:
  /// **'in {mins} min'**
  String busStopInMinutesTag(int mins);

  /// No description provided for @busStopArrivingNowTag.
  ///
  /// In en, this message translates to:
  /// **'Arriving'**
  String get busStopArrivingNowTag;

  /// No description provided for @busStopOriginTag.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get busStopOriginTag;

  /// No description provided for @busStopDestTag.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get busStopDestTag;

  /// No description provided for @busBusHereLabel.
  ///
  /// In en, this message translates to:
  /// **'Bus en route ({pct}%)'**
  String busBusHereLabel(int pct);

  /// No description provided for @busSelectSlotLabel.
  ///
  /// In en, this message translates to:
  /// **'Trip Slot:'**
  String get busSelectSlotLabel;

  /// No description provided for @busRefreshSpinToast.
  ///
  /// In en, this message translates to:
  /// **'Schedule & live position refreshed'**
  String get busRefreshSpinToast;

  /// No description provided for @aiPlanCardHeader.
  ///
  /// In en, this message translates to:
  /// **'Workout Plan Generated'**
  String get aiPlanCardHeader;

  /// No description provided for @aiPlanDayExerciseCount.
  ///
  /// In en, this message translates to:
  /// **'{count} exercises'**
  String aiPlanDayExerciseCount(int count);

  /// No description provided for @aiPlanViewDetailsBtn.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get aiPlanViewDetailsBtn;

  /// No description provided for @aiPlanImportBtn.
  ///
  /// In en, this message translates to:
  /// **'Import to Workout'**
  String get aiPlanImportBtn;

  /// No description provided for @aiPlanImportedDoneBtn.
  ///
  /// In en, this message translates to:
  /// **'Imported ✓'**
  String get aiPlanImportedDoneBtn;

  /// No description provided for @aiPlanGeneratingPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Generating workout plan…'**
  String get aiPlanGeneratingPlaceholder;

  /// No description provided for @aiPlanParseFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Structured plan block could not be parsed.'**
  String get aiPlanParseFailedHint;

  /// No description provided for @aiPlanShowRawReplyBtn.
  ///
  /// In en, this message translates to:
  /// **'Show Raw Reply'**
  String get aiPlanShowRawReplyBtn;

  /// No description provided for @aiPlanHideRawReplyBtn.
  ///
  /// In en, this message translates to:
  /// **'Hide Raw Reply'**
  String get aiPlanHideRawReplyBtn;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
