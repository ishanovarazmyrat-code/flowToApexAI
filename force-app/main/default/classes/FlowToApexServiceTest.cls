@IsTest
private class FlowToApexServiceTest {

    private static final String VALID_EINSTEIN_RESPONSE =
        '===TRIGGER===\n' +
        'trigger AccountTrigger on Account (before insert) {\n' +
        '    AccountSetDefaultIndustryHandler.beforeSave(Trigger.new);\n' +
        '}\n' +
        '===HANDLER===\n' +
        'public with sharing class AccountSetDefaultIndustryHandler {\n' +
        '    public static void beforeSave(List<Account> records) {\n' +
        '        for (Account record : records) {\n' +
        '            if (record.Industry == null) {\n' +
        '                record.Industry = \'Other\';\n' +
        '            }\n' +
        '        }\n' +
        '    }\n' +
        '}';

    @IsTest
    static void blankFlowName_returnsFailedResult() {
        Test.startTest();
        FlowToApexService.MigrationResult result = FlowToApexService.migrate('');
        Test.stopTest();

        Assert.areEqual('Failed', result.status);
        Assert.areEqual('Flow API name is required.', result.errorMessage);
        Assert.isNull(result.migrationId);
    }

    @IsTest
    static void successfulMigration_recordCreatedWithGeneratedApex() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock(true));
        EinsteinPromptClient.instance = new EinsteinPromptClient.MockClient(VALID_EINSTEIN_RESPONSE);

        Test.startTest();
        FlowToApexService.MigrationResult result =
            FlowToApexService.migrate('Account_Set_Default_Industry');
        Test.stopTest();

        Assert.areEqual('Generated', result.status);
        Assert.isNotNull(result.migrationId);

        FlowMigration__c record = [
            SELECT Source_Flow_Name__c, 
                   Generated_Apex__c, Status__c, Error_Message__c
            FROM FlowMigration__c
            WHERE Id = :result.migrationId
        ];

        Assert.areEqual('Account_Set_Default_Industry', record.Source_Flow_Name__c);
        Assert.areEqual('Generated', record.Status__c);
        Assert.isTrue(record.Generated_Apex__c.contains('AccountSetDefaultIndustryHandler'));
        Assert.isTrue(record.Generated_Apex__c.contains('TRIGGER'));
        Assert.isNull(record.Error_Message__c);
    }

    @IsTest
    static void flowNotFound_recordsFailed() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock(false));

        Test.startTest();
        FlowToApexService.MigrationResult result =
            FlowToApexService.migrate('Nonexistent_Flow');
        Test.stopTest();

        Assert.areEqual('Failed', result.status);
        Assert.isNotNull(result.migrationId);

        FlowMigration__c record = [
            SELECT Status__c, Error_Message__c
            FROM FlowMigration__c
            WHERE Id = :result.migrationId
        ];
        Assert.areEqual('Failed', record.Status__c);
        Assert.isTrue(record.Error_Message__c.contains('Flow not found'));
    }

    @IsTest
    static void einsteinReturnsGibberish_recordsFailed() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock(true));
        EinsteinPromptClient.instance = new EinsteinPromptClient.MockClient(
            'Sorry, I cannot help with that request.'
        );

        Test.startTest();
        FlowToApexService.MigrationResult result =
            FlowToApexService.migrate('Account_Set_Default_Industry');
        Test.stopTest();

        Assert.areEqual('Failed', result.status);

        FlowMigration__c record = [
            SELECT Status__c, Error_Message__c
            FROM FlowMigration__c
            WHERE Id = :result.migrationId
        ];
        Assert.areEqual('Failed', record.Status__c);
        Assert.isTrue(record.Error_Message__c.contains('missing expected markers'));
    }

    // ----- mock -----

    private class ToolingApiMock implements HttpCalloutMock {
        private Boolean exists;
        public ToolingApiMock(Boolean exists) {
            this.exists = exists;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String endpoint = req.getEndpoint();
            Boolean isDefQuery = endpoint.contains('FROM+FlowDefinition')
                || endpoint.contains('FROM%20FlowDefinition');

            if (isDefQuery) {
                if (exists) {
                    res.setBody(
                        '{"records":[{"Id":"301xx0000000001",' +
                        '"DeveloperName":"Account_Set_Default_Industry",' +
                        '"ActiveVersionId":"301xx0000000002"}]}'
                    );
                } else {
                    res.setBody('{"records":[]}');
                }
            } else {
                res.setBody(
                    '{"records":[{"Id":"301xx0000000002",' +
                    '"MasterLabel":"Account Set Default Industry",' +
                    '"Metadata":{"label":"Account Set Default Industry",' +
                    '"processType":"AutoLaunchedFlow","status":"Active"}}]}'
                );
            }
            return res;
        }
    }
}
