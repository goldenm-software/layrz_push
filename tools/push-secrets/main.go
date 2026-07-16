// push-secrets is a TUI companion for the layrz_push example lab.
//
// Paste the raw content of a `google-services.json` (Android) or a
// `GoogleService-Info.plist` (iOS) and it extracts the values required by
// `example/assets/secrets.json`, merging them into the existing file so you
// can add one platform at a time.
//
// Usage:
//
//	cd tools/push-secrets && go run . [-output ../../example/assets/secrets.json]
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"
	"howett.net/plist"
)

type platformCreds struct {
	APIKey            string  `json:"apiKey"`
	AppID             string  `json:"appId"`
	ProjectID         string  `json:"projectId"`
	MessagingSenderID string  `json:"messagingSenderId"`
	StorageBucket     *string `json:"storageBucket"`
}

type secrets struct {
	DeviceID string         `json:"deviceId"`
	Android  *platformCreds `json:"android,omitempty"`
	IOS      *platformCreds `json:"ios,omitempty"`
}

// googleServices maps the subset of google-services.json we care about.
type googleServices struct {
	ProjectInfo struct {
		ProjectNumber string `json:"project_number"`
		ProjectID     string `json:"project_id"`
		StorageBucket string `json:"storage_bucket"`
	} `json:"project_info"`
	Client []struct {
		ClientInfo struct {
			MobilesdkAppID    string `json:"mobilesdk_app_id"`
			AndroidClientInfo struct {
				PackageName string `json:"package_name"`
			} `json:"android_client_info"`
		} `json:"client_info"`
		APIKey []struct {
			CurrentKey string `json:"current_key"`
		} `json:"api_key"`
	} `json:"client"`
}

var (
	titleStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("12"))
	keyStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("8")).Width(20)
	okStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("10"))
	errStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("9"))
)

func main() {
	output := flag.String("output", defaultOutput(), "path of the secrets.json to write")
	flag.Parse()

	fmt.Println(titleStyle.Render("layrz_push · secrets.json generator"))
	fmt.Printf("Output: %s\n\n", *output)

	current := loadSecrets(*output)

	for {
		platform, creds, err := askAndParse()
		if err != nil {
			if errors.Is(err, huh.ErrUserAborted) {
				return
			}
			fmt.Println(errStyle.Render("✗ " + err.Error()))
			if !confirm("Try again?") {
				return
			}
			continue
		}

		preview(platform, creds)

		deviceID := current.DeviceID
		if err := input("Device ID (defines the topic `device_{id}`)", &deviceID); err != nil {
			return
		}
		current.DeviceID = deviceID

		if platform == "ios" {
			current.IOS = creds
		} else {
			current.Android = creds
		}

		if !confirm(fmt.Sprintf("Write to %s?", *output)) {
			return
		}

		if err := writeSecrets(*output, current); err != nil {
			fmt.Println(errStyle.Render("✗ " + err.Error()))
			return
		}
		fmt.Println(okStyle.Render("✓ Saved " + *output))

		if !confirm("Add the other platform?") {
			return
		}
	}
}

// askAndParse prompts for the raw file content and detects its format.
func askAndParse() (string, *platformCreds, error) {
	var raw string
	form := huh.NewForm(huh.NewGroup(
		huh.NewText().
			Title("Paste the file content").
			Description("google-services.json (Android) or GoogleService-Info.plist (iOS)").
			ExternalEditor(false).
			Value(&raw),
	))
	if err := form.Run(); err != nil {
		return "", nil, err
	}

	trimmed := strings.TrimSpace(raw)
	switch {
	case strings.HasPrefix(trimmed, "{"):
		creds, err := parseGoogleServices(trimmed)
		return "android", creds, err
	case strings.Contains(trimmed, "<plist"), strings.HasPrefix(trimmed, "<?xml"):
		creds, err := parsePlist(trimmed)
		return "ios", creds, err
	case trimmed == "":
		return "", nil, errors.New("nothing pasted")
	default:
		return "", nil, errors.New("unrecognized format: expected JSON (starts with '{') or a plist (XML)")
	}
}

