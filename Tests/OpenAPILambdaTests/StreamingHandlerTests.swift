//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift OpenAPI Lambda open source project
//
// Copyright Swift OpenAPI Lambda project authors
// Copyright (c) 2025 Amazon.com, Inc. or its affiliates.
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift OpenAPI Lambda project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation
import HTTPTypes
import Logging
import NIOCore
import OpenAPIRuntime
import Testing

@testable import OpenAPILambda

struct StreamingHandlerTests {

    // MARK: - Test fixtures

    /// Records every interaction with the writer for later assertion.
    /// Status/headers writes are detected via `hasCustomHeaders: true` and recorded
    /// separately from body chunks.
    final class SpyResponseStreamWriter: LambdaResponseStreamWriter, @unchecked Sendable {
        private(set) var statusBuffer: ByteBuffer?
        private(set) var bodyChunks: [ByteBuffer] = []
        private(set) var didFinish = false

        func write(_ buffer: ByteBuffer, hasCustomHeaders: Bool) async throws {
            if hasCustomHeaders {
                self.statusBuffer = buffer
            }
            else {
                self.bodyChunks.append(buffer)
            }
        }

        func finish() async throws { self.didFinish = true }

        func writeAndFinish(_ buffer: ByteBuffer) async throws {
            self.bodyChunks.append(buffer)
            self.didFinish = true
        }

        /// Concatenated body bytes across all chunks, for whole-payload assertions.
        var bodyString: String {
            self.bodyChunks.map { $0.getString(at: $0.readerIndex, length: $0.readableBytes) ?? "" }
                .joined()
        }

        /// Decoded headers struct, extracted from the eight-null-byte-separated framing.
        var statusAndHeaders: StreamingLambdaStatusAndHeadersResponse? {
            guard let buffer = self.statusBuffer else { return nil }
            let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) ?? []
            let separator: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]
            guard let range = bytes.firstRange(of: separator) else { return nil }
            let jsonBytes = Array(bytes[..<range.lowerBound])
            return try? JSONDecoder().decode(
                StreamingLambdaStatusAndHeadersResponse.self,
                from: Data(jsonBytes)
            )
        }
    }

    /// Streaming service that registers two routes: a buffered `/health` and a streaming
    /// `/numbers/stream` that emits three JSONL lines.
    struct StreamingTestService: OpenAPILambdaStreamingHttpApi {
        func register(transport: OpenAPILambdaTransport) throws {
            try transport.router.add(method: .get, path: "/health") { _, _, _ in
                (HTTPResponse(status: .ok), HTTPBody("OK"))
            }
            try transport.router.add(method: .post, path: "/numbers/stream") { _, _, _ in
                let stream = AsyncStream<ArraySlice<UInt8>> { continuation in
                    continuation.yield(ArraySlice(#"{"value":1}"#.utf8 + [0x0A]))
                    continuation.yield(ArraySlice(#"{"value":2}"#.utf8 + [0x0A]))
                    continuation.yield(ArraySlice(#"{"value":3}"#.utf8 + [0x0A]))
                    continuation.finish()
                }
                var headerFields = HTTPFields()
                headerFields.append(HTTPField(name: .contentType, value: "application/jsonl"))
                let response = HTTPResponse(status: .ok, headerFields: headerFields)
                let body = HTTPBody(stream, length: .unknown, iterationBehavior: .single)
                return (response, body)
            }
        }
    }

    /// JSON for an `APIGatewayV2Request` describing a `POST /numbers/stream` invocation.
    static func eventJSON(method: String, path: String) -> String {
        """
        {
          "rawQueryString": "",
          "headers": {"host": "test.lambda-url.us-east-1.on.aws", "content-type": "application/json"},
          "requestContext": {
            "apiId": "test",
            "http": {
              "sourceIp": "127.0.0.1",
              "userAgent": "test",
              "method": "\(method)",
              "path": "\(path)",
              "protocol": "HTTP/1.1"
            },
            "timeEpoch": 1701957940365,
            "domainPrefix": "test",
            "accountId": "000000000000",
            "time": "07/Dec/2023:14:05:40 +0000",
            "stage": "$default",
            "domainName": "test.lambda-url.us-east-1.on.aws",
            "requestId": "test"
          },
          "isBase64Encoded": false,
          "version": "2.0",
          "routeKey": "$default",
          "rawPath": "\(path)"
        }
        """
    }

    static func makeContext() -> LambdaContext {
        LambdaContext(
            requestID: "test",
            traceID: "test",
            tenantID: nil,
            invokedFunctionARN: "arn:aws:lambda:us-east-1:000000000000:function:test",
            deadline: LambdaClock.maxLambdaDeadline,
            logger: Logger(label: "test")
        )
    }

    // MARK: - Tests

    @Test("Streaming route emits status, three JSONL chunks, and finishes")
    func streamingRouteEmitsChunksThenFinishes() async throws {
        let handler = try OpenAPILambdaStreamingHandler(withService: StreamingTestService())
        let writer = SpyResponseStreamWriter()
        let event = ByteBuffer(string: Self.eventJSON(method: "POST", path: "/numbers/stream"))

        try await handler.handle(event, responseWriter: writer, context: Self.makeContext())

        let statusAndHeaders = writer.statusAndHeaders
        #expect(statusAndHeaders?.statusCode == 200)
        #expect(statusAndHeaders?.headers?["Content-Type"] == "application/jsonl")
        #expect(writer.bodyChunks.count == 3)
        #expect(writer.bodyString == #"{"value":1}"# + "\n" + #"{"value":2}"# + "\n" + #"{"value":3}"# + "\n")
        #expect(writer.didFinish)
    }

    @Test("Buffered route emits status, single chunk, and finishes")
    func bufferedRouteEmitsSingleChunkThenFinishes() async throws {
        let handler = try OpenAPILambdaStreamingHandler(withService: StreamingTestService())
        let writer = SpyResponseStreamWriter()
        let event = ByteBuffer(string: Self.eventJSON(method: "GET", path: "/health"))

        try await handler.handle(event, responseWriter: writer, context: Self.makeContext())

        #expect(writer.statusAndHeaders?.statusCode == 200)
        #expect(writer.bodyChunks.count == 1)
        #expect(writer.bodyString == "OK")
        #expect(writer.didFinish)
    }

    @Test("Unknown path returns 404 with plain-text body")
    func unknownPathReturns404() async throws {
        let handler = try OpenAPILambdaStreamingHandler(withService: StreamingTestService())
        let writer = SpyResponseStreamWriter()
        let event = ByteBuffer(string: Self.eventJSON(method: "GET", path: "/does-not-exist"))

        try await handler.handle(event, responseWriter: writer, context: Self.makeContext())

        #expect(writer.statusAndHeaders?.statusCode == 404)
        #expect(writer.statusAndHeaders?.headers?["Content-Type"] == "text/plain; charset=utf-8")
        #expect(writer.bodyString.contains("/does-not-exist"))
        #expect(writer.didFinish)
    }

    @Test("Malformed event returns 400 with decode error message")
    func malformedEventReturns400() async throws {
        let handler = try OpenAPILambdaStreamingHandler(withService: StreamingTestService())
        let writer = SpyResponseStreamWriter()
        let event = ByteBuffer(string: "not-json")

        try await handler.handle(event, responseWriter: writer, context: Self.makeContext())

        #expect(writer.statusAndHeaders?.statusCode == 400)
        #expect(writer.bodyString.contains("Cannot decode Lambda event"))
        #expect(writer.didFinish)
    }
}
