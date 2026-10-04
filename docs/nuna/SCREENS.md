# Nuna screen inventory

Generated from the Design Canvas. "Existing view" is a best-effort pointer to a SwiftUI view in this repository that can be reused or revised; `NEW` (new) means there is no counterpart yet. Screen titles are the Indonesian UI strings used in the mockups.

Total: 180 screens and boards (including the feature map boards and documentation boards).

## Peta fitur PHMNOOP

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Peta fitur · Ringkasan** (`MapOverview`) | [MapOverview.dc.html](mockups/MapOverview.dc.html) | 1180×1230 |  | — |

## Peta fitur: rincian 1 dan 2

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Peta fitur · Bagian 1** (`MapA`) | [MapA.dc.html](mockups/MapA.dc.html) | 1230×1540 |  | — |
| **Peta fitur · Bagian 2** (`MapB`) | [MapB.dc.html](mockups/MapB.dc.html) | 1230×1290 |  | — |

## Peta fitur: rincian 3 dan 4

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Peta fitur · Bagian 3** (`MapC`) | [MapC.dc.html](mockups/MapC.dc.html) | 1230×1640 |  | — |
| **Peta fitur · Bagian 4** (`MapD`) | [MapD.dc.html](mockups/MapD.dc.html) | 1230×1140 |  | — |

## 1. Onboarding: mulai dan nilai

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Selamat datang** (`ObWelcome`) | [ObWelcome.dc.html](mockups/ObWelcome.dc.html) | 390×844 | `ObPrivacy`, `ObTerms` | — |
| **Privasi** (`ObPrivacy`) | [ObPrivacy.dc.html](mockups/ObPrivacy.dc.html) | 390×900 | `ObWelcome` | — |
| **Syarat dan penafian** (`ObTerms`) | [ObTerms.dc.html](mockups/ObTerms.dc.html) | 390×900 | `ObTermsSheet`, `ObValue1`, `ObWelcome` | — |
| **Penafian lengkap** (`ObTermsSheet`) | [ObTermsSheet.dc.html](mockups/ObTermsSheet.dc.html) | 390×900 | `ObTerms`, `ObWelcome` | — |
| **Nilai 1 · Energi** (`ObValue1`) | [ObValue1.dc.html](mockups/ObValue1.dc.html) | 390×900 | `ObDevice`, `ObTerms`, `ObValue2` | — |
| **Nilai 2 · Detak langsung** (`ObValue2`) | [ObValue2.dc.html](mockups/ObValue2.dc.html) | 390×900 | `ObDevice`, `ObValue1`, `ObValue3` | — |
| **Nilai 3 · Milikmu** (`ObValue3`) | [ObValue3.dc.html](mockups/ObValue3.dc.html) | 390×900 | `ObDevice`, `ObValue2` | — |
| **Pilih perangkat** (`ObDevice`) | [ObDevice.dc.html](mockups/ObDevice.dc.html) | 390×960 | `ObBluetooth`, `ObValue3` | — |

## 1. Onboarding: koneksi dan profil

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Izin Bluetooth** (`ObBluetooth`) | [ObBluetooth.dc.html](mockups/ObBluetooth.dc.html) | 390×900 | `ObDevice`, `ObWear` | — |
| **Pasang strap** (`ObWear`) | [ObWear.dc.html](mockups/ObWear.dc.html) | 390×900 | `ObBluetooth`, `Scan` | — |
| **Strap belum ketemu** (`ObScanHelp`) | [ObScanHelp.dc.html](mockups/ObScanHelp.dc.html) | 390×900 | `ObProfile`, `Scan` | — |
| **Profil** (`ObProfile`) | [ObProfile.dc.html](mockups/ObProfile.dc.html) | 390×960 | `ObHealth`, `ObProfilePicker`, `ObScanHelp` | — |
| **Pilih berat badan** (`ObProfilePicker`) | [ObProfilePicker.dc.html](mockups/ObProfilePicker.dc.html) | 390×960 | `ObHealth`, `ObProfile`, `ObScanHelp` | — |
| **Apple Health** (`ObHealth`) | [ObHealth.dc.html](mockups/ObHealth.dc.html) | 390×1000 | `ObImport`, `ObProfile` | — |

## 1. Onboarding: akhir

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Impor data** (`ObImport`) | [ObImport.dc.html](mockups/ObImport.dc.html) | 390×900 | `ObAnya`, `ObHealth` | — |
| **Siapkan Anya** (`ObAnya`) | [ObAnya.dc.html](mockups/ObAnya.dc.html) | 390×1000 | `ObImport`, `ObPrefs` | — |
| **Preferensi** (`ObPrefs`) | [ObPrefs.dc.html](mockups/ObPrefs.dc.html) | 390×960 | `ObAnya`, `ObDone` | — |
| **Selesai** (`ObDone`) | [ObDone.dc.html](mockups/ObDone.dc.html) | 390×960 | `Main`, `ObPrefs` | — |
| **Apa yang baru** (`ObWhatsNew`) | [ObWhatsNew.dc.html](mockups/ObWhatsNew.dc.html) | 390×960 | `Main`, `ObPrefs` | — |

## 2. Hari ini: layar utama dan skor

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Hari ini** (`Main`) | [Main.dc.html](mockups/Main.dc.html) | 390×1480 | `Anya`, `Devices`, `Health`, `Personalize`, `Sleep`, `TodayAllMetrics`… | TodayView, LiquidTodayView, TodayCustomizationSheet |
| **Detail Charge** (`TodayCharge`) | [TodayCharge.dc.html](mockups/TodayCharge.dc.html) | 390×1100 | `Anya`, `AnyaSheetToday`, `Health`, `Main`, `Personalize`, `Sleep`… | MetricExplorerView (recovery), ChargeBreakdownFormat |
| **Detail Effort** (`TodayEffort`) | [TodayEffort.dc.html](mockups/TodayEffort.dc.html) | 390×1060 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `WorkoutSummary` | MetricExplorerView (strain) |
| **Detak hari ini** (`TodayHeartRate`) | [TodayHeartRate.dc.html](mockups/TodayHeartRate.dc.html) | 390×980 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | FullDayChartView |

