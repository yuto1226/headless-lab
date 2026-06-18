# Agent Script Rules & Guide

This document provides comprehensive rules and guidance for building valid Agent Script configurations (`.agent` files).

This guide is based on the Trailhead Apps Agent Script Recipes rule set and adds project guidance from Salesforce Agent Script documentation, the Salesforce Developers Japan Agent Script fundamentals article, and the Qiita Agent Script writing guide. Use it as the primary rule file whenever creating, reviewing, or changing Agent Script in this repository.

---

## Source Guidance & Design Philosophy

Agent Script is the language for building agents in Agentforce Builder. It combines natural language instructions for conversational reasoning with programmatic expressions for business rules, variable management, action sequencing, and subagent transitions.

Design Agent Script as a hybrid of deterministic execution and LLM reasoning:

- Use deterministic logic for business rules, required workflow steps, action sequencing, guardrails, eligibility checks, and transitions that must be predictable.
- Use LLM reasoning for interpretation, natural language response generation, slot filling, and cases where user intent or phrasing must be understood flexibly.
- Keep reasoning instructions short and specific. Add instructions incrementally only after previewing and testing real conversation paths.
- Prefer explicit `@` references to subagents, actions, and variables in reasoning instructions so the reasoning engine has clear context.
- Treat names and descriptions as part of the runtime design. Clear, distinct, plain-language names help the agent choose the right subagent, action, or variable.

The Salesforce Developers Japan fundamentals article and the Qiita Agent Script writing guide reinforce these operational concerns:

- Understand Agent Script as a readable, declarative, property-based language where indentation defines structure.
- Separate deterministic logic from prompt text: `->` procedural logic runs predictably, while `|` text is assembled into the prompt sent to the LLM.
- Treat variables as explicit state management across turns. Use defaults for mutable variables and `source` without defaults for linked variables.
- Use `@` references only for resources defined in Agent Script blocks or built-in utilities; do not assume Salesforce merge-field syntax such as `@Account.Name`.
- Use `{! }` template expressions so the LLM receives concrete runtime values, not variable names.
- Use `...` only for action input slot filling, never as a variable default.
- Remember that every user message starts at `start_agent`, even mid-conversation. The router must use current context and variables to select the right subagent.
- Distinguish action definitions from orchestration: subagent-level `actions` define callable capabilities; `reasoning.instructions` and `reasoning.actions` decide how they are executed or exposed.
- Use deterministic `run` for required data fetches, validations, and mandatory logic. Use `reasoning.actions` tools for user-driven or optional actions where the LLM should decide.
- Treat `@utils.transition to` as one-way and direct `@subagent.<name>` references as delegation that can return to the caller.

---

## Discovery Questions

Before writing Agent Script, work through these questions to understand requirements:

### 1. Agent Identity & Purpose

- **What is the agent's name?** (letters, numbers, underscores only; no spaces; max 80 chars)
- **What is the agent's primary purpose?** (This becomes the description)
- **What personality should the agent have?** (Friendly, professional, formal, casual?)
- **What should the welcome message say?**
- **What should the error message say?**

### 2. Subagents & Conversation Flow

- **What distinct conversation areas (subagents) does this agent need?**
- **What is the entry point subagent?** (The first subagent users interact with)
- **How should the agent transition between subagents?**
- **Are there any subagents that need to delegate to other subagents and return?**
- **Which transitions must be deterministic, and which can be left to LLM tool selection?**
- **Which subagents are specialists that should return control to the caller, and which are permanent handoffs?**

### 3. State Management

- **What information needs to be tracked across the conversation?**
    - User data (name, email, preferences)?
    - Process state (step completed, status)?
    - Collected inputs (selections, answers)?
- **What external context is needed?** (session ID, user record, etc.)
- **Which values must be stored in variables instead of relying on LLM memory?**
- **Which variables are mutable conversation state, linked Salesforce context, or read-only/system-provided values?**
- **Which variables drive `available when`, template expressions, required workflows, or transitions?**

