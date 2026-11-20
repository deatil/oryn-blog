package admin

import "oryn:jinja"
import gh "oryn:gjallarhorn"

import "oryn:app/view"
import "oryn:app/model"

setting_index :: proc(b: ^gh.Bifrost) {
	items := model.get_settings()

	data := jinja.dict()
	for item in items {
		jinja.set(data, item["name"], item["value"])
	}

	ctx := jinja.dict()
	jinja.set(ctx, "data", data)
	
	output, _ := view.render("admin/setting/index.html", ctx)

	view.return_html(b, output)
}

setting_save :: proc(b: ^gh.Bifrost) {
	fields := gh.form(b)

	for k, v in fields {
		model.update_setting(k, v)
	}

	view.return_success(b, "修改成功")
}

