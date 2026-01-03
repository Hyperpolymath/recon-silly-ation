// SPDX-License-Identifier: MIT
// Docudactyl - Documentation workflow orchestrator
// DD-M01 through DD-M10: MUST requirements

// =============================================================================
// DD-M01: Module structure with ReScript types
// =============================================================================

type componentId =
  | FormatrixDocs
  | ReconSillyAtion
  | Docubot
  | ArangoDB

type componentStatus =
  | Healthy
  | Degraded({reason: string})
  | Unhealthy({reason: string})
  | Unknown

type componentHealth = {
  componentId: componentId,
  status: componentStatus,
  lastCheck: float,
  latencyMs: option<float>,
  version: option<string>,
}

// DD-M02: Event bus for component communication
type eventType =
  | DocumentCreated
  | DocumentModified
  | DocumentDeleted
  | ReconciliationStarted
  | ReconciliationCompleted
  | EnforcementViolation
  | PackShipped
  | GenerationRequested
  | GenerationCompleted
  | ApprovalRequired
  | ApprovalGranted
  | ApprovalRejected
  | HealthCheckCompleted
  | PipelineStarted
  | PipelineStepCompleted
  | PipelineFailed
  | PipelineCompleted

type event = {
  id: string,
  eventType: eventType,
  source: componentId,
  timestamp: float,
  payload: Js.Json.t,
  correlationId: option<string>,
}

type eventHandler = event => unit

type eventBus = {
  mutable handlers: Js.Dict.t<array<eventHandler>>,
  mutable eventLog: array<event>,
}

// DD-M03: Scheduler for periodic tasks
type scheduleInterval =
  | Seconds(int)
  | Minutes(int)
  | Hours(int)
  | Daily({hour: int, minute: int})
  | Weekly({dayOfWeek: int, hour: int, minute: int})
  | Cron(string)

type scheduledTask = {
  id: string,
  name: string,
  interval: scheduleInterval,
  pipelineId: string,
  enabled: bool,
  lastRun: option<float>,
  nextRun: option<float>,
  runCount: int,
  failCount: int,
}

type scheduler = {
  mutable tasks: array<scheduledTask>,
  mutable running: bool,
}

// DD-M04: Pipeline definition format
type pipelineStepType =
  | Scan({repoPath: string})
  | Reconcile({bundleId: string})
  | Enforce({packSpec: string})
  | Ship({destination: string})
  | Generate({docType: string, format: string})
  | Approve({generationId: string})
  | Notify({channel: string, message: string})
  | Custom({action: string, params: Js.Dict.t<string>})

type pipelineStep = {
  id: string,
  name: string,
  stepType: pipelineStepType,
  dependsOn: array<string>,
  timeout: int, // seconds
  retries: int,
  continueOnError: bool,
}

type pipelineDefinition = {
  id: string,
  name: string,
  description: string,
  steps: array<pipelineStep>,
  triggers: array<eventType>,
  enabled: bool,
}

// DD-M05: Pipeline executor state
type stepStatus =
  | Pending
  | Running
  | Completed({duration: float})
  | Failed({error: string, duration: float})
  | Skipped({reason: string})

type pipelineExecution = {
  id: string,
  pipelineId: string,
  startedAt: float,
  completedAt: option<float>,
  status: string, // "running", "completed", "failed", "cancelled"
  stepStatuses: Js.Dict.t<stepStatus>,
  context: Js.Dict.t<Js.Json.t>,
  triggeredBy: option<string>,
}

// DD-M07: Configuration management
type configuration = {
  // Component endpoints
  formatrixEndpoint: option<string>,
  rsaEndpoint: option<string>,
  docubotEndpoint: option<string>,
  arangoEndpoint: string,
  arangoDatabase: string,
  arangoUsername: string,
  arangoPassword: string,

  // Scheduling
  defaultScanInterval: int, // seconds
  healthCheckInterval: int, // seconds

  // Limits
  maxConcurrentPipelines: int,
  pipelineTimeout: int, // seconds
  eventLogRetention: int, // days

  // Notifications
  notificationEndpoints: Js.Dict.t<string>,
}

// DD-M08: Logging and metrics
type logLevel =
  | Debug
  | Info
  | Warn
  | Error

type logEntry = {
  timestamp: float,
  level: logLevel,
  component: string,
  message: string,
  context: option<Js.Dict.t<string>>,
}

type metric = {
  name: string,
  value: float,
  timestamp: float,
  tags: Js.Dict.t<string>,
}