## 2. Hari ini: metrik harian

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Detail HRV** (`TodayHRV`) | [TodayHRV.dc.html](mockups/TodayHRV.dc.html) | 390×1040 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | HRVSnapshotView |
| **Detail detak istirahat** (`TodayRHR`) | [TodayRHR.dc.html](mockups/TodayRHR.dc.html) | 390×1040 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | MetricExplorerView |
| **Detail langkah** (`TodaySteps`) | [TodaySteps.dc.html](mockups/TodaySteps.dc.html) | 390×1060 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | MetricExplorerView |
| **Semua metrik** (`TodayAllMetrics`) | [TodayAllMetrics.dc.html](mockups/TodayAllMetrics.dc.html) | 390×1000 | `Anya`, `Health`, `HealthBody`, `HealthVital`, `Main`, `Personalize`… | MetricExplorerView |
| **Pilih metrik utama** (`TodayMetrics`) | [TodayMetrics.dc.html](mockups/TodayMetrics.dc.html) | 390×1700 | `Anya`, `Health`, `Main`, `Personalize`, `TodayCustomize`, `Trends` | NEW |

## 2. Hari ini: stres, jurnal, dan peringatan

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Pemantauan stres** (`TodayStress`) | [TodayStress.dc.html](mockups/TodayStress.dc.html) | 390×1640 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | StressView, StressTodayCard |
| **Jurnal hari ini** (`TodayJournal`) | [TodayJournal.dc.html](mockups/TodayJournal.dc.html) | 390×1160 | `Anya`, `Devices`, `Main`, `Sleep`, `TodayAllMetrics`, `TodayCharge`… | JournalLogCard |
| **Peringatan dini** (`TodayWarning`) | [TodayWarning.dc.html](mockups/TodayWarning.dc.html) | 390×860 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | HealthAlertBanner |
| **Notifikasi** (`TodayNotifs`) | [TodayNotifs.dc.html](mockups/TodayNotifs.dc.html) | 390×820 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | UpdatesInboxView, NotificationSettingsView |

## 2. Hari ini: pilih tanggal dan hari lampau

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Pilih tanggal** (`TodayDate`) | [TodayDate.dc.html](mockups/TodayDate.dc.html) | 390×1180 | `Anya`, `Health`, `Main`, `Personalize`, `TodayPast`, `Trends` | DayNavBar |
| **Hari lampau (hanya lihat)** (`TodayPast`) | [TodayPast.dc.html](mockups/TodayPast.dc.html) | 390×1440 | `Anya`, `Health`, `Main`, `Personalize`, `Sleep`, `TodayAddActivity`… | TodayView (day parameter) |

## 2. Hari ini: atur kartu

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Atur kartu (mode atur)** (`TodayEdit`) | [TodayEdit.dc.html](mockups/TodayEdit.dc.html) | 390×1860 | `Anya`, `Health`, `Main`, `Personalize`, `TodayCustomize`, `Trends` | TodayCustomizationSheet, EditableLayoutList |
| **Atur kartu Hari ini** (`TodayCustomize`) | [TodayCustomize.dc.html](mockups/TodayCustomize.dc.html) | 390×2100 | `Anya`, `Health`, `Main`, `Personalize`, `TodayMetrics`, `TodayQuick`… | TodayCustomizationSheet |

## 2. Hari ini: aksi cepat (tombol +)

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Aksi cepat (tombol +)** (`TodayQuick`) | [TodayQuick.dc.html](mockups/TodayQuick.dc.html) | 390×900 | `AnyaSheetToday`, `HealthBody`, `Main`, `SleepNap`, `TodayAddActivity`, `TodayBreathe`… | NEW (replaces the QuickAction FAB) |
| **Tambah aktivitas** (`TodayAddActivity`) | [TodayAddActivity.dc.html](mockups/TodayAddActivity.dc.html) | 390×1700 | `Anya`, `Health`, `Main`, `Personalize`, `TodayQuick`, `Trends`… | ManualWorkoutSheet |
| **Latihan napas** (`TodayBreathe`) | [TodayBreathe.dc.html](mockups/TodayBreathe.dc.html) | 390×1000 | `Anya`, `Health`, `Main`, `Personalize`, `TodayBreatheRhythm`, `TodayQuick`… | BreathingView |
| **Catat air** (`TodayWater`) | [TodayWater.dc.html](mockups/TodayWater.dc.html) | 390×1180 | `Anya`, `Health`, `Main`, `Personalize`, `TodayQuick`, `Trends` | HydrationView |
| **Ritme napas** (`TodayBreatheRhythm`) | [TodayBreatheRhythm.dc.html](mockups/TodayBreatheRhythm.dc.html) | 390×1380 | `Anya`, `Health`, `Main`, `Personalize`, `TodayBreathe`, `Trends` | BreathingView |

## 3. Kesehatan: tab Semua, Vital, Tubuh, Tidur

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Kesehatan** (`Health`) | [Health.dc.html](mockups/Health.dc.html) | 390×1980 | `Anya`, `AnyaSheetHealth`, `HealthBody`, `HealthOxygen`, `HealthPermissions`, `HealthSleep`… | HealthView |
| **Kesehatan · Vital** (`HealthVital`) | [HealthVital.dc.html](mockups/HealthVital.dc.html) | 390×2500 | `Anya`, `Health`, `HealthBody`, `HealthLive`, `HealthMind`, `HealthOxygen`… | VitalSignsSummary |
| **Kesehatan · Tubuh** (`HealthBody`) | [HealthBody.dc.html](mockups/HealthBody.dc.html) | 390×2090 | `Anya`, `Health`, `HealthCycle`, `HealthLab`, `HealthNutrition`, `HealthSleep`… | HealthView (Body tab) |
| **Kesehatan · Tidur** (`HealthSleep`) | [HealthSleep.dc.html](mockups/HealthSleep.dc.html) | 390×2060 | `Anya`, `Health`, `HealthBody`, `HealthVital`, `Main`, `Personalize`… | HealthView (Sleep tab) |

