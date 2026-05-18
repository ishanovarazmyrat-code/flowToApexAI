@IsTest
private class FlowReaderServiceTest {

    @IsTest
    static void blankApiName_throws() {
        try { FlowReaderService.getFlowMetadata(''); Assert.fail(); }
        catch (FlowReaderService.FlowReaderException e) {
            Assert.areEqual('Flow API name is required.', e.getMessage());
        }
    }

    @IsTest
    static void validFlow_returnsPrunedJson() {
        Test.setMock(HttpCalloutMock.class, new ApiMock('Account_Set_Default_Industry', true));
        Test.startTest();
        String json = FlowReaderService.getFlowMetadata('Account_Set_Default_Industry');
        Test.stopTest();
        Assert.isTrue(json.contains('Account_Set_Default_Industry'));
        Assert.isTrue(json.contains('processType'));
        Assert.isFalse(json.contains('processMetadataValues'), 'Ignored key should be pruned');
        Assert.isFalse(json.contains('"waits"'), 'Empty array should be pruned');
    }

    @IsTest
    static void unknownFlow_throws() {
        Test.setMock(HttpCalloutMock.class, new ApiMock('Unknown', false));
        Test.startTest();
        try { FlowReaderService.getFlowMetadata('Unknown'); Assert.fail(); }
        catch (FlowReaderService.FlowReaderException e) {
            Assert.isTrue(e.getMessage().contains('Flow not found'));
        }
        Test.stopTest();
    }

    @IsTest
    static void inactiveFlow_throws() {
        Test.setMock(HttpCalloutMock.class, new InactiveMock());
        Test.startTest();
        try { FlowReaderService.getFlowMetadata('Inactive'); Assert.fail(); }
        catch (FlowReaderService.FlowReaderException e) {
            Assert.isTrue(e.getMessage().contains('no active version'));
        }
        Test.stopTest();
    }

    @IsTest
    static void http500_throws() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        Test.startTest();
        try { FlowReaderService.getFlowMetadata('Any'); Assert.fail(); }
        catch (FlowReaderService.FlowReaderException e) {
            Assert.isTrue(e.getMessage().contains('HTTP 500'));
        }
        Test.stopTest();
    }

    @IsTest
    static void flowVersionMissing_throws() {
        Test.setMock(HttpCalloutMock.class, new MissingVersionMock());
        Test.startTest();
        try { FlowReaderService.getFlowMetadata('Stale'); Assert.fail(); }
        catch (FlowReaderService.FlowReaderException e) {
            Assert.isTrue(e.getMessage().contains('Active Flow version metadata unavailable'));
        }
        Test.stopTest();
    }

    @IsTest
    static void nullMetadata_throws() {
        Test.setMock(HttpCalloutMock.class, new NullMetaMock());
        Test.startTest();
        try { FlowReaderService.getFlowMetadata('Empty'); Assert.fail(); }
        catch (FlowReaderService.FlowReaderException e) {
            Assert.isTrue(e.getMessage().contains('Flow Metadata is empty'));
        }
        Test.stopTest();
    }

    private class ApiMock implements HttpCalloutMock {
        private String flowName;
        private Boolean exists;
        public ApiMock(String n, Boolean e) { this.flowName = n; this.exists = e; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type','application/json');
            String ep = req.getEndpoint();
            Boolean isDef = ep.contains('FROM+FlowDefinition') || ep.contains('FROM%20FlowDefinition');
            if (isDef) {
                r.setBody(exists
                    ? '{"records":[{"Id":"301xx001","DeveloperName":"' + flowName + '","ActiveVersionId":"301xx002"}]}'
                    : '{"records":[]}');
            } else {
                r.setBody('{"records":[{"Id":"301xx002","MasterLabel":"' + flowName +
                    '","Metadata":{"label":"' + flowName +
                    '","processType":"AutoLaunchedFlow","status":"Active",' +
                    '"waits":[],"variables":[],' +
                    '"processMetadataValues":[{"name":"BuilderType","value":{"stringValue":"LightningFlowBuilder"}}],' +
                    '"start":{"object":"Account","triggerType":"RecordBeforeSave","filters":[]},' +
                    '"decisions":[{"name":"Check","label":"Check","rules":[]}]}}]}');
            }
            return r;
        }
    }
    private class InactiveMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type','application/json');
            r.setBody('{"records":[{"Id":"301xx001","DeveloperName":"Inactive","ActiveVersionId":null}]}');
            return r;
        }
    }
    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse(); r.setStatusCode(500); r.setBody('err');
            return r;
        }
    }
    private class MissingVersionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type','application/json');
            String ep = req.getEndpoint();
            Boolean isDef = ep.contains('FROM+FlowDefinition') || ep.contains('FROM%20FlowDefinition');
            r.setBody(isDef
                ? '{"records":[{"Id":"301xx001","DeveloperName":"Stale","ActiveVersionId":"301xx002"}]}'
                : '{"records":[]}');
            return r;
        }
    }
    private class NullMetaMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type','application/json');
            String ep = req.getEndpoint();
            Boolean isDef = ep.contains('FROM+FlowDefinition') || ep.contains('FROM%20FlowDefinition');
            r.setBody(isDef
                ? '{"records":[{"Id":"301xx001","DeveloperName":"Empty","ActiveVersionId":"301xx002"}]}'
                : '{"records":[{"Id":"301xx002","MasterLabel":"Empty","Metadata":null}]}');
            return r;
        }
    }
}
