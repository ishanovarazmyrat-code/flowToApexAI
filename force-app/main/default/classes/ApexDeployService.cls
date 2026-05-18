/**
 * @description Automates two steps that previously required manual work after a Flow→Apex conversion:
 *              1. Deploys the generated handler Apex class via the Tooling API (synchronous).
 *              2. Registers it in the Trigger_Handler__mdt registry via Metadata.Operations (async).
 *
 *              Both operations use the same session-ID pattern as FlowReaderService so no Named
 *              Credential is required.  Call BEFORE any DML in the same transaction.
 */
public with sharing class ApexDeployService {

    private static final String API_VERSION = 'v59.0';

    public class DeployResult {
        public Boolean success;
        public String  apexClassId;
        public String  errorMessage;
    }

    public class ApexDeployException extends Exception {}

    // -------------------------------------------------------------------------
    // Public surface
    // -------------------------------------------------------------------------

    /**
     * Deploys the generated handler Apex class via the Tooling API.
     * If a class with this name already exists (e.g. from a prior SFDX deploy or a
     * previous conversion), the class body is left untouched and the existing ID is
     * returned as a success — the CMT registration step will still run so the
     * dispatcher picks it up.
     *
     * Tooling API PATCH on metadata-deployed classes requires a MetadataContainer
     * workflow and elevated permissions; skipping the update avoids that restriction
     * and also prevents accidentally overwriting a handler that was manually edited.
     *
     * Must be called before any DML (callout restriction).
     */
    public static DeployResult deployApexClass(String className, String apexBody) {
        DeployResult result = new DeployResult();
        try {
            String existingId = findExistingClass(className);
            if (String.isNotBlank(existingId)) {
                // Class already exists — skip body update, proceed to CMT registration.
                result.apexClassId = existingId;
            } else {
                result.apexClassId = createApexClass(className, apexBody);
            }
            result.success = true;
        } catch (Exception e) {
            result.success      = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    /**
     * Enqueues CMT registration in a separate @future transaction to avoid the Salesforce
     * mixed-DML restriction: inserting FlowMigration__c (non-setup) and calling
     * Metadata.Operations.enqueueDeployment() (setup) cannot happen in the same transaction.
     *
     * Safe to call after any DML.  Skipped in test context.
     */
    public static void registerHandlerAsync(String objectName, String handlerClass) {
        if (Test.isRunningTest()) return;
        registerHandlerFuture(objectName, handlerClass);
    }

    @future
    private static void registerHandlerFuture(String objectName, String handlerClass) {
        registerHandler(objectName, handlerClass);
    }

    private static void registerHandler(String objectName, String handlerClass) {
        if (Test.isRunningTest()) return;

        String devName = sanitizeDevName(objectName + '_' + handlerClass);

        Metadata.CustomMetadata rec = new Metadata.CustomMetadata();
        rec.fullName = 'Trigger_Handler.' + devName;
        String rawLabel = handlerClass;
        rec.label = rawLabel.length() > 40 ? rawLabel.substring(0, 40) : rawLabel;
        rec.values   = new List<Metadata.CustomMetadataValue>{
            cmtValue('Object__c',         objectName),
            cmtValue('Handler_Class__c',  handlerClass),
            cmtValue('Active__c',         true)
        };

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(rec);
        Metadata.Operations.enqueueDeployment(container, null);
    }

    // -------------------------------------------------------------------------
    // Tooling API helpers
    // -------------------------------------------------------------------------

    private static String findExistingClass(String className) {
        String soql = 'SELECT Id FROM ApexClass WHERE Name = \'' +
            String.escapeSingleQuotes(className) + '\'';
        Map<String, Object> resp = toolingGet(
            '/tooling/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8')
        );
        List<Object> records = (List<Object>) resp.get('records');
        if (records == null || records.isEmpty()) return null;
        return (String) ((Map<String, Object>) records[0]).get('Id');
    }

    private static String createApexClass(String className, String body) {
        Map<String, Object> payload = new Map<String, Object>{
            'Name'       => className,
            'Body'       => body,
            'ApiVersion' => Decimal.valueOf(API_VERSION.replace('v', ''))
        };
        Map<String, Object> resp = toolingPost('/tooling/sobjects/ApexClass', payload);
        checkErrors(resp);
        return (String) resp.get('id');
    }

    // -------------------------------------------------------------------------
    // HTTP primitives
    // -------------------------------------------------------------------------

    private static Map<String, Object> toolingGet(String path) {
        HttpResponse res = send('GET', path, null);
        if (res.getStatusCode() != 200) {
            throw new ApexDeployException(
                'Tooling GET failed (' + res.getStatusCode() + '): ' + res.getBody()
            );
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static Map<String, Object> toolingPost(String path, Map<String, Object> body) {
        HttpResponse res = send('POST', path, JSON.serialize(body));
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new ApexDeployException(
                'Tooling POST failed (' + res.getStatusCode() + '): ' + res.getBody()
            );
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static HttpResponse send(String method, String path, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            URL.getOrgDomainURL().toExternalForm() + '/services/data/' + API_VERSION + path
        );
        req.setMethod(method);
        req.setHeader('Authorization', 'Bearer ' + sessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(60000);
        if (String.isNotBlank(body)) req.setBody(body);
        return new Http().send(req);
    }

    // -------------------------------------------------------------------------
    // Utilities
    // -------------------------------------------------------------------------

    private static void checkErrors(Map<String, Object> resp) {
        List<Object> errors = (List<Object>) resp.get('errors');
        if (errors != null && !errors.isEmpty()) {
            throw new ApexDeployException('Tooling API errors: ' + JSON.serialize(errors));
        }
        Object success = resp.get('success');
        if (success instanceof Boolean && !(Boolean) success) {
            throw new ApexDeployException('Tooling API reported failure: ' + JSON.serialize(resp));
        }
    }

    private static Metadata.CustomMetadataValue cmtValue(String field, Object value) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
        v.field = field;
        v.value = value;
        return v;
    }

    private static String sanitizeDevName(String raw) {
        String safe = raw.replaceAll('[^a-zA-Z0-9_]', '_');
        if (safe.length() > 40) safe = safe.substring(0, 40);
        return safe;
    }

    private static String sessionId() {
        if (Test.isRunningTest()) return UserInfo.getSessionId();
        try { return Page.SessionIdPage.getContent().toString().trim(); }
        catch (Exception e) { return UserInfo.getSessionId(); }
    }
}
