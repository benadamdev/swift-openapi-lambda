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
/// AWS Lambda Function URLs.
///
/// Lambda Function URLs are the **only** front door that supports progressive HTTP response
/// streaming when configured with `InvokeMode: RESPONSE_STREAM`. API Gateway HTTP API and
/// Application Load Balancer both buffer the entire response before delivering it to the
/// client, even if the Lambda handler writes chunked output via `LambdaResponseStreamWriter`.
/// For those front doors, use ``OpenAPILambdaHttpApi`` or ``OpenAPILambdaALB`` (buffered).
///
/// Set `FunctionUrlConfig.InvokeMode: RESPONSE_STREAM` in your SAM template to enable
/// response streaming end-to-end.
public protocol OpenAPILambdaStreamingFunctionURL: OpenAPILambdaStreamingService where Event == FunctionURLRequest {}

extension OpenAPILambdaStreamingFunctionURL {

    /// Transform a Lambda input (`FunctionURLRequest` and ``LambdaContext``) to an
    /// ``OpenAPILambdaRequest`` (`HTTPRequest`, `String?`).
    public func request(context: LambdaContext, from request: Event) throws -> OpenAPILambdaRequest {
        (try request.httpRequest(), request.body)
    }
}