## 3. Kesehatan: detail vital

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Detak langsung** (`HealthLive`) | [HealthLive.dc.html](mockups/HealthLive.dc.html) | 390×1400 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `WorkoutStart` | LiveView, OverviewHRChart |
| **Oksigen dan napas** (`HealthOxygen`) | [HealthOxygen.dc.html](mockups/HealthOxygen.dc.html) | 390×1560 | `Anya`, `Health`, `Main`, `Personalize`, `TodayWarning`, `Trends` | VitalSignsSummary |
| **Suhu kulit** (`HealthSkin`) | [HealthSkin.dc.html](mockups/HealthSkin.dc.html) | 390×1300 | `Anya`, `Health`, `Main`, `Personalize`, `TodayWarning`, `Trends` | SkinTempCardsView |
| **Kebugaran (VO₂max)** (`HealthVO2`) | [HealthVO2.dc.html](mockups/HealthVO2.dc.html) | 390×2300 | `Anya`, `Health`, `HealthWaist`, `Main`, `Personalize`, `Trends` | FITNESS_AGE (engine exists), new UI |
| **Cek suasana hati** (`HealthMind`) | [HealthMind.dc.html](mockups/HealthMind.dc.html) | 390×1400 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | MindSection |

## 3. Kesehatan: detail tubuh dan data

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Berat badan** (`HealthWeight`) | [HealthWeight.dc.html](mockups/HealthWeight.dc.html) | 390×1620 | `Anya`, `AnyaSheetHealth`, `Health`, `Main`, `Personalize`, `Trends` | HealthView (Tubuh) |
| **Lingkar pinggang** (`HealthWaist`) | [HealthWaist.dc.html](mockups/HealthWaist.dc.html) | 390×1360 | `Anya`, `Health`, `HealthVO2`, `Main`, `Personalize`, `Trends` | HealthView (Tubuh) |
| **Nutrisi** (`HealthNutrition`) | [HealthNutrition.dc.html](mockups/HealthNutrition.dc.html) | 390×1960 | `Anya`, `AnyaSheetNutrition`, `Health`, `Main`, `Personalize`, `TodayWater`… | DataSourcesView (nutrition import), new UI |
| **Lab Book** (`HealthLab`) | [HealthLab.dc.html](mockups/HealthLab.dc.html) | 390×1900 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | LabBookView |
| **Siklus menstruasi** (`HealthCycle`) | [HealthCycle.dc.html](mockups/HealthCycle.dc.html) | 390×1620 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | AutomationsView (cycle awareness), new UI |
| **Izin Apple Health** (`HealthPermissions`) | [HealthPermissions.dc.html](mockups/HealthPermissions.dc.html) | 390×1600 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | AppleHealthView |

## 3. Kesehatan: Ritme (fitur eksperimental)

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Ritme · persetujuan** (`HealthRhythmConsent`) | [HealthRhythmConsent.dc.html](mockups/HealthRhythmConsent.dc.html) | 390×1500 | `Anya`, `Health`, `HealthRhythm`, `HealthVital`, `Main`, `Personalize`… | RhythmView (consent gate) |
| **Ritme · hasil** (`HealthRhythm`) | [HealthRhythm.dc.html](mockups/HealthRhythm.dc.html) | 390×2050 | `Anya`, `Health`, `HealthRhythmConsent`, `Main`, `Personalize`, `Trends` | RhythmView |
| **Ritme · belum ada bacaan** (`HealthRhythmEmpty`) | [HealthRhythmEmpty.dc.html](mockups/HealthRhythmEmpty.dc.html) | 390×1000 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | RhythmView |
| **Ritme · perangkat tak didukung** (`HealthRhythmUnsupported`) | [HealthRhythmUnsupported.dc.html](mockups/HealthRhythmUnsupported.dc.html) | 390×1000 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | RhythmView |

## 4. Tren: ringkasan dan perbandingan

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Tren** (`Trends`) | [Trends.dc.html](mockups/Trends.dc.html) | 390×3560 | `Anya`, `AnyaSheetTrends`, `Health`, `Main`, `Personalize`, `TodayHRV`… | TrendsView |

## 4. Tren: detail Charge, Effort, dan Rest

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Tren Charge** (`TrendsCharge`) | [TrendsCharge.dc.html](mockups/TrendsCharge.dc.html) | 390×2420 | `Anya`, `Health`, `Main`, `Personalize`, `TodayCharge`, `TodayHRV`… | TrendsView (Charge hero) |
| **Tren Effort** (`TrendsEffort`) | [TrendsEffort.dc.html](mockups/TrendsEffort.dc.html) | 390×2380 | `Anya`, `Health`, `Main`, `Personalize`, `TodayEffort`, `Trends`… | TrendsView |
| **Tren Rest** (`TrendsRest`) | [TrendsRest.dc.html](mockups/TrendsRest.dc.html) | 390×2400 | `Anya`, `Health`, `Main`, `Personalize`, `Sleep`, `Trends`… | TrendsView |