### 4. Actions & External Systems

- **What external systems does the agent need to call?**
    - Salesforce Flows
    - Apex classes
    - Prompt templates
    - External APIs
- **For each action:**
    - What inputs does it need?
    - What outputs does it return?
    - When should it be available?
- **Which actions must run deterministically before the LLM responds?**
- **Which actions should be exposed as reasoning tools for the LLM to choose?**
- **What user confirmation, progress indicator, security, CRUD/FLS, and sharing constraints apply?**
- **For Flow actions, is the Flow active, bulk-safe where relevant, and designed with explicit inputs/outputs?**

### 5. Reasoning & Instructions

- **What should the agent do in each subagent?**
- **Are there conditions that change the instructions?**
- **Should any actions run automatically before/after reasoning?**
- **What validation, fallback, and escalation behavior is required when user input or action output is incomplete?**
- **How will the agent be tested across happy paths, edge cases, security contexts, and regression scenarios?**

---

## Block Ordering Rules

Top-level blocks MUST appear in this order:

```agentscript
# 1. CONFIG (required) - Agent metadata
config:
   developer_name: "DescriptiveName"
   ...

# 2. VARIABLES (optional) - State management
variables:
   ...

# 3. SYSTEM (required) - Global settings
system:
   messages:
      welcome: "..."
      error: "..."
   instructions: "..."

# 4. CONNECTIONS (optional) - Escalation routing
connections:
   ...

# 5. KNOWLEDGE (optional) - Knowledge base config
knowledge:
   ...

# 6. LANGUAGE (optional) - Locale settings
language:
   ...

# 7. START_AGENT (required) - Entry point
start_agent agent_router:
   description: "..."
   reasoning:
      actions:
         ...

# 8. SUBAGENTS (at least one required)
subagent my_topic:
   description: "..."
   actions:
      ...
   reasoning:
      ...
```

---

## Block Internal Ordering

### Within `start_agent` and `subagent` blocks:

1. `description` (required)
2. `system` (optional - for instruction overrides)
3. `actions` (optional - action definitions)
4. `reasoning` (required)
5. `after_reasoning` (optional)

### Within `reasoning` blocks:

1. `instructions` (required)
2. `actions` (optional)

---

## Required Elements

Every Agent Script MUST have:

- `config` block with `developer_name`
- `system` block with `messages.welcome`, `messages.error`, and `instructions`
- `start_agent` block with `description` and `reasoning.actions`
- At least one `subagent` block with `description` and `reasoning`

---

## Naming Rules

All names (developer_name, subagent names, variable names, action names):

- Can contain only letters, numbers, and underscores
- Must begin with a letter
- Cannot include spaces
- Cannot end with an underscore
- Cannot contain two consecutive underscores
- Maximum 80 characters

---

## Variable Rules

Variables are the primary way to make Agent Script context-aware and predictable. Do not rely on LLM conversation memory for values that affect business behavior.

- Store business state, collected user inputs, action outputs, eligibility flags, workflow progress, and handoff decisions in variables.
- Use variables in deterministic expressions for `if`/`else`, `available when`, action bindings, template expressions, and transition conditions.
- Use mutable variables for session state that the agent can change. Initialize every mutable variable with a safe default.
- Use linked variables only for read-only external context. Do not give linked variables default values.
- Use `@system_variables.user_input` only when the latest utterance must be passed directly into an action; otherwise rely on reasoning and explicit variables.
- Add descriptions to variables that the LLM must fill with `@utils.setVariables` or `with field=...`.
- Avoid storing sensitive data unless required. If sensitive outputs are not needed by the reasoning engine, set `filter_from_agent: True`.
- Keep variable names specific and distinct. For example, prefer `verified_customer_id`, `requested_order_number`, or `shipping_address_confirmed` over ambiguous names like `id`, `value`, or `status`.

---

## Indentation & Comments

