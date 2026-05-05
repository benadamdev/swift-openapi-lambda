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
import Logging
import OpenAPIRuntime
import OpenAPILambda

@main
struct StreamingNumbersService: APIProtocol, OpenAPILambdaStreamingFunctionURL {

    let logger: Logger

    init() {
        var logger = Logger(label: "StreamingNumbers")
        logger.logLevel = .trace
        self.logger = logger
    }

    func register(transport: OpenAPILambdaTransport) throws {
        // Optional: a buffered, hand-registered route demonstrating that buffered and
        // streaming routes coexist on the same function.
        try transport.router.get("/health") { _, _ in "OK" }

        // Mandatory: register the OpenAPI-generated handlers.
        try self.registerHandlers(on: transport, middlewares: [LoggingMiddleware(logger: logger)])
    }

    static func main() async throws {
        try await StreamingNumbersService().run()
    }

    /// Stream a sequence of `NumberSnapshot` values as JSONL.
    ///
    /// Each line is emitted with a small delay so a client connected with
    /// `curl --no-buffer` will see lines arrive progressively.
    func streamNumbers(_ input: Operations.streamNumbers.Input) async throws -> Operations.streamNumbers.Output {
        let request: Components.Schemas.NumbersRequest
        switch input.body {
        case .json(let body): request = body
        }
        let count = request.count

        let snapshots = AsyncThrowingStream<Components.Schemas.NumberSnapshot, Error> { continuation in
            let task = Task {
                for value in 1...count {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms
                    continuation.yield(.init(value: value))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        let body = HTTPBody(
            snapshots.map { snapshot -> ArraySlice<UInt8> in
                var data = try JSONEncoder().encode(snapshot)
                data.append(0x0A)  // newline terminator (JSONL)
                return ArraySlice(data)
            },
            length: .unknown,
            iterationBehavior: .single
        )

        return .ok(.init(body: .application_jsonl(body)))
    }
}