## 4. Tren: detail perbandingan, insight, dan jelajah

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Charge dan Effort** (`TrendsChargeEffort`) | [TrendsChargeEffort.dc.html](mockups/TrendsChargeEffort.dc.html) | 390×2140 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | CompareView |
| **Charge dan Rest** (`TrendsChargeRest`) | [TrendsChargeRest.dc.html](mockups/TrendsChargeRest.dc.html) | 390×2060 | `Anya`, `Health`, `Main`, `Personalize`, `SleepPerformance`, `Trends` | CompareView |
| **Peta panas Charge** (`TrendsHeatmap`) | [TrendsHeatmap.dc.html](mockups/TrendsHeatmap.dc.html) | 390×1740 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | YearHeatStrip |
| **Insights** (`TrendsInsights`) | [TrendsInsights.dc.html](mockups/TrendsInsights.dc.html) | 390×2200 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | InsightsView, InsightsHubView |
| **Bandingkan** (`TrendsCompare`) | [TrendsCompare.dc.html](mockups/TrendsCompare.dc.html) | 390×1740 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | CompareView |
| **Explore** (`TrendsExplore`) | [TrendsExplore.dc.html](mockups/TrendsExplore.dc.html) | 390×2100 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `TrendsCompare` | MetricExplorerView |

## 5. Tidur: ringkasan dan detail

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Tidur · Ringkasan** (`Sleep`) | [Sleep.dc.html](mockups/Sleep.dc.html) | 390×2400 | `Anya`, `AnyaSheetSleep`, `Health`, `HealthSleep`, `Main`, `Personalize`… | SleepView |
| **Fase tidur** (`SleepStages`) | [SleepStages.dc.html](mockups/SleepStages.dc.html) | 390×1740 | `Anya`, `AnyaSheetSleep`, `Health`, `Main`, `Personalize`, `Sleep`… | StagesCard, StagesVsTypicalCard, Hypnogram |
| **Vital semalam** (`SleepVitals`) | [SleepVitals.dc.html](mockups/SleepVitals.dc.html) | 390×1460 | `Anya`, `Health`, `Main`, `Personalize`, `Sleep`, `Trends` | NightDetailCard |
| **Kinerja tidur** (`SleepPerformance`) | [SleepPerformance.dc.html](mockups/SleepPerformance.dc.html) | 390×1520 | `Anya`, `Health`, `Main`, `Personalize`, `Sleep`, `Trends` | HoursVsNeededCard, SleepDebtLedgerCard |
| **Tidur siang** (`SleepNap`) | [SleepNap.dc.html](mockups/SleepNap.dc.html) | 390×1700 | `Anya`, `Health`, `Main`, `Personalize`, `Sleep`, `Trends` | NEW |
| **Jam tubuh** (`SleepBodyClock`) | [SleepBodyClock.dc.html](mockups/SleepBodyClock.dc.html) | 390×1900 | `Anya`, `AnyaSheetSleep`, `Health`, `Main`, `Personalize`, `Sleep`… | BodyClockCard, BodyClockDialCard, BodyClockDialSection (CircadianEngine) |
| **Rencana jam tubuh** (`SleepBodyClockPlan`) | [SleepBodyClockPlan.dc.html](mockups/SleepBodyClockPlan.dc.html) | 390×1760 | `Anya`, `AnyaSheetSleep`, `Health`, `Main`, `Personalize`, `SleepBodyClock`… | NEW (CircadianEngine.planShift) |

## 6. Anya: percakapan

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Anya** (`Anya`) | [Anya.dc.html](mockups/Anya.dc.html) | 390×1700 | `AnyaAttach`, `AnyaHistory`, `AnyaMemory`, `AnyaPlan`, `AnyaSettings`, `AnyaVoice`… | CoachView |
| **Anya · mulai** (`AnyaStart`) | [AnyaStart.dc.html](mockups/AnyaStart.dc.html) | 390×1560 | `Anya`, `AnyaAttach`, `AnyaHistory`, `AnyaMemory`, `AnyaPlan`, `AnyaSettings`… | CoachView (empty state) |
| **Tambah lampiran** (`AnyaAttach`) | [AnyaAttach.dc.html](mockups/AnyaAttach.dc.html) | 390×900 | `Anya` | CoachView (attachments) |
| **Masukan suara** (`AnyaVoice`) | [AnyaVoice.dc.html](mockups/AnyaVoice.dc.html) | 390×900 | `Anya` | CoachVoiceInput |
| **Rencana hari ini** (`AnyaPlan`) | [AnyaPlan.dc.html](mockups/AnyaPlan.dc.html) | 390×1860 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `WorkoutStart` | NEW |
| **Ringkasan pagi** (`AnyaBrief`) | [AnyaBrief.dc.html](mockups/AnyaBrief.dc.html) | 390×1560 | `Anya`, `AnyaPlan`, `AnyaSettings`, `Health`, `Main`, `Personalize`… | CoachSettingsView (morning brief) |

## 6. Anya: penyedia dan pengaturan

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Hubungkan Anya** (`AnyaConnect`) | [AnyaConnect.dc.html](mockups/AnyaConnect.dc.html) | 390×1560 | `Anya`, `AnyaChatGPT`, `AnyaCustom`, `AnyaKey`, `Health`, `Main`… | CoachView (connect), CoachSettingsView |
| **Kunci API** (`AnyaKey`) | [AnyaKey.dc.html](mockups/AnyaKey.dc.html) | 390×1360 | `Anya`, `AnyaConnect` | CoachView (API key) |
| **Masuk ChatGPT** (`AnyaChatGPT`) | [AnyaChatGPT.dc.html](mockups/AnyaChatGPT.dc.html) | 390×1180 | `AnyaConnect` | ChatGPTAuthCard |
| **Server sendiri** (`AnyaCustom`) | [AnyaCustom.dc.html](mockups/AnyaCustom.dc.html) | 390×1400 | `Anya`, `AnyaConnect` | CoachView (custom) |
| **Pengaturan Anya** (`AnyaSettings`) | [AnyaSettings.dc.html](mockups/AnyaSettings.dc.html) | 390×2160 | `Anya`, `AnyaBrief`, `AnyaConnect`, `AnyaHistory`, `AnyaInstructions`, `AnyaKey`… | CoachSettingsView |
| **Instruksi Anya** (`AnyaInstructions`) | [AnyaInstructions.dc.html](mockups/AnyaInstructions.dc.html) | 390×1260 | `AnyaSettings` | CoachSettingsView |

