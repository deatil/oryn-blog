package middleware

import "core:strings"

import gh "oryn:gjallarhorn"

import "oryn:app/auth"
import "oryn:app/view"

admin_auth :: proc(b: ^gh.Bifrost, next: gh.Next) {
	path := b.path
	if strings.starts_with(path, "/admin") {
		if strings.starts_with(path, "/admin/auth") {
			next(b)
			return
		}

		ok := auth.admin_require_login(b)
		if !ok {
			if b.method == .Post {
				view.return_error(b, "请先登陆")
				return
			} else {
				view.return_text(b, "请先登陆")
				return
			}
		}
	}

	next(b)
}

