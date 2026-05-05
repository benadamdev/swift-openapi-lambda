# StreamingNumbers — response streaming with `swift-openapi-lambda`

A minimal example that demonstrates HTTP response streaming through a Lambda Function URL.

The service exposes a single streaming operation:

| Operation | Method | Path | Response | Notes |
|---|---|---|---|---|
| `streamNumbers` | `POST` | `/numbers/stream` | `200 application/jsonl` of `NumberSnapshot` | One JSONL line per integer in `1...count`, ~100 ms apart. |

A buffered `/health` route is also registered to demonstrate that buffered and streaming routes can coexist on the same function.

## Why a Function URL (not API Gateway HTTP API)

Response streaming requires `InvokeMode: RESPONSE_STREAM`, which is supported by Lambda Function URLs and (since November 2025) by API Gateway REST APIs with `responseTransferMode: STREAM`. **API Gateway HTTP API does not support response streaming**, so the `quoteapi-apigtw` example template can't be repurposed for streaming.

This service conforms to `OpenAPILambdaStreamingFunctionURL`, which uses `Event = FunctionURLRequest`. Lambda Function URLs are the only AWS front door that supports progressive HTTP response streaming — API Gateway HTTP API and Application Load Balancer both buffer the entire response before delivering it to the client, even when the Lambda handler writes chunked output.

## Local development (no AWS, no SAM)

`swift-aws-lambda-runtime` ships its own local HTTP server (gated by the `LocalServerSupport` SwiftPM trait, on by default) that supports streaming end-to-end. **`sam local start-api` and `sam local start-lambda` cannot emulate streaming responses** (`aws/aws-sam-cli` #6501 and #8606); the AWS Lambda Runtime Interface Emulator likewise lacks streaming (`aws/aws-lambda-runtime-interface-emulator` #175). The runtime's built-in server bypasses all of that.

```bash
# Build + run; the runtime starts an HTTP server on 127.0.0.1:7000
swift run StreamingNumbers

# In another terminal, POST a synthetic FunctionURLRequest event
curl --no-buffer -X POST http://127.0.0.1:7000/invoke \
     -H "Content-Type: application/json" \
     -d '{
       "rawQueryString": "",
       "headers": {"host": "localhost", "content-type": "application/json"},
       "requestContext": {
         "apiId": "local",
         "http": {"sourceIp": "127.0.0.1", "userAgent": "curl", "method": "POST", "path": "/numbers/stream", "protocol": "HTTP/1.1"},
         "timeEpoch": 0, "domainPrefix": "local", "accountId": "0",
         "time": "2026", "stage": "$default", "routeKey": "$default",
         "domainName": "localhost", "requestId": "test"
       },
       "isBase64Encoded": false,
       "version": "2.0",
       "routeKey": "$default",
       "rawPath": "/numbers/stream",
       "body": "{\"count\":10}"
     }'
```

The response is the wire format the AWS Function URL would emit: a `StreamingLambdaStatusAndHeadersResponse` JSON, eight null bytes (the framing separator), and then the chunked JSONL body — one `{"value":n}` line every ~100 ms.

`LOCAL_LAMBDA_HOST`, `LOCAL_LAMBDA_PORT`, and `LOCAL_LAMBDA_INVOCATION_ENDPOINT` are honoured if you need to relocate the server.

## Build & deploy to AWS

```bash
make build-StreamingNumbers   # cross-compile to Linux/arm64 in Docker
make deploy                   # `sam deploy --guided` first time, then `sam deploy`
```

The stack output `FunctionUrl` is the endpoint to call.

## Test the deployed Function URL

```bash
# Stream 20 snapshots; --no-buffer is critical so curl doesn't buffer the body
curl -v --no-buffer \
     -X POST -H 'Content-Type: application/json' \
     --data '{"count": 20}' \
     "$FUNCTION_URL/numbers/stream"

# Buffered route on the same function
curl "$FUNCTION_URL/health"
```

You should see each `{"value":n}` line appear roughly 100 ms apart in the curl output, instead of all at once at the end.

## How it works

1. `StreamingNumbersService` conforms to `OpenAPILambdaStreamingHttpApi` and `APIProtocol`.
2. The `streamNumbers(_:)` handler returns an `Output` whose body is `applicationJsonl(HTTPBody(...))`. The `HTTPBody` wraps an `AsyncThrowingStream<NumberSnapshot, Error>` that JSON-encodes each snapshot followed by `\n`.
3. `OpenAPILambdaStreamingHandler` (registered via `Self().run()`) iterates the body's async byte sequence and writes each chunk to the Lambda response stream via `LambdaResponseStreamWriter.write(_:)`. The runtime forwards each `write(_:)` call as an HTTP response chunk to the Function URL.

## Cleanup

```bash
sam delete
```
