// SPDX-FileCopyrightText: Copyright The Lima Authors
// SPDX-License-Identifier: Apache-2.0

// mayhem/kat/main.go — dynamically-linked known-answer probe for lima's download
// digest option. `import "C"` (cgo) forces a dynamically linked binary so the
// gate's LD_PRELOAD sabotage shim can neuter it. It imports the package staged
// by mayhem/build.sh at _mayhem_harness/downloader and prints fixed values for
// mayhem/test.sh to assert.
package main

// #include <stdint.h>
import "C"

import (
	"fmt"

	downloader "github.com/lima-vm/lima/v2/_mayhem_harness/downloader"
)

func main() {
	accepted, algo, badRejected := downloader.KATDigest()
	fmt.Printf("KAT_DIGEST=%s\n", accepted)
	fmt.Printf("KAT_ALGO=%s\n", algo)
	fmt.Printf("KAT_BAD_REJECTED=%t\n", badRejected)
}