## 6. Anya: memori, riwayat, dan pelatih suara

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Memory** (`AnyaMemory`) | [AnyaMemory.dc.html](mockups/AnyaMemory.dc.html) | 390×1560 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | CoachMemoryView |
| **Riwayat** (`AnyaHistory`) | [AnyaHistory.dc.html](mockups/AnyaHistory.dc.html) | 390×1420 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | CoachHistoryView |
| **Pelatih suara** (`AnyaVoiceCoach`) | [AnyaVoiceCoach.dc.html](mockups/AnyaVoiceCoach.dc.html) | 390×1760 | `AnyaSettings` | AutomationsView/LiveSessionView |

## 6. Anya di setiap modul

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Peta Anya di setiap modul** (`AnyaMap`) | [AnyaMap.dc.html](mockups/AnyaMap.dc.html) | 1330×1340 | `Anya`, `AnyaSettings`, `AnyaSheetDevice`, `AnyaSheetHealth`, `AnyaSheetNutrition`, `AnyaSheetSleep`… | DOC BOARD |
| **Anya di Tidur** (`AnyaSheetSleep`) | [AnyaSheetSleep.dc.html](mockups/AnyaSheetSleep.dc.html) | 390×1100 | `Anya`, `AnyaVoice`, `Main`, `Sleep` | CoachLauncherSheet |
| **Anya di Tren** (`AnyaSheetTrends`) | [AnyaSheetTrends.dc.html](mockups/AnyaSheetTrends.dc.html) | 390×1100 | `Anya`, `AnyaVoice`, `Main`, `Trends` | CoachLauncherSheet |
| **Anya di Latihan** (`AnyaSheetWorkout`) | [AnyaSheetWorkout.dc.html](mockups/AnyaSheetWorkout.dc.html) | 390×1100 | `Anya`, `AnyaVoice`, `Main`, `Workouts` | CoachLauncherSheet |

## 6. Anya di setiap modul: pola kemunculan dan sheet lanjutan

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Pola Anya di setiap modul** (`AnyaPattern`) | [AnyaPattern.dc.html](mockups/AnyaPattern.dc.html) | 1410×1380 |  | DOC BOARD |
| **Anya di Hari ini** (`AnyaSheetToday`) | [AnyaSheetToday.dc.html](mockups/AnyaSheetToday.dc.html) | 390×1100 | `Anya`, `AnyaVoice`, `Main` | CoachLauncherSheet |
| **Anya di Kesehatan** (`AnyaSheetHealth`) | [AnyaSheetHealth.dc.html](mockups/AnyaSheetHealth.dc.html) | 390×1100 | `Anya`, `AnyaVoice`, `Health` | CoachLauncherSheet |
| **Anya di Nutrisi** (`AnyaSheetNutrition`) | [AnyaSheetNutrition.dc.html](mockups/AnyaSheetNutrition.dc.html) | 390×1100 | `Anya`, `AnyaVoice`, `HealthNutrition` | CoachLauncherSheet |
| **Anya di Perangkat** (`AnyaSheetDevice`) | [AnyaSheetDevice.dc.html](mockups/AnyaSheetDevice.dc.html) | 390×1100 | `Anya`, `AnyaVoice`, `Devices` | CoachLauncherSheet |

## 7.1 Latihan: hub, mulai latihan, ringkasan, dan Lift Log

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Workout** (`Workouts`) | [Workouts.dc.html](mockups/Workouts.dc.html) | 390×2580 | `Anya`, `AnyaSheetWorkout`, `Health`, `LiveCycle`, `LiveWalk`, `Main`… | WorkoutsView |
| **Mulai latihan** (`WorkoutStart`) | [WorkoutStart.dc.html](mockups/WorkoutStart.dc.html) | 390×980 | `Live`, `Workouts` | WorkoutSelectionScreen, WorkoutStartControl |
| **Ringkasan latihan** (`WorkoutSummary`) | [WorkoutSummary.dc.html](mockups/WorkoutSummary.dc.html) | 390×1900 | `Strava`, `Workouts` | WorkoutDetailView |
| **Lift Log** (`WorkoutLift`) | [WorkoutLift.dc.html](mockups/WorkoutLift.dc.html) | 390×1400 | `WorkoutSummaryGym`, `Workouts` | LiftSessionView |

## 7.2 Gym: program (template), impor, dan ringkasan sesi

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Gym dan program** (`WorkoutGym`) | [WorkoutGym.dc.html](mockups/WorkoutGym.dc.html) | 390×2220 | `Anya`, `Health`, `Main`, `Personalize`, `TrainingLoadMuscle`, `Trends`… | LiftLogView |
| **Ubah program** (`WorkoutProgram`) | [WorkoutProgram.dc.html](mockups/WorkoutProgram.dc.html) | 390×2100 | `WorkoutGym`, `WorkoutProgramItem` | LiftProgramEditorSheet |
| **Latihan program** (`WorkoutProgramItem`) | [WorkoutProgramItem.dc.html](mockups/WorkoutProgramItem.dc.html) | 390×1880 | `WorkoutProgram` | LiftProgramItemSheet |
| **Impor program** (`WorkoutProgramImport`) | [WorkoutProgramImport.dc.html](mockups/WorkoutProgramImport.dc.html) | 390×1700 | `WorkoutGym` | LiftProgramImportSheet |
| **Ringkasan sesi gym** (`WorkoutSummaryGym`) | [WorkoutSummaryGym.dc.html](mockups/WorkoutSummaryGym.dc.html) | 390×2380 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `WorkoutGym`… | LiftSessionDetailSheet |
| **Simpan sebagai program** (`WorkoutSaveProgram`) | [WorkoutSaveProgram.dc.html](mockups/WorkoutSaveProgram.dc.html) | 390×1240 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `WorkoutGym`… | NEW |

