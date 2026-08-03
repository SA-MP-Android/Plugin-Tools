package plugin

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf16"

	"github.com/SA-MP-Android/Plugin-Tools/api"
)

const (
	maxManifestBytes      = 128 * 1024
	maxIDLength           = 128
	maxDisplayTextLength  = 128
	maxVersionLength      = 64
	maxVersionRangeLength = 64
	maxEntryLength        = 256
	maxDescriptionLength  = 2048
	maxActivationModeLen  = 32
	maxPermissionLength   = 128
	maxPermissions        = 64
	maxContexts           = 8
)

var (
	idPattern         = regexp.MustCompile(`^[a-z][a-z0-9]*(?:\.[a-z0-9][a-z0-9_-]*)+$`)
	permissionPattern = regexp.MustCompile(
		`^[a-z][a-z0-9]*(?:\.[a-z0-9_]+)+$`,
	)
	semverPattern = regexp.MustCompile(
		`^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)` +
			`(?:-((?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)` +
			`(?:\.(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?` +
			`(?:\+(?:[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$`,
	)
	apiRequirementPattern = regexp.MustCompile(`^(\^?)(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})$`)
	apiVersionPattern     = regexp.MustCompile(`^(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})$`)
)

type Manifest struct {
	SchemaVersion  int
	ID             string
	Name           string
	Version        string
	APIVersion     string
	Entry          string
	Description    string
	ActivationMode string
	Permissions    []string
	Contexts       []string
	AuthorName     string
}

type contractSchema struct {
	SchemaVersion int      `json:"schemaVersion"`
	APIVersion    string   `json:"apiVersion"`
	Permissions   []string `json:"permissions"`
}

type manifestJSON struct {
	SchemaVersion  json.Number `json:"schemaVersion"`
	ID             any         `json:"id"`
	Name           any         `json:"name"`
	Version        any         `json:"version"`
	APIVersion     any         `json:"apiVersion"`
	Entry          any         `json:"entry"`
	Description    any         `json:"description"`
	ActivationMode any         `json:"activationMode"`
	Permissions    any         `json:"permissions"`
	Contexts       any         `json:"contexts"`
	Author         any         `json:"author"`
}

func ParseManifest(data []byte) (Manifest, error) {
	if len(data) > maxManifestBytes {
		return Manifest{}, fmt.Errorf("manifest.json exceeds %d bytes", maxManifestBytes)
	}

	var raw manifestJSON
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if err := decoder.Decode(&raw); err != nil {
		return Manifest{}, fmt.Errorf("parse manifest.json: %w", err)
	}
	if err := requireJSONEnd(decoder); err != nil {
		return Manifest{}, err
	}

	schemaVersion, err := exactInt(raw.SchemaVersion, "schemaVersion")
	if err != nil {
		return Manifest{}, err
	}
	if schemaVersion != 1 {
		return Manifest{}, fmt.Errorf("unsupported manifest schema: %d", schemaVersion)
	}

	id, err := requiredString(raw.ID, "id", maxIDLength)
	if err != nil {
		return Manifest{}, err
	}
	if !idPattern.MatchString(id) {
		return Manifest{}, errors.New("invalid plugin id")
	}
	name, err := requiredString(raw.Name, "name", maxDisplayTextLength)
	if err != nil {
		return Manifest{}, err
	}
	version, err := requiredString(raw.Version, "version", maxVersionLength)
	if err != nil {
		return Manifest{}, err
	}
	if !validSemver(version) {
		return Manifest{}, errors.New("invalid semantic version")
	}
	apiVersion, err := requiredString(raw.APIVersion, "apiVersion", maxVersionRangeLength)
	if err != nil {
		return Manifest{}, err
	}
	entry, err := requiredString(raw.Entry, "entry", maxEntryLength)
	if err != nil {
		return Manifest{}, err
	}
	if !strings.HasSuffix(strings.ToLower(entry), ".lua") {
		return Manifest{}, errors.New("plugin entry must be a Lua file")
	}
	if !safeRelativePath(entry) {
		return Manifest{}, errors.New("invalid plugin entry path")
	}

	description, err := optionalString(raw.Description, "description", maxDescriptionLength)
	if err != nil {
		return Manifest{}, err
	}
	activationMode, err := optionalString(
		raw.ActivationMode,
		"activationMode",
		maxActivationModeLen,
	)
	if err != nil {
		return Manifest{}, err
	}
	if activationMode == "" {
		activationMode = "restart-required"
	}
	if activationMode != "immediate" && activationMode != "restart-required" {
		return Manifest{}, fmt.Errorf("unsupported activation mode: %s", activationMode)
	}

	permissions, err := optionalStringArray(raw.Permissions, "permissions", maxPermissions)
	if err != nil {
		return Manifest{}, err
	}
	contexts, err := optionalStringArray(raw.Contexts, "contexts", maxContexts)
	if err != nil {
		return Manifest{}, err
	}
	authorName, err := author(raw.Author)
	if err != nil {
		return Manifest{}, err
	}

	contract, err := loadContract()
	if err != nil {
		return Manifest{}, err
	}
	if !supportsAPI(apiVersion, contract.APIVersion) {
		return Manifest{}, fmt.Errorf(
			"unsupported plugin API version %q; tool contract is %s",
			apiVersion,
			contract.APIVersion,
		)
	}
	supportedPermissions := make(map[string]struct{}, len(contract.Permissions))
	for _, permission := range contract.Permissions {
		supportedPermissions[permission] = struct{}{}
	}
	for _, permission := range permissions {
		if !permissionPattern.MatchString(permission) {
			return Manifest{}, fmt.Errorf("invalid plugin permission: %s", permission)
		}
		if _, ok := supportedPermissions[permission]; !ok {
			return Manifest{}, fmt.Errorf("unsupported plugin permission: %s", permission)
		}
	}
	for _, context := range contexts {
		if context != "singleplayer" && context != "multiplayer" {
			return Manifest{}, fmt.Errorf("invalid plugin context: %s", context)
		}
	}

	return Manifest{
		SchemaVersion:  schemaVersion,
		ID:             id,
		Name:           name,
		Version:        version,
		APIVersion:     apiVersion,
		Entry:          entry,
		Description:    description,
		ActivationMode: activationMode,
		Permissions:    unique(permissions),
		Contexts:       unique(contexts),
		AuthorName:     authorName,
	}, nil
}

