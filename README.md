# flowToApexAI

AI-powered, bidirectional Salesforce migration tool that runs entirely inside
the org. Reads a Record-Triggered Flow or a handler Apex class via the Tooling
API, sends it to a Prompt Builder template, and persists the Einstein-generated
result into a custom object — all inside the Einstein Trust Layer.

Two conversions:

- **Flow → Apex** — generates a handler class, deploys it to the org via the
  Tooling API, and registers it in `Trigger_Handler__mdt` so the CMT-based
  dispatcher picks it up automatically on the next trigger fire. Zero manual steps.
- **Apex → Flow** — produces a deploy-ready `.flow-meta.xml`, or refuses with a
  reason when the handler uses patterns Flow cannot express.

## Architecture

```
User (Lightning App)
   │
   ▼
LWC: flowToApexConverter            ◄── direction toggle (Flow→Apex | Apex→Flow)
   │
   ▼
Apex orchestration
   ├── FlowToApexService.migrate(flowApiName)
   │     ├── FlowReaderService          → Tooling API (Flow JSON)
   │     ├── EinsteinPromptClient       → Prompt Builder → Einstein
   │     ├── ApexDeployService          → Tooling API (create ApexClass)
   │     ├── insert FlowMigration__c    (Direction=Flow_To_Apex, Deploy_Status__c)
   │     └── ApexDeployService @future  → Metadata.Operations (Trigger_Handler__mdt)
   │
   └── ApexToFlowService.migrate(apexClassName)
         ├── ApexSourceReaderService    → Tooling API (ApexClass body)
         ├── EinsteinPromptClient       → Prompt Builder → Einstein
         └── insert FlowMigration__c   (Direction=Apex_To_Flow,
                                        Generated_Flow_XML__c or Error_Message__c)
   │
   ▼
Record page + flowMigrationCodeViewer LWC
(renders handler / Flow XML / refusal reason)

── Trigger dispatch (Flow→Apex) ──────────────────────────────────────────────
AccountTrigger → AccountTriggerDispatcher.dispatch()
   └── queries Trigger_Handler__mdt WHERE Object__c = 'Account' AND Active__c = true
         └── Type.forName(Handler_Class__c).newInstance() → IFlowMigrationHandler.run()
```

## What's included

**Custom Object**
- `FlowMigration__c` — stores every conversion. Fields: `Source_Flow_Name__c`,
  `Object_Name__c`, `Direction__c` (Flow_To_Apex / Apex_To_Flow), `Status__c`,
  `Generated_Apex__c`, `Generated_Flow_XML__c`, `Error_Message__c`,
  `Deploy_Status__c` (Deployed / Deploy_Failed / Not_Attempted).

**Custom Metadata Type**
- `Trigger_Handler__mdt` — handler registry. Fields: `Object__c`,
  `Handler_Class__c`, `Active__c`, `Order__c`. Dispatchers query this at
  runtime; adding a new handler requires no code change.

**Interface**
- `IFlowMigrationHandler` — contract every generated handler implements:
  `void run(System.TriggerOperation op, List<SObject> records, Map<Id,SObject> oldMap)`

**Apex services** (each with a matching test class)
- `FlowReaderService`       — pulls Flow metadata JSON via Tooling API
- `ApexSourceReaderService` — pulls Apex class body via Tooling API
- `EinsteinPromptClient`    — generic Prompt Builder invocation client
- `FlowToApexService`       — Flow → Apex orchestration + auto-deploy
- `ApexToFlowService`       — Apex → Flow orchestration
- `ApexDeployService`       — Tooling API class creation + CMT registration
                              (`@future` to avoid mixed-DML with FlowMigration__c)

**Triggers + Dispatchers** (one trigger per object, never modified; handlers
registered automatically via Trigger_Handler__mdt)
- Account: `AccountTrigger`, `AccountTriggerDispatcher` (+ test)
- Opportunity: `OpportunityTrigger`, `OpportunityTriggerDispatcher` (+ test)
- Case: `CaseTrigger`, `CaseTriggerDispatcher` (+ test)
- Contact: `ContactTrigger`, `ContactTriggerDispatcher` (+ test)
- Lead: `LeadTrigger`, `LeadTriggerDispatcher` (+ test)

**LWCs**
- `flowToApexConverter` — direction toggle, source input, result renderer with
  copy buttons, deploy status badge, and "Open Migration Record" navigation.
- `flowMigrationCodeViewer` — record page component that renders the generated
  handler, the generated Flow XML, the refusal reason, or an empty state.

**UI shell**
- Visualforce page `SessionIdPage` — surfaces a REST-API-valid session ID for
  Tooling API self-callouts.
- Custom Tabs: `Flow_Converter`, `Flow Migrations` (FlowMigration__c).
- Lightning App: `Flow to Apex AI`.

**Prompts** (live in Salesforce Prompt Builder; canonical copies kept here for
review and version control)
- `docs/prompts/Flow_To_Apex_Converter.txt`
- `docs/prompts/Apex_To_Flow_Converter.txt`

**Reference**
- `docs/ApexToFlow_Architecture.html` — printable architecture guide (open in
  browser → Cmd+P → Save as PDF).

## Prerequisites

- Org with Einstein Generative AI + Prompt Builder enabled.
- Remote Site Setting pointing at the org's My Domain URL (Tooling API callout
  target).
- Two Prompt Templates created in Setup → Prompt Builder:
  - `Flow_To_Apex_Converter` — input variable `flowMetadata` (Free Text).
    Body: paste `docs/prompts/Flow_To_Apex_Converter.txt`.
  - `Apex_To_Flow_Converter` — input variable `apexSource` (Free Text).
    Body: paste `docs/prompts/Apex_To_Flow_Converter.txt`.

## Deploy

```bash
sf project deploy start --source-dir force-app/main/default --target-org <orgAlias>
```

After deploy:
- Grant Field-Level Security read on all `FlowMigration__c` fields to running profiles.
- Add `Direction` and `Deploy Status` to the Flow Migration page layout if you want
  them visible on the record page.

## Use

App Launcher → **Flow to Apex AI** → choose direction → enter the source name
(Flow API name for Flow→Apex; Apex class name for Apex→Flow) → **Convert**.

### Flow → Apex

Einstein generates the handler. Then automatically:

1. The handler Apex class is created in the org via the Tooling API.
2. A `Trigger_Handler__mdt` record is inserted via `Metadata.Operations`
   (runs in a `@future` transaction to avoid mixed-DML with `FlowMigration__c`).
3. On the next trigger fire, the CMT-based dispatcher instantiates the handler
   and calls `run()` — no dispatcher edits, no `sf deploy`.

The LWC shows a **Deployed** badge on success, or **Auto-deploy failed** with
the error detail if the Tooling API or CMT step fails (in which case you can
copy the generated code and deploy manually).

> **Note:** If the handler class already exists in the org (e.g. from a prior
> deploy), its body is not overwritten — only the CMT registration runs.

### Apex → Flow

The result renders inline with a copy button. "Open Migration Record" navigates
to the persisted `FlowMigration__c` record. If the handler uses patterns Flow
cannot express (try/catch, @future, callouts, etc.) the converter refuses with
a plain-English explanation.
