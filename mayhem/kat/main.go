// SPDX-FileCopyrightText: Copyright The Lima Authors
// SPDX-License-Identifier: Apache-2.0

// mayhem/kat/main.go — dynamically-linked known-answer probe for lima's YAML
// config parser. `import "C"` (cgo) forces a DYNAMICALLY LINKED binary so the
// LD_PRELOAD sabotage shim used by the gate's anti-reward-hacking check can
// neuter it (a statically-linked Go binary would be immune, giving a
// false-green oracle — exactly the trap netnew §4 warns about with `go test`
// alone).
//
// It imports the build-time-staged internal package (created by mayhem/build.sh
// at _mayhem_harness/limayaml) and runs KATParse(), which decodes a fixed
// LimaYAML document through the real Unmarshal path, then prints the decoded
// fields in a fixed, greppable format for mayhem/test.sh to assert.
package main

// #include <stdint.h>
import "C"

import (
	"fmt"
	"os"

	limayaml "github.com/lima-vm/lima/v2/_mayhem_harness/limayaml"
)

func main() {
	cpus, memory, arch, message, err := limayaml.KATParse()
	if err != nil {
		fmt.Fprintf(os.Stderr, "KAT error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("KAT_CPUS=%d\n", cpus)
	fmt.Printf("KAT_MEMORY=%s\n", memory)
	fmt.Printf("KAT_ARCH=%s\n", arch)
	fmt.Printf("KAT_MESSAGE=%s\n", message)
}
