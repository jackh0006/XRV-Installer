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
