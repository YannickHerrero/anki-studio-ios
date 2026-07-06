import Foundation
import BackgroundTasks

/// Runs an import inside a BGContinuedProcessingTask (iOS 26) so the whole
/// pipeline keeps executing when the app is backgrounded — with the system's
/// own Live Activity showing title, phase and progress in the Dynamic Island
/// and on the lock screen, including a user cancel.
@available(iOS 26.0, *)
@MainActor
enum BackgroundImporter {
    /// Must be prefixed with the bundle id and listed in
    /// BGTaskSchedulerPermittedIdentifiers.
    static let identifier = "com.yannickherrero.ankistudio.import"

    private static var pendingWork: (@MainActor () async -> Void)?
    private static var pendingExpiration: (@MainActor () -> Void)?
    private static var activeTask: BGContinuedProcessingTask?
    private static var activeTitle = "Importing video"

    /// Call once, before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in handle(task) }
        }
    }

    /// Submit the pipeline as continued-processing work. Returns false when
    /// the scheduler refuses (e.g. simulator) — caller falls back in-process.
    static func begin(
        title: String,
        work: @escaping @MainActor () async -> Void,
        onExpiration: @escaping @MainActor () -> Void
    ) -> Bool {
        pendingWork = work
        pendingExpiration = onExpiration
        activeTitle = title

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier, title: title, subtitle: "Preparing…")
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            pendingWork = nil
            pendingExpiration = nil
            return false
        }
    }

    private static func handle(_ task: BGContinuedProcessingTask) {
        guard let work = pendingWork else {
            task.setTaskCompleted(success: false)
            return
        }
        let expiration = pendingExpiration
        pendingWork = nil
        pendingExpiration = nil

        task.progress.totalUnitCount = 100
        activeTask = task

        let job = Task { @MainActor in
            await work()
            task.setTaskCompleted(success: true)
            activeTask = nil
        }
        task.expirationHandler = {
            job.cancel()
            Task { @MainActor in
                expiration?()
                activeTask = nil
            }
        }
    }

    /// Push pipeline progress into the system Live Activity.
    static func report(overall: Double, phase: String) {
        guard let task = activeTask else { return }
        task.progress.completedUnitCount = Int64((overall * 100).rounded())
        task.updateTitle(activeTitle, subtitle: phase)
    }
}
