#!/usr/bin/env bash
#
# Local preview with live reload at http://localhost:1313
#
# No config editing is needed: `hugo server` overrides baseURL to localhost by
# itself, which is what made the old Jekyll `url:` juggling unnecessary.
set -euo pipefail
exec hugo server -D --navigateToChanged "$@"
