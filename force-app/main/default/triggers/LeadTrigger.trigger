// =========================================================================
// LeadTrigger
// One trigger per object. Delegates to LeadTriggerDispatcher which calls
// every registered handler in order. Add handlers in the dispatcher, never
// here. This file should not change as new Flows are converted.
// =========================================================================
trigger LeadTrigger on Lead (
    before insert, before update, before delete,
    after insert,  after update,  after delete
) {
    LeadTriggerDispatcher.dispatch(
        Trigger.operationType,
        Trigger.new,
        Trigger.oldMap
    );
}
