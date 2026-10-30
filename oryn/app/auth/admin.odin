package auth

import gh "oryn:gjallarhorn"

ADMIN_SESSION_KEY :: "_auid"

admin_login :: proc(b: ^gh.Bifrost, user_id: string) {
	gh.session_set(b, ADMIN_SESSION_KEY, user_id)
}

admin_logout :: proc(b: ^gh.Bifrost) {
	gh.session_delete(b, ADMIN_SESSION_KEY)
}

admin_current_user :: proc(b: ^gh.Bifrost) -> (string, bool) {
	return gh.session_get(b, ADMIN_SESSION_KEY)
}

admin_require_login :: proc(b: ^gh.Bifrost) -> bool {
	if _, ok := admin_current_user(b); ok {
		return true
	}

    return false
}
