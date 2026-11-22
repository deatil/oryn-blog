package index

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

index :: proc(b: ^gh.Bifrost) {
	page, _ := gh.query_param(b, "page")
	if len(page) == 0 {
		page = "1"
	}
	new_page, _ := strconv.parse_int(page)
	new_page = math.max(1, new_page)

	per_page := 10
	lists := model.get_arts(model.Art_Where{
		offset = (new_page - 1) * per_page,
        limit = per_page,
		status = 1,
	})

	count := model.get_art_count_where(model.Art_Where{
		status = 1,
	})
	new_count, _ := strconv.parse_int(count)

	pages := math.ceil(f64(new_count) / f64(per_page))

	list := jinja.list()
	for item in lists {
		d := jinja.dict()
		jinja.set(d, "id", jinja.str(item["id"]))
		jinja.set(d, "title", jinja.str(item["title"]))
		jinja.set(d, "description", jinja.str(item["description"]))
		jinja.set(d, "tags", jinja.str(item["tags"]))
		jinja.set(d, "from", jinja.str(item["from"]))
		jinja.set(d, "views", jinja.str(item["views"]))
		jinja.set(d, "username", jinja.str(item["username"]))
		jinja.set(d, "is_top", jinja.str(item["is_top"]))
		jinja.set(d, "add_time", jinja.str(item["add_time"]))

		jinja.append_value(list, d)
	}

	cates := get_cates()

	data := jinja.dict()
	jinja.set(data, "count", jinja.integer(i64(new_count)))
	jinja.set(data, "list", list)
	jinja.set(data, "cates", cates)
	
	jinja.set(data, "page", jinja.integer(i64(new_page)))
	jinja.set(data, "pages", jinja.integer(i64(pages)))

    if new_page > 1 && pages > 1 {
		jinja.set(data, "page1", jinja.integer(i64(new_page) - 1))
    }
    if new_page < int(pages) && pages > 1 {
		jinja.set(data, "page2", jinja.integer(i64(new_page) + 1))
    }

	output, err := view.render("index/index.html", data)
	if err != "" {
		view.return_text(b, err)
		return
	}
	view.return_html(b, output)
}

cate :: proc(b: ^gh.Bifrost) {
	slug, _ := gh.param(b, "slug")
	if len(slug) == 0 {
		view.return_text(b, "分类标识不能为空")
		return
	}

	page, _ := gh.query_param(b, "page")
	if len(page) == 0 {
		page = "1"
	}
	new_page, _ := strconv.parse_int(page)
	new_page = math.max(1, new_page)

	cate_info := model.get_cate_by_slug(slug)

	lists := model.get_arts(model.Art_Where{
		offset = (new_page - 1) * 10,
		wheres = fmt.tprintf("AND cate_id = '%s'", cate_info["id"]),
        limit = 10,
		status = 1,
	})

	count := model.get_art_count_where(model.Art_Where{
		wheres = fmt.tprintf("AND cate_id = '%s'", cate_info["id"]),
		status = 1,
	})
	new_count, _ := strconv.parse_int(count)

	pages := math.ceil(f64(new_count) / 10)

	list := jinja.list()
	for item in lists {
		d := jinja.dict()
		jinja.set(d, "id", jinja.str(item["id"]))
		jinja.set(d, "title", jinja.str(item["title"]))
		jinja.set(d, "description", jinja.str(item["description"]))
		jinja.set(d, "tags", jinja.str(item["tags"]))
		jinja.set(d, "from", jinja.str(item["from"]))
		jinja.set(d, "views", jinja.str(item["views"]))
		jinja.set(d, "username", jinja.str(item["username"]))
		jinja.set(d, "is_top", jinja.str(item["is_top"]))
		jinja.set(d, "add_time", jinja.str(item["add_time"]))

		jinja.append_value(list, d)
	}

	cate := get_cate(cate_info["id"])
	cates := get_cates()

	data := jinja.dict()
	jinja.set(data, "count", jinja.integer(i64(new_count)))
	jinja.set(data, "list", list)
	jinja.set(data, "cates", cates)
	jinja.set(data, "cate", cate)

	jinja.set(data, "page", jinja.integer(i64(new_page)))
	jinja.set(data, "pages", jinja.integer(i64(pages)))

    if new_page > 1 && pages > 1 {
		jinja.set(data, "page1", jinja.integer(i64(new_page) - 1))
    }
    if new_page < int(pages) && pages > 1 {
		jinja.set(data, "page2", jinja.integer(i64(new_page) + 1))
    }

	output, err := view.render("index/cate.html", data)
	if err != "" {
		view.return_text(b, err)
		return
	}

	view.return_html(b, output)
}

