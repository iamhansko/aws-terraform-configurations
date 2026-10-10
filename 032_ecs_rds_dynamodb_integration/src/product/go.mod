module productapp

go 1.22

// The three aws-sdk-go-v2 modules are one release (2025-10-02) and have to move together.
//
// They were core v1.24.0, config v1.24.0 and dynamodb v1.24.0 - the same number on three modules that are
// versioned independently, and so three different releases. dynamodb v1.24.0 (2023-10-31) was built against
// core v1.22.0, and core v1.23.0 (2023-11-15) moved the V2 endpoint resolution middleware from the Serialize
// step to Finalize, a change its changelog marks BREAKING. With core v1.24.0 selected, the client looked for
// ResolveEndpointV2 in a step it no longer lives in, and every call - PutItem and GetItem alike - failed
// before a request was sent: "not found, ResolveEndpointV2" in the log, "Internal Server Error" to the caller.
//
// The newest release that still declares go 1.22. The next one requires go 1.23, and the builder image in
// the Dockerfile is golang:1.22.2 with GOTOOLCHAIN=local, so go mod tidy would refuse it rather than
// download a newer toolchain. Raising these means raising that image with them.
require (
    github.com/aws/aws-sdk-go-v2 v1.39.2
    github.com/aws/aws-sdk-go-v2/config v1.31.12
    github.com/aws/aws-sdk-go-v2/service/dynamodb v1.51.0
    github.com/gin-gonic/gin v1.10.0
)
