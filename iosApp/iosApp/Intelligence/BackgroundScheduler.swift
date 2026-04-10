import Foundation
import BackgroundTasks
import UIKit

/// Registers and handles BGTaskScheduler tasks for background intelligence analysis.
/// - App refresh task: lightweight check every ~1 hour
/// - Processing task: full analysis when device is charging/idle
enum BackgroundScheduler {

    static let refreshTaskId = "com.nodecompass.app.refresh"
    static let processingTaskId = "com.nodecompass.app.processing"

    /// Call once from AppDelegate/App init to register task handlers.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskId,
            using: nil
        ) { task in
            handleRefreshTask(task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingTaskId,
            using: nil
        ) { task in
            handleProcessingTask(task as! BGProcessingTask)
        }
    }

    /// Schedule the next background tasks. Call after each foreground analysis.
    static func scheduleNextTasks() {
        scheduleRefresh()
        scheduleProcessing()
    }

    // MARK: - Scheduling

    private static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600) // 1 hour
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
        }
    }

    private static func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 7200) // 2 hours
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
        }
    }

    // MARK: - Task Handlers

    private static func handleRefreshTask(_ task: BGAppRefreshTask) {
        scheduleRefresh() // Schedule the next one

        let analysisTask = Task {
            // Collect latest health data before analysis
            if UserDefaults.standard.bool(forKey: "healthKitAuthorized") {
                await HealthCollector.shared.collectAndStore()
            }
            await PatternEngine.shared.runAnalysis()
        }

        task.expirationHandler = {
            analysisTask.cancel()
        }

        Task {
            await analysisTask.value
            task.setTaskCompleted(success: true)
        }
    }

    private static func handleProcessingTask(_ task: BGProcessingTask) {
        scheduleProcessing() // Schedule the next one

        let analysisTask = Task {
            if UserDefaults.standard.bool(forKey: "healthKitAuthorized") {
                await HealthCollector.shared.collectAndStore()
            }
            await PatternEngine.shared.runAnalysis()
        }

        task.expirationHandler = {
            analysisTask.cancel()
        }

        Task {
            await analysisTask.value
            task.setTaskCompleted(success: true)
        }
    }
}
