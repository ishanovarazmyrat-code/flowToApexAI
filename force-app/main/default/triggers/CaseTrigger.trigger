// =========================================================================
// CaseTrigger
// One trigger per object. Delegates to CaseTriggerDispatcher which calls
// every registered handler in order. Add handlers in the dispatcher, never
// here. This file should not change as new Flows are converted.
// =========================================================================
trigger CaseTrigger on Case (
    before insert, before update, before delete,
    after insert,  after update,  after delete
) {
    CaseTriggerDispatcher.dispatch(
        Trigger.operationType,
        Trigger.new,
        Trigger.oldMap
    );
}