## 7.3 Beban latihan: kardio dan otot

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Beban latihan** (`TrainingLoad`) | [TrainingLoad.dc.html](mockups/TrainingLoad.dc.html) | 390×2200 | `Anya`, `Health`, `Main`, `Personalize`, `TrainingLoadCardio`, `TrainingLoadMuscle`… | TrainingLoadCard |
| **Beban kardio** (`TrainingLoadCardio`) | [TrainingLoadCardio.dc.html](mockups/TrainingLoadCardio.dc.html) | 390×2420 | `Anya`, `AnyaSheetWorkout`, `Health`, `Main`, `Personalize`, `TrainingLoad`… | TrainingLoadCard, TrainingLoadChart |
| **Beban otot** (`TrainingLoadMuscle`) | [TrainingLoadMuscle.dc.html](mockups/TrainingLoadMuscle.dc.html) | 390×2300 | `Anya`, `Health`, `Main`, `Personalize`, `TrainingLoad`, `TrainingLoadCardio`… | LiftLogView (muscle volume), new UI |

## 7.4 Kalender latihan dan semua sesi

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Kalender latihan** (`WorkoutCalendar`) | [WorkoutCalendar.dc.html](mockups/WorkoutCalendar.dc.html) | 390×2060 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `WorkoutSummary`… | NEW |
| **Semua sesi** (`WorkoutHistory`) | [WorkoutHistory.dc.html](mockups/WorkoutHistory.dc.html) | 390×2300 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `WorkoutSummary`… | WorkoutsView (all sessions) |

## 7.5 Deteksi latihan otomatis: aktif dan mati

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Deteksi otomatis · aktif** (`WorkoutAutoDetect`) | [WorkoutAutoDetect.dc.html](mockups/WorkoutAutoDetect.dc.html) | 390×1760 | `Anya`, `Health`, `Main`, `Personalize`, `TestCentre`, `Trends`… | AutoWorkoutCard, SettingsView |
| **Deteksi otomatis · mati** (`WorkoutAutoDetectOff`) | [WorkoutAutoDetectOff.dc.html](mockups/WorkoutAutoDetectOff.dc.html) | 390×1500 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `Workouts` | AutoWorkoutCard |

## 7.6 Sesi langsung: olahraga GPS (lari, jalan, sepeda)

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Sesi langsung · Lari** (`Live`) | [Live.dc.html](mockups/Live.dc.html) | 390×940 | `Main`, `WorkoutSummary` | LiveWorkoutView |
| **Sesi langsung · Jalan** (`LiveWalk`) | [LiveWalk.dc.html](mockups/LiveWalk.dc.html) | 390×940 | `Main`, `WorkoutSummary` | LiveWorkoutView |
| **Sesi langsung · Sepeda** (`LiveCycle`) | [LiveCycle.dc.html](mockups/LiveCycle.dc.html) | 390×940 | `Main`, `WorkoutSummary` | LiveWorkoutView |
| **Layar kunci · GPS** (`LiveActivities`) | [LiveActivities.dc.html](mockups/LiveActivities.dc.html) | 1410×1180 |  | StrandiOSWidgets/NOOPLiveActivity |

## 7.7 Sesi langsung: olahraga tanpa GPS (HIIT, yoga)

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Mulai HIIT** (`WorkoutStartHiit`) | [WorkoutStartHiit.dc.html](mockups/WorkoutStartHiit.dc.html) | 390×1160 | `LiveHIIT`, `Workouts` | IntervalTimerView |
| **Sesi langsung · HIIT** (`LiveHIIT`) | [LiveHIIT.dc.html](mockups/LiveHIIT.dc.html) | 390×980 | `WorkoutSummary`, `Workouts` | IntervalTimerView, LiveWorkoutView |
| **Sesi langsung · Yoga** (`LiveIndoor`) | [LiveIndoor.dc.html](mockups/LiveIndoor.dc.html) | 390×940 | `WorkoutSummary`, `Workouts` | LiveWorkoutView |
| **Layar kunci · tanpa GPS** (`LiveActivitiesNoGps`) | [LiveActivitiesNoGps.dc.html](mockups/LiveActivitiesNoGps.dc.html) | 1410×1180 |  | StrandiOSWidgets/NOOPLiveActivity |

## 7.8 Dynamic Island saat workout

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Dynamic Island saat workout** (`LiveIsland`) | [LiveIsland.dc.html](mockups/LiveIsland.dc.html) | 1410×3900 |  | StrandiOSWidgets/NOOPLiveActivity |

## 7.9 Zona detak kuning dan merah

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Zona kuning dan merah** (`LiveZone`) | [LiveZone.dc.html](mockups/LiveZone.dc.html) | 1410×2480 |  | LiveSessionView, NOOPLiveActivity |

## 8.1 Perangkat: strap, baterai, dan sinkron

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Perangkat** (`Devices`) | [Devices.dc.html](mockups/Devices.dc.html) | 390×2240 | `Anya`, `AnyaSheetDevice`, `DeviceDetail`, `DeviceHelp`, `DeviceLog`, `DeviceModel`… | DevicesView |
| **Detail strap** (`DeviceDetail`) | [DeviceDetail.dc.html](mockups/DeviceDetail.dc.html) | 390×2000 | `Anya`, `DeviceBattery`, `DeviceLog`, `DeviceRestart`, `DeviceSync`, `Devices`… | DevicesView |
| **Baterai strap** (`DeviceBattery`) | [DeviceBattery.dc.html](mockups/DeviceBattery.dc.html) | 390×1560 | `Anya`, `DeviceDetail`, `Health`, `Main`, `Personalize`, `Trends` | DevicesView, PowerSavingView |
| **Sinkron riwayat** (`DeviceSync`) | [DeviceSync.dc.html](mockups/DeviceSync.dc.html) | 390×2000 | `Anya`, `DeviceSyncIsland`, `Devices`, `Health`, `Main`, `Personalize`… | BackupSyncView?, DevicesView |

