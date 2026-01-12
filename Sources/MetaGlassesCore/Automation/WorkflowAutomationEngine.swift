import Foundation
import UIKit

/// Workflow Automation Engine
/// Executes multi-step automated workflows with conditional logic and loops
@MainActor
public class WorkflowAutomationEngine: ObservableObject {

    // MARK: - Singleton
    public static let shared = WorkflowAutomationEngine()

    // MARK: - Published Properties
    @Published public var workflows: [Workflow] = []
    @Published public var activeExecutions: [WorkflowExecution] = []
    @Published public var executionHistory: [WorkflowExecution] = []

    // MARK: - Properties
    private let contextSystem = ContextAwarenessSystem.shared
    private let patternLearning = UserPatternLearningSystem.shared
    private let eventTriggers = EventTriggerSystem.shared

    // Workflow templates
    public var templates: [WorkflowTemplate] = []

    // MARK: - Initialization
    private init() {
        loadWorkflows()
        createDefaultTemplates()
        print("🔄 WorkflowAutomationEngine initialized")
    }

    // MARK: - Public Methods

    /// Create new workflow
    public func createWorkflow(_ workflow: Workflow) {
        workflows.append(workflow)
        saveWorkflows()
        print("➕ Created workflow: \(workflow.name)")
    }

    /// Execute workflow
    public func executeWorkflow(_ workflowId: UUID) async {
        guard let workflow = workflows.first(where: { $0.id == workflowId && $0.isEnabled }) else {
            print("❌ Workflow not found or disabled: \(workflowId)")
            return
        }

        let execution = WorkflowExecution(
            id: UUID(),
            workflowId: workflowId,
            workflowName: workflow.name,
            startTime: Date(),
            status: .running
        )

        activeExecutions.append(execution)

        print("▶️ Executing workflow: \(workflow.name)")

        // Execute workflow steps
        let success = await executeSteps(workflow.steps, context: WorkflowContext(), execution: execution)

        // Update execution status
        if let index = activeExecutions.firstIndex(where: { $0.id == execution.id }) {
            activeExecutions[index].endTime = Date()
            activeExecutions[index].status = success ? .completed : .failed

            // Move to history
            executionHistory.append(activeExecutions[index])
            activeExecutions.remove(at: index)

            // Keep only last 100 executions
            if executionHistory.count > 100 {
                executionHistory.removeFirst()
            }
        }

        print(success ? "✅ Workflow completed: \(workflow.name)" : "❌ Workflow failed: \(workflow.name)")
    }

    /// Cancel workflow execution
    public func cancelExecution(_ executionId: UUID) {
        if let index = activeExecutions.firstIndex(where: { $0.id == executionId }) {
            activeExecutions[index].status = .cancelled
            activeExecutions[index].endTime = Date()

            executionHistory.append(activeExecutions[index])
            activeExecutions.remove(at: index)

            print("⏹ Cancelled workflow execution: \(executionId)")
        }
    }

    /// Enable/disable workflow
    public func setWorkflowEnabled(_ workflowId: UUID, enabled: Bool) {
        if let index = workflows.firstIndex(where: { $0.id == workflowId }) {
            workflows[index].isEnabled = enabled
            saveWorkflows()
        }
    }

    /// Delete workflow
    public func deleteWorkflow(_ workflowId: UUID) {
        if let index = workflows.firstIndex(where: { $0.id == workflowId }) {
            let name = workflows[index].name
            workflows.remove(at: index)
            saveWorkflows()
            print("🗑️ Deleted workflow: \(name)")
        }
    }

    // MARK: - Step Execution

    private func executeSteps(_ steps: [WorkflowStep], context: WorkflowContext, execution: WorkflowExecution) async -> Bool {
        var workflowContext = context

        for step in steps {
            print("📍 Executing step: \(step.name)")

            // Check if execution was cancelled
            if let exec = activeExecutions.first(where: { $0.id == execution.id }),
               exec.status == .cancelled {
                return false
            }

            let success = await executeStep(step, context: &workflowContext)

            if !success {
                if step.continueOnError {
                    print("⚠️ Step failed but continuing: \(step.name)")
                } else {
                    print("❌ Step failed, stopping workflow: \(step.name)")
                    return false
                }
            }

            // Update execution progress
            if let index = activeExecutions.firstIndex(where: { $0.id == execution.id }) {
                activeExecutions[index].stepsCompleted += 1
            }
        }

        return true
    }

