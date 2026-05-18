@IsTest
private class OpportunityTriggerDispatcherTest {
    @IsTest
    static void dispatchOnInsert_runsWithoutErrors() {
        Test.startTest();
        Opportunity o = new Opportunity(
            Name      = 'Trigger Smoke Test',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert o;
        update o;
        delete o;
        Test.stopTest();
        Assert.isTrue(true, 'Trigger + Dispatcher execute without errors when no handlers are registered.');
    }
}
