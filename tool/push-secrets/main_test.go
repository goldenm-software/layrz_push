package main

import "testing"

const sampleGoogleServices = `{
  "project_info": {
    "project_number": "1018366576798",
    "project_id": "push-multi-tenant-lab",
    "storage_bucket": "push-multi-tenant-lab.firebasestorage.app"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:1018366576798:android:7c8b37b0089bdf3e7f938f",
        "android_client_info": {
          "package_name": "com.example.layrz_push_example"
        }
      },
      "oauth_client": [],
      "api_key": [
        {
          "current_key": "AIzaSyEXAMPLE"
        }
      ]
    }
  ],
  "configuration_version": "1"
}`

const samplePlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>API_KEY</key>
	<string>AIzaSyEXAMPLE</string>
	<key>GCM_SENDER_ID</key>
	<string>1018366576798</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>com.example.layrzPushExample</string>
	<key>PROJECT_ID</key>
	<string>push-multi-tenant-lab</string>
	<key>STORAGE_BUCKET</key>
	<string>push-multi-tenant-lab.firebasestorage.app</string>
	<key>IS_ADS_ENABLED</key>
	<false></false>
	<key>GOOGLE_APP_ID</key>
	<string>1:1018366576798:ios:aabbccddeeff0011</string>
</dict>
</plist>`

func TestParseGoogleServices(t *testing.T) {
	creds, err := parseGoogleServices(sampleGoogleServices)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if creds.APIKey != "AIzaSyEXAMPLE" {
		t.Errorf("apiKey = %q", creds.APIKey)
	}
	if creds.AppID != "1:1018366576798:android:7c8b37b0089bdf3e7f938f" {
		t.Errorf("appId = %q", creds.AppID)
	}
	if creds.ProjectID != "push-multi-tenant-lab" {
		t.Errorf("projectId = %q", creds.ProjectID)
	}
	if creds.MessagingSenderID != "1018366576798" {
		t.Errorf("messagingSenderId = %q", creds.MessagingSenderID)
	}
	if creds.StorageBucket == nil || *creds.StorageBucket != "push-multi-tenant-lab.firebasestorage.app" {
		t.Errorf("storageBucket = %v", creds.StorageBucket)
	}
}

func TestParsePlist(t *testing.T) {
	creds, err := parsePlist(samplePlist)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if creds.APIKey != "AIzaSyEXAMPLE" {
		t.Errorf("apiKey = %q", creds.APIKey)
	}
	if creds.AppID != "1:1018366576798:ios:aabbccddeeff0011" {
		t.Errorf("appId = %q", creds.AppID)
	}
	if creds.ProjectID != "push-multi-tenant-lab" {
		t.Errorf("projectId = %q", creds.ProjectID)
	}
	if creds.MessagingSenderID != "1018366576798" {
		t.Errorf("messagingSenderId = %q", creds.MessagingSenderID)
	}
	if creds.StorageBucket == nil || *creds.StorageBucket != "push-multi-tenant-lab.firebasestorage.app" {
		t.Errorf("storageBucket = %v", creds.StorageBucket)
	}
}

func TestParsePlistMissingKeys(t *testing.T) {
	if _, err := parsePlist(`<plist version="1.0"><dict><key>API_KEY</key><string>x</string></dict></plist>`); err == nil {
		t.Error("expected an error for incomplete plist")
	}
}
