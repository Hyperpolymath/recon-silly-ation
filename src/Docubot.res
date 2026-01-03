// SPDX-License-Identifier: MIT
// Docubot - LLM-powered document generation with guardrails
// DB-M01 through DB-M10: MUST requirements

// =============================================================================
// DB-M01: Module structure with ReScript types
// =============================================================================

type documentType =
  | Readme
  | Security
  | Contributing
  | CodeOfConduct
  | Changelog
  | License
  | Funding
  | Citation
  | Authors
  | Support

type format =
  | Markdown
  | AsciiDoc
  | OrgMode
  | PlainText

// DB-M02: LLM provider abstraction
type llmProvider =
  | Anthropic({apiKey: string, model: string})
  | OpenAI({apiKey: string, model: string})
  | Local({endpoint: string, model: string})

type providerConfig = {
  provider: llmProvider,
  maxTokens: int,
  temperature: float,
}

// DB-M06: Rate limiting per provider
type rateLimitConfig = {
  requestsPerMinute: int,
  requestsPerHour: int,
  tokensPerMinute: int,
  tokensPerHour: int,
}

type rateLimitState = {
  mutable minuteRequests: int,
  mutable hourRequests: int,
  mutable minuteTokens: int,
  mutable hourTokens: int,
  mutable lastMinuteReset: float,
  mutable lastHourReset: float,
}

// DB-M07: Cost tracking and budgets
type costTracking = {
  mutable totalCost: float,
  mutable dailyCost: float,
  mutable monthlyCost: float,
  dailyBudget: float,
  monthlyBudget: float,
  mutable lastDayReset: float,
  mutable lastMonthReset: float,
}

// DB-M05: Audit trail for all generations
type auditEntry = {
  id: string,
  timestamp: float,
  provider: string,
  model: string,
  documentType: documentType,
  inputTokens: int,
  outputTokens: int,
  cost: float,
  success: bool,
  errorMessage: option<string>,
  approvalStatus: string, // "pending", "approved", "rejected"
  approvedBy: option<string>,
  approvedAt: option<float>,
}

type auditLog = {
  mutable entries: array<auditEntry>,
}

// DB-M09: Context extraction from repo
type repoContext = {
  name: string,
  description: option<string>,
  language: option<string>,
  license: option<string>,
  topics: array<string>,
  existingDocs: array<string>,
  dependencies: array<string>,
  readme: option<string>,
}

// DB-M08: Template system for doc types
type docTemplate = {
  documentType: documentType,
  format: format,
  systemPrompt: string,
  userPromptTemplate: string,
  requiredSections: array<string>,
  maxLength: int,
}

// DB-M04: MANDATORY approval gate
type approvalGate = {
  requiresApproval: bool, // MUST always be true
  autoApproveThreshold: option<float>, // MUST be None for safety
}

// DB-M03: Document generation function return type
type generationResult = {
  content: string,
  documentType: documentType,
  format: format,
  // DB-M04: MANDATORY - this MUST always be true
  requiresApproval: bool,
  confidence: float,
  generatedAt: float,
  auditId: string,
  estimatedCost: float,
  warnings: array<string>,
}

// DB-M10: Output validation before return
type validationResult = {
  isValid: bool,
  errors: array<string>,
  warnings: array<string>,
  score: float,
}

// =============================================================================
// Implementation
// =============================================================================

// Global state (in real impl, would be in a service)
let globalAuditLog: auditLog = {entries: []}
let globalCostTracking: costTracking = {
  totalCost: 0.0,
  dailyCost: 0.0,
  monthlyCost: 0.0,
  dailyBudget: 10.0,  // $10/day default
  monthlyBudget: 100.0, // $100/month default
  lastDayReset: 0.0,
  lastMonthReset: 0.0,
}

let globalRateLimits: Js.Dict.t<rateLimitState> = Js.Dict.empty()

