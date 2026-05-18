# flowToApexAI

AI-powered, bidirectional Salesforce migration tool that runs entirely inside
the org. Reads a Record-Triggered Flow or a handler Apex class via the Tooling
API, sends it to a Prompt Builder template, and persists the Einstein-generated
result into a custom object — all inside the Einstein Trust Layer.

Two conversions:

- **Flow → Apex** — produces a handler class that plugs into the per-object
  Trigger Dispatcher with a single registration line.
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
   │     ├── FlowReaderService        → Tooling API (Flow JSON)
   │     ├── EinsteinPromptClient     → Prompt Builder → Einstein
   │     └── insert FlowMigration__c (Direction = Flow_To_Apex, Generated_Apex__c)
   │
   └── ApexToFlowService.migrate(apexClassName)
         ├── ApexSourceReaderService  → Tooling API (ApexClass body)
         ├── EinsteinPromptClient     → Prompt Builder → Einstein
         └── insert FlowMigration__c (Direction = Apex_To_Flow,
                                      Generated_Flow_XML__c or Error_Message__c)
   │
   ▼
Record page + flowMigrationCodeViewer LWC (renders handler / Flow XML / refusal reason)
   │
   ▼
Generated handler is registered with a single line in <Object>TriggerDispatcher.dispatch()
```

## What's included

**Custom Object**
- `FlowMigration__c` — stores every conversion. Fields: `Source_Flow_Name__c`,
  `Object_Name__c`, `Direction__c` (picklist: Flow_To_Apex / Apex_To_Flow),
  `Status__c`, `Generated_Apex__c`, `Generated_Flow_XML__c`, `Error_Message__c`.

**Apex services** (each with a matching test class)
- `FlowReaderService`         — pulls Flow metadata JSON via Tooling API
- `ApexSourceReaderService`   — pulls Apex class body via Tooling API
- `EinsteinPromptClient`      — generic Prompt Builder invocation client
- `FlowToApexService`         — Flow → Apex orchestration
- `ApexToFlowService`         — Apex → Flow orchestration

**Triggers + Dispatchers** (one trigger per object, never modified; handlers
registered as one-liners inside the dispatcher)
- Account: `AccountTrigger`, `AccountTriggerDispatcher` (+ test)
- Opportunity: `OpportunityTrigger`, `OpportunityTriggerDispatcher` (+ test)
- Case: `CaseTrigger`, `CaseTriggerDispatcher` (+ test)
- Contact: `ContactTrigger`, `ContactTriggerDispatcher` (+ test)
- Lead: `LeadTrigger`, `LeadTriggerDispatcher` (+ test)

**LWCs**
- `flowToApexConverter` — direction toggle, source input, result renderer with
  copy buttons and "Open Migration Record" navigation.
- `flowMigrationCodeViewer` — record page component that renders the generated
  handler, the generated Flow XML, the refusal reason, or an empty state,
  inferring the case from whichever output field is populated.

**UI shell**
- Visualforce page `SessionIdPage` — surfaces a REST-API-valid session id
  consumable from the LWC context.
- Custom Tabs: `Flow_Converter`, `Flow Migrations` (FlowMigration__c).
- Lightning App: `Flow to Apex AI`.

**Prompts** (live in Salesforce setup as Prompt Builder templates; canonical
copies are kept in this repo for review and version control)
- `docs/prompts/Flow_To_Apex_Converter.txt`
- `docs/prompts/Apex_To_Flow_Converter.txt`

## Prerequisites

- Org with Einstein Generative AI + Prompt Builder enabled.
- Remote Site Setting pointing at the org's My Domain URL (the Tooling API
  callout target).
- Two Prompt Templates manually created in setup, matching the names and input
  variables below:
  - `Flow_To_Apex_Converter` — input variable `flowMetadata` (Free Text).
    Body: paste the contents of `docs/prompts/Flow_To_Apex_Converter.txt`.
  - `Apex_To_Flow_Converter` — input variable `apexSource` (Free Text).
    Body: paste the contents of `docs/prompts/Apex_To_Flow_Converter.txt`.

## Deploy

```bash
sf project deploy start --source-dir force-app/main/default --target-org <orgAlias>
```

After deploy, grant Field-Level Security read on `FlowMigration__c.Direction__c`
to running profiles, and add `Direction` to the Flow Migration page layout if
you want it visible on the record page.

## Use

App Launcher → **Flow to Apex AI** → choose direction → enter the source name
(Flow API name for Flow→Apex; Apex class name for Apex→Flow) → **Convert**.

The result renders inline with copy buttons. "Open Migration Record" navigates
to the persisted FlowMigration__c record where the same output is rendered by
`flowMigrationCodeViewer` for later reference.

### Registering a generated handler

After a successful Flow→Apex conversion, register the handler in the matching
object's dispatcher by adding one line inside `dispatch()`:

```apex
// e.g. in AccountTriggerDispatcher.cls
public static void dispatch(System.TriggerOperation op, List<Account> records, Map<Id, Account> oldMap) {
    AccountSetDefaultIndustryHandler.run(op, records, oldMap);
}
```

The handler's `run(op, records, oldMap)` signature is enforced by the prompt,
so registration is always exactly one line. The trigger file itself never
changes as new handlers are added.
