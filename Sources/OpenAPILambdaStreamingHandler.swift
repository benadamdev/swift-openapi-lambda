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
import Foundation
import AWSLambdaRuntime
import AWSLambdaEvents
import OpenAPIRuntime
import HTTPTypes
import NIOCore

/// Specialization of `StreamingLambdaHandler` which runs an ``OpenAPILambdaStreamingService``.
///
/// For each Lambda invocation, the handler:
/// 1. Decodes the raw `ByteBuffer` event into the service's `Event` type.
/// 2. Translates the event to an ``OpenAPILambdaRequest`` via the service.
/// 3. Looks up the registered handler in the transport's router.
/// 4. Calls the handler and obtains an `(HTTPResponse, HTTPBody?)`.
/// 5. Writes the HTTP status and headers to the response stream.
/// 6. Iterates the response body's async byte sequence and writes each chunk to the stream.
/// 7. Closes the stream.
///
/// Buffered routes (whose `HTTPBody` yields a single chunk) work transparently — the iteration
/// produces one `write` followed by `finish`. Streaming routes (whose `HTTPBody` is an open-ended
/// async sequence) write a chunk per producer iteration.
public struct OpenAPILambdaStreamingHandler<OALS: OpenAPILambdaStreamingService>: StreamingLambdaHandler, Sendable {

    private let transport: OpenAPILambdaTransport
    private let openAPIService: OALS
    private let eventDecoder: LambdaJSONEventDecoder
    private let statusEncoder: LambdaJSONOutputEncoder<StreamingLambdaStatusAndHeadersResponse>

    /// Initialize an ``OpenAPILambdaStreamingHandler``.
    ///
    /// This initializer decouples the ``OpenAPILambdaStreamingService`` creation from the registration
    /// of the transport. It allows users to control the lifecycle of their service and to inject dependencies.
    ///
    /// - Parameters:
    ///   - withService: The OpenAPI Lambda streaming service to bind to this Lambda handler.
    public init(withService openAPILambdaService: OALS) throws {
        self.openAPIService = openAPILambdaService
        self.transport = OpenAPILambdaTransport(router: TrieRouter())
        self.eventDecoder = LambdaJSONEventDecoder(JSONDecoder())
        self.statusEncoder = LambdaJSONOutputEncoder(JSONEncoder())
        try self.openAPIService.register(transport: self.transport)
    }

    /// The streaming Lambda handling method.
    ///
    /// - Parameters:
    ///   - event: The raw `ByteBuffer` representing the invocation's input event.
    ///   - responseWriter: A `LambdaResponseStreamWriter` to write the invocation's response to.
    ///   - context: The runtime ``LambdaContext``.
    public func handle(
        _ event: ByteBuffer,
        responseWriter: some LambdaResponseStreamWriter,
        context: AWSLambdaRuntime.LambdaContext
    ) async throws {

        // 1. Decode the raw event into the service's typed Event
        let decodedEvent: OALS.Event
        do {
            decodedEvent = try self.eventDecoder.decode(OALS.Event.self, from: event)
        }
        catch {
            try await self.respondPlain(
                status: .badRequest,
                message: "Cannot decode Lambda event: \(error.localizedDescription)",
                writer: responseWriter
            )
            return
        }

        do {
            // 2. Convert Lambda event to OpenAPILambdaRequest
            let request = try openAPIService.request(context: context, from: decodedEvent)

            // 3. Route the request to find the handler and extract the parameters
            let (handler, parameters) = try self.transport.router.route(
                method: request.0.method,
                path: request.0.path!
            )

            // 4. Call the handler (extract the HTTPRequest and wrap the body as an HTTPBody)
            let httpRequest = request.0
            let httpBody = HTTPBody(stringLiteral: request.1 ?? "")
            let (response, responseBody) = try await handler(
                httpRequest,
                httpBody,
                ServerRequestMetadata(pathParameters: parameters)
            )

            // 5. Stream the response: status + headers, then each body chunk, then finish
            try await responseWriter.writeStatusAndHeaders(
                StreamingLambdaStatusAndHeadersResponse(
                    statusCode: Int(response.status.code),
                    headers: response.headerFields.lambdaStreamingHeaders
                ),
                encoder: self.statusEncoder
            )

            if let responseBody {
                for try await chunk in responseBody {
                    var buffer = ByteBuffer()
                    buffer.writeBytes(chunk)
                    try await responseWriter.write(buffer)
                }
            }
            try await responseWriter.finish()

        }
        catch OpenAPILambdaRouterError.noHandlerForPath(let path) {

            // There is no handler registered for this path. This is a programming error.
            try await self.respondPlain(
                status: .internalServerError,
                message: "There is no OpenAPI handler registered for the path \(path)",
                writer: responseWriter
            )

        }
        catch OpenAPILambdaRouterError.noRouteForMethod(let method) {

            // There is no route registered for this method.
            try await self.respondPlain(
                status: .notFound,
                message: "There is no route registered for the method \(method)",
                writer: responseWriter
            )

        }
        catch OpenAPILambdaRouterError.noRouteForPath(let method, let path) {

            // There is no route registered for this path.
            try await self.respondPlain(
                status: .notFound,
                message: "There is no route registered for the path \(method) \(path)",
                writer: responseWriter
            )

        }
        catch OpenAPILambdaHttpError.invalidMethod(let method) {

            // The APIGateway HTTP verb is rejected by HTTPTypes HTTPRequest.Method => HTTP 500
            // This should never happen.
            try await self.respondPlain(
                status: .internalServerError,
                message:
                    "Type mismatch between APIGatewayV2 and HTTPRequest.Method. \(method) verb is rejected by HTTPRequest.Method 🤷‍♂️",
                writer: responseWriter
            )

        }
        catch {

            // Some other error happened.
            try await self.respondPlain(
                status: .internalServerError,
                message: "Unknown error: \(String(reflecting: error))",
                writer: responseWriter
            )
        }
    }

    /// Stream a plain-text status response and finish the stream.
    /// Used for routing errors and event-decoding failures.
    ///
    /// - Parameters:
    ///   - status: The HTTP status to return.
    ///   - message: A short text body describing the failure.
    ///   - writer: The Lambda response stream writer.
    private func respondPlain(
        status: HTTPResponse.Status,
        message: String,
        writer: some LambdaResponseStreamWriter
    ) async throws {
        try await writer.writeStatusAndHeaders(
            StreamingLambdaStatusAndHeadersResponse(
                statusCode: Int(status.code),
                headers: ["Content-Type": "text/plain; charset=utf-8"]
            ),
            encoder: self.statusEncoder
        )
        var buffer = ByteBuffer()
        buffer.writeString(message)
        try await writer.writeAndFinish(buffer)
    }
}

extension HTTPFields {

    /// Flatten `HTTPFields` to a `[String: String]` for the streaming status/headers response.
    /// Multi-value fields are collapsed by joining with ", ", matching `HTTPHeaders.init(from: HTTPFields)`.
    fileprivate var lambdaStreamingHeaders: [String: String] {
        var dictionary: [String: String] = [:]
        for field in self {
            let name = field.name.rawName
            if let existing = dictionary[name] {
                dictionary[name] = "\(existing), \(field.value)"
            }
            else {
                dictionary[name] = field.value
            }
        }
        return dictionary
    }
}
