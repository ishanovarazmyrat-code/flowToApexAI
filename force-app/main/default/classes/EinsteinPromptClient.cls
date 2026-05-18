/**
 * @description Generic Einstein Prompt Template invoker.
 *              Calls any Prompt Builder template by API name with the given input
 *              variables and returns the raw model response text. Each calling
 *              service parses the response in its own format.
 *
 *              Test seam: EinsteinPromptClient.instance can be swapped with the
 *              inner MockClient for unit tests so callers can simulate any
 *              response without hitting ConnectApi.
 */
public with sharing virtual class EinsteinPromptClient {

    public class EinsteinClientException extends Exception {}

    @TestVisible
    private static EinsteinPromptClient instance = new EinsteinPromptClient();

    public static String invoke(String templateApiName, Map<String, String> inputs) {
        return instance.callTemplate(templateApiName, inputs);
    }

    @TestVisible
    protected virtual String callTemplate(String templateApiName, Map<String, String> inputs) {
        if (String.isBlank(templateApiName)) {
            throw new EinsteinClientException('Prompt template API name is required.');
        }
        try {
            Map<String, ConnectApi.WrappedValue> params = new Map<String, ConnectApi.WrappedValue>();
            if (inputs != null) {
                for (String key : inputs.keySet()) {
                    ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
                    wrapped.value = inputs.get(key);
                    params.put('Input:' + key, wrapped);
                }
            }

            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.inputParams = params;
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptBuilderPreview';
            input.isPreview = false;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    templateApiName, input
                );

            if (result == null || result.generations == null || result.generations.isEmpty()) {
                throw new EinsteinClientException(
                    'No response from prompt template: ' + templateApiName
                );
            }
            return result.generations[0].text;
        } catch (EinsteinClientException e) {
            throw e;
        } catch (Exception e) {
            throw new EinsteinClientException(
                'Einstein invocation failed: ' + e.getMessage()
            );
        }
    }

    @TestVisible
    public class MockClient extends EinsteinPromptClient {
        public String stubbedResponse;
        public MockClient(String response) {
            this.stubbedResponse = response;
        }
        protected override String callTemplate(String templateApiName, Map<String, String> inputs) {
            return this.stubbedResponse;
        }
    }
}
