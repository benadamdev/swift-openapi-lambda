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
import HTTPTypes
import OpenAPIRuntime

extension FunctionURLRequest {

    // OpenAPIGenerator expects the path to include the query string
    var pathWithQueryString: String {
        rawPath + (rawQueryString.isEmpty ? "" : "?\(rawQueryString)")
    }

    /// Return an `HTTPRequest` for this `FunctionURLRequest`.
    public func httpRequest() throws -> HTTPRequest {
        HTTPRequest(
            method: self.requestContext.http.method,
            scheme: "https",  // Function URLs are always HTTPS
            authority: self.headers["Host"],
            path: pathWithQueryString,
            headerFields: self.headers.httpFields()
        )
    }
}