## 8.2 Tambah WHOOP: model, cari, sambung

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Tambah WHOOP** (`DeviceModel`) | [DeviceModel.dc.html](mockups/DeviceModel.dc.html) | 390×1260 | `DeviceModels`, `Devices`, `Scan` | AddDeviceWizard |
| **Cari strap** (`Scan`) | [Scan.dc.html](mockups/Scan.dc.html) | 390×1250 | `DeviceHelp`, `DeviceModel`, `Pairing` | AddDeviceWizard |
| **Menyambungkan** (`Pairing`) | [Pairing.dc.html](mockups/Pairing.dc.html) | 390×1200 | `DeviceRepair`, `Scan` | AddDeviceWizard |
| **Terhubung** (`Connected`) | [Connected.dc.html](mockups/Connected.dc.html) | 390×1250 | `Devices`, `Main` | AddDeviceWizard |

## 8.3 Bantuan koneksi, model, dan log

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Bantuan koneksi** (`DeviceHelp`) | [DeviceHelp.dc.html](mockups/DeviceHelp.dc.html) | 390×1900 | `Anya`, `DeviceLog`, `DeviceRepair`, `DeviceRestart`, `Devices`, `Health`… | DevicesView |
| **Pasang ulang** (`DeviceRepair`) | [DeviceRepair.dc.html](mockups/DeviceRepair.dc.html) | 390×1500 | `DeviceHelp`, `DeviceModel`, `Devices` | DevicesView |
| **Model dan dukungan** (`DeviceModels`) | [DeviceModels.dc.html](mockups/DeviceModels.dc.html) | 390×1760 | `Anya`, `Devices`, `Experiments`, `Health`, `Main`, `Personalize`… | NoopLimitationsView |
| **Log strap** (`DeviceLog`) | [DeviceLog.dc.html](mockups/DeviceLog.dc.html) | 390×1480 | `Anya`, `Devices`, `Health`, `Main`, `Personalize`, `Trends` | RawDataCollectorView, LiveView log |
| **Mulai ulang strap** (`DeviceRestart`) | [DeviceRestart.dc.html](mockups/DeviceRestart.dc.html) | 390×900 | `DeviceDetail`, `Devices` | DevicesView |

## 8.4 Sinkron di Dynamic Island

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Sinkron di Dynamic Island** (`DeviceSyncIsland`) | [DeviceSyncIsland.dc.html](mockups/DeviceSyncIsland.dc.html) | 1410×1160 |  | StrandiOSWidgets/SyncLiveActivity |

## 11.1 Widget layar utama: skor, detak, stres, Anya, langkah

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Widget layar utama** (`Widgets`) | [Widgets.dc.html](mockups/Widgets.dc.html) | 1410×1760 |  | StrandiOSWidgets (NOOPWidget, PHMNRings, HeartRate, Stress, CoachBrief) |

## 11.2 Widget Vital sign (baru)

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Widget Vital sign** (`WidgetVital`) | [WidgetVital.dc.html](mockups/WidgetVital.dc.html) | 1410×1180 |  | NEW (VitalWidget) |

## 11.3 Widget layar kunci

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Widget layar kunci** (`WidgetsLock`) | [WidgetsLock.dc.html](mockups/WidgetsLock.dc.html) | 1410×1080 |  | StrandiOSWidgets accessory families |

## 12.1 Saya: hub dan persona

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Saya** (`Personalize`) | [Personalize.dc.html](mockups/Personalize.dc.html) | 390×1960 | `About`, `Advanced`, `Anya`, `AnyaSettings`, `Appearance`, `Automations`… | SettingsView (new hub) |
| **Persona** (`Persona`) | [Persona.dc.html](mockups/Persona.dc.html) | 390×2160 | `Advanced`, `Anya`, `Health`, `Main`, `PersonaGoals`, `PersonaZones`… | SettingsView (Profile) |
| **Zona detak** (`PersonaZones`) | [PersonaZones.dc.html](mockups/PersonaZones.dc.html) | 390×1560 | `Anya`, `Health`, `Main`, `Persona`, `Personalize`, `Trends` | SettingsView (custom zones) |
| **Target** (`PersonaGoals`) | [PersonaGoals.dc.html](mockups/PersonaGoals.dc.html) | 390×1500 | `Anya`, `Health`, `Main`, `Persona`, `Personalize`, `Trends` | NEW |

## 12.2 Tampilan: Experience, bahasa, dan satuan

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Tampilan** (`Appearance`) | [Appearance.dc.html](mockups/Appearance.dc.html) | 390×2480 | `Anya`, `Experience`, `Health`, `Language`, `Main`, `Personalize`… | SettingsView (Appearance), Typography preset |
| **Experience** (`Experience`) | [Experience.dc.html](mockups/Experience.dc.html) | 390×1760 | `Anya`, `Appearance`, `ExperienceConfirm`, `Health`, `Main`, `Personalize`… | NEW (ExperienceMode) |
| **Ganti Experience** (`ExperienceConfirm`) | [ExperienceConfirm.dc.html](mockups/ExperienceConfirm.dc.html) | 390×1000 | `Experience` | NEW |
| **Bahasa** (`Language`) | [Language.dc.html](mockups/Language.dc.html) | 390×1700 | `Anya`, `Appearance`, `Health`, `Main`, `Personalize`, `Trends`… | NEW (IOS_INDONESIAN_LOCALIZATION) |
| **Satuan** (`Units`) | [Units.dc.html](mockups/Units.dc.html) | 390×1440 | `Anya`, `Appearance`, `Health`, `Main`, `Personalize`, `Trends` | SettingsView (Units) |