func loadContract() (contractSchema, error) {
	var contract contractSchema
	if err := json.Unmarshal(api.SchemaJSON, &contract); err != nil {
		return contractSchema{}, fmt.Errorf("parse embedded API schema: %w", err)
	}
	if contract.SchemaVersion != 1 || !apiVersionPattern.MatchString(contract.APIVersion) {
		return contractSchema{}, errors.New("embedded API schema is invalid")
	}
	return contract, nil
}

func requireJSONEnd(decoder *json.Decoder) error {
	var extra any
	err := decoder.Decode(&extra)
	if errors.Is(err, io.EOF) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("parse manifest.json: %w", err)
	}
	return errors.New("manifest.json contains multiple JSON values")
}

func exactInt(value json.Number, field string) (int, error) {
	if value == "" || strings.ContainsAny(value.String(), ".eE") {
		return 0, fmt.Errorf("missing or invalid %s", field)
	}
	result, err := strconv.ParseInt(value.String(), 10, 32)
	if err != nil {
		return 0, fmt.Errorf("missing or invalid %s", field)
	}
	return int(result), nil
}

func requiredString(value any, field string, maxLength int) (string, error) {
	text, ok := value.(string)
	if !ok {
		return "", fmt.Errorf("missing or invalid %s", field)
	}
	text = strings.TrimSpace(text)
	if text == "" || stringLength(text) > maxLength {
		return "", fmt.Errorf("invalid %s length", field)
	}
	return text, nil
}

func optionalString(value any, field string, maxLength int) (string, error) {
	if value == nil {
		return "", nil
	}
	text, ok := value.(string)
	if !ok {
		return "", fmt.Errorf("invalid %s", field)
	}
	text = strings.TrimSpace(text)
	if stringLength(text) > maxLength {
		return "", fmt.Errorf("%s is too long", field)
	}
	return text, nil
}

func optionalStringArray(value any, field string, maxItems int) ([]string, error) {
	if value == nil {
		return nil, nil
	}
	items, ok := value.([]any)
	if !ok {
		return nil, fmt.Errorf("invalid %s", field)
	}
	if len(items) > maxItems {
		return nil, fmt.Errorf("too many %s entries", field)
	}
	result := make([]string, 0, len(items))
	for _, item := range items {
		text, ok := item.(string)
		if !ok {
			return nil, fmt.Errorf("invalid %s entry", field)
		}
		text = strings.TrimSpace(text)
		if text == "" || stringLength(text) > maxPermissionLength {
			return nil, fmt.Errorf("invalid %s entry length", field)
		}
		result = append(result, text)
	}
	return result, nil
}

func author(value any) (string, error) {
	if value == nil {
		return "", nil
	}
	object, ok := value.(map[string]any)
	if !ok {
		return "", errors.New("invalid author")
	}
	return requiredString(object["name"], "author.name", maxDisplayTextLength)
}

func supportsAPI(requirement, current string) bool {
	requested := apiRequirementPattern.FindStringSubmatch(strings.TrimSpace(requirement))
	actual := apiVersionPattern.FindStringSubmatch(current)
	if requested == nil || actual == nil {
		return false
	}
	requestedMajor, requestedMajorOK := parseNonNegativeInt32(requested[2])
	requestedMinor, requestedMinorOK := parseNonNegativeInt32(requested[3])
	currentMajor, currentMajorOK := parseNonNegativeInt32(actual[1])
	currentMinor, currentMinorOK := parseNonNegativeInt32(actual[2])
	if !requestedMajorOK || !requestedMinorOK || !currentMajorOK || !currentMinorOK {
		return false
	}
	if currentMajor != requestedMajor {
		return false
	}
	// Minor releases are additive within a stable major API. The caret is
	// retained as an explicit opt-in spelling, while bare 1.0 remains
	// compatible with 1.1 so already-published manifests keep working.
	if requestedMajor != 0 {
		return currentMinor >= requestedMinor
	}
	return currentMinor == requestedMinor
}

func validSemver(value string) bool {
	if !semverPattern.MatchString(value) {
		return false
	}
	core := strings.SplitN(strings.SplitN(value, "+", 2)[0], "-", 2)[0]
	for _, component := range strings.Split(core, ".") {
		if _, ok := parseNonNegativeInt32(component); !ok {
			return false
		}
	}
	return true
}

func parseNonNegativeInt32(value string) (int, bool) {
	parsed, err := strconv.ParseInt(value, 10, 32)
	return int(parsed), err == nil && parsed >= 0
}

func stringLength(value string) int {
	// Kotlin String.length counts UTF-16 code units, not Unicode code points.
	return len(utf16.Encode([]rune(value)))
}

func unique(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}
