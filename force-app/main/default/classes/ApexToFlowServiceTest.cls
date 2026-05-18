@IsTest
private class ApexToFlowServiceTest {

    private static final String TRANSLATABLE_RESPONSE =
        '===STATUS===\nTRANSLATABLE\n' +
        '===OBJECT===\nAccount\n' +
        '===FLOW_XML===\n' +
        '<?xml version="1.0" encoding="UTF-8"?>\n' +
        '<Flow xmlns="http://soap.sforce.com/2006/04/metadata">' +
        '<apiVersion>59.0</apiVersion><label>Generated</label></Flow>';

    private static final String REFUSAL_RESPONSE =
        '===STATUS===\nNOT_TRANSLATABLE\n' +
        '===REASON===\nClass uses Map<Id, SObject> for bulkification, which has no clean Flow equivalent.';

    @IsTest
    static void blankName_fails() {
        Test.startTest();
        ApexToFlowService.MigrationResult r = ApexToFlowService.migrate('');
        Test.stopTest();
        Assert.areEqual('Failed', r.status);
        Assert.areEqual('Apex class name is required.', r.errorMessage);
    }

    @IsTest
    static void translatablePath_persistsFlowXml() {
        Test.setMock(HttpCalloutMock.class, new ApexMock(true, 'public class Foo {}'));
        EinsteinPromptClient.instance = new EinsteinPromptClient.MockClient(TRANSLATABLE_RESPONSE);

        Test.startTest();
        ApexToFlowService.MigrationResult r = ApexToFlowService.migrate('Foo');
        Test.stopTest();

        Assert.areEqual('Generated', r.status);
        Assert.areEqual('Account', r.objectName);
        Assert.isTrue(r.flowXml.contains('Generated'));

        FlowMigration__c rec = [
            SELECT Direction__c, Status__c, Object_Name__c, Generated_Flow_XML__c
            FROM FlowMigration__c WHERE Id = :r.migrationId
        ];
        Assert.areEqual('Apex_To_Flow', rec.Direction__c);
        Assert.areEqual('Generated', rec.Status__c);
        Assert.areEqual('Account', rec.Object_Name__c);
        Assert.isTrue(rec.Generated_Flow_XML__c.contains('<Flow'));
    }

    @IsTest
    static void notTranslatablePath_persistsReason() {
        Test.setMock(HttpCalloutMock.class, new ApexMock(true, 'public class Bar { void f() { try {} catch(Exception e) {} } }'));
        EinsteinPromptClient.instance = new EinsteinPromptClient.MockClient(REFUSAL_RESPONSE);

        Test.startTest();
        ApexToFlowService.MigrationResult r = ApexToFlowService.migrate('Bar');
        Test.stopTest();

        Assert.areEqual('NotTranslatable', r.status);
        Assert.isTrue(r.refusalReason.contains('Map<Id, SObject>'));

        FlowMigration__c rec = [
            SELECT Status__c, Error_Message__c
            FROM FlowMigration__c WHERE Id = :r.migrationId
        ];
        Assert.areEqual('Failed', rec.Status__c);
        Assert.isTrue(rec.Error_Message__c.startsWith('Not translatable:'));
    }

    @IsTest
    static void apexNotFound_failsCleanly() {
        Test.setMock(HttpCalloutMock.class, new ApexMock(false, null));

        Test.startTest();
        ApexToFlowService.MigrationResult r = ApexToFlowService.migrate('Missing');
        Test.stopTest();

        Assert.areEqual('Failed', r.status);
        FlowMigration__c rec = [SELECT Error_Message__c FROM FlowMigration__c WHERE Id = :r.migrationId];
        Assert.isTrue(rec.Error_Message__c.contains('Apex class not found'));
    }

    private class ApexMock implements HttpCalloutMock {
        private Boolean exists; private String body;
        public ApexMock(Boolean e, String b) { this.exists = e; this.body = b; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type','application/json');
            r.setBody(exists
                ? '{"records":[{"Id":"01pxx001","Name":"X","Body":' + JSON.serialize(body) + '}]}'
                : '{"records":[]}');
            return r;
        }
    }
}
