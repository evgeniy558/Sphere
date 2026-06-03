package music

import "testing"

func TestIsProviderStreamEndpoint(t *testing.T) {
	cases := []struct {
		url  string
		want bool
	}{
		{"https://api.soundcloud.com/tracks/x/stream", true},
		{"https://cf-media.sndcdn.com/mp3.mp3", false},
		{"https://rr1---sn-xyz.googlevideo.com/videoplayback?expire=1", false},
	}
	for _, c := range cases {
		if got := IsProviderStreamEndpoint(c.url); got != c.want {
			t.Fatalf("IsProviderStreamEndpoint(%q)=%v want %v", c.url, got, c.want)
		}
	}
}

func TestValidateResolvedStreamURL(t *testing.T) {
	if err := ValidateResolvedStreamURL("https://api.soundcloud.com/x"); err == nil {
		t.Fatal("expected error for soundcloud api url")
	}
	if err := ValidateResolvedStreamURL("https://cf-media.sndcdn.com/x.mp3"); err != nil {
		t.Fatalf("unexpected: %v", err)
	}
}
