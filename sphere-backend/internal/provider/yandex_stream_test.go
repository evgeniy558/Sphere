package provider

import (
	"strings"
	"testing"
)

func TestYandexBuildMP3URLFromXML(t *testing.T) {
	xml := []byte(`<?xml version="1.0"?><downloadInfo><host>strm-storage10.strm.yandex.net</host><path>/file.mp3</path><ts>123</ts><s>abc</s></downloadInfo>`)
	url, err := yandexBuildMP3URLFromXML(xml)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(url, "https://strm-storage10.strm.yandex.net/get-mp3/") {
		t.Fatalf("unexpected url: %s", url)
	}
	if !strings.HasSuffix(url, "/123/file.mp3") {
		t.Fatalf("expected ts+path in url: %s", url)
	}
}

func TestYandexSignRequestDeterministicMessage(t *testing.T) {
	s := yandexSignRequest("565378", yandexDefaultSignKey)
	if s.Timestamp <= 0 {
		t.Fatal("expected positive timestamp")
	}
	if s.Value == "" {
		t.Fatal("expected non-empty sign")
	}
}

func TestYandexNumericTrackID(t *testing.T) {
	if got := yandexNumericTrackID("track:42"); got != "42" {
		t.Fatalf("got %q", got)
	}
}
