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

/// A specialization of the ``OpenAPILambdaStreamingService`` protocol that works with
/// Amazon API Gateway HTTP API (`APIGatewayV2Request`).
///
/// AWS Lambda Function URLs share the same wire payload (payload format v2) as API Gateway
/// HTTP API, so the same `Event = APIGatewayV2Request` typealias is used for both deployment
/// targets. For Function URL deployments, set `FunctionUrlConfig.InvokeMode: RESPONSE_STREAM`
/// in your SAM template to enable response streaming end-to-end.
public protocol OpenAPILambdaStreamingHttpApi: OpenAPILambdaStreamingService where Event == APIGatewayV2Request {}

extension OpenAPILambdaStreamingHttpApi {

    /// Transform a Lambda input (`APIGatewayV2Request` and ``LambdaContext``) to an
    /// ``OpenAPILambdaRequest`` (`HTTPRequest`, `String?`).
    public func request(context: LambdaContext, from request: Event) throws -> OpenAPILambdaRequest {
        (try request.httpRequest(), request.body)
    }
}
