@IsTest
private class FlowToApexServiceTest {

    private static final String VALID_RESPONSE =
        '===OBJECT===\nAccount\n' +
        '===HANDLER===\n' +
        'public with sharing class AccountSetDefaultIndustryHandler {\n' +
        '    public static void run(System.TriggerOperation op, List<Account> records, Map<Id, Account> oldMap) {\n' +
        '        if (op != System.TriggerOperation.BEFORE_INSERT) return;\n' +
        '        for (Account record : records) if (record.Industry == null) record.Industry = \'Other\';\n' +
        '    }\n' +
        '}\n' +
        '===DISPATCHER===\n' +
        'AccountSetDefaultIndustryHandler.run(op, records, oldMap);';

    @IsTest
    static void blankName_fails() {
        Test.startTest();
        FlowToApexService.MigrationResult r = FlowToApexService.migrate('');
        Test.stopTest();
        Assert.areEqual('Failed', r.status);
        Assert.areEqual('Flow API name is required.', r.errorMessage);
    }

    @IsTest
    static void successPath_persistsRecord() {
        Test.setMock(HttpCalloutMock.class, new ToolingMock(true));
        EinsteinPromptClient.instance = new EinsteinPromptClient.MockClient(VALID_RESPONSE);

        Test.startTest();
        FlowToApexService.MigrationResult r =
            FlowToApexService.migrate('Account_Set_Default_Industry');
        Test.stopTest();

        Assert.areEqual('Generated', r.status);
        Assert.areEqual('Account', r.objectName);
        Assert.isTrue(r.handlerCode.contains('AccountSetDefaultIndustryHandler'));

        FlowMigration__c rec = [
            SELECT Source_Flow_Name__c, Direction__c, Object_Name__c,
                   Status__c, Generated_Apex__c
            FROM FlowMigration__c
            WHERE Id = :r.migrationId
        ];
        Assert.areEqual('Flow_To_Apex', rec.Direction__c);
        Assert.areEqual('Account', rec.Object_Name__c);
        Assert.areEqual('Generated', rec.Status__c);
        Assert.isTrue(rec.Generated_Apex__c.contains('AccountSetDefaultIndustryHandler'));
        Assert.isTrue(rec.Generated_Apex__c.contains('Register this handler'));
    }

    @IsTest
    static void flowNotFound_failsCleanly() {
        Test.setMock(HttpCalloutMock.class, new ToolingMock(false));

        Test.startTest();
        FlowToApexService.MigrationResult r =
            FlowToApexService.migrate('Nonexistent_Flow');
        Test.stopTest();

        Assert.areEqual('Failed', r.status);
        FlowMigration__c rec = [SELECT Status__c, Error_Message__c FROM FlowMigration__c WHERE Id = :r.migrationId];
        Assert.areEqual('Failed', rec.Status__c);
        Assert.isTrue(rec.Error_Message__c.contains('Flow not found'));
    }

    @IsTest
    static void einsteinReturnsGibberish_failsCleanly() {
        Test.setMock(HttpCalloutMock.class, new ToolingMock(true));
        EinsteinPromptClient.instance = new EinsteinPromptClient.MockClient('I cannot help.');

        Test.startTest();
        FlowToApexService.MigrationResult r =
            FlowToApexService.migrate('Account_Set_Default_Industry');
        Test.stopTest();

        Assert.areEqual('Failed', r.status);
        FlowMigration__c rec = [SELECT Error_Message__c FROM FlowMigration__c WHERE Id = :r.migrationId];
        Assert.isTrue(rec.Error_Message__c.contains('===HANDLER==='));
    }

    private class ToolingMock implements HttpCalloutMock {
        private Boolean exists;
        public ToolingMock(Boolean e) { this.exists = e; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type','application/json');
            String ep = req.getEndpoint();
            Boolean isDef = ep.contains('FROM+FlowDefinition') || ep.contains('FROM%20FlowDefinition');
            if (isDef) {
                r.setBody(exists
                    ? '{"records":[{"Id":"301xx001","DeveloperName":"X","ActiveVersionId":"301xx002"}]}'
                    : '{"records":[]}');
            } else {
                r.setBody('{"records":[{"Id":"301xx002","MasterLabel":"X","Metadata":{"label":"X","processType":"AutoLaunchedFlow","status":"Active","start":{"object":"Account","triggerType":"RecordBeforeSave"}}}]}');
            }
            return r;
        }
    }
}