type metricsStore = {
  mutable logs: array<logEntry>,
  mutable metrics: array<metric>,
}

// DD-M09: Error handling and recovery
type errorSeverity =
  | Recoverable
  | Critical
  | Fatal

type orchestratorError = {
  id: string,
  severity: errorSeverity,
  component: componentId,
  message: string,
  stack: option<string>,
  timestamp: float,
  recovered: bool,
  recoveryAction: option<string>,
}

// =============================================================================
// Implementation
// =============================================================================

// Global state
let globalEventBus: eventBus = {
  handlers: Js.Dict.empty(),
  eventLog: [],
}

let globalScheduler: scheduler = {
  tasks: [],
  running: false,
}

let globalPipelines: Js.Dict.t<pipelineDefinition> = Js.Dict.empty()
let globalExecutions: Js.Dict.t<pipelineExecution> = Js.Dict.empty()
let globalHealth: Js.Dict.t<componentHealth> = Js.Dict.empty()
let globalMetrics: metricsStore = {logs: [], metrics: []}
let globalErrors: array<orchestratorError> = []

let globalConfig: configuration = {
  formatrixEndpoint: None,
  rsaEndpoint: None,
  docubotEndpoint: None,
  arangoEndpoint: "http://localhost:8529",
  arangoDatabase: "docudactyl",
  arangoUsername: "root",
  arangoPassword: "",
  defaultScanInterval: 300,
  healthCheckInterval: 60,
  maxConcurrentPipelines: 5,
  pipelineTimeout: 3600,
  eventLogRetention: 30,
  notificationEndpoints: Js.Dict.empty(),
}

// Generate unique ID
let generateId = (prefix: string): string => {
  let now = Js.Date.now()
  let rand = Js.Math.random() *. 1000000.0
  `${prefix}-${now->Float.toString}-${rand->Float.toInt->Int.toString}`
}

// DD-M08: Logging
let log = (~level: logLevel, ~component: string, ~message: string, ~context: option<Js.Dict.t<string>>=?): unit => {
  let entry: logEntry = {
    timestamp: Js.Date.now(),
    level: level,
    component: component,
    message: message,
    context: context,
  }
  globalMetrics.logs = Array.concat(globalMetrics.logs, [entry])

  // Also console log for debugging
  let levelStr = switch level {
  | Debug => "DEBUG"
  | Info => "INFO"
  | Warn => "WARN"
  | Error => "ERROR"
  }
  Js.Console.log(`[${levelStr}] [${component}] ${message}`)
}

// DD-M08: Record metric
let recordMetric = (~name: string, ~value: float, ~tags: Js.Dict.t<string>=Js.Dict.empty()): unit => {
  let m: metric = {
    name: name,
    value: value,
    timestamp: Js.Date.now(),
    tags: tags,
  }
  globalMetrics.metrics = Array.concat(globalMetrics.metrics, [m])
}

// DD-M02: Event bus - subscribe
let subscribe = (eventType: eventType, handler: eventHandler): unit => {
  let key = eventTypeToString(eventType)
  let existing = switch Js.Dict.get(globalEventBus.handlers, key) {
  | Some(handlers) => handlers
  | None => []
  }
  Js.Dict.set(globalEventBus.handlers, key, Array.concat(existing, [handler]))
  log(~level=Debug, ~component="EventBus", ~message=`Subscribed handler to ${key}`)
}

// DD-M02: Event bus - publish
let publish = (event: event): unit => {
  globalEventBus.eventLog = Array.concat(globalEventBus.eventLog, [event])

  let key = eventTypeToString(event.eventType)
  switch Js.Dict.get(globalEventBus.handlers, key) {
  | Some(handlers) =>
    handlers->Array.forEach(handler => {
      try {
        handler(event)
      } catch {
      | e =>
        log(
          ~level=Error,
          ~component="EventBus",
          ~message=`Handler error for ${key}: ${Js.Exn.message(Obj.magic(e))->Option.getOr("unknown")}`
        )
      }
    })
  | None => ()
  }

  log(~level=Debug, ~component="EventBus", ~message=`Published event ${key} from ${componentIdToString(event.source)}`)
  recordMetric(~name="events_published", ~value=1.0, ~tags=Js.Dict.fromArray([("type", key)]))
}

