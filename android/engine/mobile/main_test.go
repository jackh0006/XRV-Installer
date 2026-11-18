package main

import "testing"

func TestValidCredential(t *testing.T) {
	cases := []struct {
		value string
		max   int
		want  bool
	}{
		{"xrv0123456789", 64, true},
		{"ABCxyz019", 64, true},
		{"", 64, false},
		{"bad!", 64, false},
		{"with space", 64, false},
		{"aaaaaaaaaa", 4, false},
	}
	for _, tc := range cases {
		if got := validCredential(tc.value, tc.max); got != tc.want {
			t.Errorf("validCredential(%q, %d) = %v, want %v", tc.value, tc.max, got, tc.want)
		}
	}
}

func TestUniqueIPv4(t *testing.T) {
	got := uniqueIPv4([]string{
		"216.239.32.120",
		" 216.239.38.120 ",
		"216.239.32.120",
		"not-an-ip",
		"999.1.1.1",
	})
	want := []string{"216.239.32.120", "216.239.38.120"}
	if len(got) != len(want) {
		t.Fatalf("uniqueIPv4 length = %d, want %d (%v)", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("uniqueIPv4[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}

func TestFrontingAddress(t *testing.T) {
	cases := map[string]string{
		"216.239.38.120":      "216.239.38.120:443",
		" 216.239.38.120 ":    "216.239.38.120:443",
		"216.239.38.120:8443": "216.239.38.120:8443",
	}
	for in, want := range cases {
		if got := frontingAddress(in); got != want {
			t.Errorf("frontingAddress(%q) = %q, want %q", in, got, want)
		}
	}
}
