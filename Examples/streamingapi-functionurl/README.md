# StreamingNumbers — response streaming with `swift-openapi-lambda`

A minimal example that demonstrates HTTP response streaming through a Lambda Function URL.

The service exposes a single streaming operation:

| Operation | Method | Path | Response | Notes |
|---|---|---|---|---|
| `streamNumbers` | `POST` | `/numbers/stream` | `200 application/jsonl` of `NumberSnapshot` | One JSONL line per integer in `1...count`, ~100 ms apart. |

A buffered `/health` route is also registered to demonstrate that buffered and streaming routes can coexist on the same function.

## Why a Function URL (not API Gateway HTTP API)

Response streaming requires `InvokeMode: RESPONSE_STREAM`, which is supported by Lambda Function URLs and (since November 2025) by API Gateway REST APIs with `responseTransferMode: STREAM`. **API Gateway HTTP API does not support response streaming**, so the `quoteapi-apigtw` example template can't be repurposed for streaming.

`FunctionURLRequest` and `APIGatewayV2Request` share the same wire payload (payload format v2), so this service uses `Event = APIGatewayV2Request` (provided by `OpenAPILambdaStreamingHttpApi`) — the same code works behind either trigger.

## Build & deploy

```bash
make build-StreamingNumbers   # cross-compile to Linux/arm64 in Docker
make deploy                   # `sam deploy --guided` first time, then `sam deploy`
```

The stack output `FunctionUrl` is the endpoint to call.

## Test

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
