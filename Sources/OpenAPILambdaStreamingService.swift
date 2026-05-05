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
import Logging
import OpenAPIRuntime
import HTTPTypes

/// A Lambda function implemented with an OpenAPI server (`APIProtocol` from Swift OpenAPI Runtime)
/// that supports **response streaming**.
///
/// Use this protocol when at least one operation returns an incremental response body
/// (such as `application/jsonl` or `text/event-stream`), or when the function is exposed
/// through a Lambda Function URL configured with `InvokeMode: RESPONSE_STREAM`.
/// Buffered routes mounted on the same service work transparently — each one emits a single
/// chunk to the underlying response stream.
///
/// Conforming types should typically adopt one of the event-source mixins (such as
/// ``OpenAPILambdaStreamingHttpApi``) which provide a default `request(context:from:)`.
public protocol OpenAPILambdaStreamingService: Sendable {

    associatedtype Event: Decodable, Sendable

    /// Injects the transport.
    ///
    /// This is where your `OpenAPILambdaStreamingService` implementation must register the transport.
    func register(transport: OpenAPILambdaTransport) throws

    /// Convert from `Event` type to ``OpenAPILambdaRequest``.
    /// - Parameters:
    ///   - context: Lambda context
    ///   - from: Event
    func request(context: LambdaContext, from: Event) throws -> OpenAPILambdaRequest
}

extension OpenAPILambdaStreamingService {

    /// Start the Lambda Runtime with the streaming Lambda handler function
    /// for this OpenAPI Lambda streaming service implementation, with a custom logger.
    ///
    /// - Parameter logger: The logger to use for Lambda runtime logging
    public func run(logger: Logger? = nil) async throws {
        let _logger = logger ?? Logger(label: "OpenAPILambdaStreamingService")

        let lambda = try OpenAPILambdaStreamingHandler(withService: self)
        let lambdaRuntime = LambdaRuntime(handler: lambda, logger: _logger)
        try await lambdaRuntime.run()
    }
}