- Use spaces (not tabs)
- Recommended: 3 spaces per level
- Maintain consistent indentation throughout
- Use `#` for comments (Python-style)

```agentscript
# This is a comment
config:
   developer_name: "My_Agent"  # Inline comment
```

---

## Block Reference

### Config Block

```agentscript
config:
   # Required
   developer_name: "DescriptiveName"           # Unique identifier (letters, numbers, underscores)

   # Optional with defaults
   agent_label: "DescriptiveName"               # Display name (defaults to normalized developer_name)
   description: "Agent description"       # What the agent does
   agent_type: "AgentforceServiceAgent"  # or "AgentforceEmployeeAgent"
   default_agent_user: "user@example.com" # Required for AgentforceServiceAgent
```

### Variables Block

```agentscript
variables:
   # MUTABLE variables - agent can read AND write (MUST have default value)
   my_string: mutable string = ""
      description: "Description for slot-filling"

   my_number: mutable number = 0

   my_bool: mutable boolean = False

   my_list: mutable list[string] = []

   my_object: mutable object = {}

   # LINKED variables - read-only from external context (MUST have source, NO default)
   session_id: linked string
      description: "The session ID"
      source: @session.sessionID
```

**Type Support Matrix:**

| Type        | Mutable | Linked | Actions |
| ----------- | ------- | ------ | ------- |
| `string`    | ✅      | ✅     | ✅      |
| `number`    | ✅      | ✅     | ✅      |
| `boolean`   | ✅      | ✅     | ✅      |
| `object`    | ✅      | ❌     | ✅      |
| `date`      | ✅      | ✅     | ✅      |
| `timestamp` | ✅      | ✅     | ✅      |
| `currency`  | ✅      | ✅     | ✅      |
| `id`        | ✅      | ✅     | ✅      |
| `list[T]`   | ✅      | ❌     | ✅      |
| `datetime`  | ❌      | ❌     | ✅      |
| `time`      | ❌      | ❌     | ✅      |
| `integer`   | ❌      | ❌     | ✅      |
| `long`      | ❌      | ❌     | ✅      |

**Boolean values MUST be capitalized:** `True` or `False` (never `true` or `false`)

### System Block

```agentscript
system:
   messages:
      welcome: "Welcome message shown when conversation starts"
      error: "Error message shown when something goes wrong"

   # Single-line or multi-line instructions
   instructions: "You are a helpful assistant."

   # OR multi-line with |
   instructions:|
      You are a helpful assistant.
      Always be polite and professional.
      Never share sensitive information.
```

### Subagent Block Structure

```agentscript
subagent my_topic:
   description: "What this subagent handles"

   # Optional: Override system instructions for this subagent
   system:
      instructions: "Subagent-specific system instructions"

   # Action definitions (what the subagent CAN call)
   actions:
      action_name:
         description: "What this action does"
         inputs:
            param1: string
               description: "Parameter description"
            param2: number
         outputs:
            result: string
         target: "flow://MyFlow"

   # Required: Reasoning configuration
   reasoning:
      instructions:->
         | Static instructions that always appear
         if @variables.some_condition:
            | Conditional instructions
         | More instructions with template: {!@variables.value}

      # Actions available to the LLM during reasoning
      actions:
         action_alias: @actions.action_name
            description: "Override description"
            available when @variables.condition == True
            with param1=...           # LLM slot-fills this
            with param2=@variables.x  # Bound to variable
            set @variables.y = @outputs.result

   # Optional: Runs after reasoning completes
   after_reasoning:
      if @variables.should_transition:
         transition to @subagent.next_topic
```

---

## Action Rules

Actions connect subagents to executable business capabilities such as Salesforce Flow, Apex, prompt templates, or external services.

