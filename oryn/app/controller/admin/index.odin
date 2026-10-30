package admin

import "core:fmt"

import "oryn:jinja"
import gh "oryn:gjallarhorn"

import "oryn:app/auth"
import "oryn:app/view"
import "oryn:app/model"
import "oryn:app/config"

index_index :: proc(b: ^gh.Bifrost) {
	username, _ := auth.admin_current_user(b)

	data := jinja.dict()
	jinja.set(data, "username", username)

	output, _ := view.render("admin/index/index.html", data)

	view.return_html(b, output)
}

index_console :: proc(b: ^gh.Bifrost) {
	data := jinja.dict()
	output, _ := view.render("admin/index/console.html", data)

	view.return_html(b, output)
}

index_menus :: proc(b: ^gh.Bifrost) {
	data := config.Amin_Menus

	view.return_json_raw(b, data)
}

