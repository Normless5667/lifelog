// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Life Assistant';

  @override
  String get tabToday => 'Today';

  @override
  String get tabSchedule => 'Schedule';

  @override
  String get tabDiet => 'Diet';

  @override
  String get tabWorkout => 'Workout';

  @override
  String get tabAi => 'AI Coach';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonGotIt => 'Got it';

  @override
  String get commonSkip => 'Skip';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonToday => 'Today';

  @override
  String get commonYesterday => 'Yesterday';

  @override
  String get commonTomorrow => 'Tomorrow';

  @override
  String get commonErrorTitle => 'Something went wrong';

  @override
  String get commonGoSettings => 'Open Settings';

  @override
  String get commonSavedToast => 'Saved successfully';

  @override
  String get commonDeleteRecordConfirm => 'Delete this record?';

  @override
  String get commonAtLeastOneField => 'Please fill in at least one field';

  @override
  String get commonInvalidNumber => 'Please enter a valid number';

  @override
  String commonRangeError(int min, int max) {
    return 'Range $min-$max';
  }

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get mealBreakfast => 'Breakfast';

  @override
  String get mealLunch => 'Lunch';

  @override
  String get mealDinner => 'Dinner';

  @override
  String get mealSnack => 'Snack';

  @override
  String get homeQuickRecord => 'Quick Log';

  @override
  String get homeQuickDiet => 'Log a Meal / Scan Food';

  @override
  String get homeQuickWorkout => 'Start Workout / Log Cardio';

  @override
  String get homeQuickWeight => 'Log Today\'s Weight';

  @override
  String get homeQuickBus => 'Bus Board & Switch Stop';

  @override
  String get homeHeroSnapMeal => 'Scan Food';

  @override
  String get homeHeroStartWorkout => 'Start Workout';

  @override
  String get homeHeroLogWeight => 'Log Weight';

  @override
  String get homeHeroAiCoach => 'AI Plan';

  @override
  String get homeQuickLogHint =>
      'Type what you ate (e.g. beef noodle soup with an egg)…';

  @override
  String get homeAiQuickLog => 'AI Quick Log';

  @override
  String homeStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-day streak',
      one: '1-day streak',
      zero: '0-day streak',
    );
    return '$_temp0';
  }

  @override
  String get homeStreakKeepGoing => 'Keep up the great momentum!';

  @override
  String get homeStreakStartHint =>
      'Log a meal or workout to start your streak';

  @override
  String get homeProfilePromptTitle => 'Complete Your Fitness Profile';

  @override
  String get homeProfilePromptSub =>
      'Take 30s to set height, goal & equipment for dynamic TDEE';

  @override
  String homeTodayClassesWeek(int week) {
    return 'Today\'s Classes · Week $week';
  }

  @override
  String get homeTodayClasses => 'Today\'s Classes';

  @override
  String get homeAllSchedule => 'Full Schedule';

  @override
  String get homeNoClassesToday =>
      'No classes today — rest up or hit a workout!';

  @override
  String get homeTodayWorkoutTitle => 'Today\'s Workout & Cardio';

  @override
  String get homeGoWorkout => 'Workout';

  @override
  String get homeNoWorkoutToday => 'No strength or cardio logged today';

  @override
  String get homeNoWorkoutSub =>
      'Workout burn automatically increases your daily calorie budget';

  @override
  String get homeStartWorkoutBtn => 'Start';

  @override
  String homeStrengthSummary(int count, int sets) {
    return 'Strength ${count}x ($sets sets)';
  }

  @override
  String homeCardioSummary(String mins) {
    return 'Cardio $mins min';
  }

  @override
  String homeWorkoutBurnSummary(String kcal) {
    return 'Total activity burn +$kcal kcal';
  }

  @override
  String get homeBodyStatus => 'Body Status';

  @override
  String homeWeightLabel(String weight) {
    return 'Weight $weight kg';
  }

  @override
  String get homeWeightNotLogged => 'Weight not logged yet';

  @override
  String homeBodyTargetSub(String goal, String kcal, String protein) {
    return 'Goal: $goal · Target $kcal kcal/d · P ${protein}g';
  }

  @override
  String get homeLogBodyBtn => 'Log';

  @override
  String get homeAiCoachBannerTitle => 'Ask Your AI Coach';

  @override
  String get homeAiCoachBannerSub =>
      'Meal advice, workout splits & weekly review based on your logs';

  @override
  String stepTitle(int steps, int goal) {
    return 'Today\'s Steps: $steps / $goal';
  }

  @override
  String get stepUnsupported =>
      'No hardware step sensor on this device (log walking/running in Workout)';

  @override
  String get stepPermissionNeeded =>
      'Grant Physical Activity permission to read the hardware pedometer';

  @override
  String stepBurnedSummary(String kcal) {
    return 'Step burn +$kcal kcal (added to today\'s calorie budget)';
  }

  @override
  String get stepAuthorize => 'Grant Access';

  @override
  String get weatherClear => 'Clear';

  @override
  String get weatherCloudy => 'Cloudy';

  @override
  String get weatherFoggy => 'Foggy';

  @override
  String get weatherRainy => 'Rainy';

  @override
  String get weatherSnowy => 'Snowy';

  @override
  String get weatherShowers => 'Showers';

  @override
  String get weatherThunderstorm => 'Thunderstorm';

  @override
  String get weatherTipRain => 'Bring an umbrella';

  @override
  String get weatherTipHot => 'Stay hydrated';

  @override
  String get weatherTipGreat => 'Great for outdoor activity';

  @override
  String weatherCompactSub(String min, String max, String precip, String tip) {
    return '$min~$max°C · Precip $precip% · $tip';
  }

  @override
  String get weatherSheetTitle => 'Weather Location & City (Proxy-Safe)';

  @override
  String get weatherAutoLocate => 'Auto GPS Location (6h cache)';

  @override
  String get weatherSearchCity => 'More Cities in Settings';

  @override
  String get dietRemaining => 'Remaining';

  @override
  String get dietExceeded => 'Over by';

  @override
  String dietConsumedTarget(String consumed, String target) {
    return 'Consumed $consumed / Target $target kcal';
  }

  @override
  String get dietEstimatedHint =>
      '(Default estimate — tap weight icon to set profile)';

  @override
  String get dietProtein => 'Protein';

  @override
  String get dietCarbs => 'Carbs';

  @override
  String get dietFat => 'Fat';

  @override
  String get dietBmr => 'BMR';

  @override
  String get dietTrainingBurn => 'Workout Burn';

  @override
  String get dietTodayIntake => 'Consumed';

  @override
  String get dietSurplus => 'Remaining';

  @override
  String get dietScanFood => 'Scan Food';

  @override
  String get dietPickGallery => 'Gallery';

  @override
  String get dietAiTextEstimate => 'AI Text';

  @override
  String get dietManualAdd => 'Log Meal';

  @override
  String dietEmptyMealHint(String meal) {
    return 'No $meal logged yet — tap to add or scan food above';
  }

  @override
  String dietDeleteMealConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get dietAiAnalyzing => 'AI is analyzing food & calories…';

  @override
  String dietCameraError(String error) {
    return 'Unable to open camera/gallery: $error';
  }

  @override
  String get dietPhotoHintTitle => 'Analyze Food Photo with AI';

  @override
  String get dietPhotoHintLabel => 'Optional notes';

  @override
  String get dietPhotoHintPlaceholder =>
      'e.g. half bowl of rice, skinless chicken leg, less oil';

  @override
  String get dietStartAnalyze => 'Analyze';

  @override
  String get dietTextEstimateTitle => 'Estimate Calories from Text';

  @override
  String get dietTextEstimateHint =>
      'Describe what you ate, e.g.:\nA bowl of beef noodle soup with a braised egg';

  @override
  String get dietEstimateBtn => 'Estimate';

  @override
  String get foodConfirmTitle => 'AI Estimate (Editable)';

  @override
  String get foodConfirmName => 'Food';

  @override
  String get foodConfirmAmount => 'Portion';

  @override
  String get foodConfirmKcal => 'Calories kcal';

  @override
  String get foodConfirmProtein => 'Protein g';

  @override
  String get foodConfirmCarbs => 'Carbs g';

  @override
  String get foodConfirmFat => 'Fat g';

  @override
  String get foodConfirmSaveBtn => 'Add to Today\'s Diet';

  @override
  String get mealEditAddTitle => 'Log a Meal';

  @override
  String get mealEditUpdateTitle => 'Edit Meal';

  @override
  String get mealEditTypeLabel => 'Meal';

  @override
  String get mealEditNameLabel => 'Food Name *';

  @override
  String get mealEditNameRequired => 'Please enter a food name';

  @override
  String get mealEditAmountLabel => 'Portion (e.g. 1 bowl / 200g)';

  @override
  String get mealEditKcalLabel => 'Calories';

  @override
  String busHomeTitle(String stop) {
    return 'Bus · $stop';
  }

  @override
  String busHomeNextCountdown(String dir, String time, int mins) {
    return '$dir · Next $time (in $mins min)';
  }

  @override
  String busHomeEndedToday(String time) {
    return 'Service ended today (First bus tomorrow $time)';
  }

  @override
  String get busHomeWeekend => 'Weekend (Runs Mon–Fri only)';

  @override
  String get busBoardTitle => 'Live Bus Board';

  @override
  String get busStopReminderSettings => 'Stop & Reminder Settings';

  @override
  String get busRouteActions => 'Route Actions';

  @override
  String get busMenuSwitchImport => 'Switch / Import Route';

  @override
  String get busMenuShareJson => 'Share Route JSON';

  @override
  String get busMenuDownloadTemplate => 'Download JSON Template';

  @override
  String get busSwitchImportBtn => 'Switch';

  @override
  String get busMyFavStopLabel => 'My Stop: ';

  @override
  String busReminderBadgeOn(int mins) {
    return 'Remind ${mins}m prior';
  }

  @override
  String get busReminderBadgeOff => 'Reminder off';

  @override
  String get busVibrationSwitchTitle => 'Arrival Vibration Reminder (Mon–Fri)';

  @override
  String get busRemindBeforeLabel => 'Remind Before';

  @override
  String busRemindMinsOption(int mins) {
    return '$mins min before';
  }

  @override
  String get busOutboundSegment => 'Outbound → BUV';

  @override
  String get busInboundSegment => 'Inbound ← Home';

  @override
  String get busWeekendBanner =>
      'Weekend today (runs Mon–Fri only) — showing weekday schedule preview';

  @override
  String busEndedTodayBanner(String time, String stop) {
    return 'All trips ended for today · First bus tomorrow $time ($stop)';
  }

  @override
  String get busStatusImminent => 'Arriving ≤5m';

  @override
  String get busStatusSoon => 'Approaching';

  @override
  String get busStatusUpcoming => 'Scheduled';

  @override
  String get busStatusDeparted => 'Departed';

  @override
  String get busStatusEnded => 'Ended Today';

  @override
  String get busNextBadge => 'NEXT';

  @override
  String busDepartedAtStop(String stop, String time) {
    return 'Passed $stop at $time';
  }

  @override
  String busCountdownHoursMinsSecs(int hours, String mins, String secs) {
    return 'In ${hours}h ${mins}m ${secs}s';
  }

  @override
  String busCountdownMinsSecs(String mins, String secs) {
    return 'In ${mins}m ${secs}s';
  }

  @override
  String get busEnRoute => 'En Route';

  @override
  String get busWaitingDepart => 'Waiting';

  @override
  String get busArrivingSoon => 'Arriving';

  @override
  String busProgressStart(String time) {
    return 'Start $time';
  }

  @override
  String busProgressPrev(String time) {
    return 'Prev $time';
  }

  @override
  String busProgressNow(String time) {
    return 'Now $time';
  }

  @override
  String busProgressTarget(String time) {
    return 'Stop $time';
  }

  @override
  String get busYourFavStopTag => '← Your Stop';

  @override
  String get busFooterTipTitle =>
      'Tip: Tap any stop inside a card to set it as your favorite stop';

  @override
  String get busFooterTipSub =>
      'Sorted by upcoming departure. ≤5 min alerts with red-orange breathing glow; departed buses sink to the bottom.';

  @override
  String busFavStopToast(String stop) {
    return 'Favorite stop updated to $stop';
  }

  @override
  String busSwitchedRouteToast(String name) {
    return 'Switched route to: $name';
  }

  @override
  String busImportedRouteToast(String name) {
    return 'Imported & activated route: $name';
  }

  @override
  String get busValidationFailedTitle => 'Route Validation Failed';

  @override
  String get busSheetTitle => 'Switch or Manage Bus Routes';

  @override
  String get busDownloadTemplateBtn => 'Template';

  @override
  String get busBadgeBuiltin => 'Built-in';

  @override
  String get busBadgeImported => 'Imported';

  @override
  String get busBadgeCustom => 'Custom';

  @override
  String busStopsCountSub(int outCount, int inCount) {
    return 'Outbound $outCount stops · Inbound $inCount stops';
  }

  @override
  String busDeleteRouteConfirm(String name) {
    return 'Delete route \"$name\"?';
  }

  @override
  String get busManualCreateBtn => 'Create Route';

  @override
  String get busImportJsonBtn => 'Import JSON';

  @override
  String get busCustomDialogCreateTitle => 'Create Custom Bus Route';

  @override
  String get busCustomDialogEditTitle => 'Edit Bus Route';

  @override
  String get busCustomRouteNameLabel => 'Route Name *';

  @override
  String get busCustomSchoolLabel => 'School / Organization (Optional)';

  @override
  String get busCustomOutboundHint =>
      'Outbound stops & times (one per line: Stop Name: 07:30, 09:30)';

  @override
  String get busCustomInboundHint =>
      'Inbound stops & times (one per line: Stop Name: 12:00, 17:30)';

  @override
  String get busCustomValidateSaveBtn => 'Validate & Save';

  @override
  String scheduleWeekTitle(int week) {
    return 'Week $week';
  }

  @override
  String get scheduleCurrentWeek => 'Current Week';

  @override
  String get scheduleBackToCurrent => 'Tap for Current Week';

  @override
  String get scheduleImportTitle => 'Import Schedule';

  @override
  String get scheduleImportSub =>
      'Import from screenshot, camera photo, or pasted course text';

  @override
  String get scheduleImportPresetTitle => 'Load Default BUV Schedule';

  @override
  String get scheduleImportPresetSub =>
      'Database Principles / Machine Learning / UX Design (Mon–Fri)';

  @override
  String get scheduleImportGalleryTitle => 'Pick Schedule Screenshot (AI)';

  @override
  String get scheduleImportGallerySub =>
      'Extract all courses automatically from a timetable screenshot';

  @override
  String get scheduleImportCameraTitle => 'Scan Schedule with Camera';

  @override
  String get scheduleImportCameraSub =>
      'Take a photo of your screen or printed schedule';

  @override
  String get scheduleImportTextTitle => 'Paste Course Text / JSON';

  @override
  String get scheduleImportTextSub =>
      'Paste course list text and let AI parse it';

  @override
  String get schedulePasteDialogTitle => 'Paste Schedule Text';

  @override
  String get schedulePasteDialogHint =>
      'Paste course text from your school portal, e.g.:\nDatabase Principles Mon 1-3 Weeks 1-16 E.3-8';

  @override
  String get scheduleAiParseBtn => 'AI Parse';

  @override
  String get scheduleAiParsing => 'AI is extracting all courses…';

  @override
  String scheduleConfirmImportTitle(int count) {
    return 'Found $count courses (select to import)';
  }

  @override
  String get scheduleReplaceAllSwitch =>
      'Clear existing courses before importing';

  @override
  String get scheduleWeekEvery => 'Every week';

  @override
  String get scheduleWeekOdd => 'Odd weeks';

  @override
  String get scheduleWeekEven => 'Even weeks';

  @override
  String scheduleCourseImportSub(
    String weekday,
    int start,
    int end,
    int startWeek,
    int endWeek,
    String weekType,
  ) {
    return '$weekday Sec $start-$end · Wk $startWeek-$endWeek ($weekType)';
  }

  @override
  String get scheduleConfirmImportBtn => 'Confirm Import';

  @override
  String scheduleImportedToast(int count) {
    return 'Imported $count courses';
  }

  @override
  String get scheduleSettingsTitle => 'Schedule & Class Reminders';

  @override
  String get scheduleColorOsWarnTitle =>
      'Notification Permission May Be Restricted';

  @override
  String get scheduleColorOsWarnSub =>
      'Open system notification settings and enable High Importance, Banner & Vibration for class reminders.';

  @override
  String get scheduleOpenChannelSettingsBtn =>
      'Enable High Priority & Vibration';

  @override
  String get scheduleEnableReminderSwitch =>
      'Pre-Class Vibration & Banner Alert';

  @override
  String get scheduleEnableReminderSub =>
      'Hardware alarm vibration + heads-up notification before class';

  @override
  String get scheduleDiagnoseBtn => 'Diagnostics';

  @override
  String get scheduleSysNotifBtn => 'System Settings';

  @override
  String get scheduleTestVibBtn => 'Test Vibration';

  @override
  String get scheduleTestVibToast => 'Triggered strong vibration test alert!';

  @override
  String get scheduleUseSysClockSwitch =>
      'Also Set System Clock Alarm (Optional)';

  @override
  String get scheduleUseSysClockSub =>
      'Creates an alarm in the phone\'s built-in Clock app for 100% reliability';

  @override
  String get scheduleWriteNextAlarmBtn => 'Add Next Class to System Clock';

  @override
  String scheduleWriteNextAlarmToast(String info) {
    return 'System alarm set for next class: $info';
  }

  @override
  String get scheduleNoUpcomingClassToast =>
      'No upcoming classes in the next 7 days';

  @override
  String get scheduleFirstWeekMonLabel => 'Monday of Week 1';

  @override
  String get schedulePickSemesterStartHelp =>
      'Pick any day in Week 1 of the semester';

  @override
  String get scheduleSectionsPerDayLabel => 'Periods per Day';

  @override
  String scheduleSectionsCount(int count) {
    return '$count periods';
  }

  @override
  String get scheduleAddCourseTooltip => 'Add Course';

  @override
  String scheduleRainBanner(String precip) {
    return 'Rain expected today ($precip% precip) — remember to bring an umbrella!';
  }

  @override
  String get scheduleEmptyTapHint => 'Tap any cell to add, or ';

  @override
  String get scheduleEmptyImportBtn => 'Import from Screenshot / Text';

  @override
  String scheduleMonthHeader(int month) {
    return 'M$month';
  }

  @override
  String scheduleCourseDetailSection(
    String weekday,
    String timeRange,
    int start,
    int end,
  ) {
    return '$weekday $timeRange (Period $start-$end)';
  }

  @override
  String scheduleCourseDetailWeeks(
    int startWeek,
    int endWeek,
    String weekType,
  ) {
    return 'Weeks $startWeek-$endWeek · $weekType';
  }

  @override
  String scheduleDeleteCourseConfirm(String name) {
    return 'Delete course \"$name\"?';
  }

  @override
  String get courseEditAddTitle => 'Add Course';

  @override
  String get courseEditUpdateTitle => 'Edit Course';

  @override
  String get courseEditNameLabel => 'Course Name *';

  @override
  String get courseEditNameRequired => 'Please enter course name';

  @override
  String get courseEditLocationLabel => 'Classroom';

  @override
  String get courseEditTeacherLabel => 'Instructor';

  @override
  String get courseEditWeekdayTitle => 'Day of Week';

  @override
  String get courseEditSectionTitle => 'Periods & Time';

  @override
  String get courseEditStartSection => 'Start Period';

  @override
  String get courseEditEndSection => 'End Period';

  @override
  String courseEditSectionItem(int num, String time) {
    return 'Period $num ($time)';
  }

  @override
  String get courseEditSectionOrderError =>
      'End period cannot be earlier than start period';

  @override
  String get courseEditWeeksTitle => 'Week Range & Frequency';

  @override
  String courseEditWeeksSummary(int start, int end, String timeRange) {
    return 'Weeks $start - $end · $timeRange';
  }

  @override
  String get courseEditColorTitle => 'Course Color';

  @override
  String get courseEditSaveBtn => 'Save Course';

  @override
  String get workoutTitle => 'Workout & Cardio';

  @override
  String get workoutExerciseLibBtn => 'Exercises';

  @override
  String get workoutStartStrengthBtn => 'Start Strength';

  @override
  String get workoutLogCardioBtn => 'Log Cardio';

  @override
  String get workoutTabStrength => 'Strength (Sets & Timer)';

  @override
  String get workoutTabCardio => 'Cardio (MET Burn)';

  @override
  String workoutActivePlanTitle(String name) {
    return 'Active Plan: $name';
  }

  @override
  String get workoutTapSplitHint => 'Tap a split to start';

  @override
  String workoutPlanSplitChip(String day, String focus, int count) {
    return '$day · $focus ($count exercises)';
  }

  @override
  String get workoutVolumeChartTitle => 'Recent Strength Volume (kg)';

  @override
  String get workoutHistoryTitle => 'Strength Sessions';

  @override
  String get workoutEmptyStrengthHint =>
      'No strength workouts logged yet\nTap below to start a timed session, or ask AI Coach for a custom split';

  @override
  String get workoutEmptyStrengthBtn => 'Start First Workout';

  @override
  String get workoutEmptySessionTitle => 'Empty Session';

  @override
  String workoutSessionDuration(int mins) {
    return '$mins min';
  }

  @override
  String workoutSessionSets(int sets) {
    return '$sets working sets';
  }

  @override
  String workoutSessionVolume(String volume) {
    return 'Vol $volume kg';
  }

  @override
  String workoutSessionBurn(String kcal) {
    return '~$kcal kcal';
  }

  @override
  String get workoutDeleteSessionConfirm => 'Delete this workout session?';

  @override
  String get workoutEmptyCardioHint =>
      'No cardio sessions logged yet\nLog walking, running, cycling, swimming or jump rope with automatic MET calorie burn';

  @override
  String get workoutEmptyCardioBtn => 'Add Cardio Session';

  @override
  String workoutCardioItemTitle(String type, String mins) {
    return '$type · $mins min';
  }

  @override
  String get workoutDeleteCardioConfirm => 'Delete this cardio record?';

  @override
  String workoutCardioSavedToast(String kcal) {
    return 'Cardio logged: ~$kcal kcal burned (added to today\'s calorie budget)';
  }

  @override
  String get workoutAdjustedBadge => 'Adjusted';

  @override
  String get workoutAdjustTooltip => 'Adjust duration & burn';

  @override
  String get workoutAdjustTitle => 'Adjust Workout';

  @override
  String get workoutAdjustDurationLabel => 'Actual Duration';

  @override
  String get workoutAdjustDurationUnit => 'min';

  @override
  String get workoutAdjustBurnLabel => 'Calories Burned';

  @override
  String workoutAdjustHint(String kcal) {
    return 'Estimated $kcal kcal · editable';
  }

  @override
  String get workoutAdjustResetBtn => 'Reset to Auto';

  @override
  String workoutAdjustSavedToast(String kcal) {
    return 'Adjustment saved ($kcal kcal)';
  }

  @override
  String get workoutQuickLogBtn => 'Quick Log';

  @override
  String get workoutQuickLogTitle => 'Quick Log Workout';

  @override
  String get workoutQuickLogNoteLabel => 'Workout note (optional)';

  @override
  String get workoutQuickLogNoteDefault => 'Quick-logged workout';

  @override
  String get workoutQuickLogExerciseLabel => 'Exercise (optional)';

  @override
  String get workoutQuickLogNone => 'None';

  @override
  String get workoutQuickLogSetsLabel => 'Sets (optional)';

  @override
  String get workoutQuickLogDurationRequired =>
      'Enter a duration greater than 0 min';

  @override
  String workoutQuickLogSavedToast(int mins, String kcal) {
    return 'Logged ($mins min · $kcal kcal)';
  }

  @override
  String workoutCompactSets(int count) {
    return '$count sets';
  }

  @override
  String workoutCompactDuration(int mins) {
    return '$mins min';
  }

  @override
  String workoutCompactBurnEst(String kcal) {
    return '~$kcal kcal';
  }

  @override
  String workoutCompactBurnExact(String kcal) {
    return '$kcal kcal';
  }

  @override
  String workoutSingleDayVolumeSub(String date) {
    return '$date · Latest strength session';
  }

  @override
  String get cardioDialogAddTitle => 'Log Cardio';

  @override
  String get cardioDialogEditTitle => 'Edit Cardio';

  @override
  String get cardioTypeLabel => 'Cardio Type';

  @override
  String get cardioDurationLabel => 'Duration *';

  @override
  String get cardioMinutesSuffix => 'min';

  @override
  String get cardioDistanceLabel => 'Distance (Opt)';

  @override
  String cardioEstBurnLabel(String weight, String met) {
    return 'Estimated Burn (${weight}kg × MET $met)';
  }

  @override
  String get cardioDurationRequired => 'Please enter a duration greater than 0';

  @override
  String get cardioTypeWalk => 'Walking';

  @override
  String get cardioTypeBriskWalk => 'Brisk Walk';

  @override
  String get cardioTypeJog => 'Jogging';

  @override
  String get cardioTypeRun => 'Running';

  @override
  String get cardioTypeCycle => 'Cycling';

  @override
  String get cardioTypeSwim => 'Swimming';

  @override
  String get cardioTypeJumpRope => 'Jump Rope';

  @override
  String get cardioTypeOther => 'Other';

  @override
  String sessionHeaderStats(int sets, String volume) {
    return '$sets sets · $volume kg';
  }

  @override
  String get sessionFinishBtn => 'Finish';

  @override
  String get sessionAddExerciseBtn => 'Add Exercise';

  @override
  String get sessionEmptyHint =>
      'Workout timer is running!\nTap below to add exercises, and tap ✓ on each set to start the rest timer';

  @override
  String get sessionSelectExerciseBtn => 'Select Exercise';

  @override
  String sessionRestActive(String clock, String paused) {
    return 'Rest Timer: $clock$paused';
  }

  @override
  String get sessionRestPausedTag => ' (Paused)';

  @override
  String get sessionRestResume => 'Resume';

  @override
  String get sessionRestPause => 'Pause';

  @override
  String get sessionRestSkip => 'Skip';

  @override
  String get sessionRestDurationLabel => 'Rest Timer:';

  @override
  String get sessionRestStartNow => 'Start Rest Timer';

  @override
  String get sessionRestFinishedToast =>
      'Rest finished! Time for your next set';

  @override
  String sessionPlanTargetHint(int sets, String reps, String weightHint) {
    return 'Target: $sets sets × $reps$weightHint';
  }

  @override
  String sessionLastCardioHint(String records) {
    return 'Last: $records';
  }

  @override
  String sessionLastStrengthHint(String records) {
    return 'Last: $records';
  }

  @override
  String get sessionWarmupTag => 'W';

  @override
  String get sessionCardioDuration => 'Duration';

  @override
  String get sessionCardioMins => 'min';

  @override
  String get sessionStrengthWeight => 'Weight';

  @override
  String get sessionCardioSteps => 'Steps';

  @override
  String get sessionCardioStepsUnit => 'steps';

  @override
  String get sessionStrengthReps => 'Reps';

  @override
  String get sessionStrengthRepsUnit => 'reps';

  @override
  String get sessionCompleteSetTooltip => 'Complete set & start rest timer';

  @override
  String get sessionAddCardioRow => 'Add another interval';

  @override
  String get sessionAddStrengthRow => 'Add Set (tap ✓ to start rest timer)';

  @override
  String sessionFinishedToast(int mins, int sets, String volume, String kcal) {
    return 'Workout complete! $mins min · $sets sets · Vol $volume kg · ~$kcal kcal';
  }

  @override
  String get exerciseSelectTitle => 'Select Exercise';

  @override
  String get exerciseLibTitle => 'Exercise Library';

  @override
  String get exerciseAddCustomBtn => 'Custom Exercise';

  @override
  String get exerciseCustomDialogTitle => 'Add Custom Exercise';

  @override
  String get exerciseCategoryLabel => 'Muscle Group';

  @override
  String get exerciseNameLabel => 'Exercise Name';

  @override
  String exerciseCustomSubtitle(String category) {
    return '$category · Custom';
  }

  @override
  String exercisePresetSubtitle(String category) {
    return '$category Training';
  }

  @override
  String exerciseDeleteConfirm(String name) {
    return 'Delete custom exercise \"$name\"?';
  }

  @override
  String get catChest => 'Chest';

  @override
  String get catBack => 'Back';

  @override
  String get catLegs => 'Legs';

  @override
  String get catShoulders => 'Shoulders';

  @override
  String get catArms => 'Arms';

  @override
  String get catCore => 'Core';

  @override
  String get catCardio => 'Cardio';

  @override
  String get catOther => 'Other';

  @override
  String get bodyTitle => 'Body Metrics';

  @override
  String get bodyProfileBtn => 'Profile';

  @override
  String get bodyLogWeightBtn => 'Log Weight';

  @override
  String get bodyNoProfileTitle => 'Fitness Profile Incomplete';

  @override
  String get bodyNoProfileSub =>
      'Tap Profile at the top right for accurate BMR & TDEE calculation';

  @override
  String get bodyWeightTrendTitle => 'Weight Trend';

  @override
  String get bodyEmptyChartHint =>
      'Log your first weight entry to see the trend chart';

  @override
  String get bodyEmptyChartBtn => 'Log Weight Now';

  @override
  String get bodyHistoryTitle => 'History';

  @override
  String get bodyEmptyHistoryHint =>
      'No body metrics logged yet\nMorning fasting weight is the most consistent';

  @override
  String get bodyEmptyHistoryBtn => 'Log Today\'s Weight';

  @override
  String bodyFatTag(String fat) {
    return 'Body Fat $fat%';
  }

  @override
  String bodyWaistTag(String waist) {
    return 'Waist $waist cm';
  }

  @override
  String get bodyStatWeight => 'Weight kg';

  @override
  String get bodyStatBmr => 'BMR';

  @override
  String get bodyStatTdee => 'TDEE';

  @override
  String get bodyStatTargetKcal => 'Target kcal';

  @override
  String get bodyStatGoal => 'Current Goal';

  @override
  String bodyChartTargetLine(String weight) {
    return 'Goal ${weight}kg';
  }

  @override
  String get bodyDialogTitle => 'Log Body Metrics';

  @override
  String get bodyWeightLabel => 'Weight';

  @override
  String get bodyFatLabel => 'Body Fat (Optional)';

  @override
  String get bodyWaistLabel => 'Waist (Optional)';

  @override
  String get bmiUnderweight => 'Underweight';

  @override
  String get bmiNormal => 'Normal';

  @override
  String get bmiOverweight => 'Overweight';

  @override
  String get bmiObese => 'Obese';

  @override
  String get profileTitle => 'Body & Training Profile';

  @override
  String get profileGenderSection => 'Gender';

  @override
  String get profileMale => 'Male';

  @override
  String get profileFemale => 'Female';

  @override
  String get profileAgeHeightSection => 'Age & Height';

  @override
  String get profileAgeLabel => 'Age';

  @override
  String get profileAgeUnit => 'yrs';

  @override
  String get profileHeightLabel => 'Height';

  @override
  String get profileActivityGoalSection => 'Activity Level & Goal';

  @override
  String get profileActivityLabel => 'Daily Non-Exercise Activity Level';

  @override
  String get profileTargetWeightLabel =>
      'Target Weight (Opt, shown on weight chart)';

  @override
  String get profileTrainingConditionSection =>
      'Training Setup (Used by AI Coach)';

  @override
  String get profileExperienceLabel => 'Training Experience';

  @override
  String get profileWeeklyDaysLabel => 'Days / Week';

  @override
  String profileWeeklyDaysItem(int days) {
    return '$days days/wk';
  }

  @override
  String get profileSessionMinsLabel => 'Session Length';

  @override
  String profileSessionMinsItem(int mins) {
    return '$mins min';
  }

  @override
  String get profileEquipmentLabel => 'Available Equipment';

  @override
  String get profileInjuriesLabel => 'Injuries or Limitations (Optional)';

  @override
  String get profileInjuriesHint =>
      'e.g. knee discomfort, lower back issue, none';

  @override
  String get profileSaveBtn => 'Save Profile';

  @override
  String get onboardingTitle => 'Personalize Your Health & Training';

  @override
  String get onboardingIntro =>
      'Take 30 seconds to fill in your basics. We\'ll calculate your dynamic calorie budget and include your setup when chatting with AI Coach.';

  @override
  String get onboardingStep1 => '1. Basic Body Metrics';

  @override
  String get onboardingCurrentWeight => 'Current Weight';

  @override
  String get onboardingTargetWeight => 'Target Weight (Opt)';

  @override
  String get onboardingStep2 => '2. Goal & Daily Activity';

  @override
  String get onboardingStep3 => '3. Experience & Equipment';

  @override
  String get onboardingFinishBtn => 'Complete & Initialize Plan';

  @override
  String get onboardingSavedToast =>
      'Profile saved! TDEE and AI Coach context initialized.';

  @override
  String get goalLose => 'Fat Loss';

  @override
  String get goalMaintain => 'Maintain';

  @override
  String get goalGain => 'Muscle Gain';

  @override
  String get goalFitness => 'Fitness & Conditioning';

  @override
  String get actSedentary => 'Sedentary (Desk job, little exercise)';

  @override
  String get actLight => 'Lightly Active (1–3 days/wk)';

  @override
  String get actModerate => 'Moderately Active (3–5 days/wk)';

  @override
  String get actHigh => 'Very Active (6–7 days/wk)';

  @override
  String get actExtreme => 'Extra Active (Physical job / 2x daily)';

  @override
  String get expNone => 'Complete Beginner';

  @override
  String get expBeginner => 'Under 6 Months';

  @override
  String get expIntermediate => '1–3 Years';

  @override
  String get expAdvanced => '3+ Years';

  @override
  String get equipBodyweight => 'Bodyweight Only';

  @override
  String get equipDumbbell => 'Dumbbells';

  @override
  String get equipBarbell => 'Barbell & Rack';

  @override
  String get equipGym => 'Full Commercial Gym';

  @override
  String get aiTitle => 'AI Health Coach';

  @override
  String get aiClearChatTooltip => 'Clear Chat';

  @override
  String get aiClearChatConfirm => 'Clear all chat history?';

  @override
  String get aiSettingsTooltip => 'AI Settings';

  @override
  String get aiQuickGeneratePlan => 'Generate Workout Plan (Importable)';

  @override
  String get aiQuickTodaySummary => 'Today\'s Review';

  @override
  String get aiQuickWeekSummary => 'Weekly Review';

  @override
  String get aiQuickNextMeal => 'What to Eat Next';

  @override
  String get aiPromptGeneratePlan =>
      'Please design a weekly workout split based on my profile (goal, experience, weekly days, session duration, equipment, injuries) and free slots in my class schedule, and include the importable JSON workout plan block at the end.';

  @override
  String get aiPromptTodaySummary =>
      'Please review my meals and workouts logged today, and suggest what I should eat for my next meal.';

  @override
  String get aiPromptWeekSummary =>
      'Please summarize my calorie intake, macros, and training over the last 7 days, highlighting strengths and areas to improve.';

  @override
  String get aiPromptNextMeal =>
      'Based on my remaining calories and macro targets today, recommend 2-3 practical meal options.';

  @override
  String get aiEmptyHint =>
      'AI Coach automatically reads your profile, meals, workouts & class schedule\nTap \"Generate Workout Plan\" above to create a custom split and import it in one tap';

  @override
  String get aiEmptyActionBtn => 'Generate My Custom Plan';

  @override
  String aiImportPlanBtn(String name) {
    return 'Import to Workout Plan ($name)';
  }

  @override
  String aiPlanImportedToast(String name) {
    return 'Imported \"$name\"! Open the Workout tab and tap any split to start training';
  }

  @override
  String get aiInputHint =>
      'Ask about nutrition, workouts, or say \"Build me a workout plan\"…';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearanceSection => 'Appearance, Font & Language';

  @override
  String get settingsThemeMode => 'Theme Mode';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsFontSize => 'Font Size';

  @override
  String get settingsFontSmall => 'Small';

  @override
  String get settingsFontMedium => 'Standard';

  @override
  String get settingsFontLarge => 'Large';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLangSystem => 'System';

  @override
  String get settingsLangZh => '简体中文';

  @override
  String get settingsLangEn => 'English';

  @override
  String get settingsWeatherSection => 'Weather City & Location';

  @override
  String get settingsWeatherModeAuto =>
      'Current: Auto GPS Location (6h cache, IP fallback)';

  @override
  String settingsWeatherModeManual(String city) {
    return 'Current: Locked City · $city';
  }

  @override
  String get settingsWeatherProxyHint =>
      'If using a VPN/proxy without GPS, pick your city below to lock accurate local weather:';

  @override
  String get settingsWeatherAutoChip => 'Auto GPS';

  @override
  String get settingsWeatherAutoToast =>
      'Switched to Auto GPS location and refreshed weather';

  @override
  String settingsWeatherLockedToast(String city) {
    return 'Locked weather city to: $city';
  }

  @override
  String get settingsWeatherCustomLabel => 'Search Custom City';

  @override
  String get settingsWeatherCustomHint =>
      'e.g. Ho Chi Minh City / Hanoi / London';

  @override
  String get settingsWeatherSetBtn => 'Set City';

  @override
  String get settingsChatAiSection => 'Chat AI Model (DeepSeek / OpenAI)';

  @override
  String get settingsChatAiHint =>
      'Pick a provider preset below or enter a Base URL. Your API Key is stored encrypted on device.';

  @override
  String get settingsPresetDeepseek => 'DeepSeek (Default)';

  @override
  String get settingsPresetOpenai => 'OpenAI';

  @override
  String get settingsPresetQwen => 'Qwen (DashScope)';

  @override
  String get settingsBaseUrlLabel => 'Base URL (e.g. deepseek or full URL)';

  @override
  String get settingsApiKeyLabel => 'API Key';

  @override
  String get settingsModelNameLabel => 'Model Name';

  @override
  String get settingsTestingBtn => 'Testing…';

  @override
  String get settingsTestConnectionBtn => 'Test Connection';

  @override
  String settingsTestSuccessToast(String reply) {
    return 'Connected: $reply';
  }

  @override
  String get settingsVisionSection => 'Food Scanner Vision Model';

  @override
  String get settingsVisionSameSwitch =>
      'Share configuration with Chat AI model';

  @override
  String get settingsVisionSameSub =>
      'Turn off to select a dedicated vision model (e.g. Qwen-VL / GPT-4o mini) if your chat model doesn\'t support images';

  @override
  String get settingsVisionBaseUrlLabel => 'Vision Base URL';

  @override
  String get settingsVisionApiKeyLabel => 'Vision API Key';

  @override
  String get settingsVisionModelLabel => 'Vision Model Name';

  @override
  String get settingsTestVisionBtn => 'Test Vision API';

  @override
  String get settingsSaveAiBtn => 'Save AI Configuration';

  @override
  String get settingsSystemDataSection => 'Notifications & Data Backup';

  @override
  String get settingsDiagTileTitle => 'Notification & Vibration Diagnostics';

  @override
  String get settingsDiagTileSub =>
      'Fix silent notifications, enable high-priority banners & alarms';

  @override
  String get settingsExportJsonTitle => 'Export Full Backup (JSON)';

  @override
  String get settingsExportJsonSub =>
      'Includes schedule, meals, workouts, cardio & body metrics';

  @override
  String get settingsExportCsvTitle => 'Export Spreadsheets (CSV)';

  @override
  String get settingsExportCsvSub =>
      'View meals, weight & cardio history in Excel or Sheets';

  @override
  String get settingsAboutTileTitle => 'About Life Assistant';

  @override
  String get settingsAboutTileSub =>
      'Version v2.1.7 · Co-developed with DaFeiYu';

  @override
  String get usageSectionTitle => 'Usage Telemetry & Analytics';

  @override
  String get usageSwitchTitle => 'Record App Usage & Performance';

  @override
  String usageCountSub(int count) {
    return '$count events recorded (kept locally for 30 days, never uploaded)';
  }

  @override
  String get usageExportBtn => 'Export Data';

  @override
  String get usageClearBtn => 'Clear';

  @override
  String get usageClearConfirm => 'Clear all recorded usage telemetry data?';

  @override
  String get usageClearedToast => 'Usage telemetry data cleared';

  @override
  String get usageExportDialogTitle => 'Export Usage & Performance Data';

  @override
  String get usageExportRangeLabel => 'Select Time Range:';

  @override
  String get usageRange1d => 'Last 1 Day';

  @override
  String get usageRange7d => 'Last 7 Days';

  @override
  String get usageRange30d => 'Last 30 Days';

  @override
  String get usageRangeAll => 'All Time';

  @override
  String get usageExportJsonBtn => 'Export JSON (Summary + Events)';

  @override
  String get usageExportCsvBtn => 'Export CSV (For Excel)';

  @override
  String get diagTitle => 'Notification & Vibration Diagnostics';

  @override
  String get diagRefreshTooltip => 'Re-check';

  @override
  String get diagStatusGood => 'Notifications & Strong Vibration Ready';

  @override
  String get diagStatusWarn => 'Notifications or Vibration May Be Restricted';

  @override
  String diagDeviceChannelSub(
    String device,
    String channelName,
    String channelId,
  ) {
    return 'Device: $device\nChannel: $channelName ($channelId)';
  }

  @override
  String get diagSectionPermissions => 'Permission & Channel Status';

  @override
  String get diagAppNotifTitle => 'App Notifications (areNotificationsEnabled)';

  @override
  String get diagAppNotifOn => 'Enabled';

  @override
  String get diagAppNotifOff =>
      'Disabled — you won\'t receive class or bus reminders';

  @override
  String get diagImportanceTitle => 'Channel Importance';

  @override
  String get diagImp0 => '0 - Disabled (NONE)';

  @override
  String get diagImp1 => '1 - Min (Silent, no banner)';

  @override
  String get diagImp2 => '2 - Low (Downgraded to silent notification)';

  @override
  String get diagImp3 => '3 - Default (May not pop up banner)';

  @override
  String diagImpHigh(int imp) {
    return '$imp - High/Max (Banner + Vibration enabled)';
  }

  @override
  String get diagVibrateTitle => 'Channel Vibration (shouldVibrate)';

  @override
  String get diagVibrateOn => 'Allowed (+ hardware alarm vibration backup)';

  @override
  String get diagVibrateOff =>
      'Channel vibration disabled — tap below to enable';

  @override
  String get diagSoundTitle => 'Notification Sound';

  @override
  String get diagSoundOn => 'Sound configured';

  @override
  String get diagSoundOff => 'Muted';

  @override
  String get diagExactAlarmTitle =>
      'Exact Alarm Permission (canScheduleExactAlarms)';

  @override
  String get diagExactAlarmOn => 'Authorized for exact timing';

  @override
  String get diagExactAlarmOff => 'Not authorized — reminders may be delayed';

  @override
  String get diagSectionColorOs => 'ColorOS / Android Quick Fix';

  @override
  String get diagColorOsGuide =>
      'If notifications don\'t pop up or vibrate on OPPO / ColorOS devices, tap the buttons below to allow notifications and set the channel to High Importance with Banner & Vibration enabled:';

  @override
  String get diagBtn1AppNotif => '1. Open App Notification Settings';

  @override
  String get diagBtn2Channel => '2. Open Reminder Channel Settings';

  @override
  String get diagBtn3Test => '3. Send Full-Screen Banner + Vibration Test';

  @override
  String get diagTestSentToast =>
      'Test alert sent (with alarm vibration + sound + banner)';

  @override
  String get aboutTitle => 'About · Life Assistant';

  @override
  String get aboutVersion => 'Version v2.1.7 (Build 13)';

  @override
  String get aboutBadge =>
      'Co-developed & supervised by DaFeiYu · With you every day';

  @override
  String get aboutDesc =>
      'All-in-one personal assistant featuring class schedules, live shuttle bus timeline (built-in BUV + custom/JSON import), GPS weather, AI food calorie scan, strength & MET cardio tracking, pedometer, and DeepSeek AI coach.';

  @override
  String get batteryDiagTitle => 'Battery & Performance Diagnostics';

  @override
  String get batteryDiagTileSub =>
      '7-day foreground/background time, timer activity, GPS, DB writes & widget syncs';

  @override
  String get batteryDiagResetBtn => 'Reset Stats';

  @override
  String get batteryDiagResetConfirm =>
      'Reset all rolling 7-day battery diagnostic counters?';

  @override
  String get batteryDiagResetToast => 'Battery diagnostic counters reset';

  @override
  String get batteryDiagSummaryTitle => 'Last 24h & Active Resource Monitor';

  @override
  String batteryDiagActiveTimers(int count) {
    return 'Active Periodic Timers right now: $count';
  }

  @override
  String get batteryDiagFgTime => 'Foreground';

  @override
  String get batteryDiagBgTime => 'Background';

  @override
  String get batteryDiagTimerTime => 'Timer Active';

  @override
  String get batteryDiagGpsCalls => 'GPS Calls';

  @override
  String get batteryDiagDbWrites => 'DB Writes';

  @override
  String get batteryDiagWidgetSyncs => 'Widget Syncs';

  @override
  String get batteryDiagHistoryTitle =>
      'Rolling 7-Day Telemetry (Stored in kv)';

  @override
  String batteryDiagDaySub(
    String fg,
    String bg,
    String timer,
    int gps,
    int db,
    int widget,
  ) {
    return 'FG $fg · BG $bg · Timer $timer\nGPS $gps · DB Writes $db · Widget $widget';
  }

  @override
  String get batteryDiagTipTitle => 'Power Saving Optimizations Active';

  @override
  String get batteryDiagTipSub =>
      '• AppWidget updatePeriodMillis=0 (event-driven push only)\n• Pedometer sensor unregistered in background & throttled to 30s\n• Bus & workout timers auto-pause when screen is invisible or backgrounded\n• GPS permission requested at most once, coordinates cached for 6h';

  @override
  String get widgetGuideTitle => 'Add Widget to Home Screen';

  @override
  String get widgetGuideTileSub =>
      'View today\'s classes, remaining calories & steps right on your home screen';

  @override
  String get widgetGuideHeader => 'Pin \"Life Assistant\" to Your Home Screen';

  @override
  String get widgetGuideDesc =>
      'See your daily schedule, remaining calorie budget, and live step count at a glance without opening the app.';

  @override
  String get widgetGuideStep1 =>
      '1. Tap \"Add to Home Screen\" below (supported on Android 8.0+ launchers).';

  @override
  String get widgetGuideStep2 =>
      '2. Or long-press an empty area on your phone\'s home screen → tap \"Widgets\".';

  @override
  String get widgetGuideStep3 =>
      '3. Find \"Life Assistant\" and drag the 4×2 card onto your home screen.';

  @override
  String get widgetGuidePinBtn => 'Add to Home Screen Now';

  @override
  String get widgetGuidePinSuccess =>
      'System widget prompt opened — confirm on your home screen!';

  @override
  String get widgetGuidePinFallback =>
      'Please long-press your home screen → Widgets → Life Assistant to add it.';

  @override
  String get busOriginLabel => 'Origin';

  @override
  String get busDestinationLabel => 'Destination';

  @override
  String get busSwapStopsTooltip => 'Swap Origin & Destination';

  @override
  String get busSameStopError =>
      'Origin and destination cannot be the same stop';

  @override
  String busAutoSwitchedDirToast(String origin, String dest) {
    return 'Auto-switched direction to match $origin → $dest';
  }

  @override
  String get busNoMoreTripsToday => 'No more trips today';

  @override
  String busNoMoreTripsSub(String time) {
    return 'All buses for this segment have departed today · First bus tomorrow at $time';
  }

  @override
  String busTimelineTitle(String slot) {
    return 'Live Route Timeline ($slot)';
  }

  @override
  String get busStopPassedTag => 'Passed';

  @override
  String get busStopCurrentTag => 'Current Stop';

  @override
  String busStopInMinutesTag(int mins) {
    return 'in $mins min';
  }

  @override
  String get busStopArrivingNowTag => 'Arriving';

  @override
  String get busStopOriginTag => 'Start';

  @override
  String get busStopDestTag => 'End';

  @override
  String busBusHereLabel(int pct) {
    return 'Bus en route ($pct%)';
  }

  @override
  String get busSelectSlotLabel => 'Trip Slot:';

  @override
  String get busRefreshSpinToast => 'Schedule & live position refreshed';

  @override
  String get aiPlanCardHeader => 'Workout Plan Generated';

  @override
  String aiPlanDayExerciseCount(int count) {
    return '$count exercises';
  }

  @override
  String get aiPlanViewDetailsBtn => 'View Details';

  @override
  String get aiPlanImportBtn => 'Import to Workout';

  @override
  String get aiPlanImportedDoneBtn => 'Imported ✓';

  @override
  String get aiPlanGeneratingPlaceholder => 'Generating workout plan…';

  @override
  String get aiPlanParseFailedHint =>
      'Structured plan block could not be parsed.';

  @override
  String get aiPlanShowRawReplyBtn => 'Show Raw Reply';

  @override
  String get aiPlanHideRawReplyBtn => 'Hide Raw Reply';

  @override
  String get weatherForecast15Title => '15-Day Weather Forecast';

  @override
  String get weatherForecast15Badge => '15-Day';

  @override
  String get weatherOpenSystemBtn => 'System Weather';

  @override
  String get weatherSwitchCityBtn => 'Switch City';

  @override
  String get weatherSystemNotFound =>
      'No built-in weather app found on this device';

  @override
  String get weatherForecastEmpty =>
      '15-day forecast unavailable — tap refresh';

  @override
  String get weatherTodayTag => 'Today';

  @override
  String get weatherTomorrowTag => 'Tomorrow';

  @override
  String busHomeNextAbsolute(String dir, String time) {
    return '$dir · Next $time';
  }

  @override
  String busNextTripWaiting(String time, int mins) {
    return 'Next $time · in $mins min';
  }

  @override
  String busNextTripAbsolute(String time) {
    return 'Next $time';
  }

  @override
  String busTomorrowTimeTag(String time) {
    return 'Tmr $time';
  }

  @override
  String get busWeekendShortTag => 'Weekend';

  @override
  String busReverseOrderError(String origin, String dest) {
    return 'This direction runs $dest → $origin, not $origin → $dest.';
  }

  @override
  String get busSwapBtnShort => 'Swap';
}
