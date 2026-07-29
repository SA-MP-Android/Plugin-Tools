package api

import _ "embed"

// SchemaJSON contains the Plugin API contract shipped with the matching client
// release. Keeping it embedded makes installed CLI binaries self-contained.
//
//go:embed schema.json
var SchemaJSON []byte
