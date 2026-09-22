//go:build tools

// Tools dependency anchor ensuring go modules track required gomobile toolchain binaries.

package tunnel

import (
	_ "github.com/sagernet/gomobile/bind"
	_ "github.com/sagernet/gomobile/cmd/gomobile"
	_ "golang.org/x/mobile/bind"
	_ "golang.org/x/mobile/cmd/gobind"
	_ "golang.org/x/mobile/cmd/gomobile"
)