    private func executeStep(_ step: WorkflowStep, context: inout WorkflowContext) async -> Bool {
        switch step.type {
        case .action(let action):
            return await executeAction(action, context: &context)

        case .condition(let condition):
            return await executeCondition(condition, steps: step.conditionalSteps ?? [], context: &context)

        case .loop(let loop):
            return await executeLoop(loop, steps: step.loopSteps ?? [], context: &context)

        case .delay(let seconds):
            return await executeDelay(seconds)

        case .parallel(let steps):
            return await executeParallel(steps, context: &context)

        case .setVariable(let name, let value):
            context.variables[name] = value
            return true

        case .callWorkflow(let workflowId):
            return await executeNestedWorkflow(workflowId, context: &context)
        }
    }

    // MARK: - Action Execution

    private func executeAction(_ action: WorkflowAction, context: inout WorkflowContext) async -> Bool {
        print("⚡️ Action: \(action.type.rawValue)")

        switch action.type {
        case .capturePhoto:
            // Integrate with camera system
            context.variables["lastPhoto"] = "photo_\(UUID().uuidString).jpg"
            return true

        case .captureVideo:
            context.variables["lastVideo"] = "video_\(UUID().uuidString).mp4"
            return true

        case .analyzeScene:
            // Integrate with vision system
            context.variables["sceneAnalysis"] = "Scene analyzed"
            return true

        case .sendNotification:
            if let message = action.parameters["message"] {
                await sendNotification(message)
            }
            return true

        case .saveToMemory:
            print("💾 Saving to memory")
            return true

        case .triggerEvent:
            if let eventId = action.parameters["eventId"],
               let uuid = UUID(uuidString: eventId) {
                // Trigger event
                print("🔥 Triggering event: \(uuid)")
            }
            return true

        case .executeScript:
            if let script = action.parameters["script"] {
                return executeScript(script, context: &context)
            }
            return false

        case .httpRequest:
            if let url = action.parameters["url"] {
                return await executeHTTPRequest(url, context: &context)
            }
            return false

        case .custom:
            print("🔧 Custom action")
            return true
        }
    }

    // MARK: - Conditional Logic

    private func executeCondition(_ condition: WorkflowCondition, steps: [WorkflowStep], context: inout WorkflowContext) async -> Bool {
        let conditionMet = evaluateCondition(condition, context: context)

        print("🔍 Condition '\(condition.description)': \(conditionMet ? "TRUE" : "FALSE")")

        if conditionMet {
            return await executeSteps(steps, context: context, execution: WorkflowExecution(
                id: UUID(),
                workflowId: UUID(),
                workflowName: "Conditional",
                startTime: Date(),
                status: .running
            ))
        }

        return true
    }

    private func evaluateCondition(_ condition: WorkflowCondition, context: WorkflowContext) -> Bool {
        switch condition.type {
        case .timeOfDay(let time):
            let currentContext = contextSystem.getCurrentContext()
            return currentContext.timeOfDay == time

        case .location(let placeName):
            let currentContext = contextSystem.getCurrentContext()
            return currentContext.location?.placeName?.contains(placeName) ?? false

        case .activity(let activity):
            let currentContext = contextSystem.getCurrentContext()
            return currentContext.activityType == activity

        case .battery(let comparison, let threshold):
            let currentContext = contextSystem.getCurrentContext()
            switch comparison {
            case .lessThan:
                return currentContext.batteryLevel < threshold
            case .greaterThan:
                return currentContext.batteryLevel > threshold
            case .equals:
                return abs(currentContext.batteryLevel - threshold) < 0.01
            }

        case .variable(let name, let value):
            return context.variables[name] == value

        case .custom(let evaluator):
            return evaluator(context)
        }
    }

    // MARK: - Loop Execution

    private func executeLoop(_ loop: LoopType, steps: [WorkflowStep], context: inout WorkflowContext) async -> Bool {
        print("🔁 Starting loop")

        switch loop {
        case .count(let times):
            for i in 0..<times {
                context.variables["loopIndex"] = "\(i)"

                let success = await executeSteps(steps, context: context, execution: WorkflowExecution(
                    id: UUID(),
                    workflowId: UUID(),
                    workflowName: "Loop",
                    startTime: Date(),
                    status: .running
                ))

                if !success {
                    return false
                }
            }

        case .while(let condition):
            var iterations = 0
            let maxIterations = 100 // Safety limit

            while evaluateCondition(condition, context: context) && iterations < maxIterations {
                let success = await executeSteps(steps, context: context, execution: WorkflowExecution(
                    id: UUID(),
                    workflowId: UUID(),
                    workflowName: "Loop",
                    startTime: Date(),
                    status: .running
                ))

                if !success {
                    return false
                }

                iterations += 1
            }

        case .forEach(let items):
            for item in items {
                context.variables["currentItem"] = item

                let success = await executeSteps(steps, context: context, execution: WorkflowExecution(
                    id: UUID(),
                    workflowId: UUID(),
                    workflowName: "Loop",
                    startTime: Date(),
                    status: .running
                ))

                if !success {
                    return false
                }
            }
        }

        return true
    }

