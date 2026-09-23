import Foundation

/// Maps NOOP's persisted workout labels to Strava's standard `sport_type` values.
///
/// Strava uses this field when importing a file, so downstream services see the same
/// activity family even when the FIT payload is sparse or the label is localized.
enum StravaActivityType {
    static func value(for sport: String) -> String {
        let key = sport.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        switch key {
        case "run", "running": return "Run"
        case "trail run", "trailrun": return "TrailRun"
        case "treadmill run": return "VirtualRun"
        case "walk", "walking": return "Walk"
        case "hike", "hiking", "rucking": return "Hike"
        case "cycle", "cycling", "bike", "biking", "ride": return "Ride"
        case "mountain biking", "mountain bike": return "MountainBikeRide"
        case "indoor cycle", "spinning": return "VirtualRide"
        case "swim", "swimming", "open water swim", "open water swimming", "pool swim": return "Swim"
        case "row", "rowing", "row machine": return "Rowing"
        case "elliptical": return "Elliptical"
        case "stair climber", "stair stepper": return "StairStepper"
        case "strength", "strength training", "bodybuilding", "weightlifting", "powerlifting": return "WeightTraining"
        case "crossfit": return "Crossfit"
        case "yoga": return "Yoga"
        case "pilates": return "Workout"
        case "boxing", "kickboxing": return "Boxing"
        case "basketball": return "Basketball"
        case "soccer": return "Soccer"
        case "baseball": return "Baseball"
        case "badminton": return "Badminton"
        case "tennis": return "Tennis"
        case "squash": return "Squash"
        case "racquetball": return "Racquetball"
        case "table tennis": return "TableTennis"
        case "volleyball", "sand volleyball": return "Volleyball"
        case "martial arts": return "MartialArts"
        case "dancing", "dance": return "Dance"
        case "golf": return "Golf"
        case "climbing": return "Climbing"
        case "skiing": return "AlpineSki"
        case "snowboarding": return "Snowboard"
        case "kayaking": return "Kayaking"
        case "sailing": return "Sailing"
        case "surfing": return "Surfing"
        case "ice skating": return "IceSkate"
        case "inline skating": return "InlineSkate"
        case "snowshoeing": return "Snowshoe"
        case "water polo": return "WaterPolo"
        case "ice hockey": return "IceHockey"
        case "stand up paddleboard": return "StandUpPaddling"
        case "pickleball": return "Pickleball"
        default: return "Workout"
        }
    }
}