// DD-M06: Component health checks
let checkComponentHealth = (componentId: componentId): componentHealth => {
  let now = Js.Date.now()

  // In real implementation, would make HTTP/gRPC calls
  let (status, latency) = switch componentId {
  | FormatrixDocs => (Healthy, Some(5.0))
  | ReconSillyAtion => (Healthy, Some(3.0))
  | Docubot => (Healthy, Some(10.0))
  | ArangoDB => (Healthy, Some(2.0))
  }

  let health: componentHealth = {
    componentId: componentId,
    status: status,
    lastCheck: now,
    latencyMs: latency,
    version: Some("0.1.0"),
  }

  Js.Dict.set(globalHealth, componentIdToString(componentId), health)

  // Publish health check event
  publish({
    id: generateId("evt"),
    eventType: HealthCheckCompleted,
    source: componentId,
    timestamp: now,
    payload: Js.Json.object_(Js.Dict.fromArray([
      ("status", Js.Json.string(statusToString(status))),
      ("latencyMs", switch latency {
      | Some(l) => Js.Json.number(l)
      | None => Js.Json.null
      }),
    ])),
    correlationId: None,
  })

  health
}

// DD-M06: Check all components
let checkAllHealth = (): array<componentHealth> => {
  [FormatrixDocs, ReconSillyAtion, Docubot, ArangoDB]
  ->Array.map(checkComponentHealth)
}

// DD-M04: Register pipeline
let registerPipeline = (pipeline: pipelineDefinition): unit => {
  Js.Dict.set(globalPipelines, pipeline.id, pipeline)
  log(~level=Info, ~component="PipelineRegistry", ~message=`Registered pipeline: ${pipeline.name}`)

  // Subscribe to triggers
  pipeline.triggers->Array.forEach(trigger => {
    subscribe(trigger, event => {
      if pipeline.enabled {
        let _ = executePipeline(pipeline.id, Some(event.id))
      }
    })
  })
}

// DD-M05: Execute pipeline
and executePipeline = (pipelineId: string, triggeredBy: option<string>): result<pipelineExecution, string> => {
  switch Js.Dict.get(globalPipelines, pipelineId) {
  | None => Error(`Pipeline ${pipelineId} not found`)
  | Some(pipeline) =>
    let executionId = generateId("exec")
    let now = Js.Date.now()

    let stepStatuses = Js.Dict.empty()
    pipeline.steps->Array.forEach(step => {
      Js.Dict.set(stepStatuses, step.id, Pending)
    })

    let execution: pipelineExecution = {
      id: executionId,
      pipelineId: pipelineId,
      startedAt: now,
      completedAt: None,
      status: "running",
      stepStatuses: stepStatuses,
      context: Js.Dict.empty(),
      triggeredBy: triggeredBy,
    }

    Js.Dict.set(globalExecutions, executionId, execution)

    publish({
      id: generateId("evt"),
      eventType: PipelineStarted,
      source: ReconSillyAtion,
      timestamp: now,
      payload: Js.Json.object_(Js.Dict.fromArray([
        ("pipelineId", Js.Json.string(pipelineId)),
        ("executionId", Js.Json.string(executionId)),
      ])),
      correlationId: triggeredBy,
    })

    log(~level=Info, ~component="PipelineExecutor", ~message=`Started pipeline ${pipeline.name} (${executionId})`)

    // Execute steps in order (simplified - real impl would handle dependencies)
    let _ = executeSteps(execution, pipeline.steps)

    Ok(execution)
  }
}

// Execute pipeline steps
and executeSteps = (execution: pipelineExecution, steps: array<pipelineStep>): unit => {
  steps->Array.forEach(step => {
    let stepStart = Js.Date.now()
    Js.Dict.set(execution.stepStatuses, step.id, Running)

    // Simulate step execution
    let result = executeStep(step, execution.context)

    let stepEnd = Js.Date.now()
    let duration = stepEnd -. stepStart

    switch result {
    | Ok(_) =>
      Js.Dict.set(execution.stepStatuses, step.id, Completed({duration: duration}))
      publish({
        id: generateId("evt"),
        eventType: PipelineStepCompleted,
        source: ReconSillyAtion,
        timestamp: stepEnd,
        payload: Js.Json.object_(Js.Dict.fromArray([
          ("stepId", Js.Json.string(step.id)),
          ("status", Js.Json.string("completed")),
          ("duration", Js.Json.number(duration)),
        ])),
        correlationId: Some(execution.id),
      })
    | Error(e) =>
      Js.Dict.set(execution.stepStatuses, step.id, Failed({error: e, duration: duration}))
      if !step.continueOnError {
        // Would break here in real impl
        ()
      }
    }
  })

  // Mark execution complete
  let updated = {
    ...execution,
    completedAt: Some(Js.Date.now()),
    status: "completed",
  }
  Js.Dict.set(globalExecutions, execution.id, updated)

  publish({
    id: generateId("evt"),
    eventType: PipelineCompleted,
    source: ReconSillyAtion,
    timestamp: Js.Date.now(),
    payload: Js.Json.object_(Js.Dict.fromArray([
      ("executionId", Js.Json.string(execution.id)),
      ("status", Js.Json.string("completed")),
    ])),
    correlationId: Some(execution.id),
  })

  log(~level=Info, ~component="PipelineExecutor", ~message=`Completed pipeline execution ${execution.id}`)
}