- Define concrete business actions in the subagent-level `actions` block.
- Run actions deterministically from `reasoning.instructions` when the action must always run before the LLM responds.
- Expose actions in `reasoning.actions` when the LLM can decide whether the action is appropriate.
- Use `available when` to make tool availability deterministic instead of relying only on the LLM to decide when a tool is safe.
- Bind known inputs from variables and constants. Use `...` only for user-provided values that the LLM should extract from conversation.
- Capture action outputs into variables when later logic, transitions, or user messages depend on them.
- Add `require_user_confirmation: True` for actions that mutate data, send messages, submit transactions, or have external side effects unless the business process explicitly allows automatic execution.
- Use clear action descriptions. The LLM uses names and descriptions to decide which reasoning tools to call.
- Apply Salesforce security review expectations to every action: confirm the running user/security context, object access, field access, sharing behavior, and whether outputs should be visible to the agent or user.

### Flow Integration Policy

Use Flow when the agent is orchestrating declarative Salesforce process logic or existing Flow automation.

- Use `target: "flow://Flow_API_Name"` and match input/output parameter names and types exactly.
- Keep Flow actions small and purpose-specific. A subagent can sequence multiple actions; a single Flow should not hide unrelated business decisions.
- Prefer deterministic `run @actions.flow_action` when the Flow is required to fetch state, validate a condition, or perform a mandatory step before the LLM responds.
- Prefer reasoning tools for optional Flow actions where the LLM needs to decide based on user intent.
- Store important Flow outputs in variables immediately with `set @variables.x = @outputs.y`.
- Confirm the Flow is active and deployable in the target org. Validate that the Flow handles missing inputs and returns predictable outputs.
- Treat Flow as part of the Salesforce security boundary. Check user context, CRUD/FLS expectations, sharing, and data exposure.

### Target Formats

| Short                     | Long                      | Use Case         |
| ------------------------- | ------------------------- | ---------------- |
| `flow`                    | `flow`                    | Salesforce Flow  |
| `apex`                    | `apex`                    | Apex Class       |
| `prompt`                  | `generatePromptResponse`  | Prompt Template  |
| `standardInvocableAction` | `standardInvocableAction` | Built-in Actions |
| `externalService`         | `externalService`         | External APIs    |
| `quickAction`             | `quickAction`             | Quick Actions    |
| `api`                     | `api`                     | REST API         |
| `apexRest`                | `apexRest`                | Apex REST        |

Additional types: `serviceCatalog`, `integrationProcedureAction`, `expressionSet`, `cdpMlPrediction`, `externalConnector`, `slack`, `namedQuery`, `auraEnabled`, `mcpTool`, `retriever`

### Full Action Syntax

```agentscript
actions:
   get_customer:
      description: "Fetches customer information"
      label: "Get Customer"
      require_user_confirmation: False
      include_in_progress_indicator: True
      progress_indicator_message: "Looking up customer..."
      inputs:
         customer_id: string
            description: "The customer's unique ID"
            label: "Customer ID"
            is_required: True
      outputs:
         name: string
            description: "Customer's name"
         email: string
            description: "Customer's email"
            filter_from_agent: False
            is_displayable: True
      target: "flow://GetCustomerInfo"
```

### Output Parameter Complex Data Types

When defining action output parameters, use the `object` type with a `complex_data_type_name` to map to specific Salesforce data types. This is required when the platform expects a particular data type mapping (e.g., Integer outputs from Apex `@InvocableMethod` classes).

**Primitive Types:**

| `complex_data_type_name`  | Description                    |
| ------------------------- | ------------------------------ |
| `lightning__integerType`  | Integer numbers                |
| `lightning__booleanType`  | True/false values              |
| `lightning__dateType`     | Date values                    |
| `lightning__dateTimeType` | Date and time values           |
| `lightning__doubleType`   | Decimal/floating point numbers |

**Complex Types:**

| `complex_data_type_name` | Description             |
| ------------------------ | ----------------------- |
| `lightning__objectType`  | Complex data structures |
| `lightning__listType`    | Arrays/lists of items   |

**Apex Class Types:**

Reference custom Apex classes using the format `@apexClassType/<namespace>__<ClassName>`:

