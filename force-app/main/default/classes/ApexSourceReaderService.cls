/**
 * @description Reads Apex class source via the Tooling API.
 *              Returns the .Body of the named ApexClass so it can be sent
 *              to the Apex_To_Flow_Converter Prompt Template.
 */
public with sharing class ApexSourceReaderService {

    private static final String API_VERSION = 'v59.0';
    public class ApexReaderException extends Exception {}

    public static String getApexBody(String apexClassName) {
        if (String.isBlank(apexClassName)) {
            throw new ApexReaderException('Apex class name is required.');
        }
        String soql = 'SELECT Id, Name, Body FROM ApexClass WHERE Name = \'' +
            String.escapeSingleQuotes(apexClassName) + '\'';
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
            throw new ApexReaderException(
                'Tooling API call failed (HTTP ' + res.getStatusCode() + '): ' + res.getBody()
            );
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> records = (List<Object>) body.get('records');
        if (records == null || records.isEmpty()) {
            throw new ApexReaderException('Apex class not found: ' + apexClassName);
        }
        Object apexBody = ((Map<String, Object>) records[0]).get('Body');
        if (apexBody == null || String.isBlank(String.valueOf(apexBody))) {
            throw new ApexReaderException('Apex class body is empty: ' + apexClassName);
        }
        return String.valueOf(apexBody);
    }

    private static String getValidSessionId() {
        if (Test.isRunningTest()) return UserInfo.getSessionId();
        try {
            return Page.SessionIdPage.getContent().toString().trim();
        } catch (Exception e) {
            return UserInfo.getSessionId();
        }
    }
}