// Execute single step
and executeStep = (step: pipelineStep, context: Js.Dict.t<Js.Json.t>): result<unit, string> => {
  log(~level=Debug, ~component="StepExecutor", ~message=`Executing step: ${step.name}`)

  switch step.stepType {
  | Scan({repoPath}) =>
    log(~level=Info, ~component="StepExecutor", ~message=`Scanning ${repoPath}`)
    Ok()
  | Reconcile({bundleId}) =>
    log(~level=Info, ~component="StepExecutor", ~message=`Reconciling bundle ${bundleId}`)
    Ok()
  | Enforce({packSpec}) =>
    log(~level=Info, ~component="StepExecutor", ~message=`Enforcing pack spec ${packSpec}`)
    Ok()
  | Ship({destination}) =>
    log(~level=Info, ~component="StepExecutor", ~message=`Shipping to ${destination}`)
    Ok()
  | Generate({docType, format}) =>
    log(~level=Info, ~component="StepExecutor", ~message=`Generating ${docType} in ${format}`)
    Ok()
  | Approve({generationId}) =>
    log(~level=Info, ~component="StepExecutor", ~message=`Awaiting approval for ${generationId}`)
    Ok()
  | Notify({channel, message}) =>
    log(~level=Info, ~component="StepExecutor", ~message=`Notifying ${channel}: ${message}`)
    Ok()
  | Custom({action, params: _}) =>
    log(~level=Info, ~component="StepExecutor", ~message=`Custom action: ${action}`)
    Ok()
  }
}

// DD-M03: Schedule task
let scheduleTask = (task: scheduledTask): unit => {
  globalScheduler.tasks = Array.concat(globalScheduler.tasks, [task])
  log(~level=Info, ~component="Scheduler", ~message=`Scheduled task: ${task.name}`)
}

// DD-M03: Calculate next run time
let calculateNextRun = (interval: scheduleInterval, lastRun: float): float => {
  switch interval {
  | Seconds(s) => lastRun +. Float.fromInt(s) *. 1000.0
  | Minutes(m) => lastRun +. Float.fromInt(m) *. 60000.0
  | Hours(h) => lastRun +. Float.fromInt(h) *. 3600000.0
  | Daily(_) => lastRun +. 86400000.0
  | Weekly(_) => lastRun +. 604800000.0
  | Cron(_) => lastRun +. 60000.0 // Simplified
  }
}

// DD-M03: Start scheduler
let startScheduler = (): unit => {
  globalScheduler.running = true
  log(~level=Info, ~component="Scheduler", ~message="Scheduler started")
  // In real impl, would start a timer/interval
}

// DD-M03: Stop scheduler
let stopScheduler = (): unit => {
  globalScheduler.running = false
  log(~level=Info, ~component="Scheduler", ~message="Scheduler stopped")
}

// DD-M09: Handle error
let handleError = (error: orchestratorError): unit => {
  log(
    ~level=Error,
    ~component=componentIdToString(error.component),
    ~message=error.message,
    ~context=Some(Js.Dict.fromArray([
      ("errorId", error.id),
      ("severity", severityToString(error.severity)),
    ]))
  )

  recordMetric(
    ~name="errors",
    ~value=1.0,
    ~tags=Js.Dict.fromArray([
      ("component", componentIdToString(error.component)),
      ("severity", severityToString(error.severity)),
    ])
  )

  // Attempt recovery for recoverable errors
  switch error.severity {
  | Recoverable =>
    log(~level=Info, ~component="ErrorHandler", ~message=`Attempting recovery for ${error.id}`)
    // Would implement recovery logic here
    ()
  | Critical =>
    log(~level=Warn, ~component="ErrorHandler", ~message=`Critical error ${error.id} - manual intervention may be required`)
    ()
  | Fatal =>
    log(~level=Error, ~component="ErrorHandler", ~message=`Fatal error ${error.id} - stopping affected component`)
    ()
  }
}