```agentscript
# Example: custom Apex class output
outputs:
   document: object
      description: "Signed document wrapper"
      complex_data_type_name: "@apexClassType/c__AgentSentForSignature$DocumentWrapperSign"
```

**Syntax:**

```agentscript
actions:
   get_orders:
      description: "Retrieve orders for a customer"
      inputs:
         customer_id: string
            description: "The customer's Salesforce record ID"
      outputs:
         success: object
            description: "Whether the lookup was successful"
            complex_data_type_name: "lightning__booleanType"
         order_count: object
            description: "Total number of orders found"
            complex_data_type_name: "lightning__integerType"
         order_summary: string
            description: "Formatted summary of orders"
      target: "apex://OrderLookupService"
```

---

## Reasoning Actions

### Input Binding

```agentscript
reasoning:
   actions:
      # LLM slot-fills all parameters
      search: @actions.search_products
         with query=...
         with category=...

      # Mix of bound and slot-filled
      lookup: @actions.lookup_customer
         with customer_id=@variables.current_customer_id  # Bound
         with include_history=...                          # LLM decides
         with limit=10                                     # Fixed value
```

Use `...` to indicate LLM should extract value from conversation.

### Post-Action Directives

Only work with `@actions.*`, NOT with `@utils.*`:

```agentscript
reasoning:
   actions:
      process: @actions.process_order
         with order_id=@variables.order_id
         # Capture outputs
         set @variables.status = @outputs.status
         set @variables.total = @outputs.total
         # Chain another action
         run @actions.send_notification
            with message="Order processed"
            set @variables.notified = @outputs.sent
         # Conditional transition
         if @outputs.needs_review:
            transition to @subagent.review
```

### Utility Actions (reasoning.actions only)

| Utility                | Purpose               | Syntax                                          |
| ---------------------- | --------------------- | ----------------------------------------------- |
| `@utils.escalate`      | Escalate to human     | `name: @utils.escalate`                         |
| `@utils.transition to` | Permanent handoff     | `name: @utils.transition to @subagent.X`        |
| `@utils.setVariables`  | Set variables via LLM | `name: @utils.setVariables` with `with var=...` |
| `@subagent.<name>`     | Delegate (can return) | `name: @subagent.X`                             |

```agentscript
reasoning:
   actions:
      # Transition to another subagent (permanent handoff)
      go_to_checkout: @utils.transition to @subagent.checkout
         description: "Move to checkout when ready"
         available when @variables.cart_has_items == True

      # Escalate to human
      get_help: @utils.escalate
         description: "Connect with a human agent"
         available when @variables.needs_human == True

      # Delegate to subagent (can return)
      consult_expert: @subagent.expert_topic
         description: "Consult the expert subagent"

      # Set variables via LLM
      collect_info: @utils.setVariables
         description: "Collect user preferences"
         with preferred_color=...
         with budget=...
```

---

## Subagent Design Policy

Design subagents around distinct user intents or workflow responsibilities. A subagent should have one clear purpose, a clear description, and only the actions/tools needed for that purpose.

- Use the `start_agent` block as the agent router. It should classify the current request, initialize required state, and transition to the appropriate subagent.
- Keep subagent names and descriptions specific, distinct, and written in user-facing business language where possible.
- Put specialist behavior in separate subagents when it reduces overlap and improves routing clarity.
- Use direct `@subagent.name` references when a subagent should act like a specialist tool and return control to the calling subagent.
- Use `@utils.transition to @subagent.name` or directive `transition to @subagent.name` for one-way handoffs.
- Avoid duplicate responsibilities across subagents. Overlapping descriptions make LLM routing and tool selection less reliable.
- Use subagent-level `system.instructions` only when the subagent needs a real persona, policy, or behavior override.
- Keep global instructions global and subagent instructions local. Do not repeat large global policy text inside every subagent.

---

## Transition Syntax Rules

**CRITICAL: Different syntax depending on context!**

