@IsTest
private class FlowToApexServiceTest {

    // Handler code now implements IFlowMigrationHandler (instance method, not static)
    private static final String VALID_RESPONSE =
        '===OBJECT===\nAccount\n' +
        '===HANDLER===\n' +
        'public with sharing class AccountSetDefaultIndustryHandler implements IFlowMigrationHandler {\n' +
        '    public void run(System.TriggerOperation op, List<SObject> records, Map<Id, SObject> oldMap) {\n' +
        '        if (op != System.TriggerOperation.BEFORE_INSERT) return;\n' +
        '        for (SObject sObj : records) {\n' +
        '            Account record = (Account) sObj;\n' +
        '            if (record.Industry == null) record.Industry = \'Other\';\n' +
        '        }\n' +
        '    }\n' +
        '}\n' +
        '===DISPATCHER===\n' +
        'AccountSetDefaultIndustryHandler registered via Trigger_Handler__mdt.';

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
                   Status__c, Generated_Apex__c, Deploy_Status__c
            FROM FlowMigration__c
            WHERE Id = :r.migrationId
        ];
        Assert.areEqual('Flow_To_Apex',    rec.Direction__c);
        Assert.areEqual('Account',         rec.Object_Name__c);
        Assert.areEqual('Generated',       rec.Status__c);
        Assert.isTrue(rec.Generated_Apex__c.contains('AccountSetDefaultIndustryHandler'));
        // In test context ApexDeployService skips the CMT enqueue but the class deploy
        // callout is handled by ToolingMock — status should be Deployed.
        Assert.areEqual('Deployed', rec.Deploy_Status__c);
        Assert.areEqual('Deployed', r.deployStatus);
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

    // -------------------------------------------------------------------------
    // Mock: handles FlowDefinition query, Flow metadata query, ApexClass check,
    //       and ApexClass create — all via a single HttpCalloutMock.
    // -------------------------------------------------------------------------
    private class ToolingMock implements HttpCalloutMock {
        private final Boolean flowExists;
        public ToolingMock(Boolean flowExists) { this.flowExists = flowExists; }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type', 'application/json');

            String ep     = req.getEndpoint();
            String method = req.getMethod();

            // POST → create ApexClass
            if (method == 'POST' && ep.contains('/tooling/sobjects/ApexClass')) {
                r.setBody('{"id":"01pxx000000FAKE","success":true,"errors":[]}');
                r.setStatusCode(201);
                return r;
            }

            // GET queries (all use /tooling/query/)
            Boolean isFlowDef  = ep.contains('FROM+FlowDefinition')  || ep.contains('FROM%20FlowDefinition');
            Boolean isApexClass = ep.contains('FROM+ApexClass')       || ep.contains('FROM%20ApexClass');

            if (isFlowDef) {
                r.setBody(flowExists
                    ? '{"records":[{"Id":"301xx001","DeveloperName":"X","ActiveVersionId":"301xx002"}]}'
                    : '{"records":[]}');
            } else if (isApexClass) {
                // Simulate class not yet existing → dispatcher will create it
                r.setBody('{"totalSize":0,"done":true,"records":[]}');
            } else {
                // Flow version metadata
                r.setBody('{"records":[{"Id":"301xx002","MasterLabel":"X","Metadata":{"label":"X","processType":"AutoLaunchedFlow","status":"Active","start":{"object":"Account","triggerType":"RecordBeforeSave"}}}]}');
            }
            return r;
        }
    }
}
