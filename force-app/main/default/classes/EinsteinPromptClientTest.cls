@IsTest
private class EinsteinPromptClientTest {

    @IsTest
    static void blankTemplateName_throws() {
        try {
            EinsteinPromptClient.invoke('', new Map<String, String>{'x' => 'y'});
            Assert.fail('Expected exception');
        } catch (EinsteinPromptClient.EinsteinClientException e) {
            Assert.areEqual('Prompt template API name is required.', e.getMessage());
        }
    }

    @IsTest
    static void mockReturnsStub() {
        EinsteinPromptClient.instance =
            new EinsteinPromptClient.MockClient('STUB_RESPONSE');

        Test.startTest();
        String out = EinsteinPromptClient.invoke(
            'Any_Template', new Map<String, String>{'k' => 'v'}
        );
        Test.stopTest();

        Assert.areEqual('STUB_RESPONSE', out);
    }

    @IsTest
    static void mockHandlesNullInputs() {
        EinsteinPromptClient.instance =
            new EinsteinPromptClient.MockClient('OK');
        String out = EinsteinPromptClient.invoke('Any_Template', null);
        Assert.areEqual('OK', out);
    }
}
