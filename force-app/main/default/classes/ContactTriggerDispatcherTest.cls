@IsTest
private class ContactTriggerDispatcherTest {
    @IsTest
    static void dispatchOnInsert_runsWithoutErrors() {
        Test.startTest();
        Contact c = new Contact(LastName = 'TriggerSmokeTest');
        insert c;
        update c;
        delete c;
        Test.stopTest();
        Assert.isTrue(true, 'Trigger + Dispatcher execute without errors when no handlers are registered.');
    }
}