// DB-M08: Pre-defined templates
let templates: array<docTemplate> = [
  {
    documentType: Readme,
    format: Markdown,
    systemPrompt: "You are a technical writer creating README documentation. Be concise, accurate, and helpful.",
    userPromptTemplate: "Create a README.md for a project with the following context:\n\nName: {{name}}\nDescription: {{description}}\nLanguage: {{language}}\nLicense: {{license}}\n\nInclude sections for: Installation, Usage, Contributing, License.",
    requiredSections: ["Installation", "Usage", "Contributing", "License"],
    maxLength: 5000,
  },
  {
    documentType: Security,
    format: Markdown,
    systemPrompt: "You are a security engineer writing security documentation. Be precise about vulnerability reporting procedures.",
    userPromptTemplate: "Create a SECURITY.md for a project:\n\nName: {{name}}\nDescription: {{description}}\n\nInclude: Supported versions, Reporting a vulnerability, Disclosure policy.",
    requiredSections: ["Supported Versions", "Reporting a Vulnerability", "Disclosure Policy"],
    maxLength: 2000,
  },
  {
    documentType: Contributing,
    format: Markdown,
    systemPrompt: "You are a community manager writing contribution guidelines. Be welcoming and clear about the process.",
    userPromptTemplate: "Create CONTRIBUTING.md for:\n\nName: {{name}}\nLanguage: {{language}}\n\nInclude: Code of conduct reference, How to contribute, Pull request process, Code style.",
    requiredSections: ["Code of Conduct", "How to Contribute", "Pull Request Process"],
    maxLength: 3000,
  },
  {
    documentType: CodeOfConduct,
    format: Markdown,
    systemPrompt: "You are creating a code of conduct based on the Contributor Covenant.",
    userPromptTemplate: "Create a CODE_OF_CONDUCT.md based on Contributor Covenant 2.1 for project: {{name}}",
    requiredSections: ["Our Pledge", "Our Standards", "Enforcement"],
    maxLength: 4000,
  },
  {
    documentType: Changelog,
    format: Markdown,
    systemPrompt: "You are maintaining a changelog following Keep a Changelog format.",
    userPromptTemplate: "Create a CHANGELOG.md skeleton for project: {{name}}\n\nCurrent version: {{version}}\n\nUse Keep a Changelog format.",
    requiredSections: ["Unreleased", "Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"],
    maxLength: 2000,
  },
]

// Get template for document type
let getTemplate = (docType: documentType, fmt: format): option<docTemplate> => {
  templates->Array.find(t => t.documentType == docType && t.format == fmt)
}

// Generate unique ID
let generateId = (): string => {
  let now = Js.Date.now()
  let rand = Js.Math.random() *. 1000000.0
  `db-${now->Float.toString}-${rand->Float.toInt->Int.toString}`
}

// DB-M06: Check rate limits
let checkRateLimit = (providerName: string, config: rateLimitConfig): result<unit, string> => {
  let now = Js.Date.now()

  let state = switch Js.Dict.get(globalRateLimits, providerName) {
  | Some(s) => s
  | None => {
      let newState = {
        minuteRequests: 0,
        hourRequests: 0,
        minuteTokens: 0,
        hourTokens: 0,
        lastMinuteReset: now,
        lastHourReset: now,
      }
      Js.Dict.set(globalRateLimits, providerName, newState)
      newState
    }
  }

  // Reset counters if time has passed
  if now -. state.lastMinuteReset > 60000.0 {
    state.minuteRequests = 0
    state.minuteTokens = 0
    state.lastMinuteReset = now
  }

  if now -. state.lastHourReset > 3600000.0 {
    state.hourRequests = 0
    state.hourTokens = 0
    state.lastHourReset = now
  }

  // Check limits
  if state.minuteRequests >= config.requestsPerMinute {
    Error("Rate limit exceeded: too many requests per minute")
  } else if state.hourRequests >= config.requestsPerHour {
    Error("Rate limit exceeded: too many requests per hour")
  } else {
    state.minuteRequests = state.minuteRequests + 1
    state.hourRequests = state.hourRequests + 1
    Ok()
  }
}

// DB-M07: Check budget
let checkBudget = (estimatedCost: float): result<unit, string> => {
  let now = Js.Date.now()

  // Reset daily if needed
  if now -. globalCostTracking.lastDayReset > 86400000.0 {
    globalCostTracking.dailyCost = 0.0
    globalCostTracking.lastDayReset = now
  }

  // Reset monthly if needed (approximate 30 days)
  if now -. globalCostTracking.lastMonthReset > 2592000000.0 {
    globalCostTracking.monthlyCost = 0.0
    globalCostTracking.lastMonthReset = now
  }

  if globalCostTracking.dailyCost +. estimatedCost > globalCostTracking.dailyBudget {
    Error("Daily budget exceeded")
  } else if globalCostTracking.monthlyCost +. estimatedCost > globalCostTracking.monthlyBudget {
    Error("Monthly budget exceeded")
  } else {
    Ok()
  }
}

// DB-M07: Record cost
let recordCost = (cost: float): unit => {
  globalCostTracking.totalCost = globalCostTracking.totalCost +. cost
  globalCostTracking.dailyCost = globalCostTracking.dailyCost +. cost
  globalCostTracking.monthlyCost = globalCostTracking.monthlyCost +. cost
}

// DB-M05: Add audit entry
let addAuditEntry = (entry: auditEntry): unit => {
  globalAuditLog.entries = Array.concat(globalAuditLog.entries, [entry])
}

