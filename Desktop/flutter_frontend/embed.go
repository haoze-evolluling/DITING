// Package flutter_frontend embeds the Flutter desktop shell separately from
// the Vue application used by the LAN web console.
package flutter_frontend

import "embed"

// Assets contains the release output of DITING-Flutter/lib/desktop/main.dart.
//
//go:embed all:dist
var Assets embed.FS
