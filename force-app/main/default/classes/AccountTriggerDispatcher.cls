/**
 * @description Routes Account trigger context to all registered handlers.
 *              Each Flow→Apex conversion produces a separate handler class;
 *              register it by adding ONE line inside dispatch() below.
 *
 *              Each handler's run() method is responsible for filtering by
 *              System.TriggerOperation, so the dispatcher itself stays operation-agnostic.
 */
public with sharing class AccountTriggerDispatcher {

    public static void dispatch(
        System.TriggerOperation op,
        List<Account> records,
        Map<Id, Account> oldMap
    ) {
        // -----------------------------------------------------------------
        // Register handlers below — order matters for before-save handlers
        // when one's output is another's input.
        //
        // Example:
        //   AccountSetDefaultIndustryHandler.run(op, records, oldMap);
        //   AccountSyncPhoneToContactsHandler.run(op, records, oldMap);
        // -----------------------------------------------------------------
        
         AccountSetDefaultIndustryHandler.run(op, records, oldMap);
         AccountSetDescriptionByIndustryHandler.run(op, records, oldMap);
    }
}
