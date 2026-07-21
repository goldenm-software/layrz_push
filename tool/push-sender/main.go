// push-sender is a TUI companion for the layrz_push example lab.
//
// It sends test push notifications to an FCM topic using the Firebase Admin SDK,
// authenticated with a Firebase service account key (Firebase console →
// Project settings → Service accounts → Generate new private key).
//
// Usage:
//
//	cd tools/push-sender && go run . [-account service-account.json]
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"
	"google.golang.org/api/option"
)

var (
	// pushTTL is the fixed time-to-live for lab test messages.
	// Messages older than this will be discarded by FCM,
	// ensuring stale notifications don't clutter the device.
	pushTTL = time.Minute

	titleStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("12"))
	okStyle    = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("10"))
	errStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("9"))
)

func main() {
	account := flag.String("account", "", "path to the Firebase service account JSON key")
	flag.Parse()

	fmt.Println(titleStyle.Render("layrz_push · test notification sender"))

	path, err := resolveAccountPath(*account)
	if err != nil {
		fmt.Println(errStyle.Render("✗ " + err.Error()))
		os.Exit(1)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		fmt.Println(errStyle.Render("✗ " + err.Error()))
		os.Exit(1)
	}

	var sa struct {
		Type        string `json:"type"`
		ProjectID   string `json:"project_id"`
		ClientEmail string `json:"client_email"`
	}
	if err := json.Unmarshal(raw, &sa); err != nil || sa.Type != "service_account" || sa.ProjectID == "" {
		fmt.Println(errStyle.Render("✗ " + path + " is not a Firebase service account key"))
		os.Exit(1)
	}

	ctx := context.Background()
	app, err := firebase.NewApp(ctx, nil, option.WithCredentialsFile(path))
	if err != nil {
		fmt.Println(errStyle.Render("✗ failed to init Firebase: " + err.Error()))
		os.Exit(1)
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		fmt.Println(errStyle.Render("✗ failed to get Messaging client: " + err.Error()))
		os.Exit(1)
	}

	fmt.Printf("Project: %s (%s)\n\n", sa.ProjectID, sa.ClientEmail)

	topic := defaultTopic()
	title := "Hello from push-sender"
	body := "It works!"
	dataRaw := ""
	collapseID := ""
	channelID := ""

	for {
		form := huh.NewForm(huh.NewGroup(
			huh.NewInput().Title("Topic").Description("The lab subscribes to device_{deviceId}").Value(&topic),
			huh.NewInput().Title("Title").Value(&title),
			huh.NewInput().Title("Body").Value(&body),
			huh.NewInput().Title("Data").Description("Optional, key=value pairs separated by commas").Value(&dataRaw),
			huh.NewInput().Title("Collapse ID").Description("Optional, dedups banners for the same logical event on iOS, max 64 bytes").Value(&collapseID),
			huh.NewInput().Title("Android channel ID").Description("Optional, must match a channel created by the app").Value(&channelID),
		))
		if err := form.Run(); err != nil {
			return
		}

		msg, err := buildMessage(topic, title, body, dataRaw, collapseID, channelID, time.Now().Add(pushTTL))
		if err != nil {
			fmt.Println(errStyle.Render("✗ " + err.Error()))
			continue
		}

		id, err := client.Send(ctx, msg)
		if err != nil {
			fmt.Println(errStyle.Render("✗ " + err.Error()))
		} else {
			fmt.Println(okStyle.Render("✓ Sent: " + id))
		}

		again := true
		confirm := huh.NewForm(huh.NewGroup(huh.NewConfirm().Title("Send another?").Value(&again)))
		if err := confirm.Run(); err != nil || !again {
			return
		}
	}
}

