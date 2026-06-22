//go:build darwin

package agent

import (
	"context"
	"testing"
)

// Smoke test: exercises the real smctemp-backed getSensorTemps on this Mac.
// Skips automatically if smctemp is not installed.
func TestGetSensorTempsDarwinSmoke(t *testing.T) {
	temps, err := getSensorTemps(context.Background())
	if err != nil {
		t.Fatalf("getSensorTemps returned error: %v", err)
	}
	if len(temps) == 0 {
		t.Skip("no temps returned (is smctemp installed and on PATH?)")
	}
	for _, s := range temps {
		t.Logf("sensor %q = %.1f°C", s.SensorKey, s.Temperature)
		if s.Temperature <= 0 || s.Temperature >= 200 {
			t.Errorf("sensor %q out of range: %.1f", s.SensorKey, s.Temperature)
		}
	}
}