// DD-M10: CLI interface types
type cliCommand =
  | Status
  | Health
  | ListPipelines
  | RunPipeline({pipelineId: string})
  | ListTasks
  | EnableTask({taskId: string})
  | DisableTask({taskId: string})
  | Logs({component: option<string>, level: option<logLevel>, limit: int})
  | Metrics({name: option<string>, limit: int})
  | Config
  | Version

// DD-M10: Execute CLI command
let executeCommand = (cmd: cliCommand): string => {
  switch cmd {
  | Status =>
    let health = checkAllHealth()
    let healthy = health->Array.filter(h => h.status == Healthy)->Array.length
    let total = Array.length(health)
    `Docudactyl Status: ${healthy->Int.toString}/${total->Int.toString} components healthy`

  | Health =>
    let health = checkAllHealth()
    health
    ->Array.map(h => `${componentIdToString(h.componentId)}: ${statusToString(h.status)}`)
    ->Array.join("\n")

  | ListPipelines =>
    let keys = Js.Dict.keys(globalPipelines)
    if Array.length(keys) == 0 {
      "No pipelines registered"
    } else {
      keys
      ->Array.map(k => {
        switch Js.Dict.get(globalPipelines, k) {
        | Some(p) => `${p.id}: ${p.name} (${p.enabled ? "enabled" : "disabled"})`
        | None => k
        }
      })
      ->Array.join("\n")
    }

  | RunPipeline({pipelineId}) =>
    switch executePipeline(pipelineId, None) {
    | Ok(exec) => `Started execution ${exec.id}`
    | Error(e) => `Error: ${e}`
    }

  | ListTasks =>
    if Array.length(globalScheduler.tasks) == 0 {
      "No tasks scheduled"
    } else {
      globalScheduler.tasks
      ->Array.map(t => `${t.id}: ${t.name} (${t.enabled ? "enabled" : "disabled"})`)
      ->Array.join("\n")
    }

  | EnableTask({taskId}) =>
    globalScheduler.tasks = globalScheduler.tasks->Array.map(t =>
      if t.id == taskId {
        {...t, enabled: true}
      } else {
        t
      }
    )
    `Task ${taskId} enabled`

  | DisableTask({taskId}) =>
    globalScheduler.tasks = globalScheduler.tasks->Array.map(t =>
      if t.id == taskId {
        {...t, enabled: false}
      } else {
        t
      }
    )
    `Task ${taskId} disabled`

  | Logs({component, level, limit}) =>
    let filtered = globalMetrics.logs
    ->Array.filter(l => {
      let componentMatch = switch component {
      | Some(c) => l.component == c
      | None => true
      }
      let levelMatch = switch level {
      | Some(lvl) => l.level == lvl
      | None => true
      }
      componentMatch && levelMatch
    })
    ->Array.slice(~start=0, ~end=limit)

    filtered
    ->Array.map(l => `[${logLevelToString(l.level)}] [${l.component}] ${l.message}`)
    ->Array.join("\n")

  | Metrics({name, limit}) =>
    let filtered = globalMetrics.metrics
    ->Array.filter(m => {
      switch name {
      | Some(n) => m.name == n
      | None => true
      }
    })
    ->Array.slice(~start=0, ~end=limit)

    filtered
    ->Array.map(m => `${m.name}: ${m.value->Float.toString}`)
    ->Array.join("\n")

  | Config =>
    `ArangoDB: ${globalConfig.arangoEndpoint}
Database: ${globalConfig.arangoDatabase}
Health Check Interval: ${globalConfig.healthCheckInterval->Int.toString}s
Max Concurrent Pipelines: ${globalConfig.maxConcurrentPipelines->Int.toString}`

  | Version =>
    "Docudactyl v0.1.0"
  }
}

