@IsTest
private class FlowReaderServiceTest {

    @IsTest
    static void blankApiName_throws() {
        try {
            FlowReaderService.getFlowMetadata('');
            Assert.fail('Expected exception');
        } catch (FlowReaderService.FlowReaderException e) {
            Assert.areEqual('Flow API name is required.', e.getMessage());
        }
    }

    @IsTest
    static void validFlow_returnsMetadataJson() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock('Account_Set_Default_Industry', true));
        Test.startTest();
        String json = FlowReaderService.getFlowMetadata('Account_Set_Default_Industry');
        Test.stopTest();
        Assert.isNotNull(json);
        Assert.isTrue(json.contains('Account_Set_Default_Industry'));
        Assert.isTrue(json.contains('processType'));
    }

    @IsTest
    static void unknownFlow_throws() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMock('Unknown_Flow', false));
        Test.startTest();
        try {
            FlowReaderService.getFlowMetadata('Unknown_Flow');
            Assert.fail();
        } catch (FlowReaderService.FlowReaderException e) {
            Assert.isTrue(e.getMessage().contains('Flow not found'));
        }
        Test.stopTest();
    }

    @IsTest
    static void inactiveFlow_throws() {
        Test.setMock(HttpCalloutMock.class, new InactiveFlowMock());
        Test.startTest();
        try {
            FlowReaderService.getFlowMetadata('Inactive_Flow');
            Assert.fail();
        } catch (FlowReaderService.FlowReaderException e) {
            Assert.isTrue(e.getMessage().contains('no active version'));
        }
        Test.stopTest();
    }

    @IsTest
    static void http500_throws() {
        Test.setMock(HttpCalloutMock.class, new HttpErrorMock());
        Test.startTest();
        try {
            FlowReaderService.getFlowMetadata('Any_Flow');
            Assert.fail();
        } catch (FlowReaderService.FlowReaderException e) {
            Assert.isTrue(e.getMessage().contains('HTTP 500'));
        }
        Test.stopTest();
    }

    @IsTest
    static void flowVersionMissing_throws() {
        Test.setMock(HttpCalloutMock.class, new MissingVersionMock());
        Test.startTest();
        try {
            FlowReaderService.getFlowMetadata('Stale_Flow');
            Assert.fail();
        } catch (FlowReaderService.FlowReaderException e) {
            Assert.isTrue(e.getMessage().contains('Active Flow version metadata unavailable'));
        }
        Test.stopTest();
    }

    @IsTest
    static void nullMetadata_throws() {
        Test.setMock(HttpCalloutMock.class, new NullMetadataMock());
        Test.startTest();
        try {
            FlowReaderService.getFlowMetadata('Empty_Meta_Flow');
            Assert.fail();
        } catch (FlowReaderService.FlowReaderException e) {
            Assert.isTrue(e.getMessage().contains('Flow Metadata is empty'));
        }
        Test.stopTest();
    }

    // ----- mocks -----

    private class ToolingApiMock implements HttpCalloutMock {
        private String flowName; private Boolean exists;
        public ToolingApiMock(String flowName, Boolean exists) {
            this.flowName = flowName; this.exists = exists;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type','application/json');
            String ep = req.getEndpoint();
            Boolean isDef = ep.contains('FROM+FlowDefinition') || ep.contains('FROM%20FlowDefinition');
            if (isDef) {
                res.setBody(exists
                    ? '{"records":[{"Id":"301xx0000000001","DeveloperName":"'+flowName+'","ActiveVersionId":"301xx0000000002"}]}'
                    : '{"records":[]}');
            } else {
                res.setBody('{"records":[{"Id":"301xx0000000002","MasterLabel":"'+flowName+'","Metadata":{"label":"'+flowName+'","processType":"AutoLaunchedFlow","status":"Active"}}]}');
            }
            return res;
        }
    }

    private class InactiveFlowMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200); res.setHeader('Content-Type','application/json');
            res.setBody('{"records":[{"Id":"301xx0000000001","DeveloperName":"Inactive_Flow","ActiveVersionId":null}]}');
            return res;
        }
    }

    private class HttpErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"server failure"}');
            return res;
        }
    }

    private class MissingVersionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200); res.setHeader('Content-Type','application/json');
            String ep = req.getEndpoint();
            Boolean isDef = ep.contains('FROM+FlowDefinition') || ep.contains('FROM%20FlowDefinition');
            // FlowDefinition returns a valid version Id, but Flow query returns empty records
            res.setBody(isDef
                ? '{"records":[{"Id":"301xx0000000001","DeveloperName":"Stale_Flow","ActiveVersionId":"301xx0000000002"}]}'
                : '{"records":[]}');
            return res;
        }
    }

    private class NullMetadataMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200); res.setHeader('Content-Type','application/json');
            String ep = req.getEndpoint();
            Boolean isDef = ep.contains('FROM+FlowDefinition') || ep.contains('FROM%20FlowDefinition');
            res.setBody(isDef
                ? '{"records":[{"Id":"301xx0000000001","DeveloperName":"Empty_Meta_Flow","ActiveVersionId":"301xx0000000002"}]}'
                : '{"records":[{"Id":"301xx0000000002","MasterLabel":"Empty","Metadata":null}]}');
            return res;
        }
    }
}