    // MARK: - Utility Methods

    private func executeDelay(_ seconds: TimeInterval) async -> Bool {
        print("⏰ Delaying for \(seconds) seconds")
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return true
    }

    private func executeParallel(_ steps: [WorkflowStep], context: inout WorkflowContext) async -> Bool {
        print("⚡️ Executing \(steps.count) steps in parallel")

        await withTaskGroup(of: Bool.self) { group in
            for step in steps {
                group.addTask {
                    var localContext = context
                    return await self.executeStep(step, context: &localContext)
                }
            }

            var allSuccess = true
            for await success in group {
                if !success {
                    allSuccess = false
                }
            }

            return allSuccess
        }
    }

    private func executeNestedWorkflow(_ workflowId: UUID, context: inout WorkflowContext) async -> Bool {
        print("🔄 Executing nested workflow: \(workflowId)")
        await executeWorkflow(workflowId)
        return true
    }

    private func executeScript(_ script: String, context: inout WorkflowContext) -> Bool {
        print("📝 Executing script: \(script)")
        // Simple script execution (extend as needed)
        return true
    }

    private func executeHTTPRequest(_ url: String, context: inout WorkflowContext) async -> Bool {
        print("🌐 HTTP Request to: \(url)")

        guard let requestURL = URL(string: url) else {
            return false
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: requestURL)
            context.variables["httpResponse"] = String(data: data, encoding: .utf8) ?? ""
            return true
        } catch {
            print("❌ HTTP Request failed: \(error.localizedDescription)")
            return false
        }
    }

    private func sendNotification(_ message: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Workflow"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Templates

    private func createDefaultTemplates() {
        templates = [
            WorkflowTemplate(
                id: UUID(),
                name: "Morning Routine",
                description: "Automated actions for your morning",
                category: .routine,
                steps: [
                    WorkflowStep(
                        id: UUID(),
                        name: "Capture sunrise",
                        type: .action(WorkflowAction(type: .capturePhoto))
                    ),
                    WorkflowStep(
                        id: UUID(),
                        name: "Send good morning notification",
                        type: .action(WorkflowAction(
                            type: .sendNotification,
                            parameters: ["message": "Good morning! Your day starts now."]
                        ))
                    )
                ]
            ),
            WorkflowTemplate(
                id: UUID(),
                name: "Commute Tracker",
                description: "Track your daily commute",
                category: .travel,
                steps: [
                    WorkflowStep(
                        id: UUID(),
                        name: "Detect driving",
                        type: .condition(WorkflowCondition(
                            type: .activity(.driving),
                            description: "Check if driving"
                        ))
                    ),
                    WorkflowStep(
                        id: UUID(),
                        name: "Log commute start",
                        type: .action(WorkflowAction(
                            type: .saveToMemory,
                            parameters: ["event": "Commute started"]
                        ))
                    )
                ]
            ),
            WorkflowTemplate(
                id: UUID(),
                name: "Meeting Capture",
                description: "Auto-capture during meetings",
                category: .work,
                steps: [
                    WorkflowStep(
                        id: UUID(),
                        name: "Take photo every 5 min",
                        type: .loop(LoopType.count(12), loopSteps: [
                            WorkflowStep(
                                id: UUID(),
                                name: "Capture",
                                type: .action(WorkflowAction(type: .capturePhoto))
                            ),
                            WorkflowStep(
                                id: UUID(),
                                name: "Wait",
                                type: .delay(300)
                            )
                        ])
                    )
                ]
            )
        ]

        print("📋 Created \(templates.count) workflow templates")
    }

    /// Create workflow from template
    public func createFromTemplate(_ templateId: UUID, name: String) -> Workflow? {
        guard let template = templates.first(where: { $0.id == templateId }) else {
            return nil
        }

        let workflow = Workflow(
            id: UUID(),
            name: name,
            description: template.description,
            steps: template.steps,
            isEnabled: true,
            createdAt: Date()
        )

        createWorkflow(workflow)
        return workflow
    }

    // MARK: - Persistence

    private var workflowsFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("workflows.json")
    }

    private func saveWorkflows() {
        if let data = try? JSONEncoder().encode(workflows) {
            try? data.write(to: workflowsFileURL)
        }
    }

    private func loadWorkflows() {
        if let data = try? Data(contentsOf: workflowsFileURL),
           let loadedWorkflows = try? JSONDecoder().decode([Workflow].self, from: data) {
            workflows = loadedWorkflows
            print("📚 Loaded \(workflows.count) workflows")
        }
    }

    /// Clear all workflows
    public func clearAllWorkflows() {
        workflows.removeAll()
        activeExecutions.removeAll()
        executionHistory.removeAll()
        saveWorkflows()

        print("🗑️ Cleared all workflows")
    }
}

