/**
 * @description Tests for EinsteinPromptClient.
 *              Uses the MockClient seam so tests don't hit Einstein/ConnectApi.
 *              Validates blank-input handling, successful parsing, and marker errors.
 */
@IsTest
private class EinsteinPromptClientTest {

    private static final String VALID_RESPONSE =
        '===TRIGGER===\n' +
        'trigger AccountTrigger on Account (before insert) {\n' +
        '    AccountFooHandler.beforeSave(Trigger.new);\n' +
        '}\n' +
        '===HANDLER===\n' +
        'public with sharing class AccountFooHandler {\n' +
        '    public static void beforeSave(List<Account> records) {\n' +
        '        for (Account record : records) {\n' +
        '            record.Industry = \'Other\';\n' +
        '        }\n' +
        '    }\n' +
        '}';

    @IsTest
    static void blankInput_throws() {
        try {
            EinsteinPromptClient.generate('');
            Assert.fail('Expected EinsteinClientException for blank input');
        } catch (EinsteinPromptClient.EinsteinClientException e) {
            Assert.areEqual('Flow metadata JSON is required.', e.getMessage());
        }
    }

    @IsTest
    static void validResponse_parsesIntoTriggerAndHandler() {
        EinsteinPromptClient.instance = new EinsteinPromptClient.MockClient(VALID_RESPONSE);

        Test.startTest();
        EinsteinPromptClient.GeneratedApex result =
            EinsteinPromptClient.generate('{"label":"Test","start":{}}');
        Test.stopTest();

        Assert.isNotNull(result.triggerCode, 'Trigger code should be populated');
        Assert.isNotNull(result.handlerCode, 'Handler code should be populated');
        Assert.isTrue(result.triggerCode.contains('trigger AccountTrigger'),
            'Trigger code should contain the trigger declaration');
        Assert.isTrue(result.handlerCode.contains('AccountFooHandler'),
            'Handler code should contain the handler class declaration');
        Assert.areEqual(VALID_RESPONSE, result.rawResponse,
            'Raw response should be preserved');
    }

    @IsTest
    static void missingMarkers_throws() {
        EinsteinPromptClient.instance = new EinsteinPromptClient.MockClient(
            'Sorry, I cannot help with that.'
        );

        Test.startTest();
        try {
            EinsteinPromptClient.generate('{"label":"Test"}');
            Assert.fail('Expected EinsteinClientException for missing markers');
        } catch (EinsteinPromptClient.EinsteinClientException e) {
            Assert.isTrue(e.getMessage().contains('missing expected markers'),
                'Error should mention missing markers');
        }
        Test.stopTest();
    }

    @IsTest
    static void emptySectionAfterMarkers_throws() {
        EinsteinPromptClient.instance = new EinsteinPromptClient.MockClient(
            '===TRIGGER===\n\n===HANDLER===\npublic class X {}'
        );

        Test.startTest();
        try {
            EinsteinPromptClient.generate('{"label":"Test"}');
            Assert.fail('Expected EinsteinClientException for empty section');
        } catch (EinsteinPromptClient.EinsteinClientException e) {
            Assert.isTrue(e.getMessage().contains('one of the sections is empty'),
                'Error should mention empty section');
        }
        Test.stopTest();
    }

    @IsTest
    static void invertedMarkers_throws() {
        EinsteinPromptClient.instance = new EinsteinPromptClient.MockClient(
            '===HANDLER===\npublic class X {}\n===TRIGGER===\ntrigger Y on Z (before insert) {}'
        );

        Test.startTest();
        try {
            EinsteinPromptClient.generate('{"label":"Test"}');
            Assert.fail('Expected EinsteinClientException for inverted markers');
        } catch (EinsteinPromptClient.EinsteinClientException e) {
            Assert.isTrue(e.getMessage().contains('missing expected markers'),
                'Error should mention missing markers when order is wrong');
        }
        Test.stopTest();
    }
}
