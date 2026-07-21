package main

import (
	"testing"
	"time"
)

func TestBuildMessageFull(t *testing.T) {
	expiresAt := time.Unix(2000, 0)
	msg, err := buildMessage("device_test", "Title", "Body", "foo=bar, baz=qux", "", "", expiresAt)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if msg.Topic != "device_test" {
		t.Errorf("topic = %q, want %q", msg.Topic, "device_test")
	}
	if msg.Notification == nil {
		t.Error("expected notification block")
	} else {
		if msg.Notification.Title != "Title" {
			t.Errorf("notification.title = %q, want %q", msg.Notification.Title, "Title")
		}
		if msg.Notification.Body != "Body" {
			t.Errorf("notification.body = %q, want %q", msg.Notification.Body, "Body")
		}
	}
	if msg.Data["foo"] != "bar" || msg.Data["baz"] != "qux" {
		t.Errorf("data = %v, want foo=bar and baz=qux", msg.Data)
	}
	if msg.Android == nil {
		t.Error("expected Android config")
	} else {
		if msg.Android.Priority != "high" {
			t.Errorf("android.priority = %q, want %q", msg.Android.Priority, "high")
		}
		if msg.Android.TTL == nil || *msg.Android.TTL != pushTTL {
			t.Errorf("android.ttl not set to pushTTL")
		}
	}
	if msg.APNS == nil {
		t.Error("expected APNS config for alert notification")
	} else {
		if msg.APNS.Headers["apns-priority"] != "10" {
			t.Errorf("apns-priority = %q, want %q", msg.APNS.Headers["apns-priority"], "10")
		}
		if msg.APNS.Headers["apns-push-type"] != "alert" {
			t.Errorf("apns-push-type = %q, want %q", msg.APNS.Headers["apns-push-type"], "alert")
		}
		if msg.APNS.Headers["apns-expiration"] != "2000" {
			t.Errorf("apns-expiration = %q, want %q", msg.APNS.Headers["apns-expiration"], "2000")
		}
		if _, hasCollapseID := msg.APNS.Headers["apns-collapse-id"]; hasCollapseID {
			t.Error("expected no apns-collapse-id header when collapseID is empty")
		}
	}
}

func TestBuildMessageDataOnly(t *testing.T) {
	expiresAt := time.Unix(2000, 0)
	msg, err := buildMessage("device_test", "", "", "foo=bar", "", "", expiresAt)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if msg.Notification != nil {
		t.Error("expected no notification block for a data-only message")
	}
	if msg.APNS != nil {
		t.Error("expected no APNS config for data-only message")
	}
	if msg.Data["foo"] != "bar" {
		t.Errorf("data = %v, want foo=bar", msg.Data)
	}
}

func TestBuildMessageCollapseIDTruncation(t *testing.T) {
	expiresAt := time.Unix(2000, 0)
	// Create a 100-character string
	longID := ""
	for i := 0; i < 100; i++ {
		longID += "a"
	}
	msg, err := buildMessage("device_test", "Title", "Body", "", longID, "", expiresAt)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if msg.APNS == nil {
		t.Error("expected APNS config")
		return
	}
	collapseID := msg.APNS.Headers["apns-collapse-id"]
	if len(collapseID) != 64 {
		t.Errorf("collapse ID length = %d, want 64", len(collapseID))
	}
	if collapseID != longID[:64] {
		t.Errorf("collapse ID not truncated correctly")
	}
}

func TestBuildMessageChannelID(t *testing.T) {
	expiresAt := time.Unix(2000, 0)
	msg, err := buildMessage("device_test", "Title", "Body", "", "", "my_channel", expiresAt)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if msg.Android == nil || msg.Android.Notification == nil {
		t.Error("expected Android notification block when channelID is set")
	} else {
		if msg.Android.Notification.ChannelID != "my_channel" {
			t.Errorf("channel_id = %q, want %q", msg.Android.Notification.ChannelID, "my_channel")
		}
	}
	if msg.Notification == nil {
		t.Error("expected notification block when title is provided")
	} else {
		if msg.Notification.Title != "Title" {
			t.Errorf("notification.title = %q, want %q", msg.Notification.Title, "Title")
		}
	}
}

func TestBuildMessageEmpty(t *testing.T) {
	expiresAt := time.Unix(2000, 0)
	if _, err := buildMessage("device_test", "", "", "", "", "", expiresAt); err == nil {
		t.Error("expected an error when there is nothing to send")
	}
	if _, err := buildMessage("", "Title", "Body", "", "", "", expiresAt); err == nil {
		t.Error("expected an error when the topic is empty")
	}
	if _, err := buildMessage("device_test", "Title", "", "", "", "", expiresAt); err == nil {
		t.Error("expected error when title provided but body is empty")
	}
	if _, err := buildMessage("device_test", "", "Body", "", "", "", expiresAt); err == nil {
		t.Error("expected error when body provided but title is empty")
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