func parseGoogleServices(raw string) (*platformCreds, error) {
	var gs googleServices
	if err := json.Unmarshal([]byte(raw), &gs); err != nil {
		return nil, fmt.Errorf("invalid google-services.json: %w", err)
	}
	if len(gs.Client) == 0 {
		return nil, errors.New("google-services.json has no clients")
	}

	client := gs.Client[0]
	if len(gs.Client) > 1 {
		options := make([]huh.Option[int], 0, len(gs.Client))
		for i, c := range gs.Client {
			options = append(options, huh.NewOption(c.ClientInfo.AndroidClientInfo.PackageName, i))
		}

		var selected int
		form := huh.NewForm(huh.NewGroup(
			huh.NewSelect[int]().Title("Multiple apps found, pick the package").Options(options...).Value(&selected),
		))
		if err := form.Run(); err != nil {
			return nil, err
		}
		client = gs.Client[selected]
	}

	if len(client.APIKey) == 0 {
		return nil, errors.New("selected client has no api_key")
	}

	return &platformCreds{
		APIKey:            client.APIKey[0].CurrentKey,
		AppID:             client.ClientInfo.MobilesdkAppID,
		ProjectID:         gs.ProjectInfo.ProjectID,
		MessagingSenderID: gs.ProjectInfo.ProjectNumber,
		StorageBucket:     nilIfEmpty(gs.ProjectInfo.StorageBucket),
	}, nil
}

func parsePlist(raw string) (*platformCreds, error) {
	var data map[string]any
	if _, err := plist.Unmarshal([]byte(raw), &data); err != nil {
		return nil, fmt.Errorf("invalid GoogleService-Info.plist: %w", err)
	}

	str := func(key string) string {
		value, _ := data[key].(string)
		return value
	}

	creds := &platformCreds{
		APIKey:            str("API_KEY"),
		AppID:             str("GOOGLE_APP_ID"),
		ProjectID:         str("PROJECT_ID"),
		MessagingSenderID: str("GCM_SENDER_ID"),
		StorageBucket:     nilIfEmpty(str("STORAGE_BUCKET")),
	}

	if creds.APIKey == "" || creds.AppID == "" || creds.ProjectID == "" || creds.MessagingSenderID == "" {
		return nil, errors.New("plist is missing one of API_KEY, GOOGLE_APP_ID, PROJECT_ID or GCM_SENDER_ID")
	}
	return creds, nil
}

func preview(platform string, creds *platformCreds) {
	bucket := "(none)"
	if creds.StorageBucket != nil {
		bucket = *creds.StorageBucket
	}

	fmt.Println()
	fmt.Println(titleStyle.Render("Detected: " + platform))
	fmt.Println(keyStyle.Render("apiKey") + creds.APIKey)
	fmt.Println(keyStyle.Render("appId") + creds.AppID)
	fmt.Println(keyStyle.Render("projectId") + creds.ProjectID)
	fmt.Println(keyStyle.Render("messagingSenderId") + creds.MessagingSenderID)
	fmt.Println(keyStyle.Render("storageBucket") + bucket)
	fmt.Println()
}

func loadSecrets(path string) secrets {
	var current secrets
	raw, err := os.ReadFile(path)
	if err != nil {
		return current
	}
	if err := json.Unmarshal(raw, &current); err != nil {
		fmt.Println(errStyle.Render("✗ Existing " + path + " is not valid JSON, starting from scratch"))
		return secrets{}
	}
	return current
}

func writeSecrets(path string, value secrets) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	raw, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(raw, '\n'), 0o600)
}

// defaultOutput finds the example's secrets.json relative to where the tool
// runs from: the repo root, tools/push-secrets, or the example folder itself.
func defaultOutput() string {
	candidates := []string{
		"example/assets",
		filepath.Join("..", "..", "example", "assets"),
		"assets",
	}
	for _, dir := range candidates {
		if info, err := os.Stat(dir); err == nil && info.IsDir() {
			return filepath.Join(dir, "secrets.json")
		}
	}
	return "secrets.json"
}

func confirm(question string) bool {
	value := true
	form := huh.NewForm(huh.NewGroup(huh.NewConfirm().Title(question).Value(&value)))
	if err := form.Run(); err != nil {
		return false
	}
	return value
}

func input(title string, value *string) error {
	return huh.NewForm(huh.NewGroup(huh.NewInput().Title(title).Value(value))).Run()
}

func nilIfEmpty(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}
