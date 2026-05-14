/**
 * @description Orchestrates a Flow-to-Apex conversion end-to-end:
 *              1. Reads the source Flow metadata via the Tooling API.
 *              2. Sends it to the Flow_To_Apex_Converter Prompt Template.
 *              3. Persists the source XML and generated Apex into a new
 *                 FlowMigration__c record.
 *
 *              This is the @AuraEnabled entry point called by the LWC.
 */
public with sharing class FlowToApexService {

    /** @AuraEnabled-friendly result object returned to the LWC. */
    public class MigrationResult {
        @AuraEnabled public Id      migrationId;
        @AuraEnabled public String  status;       // 'Generated' | 'Failed'
        @AuraEnabled public String  errorMessage; // populated when status = Failed
        @AuraEnabled public String  flowName;
        @AuraEnabled public String triggerCode;   
        @AuraEnabled public String handlerCode;

    }

    @AuraEnabled
    public static MigrationResult migrate(String flowApiName) {
        MigrationResult result = new MigrationResult();
        result.flowName = flowApiName;

        if (String.isBlank(flowApiName)) {
            result.status = 'Failed';
            result.errorMessage = 'Flow API name is required.';
            return result;
        }

        // IMPORTANT: All HTTP callouts (Tooling API + Einstein) MUST run before any DML
        //            in the same transaction. We build the FlowMigration__c record in
        //            memory and insert it once at the end (success or failure path).
        FlowMigration__c migration = new FlowMigration__c(
            Source_Flow_Name__c = flowApiName,
            Status__c           = 'New'
        );

        try {
            // Step 1: read Flow metadata via Tooling API (callout #1)
            String flowMetadataJson = FlowReaderService.getFlowMetadata(flowApiName);
            

            // Step 2: call Einstein with the Flow metadata (callout #2)
            EinsteinPromptClient.GeneratedApex generated =
                EinsteinPromptClient.generate(flowMetadataJson);

            String combined =
                '// ===== TRIGGER =====\n' +
                generated.triggerCode +
                '\n\n// ===== HANDLER =====\n' +
                generated.handlerCode;

            migration.Generated_Apex__c = truncateForField(combined, 131072);
            migration.Status__c         = 'Generated';

            // All callouts complete — single DML at the very end.
            insert migration;
            result.migrationId = migration.Id;
            result.triggerCode = generated.triggerCode;
            result.handlerCode = generated.handlerCode;
            result.status      = 'Generated';
            return result;

        } catch (Exception e) {
            // Capture the failure on the same in-memory record, then insert once.
            migration.Status__c        = 'Failed';
            migration.Error_Message__c = truncateForField(
                e.getMessage() + '\n\n' + e.getStackTraceString(),
                32768
            );
            insert migration;

            result.migrationId  = migration.Id;
            result.status       = 'Failed';
            result.errorMessage = e.getMessage();
            return result;
        }
    }

    /** Truncate a string to the field's max length, leaving room for an ellipsis. */
    private static String truncateForField(String value, Integer maxLength) {
        if (value == null) return null;
        if (value.length() <= maxLength) return value;
        return value.substring(0, maxLength - 25) + '\n\n...[truncated]';
    }
}