## 12.3 Notifikasi, fitur opsional, dan widget

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Notifikasi** (`Notifications`) | [Notifications.dc.html](mockups/Notifications.dc.html) | 390×1900 | `Anya`, `AnyaBrief`, `DeviceBattery`, `Health`, `Main`, `Personalize`… | NotificationSettingsView |
| **Fitur opsional** (`Features`) | [Features.dc.html](mockups/Features.dc.html) | 390×1380 | `Anya`, `Health`, `HealthCycle`, `Main`, `Personalize`, `TodayEdit`… | SettingsView (Features) |
| **Pengaturan widget** (`WidgetSettings`) | [WidgetSettings.dc.html](mockups/WidgetSettings.dc.html) | 390×2200 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `WidgetVitalConfig` | NEW |
| **Atur widget Vital** (`WidgetVitalConfig`) | [WidgetVitalConfig.dc.html](mockups/WidgetVitalConfig.dc.html) | 390×1560 | `Anya`, `Health`, `Main`, `Personalize`, `Trends`, `WidgetSettings` | NEW |

## 12.4 Otomasi strap

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Otomasi strap** (`Automations`) | [Automations.dc.html](mockups/Automations.dc.html) | 390×2140 | `Anya`, `AutoAlerts`, `AutoCoaching`, `AutoDoubleTap`, `AutoPresence`, `AutoSedentary`… | AutomationsView |
| **Ketuk dua kali** (`AutoDoubleTap`) | [AutoDoubleTap.dc.html](mockups/AutoDoubleTap.dc.html) | 390×1880 | `Anya`, `Automations`, `Health`, `Main`, `Personalize`, `Trends` | AutomationsView |
| **Pakai dan lepas strap** (`AutoPresence`) | [AutoPresence.dc.html](mockups/AutoPresence.dc.html) | 390×1700 | `Anya`, `Automations`, `Health`, `Main`, `Personalize`, `Trends` | AutomationsView |
| **Getar saat beraktivitas** (`AutoCoaching`) | [AutoCoaching.dc.html](mockups/AutoCoaching.dc.html) | 390×2200 | `Anya`, `Automations`, `DeviceLog`, `Health`, `Main`, `PersonaZones`… | AutomationsView |
| **Duduk terlalu lama** (`AutoSedentary`) | [AutoSedentary.dc.html](mockups/AutoSedentary.dc.html) | 390×1600 | `Anya`, `Automations`, `Health`, `Main`, `Personalize`, `Trends` | AutomationsView |
| **Peringatan dan laporan** (`AutoAlerts`) | [AutoAlerts.dc.html](mockups/AutoAlerts.dc.html) | 390×1900 | `Anya`, `Automations`, `Health`, `Main`, `Notifications`, `Personalize`… | AutomationsView |
| **Siri dan Pintasan** (`AutoShortcuts`) | [AutoShortcuts.dc.html](mockups/AutoShortcuts.dc.html) | 390×1700 | `Anya`, `AutoDoubleTap`, `AutoPresence`, `Automations`, `DeviceSync`, `Health`… | SiriShortcutsSettingsView, ShortcutExportSettingsView |

## 12.5 Data, cadangan, dan Strava

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Data dan integrasi** (`DataHub`) | [DataHub.dc.html](mockups/DataHub.dc.html) | 390×2110 | `Anya`, `Backup`, `Health`, `HealthNutrition`, `HealthPermissions`, `Main`… | DataSourcesView |
| **Cadangan** (`Backup`) | [Backup.dc.html](mockups/Backup.dc.html) | 390×1860 | `Anya`, `DataHub`, `Health`, `Main`, `Personalize`, `Trends` | BackupSyncView |
| **Strava · mati** (`Strava`) | [Strava.dc.html](mockups/Strava.dc.html) | 390×1280 | `Anya`, `DataHub`, `Health`, `Main`, `Personalize`, `StravaSetup`… | StravaSettingsView |
| **Strava · penyiapan** (`StravaSetup`) | [StravaSetup.dc.html](mockups/StravaSetup.dc.html) | 390×1900 | `Anya`, `DataHub`, `Health`, `Main`, `Personalize`, `StravaConnected`… | StravaSettingsView |
| **Strava · tersambung** (`StravaConnected`) | [StravaConnected.dc.html](mockups/StravaConnected.dc.html) | 390×1900 | `Anya`, `DataHub`, `Health`, `Main`, `Personalize`, `StravaSetup`… | StravaSettingsView |

## 12.6 Privasi, lanjutan, dan tentang

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Privasi** (`Privacy`) | [Privacy.dc.html](mockups/Privacy.dc.html) | 390×1900 | `Anya`, `Health`, `Main`, `Personalize`, `Trends` | NEW |
| **Lanjutan** (`Advanced`) | [Advanced.dc.html](mockups/Advanced.dc.html) | 390×1700 | `Anya`, `DeviceLog`, `Experiments`, `Health`, `Main`, `Personalize`… | SettingsView (Advanced) |
| **Tentang** (`About`) | [About.dc.html](mockups/About.dc.html) | 390×1900 | `Anya`, `DeviceHelp`, `DeviceLog`, `DeviceModels`, `Health`, `Main`… | AboutView, HowNoopWorksView, WhatsNewView |

## 12.7 Eksperimen dan Test Centre

| Screen | Mockup | Size | Links to | Existing view |
|---|---|---|---|---|
| **Eksperimen** (`Experiments`) | [Experiments.dc.html](mockups/Experiments.dc.html) | 390×1960 | `Anya`, `Health`, `HealthRhythmConsent`, `Main`, `Personalize`, `Strava`… | SettingsView (experimental) |
| **Test Centre** (`TestCentre`) | [TestCentre.dc.html](mockups/TestCentre.dc.html) | 390×1700 | `Anya`, `Experiments`, `Health`, `Main`, `Personalize`, `Trends` | TestCentreView |