// DB-M10: Validate generated content
let validateOutput = (content: string, template: docTemplate): validationResult => {
  let errors = []
  let warnings = []

  // Check length
  if String.length(content) > template.maxLength {
    Array.push(warnings, `Content exceeds recommended length of ${template.maxLength->Int.toString} characters`)
  }

  if String.length(content) < 100 {
    Array.push(errors, "Content too short - likely generation failure")
  }

  // Check required sections
  template.requiredSections->Array.forEach(section => {
    if !String.includes(content, section) {
      Array.push(warnings, `Missing required section: ${section}`)
    }
  })

  // Check for placeholder text
  if String.includes(content, "{{") || String.includes(content, "}}") {
    Array.push(errors, "Content contains unresolved template placeholders")
  }

  // Check for obvious errors
  if String.includes(content, "I cannot") || String.includes(content, "I'm sorry") {
    Array.push(errors, "Content appears to be an error response from LLM")
  }

  let errorCount = Array.length(errors)
  let warningCount = Array.length(warnings)
  let score = 1.0 -. (Float.fromInt(errorCount) *. 0.3) -. (Float.fromInt(warningCount) *. 0.1)

  {
    isValid: errorCount == 0,
    errors: errors,
    warnings: warnings,
    score: Js.Math.max_float(0.0, score),
  }
}

// DB-M09: Extract context from repository
let extractRepoContext = (repoPath: string): repoContext => {
  // In real implementation, this would read from filesystem
  // For now, return a placeholder
  {
    name: "unknown",
    description: None,
    language: None,
    license: None,
    topics: [],
    existingDocs: [],
    dependencies: [],
    readme: None,
  }
}

// Get provider name for rate limiting
let getProviderName = (provider: llmProvider): string => {
  switch provider {
  | Anthropic(_) => "anthropic"
  | OpenAI(_) => "openai"
  | Local({endpoint}) => `local-${endpoint}`
  }
}

// Estimate cost based on tokens
let estimateCost = (provider: llmProvider, inputTokens: int, outputTokens: int): float => {
  switch provider {
  | Anthropic({model}) =>
    // Claude pricing (approximate)
    if String.includes(model, "opus") {
      Float.fromInt(inputTokens) *. 0.000015 +. Float.fromInt(outputTokens) *. 0.000075
    } else if String.includes(model, "sonnet") {
      Float.fromInt(inputTokens) *. 0.000003 +. Float.fromInt(outputTokens) *. 0.000015
    } else {
      Float.fromInt(inputTokens) *. 0.00000025 +. Float.fromInt(outputTokens) *. 0.00000125
    }
  | OpenAI({model}) =>
    // GPT pricing (approximate)
    if String.includes(model, "gpt-4") {
      Float.fromInt(inputTokens) *. 0.00003 +. Float.fromInt(outputTokens) *. 0.00006
    } else {
      Float.fromInt(inputTokens) *. 0.0000005 +. Float.fromInt(outputTokens) *. 0.0000015
    }
  | Local(_) => 0.0 // Local models are free
  }
}

// DB-M03: Main document generation function
// DB-M04: MANDATORY approval gate - requiresApproval is ALWAYS true
let generateDocument = (
  ~docType: documentType,
  ~format: format,
  ~context: repoContext,
  ~providerConfig: providerConfig,
  ~rateLimitConfig: rateLimitConfig,
): result<generationResult, string> => {
  let auditId = generateId()
  let now = Js.Date.now()
  let providerName = getProviderName(providerConfig.provider)

  // Check rate limits (DB-M06)
  switch checkRateLimit(providerName, rateLimitConfig) {
  | Error(e) => Error(e)
  | Ok() =>
    // Get template (DB-M08)
    switch getTemplate(docType, format) {
    | None => Error(`No template found for ${docType->documentTypeToString} in ${format->formatToString}`)
    | Some(template) =>
      // Estimate cost (DB-M07)
      let estimatedInputTokens = 500 // Approximate
      let estimatedOutputTokens = providerConfig.maxTokens
      let estimatedCost = estimateCost(
        providerConfig.provider,
        estimatedInputTokens,
        estimatedOutputTokens
      )

      // Check budget (DB-M07)
      switch checkBudget(estimatedCost) {
      | Error(e) => Error(e)
      | Ok() =>
        // In real implementation, this would call the LLM API
        // For now, generate a placeholder
        let content = generatePlaceholder(docType, context, template)

        // Validate output (DB-M10)
        let validation = validateOutput(content, template)

        // Record cost (DB-M07)
        recordCost(estimatedCost)

        // Create audit entry (DB-M05)
        let auditEntry: auditEntry = {
          id: auditId,
          timestamp: now,
          provider: providerName,
          model: switch providerConfig.provider {
          | Anthropic({model}) => model
          | OpenAI({model}) => model
          | Local({model}) => model
          },
          documentType: docType,
          inputTokens: estimatedInputTokens,
          outputTokens: String.length(content) / 4, // Rough estimate
          cost: estimatedCost,
          success: validation.isValid,
          errorMessage: if validation.isValid { None } else { Some(Array.join(validation.errors, "; ")) },
          approvalStatus: "pending",
          approvedBy: None,
          approvedAt: None,
        }
        addAuditEntry(auditEntry)

        Ok({
          content: content,
          documentType: docType,
          format: format,
          // DB-M04: MANDATORY - this MUST ALWAYS be true, no exceptions
          requiresApproval: true,
          confidence: validation.score,
          generatedAt: now,
          auditId: auditId,
          estimatedCost: estimatedCost,
          warnings: validation.warnings,
        })
      }
    }
  }
}