### In `reasoning.actions` (LLM-selected):

```agentscript
go_next: @utils.transition to @subagent.target_topic
   description: "Description for LLM"
```

### In Directive Blocks (`after_reasoning`):

```agentscript
transition to @subagent.target_topic
```

- NEVER use `@utils.transition to` in directive blocks
- NEVER use bare `transition to` in `reasoning.actions`

---

## Control Flow

### If/Else in Instructions

```agentscript
instructions:->
   | Welcome to the assistant!

   if @variables.user_name:
      | Hello, {!@variables.user_name}!
   else:
      | What's your name?

   if @variables.is_premium:
      | As a premium member, you have access to exclusive features.
```

Note: `else if` is not currently supported.

### Transitions in Directive Blocks

```agentscript
after_reasoning:
   if @variables.completed:
      transition to @subagent.summary
```

### Conditional Action Availability

```agentscript
reasoning:
   actions:
      admin_action: @actions.admin_function
         available when @variables.user_role == "admin"

      premium_feature: @actions.premium_function
         available when @variables.is_premium == True
```

---

## Templates & Expressions

### String Templates

Use `{!expression}` for string interpolation:

```agentscript
instructions:->
   | Your order total is: {!@variables.total}
   | Items in cart: {!@variables.cart_items}
   | Status: {!@variables.status if @variables.status else "pending"}
```

### Multiline Strings

Use `|` for multiline content:

```agentscript
instructions:|
   Line one
   Line two
   Line three
```

Or in procedures:

```agentscript
instructions:->
   | Line one
     continues here
   | Line two starts fresh
```

### Supported Operators

| Category    | Operators                                        |
| ----------- | ------------------------------------------------ |
| Comparison  | `==`, `!=`, `<`, `<=`, `>`, `>=`, `is`, `is not` |
| Logical     | `and`, `or`, `not`                               |
| Arithmetic  | `+`, `-` (no `*`, `/`, `%`)                      |
| Access      | `.` (property), `[]` (index)                     |
| Conditional | `x if condition else y`                          |

### Resource References

- `@actions.<name>` - Reference action defined in subagent's `actions` block
- `@subagent.<name>` - Reference a subagent by name
- `@variables.<name>` - Reference a variable
- `@outputs.<name>` - Reference action output (in post-action context)
- `@inputs.<name>` - Reference action input (procedure context only — see warning below)
- `@utils.<utility>` - Reference utility function (escalate, transition to, setVariables)

---

## Common Patterns

### Simple Q&A Agent

```agentscript
config:
   developer_name: "Simple_QA"

system:
   messages:
      welcome: "Hello! How can I help you today?"
      error: "Sorry, something went wrong."
   instructions: "You are a helpful assistant. Answer questions clearly."

start_agent agent_router:
   description: "Entry point"
   reasoning:
      actions:
         start: @utils.transition to @subagent.main

subagent main:
   description: "Answer user questions"
   reasoning:
      instructions:->
         | Help the user with their questions.
```

### Multi-Subagent with Transitions

```agentscript
start_agent agent_router:
   description: "Route to appropriate subagent"
   reasoning:
      actions:
         go_sales: @utils.transition to @subagent.sales
            description: "Handle sales inquiries"
         go_support: @utils.transition to @subagent.support
            description: "Handle support issues"

subagent sales:
   description: "Handle sales"
   reasoning:
      instructions:->
         | Help the customer with purchasing.
      actions:
         need_support: @utils.transition to @subagent.support
            description: "Transfer to support"

subagent support:
   description: "Handle support"
   reasoning:
      instructions:->
         | Help resolve the customer's issue.
      actions:
         need_sales: @utils.transition to @subagent.sales
            description: "Transfer to sales"
```

### Action with State Management

