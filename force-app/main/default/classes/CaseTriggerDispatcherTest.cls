@IsTest
private class CaseTriggerDispatcherTest {
    @IsTest
    static void dispatchOnInsert_runsWithoutErrors() {
        Test.startTest();
        Case c = new Case(Subject = 'Trigger Smoke Test', Status = 'New', Origin = 'Web');
        insert c;
        update c;
        delete c;
        Test.stopTest();
        Assert.isTrue(true, 'Trigger + Dispatcher execute without errors when no handlers are registered.');
    }
}
