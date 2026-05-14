# flowToApexAI

AI-powered Salesforce Flow to Apex converter that runs entirely inside the org.
Reads a Record-Triggered Flow via the Tooling API, sends it to a Prompt Builder
template, and persists Einstein-generated Apex into a custom object — all inside
the Einstein Trust Layer.

## Architecture

User (Lightning App)
↓
LWC: flowToApexConverter
↓
Apex: FlowToApexService.migrate(flowApiName)
├── FlowReaderService     → Tooling API (Flow JSON)
├── EinsteinPromptClient  → Prompt Builder → Einstein
└── Insert FlowMigration__c with generated Apex
↓
Record page + flowMigrationCodeViewer LWC (tabbed code view, copy buttons)

## What's included

- Custom Object: `FlowMigration__c`
- Apex services: `FlowReaderService`, `EinsteinPromptClient`, `FlowToApexService` (+ tests)
- LWCs: `flowToApexConverter`, `flowMigrationCodeViewer`
- Visualforce: `SessionIdPage` (for REST-API-valid session in LWC context)
- Custom Tabs + Lightning App: `Flow to Apex AI`

The Prompt Builder template `Flow_To_Apex_Converter` lives in Salesforce setup
and must be created manually in the target org.

## Prerequisites

- Org with Einstein Generative AI + Prompt Builder enabled
- Remote Site Setting pointing at the org's My Domain URL
- Manually-created Prompt Template named `Flow_To_Apex_Converter` with a
  `flowMetadata` Free Text input variable (see `docs/flowToApexAI_User_Guide.pdf`)

## Deploy

```bash
sf project deploy start --source-dir force-app/main/default --target-org <orgAlias>
```

## Use

App Launcher → **Flow to Apex AI** → enter Flow API name → **Convert to Apex**.

See `docs/flowToApexAI_User_Guide.pdf` for the full walkthrough.