```agentscript
variables:
   customer_id: mutable string = ""
   customer_name: mutable string = ""
   customer_loaded: mutable boolean = False

subagent customer_service:
   description: "Customer service with data loading"

   actions:
      fetch_customer:
         description: "Get customer details"
         inputs:
            id: string
         outputs:
            name: string
            email: string
         target: "flow://FetchCustomer"

   reasoning:
      instructions:->
         if @variables.customer_id and not @variables.customer_loaded:
            run @actions.fetch_customer
               with id=@variables.customer_id
               set @variables.customer_name = @outputs.name
               set @variables.customer_loaded = True
         if @variables.customer_name:
            | Hello, {!@variables.customer_name}!
         else:
            | Please provide your customer ID.
```

---

## Validation Checklist

Before finalizing an Agent Script, verify:

- [ ] Block ordering is correct (config → variables → system → connections → knowledge → language → start_agent → subagents)
- [ ] `config` block has `developer_name` (and `default_agent_user` for service agents)
- [ ] `system` block has `messages.welcome`, `messages.error`, and `instructions`
- [ ] `start_agent` block exists with at least one transition action
- [ ] Each `subagent` has a `description` and `reasoning` block
- [ ] All `mutable` variables have default values
- [ ] All `linked` variables have `source` specified (and NO default value)
- [ ] Action `target` uses valid format (`flow://`, `apex://`, etc.)
- [ ] Boolean values use `True`/`False` (capitalized)
- [ ] `...` is used for LLM slot-filling (not as variable default values)
- [ ] `@utils.transition to` is used in `reasoning.actions`
- [ ] `transition to` (without `@utils`) is used in directive blocks
- [ ] Indentation is consistent (3 spaces recommended)
- [ ] Names follow naming rules (letters, numbers, underscores; no spaces; start with letter)
- [ ] Discovery Questions were answered before generating or changing the script
- [ ] Deterministic logic is used for required business rules, required workflows, action sequencing, and non-optional transitions
- [ ] LLM reasoning is used only where interpretation, natural language response, or flexible tool selection is appropriate
- [ ] Variables are used for state that affects business behavior; the design does not rely on LLM memory for required state
- [ ] `available when` filters guard actions and transitions that should only be visible in specific states
- [ ] Subagent descriptions are distinct and do not overlap in responsibility
- [ ] One-way transitions and returning subagent delegation are intentionally chosen
- [ ] Flow actions use active Flow API names, matching input/output names and expected types
- [ ] Flow/Apex/action security context, CRUD/FLS, sharing behavior, and data exposure have been reviewed
- [ ] Mutating or externally visible actions require confirmation or have a documented reason for automatic execution
- [ ] User-facing and agent-facing outputs are filtered appropriately with `filter_from_agent` when sensitive data should not enter the agent context
- [ ] Happy path, edge case, fallback, escalation, and regression conversation paths have been tested or documented

---

## Error Prevention

### Common Mistakes

1. **Wrong transition syntax:**

    ```agentscript
    # WRONG in reasoning.actions
    go_next: transition to @subagent.next

    # CORRECT in reasoning.actions
    go_next: @utils.transition to @subagent.next

    # CORRECT in directive blocks
    after_reasoning:
       transition to @subagent.next
    ```

2. **Missing default for mutable:**

    ```agentscript
    # WRONG
    count: mutable number

    # CORRECT
    count: mutable number = 0
    ```

3. **Wrong boolean case:**

    ```agentscript
    # WRONG
    enabled: mutable boolean = true

    # CORRECT
    enabled: mutable boolean = True
    ```

