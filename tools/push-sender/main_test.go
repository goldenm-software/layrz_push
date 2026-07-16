package main

import (
	"encoding/json"
	"testing"
)

func TestBuildMessageFull(t *testing.T) {
	msg, err := buildMessage("device_test", "Title", "Body", "foo=bar, baz=qux")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	raw, _ := json.Marshal(sendRequest{Message: msg})
	want := `{"message":{"topic":"device_test","notification":{"title":"Title","body":"Body"},"data":{"baz":"qux","foo":"bar"}}}`
	if string(raw) != want {
		t.Errorf("payload = %s\nwant %s", raw, want)
	}
}

func TestBuildMessageDataOnly(t *testing.T) {
	msg, err := buildMessage("device_test", "", "", "foo=bar")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if msg.Notification != nil {
		t.Error("expected no notification block for a data-only message")
	}
}

func TestBuildMessageEmpty(t *testing.T) {
	if _, err := buildMessage("device_test", "", "", ""); err == nil {
		t.Error("expected an error when there is nothing to send")
	}
	if _, err := buildMessage("", "Title", "", ""); err == nil {
		t.Error("expected an error when the topic is empty")
	}
}

func TestParseDataInvalid(t *testing.T) {
	if _, err := parseData("not-a-pair"); err == nil {
		t.Error("expected an error for a pair without '='")
	}
	if _, err := parseData("=value"); err == nil {
		t.Error("expected an error for an empty key")
	}
}
