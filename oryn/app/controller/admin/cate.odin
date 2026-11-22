package admin

import "core:fmt"
import "core:time"
import "core:math"
import "core:strconv"
import "core:encoding/json"

import "oryn:jinja"
import gh "oryn:gjallarhorn"

import "oryn:app/auth"
import "oryn:app/view"
import "oryn:app/model"
import "oryn:app/utils"

cate_index :: proc(b: ^gh.Bifrost) {
	count := model.get_cate_count()

	data := jinja.dict()
	jinja.set(data, "count", count)
	
	output, _ := view.render("admin/cate/index.html", data)

	view.return_html(b, output)
}

cate_data :: proc(b: ^gh.Bifrost) {
	page, _ := gh.query_param(b, "page")
	limit, _ := gh.query_param(b, "limit")

	if len(page) == 0 {
		page = "1"
	}
	new_page, _ := strconv.parse_int(page)
	new_page = math.max(1, new_page)

	if len(limit) == 0 {
		limit = "10"
	}
	new_limit, _ := strconv.parse_int(limit)
	new_limit = math.max(1, new_limit)

	lists := model.get_cates(model.Cate_Where{
		offset = (new_page - 1) * 10,
        limit = new_limit,
		status = -1,
	})

	count := model.get_cate_count()

	list := make(json.Array)
	for i := 0; i < len(lists); i += 1 {
		d := make(json.Object)
		for k, v in lists[i] {
			d[k] = json.String(v)
		}
		append(&list, json.Value(d))
	}

	data := make(json.Object)
	data["count"] = json.String(count)
	data["list"] = list

	view.return_success(b, "获取成功", data)
}

cate_create :: proc(b: ^gh.Bifrost) {
	data := jinja.dict()	
	output, _ := view.render("admin/cate/create.html", data)

	view.return_html(b, output)
}

cate_create_save :: proc(b: ^gh.Bifrost) {
	fields := gh.form(b)

	name := fields["name"]
	if name == "" {
		view.return_error(b, "名称不能为空")
		return
	}
	slug := fields["slug"]
	if slug == "" {
		view.return_error(b, "标识不能为空")
		return
	}

	item := model.get_cate_by_slug(slug)
	if item != nil {
		view.return_error(b, "标识已经存在")
		return
	}

	data := make(map[string]string)
	data["name"] = name
	data["slug"] = slug
	data["add_time"] = fmt.tprintf("%v", time.time_to_unix(time.now()))
	data["add_ip"] = gh.client_ip(b)

	if !model.add_cate(data) {
		view.return_error(b, "添加失败")
		return
	}

	view.return_success(b, "添加成功")
}

cate_edit :: proc(b: ^gh.Bifrost) {
	id, _ := gh.query_param(b, "id")
	item := model.get_cate(id)

	ctx := jinja.dict()
	jinja.set(ctx, "id", jinja.str(item["id"]))
	jinja.set(ctx, "name", jinja.str(item["name"]))
	jinja.set(ctx, "slug", jinja.str(item["slug"]))
	jinja.set(ctx, "desc", jinja.str(item["desc"]))
	jinja.set(ctx, "sort", jinja.str(item["sort"]))
	jinja.set(ctx, "status", jinja.str(item["status"]))

	data := jinja.dict()
	jinja.set(data, "data", ctx)

	output, _ := view.render("admin/cate/edit.html", data)

	view.return_html(b, output)
}

cate_edit_save :: proc(b: ^gh.Bifrost) {
	id, ok := gh.query_param(b, "id")
	if !ok {
		view.return_error(b, "ID不能为空")
		return
	}

	fields := gh.form(b)

	name := fields["name"]
	if name == "" {
		view.return_error(b, "名称不能为空")
		return
	}
	slug := fields["slug"]
	if slug == "" {
		view.return_error(b, "标识不能为空")
		return
	}

	item := model.get_cate_by_slug(slug)
	if item != nil && item["id"] != id {
		view.return_error(b, "标识已经存在")
		return
	}

	data := make(map[string]string)
	data["name"] = name
	data["slug"] = slug
	data["desc"] = fields["desc"]
	data["sort"] = fields["sort"]
	data["status"] = fields["status"]

	if !model.update_cate(id, data) {
		view.return_error(b, "修改失败")
		return
	}

	view.return_success(b, "修改成功")
}

cate_del :: proc(b: ^gh.Bifrost) {
	id, ok := gh.query_param(b, "id")
	if !ok {
		view.return_error(b, "ID不能为空")
		return
	}

	if !model.delete_cate(id) {
		view.return_error(b, "删除失败")
		return
	}

	view.return_success(b, "删除成功")
}