4. **Using `...` as a variable default (it's for slot-filling only):**

    ```agentscript
    # WRONG - this is slot-filling syntax
    my_var: mutable string = ...

    # CORRECT
    my_var: mutable string = ""
    ```

5. **List type for linked variables:**

    ```agentscript
    # WRONG - linked cannot be list
    items: linked list[string]

    # CORRECT
    items: mutable list[string] = []
    ```

6. **Default value on linked variable:**

    ```agentscript
    # WRONG - linked variables get value from source
    session_id: linked string = ""
       source: @session.sessionID

    # CORRECT
    session_id: linked string
       source: @session.sessionID
    ```

7. **Post-action directives on utilities:**

    ```agentscript
    # WRONG - utilities don't support post-action directives
    go_next: @utils.transition to @subagent.next
       set @variables.navigated = True

    # CORRECT - only @actions support post-action directives
    process: @actions.process_order
       set @variables.result = @outputs.result
    ```

8. **Referencing actions by bare name instead of `@actions.`:**

    Always use `@actions.action_name` when referencing actions — in `run` statements, template expressions `{!...}`, and instruction text. Never use the bare action name.

    ```agentscript
    # WRONG - bare action name in run statement
    run set_user_name

    # CORRECT
    run @actions.set_user_name

    # WRONG - bare action name in instruction text
    | Add items to the cart using add_to_cart

    # CORRECT
    | Add items to the cart using {!@actions.add_to_cart}

    # WRONG - bare action name in instructions referencing a reasoning action
    | If continuing a conversation, route to begin_data_management.

    # CORRECT
    | If continuing a conversation, route to {!@actions.begin_data_management}.
    ```

9. **Using `run @actions.X` where X is only a reasoning-level utility (not a subagent-level action):**

    The `run @actions.X` directive in `instructions` procedures resolves against the **subagent-level `actions`** block (those with a `target:`). It cannot invoke actions defined only in `reasoning.actions` (such as `@utils.setVariables`). If the subagent has no top-level `actions` block, you'll get: _"Action '@actions.X' not found … No actions defined in this subagent."_

    ```agentscript
    # WRONG - set_user_name is a @utils.setVariables utility, not a subagent-level action
    reasoning:
       instructions:->
          run @actions.set_user_name
          | Collect the user's name.
       actions:
          set_user_name: @utils.setVariables
             with user_name=...

    # CORRECT - remove the run; the LLM will invoke set_user_name during reasoning
    reasoning:
       instructions:->
          | Collect the user's name.
       actions:
          set_user_name: @utils.setVariables
             with user_name=...

    # ALSO VALID - run works when the action is defined at the subagent level with a target
    actions:
       fetch_customer:
          inputs:
             id: string
          outputs:
             name: string
          target: "flow://FetchCustomer"
    reasoning:
       instructions:->
          run @actions.fetch_customer
             with id=@variables.customer_id
             set @variables.customer_name = @outputs.name
    ```

10. **Using `@inputs` in `set` directives (causes unknown deploy error):**

    ```agentscript
    # WRONG - @inputs in set causes unknown error at deploy time
    verify: @actions.verify_customer
       with account_number=...
       set @variables.account_number = @inputs.account_number
       set @variables.customer_name = @outputs.customer_name

    # CORRECT - use @utils.setVariables to capture input, only @outputs in set
    collect_input: @utils.setVariables
       description: "Collect the account number from the user"
       with account_number=...
    verify: @actions.verify_customer
       with account_number=@variables.account_number
       set @variables.customer_name = @outputs.customer_name
    ```

---

## References

- Salesforce Developers: Agent Script Developer Guide: https://developer.salesforce.com/docs/ai/agentforce/guide/agent-script.html
- Salesforce Developers: Agent Script Variables: https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-ref-variables.html
- Salesforce Developers: Agent Script Actions: https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-ref-actions.html
- Salesforce Developers: Agent Script Flow of Control: https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-flow.html
- Salesforce Developers: Agent Script Common Patterns: https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-patterns.html
- Trailhead Apps Agent Script Recipes rules source: https://github.com/trailheadapps/agent-script-recipes/blob/main/.airules/AGENT_SCRIPT.md
- Salesforce Developers Japan Blog: Agent Script fundamentals: https://developer.salesforce.com/jpblogs/2026/03/agent-script-decoded-intro-to-agent-script-language-fundamentals-jp
- Qiita: Agent Script writing guide: https://qiita.com/misu007/items/790d61c4de7071fcf215
