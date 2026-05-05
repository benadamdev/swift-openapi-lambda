[![Build & Test on GitHub](https://github.com/awslabs/swift-openapi-lambda/actions/workflows/swift.yml/badge.svg)](https://github.com/awslabs/swift-openapi-lambda/actions/workflows/swift.yml)

![language](https://img.shields.io/badge/swift-6.0-blue)
![language](https://img.shields.io/badge/swift-6.1-blue)
![platform](https://img.shields.io/badge/platform-macOS-green)
![platform](https://img.shields.io/badge/platform-Linux-orange)
[![license](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

# AWS Lambda transport for Swift OpenAPI

This library provides an [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html) transport for [Swift OpenAPI generator](https://github.com/apple/swift-openapi-generator)

This library allows you to expose server-side Swift OpenAPI implementations as AWS Lambda functions with minimal code changes.

The library provides:

- A default AWS Lambda Swift function that consumes your OpenAPI service implementation
- Built-in support for [Amazon API Gateway HTTP API](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html) events
- Re-exported dependencies to minimize `Package.swift` complexity

We strongly recommend never deploying an openly available API. The QuoteAPI example project shows you how to add a Lambda Authorizer function to the API Gateway.
## Prerequisites

- [AWS Account](https://console.aws.amazon.com/)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) - configured with your AWS credentials
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html) - for serverless deployment
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) - for cross compilation to Linux, when using macOS or Windows.

## Quick Start
If you already have an OpenAPI definition, you already generated the server stubs, and wrote an implementation, here are the additional steps to expose your OpenAPI service implementation as a AWS Lambda function and an Amazon API Gateway HTTP API (aka `APIGatewayV2`).

To expose your OpenAPI implementation as an AWS Lambda function:

### 1. Add dependencies to Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
    .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.8.2"),
    
    // add these three dependencies
    .package(url: "https://github.com/awslabs/swift-aws-lambda-runtime.git", from: "2.0.0"),
    .package(url: "https://github.com/awslabs/swift-aws-lambda-events.git", from: "1.2.0"),
    .package(url: "https://github.com/awslabs/swift-openapi-lambda.git", from: "2.0.0"),
],
targets: [
  .executableTarget(
    name: "YourOpenAPIService",
    dependencies: [
      .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),

      // add these three products
      .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
      .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
      .product(name: "OpenAPILambda", package: "swift-openapi-lambda"),
    ]
  )
]
```

### 2. Update your service implementation

Add a protocol and a constructor to your existing OpenAPI service implementation 

There are only five changes to make to your existing implementation:

![Animated GIF to show the changes](assets/swift-openapi-lambda.gif)

```swift
import OpenAPIRuntime
import OpenAPILambda // <-- 1. import this library 

@main // <-- 2. flag this struct as the executable target entrypoint
struct QuoteServiceImpl: APIProtocol, OpenAPILambdaHttpApi { // <-- 3. add the OpenAPILambdaHttpApi protocol 

  // The registration of your OpenAPI handlers
  func register(transport: OpenAPILambdaTransport) throws { // <-- 4. add this method (calls registerHandlers)
    try self.registerHandlers(on: transport)
  }

  // the entry point for your Lambda function
  static func main() async throws { // <-- 5. add this entry point to start the lambdaRuntime
    let openAPIService = QuoteServiceImpl()  
    try await openAPIService.run()
  }

  // Your existing OpenAPI implementation
  func getQuote(_ input: Operations.getQuote.Input) async throws -> Operations.getQuote.Output {
    let symbol = input.path.symbol
    let price = Components.Schemas.quote(
        symbol: symbol,
        price: Double.random(in: 100..<150).rounded(),
        change: Double.random(in: -5..<5).rounded(),
        changePercent: Double.random(in: -0.05..<0.05),
        volume: Double.random(in: 10000..<100000).rounded(),
        timestamp: Date()
    )
    return .ok(.init(body: .json(price)))
  }
}
```

### 3. Deploy with SAM

```bash
sam build && sam deploy --guided
```

## Complete Example

See the [Examples/quoteapi](Examples/quoteapi) directory for a complete working example that includes:

- Stock quote API with OpenAPI 3.1 specification
- Lambda authorizer for protected endpoints
- Use `make` for common commands
- SAM deployment configuration
- Local testing setup

## Testing

### Local Development

```bash
# Run locally with built-in development server
swift run QuoteService

# Test from another terminal
curl -H 'Authorization: Bearer 123' -X POST \
  --data @events/GetQuote.json \
  http://127.0.0.1:7000/invoke
```

### Production Testing

```bash
# Test deployed API (replace with your endpoint)
curl -H 'Authorization: Bearer 123' \
  https://your-api-id.execute-api.region.amazonaws.com/stocks/AAPL
```

## Deployment Costs

New AWS accounts get 1 million Lambda invocations and 1 million API Gateway requests free per month. After the free tier, costs are approximately $1.00 per million API calls.

## Cleanup

```bash
sam delete
```

## Lambda Authorizers

The library supports Lambda authorizers for API protection. See [Examples/quoteapi/Sources/LambdaAuthorizer](Examples/quoteapi/Sources/LambdaAuthorizer) for a complete implementation that validates a Bearer token.

```swift
let simpleAuthorizerHandler: (APIGatewayLambdaAuthorizerRequest, LambdaContext) async throws -> APIGatewayLambdaAuthorizerSimpleResponse = {
    guard let authToken = $0.headers["authorization"],
          authToken == "Bearer 123" else {
        return .init(isAuthorized: false, context: [:])
    }
    return .init(isAuthorized: true, context: ["user": "authenticated"])
}
```

## Streaming Responses

For Lambda Function URLs configured with `InvokeMode: RESPONSE_STREAM`, this library provides an `OpenAPILambdaStreamingService` protocol that lets you return chunked HTTP responses (e.g. `application/jsonl`, `text/event-stream`) instead of single buffered values. Buffered routes (`application/json`, `text/plain`) keep working on the same service — they emit a single chunk to the underlying response stream.

Adopt `OpenAPILambdaStreamingHttpApi` in place of `OpenAPILambdaHttpApi`. AWS Lambda Function URL events share the API Gateway HTTP API wire payload (payload format v2), so the same `Event = APIGatewayV2Request` type is used for both deployment targets.

```swift
import OpenAPIRuntime
import OpenAPILambda

@main
struct MyService: APIProtocol, OpenAPILambdaStreamingHttpApi {
    func register(transport: OpenAPILambdaTransport) throws {
        try self.registerHandlers(on: transport)
    }

    static func main() async throws {
        try await Self().run()
    }

    // Streaming route — return an HTTPBody wrapping an AsyncSequence of bytes
    func streamNumbers(_ input: Operations.streamNumbers.Input) async throws -> Operations.streamNumbers.Output {
        let snapshots = AsyncStream<ArraySlice<UInt8>> { continuation in
            for value in 1...10 {
                let line = #"{"value":\#(value)}"#.utf8 + [0x0A]
                continuation.yield(ArraySlice(line))
            }
            continuation.finish()
        }
        let body = HTTPBody(snapshots, length: .unknown, iterationBehavior: .single)
        return .ok(.init(body: .application_jsonl(body)))
    }

    // Buffered route on the same service — works transparently
    func health(_ input: Operations.health.Input) async throws -> Operations.health.Output {
        .ok(.init(body: .json(.init(status: "OK"))))
    }
}
```

In your SAM template, configure the function with a Function URL set to `RESPONSE_STREAM`:

```yaml
FunctionUrlConfig:
  AuthType: NONE
  InvokeMode: RESPONSE_STREAM
```

Note: `sam local start-api` does **not** emulate streaming responses (`aws/aws-sam-cli` issues #6501 and #8606). Local development requires deploying to AWS, or invoking the swift binary directly via `swift run`.

See [Examples/streamingapi-functionurl](Examples/streamingapi-functionurl) for a complete working example.

## Advanced Usage

### Custom Event Types

To support other Lambda event types beyond API Gateway, implement the `OpenAPILambda` protocol:

```swift
@main
struct CustomServiceLambda: OpenAPILambda {
  typealias Event = YourCustomEvent
  typealias Output = YourCustomResponse
  
  func register(transport: OpenAPILambdaTransport) throws {
    let handler = YourServiceImpl()
    try handler.registerHandlers(on: transport)
  }
  
  func request(context: LambdaContext, from event: Event) throws -> OpenAPILambdaRequest {
    // Transform your event to HTTPRequest
  }
  
  func output(from response: OpenAPILambdaResponse) -> Output {
    // Transform HTTPResponse to your output type
  }
}
```

### Service Lifecycle Integration

```swift
import ServiceLifecycle

// In your OpenAPI service, explicitly create and manage the LambdaRuntime
static func main() async throws {
  let lambdaRuntime = try LambdaRuntime(body: Self.handler())
  let serviceGroup = ServiceGroup(
    services: [lambdaRuntime],
    gracefulShutdownSignals: [.sigterm],
    cancellationSignals: [.sigint],
    logger: Logger(label: "ServiceGroup")
  )
  try await serviceGroup.run()
}
```

### Dependency Injection

For advanced use cases requiring dependency injection:

```swift
@main
struct QuoteServiceImpl: APIProtocol, OpenAPILambdaHttpApi {
    let customDependency: Int
    
    init(customDependency: Int = 0) {
        self.customDependency = customDependency
    }
    
    // the entry point can be in another file / struct as well.
    static func main() async throws {
        let service = QuoteServiceImpl(customDependency: 42)
        let lambda = try OpenAPILambdaHandler(service: service)
        let lambdaRuntime = LambdaRuntime(body: lambda.handler)
        try await lambdaRuntime.run()
    }
    
    func register(transport: OpenAPILambdaTransport) throws {
        try self.registerHandlers(on: transport)
    }
}
```

## References

- [Swift OpenAPI Generator](https://swiftpackageindex.com/apple/swift-openapi-generator/documentation) - Complete documentation and tutorials
- [Swift AWS Lambda Runtime](https://swiftpackageindex.com/awslabs/swift-aws-lambda-runtime) - Swift runtime for AWS Lambda
- [AWS SAM](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html) - Serverless Application Model documentation
- [API Gateway Lambda Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html) - Lambda authorization documentation
