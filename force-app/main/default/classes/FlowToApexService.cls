/**
 * @description Orchestrates a Flow→Apex conversion end-to-end:
 *              1. Reads the source Flow metadata via the Tooling API.
 *              2. Sends it to the Flow_To_Apex_Converter Prompt Template.
 *              3. Parses the handler class (and optional object name) from the
 *                 model response and persists everything into FlowMigration__c.
 *
 *              Output is HANDLER-ONLY. The triggering itself is handled by a
 *              single per-object Trigger + Dispatcher pattern (see the
 *              AccountTrigger + AccountTriggerDispatcher template). Users add
 *              one line to the dispatcher to register each new handler.
 */
public with sharing class FlowToApexService {

    private static final String TEMPLATE_API_NAME = 'Flow_To_Apex_Converter';

    public class MigrationResult {
        @AuraEnabled public Id     migrationId;
        @AuraEnabled public String status;        // 'Generated' | 'Failed'
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String flowName;
        @AuraEnabled public String objectName;
        @AuraEnabled public String handlerCode;
        @AuraEnabled public String dispatcherHint; // e.g. "MyHandler.run(op, records, oldMap);"
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
            // Callouts FIRST — all of them — before any DML.
            String flowMetadataJson = FlowReaderService.getFlowMetadata(flowApiName);
            String raw = EinsteinPromptClient.invoke(
                TEMPLATE_API_NAME,
                new Map<String, String>{ 'flowMetadata' => flowMetadataJson }
            );

            Parsed p = parseResponse(raw);
            rec.Object_Name__c   = p.objectName;
            rec.Generated_Apex__c = truncate(
                p.handlerCode + buildDispatcherFooter(p),
                131072
            );
            rec.Status__c = 'Generated';
            insert rec;

            out.migrationId    = rec.Id;
            out.status         = 'Generated';
            out.objectName     = p.objectName;
            out.handlerCode    = p.handlerCode;
            out.dispatcherHint = p.dispatcherHint;
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

    private class Parsed {
        String objectName;
        String handlerCode;
        String dispatcherHint;
    }

    /**
     * Parses the model response. Expected format (markers from the prompt):
     *   ===OBJECT===
     *   Account
     *   ===HANDLER===
     *   public with sharing class ... { ... }
     *   ===DISPATCHER===
     *   AccountFooHandler.run(op, records, oldMap);
     *
     * The OBJECT and DISPATCHER sections are optional; HANDLER is required.
     */
    private static Parsed parseResponse(String raw) {
        if (String.isBlank(raw)) {
            throw new EinsteinPromptClient.EinsteinClientException('Empty model response.');
        }
        Parsed p = new Parsed();
        p.objectName     = extractBetween(raw, '===OBJECT===',     '===HANDLER===');
        p.handlerCode    = extractBetween(raw, '===HANDLER===',    '===DISPATCHER===');
        p.dispatcherHint = extractAfter(raw, '===DISPATCHER===');

        // Fallback: if the model produced only HANDLER without other markers
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
        return p;
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

    private static String buildDispatcherFooter(Parsed p) {
        if (String.isBlank(p.dispatcherHint)) return '';
        return '\n\n/*\n' +
            ' * Register this handler by adding the following line inside\n' +
            ' * the dispatcher\'s dispatch() method:\n' +
            ' *\n' +
            ' *   ' + p.dispatcherHint + '\n' +
            ' */';
    }

    private static String truncate(String value, Integer maxLen) {
        if (value == null) return null;
        if (value.length() <= maxLen) return value;
        return value.substring(0, maxLen - 25) + '\n\n...[truncated]';
    }
}
