#if os(iOS)
import SwiftUI
import StrandDesign

/// The explanation card under a trend page: what the reading is and how to read it. Generated from one table so the catalog keys match.
enum NunaTrendInfoKind: String {
    case calories, stressNonActivity, stressSleep, stressTotal, weight, leanBodyMass, debt, efficiency, restorative, consistency, hoursNeeded, timeInBed, restPerformance, respiratory, rhr, hrv, charge
}

struct NunaTrendInfo: View {
    let kind: NunaTrendInfoKind

    private enum Item { case paragraph(String), bullet(String) }

    private var entry: (title: String, items: [Item]) {
        switch kind {
        case .calories:
            return ("What are Calories?", [
                .paragraph("Calories measure the energy you burn in a day. PHMN works it out from an estimate of your Basal Metabolic Rate (BMR), the energy your body uses at rest, and from your heart rate through the day, which shows when you burned more."),
                .paragraph("Your BMR is estimated from the height, weight, sex and age in your profile. In general, the more active you are, the more calories you burn."),
                .paragraph("Eat more calories than you burn and you gain weight (muscle or fat). Eat fewer and you lose weight. Match the two and your weight holds steady."),
            ])
        case .stressNonActivity:
            return ("What is Non-Activity Stress?", [
                .paragraph("Stress is your body's natural response to a physical or mental demand. It shows how alert or switched on your body is at a given moment. Outside of chronic stress it is not good or bad in itself: what matters is having the right amount for what you are doing."),
                .paragraph("PHMN reads your heart rate and heart rate variability (HRV) in the moment and compares them with your own baseline from recent nights and your typical resting heart rate."),
                .paragraph("Non-Activity Stress is the stress your body builds up outside workouts and sleep. Because it leaves those out, it can have an emotional or interpersonal trigger, though it can also show up when you feel calm. A higher score can come from illness, altitude, injury, travel, digestive trouble or pregnancy. A lower score suggests your body is being taxed very little."),
            ])
        case .stressSleep:
            return ("What is Sleep Stress?", [
                .paragraph("Stress is your body's natural response to a physical or mental demand. It shows how alert or switched on your body is at a given moment. Outside of chronic stress it is not good or bad in itself: what matters is having the right amount for what you are doing."),
                .paragraph("PHMN reads your heart rate and heart rate variability (HRV) in the moment and compares them with your own baseline from recent nights and your typical resting heart rate."),
                .paragraph("Sleep Stress is the stress your body shows while you sleep. Vitals are usually steadier at rest, so stress during sleep says a lot about how well you slept. A higher score can point to lighter, more disrupted sleep, and a lower one to better sleep. Here a lower score is actually better."),
            ])
        case .stressTotal:
            return ("What is Total Day Stress?", [
                .paragraph("Stress is your body's natural response to a physical or mental demand. It shows how alert or switched on your body is at a given moment. Outside of chronic stress it is not good or bad in itself: what matters is having the right amount for what you are doing."),
                .paragraph("PHMN reads your heart rate and heart rate variability (HRV) in the moment and compares them with your own baseline from recent nights and your typical resting heart rate."),
                .paragraph("Total Day Stress covers your whole day, including workouts and sleep. A higher score can mean you felt excited, highly activated or overwhelmed, and a lower one that you felt calm, relaxed or sleepy."),
            ])
        case .weight:
            return ("Weight: an essential health marker", [
                .paragraph("Your weight shapes your overall health, and knowing it helps you make informed choices for a healthy body at any age."),
                .paragraph("To track changes accurately, weigh yourself at the same time of day and under the same conditions."),
                .paragraph("It is normal for weight to move around. It shifts with food, exercise, hydration, stress and metabolism."),
                .paragraph("Weight alone is a blunt measure. Muscle mass, body composition and where fat sits all matter, and looking at them together points to better-targeted strategies."),
                .paragraph("Aim for a healthy weight through steady tracking and small lifestyle adjustments."),
            ])
        case .leanBodyMass:
            return ("Lean body mass: a key part of overall health", [
                .paragraph("Lean body mass is your body weight minus your body fat, and it is a useful measure of health."),
                .paragraph("It is made up of muscles, organs and bones. Consistent resistance training for more than 8 weeks can raise it."),
                .paragraph("It can change. Diet, exercise, genetics and hormones all alter how much lean mass you gain, in the short term and over time."),
                .paragraph("It also bears on longevity. Keeping a good amount of it supports well-being and helps protect against disease, and balanced nutrition and exercise help you build it."),
                .paragraph("Track it regularly to stay on top of your overall health."),
            ])
        case .debt:
            return ("What is Sleep Debt?", [
                .paragraph("Sleep debt is the sleep you have lost over time by not getting enough on a regular basis: the gap between the sleep you need and the sleep you actually get. A debt under 30 to 45 minutes is best for performance. Higher levels can hurt your physical and mental health, with tiredness, irritability, poor concentration and memory, and a weaker immune system."),
                .paragraph("Extra sleep and naps can pay the debt back. How long that takes depends on how much you owe, often several nights of good rest, though even 10 to 15 extra minutes a night goes a long way. Avoid long naps close to bedtime and sleeping in too much on weekends, since both make it harder to sleep at night. Naps of 20 to 30 minutes work best."),
            ])
        case .efficiency:
            return ("What is Sleep Efficiency?", [
                .paragraph("Sleep efficiency is the share of your time in bed that you actually spend asleep: time asleep divided by time in bed, times 100. It helps you judge how good your sleep is. On a 0 to 100% scale, 85% or higher is good. With good efficiency you can spend less time in bed and still get the sleep you need."),
                .paragraph("Trouble falling asleep or waking often lowers it, and it is common for efficiency to drop with age or with a sleep disorder such as insomnia or sleep apnea. To raise it, make your room quiet and dark, since bright light cuts melatonin, and go easy on caffeine, alcohol and large or fatty meals close to bedtime. Keeping a steady schedule helps too."),
            ])
        case .restorative:
            return ("What is Restorative Sleep?", [
                .paragraph("Restorative sleep is the time you spend in the deep (slow-wave) and REM stages of sleep each night."),
                .paragraph("Deep sleep is the physically restorative stage, when much of your body's repair happens. REM is the mentally restorative stage, where most dreaming occurs and short-term memories are turned into long-term ones."),
                .paragraph("Make the most of it to give your body its best chance to recover. Spending about 40 to 50% of your night in these stages is a good level for most people. More time in bed, a steadier sleep schedule and no alcohol before bed all help."),
            ])
        case .consistency:
            return ("What is Sleep Consistency?", [
                .paragraph("Sleep consistency measures how similar your sleep and wake times are from night to night. Keeping regular times helps set your body clock, which governs sleep, metabolism and immune function. It is scored 0 to 100%: a higher score means steadier patterns, a lower one more variation. Above 80% is optimal, and 70 to 79% is enough to get by."),
                .paragraph("Going to bed and getting up at the same time every day, weekends included, trains your body to expect sleep and waking. That brings better sleep, more daytime alertness and better health, while erratic patterns throw off your internal clock and lead to poor sleep, fatigue and weaker performance."),
                .paragraph("A one-off nap can briefly lower consistency, especially at an odd time or length. To improve it, try morning sunlight, eating in daylight, regular exercise times, little caffeine in the 8 hours before bed, less light after dark, and naps kept steady in time and length."),
            ])
        case .hoursNeeded:
            return ("What is Sleep Hours vs. Need?", [
                .paragraph("Hours vs. Need compares the hours you slept with the hours you needed each night."),
                .paragraph("Your sleep need is worked out each day from your personal baseline, your sleep debt, your Day Strain and any naps. It is how much sleep you need to perform at your peak."),
                .paragraph("Meeting it consistently speeds up Recovery and helps you perform."),
            ])
        case .timeInBed:
            return ("What is Time in Bed?", [
                .paragraph("Time in bed is the time between getting into bed and getting out of it after waking. It includes the time it takes to fall asleep, known as latency, and any time awake during the night."),
                .paragraph("Watch it to make your sleep more consistent. A steady sleep schedule improves sleep quality and makes it easier to fall asleep and wake up."),
            ])
        case .restPerformance:
            return ("What is Sleep Performance?", [
                .paragraph("Sleep Performance measures the overall quality of your sleep and helps you see improvement over time. It is made up of four parts, and half of the score comes from the first:"),
                .bullet("Hours vs. Needed: the share of your sleep need you actually got"),
                .bullet("Sleep Consistency: how steady your bed and wake times are"),
                .bullet("Sleep Efficiency: how much of your time in bed you spent asleep"),
                .bullet("Restorative sleep: the hours spent in deep and REM sleep"),
                .paragraph("A score of 85% or more is optimal, 70 to 85% is sufficient, and under 70% is poor."),
            ])
        case .respiratory:
            return ("What is Respiratory Rate?", [
                .paragraph("Respiratory rate (RR) is how many breaths you take per minute while asleep."),
                .paragraph("It is your median rate across the night, worked out from the rhythmic rise and fall in your heart rate as you breathe in and out."),
                .paragraph("RR is normally very steady from night to night, so a sharp change is likely meaningful. Illness, fatigue, allergies or a change in altitude can move it, and an unusually high or low rate can sometimes point to an underlying health issue."),
            ])
        case .rhr:
            return ("What is Resting Heart Rate?", [
                .paragraph("Resting heart rate (RHR) is the average number of times your heart beats per minute when you are fully at rest. It is measured during sleep, when your body is at its calmest."),
                .paragraph("In general, a lower RHR points to better fitness: a strong heart muscle pumps more blood with each beat, so it does not need to beat as often."),
                .paragraph("Short-term rises can signal fatigue or illness, while long-term falls point to better cardiovascular health."),
            ])
        case .hrv:
            return ("What is Heart Rate Variability?", [
                .paragraph("Heart rate variability (HRV) measures how much the time between your heartbeats varies while you sleep. It is a good sign of how well your body adapts to its surroundings and performs."),
                .paragraph("HRV is highly individual and differs for everyone: age, gender, lifestyle and fitness all play a part. Rather than comparing yourself with others, compare your HRV with your own baseline over time. In general, a rise points to better fitness and health."),
                .paragraph("Upward trends are a sign your nervous system is balanced and you are performing well. Downward trends can be a sign of overtraining, lack of sleep, dehydration or other negative factors such as stress."),
            ])
        case .charge:
            return ("What is Recovery?", [
                .paragraph("Recovery is a measure of how ready your body is to take on Strain and perform."),
                .paragraph("It is worked out overnight from your resting heart rate, HRV, respiratory rate and sleep, along with other overnight readings you have. Strain, stress and lifestyle choices all affect it, which is why you can have a low Recovery after good sleep, and the other way round."),
                .paragraph("Following Recovery over time can guide your training and help you avoid injury. Track daily behaviors in the Journal to see which ones help or hurt your Recovery most."),
            ])
        }
    }

    var body: some View {
        let e = entry
        NunaInfoCard(title: LocalizedStringKey(e.title)) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(e.items.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .paragraph(let s): Text(verbatim: NSLocalizedString(s, comment: "")).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
                    case .bullet(let s):
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(NunaPalette.textSecondary).frame(width: 4, height: 4).offset(y: -3)
                            Text(verbatim: NSLocalizedString(s, comment: "")).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
#endif
