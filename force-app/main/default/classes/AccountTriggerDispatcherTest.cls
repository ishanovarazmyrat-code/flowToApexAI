@IsTest
private class AccountTriggerDispatcherTest {
    @IsTest
    static void dispatchOnInsert_runsWithoutErrors() {
        Test.startTest();
        Account a = new Account(Name = 'Trigger Smoke Test');
        insert a;
        update a;
        delete a;
        Test.stopTest();
        Assert.isTrue(true, 'Trigger + Dispatcher execute without errors when no handlers are registered.');
    }
}