// MARK: - Models

public struct Workflow: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public var steps: [WorkflowStep]
    public var isEnabled: Bool
    public let createdAt: Date
    public var lastRun: Date?

    public init(id: UUID, name: String, description: String, steps: [WorkflowStep], isEnabled: Bool = true, createdAt: Date = Date(), lastRun: Date? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.steps = steps
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastRun = lastRun
    }
}

public struct WorkflowStep: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let type: StepType
    public var continueOnError: Bool
    public var conditionalSteps: [WorkflowStep]?
    public var loopSteps: [WorkflowStep]?

    public init(id: UUID, name: String, type: StepType, continueOnError: Bool = false, conditionalSteps: [WorkflowStep]? = nil, loopSteps: [WorkflowStep]? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.continueOnError = continueOnError
        self.conditionalSteps = conditionalSteps
        self.loopSteps = loopSteps
    }
}

public enum StepType: Codable {
    case action(WorkflowAction)
    case condition(WorkflowCondition, thenSteps: [WorkflowStep] = [])
    case loop(LoopType, steps: [WorkflowStep] = [])
    case delay(TimeInterval)
    case parallel([WorkflowStep])
    case setVariable(name: String, value: String)
    case callWorkflow(UUID)
}

public struct WorkflowAction: Codable {
    public let type: ActionType
    public let parameters: [String: String]

    public init(type: ActionType, parameters: [String: String] = [:]) {
        self.type = type
        self.parameters = parameters
    }

    public enum ActionType: String, Codable {
        case capturePhoto
        case captureVideo
        case analyzeScene
        case sendNotification
        case saveToMemory
        case triggerEvent
        case executeScript
        case httpRequest
        case custom
    }
}

public struct WorkflowCondition: Codable {
    public let type: ConditionType
    public let description: String

    public init(type: ConditionType, description: String) {
        self.type = type
        self.description = description
    }
}

public enum ConditionType: Codable {
    case timeOfDay(TimeOfDay)
    case location(String)
    case activity(ActivityType)
    case battery(Comparison, Float)
    case variable(String, String)
    case custom((WorkflowContext) -> Bool)

    // Codable conformance
    enum CodingKeys: String, CodingKey {
        case type
    }

    public func encode(to encoder: Encoder) throws {
        // Simplified encoding
    }

    public init(from decoder: Decoder) throws {
        // Simplified decoding
        self = .variable("", "")
    }
}

public enum Comparison: String, Codable {
    case lessThan
    case greaterThan
    case equals
}

public enum LoopType: Codable {
    case count(Int)
    case while(WorkflowCondition)
    case forEach([String])
}

public struct WorkflowContext {
    public var variables: [String: String] = [:]
    public var data: [String: Any] = [:]

    public init() {}
}

public struct WorkflowExecution: Identifiable {
    public let id: UUID
    public let workflowId: UUID
    public let workflowName: String
    public let startTime: Date
    public var endTime: Date?
    public var status: ExecutionStatus
    public var stepsCompleted: Int = 0

    public init(id: UUID, workflowId: UUID, workflowName: String, startTime: Date, endTime: Date? = nil, status: ExecutionStatus = .running, stepsCompleted: Int = 0) {
        self.id = id
        self.workflowId = workflowId
        self.workflowName = workflowName
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.stepsCompleted = stepsCompleted
    }
}

public enum ExecutionStatus: String {
    case running
    case completed
    case failed
    case cancelled
}

public struct WorkflowTemplate: Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public let category: TemplateCategory
    public let steps: [WorkflowStep]

    public init(id: UUID, name: String, description: String, category: TemplateCategory, steps: [WorkflowStep]) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.steps = steps
    }
}

public enum TemplateCategory: String {
    case routine
    case travel
    case work
    case health
    case custom
}
