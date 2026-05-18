/**
 * @description Orchestrates an Apex→Flow conversion end-to-end:
 *              1. Reads the source Apex class body via the Tooling API.
 *              2. Sends it to the Apex_To_Flow_Converter Prompt Template.
 *              3. Parses the response: either TRANSLATABLE (with Flow XML) or
 *                 NOT_TRANSLATABLE (with a refusal reason).
 *              4. Persists the result into FlowMigration__c (Direction = Apex_To_Flow).
 */
public with sharing class ApexToFlowService {

    private static final String TEMPLATE_API_NAME = 'Apex_To_Flow_Converter';

    public class MigrationResult {
        @AuraEnabled public Id     migrationId;
        @AuraEnabled public String status;        // 'Generated' | 'NotTranslatable' | 'Failed'
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String apexName;
        @AuraEnabled public String objectName;
        @AuraEnabled public String flowXml;
        @AuraEnabled public String refusalReason;
    }

    @AuraEnabled
    public static MigrationResult migrate(String apexClassName) {
        MigrationResult out = new MigrationResult();
        out.apexName = apexClassName;

        if (String.isBlank(apexClassName)) {
            out.status = 'Failed';
            out.errorMessage = 'Apex class name is required.';
            return out;
        }

        FlowMigration__c rec = new FlowMigration__c(
            Source_Flow_Name__c = apexClassName,
            Direction__c        = 'Apex_To_Flow',
            Status__c           = 'New'
        );

        try {
            // Callouts FIRST — all of them — before any DML.
            String apexBody = ApexSourceReaderService.getApexBody(apexClassName);
            String raw = EinsteinPromptClient.invoke(
                TEMPLATE_API_NAME,
                new Map<String, String>{ 'apexSource' => apexBody }
            );

            ParsedResponse p = parseResponse(raw);
            rec.Object_Name__c = p.objectName;

            if (p.translatable) {
                rec.Generated_Flow_XML__c = truncate(p.flowXml, 131072);
                rec.Status__c             = 'Generated';
                out.flowXml = p.flowXml;
                out.status  = 'Generated';
            } else {
                rec.Error_Message__c = truncate('Not translatable: ' + p.reason, 32768);
                rec.Status__c        = 'Failed';
                out.refusalReason = p.reason;
                out.status        = 'NotTranslatable';
            }
            insert rec;
            out.migrationId = rec.Id;
            out.objectName  = p.objectName;
            return out;

        } catch (Exception e) {
            rec.Status__c        = 'Failed';
            rec.Error_Message__c = truncate(
                e.getMessage() + '\n\n' + e.getStackTraceString(), 32768
            );
            insert rec;
            out.migrationId  = rec.Id;
            out.status       = 'Failed';
            out.errorMessage = e.getMessage();
            return out;
        }
    }

    // ----- parsing -----

    private class ParsedResponse {
        Boolean translatable;
        String  flowXml;
        String  reason;
        String  objectName;
    }

    /**
     * Expected response shape (markers from the prompt):
     *   ===STATUS===
     *   TRANSLATABLE | NOT_TRANSLATABLE
     *   ===OBJECT===
     *   Account
     *   ===FLOW_XML===
     *   <flow xml ...>
     *   ===REASON===
     *   <one or two sentences>
     */
    private static ParsedResponse parseResponse(String raw) {
        if (String.isBlank(raw)) {
            throw new EinsteinPromptClient.EinsteinClientException('Empty model response.');
        }
        ParsedResponse p = new ParsedResponse();

        if (raw.indexOf('===STATUS===') < 0) {
            throw new EinsteinPromptClient.EinsteinClientException(
                'Model response missing ===STATUS=== marker. First 500 chars: ' +
                raw.substring(0, Math.min(500, raw.length()))
            );
        }

        String statusSection = section(raw, '===STATUS===',  new List<String>{'===OBJECT===','===FLOW_XML===','===REASON==='});
        p.objectName = section(raw, '===OBJECT===',  new List<String>{'===FLOW_XML===','===REASON==='});
        String xml   = section(raw, '===FLOW_XML===', new List<String>{'===REASON==='});
        String reason = section(raw, '===REASON===', new List<String>());

        Boolean isTranslatable = (statusSection != null) &&
            statusSection.toUpperCase().contains('TRANSLATABLE') &&
            !statusSection.toUpperCase().contains('NOT_TRANSLATABLE');

        if (isTranslatable && !String.isBlank(xml)) {
            p.translatable = true;
            p.flowXml = xml;
        } else if (!String.isBlank(reason)) {
            p.translatable = false;
            p.reason = reason;
        } else if (!String.isBlank(xml)) {
            // STATUS unclear but XML present — accept it
            p.translatable = true;
            p.flowXml = xml;
        } else {
            throw new EinsteinPromptClient.EinsteinClientException(
                'Model response missing FLOW_XML and REASON sections.'
            );
        }
        return p;
    }

    private static String section(String raw, String startMarker, List<String> terminators) {
        Integer start = raw.indexOf(startMarker);
        if (start < 0) return null;
        Integer beginIdx = start + startMarker.length();
        Integer finishIdx = raw.length();
        for (String m : terminators) {
            Integer idx = raw.indexOf(m, beginIdx);
            if (idx >= 0 && idx < finishIdx) finishIdx = idx;
        }
        return raw.substring(beginIdx, finishIdx).trim();
    }

    private static String truncate(String value, Integer maxLen) {
        if (value == null) return null;
        if (value.length() <= maxLen) return value;
        return value.substring(0, maxLen - 25) + '\n\n...[truncated]';
    }
}
