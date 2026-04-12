import Foundation

/// Fetches weather data from Open-Meteo and correlates with user behavior patterns.
/// Generates insights like "You order 2x more delivery on rainy days".
actor WeatherCorrelation {
    static let shared = WeatherCorrelation()

    private let cacheKey = "weather_cache"
    private var cachedWeather: [WeatherData] = []

    // MARK: - Models

    struct WeatherData: Codable {
        let date: String             // "2026-04-10"
        let condition: String        // "sunny", "rainy", "cloudy", "snowy", "foggy", "stormy"
        let tempHigh: Double
        let tempLow: Double
        let humidity: Double
    }

    struct WeatherInsight {
        let title: String
        let description: String
        let icon: String
    }

    private init() {
        cachedWeather = loadCache()
    }

    // MARK: - Fetch Weather

    /// Fetch current weather from Open-Meteo (free, no API key).
    func fetchCurrentWeather(lat: Double, lon: Double) async -> WeatherData? {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&daily=temperature_2m_max,temperature_2m_min,weathercode,relative_humidity_2m_max&current_weather=true&timezone=auto"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            // Parse daily data (today is index 0)
            guard let daily = json["daily"] as? [String: Any],
                  let dates = daily["time"] as? [String],
                  let maxTemps = daily["temperature_2m_max"] as? [Double],
                  let minTemps = daily["temperature_2m_min"] as? [Double],
                  let weatherCodes = daily["weathercode"] as? [Int],
                  !dates.isEmpty else { return nil }

            // Humidity might be an array or absent
            let humidities = daily["relative_humidity_2m_max"] as? [Double]
            let humidity = humidities?.first ?? 50.0

            let condition = Self.conditionFromCode(weatherCodes[0])

            let weather = WeatherData(
                date: dates[0],
                condition: condition,
                tempHigh: maxTemps[0],
                tempLow: minTemps[0],
                humidity: humidity
            )

            // Cache it
            cachedWeather.removeAll { $0.date == weather.date }
            cachedWeather.append(weather)
            // Keep last 90 days of cache
            if cachedWeather.count > 90 {
                cachedWeather = Array(cachedWeather.suffix(90))
            }
            saveCache()

            return weather
        } catch {
            return nil
        }
    }

    /// Get today's weather using home location from UserProfileStore.
    func todayWeather() async -> WeatherData? {
        let profile = await UserProfileStore.shared.currentProfile()

        // Find home location
        let home = profile.frequentLocations.first { loc in
            loc.label?.lowercased() == "home" || loc.inferredType == "residence"
        } ?? profile.frequentLocations.first

        guard let location = home else { return nil }

        return await fetchCurrentWeather(lat: location.latitude, lon: location.longitude)
    }

    // MARK: - Insights

    /// Generate behavioral insights correlated with weather patterns.
    func generateInsights() async -> [WeatherInsight] {
        var insights: [WeatherInsight] = []
        guard cachedWeather.count >= 7 else {
            return [WeatherInsight(
                title: "Building Weather Profile",
                description: "Keep using NodeCompass for a week to see weather-based insights.",
                icon: "cloud.sun"
            )]
        }

        // Build a lookup: date string -> weather condition
        var weatherByDate: [String: String] = [:]
        for w in cachedWeather {
            weatherByDate[w.date] = w.condition
        }

        // Get transactions for correlation
        let transactions = await MainActor.run { TransactionStore.shared.transactions }
        let foodEntries = await FoodStore.shared.entries(since: Calendar.current.date(byAdding: .day, value: -30, to: Date())!)
        let moodEntries = await MoodStore.shared.recentEntries(days: 30)
        let lifeScores = await LifeScoreEngine.shared.recentScores(days: 30)

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        // --- Food delivery on rainy vs sunny days ---
        let deliveryByCondition = groupByCondition(items: foodEntries, weatherByDate: weatherByDate, dateFormatter: df) { entry in
            df.string(from: entry.timestamp)
        } filter: { entry in
            entry.source == .emailOrder
        }

        if let rainyCount = deliveryByCondition["rainy"], let sunnyCount = deliveryByCondition["sunny"], sunnyCount > 0 {
            let ratio = Double(rainyCount) / Double(sunnyCount)
            if ratio > 1.3 {
                insights.append(WeatherInsight(
                    title: "Rainy Day Delivery Fan",
                    description: "You order \(String(format: "%.1f", ratio))x more delivery on rainy days compared to sunny days.",
                    icon: "cloud.rain"
                ))
            }
        }

        // --- Spending on different weather ---
        var spendByCondition: [String: (total: Double, days: Int)] = [:]
        for txn in transactions where txn.type.uppercased() == "DEBIT" {
            let dateStr = df.string(from: txn.date)
            guard let condition = weatherByDate[dateStr] else { continue }
            var entry = spendByCondition[condition] ?? (total: 0, days: 0)
            entry.total += txn.amount
            spendByCondition[condition] = entry
        }
        // Count unique days per condition
        var daysPerCondition: [String: Set<String>] = [:]
        for (dateStr, condition) in weatherByDate {
            daysPerCondition[condition, default: []].insert(dateStr)
        }
        for (condition, daySet) in daysPerCondition {
            if var entry = spendByCondition[condition] {
                entry.days = daySet.count
                spendByCondition[condition] = entry
            }
        }

        let avgSpendByCondition = spendByCondition.mapValues { $0.days > 0 ? $0.total / Double($0.days) : 0 }
        if let rainyAvg = avgSpendByCondition["rainy"], let sunnyAvg = avgSpendByCondition["sunny"], sunnyAvg > 0 {
            let diff = rainyAvg - sunnyAvg
            if diff > 0 {
                insights.append(WeatherInsight(
                    title: "Rain Tax",
                    description: "You spend \(NC.money(diff)) more per day when it rains vs sunny days.",
                    icon: "cloud.rain.fill"
                ))
            } else if diff < -100 {
                insights.append(WeatherInsight(
                    title: "Sunshine Spender",
                    description: "You spend \(NC.money(abs(diff))) more per day on sunny days.",
                    icon: "sun.max.fill"
                ))
            }
        }

        // --- Mood on different weather ---
        var moodByCondition: [String: [Int]] = [:]
        for entry in moodEntries {
            guard let condition = weatherByDate[entry.dateKey] else { continue }
            moodByCondition[condition, default: []].append(entry.mood.rawValue)
        }
        let avgMoodByCondition = moodByCondition.mapValues { moods -> Double in
            moods.isEmpty ? 0 : Double(moods.reduce(0, +)) / Double(moods.count)
        }
        if let sunnyMood = avgMoodByCondition["sunny"], let rainyMood = avgMoodByCondition["rainy"] {
            if sunnyMood - rainyMood > 0.5 {
                insights.append(WeatherInsight(
                    title: "Sunshine Lifts Your Mood",
                    description: "Your mood averages \(String(format: "%.1f", sunnyMood))/5 on sunny days vs \(String(format: "%.1f", rainyMood))/5 on rainy days.",
                    icon: "sun.max.fill"
                ))
            } else if rainyMood > sunnyMood + 0.3 {
                insights.append(WeatherInsight(
                    title: "Cozy Rain Lover",
                    description: "Interestingly, your mood is higher on rainy days (\(String(format: "%.1f", rainyMood))/5).",
                    icon: "cloud.rain"
                ))
            }
        }

        // --- Steps on different weather ---
        var stepsByCondition: [String: [Int]] = [:]
        for score in lifeScores {
            guard let condition = weatherByDate[score.dateKey] else { continue }
            // Use health score as a proxy for step activity
            stepsByCondition[condition, default: []].append(score.health)
        }
        let avgStepsByCondition = stepsByCondition.mapValues { vals -> Double in
            vals.isEmpty ? 0 : Double(vals.reduce(0, +)) / Double(vals.count)
        }
        if let sunnySteps = avgStepsByCondition["sunny"], let rainySteps = avgStepsByCondition["rainy"], sunnySteps > 0 {
            if sunnySteps - rainySteps > 10 {
                insights.append(WeatherInsight(
                    title: "Fair Weather Walker",
                    description: "Your health score drops by \(Int(sunnySteps - rainySteps)) points on rainy days. Try indoor workouts!",
                    icon: "figure.walk"
                ))
            }
        }

        // --- Temperature insights ---
        let hotDays = cachedWeather.filter { $0.tempHigh > 35 }
        let coldDays = cachedWeather.filter { $0.tempLow < 10 }
        if hotDays.count >= 3 {
            let hotDateSet = Set(hotDays.map { $0.date })
            let hotSpend = transactions
                .filter { txn in txn.type.uppercased() == "DEBIT" && hotDateSet.contains(df.string(from: txn.date)) }
                .reduce(0.0) { $0 + $1.amount }
            let avgHotSpend = Double(hotDays.count) > 0 ? hotSpend / Double(hotDays.count) : 0
            if avgHotSpend > 0 {
                insights.append(WeatherInsight(
                    title: "Heat Wave Spending",
                    description: "On hot days (35C+), you spend an average of \(NC.money(avgHotSpend))/day.",
                    icon: "thermometer.sun.fill"
                ))
            }
        }
        if coldDays.count >= 3 {
            insights.append(WeatherInsight(
                title: "Cold Snap Pattern",
                description: "You had \(coldDays.count) cold days recently. Bundle up and check your heating bills!",
                icon: "thermometer.snowflake"
            ))
        }

        if insights.isEmpty {
            insights.append(WeatherInsight(
                title: "No Strong Patterns Yet",
                description: "Your behavior is consistent across weather conditions. Keep logging for more insights!",
                icon: "cloud.sun"
            ))
        }

        return insights
    }

    func clearAll() {
        cachedWeather = []
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    // MARK: - Helpers

    /// Map WMO weather codes to human-readable conditions.
    private static func conditionFromCode(_ code: Int) -> String {
        switch code {
        case 0...3:   return "sunny"
        case 45...48: return "foggy"
        case 51...67: return "rainy"
        case 71...77: return "snowy"
        case 80...82: return "rainy"
        case 95...99: return "stormy"
        default:      return "cloudy"
        }
    }

    /// Group items by weather condition for the date they occurred.
    private func groupByCondition<T>(
        items: [T],
        weatherByDate: [String: String],
        dateFormatter: DateFormatter,
        dateKey: (T) -> String,
        filter: (T) -> Bool
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for item in items where filter(item) {
            let dk = dateKey(item)
            guard let condition = weatherByDate[dk] else { continue }
            counts[condition, default: 0] += 1
        }
        return counts
    }

    // MARK: - Persistence

    private func loadCache() -> [WeatherData] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([WeatherData].self, from: data) else { return [] }
        return decoded
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(cachedWeather) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}
