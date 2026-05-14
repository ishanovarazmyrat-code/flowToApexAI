/**
 * @description Invokes the `Flow_To_Apex_Converter` Prompt Template via the
 *              Einstein Generative AI service and returns the generated Apex.
 *
 *              Returns a structured result split into trigger code and handler
 *              code by parsing the `===TRIGGER===` and `===HANDLER===` markers
 *              that the prompt asks the model to emit.
 *
 * @usage
 *   EinsteinPromptClient.GeneratedApex result =
 *       EinsteinPromptClient.generate('{"label":"...","start":{...},...}');
 *   String triggerCode = result.triggerCode;
 *   String handlerCode = result.handlerCode;
 */
public with sharing virtual class EinsteinPromptClient {

    private static final String TEMPLATE_API_NAME = 'Flow_To_Apex_Converter';
    private static final String INPUT_KEY        = 'Input:flowMetadata';
    private static final String TRIGGER_MARKER   = '===TRIGGER===';
    private static final String HANDLER_MARKER   = '===HANDLER===';

    /** Container returned to callers — split into the two Apex artifacts. */
    public class GeneratedApex {
        public String triggerCode;
        public String handlerCode;
        public String rawResponse;
    }

    public class EinsteinClientException extends Exception {}

    /** Test seam — replace with a stub in tests via the inner MockClient class. */
    @TestVisible
    private static EinsteinPromptClient instance = new EinsteinPromptClient();

    /** Static entry point. */
    public static GeneratedApex generate(String flowMetadataJson) {
        if (String.isBlank(flowMetadataJson)) {
            throw new EinsteinClientException('Flow metadata JSON is required.');
        }
        String raw = instance.invokePromptTemplate(flowMetadataJson);
        return parseResponse(raw);
    }

    /** Invokes the Prompt Template. Virtual so tests can subclass. */
    @TestVisible
    protected virtual String invokePromptTemplate(String flowMetadataJson) {
        try {
            ConnectApi.WrappedValue wrappedValue = new ConnectApi.WrappedValue();
            wrappedValue.value = flowMetadataJson;

            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.inputParams = new Map<String, ConnectApi.WrappedValue>{
                INPUT_KEY => wrappedValue
            };
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptBuilderPreview';
            input.isPreview = false;

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    TEMPLATE_API_NAME, input
                );

            if (result == null || result.generations == null || result.generations.isEmpty()) {
                throw new EinsteinClientException('No response returned from prompt template.');
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

    /**
     * Splits the raw model response into trigger and handler portions
     * using the markers the prompt instructs the model to emit.
     */
    private static GeneratedApex parseResponse(String raw) {
        GeneratedApex out = new GeneratedApex();
        out.rawResponse = raw;

        if (String.isBlank(raw)) {
            throw new EinsteinClientException('Empty model response.');
        }

        Integer trigIdx    = raw.indexOf(TRIGGER_MARKER);
        Integer handlerIdx = raw.indexOf(HANDLER_MARKER);

        if (trigIdx < 0 || handlerIdx < 0 || handlerIdx <= trigIdx) {
            throw new EinsteinClientException(
                'Model response missing expected markers (===TRIGGER=== / ===HANDLER===). ' +
                'Raw response (first 500 chars): ' +
                raw.substring(0, Math.min(500, raw.length()))
            );
        }

        out.triggerCode = raw.substring(trigIdx + TRIGGER_MARKER.length(), handlerIdx).trim();
        out.handlerCode = raw.substring(handlerIdx + HANDLER_MARKER.length()).trim();

        if (String.isBlank(out.triggerCode) || String.isBlank(out.handlerCode)) {
            throw new EinsteinClientException(
                'Model response had markers but one of the sections is empty.'
            );
        }
        return out;
    }

    /** ---- Test stub helper ---- */
    @TestVisible
    public class MockClient extends EinsteinPromptClient {
        public String stubbedResponse;
        public MockClient(String stubbedResponse) {
            this.stubbedResponse = stubbedResponse;
        }
        protected override String invokePromptTemplate(String flowMetadataJson) {
            return this.stubbedResponse;
        }
    }
}
