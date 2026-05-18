@IsTest
private class ApexSourceReaderServiceTest {

    @IsTest
    static void blankName_throws() {
        try { ApexSourceReaderService.getApexBody(''); Assert.fail(); }
        catch (ApexSourceReaderService.ApexReaderException e) {
            Assert.areEqual('Apex class name is required.', e.getMessage());
        }
    }

    @IsTest
    static void validClass_returnsBody() {
        Test.setMock(HttpCalloutMock.class, new Mock(true, 'public class Foo { void bar() {} }'));
        Test.startTest();
        String body = ApexSourceReaderService.getApexBody('Foo');
        Test.stopTest();
        Assert.isTrue(body.contains('public class Foo'));
    }

    @IsTest
    static void unknownClass_throws() {
        Test.setMock(HttpCalloutMock.class, new Mock(false, null));
        Test.startTest();
        try { ApexSourceReaderService.getApexBody('Missing'); Assert.fail(); }
        catch (ApexSourceReaderService.ApexReaderException e) {
            Assert.isTrue(e.getMessage().contains('Apex class not found'));
        }
        Test.stopTest();
    }

    @IsTest
    static void emptyBody_throws() {
        Test.setMock(HttpCalloutMock.class, new EmptyBodyMock());
        Test.startTest();
        try { ApexSourceReaderService.getApexBody('Empty'); Assert.fail(); }
        catch (ApexSourceReaderService.ApexReaderException e) {
            Assert.isTrue(e.getMessage().contains('body is empty'));
        }
        Test.stopTest();
    }

    @IsTest
    static void http500_throws() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        Test.startTest();
        try { ApexSourceReaderService.getApexBody('Any'); Assert.fail(); }
        catch (ApexSourceReaderService.ApexReaderException e) {
            Assert.isTrue(e.getMessage().contains('HTTP 500'));
        }
        Test.stopTest();
    }

    private class Mock implements HttpCalloutMock {
        private Boolean exists; private String body;
        public Mock(Boolean e, String b) { this.exists = e; this.body = b; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200); r.setHeader('Content-Type','application/json');
            r.setBody(exists
                ? '{"records":[{"Id":"01pxx001","Name":"Foo","Body":' + JSON.serialize(body) + '}]}'
                : '{"records":[]}');
            return r;
        }
    }
    private class EmptyBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200); r.setHeader('Content-Type','application/json');
            r.setBody('{"records":[{"Id":"01pxx001","Name":"Empty","Body":""}]}');
            return r;
        }
    }
    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse(); r.setStatusCode(500); r.setBody('err'); return r;
        }
    }
}
