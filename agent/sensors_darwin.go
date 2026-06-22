//go:build darwin

package agent

import (
	"context"
	"os/exec"
	"strconv"
	"strings"

	"github.com/henrygd/beszel/agent/utils"

	"github.com/shirou/gopsutil/v4/sensors"
)

// macOS exposes no temperature sensors through gopsutil (the Darwin sensors
// implementation is a no-op), so the agent reports nothing by default. We close
// that gap by shelling out to `smctemp`, a small external tool that reads CPU/GPU
// temperatures from the Apple SMC.
//
// This mirrors the Windows integration (sensors_windows.go), which shells out to
// an external LibreHardwareMonitor helper. Keeping smctemp as a separate process
// is also deliberate on licensing grounds: smctemp is GPL-2.0 while Beszel is MIT,
// so an arm's-length subprocess avoids mixing the two in one binary.
//
// Requirements: `smctemp` must be installed (e.g. `brew install smctemp`). Override
// the binary location with SMCTEMP_PATH (or BESZEL_AGENT_SMCTEMP_PATH) if it is not
// on PATH. smctemp only reads temperatures, not fan RPM, so no fan data is reported.

// smctempReads maps the sensor name shown in the Beszel Temperature card to the
// smctemp CLI flag that produces it.
var smctempReads = []struct {
	name string
	flag string
}{
	{"CPU", "-c"},
	{"GPU", "-g"},
}

// getSensorTemps collects temperatures on macOS by invoking smctemp once per
// sensor. It never returns an error: a missing binary or a sensor that does not
// exist on this Mac (e.g. no discrete GPU) is simply skipped so the agent keeps
// reporting whatever is available. The whole call runs inside the caller's
// timeout (see Agent.getTempsWithTimeout), so reads are kept short.
func getSensorTemps(ctx context.Context) ([]sensors.TemperatureStat, error) {
	bin := "smctemp"
	if p, ok := utils.GetEnv("SMCTEMP_PATH"); ok && p != "" {
		bin = p
	}

	temps := make([]sensors.TemperatureStat, 0, len(smctempReads))
	for _, r := range smctempReads {
		v, err := readSmctemp(ctx, bin, r.flag)
		if err != nil || v <= 0 {
			continue
		}
		temps = append(temps, sensors.TemperatureStat{
			SensorKey:   r.name,
			Temperature: v,
		})
	}
	return temps, nil
}

// readSmctemp runs `smctemp <flag>` and parses the single temperature it prints
// to stdout. The retry flags (-n3 -i200) ride out occasional empty SMC reads
// while staying well under the agent's sensor timeout; smctemp exits non-zero
// and prints 0.0 when it cannot read a valid value, which surfaces here as an
// error or a non-positive value and is skipped by the caller.
func readSmctemp(ctx context.Context, bin, flag string) (float64, error) {
	out, err := exec.CommandContext(ctx, bin, flag, "-n3", "-i200").Output()
	if err != nil {
		return 0, err
	}
	return strconv.ParseFloat(strings.TrimSpace(string(out)), 64)
}