// buildMessage constructs a Firebase messaging.Message with the given parameters.
// It validates that at least a notification or data is present, and applies
// platform-specific constraints (APNS collapse ID truncation, Android channel ID, etc.).
// The expiresAt time is used for the APNS expiration header.
func buildMessage(topic, title, body, dataRaw, collapseID, channelID string, expiresAt time.Time) (*messaging.Message, error) {
	topic = strings.TrimSpace(topic)
	if topic == "" {
		return nil, errors.New("topic is required")
	}

	// Determine if this is intended to be a notification message
	hasNotification := title != "" || body != ""

	// If creating a notification, both title and body are required
	if hasNotification && (title == "" || body == "") {
		return nil, errors.New("title and body are both required when creating an alert notification")
	}

	data, err := parseData(dataRaw)
	if err != nil {
		return nil, err
	}

	// For notification messages, add title/body to data
	if hasNotification {
		data["title"] = title
		data["body"] = body
	}

	// Truncate collapseID to APNS hard limit (64 bytes)
	if len(collapseID) > 64 {
		collapseID = collapseID[:64]
	}

	ttl := pushTTL

	msg := &messaging.Message{
		Topic: topic,
		Data:  data,
	}

	// Only set notification blocks if this is an alert notification
	if hasNotification {
		msg.Notification = &messaging.Notification{
			Title: title,
			Body:  body,
		}

		apnHeaders := map[string]string{
			"apns-priority":   "10",
			"apns-push-type":  "alert",
			"apns-expiration": strconv.FormatInt(expiresAt.Unix(), 10),
		}

		if collapseID != "" {
			apnHeaders["apns-collapse-id"] = collapseID
		}

		msg.APNS = &messaging.APNSConfig{
			Headers: apnHeaders,
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{
					Alert: &messaging.ApsAlert{
						Title: title,
						Body:  body,
					},
				},
			},
		}

		msg.Android = &messaging.AndroidConfig{
			Priority: "high",
			TTL:      &ttl,
			Notification: &messaging.AndroidNotification{
				Title:     title,
				Body:      body,
				ChannelID: channelID,
			},
		}
	} else {
		// Data-only message: set Android config for delivery only
		msg.Android = &messaging.AndroidConfig{
			Priority: "high",
			TTL:      &ttl,
		}
	}

	// Validate that message has content: either a notification or data
	if !hasNotification && len(msg.Data) == 0 {
		return nil, errors.New("nothing to send: set a title, a body or data")
	}

	return msg, nil
}

// parseData parses a comma-separated list of key=value pairs into a map.
func parseData(raw string) (map[string]string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return map[string]string{}, nil
	}

	data := map[string]string{}
	for _, pair := range strings.Split(raw, ",") {
		key, value, found := strings.Cut(strings.TrimSpace(pair), "=")
		if !found || strings.TrimSpace(key) == "" {
			return nil, fmt.Errorf("invalid data pair %q, expected key=value", pair)
		}
		data[strings.TrimSpace(key)] = strings.TrimSpace(value)
	}
	return data, nil
}

// resolveAccountPath finds the service account key: the -account flag, common
// locations, or an interactive prompt as a last resort.
func resolveAccountPath(flagValue string) (string, error) {
	if flagValue != "" {
		return flagValue, nil
	}

	candidates := []string{
		"service-account.json",
		filepath.Join("tools", "push-sender", "service-account.json"),
	}
	for _, candidate := range candidates {
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}

	var path string
	form := huh.NewForm(huh.NewGroup(
		huh.NewInput().
			Title("Path to the service account JSON key").
			Description("Firebase console → Project settings → Service accounts → Generate new private key").
			Value(&path),
	))
	if err := form.Run(); err != nil {
		return "", err
	}
	if strings.TrimSpace(path) == "" {
		return "", errors.New("no service account key provided")
	}
	return strings.TrimSpace(path), nil
}

// defaultTopic prefills the topic from the lab's secrets.json device id.
func defaultTopic() string {
	candidates := []string{
		filepath.Join("example", "assets", "secrets.json"),
		filepath.Join("..", "..", "example", "assets", "secrets.json"),
	}
	for _, candidate := range candidates {
		raw, err := os.ReadFile(candidate)
		if err != nil {
			continue
		}
		var secrets struct {
			DeviceID string `json:"deviceId"`
		}
		if err := json.Unmarshal(raw, &secrets); err == nil && secrets.DeviceID != "" {
			return "device_" + secrets.DeviceID
		}
	}
	return "device_"
}
