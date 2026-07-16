// push-sender is a TUI companion for the layrz_push example lab.
//
// It sends test push notifications to an FCM topic using the HTTP v1 API,
// authenticated with a Firebase service account key (Firebase console →
// Project settings → Service accounts → Generate new private key).
//
// Usage:
//
//	cd tools/push-sender && go run . [-account service-account.json]
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"
	"golang.org/x/oauth2/google"
)

type notification struct {
	Title string `json:"title,omitempty"`
	Body  string `json:"body,omitempty"`
}

type message struct {
	Topic        string            `json:"topic"`
	Notification *notification     `json:"notification,omitempty"`
	Data         map[string]string `json:"data,omitempty"`
}

type sendRequest struct {
	Message message `json:"message"`
}

var (
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

	conf, err := google.JWTConfigFromJSON(raw, "https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		fmt.Println(errStyle.Render("✗ invalid service account key: " + err.Error()))
		os.Exit(1)
	}
	client := conf.Client(context.Background())

	fmt.Printf("Project: %s (%s)\n\n", sa.ProjectID, sa.ClientEmail)

	topic := defaultTopic()
	title := "Hello from push-sender"
	body := "It works!"
	dataRaw := ""

	for {
		form := huh.NewForm(huh.NewGroup(
			huh.NewInput().Title("Topic").Description("The lab subscribes to device_{deviceId}").Value(&topic),
			huh.NewInput().Title("Title").Value(&title),
			huh.NewInput().Title("Body").Value(&body),
			huh.NewInput().Title("Data").Description("Optional, key=value pairs separated by commas").Value(&dataRaw),
		))
		if err := form.Run(); err != nil {
			return
		}

		msg, err := buildMessage(topic, title, body, dataRaw)
		if err != nil {
			fmt.Println(errStyle.Render("✗ " + err.Error()))
			continue
		}

		id, err := send(client, sa.ProjectID, msg)
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

func buildMessage(topic, title, body, dataRaw string) (message, error) {
	topic = strings.TrimSpace(topic)
	if topic == "" {
		return message{}, errors.New("topic is required")
	}

	data, err := parseData(dataRaw)
	if err != nil {
		return message{}, err
	}

	msg := message{Topic: topic, Data: data}
	if title != "" || body != "" {
		msg.Notification = &notification{Title: title, Body: body}
	}
	if msg.Notification == nil && len(msg.Data) == 0 {
		return message{}, errors.New("nothing to send: set a title, a body or data")
	}
	return msg, nil
}

func parseData(raw string) (map[string]string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, nil
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

func send(client *http.Client, projectID string, msg message) (string, error) {
	payload, err := json.Marshal(sendRequest{Message: msg})
	if err != nil {
		return "", err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", projectID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("FCM returned %s: %s", resp.Status, strings.TrimSpace(string(respBody)))
	}

	var out struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal(respBody, &out); err != nil {
		return "", err
	}
	return out.Name, nil
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