// Generate placeholder content (for testing without actual LLM)
and generatePlaceholder = (docType: documentType, context: repoContext, template: docTemplate): string => {
  switch docType {
  | Readme => `# ${context.name}

${context.description->Option.getOr("A project description goes here.")}

## Installation

\`\`\`bash
# Installation instructions
\`\`\`

## Usage

Usage instructions go here.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

${context.license->Option.getOr("MIT")} License
`
  | Security => `# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |

## Reporting a Vulnerability

Please report security vulnerabilities to security@example.com.

## Disclosure Policy

We follow responsible disclosure practices.
`
  | Contributing => `# Contributing to ${context.name}

## Code of Conduct

Please read our [Code of Conduct](CODE_OF_CONDUCT.md).

## How to Contribute

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Pull Request Process

1. Ensure tests pass
2. Update documentation
3. Request review
`
  | _ => `# ${documentTypeToString(docType)}

Content for ${documentTypeToString(docType)} goes here.
`
  }
}

// Helper functions for type conversion
and documentTypeToString = (dt: documentType): string => {
  switch dt {
  | Readme => "README"
  | Security => "SECURITY"
  | Contributing => "CONTRIBUTING"
  | CodeOfConduct => "CODE_OF_CONDUCT"
  | Changelog => "CHANGELOG"
  | License => "LICENSE"
  | Funding => "FUNDING"
  | Citation => "CITATION"
  | Authors => "AUTHORS"
  | Support => "SUPPORT"
  }
}

and formatToString = (f: format): string => {
  switch f {
  | Markdown => "md"
  | AsciiDoc => "adoc"
  | OrgMode => "org"
  | PlainText => "txt"
  }
}

// DB-M04: Approval functions
let approveGeneration = (auditId: string, approvedBy: string): result<unit, string> => {
  let now = Js.Date.now()
  let found = ref(false)

  globalAuditLog.entries = globalAuditLog.entries->Array.map(entry => {
    if entry.id == auditId {
      found := true
      {
        ...entry,
        approvalStatus: "approved",
        approvedBy: Some(approvedBy),
        approvedAt: Some(now),
      }
    } else {
      entry
    }
  })

  if found.contents {
    Ok()
  } else {
    Error(`Audit entry ${auditId} not found`)
  }
}

let rejectGeneration = (auditId: string, rejectedBy: string): result<unit, string> => {
  let now = Js.Date.now()
  let found = ref(false)

  globalAuditLog.entries = globalAuditLog.entries->Array.map(entry => {
    if entry.id == auditId {
      found := true
      {
        ...entry,
        approvalStatus: "rejected",
        approvedBy: Some(rejectedBy),
        approvedAt: Some(now),
      }
    } else {
      entry
    }
  })

  if found.contents {
    Ok()
  } else {
    Error(`Audit entry ${auditId} not found`)
  }
}

// Get pending approvals
let getPendingApprovals = (): array<auditEntry> => {
  globalAuditLog.entries->Array.filter(e => e.approvalStatus == "pending")
}

// Get cost summary
let getCostSummary = (): {
  "total": float,
  "daily": float,
  "monthly": float,
  "dailyBudget": float,
  "monthlyBudget": float,
  "dailyRemaining": float,
  "monthlyRemaining": float,
} => {
  {
    "total": globalCostTracking.totalCost,
    "daily": globalCostTracking.dailyCost,
    "monthly": globalCostTracking.monthlyCost,
    "dailyBudget": globalCostTracking.dailyBudget,
    "monthlyBudget": globalCostTracking.monthlyBudget,
    "dailyRemaining": globalCostTracking.dailyBudget -. globalCostTracking.dailyCost,
    "monthlyRemaining": globalCostTracking.monthlyBudget -. globalCostTracking.monthlyCost,
  }
}

// Set budgets
let setBudgets = (~daily: float, ~monthly: float): unit => {
  globalCostTracking.dailyBudget = daily
  globalCostTracking.monthlyBudget = monthly
}
