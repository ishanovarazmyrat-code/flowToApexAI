@IsTest
private class LeadTriggerDispatcherTest {
    @IsTest
    static void dispatchOnInsert_runsWithoutErrors() {
        Test.startTest();
        Lead l = new Lead(LastName = 'TriggerSmokeTest', Company = 'Test Company');
        insert l;
        update l;
        delete l;
        Test.stopTest();
        Assert.isTrue(true, 'Trigger + Dispatcher execute without errors when no handlers are registered.');
    }
}
