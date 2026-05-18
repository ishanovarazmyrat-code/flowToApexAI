/**
 * @description Orchestrates a Flow→Apex conversion end-to-end:
 *              1. Reads the source Flow metadata via the Tooling API.
 *              2. Sends it to the Flow_To_Apex_Converter Prompt Template.
 *              3. Parses the handler class from the model response.
 *              4. Deploys the handler Apex class via the Tooling API (synchronous callout).
 *              5. Registers it in Trigger_Handler__mdt so the CMT-based dispatcher picks it up
 *                 automatically — no manual dispatcher edits required.
 *              6. Persists everything into FlowMigration__c.
 */
public with sharing class FlowToApexService {

    private static final String TEMPLATE_API_NAME = 'Flow_To_Apex_Converter';

    public class MigrationResult {
        @AuraEnabled public Id     migrationId;
        @AuraEnabled public String status;         // 'Generated' | 'Failed'
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String flowName;
        @AuraEnabled public String objectName;
        @AuraEnabled public String handlerCode;
        @AuraEnabled public String dispatcherHint; // kept for backwards-compat / display
        @AuraEnabled public String deployStatus;   // 'Deployed' | 'Deploy_Failed' | 'Not_Attempted'
        @AuraEnabled public String deployError;
    }

    @AuraEnabled
    public static MigrationResult migrate(String flowApiName) {
        MigrationResult out = new MigrationResult();
        out.flowName = flowApiName;

        if (String.isBlank(flowApiName)) {
            out.status = 'Failed';
            out.errorMessage = 'Flow API name is required.';
            return out;
        }

        FlowMigration__c rec = new FlowMigration__c(
            Source_Flow_Name__c = flowApiName,
            Direction__c        = 'Flow_To_Apex',
            Status__c           = 'New'
        );

        try {
            // ── Step 1-2: All callouts BEFORE any DML ──────────────────────
            String flowMetadataJson = FlowReaderService.getFlowMetadata(flowApiName);
            String raw = EinsteinPromptClient.invoke(
                TEMPLATE_API_NAME,
                new Map<String, String>{ 'flowMetadata' => flowMetadataJson }
            );

            Parsed p = parseResponse(raw);
            rec.Object_Name__c    = p.objectName;
            rec.Generated_Apex__c = truncate(p.handlerCode, 131072);
            rec.Status__c         = 'Generated';

            // ── Step 3: Deploy handler class (callout — still before DML) ──
            ApexDeployService.DeployResult deployResult = null;
            if (String.isNotBlank(p.className) && String.isNotBlank(p.handlerCode)) {
                deployResult = ApexDeployService.deployApexClass(p.className, p.handlerCode);
            }

            String deployStatus = deployResult == null     ? 'Not_Attempted'
                                : deployResult.success     ? 'Deployed'
                                                           : 'Deploy_Failed';
            rec.Deploy_Status__c = deployStatus;

            // ── Step 4: DML ─────────────────────────────────────────────────
            insert rec;

            // ── Step 5: Register in CMT (after DML — not a callout) ─────────
            // Isolated try/catch: a CMT deploy failure must never roll back the
            // already-inserted FlowMigration__c record or produce an unhandled exception.
            if (deployResult != null && deployResult.success
                    && String.isNotBlank(p.objectName) && String.isNotBlank(p.className)) {
                try {
                    ApexDeployService.registerHandlerAsync(p.objectName, p.className);
                } catch (Exception cmtEx) {
                    // Non-fatal: class is deployed; dispatcher registration will need
                    // to be done manually or retried. Surface the error but keep status=Generated.
                    deployStatus         = 'Deploy_Failed';
                    rec.Deploy_Status__c = deployStatus;
                    update rec;
                    out.deployError = 'CMT registration failed: ' + cmtEx.getMessage();
                }
            }

            out.migrationId    = rec.Id;
            out.status         = 'Generated';
            out.objectName     = p.objectName;
            out.handlerCode    = p.handlerCode;
            out.dispatcherHint = p.dispatcherHint;
            out.deployStatus   = deployStatus;
            if (deployResult != null && !deployResult.success && out.deployError == null) {
                out.deployError = deployResult.errorMessage;
            }
            return out;

        } catch (Exception e) {
            rec.Status__c        = 'Failed';
            rec.Error_Message__c = truncate(
                e.getMessage() + '\n\n' + e.getStackTraceString(), 32768
            );
            // rec.Id is null here (DML not yet run) so insert is always safe.
            // If somehow Id is already set (should not happen), fall back to update.
            if (rec.Id == null) {
                insert rec;
            } else {
                update rec;
            }
            out.migrationId  = rec.Id;
            out.status       = 'Failed';
            out.errorMessage = e.getMessage();
            return out;
        }
    }

    // -------------------------------------------------------------------------
    // Parsing
    // -------------------------------------------------------------------------

    private class Parsed {
        String objectName;
        String className;      // extracted from the class declaration
        String handlerCode;
        String dispatcherHint;
    }

    /**
     * Expected format (markers from the prompt):
     *   ===OBJECT===
     *   Account
     *   ===HANDLER===
     *   public with sharing class AccountFooHandler implements IFlowMigrationHandler { ... }
     *   ===DISPATCHER===
     *   AccountFooHandler.run(op, records, oldMap);  (kept for UI display only)
     */
    private static Parsed parseResponse(String raw) {
        if (String.isBlank(raw)) {
            throw new EinsteinPromptClient.EinsteinClientException('Empty model response.');
        }
        Parsed p = new Parsed();
        p.objectName     = extractBetween(raw, '===OBJECT===',     '===HANDLER===');
        p.handlerCode    = extractBetween(raw, '===HANDLER===',    '===DISPATCHER===');
        p.dispatcherHint = extractAfter(raw,   '===DISPATCHER===');

        if (String.isBlank(p.handlerCode)) {
            Integer h = raw.indexOf('===HANDLER===');
            if (h >= 0) {
                p.handlerCode = raw.substring(h + '===HANDLER==='.length()).trim();
            } else {
                throw new EinsteinPromptClient.EinsteinClientException(
                    'Model response missing ===HANDLER=== marker. First 500 chars: ' +
                    raw.substring(0, Math.min(500, raw.length()))
                );
            }
        }

        p.className = extractClassName(p.handlerCode);
        return p;
    }

    private static String extractClassName(String apexBody) {
        if (String.isBlank(apexBody)) return null;
        Matcher m = Pattern.compile('(?i)\\bclass\\s+(\\w+)').matcher(apexBody);
        return m.find() ? m.group(1) : null;
    }

    private static String extractBetween(String raw, String startMarker, String endMarker) {
        Integer a = raw.indexOf(startMarker);
        if (a < 0) return null;
        Integer b = raw.indexOf(endMarker, a + startMarker.length());
        if (b < 0) return null;
        return raw.substring(a + startMarker.length(), b).trim();
    }

    private static String extractAfter(String raw, String marker) {
        Integer i = raw.indexOf(marker);
        if (i < 0) return null;
        return raw.substring(i + marker.length()).trim();
    }

    private static String truncate(String value, Integer maxLen) {
        if (value == null) return null;
        if (value.length() <= maxLen) return value;
        return value.substring(0, maxLen - 25) + '\n\n...[truncated]';
    }
}
