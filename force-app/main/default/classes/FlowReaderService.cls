/**
 * @description Reads Salesforce Flow metadata via the Tooling API and returns
 *              it as a cleaned-up JSON string ready for LLM consumption.
 *              
 * @usage       String json = FlowReaderService.getFlowMetadata('Account_Set_Default_Industry');
 *
 * @prerequisite
 *   - Remote Site Setting pointing at the org's My Domain URL.
 *   - Visualforce page 'SessionIdPage' deployed (used in Lightning/LWC context
 *     where UserInfo.getSessionId() returns a non-REST-API Lightning session).
 */

public with sharing class FlowReaderService {

    private static final String API_VERSION = 'v59.0';
    public class FlowReaderException extends Exception {}

    public static String getFlowMetadata(String flowApiName) {
        if (String.isBlank(flowApiName)) {
            throw new FlowReaderException('Flow API name is required.');
        }
        String activeVersionId = findActiveVersionId(flowApiName);
        Object metadata = fetchFlowMetadata(activeVersionId, flowApiName);
        Object pruned = pruneEmpty(metadata);
        return JSON.serializePretty(pruned);
    }

    private static String findActiveVersionId(String flowApiName) {
        String soql = 'SELECT Id, DeveloperName, ActiveVersionId FROM FlowDefinition WHERE DeveloperName = \'' + String.escapeSingleQuotes(flowApiName) + '\'';
        Map<String, Object> response = executeToolingQuery(soql);
        List<Object> records = (List<Object>) response.get('records');
        if (records == null || records.isEmpty()) {
            throw new FlowReaderException('Flow not found: ' + flowApiName);
        }
        Map<String, Object> def = (Map<String, Object>) records[0];
        String activeId = (String) def.get('ActiveVersionId');
        if (String.isBlank(activeId)) {
            throw new FlowReaderException('Flow has no active version. Activate the Flow before migrating: ' + flowApiName);
        }
        return activeId;
    }

    private static Object fetchFlowMetadata(String activeVersionId, String flowApiName) {
        String soql = 'SELECT Id, MasterLabel, Metadata FROM Flow WHERE Id = \'' + activeVersionId + '\'';
        Map<String, Object> response = executeToolingQuery(soql);
        List<Object> records = (List<Object>) response.get('records');
        if (records == null || records.isEmpty()) {
            throw new FlowReaderException('Active Flow version metadata unavailable for: ' + flowApiName);
        }
        Object metadata = ((Map<String, Object>) records[0]).get('Metadata');
        if (metadata == null) {
            throw new FlowReaderException('Flow Metadata is empty for: ' + flowApiName);
        }
        return metadata;
    }

    private static Map<String, Object> executeToolingQuery(String soql) {
        String url = URL.getOrgDomainURL().toExternalForm() +
            '/services/data/' + API_VERSION + '/tooling/query/?q=' +
            EncodingUtil.urlEncode(soql, 'UTF-8');
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + getValidSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(60000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new FlowReaderException('Tooling API call failed (HTTP ' + res.getStatusCode() + '): ' + res.getBody());
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static String getValidSessionId() {
        if (Test.isRunningTest()) {
            return UserInfo.getSessionId();
        }
        try {
            return Page.SessionIdPage.getContent().toString().trim();
        } catch (Exception e) {
            return UserInfo.getSessionId();
        }
    }


    private static final Set<String> IGNORED_KEYS = new Set<String>{
        'processMetadataValues', 'attributes', 'segment', 'form',
        'sourceTemplate', 'overriddenFlow', 'migratedFromWorkflowRuleName',
        'interviewLabel', 'apexPluginCalls', 'isTemplate', 'isOverridable',
        'isAdditionalPermissionRequiredToRun', 'runInMode', 'environments'
    };

    private static Object pruneEmpty(Object input) {
        if (input == null) return null;
        if (input instanceof Map<String, Object>) {
            Map<String, Object> src = (Map<String, Object>) input;
            Map<String, Object> out = new Map<String, Object>();
            for (String key : src.keySet()) {
                if (IGNORED_KEYS.contains(key)) continue;
                Object pruned = pruneEmpty(src.get(key));
                if (!isEmpty(pruned)) out.put(key, pruned);
            }
            return out;
        }
        if (input instanceof List<Object>) {
            List<Object> src = (List<Object>) input;
            List<Object> out = new List<Object>();
            for (Object item : src) {
                Object pruned = pruneEmpty(item);
                if (!isEmpty(pruned)) out.add(pruned);
            }
            return out;
        }
        return input;
    }

    private static Boolean isEmpty(Object val) {
        if (val == null) return true;
        if (val instanceof String) return String.isBlank((String) val);
        if (val instanceof List<Object>) return ((List<Object>) val).isEmpty();
        if (val instanceof Map<String, Object>) return ((Map<String, Object>) val).isEmpty();
        return false;
    }
}