art :: proc(b: ^gh.Bifrost) {
	id, _ := gh.param(b, "id")
	if len(id) == 0 {
		view.return_text(b, "文章不存在")
		return
	}

	item := model.get_art(id)
	if item == nil {
		view.return_text(b, "文章不存在")
		return
	}

	ctx := jinja.dict()
	jinja.set(ctx, "id", jinja.str(item["id"]))
	jinja.set(ctx, "cate_id", jinja.str(item["cate_id"]))
	jinja.set(ctx, "title", jinja.str(item["title"]))
	jinja.set(ctx, "keywords", jinja.str(item["keywords"]))
	jinja.set(ctx, "description", jinja.str(item["description"]))
	jinja.set(ctx, "content", jinja.str(item["content"]))
	jinja.set(ctx, "tags", jinja.str(item["tags"]))
	jinja.set(ctx, "from", jinja.str(item["from"]))
	jinja.set(ctx, "views", jinja.str(item["views"]))
	jinja.set(ctx, "is_top", jinja.str(item["is_top"]))
	jinja.set(ctx, "status", jinja.str(item["status"]))

	// comment list
	page, _ := gh.query_param(b, "page")
	if len(page) == 0 {
		page = "1"
	}
	new_page, _ := strconv.parse_int(page)
	new_page = math.max(1, new_page)

	comment_list := model.get_comments(model.Comment_Where{
		offset = (new_page - 1) * 10,
		wheres = fmt.tprintf("AND art_id = '%s'", item["id"]),
        limit = 10,
		status = 1,
	})

	count := model.get_comment_count_where(model.Comment_Where{
		wheres = fmt.tprintf("AND art_id = '%s'", item["id"]),
		status = 1,
	})
	new_count, _ := strconv.parse_int(count)

	pages := math.ceil(f64(new_count) / 10)

	comments := jinja.list()
	for item in comment_list {
		d := jinja.dict()
		jinja.set(d, "id", jinja.str(item["id"]))
		jinja.set(d, "content", jinja.str(item["content"]))
		jinja.set(d, "username", jinja.str(item["username"]))
		jinja.set(d, "add_time", jinja.str(item["add_time"]))
		jinja.set(d, "add_ip", jinja.str(item["add_ip"]))

		jinja.append_value(comments, d)
	}

	// cate info
	cate_info := model.get_cate(item["cate_id"])

	cate := get_cate(item["cate_id"])
	cates := get_cates()

	data := jinja.dict()
	jinja.set(data, "data", ctx)
	jinja.set(data, "cate", cate)
	jinja.set(data, "comments", comments)
	jinja.set(data, "cates", cates)

	output, err := view.render("index/art.html", data)
	if err != "" {
		view.return_text(b, err)
		return
	}

	view.return_html(b, output)
}

comment_create :: proc(b: ^gh.Bifrost) {
	art_id, ok := gh.query_param(b, "art_id")
	if !ok {
		view.return_error(b, "文章ID不能为空")
		return
	}

	fields := gh.form(b)

	content := fields["content"]
	if content == "" {
		view.return_error(b, "评论不能为空")
		return
	}

	data := make(map[string]string)
	data["art_id"] = art_id
	data["content"] = fields["content"]
	data["username"] = fields["username"]
	data["status"] = "1"

	if !model.add_comment(data) {
		view.return_error(b, "添加评论失败")
		return
	}

	view.return_success(b, "添加评论成功")
}

@(private)
get_cates :: proc() -> jinja.Value {
	cate_list := model.get_cate_all()

	cates := jinja.list()
	for item in cate_list {
		d := jinja.dict()
		jinja.set(d, "id", jinja.str(item["id"]))
		jinja.set(d, "name", jinja.str(item["name"]))
		jinja.set(d, "slug", jinja.str(item["slug"]))

		jinja.append_value(cates, d)
	}

	return cates
}

@(private)
get_cate :: proc(id: string) -> jinja.Value {
	cate := jinja.dict()
	
	cate_info := model.get_cate(id)
	if cate_info == nil {
		return cate
	}

	jinja.set(cate, "id", jinja.str(cate_info["id"]))
	jinja.set(cate, "name", jinja.str(cate_info["name"]))
	jinja.set(cate, "slug", jinja.str(cate_info["slug"]))
	jinja.set(cate, "desc", jinja.str(cate_info["desc"]))
	jinja.set(cate, "sort", jinja.str(cate_info["sort"]))
	jinja.set(cate, "status", jinja.str(cate_info["status"]))

	return cate
}