// Helper functions for type conversion
and eventTypeToString = (et: eventType): string => {
  switch et {
  | DocumentCreated => "document.created"
  | DocumentModified => "document.modified"
  | DocumentDeleted => "document.deleted"
  | ReconciliationStarted => "reconciliation.started"
  | ReconciliationCompleted => "reconciliation.completed"
  | EnforcementViolation => "enforcement.violation"
  | PackShipped => "pack.shipped"
  | GenerationRequested => "generation.requested"
  | GenerationCompleted => "generation.completed"
  | ApprovalRequired => "approval.required"
  | ApprovalGranted => "approval.granted"
  | ApprovalRejected => "approval.rejected"
  | HealthCheckCompleted => "health.check.completed"
  | PipelineStarted => "pipeline.started"
  | PipelineStepCompleted => "pipeline.step.completed"
  | PipelineFailed => "pipeline.failed"
  | PipelineCompleted => "pipeline.completed"
  }
}

and componentIdToString = (c: componentId): string => {
  switch c {
  | FormatrixDocs => "formatrix-docs"
  | ReconSillyAtion => "recon-silly-ation"
  | Docubot => "docubot"
  | ArangoDB => "arangodb"
  }
}

and statusToString = (s: componentStatus): string => {
  switch s {
  | Healthy => "healthy"
  | Degraded({reason}) => `degraded: ${reason}`
  | Unhealthy({reason}) => `unhealthy: ${reason}`
  | Unknown => "unknown"
  }
}

and severityToString = (s: errorSeverity): string => {
  switch s {
  | Recoverable => "recoverable"
  | Critical => "critical"
  | Fatal => "fatal"
  }
}

and logLevelToString = (l: logLevel): string => {
  switch l {
  | Debug => "DEBUG"
  | Info => "INFO"
  | Warn => "WARN"
  | Error => "ERROR"
  }
}

// Pre-defined pipelines
let standardReconciliationPipeline: pipelineDefinition = {
  id: "standard-reconciliation",
  name: "Standard Reconciliation Pipeline",
  description: "Full 7-stage reconciliation pipeline for document bundles",
  steps: [
    {
      id: "scan",
      name: "Scan Repository",
      stepType: Scan({repoPath: "${repoPath}"}),
      dependsOn: [],
      timeout: 300,
      retries: 2,
      continueOnError: false,
    },
    {
      id: "reconcile",
      name: "Reconcile Documents",
      stepType: Reconcile({bundleId: "${bundleId}"}),
      dependsOn: ["scan"],
      timeout: 600,
      retries: 1,
      continueOnError: false,
    },
    {
      id: "enforce",
      name: "Enforce Pack Spec",
      stepType: Enforce({packSpec: "rsr-standard"}),
      dependsOn: ["reconcile"],
      timeout: 300,
      retries: 1,
      continueOnError: true,
    },
    {
      id: "notify",
      name: "Notify Completion",
      stepType: Notify({channel: "default", message: "Reconciliation complete"}),
      dependsOn: ["enforce"],
      timeout: 60,
      retries: 3,
      continueOnError: true,
    },
  ],
  triggers: [DocumentCreated, DocumentModified],
  enabled: true,
}

let docGenerationPipeline: pipelineDefinition = {
  id: "doc-generation",
  name: "Document Generation Pipeline",
  description: "Generate missing documentation with LLM assistance",
  steps: [
    {
      id: "generate",
      name: "Generate Document",
      stepType: Generate({docType: "${docType}", format: "${format}"}),
      dependsOn: [],
      timeout: 120,
      retries: 2,
      continueOnError: false,
    },
    {
      id: "approve",
      name: "Await Approval",
      stepType: Approve({generationId: "${generationId}"}),
      dependsOn: ["generate"],
      timeout: 86400, // 24 hours
      retries: 0,
      continueOnError: false,
    },
    {
      id: "ship",
      name: "Ship Document",
      stepType: Ship({destination: "${destination}"}),
      dependsOn: ["approve"],
      timeout: 300,
      retries: 2,
      continueOnError: false,
    },
  ],
  triggers: [GenerationRequested],
  enabled: true,
}

// Initialize with default pipelines
let init = (): unit => {
  registerPipeline(standardReconciliationPipeline)
  registerPipeline(docGenerationPipeline)

  // Schedule health checks
  scheduleTask({
    id: "health-check",
    name: "Component Health Check",
    interval: Seconds(globalConfig.healthCheckInterval),
    pipelineId: "",
    enabled: true,
    lastRun: None,
    nextRun: Some(Js.Date.now() +. Float.fromInt(globalConfig.healthCheckInterval) *. 1000.0),
    runCount: 0,
    failCount: 0,
  })

  log(~level=Info, ~component="Docudactyl", ~message="Initialized with default configuration")
}
